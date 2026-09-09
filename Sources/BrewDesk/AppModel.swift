import SwiftUI
import AppKit

struct PendingOperation: Identifiable {
    let id = UUID()
    let action: BrewAction
    let packages: [BrewPackage]
    let environment: BrewEnvironment
}
@MainActor final class AppModel: ObservableObject {
    @Published var executableManager: PackageManager = .homebrew
    @Published var environments: [BrewEnvironment] = []
    @Published var environment: BrewEnvironment?
    @Published var packages: [BrewPackage] = []
    @Published var selection = Set<String>()
    @Published var section = "installed"
    @Published var language = AppLanguage.saved() { didSet { UserDefaults.standard.set(language.rawValue, forKey: AppLanguage.preferenceKey) } }
    @Published var search = ""
    @Published var kind = "all"
    @Published var sort = "name"
    @Published var catalogQuery = ""
    @Published var catalogKind: PackageKind? = nil
    @Published var catalogResults: [CatalogEntry] = []
    @Published var catalogPackage: BrewPackage?
    @Published var catalogLoading = false
    @Published var catalogError: String?
    @Published var catalogSearched = false
    private var catalogRequest = UUID()
    @Published var loading = false
    @Published var busy = false
    @Published var statusMessage = M("패키지 관리자를 찾는 중")
    var status: String { statusMessage.rendered() }
    @Published var error: String?
    @Published var lastLoaded: Date?
    @Published var lastChecked: Date?
    @Published var pending: PendingOperation?
    @Published var history: [OperationRecord] = []
    @Published var paths: [String] = []
    @Published var dependents: [String] = []
    @Published var detailLoading = false
    @Published var consoleExpanded = true
    @Published var queueRemaining = 0
    @Published var cancelled = false
    @Published var operationStarted: Date?
    let runner = PTYRunner()
    let repository = BrewRepository()
    let historyStore: OperationHistoryStore
    init(historyStore: OperationHistoryStore = OperationHistoryStore()) { self.historyStore = historyStore }
    private var booted = false
    private var detailRequest = UUID()
    var visible: [BrewPackage] {
        packages.filter { (section != "updates" || $0.outdated) && (kind == "all" || $0.kind.rawValue == kind) && (search.isEmpty || "\($0.name) \($0.token) \($0.summary)".localizedCaseInsensitiveContains(search)) }.sorted {
            if sort == "updates", $0.outdated != $1.outdated { return $0.outdated }
            if sort == "kind", $0.kind != $1.kind { return $0.kind.rawValue < $1.kind.rawValue }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
    var selected: [BrewPackage] { packages.filter { selection.contains($0.id) } }
    var upgradeable: [BrewPackage] { packages.filter { $0.outdated && !$0.pinned } }
    func selectAllVisible() { selection.formUnion(visible.map(\.id)) }
    func clearSelection() { selection.removeAll() }
    func setSelected(_ id: String, selected: Bool) {
        if selected { selection.insert(id) } else { selection.remove(id) }
    }
    func prepareAllUpgrades() {
        guard !unavailable, let env = environment, !upgradeable.isEmpty else { return }
        pending = PendingOperation(action: .upgrade, packages: upgradeable, environment: env)
    }
    var focused: BrewPackage? { selected.count == 1 ? selected.first : nil }
    var unavailable: Bool { busy || loading }
    func resetCatalog() {
        catalogRequest = UUID(); catalogResults = []; catalogPackage = nil
        catalogLoading = false; catalogError = nil; catalogSearched = false
    }
    func searchCatalog() async {
        guard !unavailable, let env = environment else { return }
        let request = UUID(); catalogRequest = request
        let query = catalogQuery, kind = catalogKind
        catalogLoading = true; catalogPackage = nil; catalogResults = []; catalogError = nil; catalogSearched = true
        do {
            let results = try await repository.search(query, kind: kind, environment: env)
            guard catalogRequest == request, environment == env else { return }
            catalogResults = results
        } catch {
            guard catalogRequest == request, environment == env else { return }
            catalogError = error.localizedDescription
        }
        if catalogRequest == request { catalogLoading = false }
    }
    func inspectCatalog(_ entry: CatalogEntry) async {
        guard !unavailable, let env = environment else { return }
        let request = UUID(); catalogRequest = request
        catalogPackage = nil; catalogLoading = true; catalogError = nil
        do {
            let package = try await repository.catalogInfo(entry, environment: env)
            guard catalogRequest == request, environment == env else { return }
            catalogPackage = package
        } catch {
            guard catalogRequest == request, environment == env else { return }
            catalogError = error.localizedDescription
        }
        if catalogRequest == request { catalogLoading = false }
    }
    func prepareInstall() {
        guard !unavailable, !catalogLoading, let env = environment, let package = catalogPackage,
              package.installed.isEmpty, !packages.contains(where: { $0.id == package.id }) else { return }
        pending = PendingOperation(action: .install, packages: [package], environment: env)
    }
    func start() async {
        guard !booted else { return }; booted = true
        do { history = try historyStore.load() } catch { self.error = L("작업 기록을 읽지 못했습니다: \(error.localizedDescription)") }
        loading = true
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let directories = ["/opt/homebrew/bin", "/usr/local/bin", home + "/.local/bin", home + "/.cargo/bin", "/usr/bin"] + (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        for manager in PackageManager.allCases {
            var candidates = directories.filter { $0.hasPrefix("/") }.map { $0 + "/" + manager.executableName }
            if let custom = UserDefaults.standard.string(forKey: "executable.\(manager.rawValue)") { candidates.insert(custom, at: 0) }
            if manager == .homebrew, let custom = UserDefaults.standard.string(forKey: "brewPath") { candidates.insert(custom, at: 0) }
            var seen = Set<String>()
            for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
                // Keep the original executable path (not the symlink target): Cargo may be a rustup proxy.
                let canonical = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
                guard seen.insert(canonical).inserted else { continue }
                do { environments.append(try await repository.resolve(path, manager: manager)) }
                catch { /* Other valid environments remain available. Custom files can be retried in Settings. */ }
            }
        }
        loading = false
        let saved = UserDefaults.standard.string(forKey: "environmentPath") ?? UserDefaults.standard.string(forKey: "brewPath")
        if let found = environments.first(where: { $0.executable == saved }) { await connect(found) }
        else if let first = environments.first { await connect(first) }
        else { statusMessage = M("패키지 관리자를 찾지 못했습니다"); section = "settings" }
    }
    func connect(_ env: BrewEnvironment) async {
        guard !unavailable else { return }
        resetCatalog(); kind = "all"; catalogKind = nil; search = ""; pending = nil
        environment = env; packages = []; selection = []; paths = []; dependents = []; lastChecked = nil; lastLoaded = nil
        UserDefaults.standard.set(env.executable, forKey: "environmentPath")
        UserDefaults.standard.set(env.executable, forKey: "executable.\(env.manager.rawValue)")
        section = "installed"
        await refresh()
    }
    func chooseExecutable() {
        guard !unavailable else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.canChooseFiles = true
        panel.message = L("선택한 패키지 관리자의 신뢰할 수 있는 실행 파일을 지정하세요. 버전과 환경을 확인하기 위해 실행합니다.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let manager = executableManager
        loading = true
        Task {
            do {
                let env = try await repository.resolve(url.path, manager: manager)
                if !environments.contains(env) { environments.append(env) }
                loading = false; await connect(env)
            } catch { loading = false; self.error = error.localizedDescription }
        }
    }
    func refresh() async {
        guard !unavailable, let env = environment else { return }
        loading = true; statusMessage = M("설치 상태 조회 중")
        do {
            packages = try await repository.installed(env, checkingUpdates: lastChecked != nil)
            selection.formIntersection(Set(packages.map(\.id)))
            lastLoaded = Date(); statusMessage = M("\(packages.count)개 패키지 · 설치 상태 확인됨")
        } catch { self.error = error.localizedDescription; statusMessage = M("조회 실패 · 기존 목록 유지") }
        loading = false
    }
    func loadDetails() async {
        let request = UUID(); detailRequest = request
        paths = []; dependents = []; detailLoading = false
        guard let p = focused, let env = environment, !busy else { return }
        detailLoading = true
        defer { if detailRequest == request { detailLoading = false } }
        do {
            let foundPaths = try await repository.paths(p, environment: env)
            let users = try await repository.dependents(p, environment: env)
            guard detailRequest == request, focused?.id == p.id, environment == env, !busy else { return }
            paths = foundPaths; dependents = users
        } catch { if detailRequest == request, focused?.id == p.id { self.error = error.localizedDescription } }
    }
    func prepare(_ action: BrewAction) {
        guard !unavailable, let env = environment else { return }
        let targets = action == .update ? [] : selected.filter { action != .upgrade || ($0.outdated && !$0.pinned) }
        guard action == .update || !targets.isEmpty else { return }
        pending = PendingOperation(action: action, packages: targets, environment: env)
    }
    func execute(_ request: PendingOperation) async {
        guard !unavailable, request.environment == environment else { return }
        busy = true; operationStarted = Date(); cancelled = false; consoleExpanded = true; pending = nil
        defer { busy = false; operationStarted = nil; queueRemaining = 0 }
        if request.action == .update, request.environment.manager != .homebrew {
            await checkManagerUpdates(request.environment)
            return
        }
        let targets: [BrewPackage?] = request.action == .update ? [nil] : request.packages.map(Optional.some)
        for (index, target) in targets.enumerated() {
            if cancelled { break }
            queueRemaining = targets.count - index - 1
            statusMessage = M("실행 전 상태 확인 · \(target?.name ?? L("업데이트 확인"))")
            do {
                if request.environment.manager != .homebrew {
                    let resolved = try await repository.resolve(request.environment.executable, manager: request.environment.manager)
                    guard resolved.prefix == request.environment.prefix else { throw BrewError.message(L("설치 환경이 바뀌었습니다. 다시 연결하세요.")) }
                }
                let before = try await repository.installed(request.environment)
                if let target {
                    if request.action == .install {
                        guard !before.contains(where: { $0.id == target.id }) else { throw BrewError.message(L("이미 설치된 패키지입니다. 설치 목록에서 확인하세요.")) }
                    } else {
                    guard before.contains(where: { $0.id == target.id && $0.installed == target.installed }) else { throw BrewError.message(L("\(target.name)의 설치 상태가 바뀌었습니다. 목록을 새로고침하고 다시 선택하세요.")) }
                    }
                    if request.action == .uninstall {
                        let users = try await repository.dependents(target, environment: request.environment)
                        guard users.isEmpty else { throw BrewError.message(L("\(target.name)을 사용하는 설치 항목이 있어 제거하지 않았습니다: \(users.joined(separator: ", "))")) }
                    }
                }
                if cancelled { break }
                let command = try BrewCommandFactory.mutation(request.action, package: target, environment: request.environment)
                statusMessage = M("\(target?.name ?? L("Homebrew 정의")) 실행 중 · 필요한 입력은 콘솔에서 진행하세요")
                let exitCode = await runner.run(command)
                statusMessage = M("실제 변경 결과 확인 중")
                var changes: [VersionChange] = []
                var result = cancelled ? M("중단 요청됨 · 원상 복구 아님") : (exitCode == 0 ? M("명령 완료") : M("실패 (종료 코드 \(exitCode))"))
                var verificationFailed = false
                do {
                    let after = try await repository.installed(request.environment, checkingUpdates: request.action == .upgrade)
                    changes = VersionChange.between(before, after)
                    packages = after; lastLoaded = Date()
                    selection.formIntersection(Set(after.map(\.id)))
                    if request.action == .install, let target, exitCode == 0, !after.contains(where: { $0.id == target.id }) {
                        verificationFailed = true; result = M("검증 실패 · 설치된 대상을 찾지 못함")
                    }
                    if request.action == .uninstall, let target, exitCode == 0, after.contains(where: { $0.id == target.id }) { verificationFailed = true; result = M("검증 실패 · 대상이 아직 설치되어 있음") }
                    if request.action == .upgrade, let target, exitCode == 0, (after.first(where: { $0.id == target.id })?.outdated != false || (request.environment.manager != .homebrew && after.first(where: { $0.id == target.id })?.installed != target.available)) { verificationFailed = true; result = M("검증 필요 · 업데이트 상태 미해결") }
                    if request.action == .update, request.environment.manager == .homebrew, exitCode == 0 {
                        _ = try BrewJSON.outdatedIDs(await repository.query(request.environment, ["outdated", "--json=v2"]))
                        lastChecked = Date()
                    }
                } catch { verificationFailed = true; result += M(" · 결과 재조회 실패"); self.error = error.localizedDescription }
                let record = OperationRecord(id: UUID(), date: Date(), environment: request.environment.executable, command: command.display, exitCode: exitCode, result: result.rendered(), changes: changes, log: runner.log, localizedResult: result)
                history.insert(record, at: 0)
                do { try historyStore.save(history) } catch { self.error = L("기록 저장 실패: \(error.localizedDescription)") }
                statusMessage = result
                if exitCode != 0 || verificationFailed { break }
            } catch {
                self.error = error.localizedDescription; statusMessage = M("작업 시작 전 중단")
                let cmd = try? BrewCommandFactory.mutation(request.action, package: target, environment: request.environment)
                history.insert(OperationRecord(id: UUID(), date: Date(), environment: request.environment.executable, command: cmd?.display ?? request.action.rawValue, exitCode: -1, result: L("실행 전 차단: \(error.localizedDescription)"), changes: [], log: L("명령을 실행하지 않았습니다."), localizedResult: M("실행 전 차단: \(error.localizedDescription)")), at: 0)
                do { try historyStore.save(history) } catch { self.error = L("기록 저장 실패: \(error.localizedDescription)") }
                break
            }
        }
    }
    private func checkManagerUpdates(_ env: BrewEnvironment) async {
        statusMessage = M("업데이트 조회 중")
        runner.showReadResult(command: env.manager.title + ": " + L("업데이트 확인"), output: statusMessage.rendered())
        var result = M("업데이트 조회 완료"), exitCode: Int32 = 0
        do {
            let refreshed = try await repository.installed(env, checkingUpdates: true)
            if cancelled { statusMessage = M("중단 요청됨 · 원상 복구 아님"); return }
            packages = refreshed; lastLoaded = Date(); lastChecked = Date()
            selection.formIntersection(Set(packages.map(\.id)))
        } catch { self.error = error.localizedDescription; result = M("업데이트 조회에 실패했습니다."); exitCode = -1 }
        let record = OperationRecord(id: UUID(), date: Date(), environment: env.executable, command: "\(env.manager.title): \(L("업데이트 확인"))", exitCode: exitCode, result: result.rendered(), changes: [], log: exitCode == 0 ? packages.filter(\.outdated).map { "\($0.token): \($0.installed) → \($0.available)" }.joined(separator: "\n") : (error ?? ""), localizedResult: result)
        runner.showReadResult(command: record.command, output: result.rendered() + "\n" + record.log)
        history.insert(record, at: 0)
        do { try historyStore.save(history) } catch { self.error = error.localizedDescription }
        statusMessage = result
    }
    func cancel() { cancelled = true; statusMessage = M("중단 요청 중 · 종료 후 실제 상태를 확인합니다"); runner.interrupt() }
    func copyLog(_ text: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
    func saveLog(_ text: String) {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "BrewDesk-log.txt"
        if panel.runModal() == .OK, let url = panel.url {
            do { try text.write(to: url, atomically: true, encoding: .utf8) } catch { self.error = error.localizedDescription }
        }
    }
}
