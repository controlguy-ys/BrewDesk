import XCTest
@testable import BrewDesk

final class LocalizationTests: XCTestCase {
    func testEnglishDefaultAndSavedPreference() {
        let name = "BrewDesk.LocalizationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(AppLanguage.saved(in: defaults), .english)
        defaults.set("ko", forKey: AppLanguage.preferenceKey)
        XCTAssertEqual(AppLanguage.saved(in: defaults), .korean)
        defaults.set("invalid", forKey: AppLanguage.preferenceKey)
        XCTAssertEqual(AppLanguage.saved(in: defaults), .english)
    }
    func testSystemLanguageResolution() {
        XCTAssertEqual(AppLanguage.system.resolved(preferredLanguages: ["ko-KR", "en-US"]), .korean)
        XCTAssertEqual(AppLanguage.system.resolved(preferredLanguages: ["fr-FR", "en-GB", "ko"]), .english)
        XCTAssertEqual(AppLanguage.system.resolved(preferredLanguages: ["ja-JP"]), .english)
        XCTAssertEqual(AppLanguage.english.resolved(preferredLanguages: ["ko-KR"]), .english)
    }
    func testCatalogParityAndPlaceholders() {
        let en = L10n.catalog(.english), ko = L10n.catalog(.korean)
        XCTAssertGreaterThan(en.count, 120)
        XCTAssertEqual(Set(en.keys), Set(ko.keys))
        let pattern = try! NSRegularExpression(pattern: #"\{[0-9]+\}"#)
        func placeholders(_ text: String) -> [String] {
            let ns = text as NSString
            return pattern.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }.sorted()
        }
        for key in en.keys {
            XCTAssertFalse(en[key]!.isEmpty, key)
            XCTAssertEqual(placeholders(key), placeholders(en[key]!), key)
            XCTAssertEqual(placeholders(key), placeholders(ko[key]!), key)
        }
    }
    func testInterpolationReordersWithoutReinterpretingArguments() {
        let message = M("선택 \(3)개 업데이트…")
        XCTAssertEqual(message.rendered(language: .english), "Update selection (3)…")
        XCTAssertEqual(message.rendered(language: .korean), "선택 3개 업데이트…")
        XCTAssertEqual(L10n.format("{1} / {0}", arguments: ["{1} %s", "B"]), "B / {1} %s")
    }
    func testStoredMessagesCanBeRenderedInBothLanguages() throws {
        var message = M("실패 (종료 코드 \(7))")
        message += M(" · 결과 재조회 실패")
        let restored = try JSONDecoder().decode(LocalizedMessage.self, from: JSONEncoder().encode(message))
        XCTAssertEqual(restored.rendered(language: .english), "Failed (exit code 7) · Could not verify the result")
        XCTAssertEqual(restored.rendered(language: .korean), "실패 (종료 코드 7) · 결과 재조회 실패")
    }
    func testLegacyHistoryDecodesWithoutLocalizedResult() throws {
        let old = #"{"id":"00000000-0000-0000-0000-000000000001","date":0,"environment":"/brew","command":"brew update","exitCode":0,"result":"명령 완료","changes":[],"log":"raw output"}"#
        let record = try JSONDecoder().decode(OperationRecord.self, from: Data(old.utf8))
        XCTAssertNil(record.localizedResult)
        XCTAssertEqual(record.displayResult, "명령 완료")
        XCTAssertEqual(record.log, "raw output")
    }
}
