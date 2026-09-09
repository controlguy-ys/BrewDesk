import XCTest
@testable import BrewDesk

final class CatalogSearchTests: XCTestCase {
    @MainActor func testDefaultIsAllTypes() { XCTAssertNil(AppModel().catalogKind) }
    func testAllTypesPreserveKindAndAllowEmptyCategory() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let exe = dir.appendingPathComponent("brew")
        let script = #"""
        #!/bin/sh
        if [ "$4" = fail ]; then echo 'network failure' >&2; exit 1; fi
        if [ "$2" = --formula ]; then printf 'demo\n'; exit 0; fi
        if [ "$4" = single ]; then echo 'Error: No formulae or casks found for "single".' >&2; exit 1; fi
        printf 'demo\n'
        """#
        try script.write(to: exe, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: exe.path)
        let env = BrewEnvironment(executable: exe.path, prefix: dir.path, version: "test")
        let repo = BrewRepository()
        let both = try await repo.search("demo", kind: nil, environment: env)
        XCTAssertEqual(Set(both.map(\.id)), ["formula:demo", "cask:demo"])
        let one = try await repo.search("single", kind: nil, environment: env)
        XCTAssertEqual(one.map(\.id), ["formula:demo"])
        do { _ = try await repo.search("fail", kind: nil, environment: env); XCTFail("Error swallowed") } catch {}
    }
}
