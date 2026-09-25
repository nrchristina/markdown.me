import Testing
import MarkdownCore

/// Every command on generated documents, with carets and selections at
/// random character boundaries: no crash, and every edit is well formed.
@Suite("Editing on generated documents")
struct EditingFuzzTests {
    private static let commands: [FormattingCommand] = [
        .bold, .italic, .strikethrough, .inlineCode, .heading(level: 2), .paragraph,
        .bulletList, .numberedList, .taskList, .blockquote, .codeBlock, .link, .image, .horizontalRule,
    ]

    @Test func editsAreWellFormed() {
        var generator = DocumentGenerator(seed: 0x4D44_2D37)
        var random = SplitMix(seed: 7)
        for _ in 0..<150 {
            let text = generator.document()
            // Offsets between characters, so a selection never splits an
            // emoji or a CRLF.
            let boundaries = text.indices.map { $0.utf16Offset(in: text) } + [text.utf16.count]
            for _ in 0..<3 {
                let first = boundaries[random.next(boundaries.count)]
                let second = random.next(3) == 0 ? first : boundaries[random.next(boundaries.count)]
                let selection = min(first, second)..<max(first, second)
                for command in Self.commands {
                    check(command.edit(in: text, selection: selection), text, "\(command)", selection)
                }
                check(ListEditing.newline(in: text, selection: selection), text, "newline", selection)
                check(ListEditing.indent(in: text, selection: selection), text, "indent", selection)
                check(ListEditing.outdent(in: text, selection: selection), text, "outdent", selection)
                check(ListEditing.toggleCheckbox(in: text, at: first, selection: selection), text, "checkbox", selection)
            }
        }
    }

    private func check(_ edit: TextEdit?, _ text: String, _ name: String, _ selection: Range<Int>) {
        guard let edit else { return }
        let units = Array(text.utf16)
        let context = "\(name) at \(selection) in \(text.debugDescription)"
        guard edit.range.lowerBound >= 0, edit.range.upperBound <= units.count else {
            Issue.record("Range \(edit.range) out of bounds: \(context)")
            return
        }
        let replaced = units[edit.range]
        let replacement = Array(edit.replacement.utf16)
        if !replaced.isEmpty, !replacement.isEmpty {
            #expect(replaced.first != replacement.first && replaced.last != replacement.last, "Not minimal: \(context)")
        }
        for bound in [edit.range.lowerBound, edit.range.upperBound] where bound < units.count {
            #expect(!UTF16.isTrailSurrogate(units[bound]), "Splits a surrogate pair: \(context)")
        }
        let edited = edit.applied(to: text)
        #expect(edit.selection.upperBound <= edited.utf16.count, "Selection out of bounds: \(context)")
        #expect(!edited.unicodeScalars.contains("\u{FFFD}") || text.unicodeScalars.contains("\u{FFFD}"),
                "Broken UTF-16: \(context)")
    }
}

/// SplitMix64, for reproducible random choices.
struct SplitMix {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    /// A number in `0..<upperBound`.
    mutating func next(_ upperBound: Int) -> Int {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        value ^= value >> 31
        return Int(value % UInt64(upperBound))
    }
}
