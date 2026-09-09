import XCTest
import AppKit
@testable import BrewDesk

final class InstallTests: XCTestCase {
    let info = #"{"formulae":[{"name":"demo","full_name":"demo","versions":{"stable":"2"},"installed":[],"desc":"Demo tool"}],"casks":[]}"#
    func testCatalogDecodesUninstalledAndUsesInstallAllowlist() throws {
        let package = try XCTUnwrap(BrewJSON.packages(Data(info.utf8)).first)
        XCTAssertTrue(package.installed.isEmpty)
        let env = BrewEnvironment(executable: "/fixture/brew", prefix: "/fixture", version: "test")
        XCTAssertEqual(try BrewCommandFactory.mutation(.install, package: package, environment: env).arguments, ["install", "--formula", "demo"])
    }
    @MainActor func testInstallRunsThroughVerificationAndHistory() async throws {
        _ = NSApplication.shared
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let script = #"""
        #!/bin/sh
        dir=$(dirname "$0")
        case "$1" in
          info) cat "$dir/state.json" ;;
          install) cp "$dir/after.json" "$dir/state.json"; printf 'installed\n' ;;
          *) exit 2 ;;
        esac
        """#
        let exe = dir.appendingPathComponent("brew")
        try script.write(to: exe, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: exe.path)
        try Data(#"{"formulae":[],"casks":[]}"#.utf8).write(to: dir.appendingPathComponent("state.json"))
        let after = info.replacingOccurrences(of: #""installed":[]"#, with: #""installed":[{"version":"2"}]"#)
        try Data(after.utf8).write(to: dir.appendingPathComponent("after.json"))
        let model = AppModel(historyStore: OperationHistoryStore(directory: dir.appendingPathComponent("history")))
        model.environment = BrewEnvironment(executable: exe.path, prefix: dir.path, version: "test")
        model.catalogPackage = try XCTUnwrap(BrewJSON.packages(Data(info.utf8)).first)
        model.prepareInstall()
        let request = try XCTUnwrap(model.pending)
        XCTAssertFalse(model.busy)
        await model.execute(request)
        XCTAssertEqual(model.packages.first?.installed, "2")
        XCTAssertEqual(model.history.first?.exitCode, 0)
        XCTAssertEqual(model.history.first?.changes.first?.after, "2")
        model.prepareInstall()
        XCTAssertNil(model.pending)
        // A stale confirmation cannot reinstall a package installed since confirmation.
        await model.execute(request)
        XCTAssertEqual(model.history.first?.exitCode, -1)
    }
    func testSearchRejectsOptionsAndRegex() async {
        let repo = BrewRepository()
        let env = BrewEnvironment(executable: "/must/not/run", prefix: "", version: "")
        for query in ["--help", "/.*/", "foo;bar", ""] {
            do { _ = try await repo.search(query, kind: .formula, environment: env); XCTFail("Accepted invalid search") }
            catch { XCTAssertTrue(error is BrewError) }
        }
    }
}
