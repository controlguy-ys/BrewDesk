import Foundation

struct CatalogEntry: Identifiable, Hashable {
    let token: String
    let kind: PackageKind
    var id: String { "\(kind.rawValue):\(token)" }
}
extension BrewRepository {
    func search(_ text: String, kind: PackageKind?, environment: BrewEnvironment) async throws -> [CatalogEntry] {
        if environment.manager != .homebrew { return try await managerSearch(text, environment: environment) }
        if let kind { return try await search(text, kind: kind, environment: environment) }
        async let formulae = search(text, kind: PackageKind.formula, environment: environment)
        async let casks = search(text, kind: PackageKind.cask, environment: environment)
        return try await Array((formulae + casks).sorted {
            if $0.token == $1.token { return $0.kind.rawValue < $1.kind.rawValue }
            return $0.token.localizedStandardCompare($1.token) == .orderedAscending
        }.prefix(200))
    }

    func search(_ text: String, kind: PackageKind, environment: BrewEnvironment) async throws -> [CatalogEntry] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.range(of: #"^[A-Za-z0-9][A-Za-z0-9@+._-]{0,79}$"#, options: .regularExpression) != nil else {
            throw BrewError.message(L("패키지 이름을 입력하세요. 영문·숫자·@+._-를 사용할 수 있습니다."))
        }
        let result = try await ProcessRunner.run(BrewCommand(executable: environment.executable, arguments: ["search", "--\(kind.rawValue)", "--", query]))
        let message = String(decoding: result.error, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if result.status == 1, result.output.isEmpty,
           message == "Error: No formulae or casks found for \"\(query)\"." { return [] }
        guard result.status == 0 else { throw BrewError.message(String(message.prefix(6000))) }
        let data = result.output
        return String(decoding: data, as: UTF8.self).split(whereSeparator: \.isWhitespace)
            .map(String.init).filter { $0.range(of: #"^[A-Za-z0-9][A-Za-z0-9@+._/-]*$"#, options: .regularExpression) != nil }
            .prefix(200).map { CatalogEntry(token: $0, kind: kind) }
    }
    func catalogInfo(_ entry: CatalogEntry, environment: BrewEnvironment) async throws -> BrewPackage {
        if environment.manager != .homebrew { return try await managerInfo(entry, environment: environment) }
        let data = try await query(environment, ["info", "--json=v2", "--\(entry.kind.rawValue)", "--", entry.token])
        guard let package = try BrewJSON.packages(data).first(where: { $0.kind == entry.kind }) else {
            throw BrewError.message(L("패키지 정보를 찾지 못했습니다."))
        }
        return package
    }
}
