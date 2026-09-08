import Foundation

enum PackageKind: String, Codable, CaseIterable { case formula, cask
    var title: String { self == .formula ? L("도구·라이브러리") : L("앱·기타 Cask") }
    var symbol: String { self == .formula ? "terminal" : "app.dashed" }
}
struct BrewPackage: Identifiable, Hashable, Codable {
    var id: String { "\(kind.rawValue):\(token)" }
    let token: String
    let name: String
    let kind: PackageKind
    let summary: String
    let installed: String
    let available: String
    let homepage: String
    let tap: String
    let dependencies: [String]
    let outdated: Bool
    let autoUpdates: Bool
    let pinned: Bool
    var status: String {
        if pinned { return L("고정됨") }
        if outdated { return L("업데이트 가능") }
        if autoUpdates || available == "latest" { return L("자체 업데이트 / 확인 제한") }
        return L("로컬 정의 기준 일치")
    }
}
struct BrewEnvironment: Identifiable, Hashable, Codable {
    var id: String { executable }
    let executable: String
    let prefix: String
    let version: String
}
enum BrewAction: String, Codable { case upgrade, uninstall, update }
struct BrewCommand: Equatable {
    let executable: String
    let arguments: [String]
    var display: String { ([executable] + arguments).map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }.joined(separator: " ") }
}
enum BrewError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let s) = self { return s }; return nil }
}
enum BrewCommandFactory {
    static func mutation(_ action: BrewAction, package: BrewPackage?, environment: BrewEnvironment) throws -> BrewCommand {
        guard environment.executable.hasPrefix("/") else { throw BrewError.message(L("Homebrew 절대 경로가 필요합니다.")) }
        if action == .update { return BrewCommand(executable: environment.executable, arguments: ["update"]) }
        guard let package, package.token.range(of: #"^[A-Za-z0-9][A-Za-z0-9@+._/-]*$"#, options: .regularExpression) != nil,
              !package.token.split(separator: "/").contains("..") else { throw BrewError.message(L("유효하지 않은 패키지 식별자입니다.")) }
        return BrewCommand(executable: environment.executable, arguments: [action.rawValue, "--\(package.kind.rawValue)", package.token])
    }
}

enum BrewJSON {
    // Homebrew adds fields within schema v2. Decode known fields and ignore additions.
    static func packages(_ data: Data) throws -> [BrewPackage] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let formulae = root["formulae"] as? [[String: Any]], let casks = root["casks"] as? [[String: Any]] else {
            throw BrewError.message(L("Homebrew JSON v2 설치 목록을 해석할 수 없습니다."))
        }
        let f = try formulae.map { item -> BrewPackage in
            guard let token = item["full_name"] as? String ?? item["name"] as? String else { throw BrewError.message(L("Formula 이름이 없습니다.")) }
            let installs = item["installed"] as? [[String: Any]] ?? []
            return BrewPackage(token: token, name: item["name"] as? String ?? token, kind: .formula,
                summary: item["desc"] as? String ?? "", installed: installs.compactMap { $0["version"] as? String }.joined(separator: ", "),
                available: (item["versions"] as? [String: Any])?["stable"] as? String ?? "",
                homepage: item["homepage"] as? String ?? "", tap: item["tap"] as? String ?? "",
                dependencies: Array(Set((item["dependencies"] as? [String] ?? []) + installs.flatMap { ($0["runtime_dependencies"] as? [[String: Any]] ?? []).compactMap { $0["full_name"] as? String } })).sorted(),
                outdated: item["outdated"] as? Bool ?? false, autoUpdates: false, pinned: item["pinned"] as? Bool ?? false)
        }
        let c = try casks.map { item -> BrewPackage in
            guard let token = item["full_token"] as? String ?? item["token"] as? String else { throw BrewError.message(L("Cask 식별자가 없습니다.")) }
            let raw = item["installed"]
            let installed = raw as? String ?? (raw as? [String])?.joined(separator: ", ") ?? ""
            return BrewPackage(token: token, name: (item["name"] as? [String])?.first ?? token, kind: .cask,
                summary: item["desc"] as? String ?? "", installed: installed, available: item["version"] as? String ?? "",
                homepage: item["homepage"] as? String ?? "", tap: item["tap"] as? String ?? "",
                dependencies: (item["depends_on"] as? [String: Any])?["formula"] as? [String] ?? [],
                outdated: item["outdated"] as? Bool ?? false, autoUpdates: item["auto_updates"] as? Bool ?? false, pinned: false)
        }
        return (f + c).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    static func outdatedIDs(_ data: Data) throws -> Set<String> {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let formulae = root["formulae"] as? [[String: Any]], let casks = root["casks"] as? [[String: Any]] else { throw BrewError.message(L("업데이트 JSON을 해석할 수 없습니다.")) }
        return Set(formulae.compactMap { ($0["name"] as? String).map { "formula:\($0)" } } + casks.compactMap { ($0["name"] as? String).map { "cask:\($0)" } })
    }
}
struct VersionChange: Codable, Identifiable {
    var id: String { package }
    let package: String
    let before: String?
    let after: String?
    static func between(_ before: [BrewPackage], _ after: [BrewPackage]) -> [VersionChange] {
        let b = Dictionary(uniqueKeysWithValues: before.map { ($0.id, $0.installed) })
        let a = Dictionary(uniqueKeysWithValues: after.map { ($0.id, $0.installed) })
        return Set(b.keys).union(a.keys).sorted().compactMap { key in
            b[key] == a[key] ? nil : VersionChange(package: key, before: b[key], after: a[key])
        }
    }
}
struct OperationRecord: Codable, Identifiable {
    let id: UUID
    let date: Date
    let environment: String
    let command: String
    let exitCode: Int32
    let result: String
    let changes: [VersionChange]
    let log: String
    var localizedResult: LocalizedMessage? = nil
    var displayResult: String { localizedResult?.rendered() ?? result }
}
