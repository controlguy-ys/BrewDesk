import Foundation

struct ProcessResult { let output: Data; let error: Data; let status: Int32 }
enum ProcessRunner {
    static func environment(for executable: String) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = URL(fileURLWithPath: executable).deletingLastPathComponent().path + ":/usr/bin:/bin:/usr/sbin:/sbin"
        env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        env["HOMEBREW_NO_ANALYTICS"] = "1"
        env["HOMEBREW_NO_ENV_HINTS"] = "1"
        return env
    }
    static func run(_ command: BrewCommand) async throws -> ProcessResult {
        try await Task.detached(priority: .userInitiated) {
            let p = Process(), out = Pipe(), err = Pipe()
            p.executableURL = URL(fileURLWithPath: command.executable)
            p.arguments = command.arguments
            p.environment = environment(for: command.executable)
            p.standardOutput = out; p.standardError = err; p.standardInput = FileHandle.nullDevice
            try p.run()
            // Drain both streams concurrently: large stderr must never block stdout.
            let errorTask = Task.detached { err.fileHandleForReading.readDataToEndOfFile() }
            let output = out.fileHandleForReading.readDataToEndOfFile()
            let error = await errorTask.value
            p.waitUntilExit()
            return ProcessResult(output: output, error: error, status: p.terminationStatus)
        }.value
    }
}
struct BrewRepository {
    func query(_ environment: BrewEnvironment, _ args: [String]) async throws -> Data {
        let result = try await ProcessRunner.run(BrewCommand(executable: environment.executable, arguments: args))
        guard result.status == 0 else { throw BrewError.message(String(decoding: result.error, as: UTF8.self).prefix(6000).description) }
        return result.output
    }
    func resolve(_ path: String) async throws -> BrewEnvironment {
        guard path.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: path) else { throw BrewError.message(L("실행 가능한 Homebrew 파일을 선택하세요.")) }
        let stub = BrewEnvironment(executable: path, prefix: "", version: "")
        let version = String(decoding: try await query(stub, ["--version"]), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard version.hasPrefix("Homebrew ") else { throw BrewError.message(L("Homebrew 실행 파일이 아닙니다.")) }
        let prefix = String(decoding: try await query(stub, ["--prefix"]), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return BrewEnvironment(executable: path, prefix: prefix, version: version)
    }
    func installed(_ environment: BrewEnvironment) async throws -> [BrewPackage] { try BrewJSON.packages(await query(environment, ["info", "--json=v2", "--installed"])) }
    func dependents(_ package: BrewPackage, environment: BrewEnvironment) async throws -> [String] {
        guard package.kind == .formula else { return [] }
        return String(decoding: try await query(environment, ["uses", "--installed", "--recursive", package.token]), as: UTF8.self).split(whereSeparator: \.isWhitespace).map(String.init)
    }
    func paths(_ package: BrewPackage, environment: BrewEnvironment) async throws -> [String] {
        let data = try await query(environment, ["list", "--\(package.kind.rawValue)", package.token])
        return String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init).filter { $0.hasPrefix("/") && FileManager.default.fileExists(atPath: $0) }
    }
}
struct OperationHistoryStore {
    let directory: URL
    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("BrewDesk")
    }
    func load() throws -> [OperationRecord] {
        let file = directory.appendingPathComponent("history.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        return try JSONDecoder().decode([OperationRecord].self, from: Data(contentsOf: file))
    }
    func save(_ records: [OperationRecord]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let file = directory.appendingPathComponent("history.json")
        try JSONEncoder().encode(Array(records.prefix(200))).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}
