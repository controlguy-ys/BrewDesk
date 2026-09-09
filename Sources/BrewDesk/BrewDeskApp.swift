import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model?.busy == true else { return .terminateNow }
        let alert = NSAlert(); alert.messageText = L("Homebrew 작업이 진행 중입니다")
        alert.informativeText = L("작업이 끝날 때까지 기다리거나 콘솔에서 중단을 요청한 뒤 종료하세요. 중단은 변경 사항을 되돌리지 않습니다.")
        alert.addButton(withTitle: L("앱으로 돌아가기")); alert.runModal()
        return .terminateCancel
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
@main struct BrewDeskApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel()
    var body: some Scene {
        Window("BrewDesk", id: "main") {
            ContentView(model: model)
                .frame(minWidth: 1080, minHeight: 720)
                .environment(\.locale, model.language.locale)
                .task { delegate.model = model; await model.start() }
        }
        .defaultSize(width: 1320, height: 880)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .pasteboard) {
                Button(L("전체 선택")) {
                    NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                }.keyboardShortcut("a", modifiers: .command)
            }
            CommandGroup(after: .toolbar) {
                Button(L("설치 목록 새로고침")) { Task { await model.refresh() } }.keyboardShortcut("r").disabled(model.unavailable)
                Button(L("업데이트 확인…")) { model.prepare(.update) }.disabled(model.unavailable || model.environment == nil)
            }
        }
    }
}
struct ContentView: View {
    @ObservedObject var model: AppModel
    private let sections = [("installed", "설치됨", "square.stack.3d.up"), ("updates", "업데이트", "arrow.down.circle"), ("install", "패키지 설치", "plus.app"), ("history", "작업 기록", "clock.arrow.circlepath"), ("settings", "설정", "slider.horizontal.3")]
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 10) {
                    Image(systemName: "shippingbox.fill").font(.title).foregroundStyle(.orange)
                    VStack(alignment: .leading) { Text("BrewDesk").font(.title3.bold()); Text("YOUR MAC, IN ORDER").font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundStyle(.secondary) }
                }.padding(.horizontal, 18).padding(.top, 20)
                VStack(spacing: 6) {
                    ForEach(sections, id: \.0) { id, title, symbol in
                        Button { model.section = id; model.selection = [] } label: {
                            HStack { Image(systemName: symbol).frame(width: 20); Text(L(LocalizedMessage(key: title))); Spacer(); if id == "updates" { Text("\(model.packages.filter(\.outdated).count)").font(.caption.monospacedDigit()) } }
                                .padding(10).contentShape(Rectangle())
                                .background(model.section == id ? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain)
                    }
                }.padding(.horizontal, 10)
                Spacer()
                VStack(alignment: .leading, spacing: 8) {
                    Label(model.environment == nil ? L("연결 대기") : L("Homebrew 연결됨"), systemImage: "circle.fill").font(.caption).foregroundStyle(model.environment == nil ? .secondary : Color.green)
                    Text(model.environment?.prefix ?? L("환경을 선택하세요")).font(.caption.monospaced()).foregroundStyle(.secondary)
                    Text(L("변경 전 확인. 실행 후 검증.")).font(.caption2).foregroundStyle(.tertiary)
                }.padding(18)
            }
            .navigationSplitViewColumnWidth(210)
        } detail: {
            VStack(spacing: 0) {
                if model.section == "settings" { settings }
                else if model.section == "history" { history }
                else if model.section == "install" { InstallView(model: model) }
                else { library }
                Divider()
                console
            }
        }
        .background(WindowCloseGuard(model: model).frame(width: 0, height: 0))
        .navigationTitle("")
        .toolbar {
            ToolbarItemGroup {
                Button { model.prepare(.update) } label: { Text(L("업데이트 확인")) }
                    .disabled(model.unavailable || model.environment == nil)
                Button { model.prepareAllUpgrades() } label: { Text(L("패키지 업데이트 실행")) }
                    .disabled(model.unavailable || model.environment == nil || model.upgradeable.isEmpty)
            }
        }
        .sheet(item: $model.pending) { request in confirmation(request) }
        .alert(L("작업을 확인하세요"), isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button(L("확인")) { model.error = nil } } message: { Text(model.error ?? "") }
    }
    private var library: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.section == "updates" ? L("업데이트할 항목") : L("내 Mac의 패키지")).font(.system(size: 27, weight: .bold))
                    Text(model.section == "updates" ? L("변경할 항목을 직접 선택하세요.") : L("Homebrew로 설치한 앱과 개발 도구를 한곳에서.")).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) { Text("\(model.packages.count)").font(.system(size: 30, weight: .light, design: .rounded)); Text(L("설치된 패키지")).font(.caption).foregroundStyle(.secondary) }
            }.padding(24)
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(L("이름, 도구 또는 설명 검색"), text: $model.search).textFieldStyle(.plain)
                Picker(L("정렬"), selection: $model.sort) { Text(L("이름순")).tag("name"); Text(L("업데이트 우선")).tag("updates"); Text(L("유형순")).tag("kind") }.labelsHidden().frame(width: 130)
                Picker(L("유형"), selection: $model.kind) { Text(L("전체 유형")).tag("all"); ForEach(PackageKind.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) } }.labelsHidden().frame(width: 170)
            }.padding(10).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8)).padding(.horizontal, 24).padding(.bottom, 16)
            HStack {
                Text(L("\(model.visible.count)개 항목")).font(.caption).foregroundStyle(.secondary)
                if let date = model.lastLoaded { Text(L("· 조회 \(L10n.date(date, timeOnly: true))")).font(.caption).foregroundStyle(.tertiary) }
                Button(L("전체 선택")) { model.selectAllVisible() }.disabled(model.visible.isEmpty)
                    .help(L("현재 표시된 항목을 모두 선택합니다."))
                Button(L("선택 해제")) { model.clearSelection() }.disabled(model.selection.isEmpty)
                Text(L("\(model.selected.count)개 선택됨")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(L("전체 업데이트 \(model.upgradeable.count)개…")) { model.prepareAllUpgrades() }
                    .disabled(model.unavailable || model.environment == nil || model.upgradeable.isEmpty)
                    .help(L("검색·필터와 관계없이 업데이트 가능한 모든 항목을 확인합니다. 고정된 항목은 제외됩니다."))
                if !model.selected.isEmpty { Button(L("선택 \(model.selected.count)개 업데이트…")) { model.prepare(.upgrade) }.disabled(model.unavailable || !model.selected.contains(where: { $0.outdated && !$0.pinned })) }
            }.padding(.horizontal, 24).padding(.bottom, 10)
            Divider()
            HSplitView {
                Table(model.visible, selection: $model.selection) {
                    TableColumn(L("선택")) { p in
                        Toggle(L("\(p.name) 선택"), isOn: Binding(
                            get: { model.selection.contains(p.id) },
                            set: { model.setSelected(p.id, selected: $0) }
                        )).toggleStyle(.checkbox).labelsHidden()
                    }.width(56)
                    TableColumn(L("패키지")) { p in
                        HStack(spacing: 10) {
                            Image(systemName: p.kind.symbol).font(.title3).foregroundStyle(p.kind == .cask ? Color.orange : .blue).frame(width: 32, height: 32).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))
                            VStack(alignment: .leading, spacing: 3) { Text(p.name).fontWeight(.medium); Text(p.token).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                        }.padding(.vertical, 5)
                    }.width(min: 190, ideal: 245)
                    TableColumn(L("설치 버전")) { Text($0.installed.isEmpty ? L("확인되지 않음") : $0.installed).font(.system(.caption, design: .monospaced)).lineLimit(1) }.width(min: 90, ideal: 110)
                    TableColumn(L("상태")) { p in Text(p.status).font(.caption).foregroundStyle(p.outdated ? Color.orange : .secondary).lineLimit(2) }.width(min: 125, ideal: 155)
                }
                .overlay { if model.packages.isEmpty { ContentUnavailableView(model.loading ? L("설치 목록을 읽는 중") : L("표시할 패키지가 없습니다"), systemImage: "shippingbox", description: Text(model.environment == nil ? L("설정에서 Homebrew를 연결하세요.") : L("목록을 새로고침해 설치 상태를 확인하세요."))) } }
                .frame(minWidth: 430)
                detail.frame(minWidth: 270, idealWidth: 310, maxWidth: 380)
            }
        }
    }
    private var detail: some View {
        ScrollView {
            if let p = model.focused {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: p.kind.symbol).font(.system(size: 32)).foregroundStyle(.orange).frame(width: 60, height: 60).background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 5) { Text(p.name).font(.title2.bold()); Text(p.kind.title).font(.caption).foregroundStyle(.secondary); Text(p.summary.isEmpty ? L("설명 없음") : p.summary).padding(.top, 6).textSelection(.enabled) }
                    Divider()
                    info(L("설치 버전"), p.installed); info(L("Homebrew 제공 버전"), p.available); info(L("저장소"), p.tap)
                    if p.autoUpdates || p.available == "latest" { Text(L("자체 업데이트 항목은 기본 업데이트 조회에서 제외될 수 있습니다.")).font(.caption).foregroundStyle(.orange) }
                    HStack { Button(L("업데이트…")) { model.prepare(.upgrade) }.buttonStyle(.borderedProminent).disabled(model.unavailable || !p.outdated || p.pinned); Button(L("제거…"), role: .destructive) { model.prepare(.uninstall) }.disabled(model.unavailable) }
                    if let url = URL(string: p.homepage), ["https", "http"].contains(url.scheme ?? "") { Link(destination: url) { Label(L("홈페이지"), systemImage: "arrow.up.right.square") } }
                    Divider()
                    info(L("필요한 패키지"), p.dependencies.isEmpty ? L("없음 / 제공 정보 없음") : p.dependencies.joined(separator: ", "))
                    info(L("사용하는 설치 항목"), model.detailLoading ? L("확인 중…") : (model.dependents.isEmpty ? L("조회된 항목 없음") : model.dependents.joined(separator: ", ")))
                    info(L("확인된 설치 경로"), model.detailLoading ? L("확인 중…") : model.paths.first ?? L("확인되지 않음"))
                    if let path = model.paths.first { Button(L("Finder에서 보기")) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) } }
                    if let path = model.paths.first(where: { $0.hasSuffix(".app") || $0.hasSuffix(".app/") }) { Button(L("앱 열기")) { NSWorkspace.shared.open(URL(fileURLWithPath: path)) } }
                }.padding(22)
            } else { ContentUnavailableView(model.selected.isEmpty ? L("패키지를 선택하세요") : L("\(model.selected.count)개 선택됨"), systemImage: "sidebar.right", description: Text(L("설치 정보와 변경할 내용을 여기서 확인합니다."))).padding(.top, 50) }
        }.background(.background.opacity(0.5)).task(id: DetailIdentity(package: model.focused?.id, refreshed: model.lastLoaded, busy: model.busy)) { await model.loadDetails() }
    }
    private func info(_ title: String, _ value: String) -> some View { VStack(alignment: .leading, spacing: 5) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value.isEmpty ? L("확인되지 않음") : value).font(.callout).textSelection(.enabled) } }
    private var settings: some View {
        Form {
            Section(L("언어")) {
                Picker(L("앱 언어"), selection: $model.language) {
                    ForEach(AppLanguage.allCases) { language in Text(language.title).tag(language) }
                }
                Text(L("언어 변경은 즉시 적용되며 다음 실행에도 유지됩니다."))
                Text(L("Homebrew 설명과 콘솔 원문은 번역하지 않습니다.")).foregroundStyle(.secondary)
            }
            Section(L("Homebrew 환경")) {
                Text(L("환경별 설치 목록을 분리합니다. 연결 시 업데이트나 재설치를 실행하지 않습니다."))
                ForEach(model.environments) { env in
                    HStack { VStack(alignment: .leading) { Text(env.version); Text(env.executable).font(.caption.monospaced()) }; Spacer(); Button(model.environment == env ? L("연결됨") : L("선택")) { Task { await model.connect(env) } }.disabled(model.unavailable || model.environment == env) }
                }
                Button(L("Homebrew 실행 파일 지정…")) { model.chooseExecutable() }.disabled(model.unavailable)
                Link(L("Homebrew 공식 설치 안내"), destination: URL(string: "https://brew.sh")!)
            }
            Section(L("업데이트 확인")) {
                Text(model.lastChecked.map { L("정의 갱신 및 조회: \(L10n.date($0))") } ?? L("이 실행에서 아직 업데이트를 확인하지 않았습니다."))
                Text(L("목록 새로고침은 현재 정의로 상태를 조회합니다. 업데이트 확인은 brew update를 실행합니다.")).foregroundStyle(.secondary)
            }
            Section(L("작업과 기록")) {
                Text(L("변경은 한 번에 하나씩 실행하며, 실패하면 남은 대기열을 멈춥니다. 제거는 일반 uninstall만 사용합니다."))
                Text(L("인증은 콘솔에서 진행합니다. 비밀 입력 이후 출력은 기록에서 제외됩니다. 기록은 이 Mac에 최대 200개 저장됩니다."))
                Text(L("공개 배포용 서명·공증 전의 로컬 개발 빌드입니다.")).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
    private var history: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(L("작업 기록")).font(.largeTitle.bold())
                Text(L("명령의 결과와 실제로 관찰된 변경 사항을 확인하세요.")).foregroundStyle(.secondary)
                if model.history.isEmpty { ContentUnavailableView(L("아직 작업 기록이 없습니다"), systemImage: "clock", description: Text(L("업데이트 확인, 선택 업데이트, 제거 결과가 여기에 남습니다."))) }
                ForEach(model.history) { record in
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(record.environment).font(.caption.monospaced())
                            Text(record.command).font(.caption.monospaced()).textSelection(.enabled)
                            ForEach(record.changes) { change in Text("\(change.package): \(change.before ?? L("없음")) → \(change.after ?? L("제거됨"))").font(.callout) }
                            if record.changes.isEmpty { Text(L("관찰된 버전 변화 없음")).foregroundStyle(.secondary) }
                            HStack { Button(L("로그 복사")) { model.copyLog(record.log) }; Button(L("로그 저장…")) { model.saveLog(record.log) } }
                            Text(record.log.isEmpty ? L("저장된 출력 없음") : record.log).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        }.padding(.top, 12)
                    } label: { VStack(alignment: .leading, spacing: 4) { Text(record.displayResult).fontWeight(.semibold); Text(L10n.date(record.date)).font(.caption).foregroundStyle(.secondary) } }.disclosureGroupStyle(HistoryDisclosureStyle()).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
                }
            }.padding(28).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private var console: some View { ConsolePanel(model: model, runner: model.runner) }
    private func confirmation(_ request: PendingOperation) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(request.action == .uninstall ? L("제거할 항목 확인") : request.action == .update ? L("업데이트 확인") : request.action == .install ? L("설치할 항목 확인") : L("업데이트할 항목 확인"), systemImage: request.action == .uninstall ? "trash" : "arrow.down.circle").font(.title2.bold())
            Text(request.environment.executable).font(.caption.monospaced()).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if request.action == .update { Text(L("Homebrew와 패키지 정의를 갱신한 뒤 업데이트 대상을 조회합니다. 설치된 패키지의 업그레이드는 별도 선택합니다.")) }
                    ForEach(request.packages) { p in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(p.name).bold(); Text(request.action == .upgrade ? "\(p.installed) → \(p.available)" : request.action == .install ? L("설치할 버전 \(p.available)") : L("설치 버전 \(p.installed)"))
                            if let cmd = try? BrewCommandFactory.mutation(request.action, package: p, environment: request.environment) { Text(cmd.display).font(.caption.monospaced()).foregroundStyle(.secondary) }
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: 240)
            Text(request.action == .uninstall ? L("설정·캐시 정리(--zap)와 강제 제거는 사용하지 않습니다. 사용 중인 Formula는 제거를 차단합니다. Cask에 포함된 제거 스크립트가 실행될 수 있습니다.") : L("의존 패키지 등 추가 변경이 발생할 수 있습니다. 실제 변경은 실행 후 기록됩니다.")).font(.callout).foregroundStyle(.secondary)
            HStack { Spacer(); Button(L("취소")) { model.pending = nil }.keyboardShortcut(.cancelAction); Button(request.action == .uninstall ? L("제거 실행") : request.action == .install ? L("설치 실행") : L("실행")) { Task { await model.execute(request) } }.buttonStyle(.borderedProminent) }
        }.padding(28).frame(width: 540)
    }
}
/// Keeps the whole summary row clickable without intercepting log selection or buttons.
struct HistoryDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation { configuration.isExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: configuration.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    configuration.label
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(configuration.isExpanded ? L("펼쳐짐") : L("접힘"))
            if configuration.isExpanded {
                configuration.content.padding(.horizontal, 16).padding(.bottom, 16)
            }
        }
    }
}

struct ConsolePanel: View {
    @ObservedObject var model: AppModel
    @ObservedObject var runner: PTYRunner
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { model.consoleExpanded.toggle() } label: { Image(systemName: model.consoleExpanded ? "chevron.down" : "chevron.up") }.buttonStyle(.plain)
                if model.busy || model.loading { ProgressView().controlSize(.small) } else { Image(systemName: "terminal").foregroundStyle(.secondary) }
                Text(model.status).font(.caption).lineLimit(1)
                Spacer()
                if let started = model.operationStarted {
                    TimelineView(.periodic(from: started, by: 1)) { context in
                        Text(L("\(Int(context.date.timeIntervalSince(started)))초")).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                if model.queueRemaining > 0 { Text(L("대기 \(model.queueRemaining)개")).font(.caption) }
                if model.busy { Button(L("중단 요청"), role: .destructive) { model.cancel() }.disabled(model.cancelled) }
                Button { model.copyLog(runner.command + "\n" + runner.log) } label: { Image(systemName: "doc.on.doc") }.help(L("로그 복사"))
                Button { model.saveLog(runner.command + "\n" + runner.log) } label: { Image(systemName: "square.and.arrow.down") }.help(L("로그 저장"))
            }.padding(12)
            if model.consoleExpanded {
                Text(runner.command.isEmpty ? L("아직 실행한 작업이 없습니다.") : runner.command).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).padding(.bottom, 8)
                TerminalHost(view: runner.terminal).id(ObjectIdentifier(runner.terminal)).frame(height: 170)
                if model.busy { Text(L("인증 또는 확인 입력이 필요하면 위 콘솔을 클릭하세요. 중단은 원상 복구가 아닙니다.")).font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(6) }
            }
        }.background(.bar)
        .alert(L("터미널 확인 요청"), isPresented: Binding(
            get: { runner.confirmation != nil },
            set: { _ in }
        ), presenting: runner.confirmation) { request in
            Button(L("예")) { runner.answer(request, yes: true) }
            Button(L("아니요"), role: .cancel) { runner.answer(request, yes: false) }
            Button(L("터미널에서 응답")) { runner.useTerminal() }
        } message: { request in
            Text(request.question + "\n\n" + L("실행 중인 명령의 질문입니다. 응답은 터미널로 전달됩니다."))
        }
    }
}


// Keep the active console reachable when the user clicks the red window button.
struct WindowCloseGuard: NSViewRepresentable {
    let model: AppModel
    final class Probe: NSView {
        var install: ((NSWindow) -> Void)?
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); if let window { install?(window) } }
    }
    final class Coordinator: NSObject, NSWindowDelegate {
        let model: AppModel
        weak var previous: NSWindowDelegate?
        init(model: AppModel) { self.model = model }
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            if model.busy {
                let alert = NSAlert()
                alert.messageText = L("진행 중인 작업이 있습니다")
                alert.informativeText = L("콘솔에서 작업을 마치거나 중단 처리가 끝난 뒤 창을 닫으세요.")
                alert.addButton(withTitle: L("돌아가기"))
                alert.beginSheetModal(for: sender)
                return false
            }
            return previous?.windowShouldClose?(sender) ?? true
        }
        override func responds(to selector: Selector!) -> Bool { super.responds(to: selector) || previous?.responds(to: selector) == true }
        override func forwardingTarget(for selector: Selector!) -> Any? { previous?.responds(to: selector) == true ? previous : super.forwardingTarget(for: selector) }
    }
    func makeCoordinator() -> Coordinator { Coordinator(model: model) }
    func makeNSView(context: Context) -> Probe {
        let probe = Probe()
        probe.install = { [weak coordinator = context.coordinator] window in
            guard let coordinator, window.delegate !== coordinator else { return }
            coordinator.previous = window.delegate
            window.delegate = coordinator
        }
        return probe
    }
    func updateNSView(_ view: Probe, context: Context) {}
}

private struct DetailIdentity: Hashable { let package: String?; let refreshed: Date?; let busy: Bool }
