import XCTest
import AppKit
@testable import BrewDesk

final class OperationTests: XCTestCase {
    struct Fixture {
        let directory: URL
        let env: BrewEnvironment
        init(failing: Bool = false, blocked: Bool = false) throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("BrewDesk Test " + UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            env = BrewEnvironment(executable: directory.appendingPathComponent("brew").path, prefix: directory.path, version: "Homebrew fixture")
            let script = #"""
            #!/bin/sh
            dir=$(dirname "$0")
            case "$1" in
              info) if [ -f "$dir/queryfail" ]; then printf "query failed" >&2; exit 1; fi; cat "$dir/state.json" ;;
              uses) if [ -f "$dir/blocked" ]; then printf 'dependent\n'; fi ;;
              upgrade)
                printf '%s\n' "$3" >> "$dir/calls"
                if [ -f "$dir/fail" ]; then printf 'simulated failure\n'; exit 7; fi
                cp "$dir/$3.json" "$dir/state.json"
                printf 'fixture upgrade complete\n'
                ;;
              uninstall) printf 'unexpected uninstall\n' >> "$dir/calls"; exit 9 ;;
              *) exit 2 ;;
            esac
            """#
            try script.write(toFile: env.executable, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: env.executable)
            try Self.json(a: "1", b: "1").write(to: directory.appendingPathComponent("state.json"), atomically: true, encoding: .utf8)
            try Self.json(a: "2", b: "1").write(to: directory.appendingPathComponent("a.json"), atomically: true, encoding: .utf8)
            try Self.json(a: "2", b: "2").write(to: directory.appendingPathComponent("b.json"), atomically: true, encoding: .utf8)
            if failing { try Data().write(to: directory.appendingPathComponent("fail")) }
            if blocked { try Data().write(to: directory.appendingPathComponent("blocked")) }
        }
        static func json(a: String, b: String) -> String {
            "{\"formulae\":[" + [("a", a), ("b", b)].map { name, version in
                "{\"name\":\"\(name)\",\"installed\":[{\"version\":\"\(version)\"}],\"versions\":{\"stable\":\"2\"},\"outdated\":\(version == "1")}"
            }.joined(separator: ",") + "],\"casks\":[]}"
        }
        func cleanup() { try? FileManager.default.removeItem(at: directory) }
    }
    @MainActor func testBatchRunsFIFOAndVerifiesActualVersions() async throws {
        _ = NSApplication.shared
        let fixture = try Fixture(); defer { fixture.cleanup() }
        let model = AppModel(historyStore: OperationHistoryStore(directory: fixture.directory.appendingPathComponent("history")))
        model.environment = fixture.env
        model.packages = try await model.repository.installed(fixture.env)
        await model.execute(PendingOperation(action: .upgrade, packages: model.packages, environment: fixture.env))
        XCTAssertEqual(try String(contentsOf: fixture.directory.appendingPathComponent("calls"), encoding: .utf8), "a\nb\n")
        XCTAssertEqual(model.history.count, 2)
        XCTAssertTrue(model.packages.allSatisfy { $0.installed == "2" })
        XCTAssertEqual(model.history.first?.changes.first?.package, "formula:b")
        XCTAssertFalse(model.busy)
    }
    @MainActor func testFailureStopsQueueAndDoesNotFakeVersions() async throws {
        _ = NSApplication.shared
        let fixture = try Fixture(failing: true); defer { fixture.cleanup() }
        let model = AppModel(historyStore: OperationHistoryStore(directory: fixture.directory.appendingPathComponent("history")))
        model.environment = fixture.env
        model.packages = try await model.repository.installed(fixture.env)
        await model.execute(PendingOperation(action: .upgrade, packages: model.packages, environment: fixture.env))
        XCTAssertEqual(try String(contentsOf: fixture.directory.appendingPathComponent("calls"), encoding: .utf8), "a\n")
        XCTAssertEqual(model.history.first?.exitCode, 7)
        XCTAssertTrue(model.packages.allSatisfy { $0.installed == "1" })
        XCTAssertTrue(model.statusMessage.rendered(language: .english).contains("Failed"))
    }
    @MainActor func testDependentBlocksUninstallBeforeMutation() async throws {
        let fixture = try Fixture(blocked: true); defer { fixture.cleanup() }
        let model = AppModel(historyStore: OperationHistoryStore(directory: fixture.directory.appendingPathComponent("history")))
        model.environment = fixture.env
        model.packages = try await model.repository.installed(fixture.env)
        await model.execute(PendingOperation(action: .uninstall, packages: [model.packages[0]], environment: fixture.env))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("calls").path))
        XCTAssertTrue(model.error?.contains("dependent") == true)
        XCTAssertEqual(model.history.first?.exitCode, -1)
    }
    @MainActor func testRefreshFailurePreservesExistingList() async throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        let model = AppModel(historyStore: OperationHistoryStore(directory: fixture.directory.appendingPathComponent("history")))
        model.environment = fixture.env
        await model.refresh()
        let before = model.packages
        try Data().write(to: fixture.directory.appendingPathComponent("queryfail"))
        await model.refresh()
        XCTAssertEqual(model.packages, before)
        XCTAssertNotNil(model.error)
        XCTAssertTrue(model.statusMessage.rendered(language: .english).contains("Previous list retained"))
    }
    @MainActor func testChangedEnvironmentRejectsPendingOperation() async throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        let model = AppModel(historyStore: OperationHistoryStore(directory: fixture.directory.appendingPathComponent("history")))
        await model.execute(PendingOperation(action: .upgrade, packages: [], environment: fixture.env))
        XCTAssertFalse(model.busy)
        XCTAssertTrue(model.history.isEmpty)
    }
}
