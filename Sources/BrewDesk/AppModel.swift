import SwiftUI
import AppKit

struct PendingOperation: Identifiable {
    let id = UUID()
    let action: BrewAction
    let packages: [BrewPackage]
    let environment: BrewEnvironment
}
@MainActor final class AppModel: ObservableObject {
    @Published var environments: [BrewEnvironment] = []
    @Published var environment: BrewEnvironment?
    @Published var packages: [BrewPackage] = []
    @Published var selection = Set<String>()
    @Published var section = "installed"
    @Published var language = AppLanguage.saved() { didSet { UserDefaults.standard.set(language.rawValue, forKey: AppLanguage.preferenceKey) } }
    @Published var search = ""
    @Published var kind = "all"
    @Published var sort = "name"
    @Published var loading = false
    @Published var busy = false
    @Published var statusMessage = M("Homebrew를 찾는 중")
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
    func start() async {
        guard !booted else { return }; booted = true
        do { history = try historyStore.load() } catch { self.error = L("작업 기록을 읽지 못했습니다: \(error.localizedDescription)") }
        loading = true
        var candidates = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        if let custom = UserDefaults.standard.string(forKey: "brewPath"), !candidates.contains(custom) { candidates.append(custom) }
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            do { environments.append(try await repository.resolve(path)) }
            catch { self.error = error.localizedDescription }
        }
        loading = false
        if let saved = UserDefaults.standard.string(forKey: "brewPath"), let found = environments.first(where: { $0.executable == saved }) { await connect(found) }
        else if environments.count == 1 { await connect(environments[0]) }
        else { statusMessage = environments.isEmpty ? M("Homebrew를 찾지 못했습니다") : M("사용할 Homebrew 환경을 선택하세요"); section = "settings" }
    }
    func connect(_ env: BrewEnvironment) async {
        guard !unavailable else { return }
        environment = env; packages = []; selection = []; paths = []; dependents = []; lastChecked = nil; lastLoaded = nil
        UserDefaults.standard.set(env.executable, forKey: "brewPath")
        section = "installed"
        await refresh()
    }
    func chooseExecutable() {
        guard !unavailable else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.canChooseFiles = true
        panel.message = L("신뢰할 수 있는 Homebrew 실행 파일(brew)을 선택하세요. 선택한 파일을 실행해 버전을 확인합니다.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loading = true
        Task {
            do {
                let env = try await repository.resolve(url.path)
                if !environments.contains(env) { environments.append(env) }
                loading = false; await connect(env)
            } catch { loading = false; self.error = error.localizedDescription }
        }
    }
    func refresh() async {
        guard !unavailable, let env = environment else { return }
        loading = true; statusMessage = M("설치 상태 조회 중")
        do {
            packages = try await repository.installed(env)
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
        let targets: [BrewPackage?] = request.action == .update ? [nil] : request.packages.map(Optional.some)
        for (index, target) in targets.enumerated() {
            if cancelled { break }
            queueRemaining = targets.count - index - 1
            statusMessage = M("실행 전 상태 확인 · \(target?.name ?? L("업데이트 확인"))")
            do {
                let before = try await repository.installed(request.environment)
                if let target {
                    guard before.contains(where: { $0.id == target.id && $0.installed == target.installed }) else { throw BrewError.message(L("\(target.name)의 설치 상태가 바뀌었습니다. 목록을 새로고침하고 다시 선택하세요.")) }
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
                    let after = try await repository.installed(request.environment)
                    changes = VersionChange.between(before, after)
                    packages = after; lastLoaded = Date()
                    selection.formIntersection(Set(after.map(\.id)))
                    if request.action == .uninstall, let target, exitCode == 0, after.contains(where: { $0.id == target.id }) { verificationFailed = true; result = M("검증 실패 · 대상이 아직 설치되어 있음") }
                    if request.action == .upgrade, let target, exitCode == 0, after.first(where: { $0.id == target.id })?.outdated != false { verificationFailed = true; result = M("검증 필요 · 업데이트 상태 미해결") }
                    if request.action == .update, exitCode == 0 {
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
    func cancel() { cancelled = true; statusMessage = M("중단 요청 중 · 종료 후 실제 상태를 확인합니다"); runner.interrupt() }
    func copyLog(_ text: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
    func saveLog(_ text: String) {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "BrewDesk-log.txt"
        if panel.runModal() == .OK, let url = panel.url {
            do { try text.write(to: url, atomically: true, encoding: .utf8) } catch { self.error = error.localizedDescription }
        }
    }
}
