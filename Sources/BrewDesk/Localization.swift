import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en", korean = "ko", system = "system"
    var id: String { rawValue }
    static let preferenceKey = "appLanguage"
    static func saved(in defaults: UserDefaults = .standard) -> AppLanguage {
        AppLanguage(rawValue: defaults.string(forKey: preferenceKey) ?? "") ?? .english
    }
    func resolved(preferredLanguages: [String] = Locale.preferredLanguages) -> AppLanguage {
        guard self == .system else { return self }
        for language in preferredLanguages {
            let base = language.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first
            if base == "ko" { return .korean }
            if base == "en" { return .english }
        }
        return .english
    }
    var locale: Locale { Locale(identifier: resolved().rawValue) }
    var title: String {
        switch self { case .english: return "English"; case .korean: return "한국어"; case .system: return L("시스템 언어") }
    }
}

/// Stores templates and arguments separately so counts and operation results can change language later.
struct LocalizedMessage: ExpressibleByStringLiteral, ExpressibleByStringInterpolation, Codable, Equatable {
    struct Part: Codable, Equatable { var key: String; var arguments: [String] }
    var parts: [Part]
    init(stringLiteral value: String) { parts = [Part(key: value, arguments: [])] }
    init(key: String) { parts = [Part(key: key, arguments: [])] }
    init(stringInterpolation: StringInterpolation) { parts = [Part(key: stringInterpolation.key, arguments: stringInterpolation.arguments)] }
    struct StringInterpolation: StringInterpolationProtocol {
        var key = ""
        var arguments: [String] = []
        init(literalCapacity: Int, interpolationCount: Int) {}
        mutating func appendLiteral(_ literal: String) { key += literal }
        mutating func appendInterpolation<T>(_ value: T) { key += "{\(arguments.count)}"; arguments.append(String(describing: value)) }
    }
    func rendered(language: AppLanguage = .saved()) -> String {
        parts.map { part in L10n.format(L10n.catalog(language.resolved())[part.key] ?? L10n.catalog(.english)[part.key] ?? part.key, arguments: part.arguments) }.joined()
    }
    static func += (lhs: inout LocalizedMessage, rhs: LocalizedMessage) { lhs.parts += rhs.parts }
}
func L(_ message: LocalizedMessage) -> String { message.rendered() }
func M(_ message: LocalizedMessage) -> LocalizedMessage { message }

enum L10n {
    private static let bundle: Bundle = {
        // SwiftPM's command-line accessor does not search a packaged app's Contents/Resources.
        if let url = Bundle.main.resourceURL?.appendingPathComponent("BrewDesk_BrewDesk.bundle"), let packaged = Bundle(url: url) { return packaged }
        return Bundle.module
    }()
    private static let catalogs: [String: [String: String]] = {
        var result: [String: [String: String]] = [:]
        for language in ["en", "ko"] {
            if let url = bundle.url(forResource: language, withExtension: "json", subdirectory: "Resources"),
               let data = try? Data(contentsOf: url), let entries = try? JSONDecoder().decode([String: String].self, from: data) { result[language] = entries }
        }
        return result
    }()
    static func catalog(_ language: AppLanguage) -> [String: String] { catalogs[language.resolved().rawValue] ?? [:] }
    // Replace placeholders in the template only, never in user-provided values.
    static func format(_ template: String, arguments: [String]) -> String {
        let pattern = try! NSRegularExpression(pattern: #"\{([0-9]+)\}"#)
        let source = template as NSString
        var output = "", cursor = 0
        for match in pattern.matches(in: template, range: NSRange(location: 0, length: source.length)) {
            output += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let index = Int(source.substring(with: match.range(at: 1)))!
            output += arguments.indices.contains(index) ? arguments[index] : source.substring(with: match.range)
            cursor = NSMaxRange(match.range)
        }
        return output + source.substring(from: cursor)
    }
    static func date(_ date: Date, timeOnly: Bool = false) -> String {
        let formatter = DateFormatter(); formatter.locale = AppLanguage.saved().locale
        formatter.dateStyle = timeOnly ? .none : .medium; formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
