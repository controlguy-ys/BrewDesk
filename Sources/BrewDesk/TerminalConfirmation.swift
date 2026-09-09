import Foundation

struct TerminalConfirmation: Identifiable {
    let id = UUID()
    let question: String
    let usesFullWords: Bool
    func response(yes: Bool) -> String {
        (usesFullWords ? (yes ? "yes" : "no") : (yes ? "y" : "n")) + "\n"
    }
}

/// Only an explicit yes/no marker on the unfinished terminal line is eligible.
struct TerminalConfirmationDetector {
    private(set) var buffer = ""
    mutating func reset() { buffer = "" }
    mutating func append(_ text: String) { buffer += text; buffer = String(buffer.suffix(4096)) }
    var confirmation: TerminalConfirmation? {
        let clean = buffer.replacingOccurrences(of: #"\x1B\[[0-?]*[ -/]*[@-~]"#, with: "", options: .regularExpression)
        guard let line = clean.components(separatedBy: .newlines).last else { return nil }
        let question = line.trimmingCharacters(in: .whitespaces)
        guard !question.isEmpty, question.count <= 600 else { return nil }
        let pattern = #"(?i)(\[\s*(y\s*/\s*n|n\s*/\s*y|yes\s*/\s*no|no\s*/\s*yes)\s*\]|\(\s*(y\s*/\s*n|n\s*/\s*y|yes\s*/\s*no|no\s*/\s*yes)\s*\))\s*[:?]?\s*$"#
        guard let range = question.range(of: pattern, options: .regularExpression) else { return nil }
        return TerminalConfirmation(question: question, usesFullWords: question[range].lowercased().contains("yes"))
    }
}
