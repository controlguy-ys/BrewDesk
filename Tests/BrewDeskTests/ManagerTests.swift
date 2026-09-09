import XCTest
import AppKit
@testable import BrewDesk

final class ManagerTests: XCTestCase {
    func testCommandsStayInTheirManagerAndScope() throws {
        for manager in PackageManager.allCases where manager != .homebrew {
            let env = BrewEnvironment(executable: "/fixture/manager", prefix: "/fixture/root", version: "fixture", manager: manager)
            let p = ManagerParser.package("demo", "1.0.0", manager: manager, available: "2.0.0")
            for action in [BrewAction.install, .upgrade, .uninstall] {
                let cmd = try BrewCommandFactory.mutation(action, package: p, environment: env)
                XCTAssertEqual(cmd.executable, env.executable)
                XCTAssertFalse(cmd.arguments.contains("--break-system-packages"))
                XCTAssertFalse(cmd.arguments.contains("--force"))
                XCTAssertFalse(cmd.arguments.contains("-c"))
                if manager == .npm { XCTAssertTrue(cmd.arguments.contains("--global")); XCTAssertTrue(cmd.arguments.contains(env.prefix)) }
                if manager == .cargo { XCTAssertTrue(cmd.arguments.contains("--root")); XCTAssertTrue(cmd.arguments.contains(env.prefix)) }
            }
            let other = ManagerParser.package("demo", "1", manager: manager == .npm ? .pip : .npm, available: "2")
            XCTAssertThrowsError(try BrewCommandFactory.mutation(.install, package: other, environment: env))
            for token in ["--help", "foo;touch", "https://host/x", "../file", "name@tag", "a b", "$(id)"] {
                let invalid = ManagerParser.package(token, "1", manager: manager, available: "2")
                XCTAssertThrowsError(try BrewCommandFactory.mutation(.install, package: invalid, environment: env), "\(manager): \(token)")
            }
        }
        XCTAssertTrue(ManagerCommands.validName("@scope/tool", manager: .npm))
        XCTAssertFalse(ManagerCommands.validName("@scope/tool", manager: .pip))
    }
    func testManagerParsersAndDistinctIdentities() throws {
        let npm = try ManagerParser.npm(Data(#"{"dependencies":{"@scope/tool":{"version":"1.2.3"},"linked":{"version":"1","link":true}}}"#.utf8))
        XCTAssertEqual(npm.first(where: { $0.token == "@scope/tool" })?.id, "npm:@scope/tool")
        XCTAssertTrue(npm.first(where: { $0.token == "linked" })!.pinned)
        let pip = try ManagerParser.pip(Data(#"[{"name":"Some_Pkg","version":"1","latest_version":"2"}]"#.utf8))
        XCTAssertEqual(pip.first?.id, "pip:some-pkg"); XCTAssertTrue(pip[0].outdated)
        let pipx = try ManagerParser.pipx(Data(#"{"venvs":{"demo":{"metadata":{"main_package":{"package":"demo","package_version":"1","package_or_url":"demo"}}}}}"#.utf8))
        XCTAssertEqual(pipx.first?.id, "pipx:demo"); XCTAssertFalse(pipx[0].pinned)
        let uv = try ManagerParser.lines(Data("demo v1.2.3\n- demo\n".utf8), manager: .uv)
        XCTAssertEqual(uv.first?.id, "uv:demo"); XCTAssertEqual(uv.count, 1)
        let cargo = try ManagerParser.lines(Data("demo v1.2.3:\n    demo\nlocal v1.0.0 (/tmp/local):\n    local\n".utf8), manager: .cargo)
        XCTAssertEqual(cargo.count, 2); XCTAssertTrue(cargo[1].pinned)
        let gem = try ManagerParser.lines(Data("rake (13.2.0, 13.1.0)\njson (default: 2.6.1)\n".utf8), manager: .gem)
        XCTAssertEqual(gem[0].installed, "13.2.0"); XCTAssertTrue(gem[1].pinned)
        XCTAssertThrowsError(try ManagerParser.pip(Data("{}".utf8)))
        XCTAssertThrowsError(try ManagerParser.pipx(Data("{}".utf8)))
        XCTAssertThrowsError(try ManagerParser.npm(Data(#"{"error":{"code":"EFAIL"}}"#.utf8)))
        XCTAssertTrue(ManagerParser.stableNewer("1.10.0", than: "1.9.0"))
        XCTAssertFalse(ManagerParser.stableNewer("2.0.0-rc.1", than: "1.9.0"))
        XCTAssertFalse(ManagerParser.stableNewer("1.0.0", than: "2.0.0"))
        let prerelease = ManagerParser.package("demo", "2.0.0-rc.1", manager: .cargo)
        XCTAssertEqual(ManagerParser.applying([:], to: [prerelease])[0].available, "")
    }
    @MainActor func testNpmReadCheckThenVerifiedUpgradeAndStaleConfirmation() async throws {
        _ = NSApplication.shared
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let exe = dir.appendingPathComponent("npm")
        let script = #"""
        #!/bin/sh
        dir=$(dirname "$0")
        case "$1" in
          --version) echo 11.0.0 ;;
          prefix) echo "$dir" ;;
          list) cat "$dir/state.json" ;;
          outdated) if [ -f "$dir/error" ]; then echo '{"error":{"code":"ENETWORK"}}'; exit 1; fi
            if [ -f "$dir/changed" ]; then echo '{}'; else echo '{"demo":{"current":"1.0.0","latest":"2.0.0"}}'; exit 1; fi ;;
          install) echo '{"dependencies":{"demo":{"version":"2.0.0"}}}' > "$dir/state.json"; touch "$dir/changed" ;;
          *) exit 9 ;;
        esac
        """#
        try script.write(to: exe, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: exe.path)
        try Data(#"{"dependencies":{"demo":{"version":"1.0.0"}}}"#.utf8).write(to: dir.appendingPathComponent("state.json"))
        let model = AppModel(historyStore: OperationHistoryStore(directory: dir.appendingPathComponent("history")))
        model.environment = try await model.repository.resolve(exe.path, manager: .npm)
        await model.refresh()
        XCTAssertEqual(model.packages[0].available, "")
        let env = try XCTUnwrap(model.environment)
        await model.execute(PendingOperation(action: .update, packages: [], environment: env))
        XCTAssertTrue(model.packages[0].outdated)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("changed").path))
        model.prepareAllUpgrades(); let request = try XCTUnwrap(model.pending)
        await model.execute(request)
        XCTAssertEqual(model.packages[0].installed, "2.0.0")
        XCTAssertEqual(model.history[0].exitCode, 0)
        XCTAssertEqual(model.history[0].changes.first?.package, "npm:demo")
        await model.execute(request)
        XCTAssertEqual(model.history[0].exitCode, -1)
        let previous = model.packages
        try Data().write(to: dir.appendingPathComponent("error"))
        await model.execute(PendingOperation(action: .update, packages: [], environment: env))
        XCTAssertEqual(model.packages, previous); XCTAssertEqual(model.history[0].exitCode, -1)
    }
    @MainActor func testEveryManagerInstallAndRemoveVerifyStateAndHistory() async throws {
        _ = NSApplication.shared
        for manager in PackageManager.allCases where manager != .homebrew {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }
            let exe = dir.appendingPathComponent(manager.executableName)
            let script = #"""
            #!/bin/sh
            dir=$(dirname "$0")
            if [ "$1" = tool ]; then shift; fi
            case "$1" in
              --version) echo '1.0.0' ;;
              environment|prefix|dir) echo "$dir" ;;
              list) cat "$dir/state" ;;
              show) echo 'Required-by: ' ;;
              install)
                if [ "$2" = --list ]; then cat "$dir/state"; else cp "$dir/after" "$dir/state"; fi ;;
              uninstall) cp "$dir/empty" "$dir/state" ;;
              *) echo 'unexpected command' >&2; exit 9 ;;
            esac
            """#
            try script.write(to: exe, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: exe.path)
            let empty: String, after: String
            switch manager {
            case .npm: empty = #"{"dependencies":{}}"#; after = #"{"dependencies":{"demo":{"version":"1.0.0"}}}"#
            case .pip: empty = "[]"; after = #"[{"name":"demo","version":"1.0.0"}]"#
            case .pipx: empty = #"{"venvs":{}}"#; after = #"{"venvs":{"demo":{"metadata":{"main_package":{"package":"demo","package_version":"1.0.0","package_or_url":"demo"}}}}}"#
            case .uv: empty = ""; after = "demo v1.0.0\n- demo\n"
            case .cargo: empty = ""; after = "demo v1.0.0:\n    demo\n"
            case .gem: empty = ""; after = "demo (1.0.0)\n"
            case .homebrew: continue
            }
            for (filename, text) in [("state", empty), ("empty", empty), ("after", after)] {
                try text.write(to: dir.appendingPathComponent(filename), atomically: true, encoding: .utf8)
            }
            let model = AppModel(historyStore: OperationHistoryStore(directory: dir.appendingPathComponent("history")))
            let env = try await model.repository.resolve(exe.path, manager: manager)
            model.environment = env
            model.catalogPackage = ManagerParser.package("demo", "", manager: manager, available: "1.0.0")
            model.prepareInstall()
            await model.execute(try XCTUnwrap(model.pending))
            XCTAssertEqual(model.history.first?.exitCode, 0, manager.title)
            XCTAssertEqual(model.packages.first?.installed, "1.0.0", manager.title)
            let installed = try XCTUnwrap(model.packages.first)
            await model.execute(PendingOperation(action: .uninstall, packages: [installed], environment: env))
            XCTAssertTrue(model.packages.isEmpty, manager.title)
            XCTAssertEqual(model.history.first?.exitCode, 0, manager.title)
            XCTAssertEqual(model.history.first?.changes.first?.before, "1.0.0", manager.title)
        }
    }

}
