import XCTest
import AppKit
import Darwin
@testable import BrewDesk

final class TerminalConfirmationTests: XCTestCase {
    func testSplitANSIAndFullWordPrompt() {
        var detector = TerminalConfirmationDetector()
        detector.append("Preparing\n\u{1B}[32mContinue? [Y/")
        XCTAssertNil(detector.confirmation)
        detector.append("n]\u{1B}[0m ")
        XCTAssertEqual(detector.confirmation?.response(yes: false), "n\n")
        detector.reset()
        detector.append("Proceed (yes/no): ")
        XCTAssertEqual(detector.confirmation?.response(yes: true), "yes\n")
    }
    func testDoesNotOfferPasswordOrCompletedOutput() {
        for text in ["Password: ", "Continue [y/n]\nDone\n", "Press RETURN to continue", "https://example.com/y/n", "Continue [y/n] y"] {
            var detector = TerminalConfirmationDetector(); detector.append(text)
            XCTAssertNil(detector.confirmation, text)
        }
    }
    @MainActor func testPopupAnswersReachPTYAndStaleAnswerIsIgnored() async {
        _ = NSApplication.shared
        let runner = PTYRunner()
        let task = Task { await runner.run(BrewCommand(executable: "/bin/sh", arguments: ["-c", "printf 'Continue [y/n]: '; read answer; [ \"$answer\" = y ] || exit 4; printf 'Again (yes/no): '; read answer; [ \"$answer\" = no ]"])) }
        for _ in 0..<100 { if runner.confirmation != nil { break }; try? await Task.sleep(nanoseconds: 20_000_000) }
        guard let first = runner.confirmation else { runner.interrupt(); _ = await task.value; return XCTFail("First prompt missing") }
        runner.answer(first, yes: true)
        for _ in 0..<100 { if runner.confirmation != nil { break }; try? await Task.sleep(nanoseconds: 20_000_000) }
        guard let second = runner.confirmation else { runner.interrupt(); _ = await task.value; return XCTFail("Second prompt missing") }
        runner.answer(first, yes: true)
        XCTAssertEqual(runner.confirmation?.id, second.id)
        runner.answer(second, yes: false)
        let code = await task.value
        XCTAssertEqual(code, 0)
        XCTAssertNil(runner.confirmation)
    }
    @MainActor func testPromptAfterSecretInputDoesNotResumeLogging() async {
        _ = NSApplication.shared
        let runner = PTYRunner()
        let task = Task { await runner.run(BrewCommand(executable: "/bin/sh", arguments: ["-c", "stty -echo; printf 'Password: '; read password; stty echo; printf '\\nContinue [y/n]: '; read answer; [ \"$answer\" = n ]"])) }
        for _ in 0..<100 { var state = termios(); if runner.terminal.process.running && tcgetattr(runner.terminal.process.childfd, &state) == 0 && state.c_lflag & tcflag_t(ECHO) == 0 { break }; try? await Task.sleep(nanoseconds: 20_000_000) }
        try? await Task.sleep(nanoseconds: 200_000_000)
        runner.terminal.send(source: runner.terminal, data: Array("test-secret\n".utf8)[...])
        for _ in 0..<100 { if runner.confirmation != nil { break }; try? await Task.sleep(nanoseconds: 20_000_000) }
        guard let request = runner.confirmation else { runner.interrupt(); _ = await task.value; return XCTFail("Post-authentication prompt missing") }
        XCTAssertFalse(runner.log.contains("Continue"))
        XCTAssertFalse(runner.log.contains("test-secret"))
        runner.answer(request, yes: false)
        let code = await task.value
        XCTAssertEqual(code, 0)
    }

}
