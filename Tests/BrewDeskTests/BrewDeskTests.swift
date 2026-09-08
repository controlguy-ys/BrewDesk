import XCTest
import AppKit
import Darwin
@testable import BrewDesk

final class BrewDeskTests: XCTestCase {
    let env = BrewEnvironment(executable: "/opt/homebrew/bin/brew", prefix: "/opt/homebrew", version: "Homebrew 5")
    func package(_ token: String = "wget", version: String = "1", kind: PackageKind = .formula) -> BrewPackage {
        BrewPackage(token: token, name: token, kind: kind, summary: "", installed: version, available: "2", homepage: "", tap: "homebrew/core", dependencies: [], outdated: true, autoUpdates: false, pinned: false)
    }
    func testCommandsAreTypedAndNeverShellOrRoot() throws {
        XCTAssertEqual(try BrewCommandFactory.mutation(.upgrade, package: package(), environment: env).arguments, ["upgrade", "--formula", "wget"])
        XCTAssertEqual(try BrewCommandFactory.mutation(.uninstall, package: package("visual-studio-code", kind: .cask), environment: env).arguments, ["uninstall", "--cask", "visual-studio-code"])
        XCTAssertEqual(try BrewCommandFactory.mutation(.update, package: nil, environment: env).arguments, ["update"])
        for token in ["--force", "$(id)", "a;rm", "../bad", "a/../b", "", "a b", "a\nb"] { XCTAssertThrowsError(try BrewCommandFactory.mutation(.uninstall, package: package(token), environment: env), token) }
    }
    func testFlexibleJSONAndKinds() throws {
        let input = #"{"formulae":[{"name":"a","full_name":"tap/a","versions":{"stable":"2"},"installed":[{"version":"1","runtime_dependencies":[{"full_name":"b"}]}],"outdated":true,"new_field":42}],"casks":[{"token":"app","name":["App"],"installed":"1.1","version":"latest","auto_updates":true,"desc":null}]}"#
        let result = try BrewJSON.packages(Data(input.utf8))
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.first(where: { $0.kind == .formula })?.dependencies, ["b"])
        XCTAssertEqual(result.first(where: { $0.kind == .cask })?.installed, "1.1")
        XCTAssertTrue(result.first(where: { $0.kind == .cask })!.status == L("자체 업데이트 / 확인 제한"))
        XCTAssertThrowsError(try BrewJSON.packages(Data("{}".utf8)))
        XCTAssertThrowsError(try BrewJSON.packages(Data("not json".utf8)))
    }
    func testOutdatedSchema() throws {
        let ids = try BrewJSON.outdatedIDs(Data(#"{"formulae":[{"name":"git"}],"casks":[{"name":"firefox"}]}"#.utf8))
        XCTAssertEqual(ids, ["formula:git", "cask:firefox"])
    }
    func testChangesIncludeIndirectInstallsAndRemovals() {
        let changes = VersionChange.between([package("a"), package("b")], [package("a", version: "2"), package("c")])
        XCTAssertEqual(changes.count, 3)
        XCTAssertNil(changes.first(where: { $0.package == "formula:b" })?.after)
        XCTAssertNil(changes.first(where: { $0.package == "formula:c" })?.before)
    }
    func testHistoryRoundTripAndPermissions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = OperationHistoryStore(directory: directory)
        XCTAssertTrue(try store.load().isEmpty)
        let record = OperationRecord(id: UUID(), date: Date(), environment: env.executable, command: "brew update", exitCode: 1, result: "실패", changes: [], log: "fixture")
        try store.save([record])
        XCTAssertEqual(try store.load().first?.exitCode, 1)
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("history.json").path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }
    func testPipesDrainLargeStderrAndPreserveExitCode() async throws {
        let result = try await ProcessRunner.run(BrewCommand(executable: "/bin/sh", arguments: ["-c", "head -c 200000 /dev/zero >&2; printf good; exit 7"]))
        XCTAssertEqual(result.status, 7)
        XCTAssertEqual(String(decoding: result.output, as: UTF8.self), "good")
        XCTAssertEqual(result.error.count, 200000)
    }
    @MainActor func testPTYExitStatus() async {
        _ = NSApplication.shared
        let runner = PTYRunner()
        for _ in 0..<12 {
            let status = await runner.run(BrewCommand(executable: "/bin/sh", arguments: ["-c", "printf test-output; exit 7"]))
            XCTAssertEqual(status, 7)
            XCTAssertTrue(runner.log.contains("test-output"))
        }
    }
    @MainActor func testSecretInputNeverEntersSavedLog() async {
        _ = NSApplication.shared
        let runner = PTYRunner()
        let task = Task { await runner.run(BrewCommand(executable: "/bin/sh", arguments: ["-c", "stty -echo; read secret; stty echo; printf '%s' \"$secret\"; exit 0"])) }
        var sent = false
        for _ in 0..<200 {
            try? await Task.sleep(nanoseconds: 10_000_000)
            var state = termios()
            if tcgetattr(runner.terminal.process.childfd, &state) == 0, state.c_lflag & tcflag_t(ECHO) == 0 {
                runner.terminal.send(source: runner.terminal, data: Array("synthetic-secret\n".utf8)[...])
                sent = true; break
            }
        }
        if !sent { runner.interrupt() }
        let code = await task.value
        XCTAssertTrue(sent)
        XCTAssertEqual(code, 0)
        XCTAssertFalse(runner.log.contains("synthetic-secret"))
    }
    func testResolverRejectsMissingAndNonBrewExecutables() async {
        for path in ["/does-not-exist/brew", "/usr/bin/true"] {
            do { _ = try await BrewRepository().resolve(path); XCTFail("Invalid executable accepted") }
            catch { XCTAssertFalse(error.localizedDescription.isEmpty) }
        }
    }
    @MainActor func testPTYInterruptReachesForegroundProcess() async {
        _ = NSApplication.shared
        let runner = PTYRunner()
        let task = Task { await runner.run(BrewCommand(executable: "/bin/sh", arguments: ["-c", "sleep 20"])) }
        try? await Task.sleep(nanoseconds: 150_000_000)
        runner.interrupt()
        let code = await task.value
        XCTAssertEqual(code, 130)
    }
    func testLiveReadOnlyFixtureIfPresent() throws {
        guard ProcessInfo.processInfo.environment["BREWDESK_LIVE_FIXTURE"] == "1" else { throw XCTSkip("Opt-in local read-only fixture") }
        let packages = try BrewJSON.packages(Data(contentsOf: URL(fileURLWithPath: "/tmp/brewdesk-installed.json")))
        XCTAssertFalse(packages.isEmpty)
        XCTAssertEqual(Set(packages.map(\.id)).count, packages.count)
        print("Live Homebrew JSON decoded: \(packages.count) packages")
    }
}
