import AppKit
import SwiftUI
import SwiftTerm
import Darwin

final class BrewTerminalView: LocalProcessTerminalView {
    var outputHandler: ((String) -> Void)?
    var exitHandler: ((Int32) -> Void)?
    private var suppressRecording = false
    override func send(source: TerminalView, data: ArraySlice<UInt8>) {
        var state = termios()
        if tcgetattr(process.childfd, &state) != 0 || state.c_lflag & tcflag_t(ECHO) == 0 {
            // Never persist any output after a secret is entered, even if a child echoes it later.
            suppressRecording = true
        }
        super.send(source: source, data: data)
    }
    override func dataReceived(slice: ArraySlice<UInt8>) {
        super.dataReceived(slice: slice)
        var state = termios()
        let readableState = tcgetattr(process.childfd, &state) == 0
        if !suppressRecording, !readableState || state.c_lflag & tcflag_t(ECHO) != 0 {
            outputHandler?(String(decoding: slice, as: UTF8.self))
        }
    }
    override func processTerminated(_ source: LocalProcess, exitCode: Int32?) {
        // SwiftTerm 1.20.0 forkpty backend returns waitpid status, not a decoded exit code.
        let raw = exitCode ?? -1
        let status: Int32 = raw < 0 ? -1 : (raw & 0x7f == 0 ? (raw >> 8) & 0xff : 128 + (raw & 0x7f))
        exitHandler?(status)
        exitHandler = nil
    }
}
@MainActor final class PTYRunner: ObservableObject {
    @Published var terminal = BrewTerminalView(frame: NSRect(x: 0, y: 0, width: 1000, height: 230))
    @Published var log = ""
    @Published var command = ""
    func run(_ command: BrewCommand) async -> Int32 {
        self.command = command.display; log = ""
        let view = BrewTerminalView(frame: NSRect(x: 0, y: 0, width: 1000, height: 230))
        view.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        terminal = view
        view.outputHandler = { [weak self] text in
            self?.log.append(text)
            if let count = self?.log.count, count > 250_000 { self?.log.removeFirst(count - 250_000) }
        }
        var environment = ProcessRunner.environment(for: command.executable)
        environment["TERM"] = "xterm-256color"
        let status: Int32 = await withCheckedContinuation { continuation in
            view.exitHandler = { status in continuation.resume(returning: status) }
            view.startProcess(executable: command.executable, args: command.arguments, environment: environment.map { "\($0.key)=\($0.value)" })
            // A short-lived child can reach EOF before startProcess returns. PID, not running, proves launch.
            if view.process.shellPid <= 0 { view.exitHandler?(-1); view.exitHandler = nil }
        }
        // Reaping and PTY EOF are separate events. Let trailing output reach the view.
        for _ in 0..<200 {
            if view.process.childfd < 0 { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        await Task.yield()
        if view.process.childfd >= 0 { log += L("\n[출력 스트림 종료 미확인: 기록이 일부 생략될 수 있습니다.]\n") }
        return status
    }
    func interrupt() {
        guard terminal.process.running else { return }
        // Terminal interrupt reaches the foreground process group, including child installers.
        terminal.process.send(data: [3][...])
    }
}
struct TerminalHost: NSViewRepresentable {
    let view: BrewTerminalView
    func makeNSView(context: Context) -> BrewTerminalView { view }
    func updateNSView(_ nsView: BrewTerminalView, context: Context) {}
}
