import Foundation

struct CatalogEntry: Identifiable, Hashable {
    let token: String
    let kind: PackageKind
    var id: String { "\(kind.rawValue):\(token)" }
}
extension BrewRepository {
    func search(_ text: String, kind: PackageKind, environment: BrewEnvironment) async throws -> [CatalogEntry] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.range(of: #"^[A-Za-z0-9][A-Za-z0-9@+._-]{0,79}$"#, options: .regularExpression) != nil else {
            throw BrewError.message(L("패키지 이름을 입력하세요. 영문·숫자·@+._-를 사용할 수 있습니다."))
        }
        let data = try await self.query(environment, ["search", "--\(kind.rawValue)", "--", query])
        return String(decoding: data, as: UTF8.self).split(whereSeparator: \.isWhitespace)
            .map(String.init).filter { $0.range(of: #"^[A-Za-z0-9][A-Za-z0-9@+._/-]*$"#, options: .regularExpression) != nil }
            .prefix(200).map { CatalogEntry(token: $0, kind: kind) }
    }
    func catalogInfo(_ entry: CatalogEntry, environment: BrewEnvironment) async throws -> BrewPackage {
        let data = try await query(environment, ["info", "--json=v2", "--\(entry.kind.rawValue)", "--", entry.token])
        guard let package = try BrewJSON.packages(data).first(where: { $0.kind == entry.kind }) else {
            throw BrewError.message(L("패키지 정보를 찾지 못했습니다."))
        }
        return package
    }
}
