import Foundation

/// All commands use argument arrays. Package names never become shell code or arbitrary URLs.
enum ManagerCommands {
    static func validName(_ name: String, manager: PackageManager) -> Bool {
        let pattern = manager == .npm ? #"^(?:@[a-z0-9][a-z0-9._-]*/)?[a-z0-9][a-z0-9._-]*$"# : #"^[A-Za-z0-9][A-Za-z0-9._-]*$"#
        return name.count <= 214 && !name.contains("..") && name.range(of: pattern, options: .regularExpression) != nil
    }
    static func normalize(_ name: String) -> String {
        name.lowercased().replacingOccurrences(of: #"[-_.]+"#, with: "-", options: .regularExpression)
    }
    static func mutation(_ action: BrewAction, package: BrewPackage?, environment e: BrewEnvironment) throws -> BrewCommand {
        guard e.executable.hasPrefix("/"), let p = package, p.kind.manager == e.manager,
              validName(p.token, manager: e.manager), action != .update else { throw BrewError.message(L("유효하지 않은 패키지 식별자입니다.")) }
        if action != .uninstall {
            guard !p.available.isEmpty, p.available.range(of: #"^[A-Za-z0-9][A-Za-z0-9.+_-]*$"#, options: .regularExpression) != nil else { throw BrewError.message(L("설치할 버전을 먼저 확인하세요.")) }
        }
        let name = p.token, version = p.available
        let args: [String]
        switch e.manager {
        case .npm:
            args = [action == .uninstall ? "uninstall" : "install", "--global", "--prefix", e.prefix, "--", action == .uninstall ? name : "\(name)@\(version)"]
        case .pip:
            args = action == .uninstall ? ["uninstall", name] : ["install", "--upgrade", "\(name)==\(version)"]
        case .pipx:
            args = action == .install ? ["install", name] : [action == .uninstall ? "uninstall" : "upgrade", name]
        case .uv:
            args = action == .install ? ["tool", "install", name] : ["tool", action == .uninstall ? "uninstall" : "upgrade", name]
        case .cargo:
            args = action == .uninstall ? ["uninstall", "--root", e.prefix, name] : ["install", "--root", e.prefix, "--version", version, name]
        case .gem:
            args = action == .uninstall ? ["uninstall", name, "--all", "--executables"] : ["install", name, "--version", version, "--no-document"]
        case .homebrew: throw BrewError.message(L("유효하지 않은 패키지 식별자입니다."))
        }
        return BrewCommand(executable: e.executable, arguments: args)
    }
}

enum ManagerParser {
    static func object(_ data: Data) throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw BrewError.message(L("패키지 목록 형식이 올바르지 않습니다.")) }; return value
    }
    static func array(_ data: Data) throws -> [[String: Any]] {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw BrewError.message(L("패키지 목록 형식이 올바르지 않습니다.")) }; return value
    }
    static func package(_ name: String, _ version: String, manager: PackageManager, available: String = "", summary: String = "", homepage: String = "", pinned: Bool = false) -> BrewPackage {
        let token = [.pip, .pipx, .uv].contains(manager) ? ManagerCommands.normalize(name) : name
        return BrewPackage(token: token, name: name, kind: manager.kinds[0], summary: summary, installed: version, available: available, homepage: homepage, tap: manager.title, dependencies: [], outdated: !version.isEmpty && !available.isEmpty && version != available, autoUpdates: false, pinned: pinned)
    }
    static func npm(_ data: Data) throws -> [BrewPackage] {
        let root = try object(data)
        if root["error"] != nil { throw BrewError.message(L("패키지 목록 형식이 올바르지 않습니다.")) }
        return try (root["dependencies"] as? [String: [String: Any]] ?? [:]).map { name, item in
            guard let version = item["version"] as? String else { throw BrewError.message(L("패키지 목록 형식이 올바르지 않습니다.")) }
            return package(name, version, manager: .npm, pinned: item["link"] as? Bool == true)
        }
    }
    static func pip(_ data: Data, manager: PackageManager = .pip) throws -> [BrewPackage] {
        try array(data).map { item in
            guard let name = item["name"] as? String, let version = item["version"] as? String else { throw BrewError.message(L("패키지 목록 형식이 올바르지 않습니다.")) }
            return package(name, version, manager: manager, available: item["latest_version"] as? String ?? "", pinned: item["editable_project_location"] != nil)
        }
    }
    static func pipx(_ data: Data) throws -> [BrewPackage] {
        guard let venvs = try object(data)["venvs"] as? [String: [String: Any]] else { throw BrewError.message(L("패키지 목록 형식이 올바르지 않습니다.")) }
        return try venvs.map { name, item in
            guard let metadata = item["metadata"] as? [String: Any], let main = metadata["main_package"] as? [String: Any], let version = main["package_version"] as? String else { throw BrewError.message(L("패키지 목록 형식이 올바르지 않습니다.")) }
            let source = main["package_or_url"] as? String ?? name
            let canonical = main["package"] as? String ?? name
            return package(name, version, manager: .pipx, pinned: ManagerCommands.normalize(name) != ManagerCommands.normalize(canonical) || !ManagerCommands.validName(source, manager: .pipx) || metadata["pinned"] as? Bool == true)
        }
    }
    static func lines(_ data: Data, manager: PackageManager) throws -> [BrewPackage] {
        let text = String(decoding: data, as: UTF8.self)
        let pattern = manager == .gem ? #"^([A-Za-z0-9][A-Za-z0-9._-]*) \((.+)\)$"# : #"^([A-Za-z0-9][A-Za-z0-9._-]*) v([^ :]+)(.*)$"#
        let re = try NSRegularExpression(pattern: pattern)
        return try text.split(separator: "\n").compactMap { line in
            let s = String(line), ns = s as NSString
            guard let match = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else {
                if s.trimmingCharacters(in: .whitespaces).isEmpty || s.hasPrefix(" ") || s.hasPrefix("-") || s.hasPrefix("***") { return nil }
                throw BrewError.message(L("패키지 목록 형식이 올바르지 않습니다."))
            }
            let name = ns.substring(with: match.range(at: 1)), rawVersion = ns.substring(with: match.range(at: 2))
            let version = rawVersion.replacingOccurrences(of: "default: ", with: "").split(separator: ",").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? rawVersion
            return package(name, version, manager: manager, summary: manager == .gem ? rawVersion : "", pinned: rawVersion.contains("default:") || (manager == .cargo && s.contains(" (")))
        }
    }
    static func applying(_ updates: [String: String], to packages: [BrewPackage]) -> [BrewPackage] {
        packages.map { p in
            BrewPackage(token: p.token, name: p.name, kind: p.kind, summary: p.summary, installed: p.installed, available: p.kind == .cargo && p.installed.range(of: #"^[0-9]+\.[0-9]+\.[0-9]+$"#, options: .regularExpression) == nil ? "" : (updates[p.token] ?? p.installed), homepage: p.homepage, tap: p.tap, dependencies: p.dependencies, outdated: updates[p.token].map { $0 != p.installed } ?? false, autoUpdates: p.autoUpdates, pinned: p.pinned)
        }
    }
    static func stableNewer(_ latest: String, than current: String) -> Bool {
        // crates.io comparisons only: do not interpret prerelease/build/local versions as stable upgrades.
        func numbers(_ version: String) -> [Int]? {
            let parts = version.split(separator: "."); let ints = parts.compactMap { Int($0) }
            return parts.count == 3 && ints.count == 3 ? ints : nil
        }
        guard let a = numbers(latest), let b = numbers(current) else { return false }
        return b.lexicographicallyPrecedes(a)
    }
}

extension BrewRepository {
    func resolve(_ path: String, manager: PackageManager) async throws -> BrewEnvironment {
        if manager == .homebrew { return try await resolve(path) }
        guard path.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: path) else { throw BrewError.message(L("실행 파일을 확인하세요.")) }
        var env = BrewEnvironment(executable: path, prefix: "", version: "", manager: manager)
        let version = String(decoding: try await query(env, ["--version"]), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !version.isEmpty else { throw BrewError.message(L("실행 파일을 확인하세요.")) }
        let args: [String]
        switch manager {
        case .npm: args = ["prefix", "--global"]
        case .pip: args = []
        case .pipx: args = ["environment", "--value", "PIPX_HOME"]
        case .uv: args = ["tool", "dir"]
        case .gem: args = ["environment", "home"]
        case .cargo, .homebrew: args = []
        }
        let prefix: String
        if manager == .cargo {
            prefix = ProcessInfo.processInfo.environment["CARGO_INSTALL_ROOT"] ?? ProcessInfo.processInfo.environment["CARGO_HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cargo").path
        } else if args.isEmpty { prefix = URL(fileURLWithPath: path).deletingLastPathComponent().path }
        else { prefix = String(decoding: try await query(env, args), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) }
        guard prefix.hasPrefix("/"), !prefix.contains("\n") else { throw BrewError.message(L("설치 환경 경로를 확인하지 못했습니다.")) }
        env = BrewEnvironment(executable: path, prefix: prefix, version: "\(manager.title) · \(version)", manager: manager)
        return env
    }

    func managerInstalled(_ e: BrewEnvironment, checkingUpdates: Bool) async throws -> [BrewPackage] {
        var packages: [BrewPackage]
        switch e.manager {
        case .npm: packages = try ManagerParser.npm(await query(e, ["list", "--global", "--prefix", e.prefix, "--depth=0", "--json"]))
        case .pip: packages = try ManagerParser.pip(await query(e, ["list", "--format=json", "--disable-pip-version-check"]))
        case .pipx: packages = try ManagerParser.pipx(await query(e, ["list", "--json"]))
        case .uv: packages = try ManagerParser.lines(await query(e, ["tool", "list", "--color", "never"]), manager: .uv)
        case .cargo: packages = try ManagerParser.lines(await query(e, ["install", "--list", "--root", e.prefix]), manager: .cargo)
        case .gem: packages = try ManagerParser.lines(await query(e, ["list", "--local"]), manager: .gem)
        case .homebrew: return []
        }
        if checkingUpdates {
            var updates: [String: String] = [:]
            switch e.manager {
            case .npm:
                let result = try await ProcessRunner.run(BrewCommand(executable: e.executable, arguments: ["outdated", "--global", "--prefix", e.prefix, "--json"]))
                guard result.status == 0 || result.status == 1 else { throw BrewError.message(String(decoding: result.error, as: UTF8.self)) }
                let root = try ManagerParser.object(result.output)
                guard root["error"] == nil else { throw BrewError.message(L("업데이트 조회에 실패했습니다.")) }
                for (name, value) in root {
                    guard let item = value as? [String: Any], let latest = item["latest"] as? String else { throw BrewError.message(L("패키지 목록 형식이 올바르지 않습니다.")) }
                    updates[name] = latest
                }
            case .pip:
                for p in try ManagerParser.pip(await query(e, ["list", "--outdated", "--format=json", "--disable-pip-version-check"])) { updates[p.token] = p.available }
            case .pipx, .uv:
                for p in packages where !p.pinned {
                    guard ManagerCommands.validName(p.token, manager: e.manager) else { continue }
                    let args = e.manager == .pipx ? ["runpip", p.token, "list", "--outdated", "--format=json", "--disable-pip-version-check"] : ["pip", "list", "--python", e.prefix + "/" + p.token + "/bin/python", "--outdated", "--format=json", "--color", "never"]
                    for result in try ManagerParser.pip(await query(e, args)) where result.token == p.token { updates[p.token] = result.available }
                }
            case .cargo:
                for p in packages where !p.pinned {
                    let info = try await managerInfo(CatalogEntry(token: p.token, kind: .cargo), environment: e)
                    if ManagerParser.stableNewer(info.available, than: p.installed) { updates[p.token] = info.available }
                }
            case .gem:
                let data = try await query(e, ["outdated"])
                let re = try NSRegularExpression(pattern: #"^([A-Za-z0-9][A-Za-z0-9._-]*) \([^ ]+ < ([^)]+)\)$"#)
                for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
                    let ns = String(line) as NSString
                    if let m = re.firstMatch(in: String(line), range: NSRange(location: 0, length: ns.length)) { updates[ns.substring(with: m.range(at: 1))] = ns.substring(with: m.range(at: 2)) }
                }
            case .homebrew: break
            }
            packages = ManagerParser.applying(updates, to: packages)
        }
        return packages.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func pipDependents(_ p: BrewPackage, environment e: BrewEnvironment) async throws -> [String] {
        guard ManagerCommands.validName(p.token, manager: .pip) else { throw BrewError.message(L("유효하지 않은 패키지 식별자입니다.")) }
        let data = try await query(e, ["show", p.token])
        let line = String(decoding: data, as: UTF8.self).split(separator: "\n").first { $0.hasPrefix("Required-by:") }
        guard let line else { throw BrewError.message(L("패키지 목록 형식이 올바르지 않습니다.")) }
        return String(line.dropFirst("Required-by:".count)).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    func registryJSON(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue("BrewDesk/0.4.0 (https://github.com/controlguy-ys/BrewDesk)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw BrewError.message(L("패키지를 찾지 못했거나 저장소에 연결하지 못했습니다.")) }
        return data
    }
    func managerSearch(_ text: String, environment e: BrewEnvironment) async throws -> [CatalogEntry] {
        let term = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ManagerCommands.validName(term, manager: e.manager) else { throw BrewError.message(L("유효하지 않은 패키지 식별자입니다.")) }
        if e.manager == .npm {
            return try ManagerParser.array(await query(e, ["search", "--json", "--searchlimit=100", "--", term])).compactMap { item in
                guard let name = item["name"] as? String, ManagerCommands.validName(name, manager: .npm) else { return nil }
                return CatalogEntry(token: name, kind: .npm)
            }
        }
        // PyPI, crates.io and RubyGems exact-name lookup avoids brittle human search output.
        let package = try await managerInfo(CatalogEntry(token: term, kind: e.manager.kinds[0]), environment: e)
        return [CatalogEntry(token: package.token, kind: package.kind)]
    }
    func managerInfo(_ entry: CatalogEntry, environment e: BrewEnvironment) async throws -> BrewPackage {
        guard entry.kind.manager == e.manager, ManagerCommands.validName(entry.token, manager: e.manager) else { throw BrewError.message(L("유효하지 않은 패키지 식별자입니다.")) }
        let name = entry.token
        let item: [String: Any]
        switch e.manager {
        case .npm: item = try ManagerParser.object(await query(e, ["view", "--json", "--", name]))
        case .pip, .pipx, .uv:
            let root = try ManagerParser.object(await registryJSON(URL(string: "https://pypi.org/pypi/\(name)/json")!))
            guard let info = root["info"] as? [String: Any] else { throw BrewError.message(L("패키지 정보를 찾지 못했습니다.")) }; item = info
        case .cargo:
            let root = try ManagerParser.object(await registryJSON(URL(string: "https://crates.io/api/v1/crates/\(name)")!))
            guard let crate = root["crate"] as? [String: Any] else { throw BrewError.message(L("패키지 정보를 찾지 못했습니다.")) }; item = crate
        case .gem: item = try ManagerParser.object(await registryJSON(URL(string: "https://rubygems.org/api/v1/gems/\(name).json")!))
        case .homebrew: throw BrewError.message(L("패키지 정보를 찾지 못했습니다."))
        }
        guard let version = (e.manager == .cargo ? item["max_stable_version"] : item["version"]) as? String else { throw BrewError.message(L("패키지 정보를 찾지 못했습니다.")) }
        return ManagerParser.package(item["name"] as? String ?? name, "", manager: e.manager, available: version, summary: item["summary"] as? String ?? item["description"] as? String ?? item["info"] as? String ?? "", homepage: item["homepage"] as? String ?? item["home_page"] as? String ?? item["homepage_uri"] as? String ?? "")
    }
}
