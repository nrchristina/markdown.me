import Testing
import MarkdownCore

private let caretMark = "‸".utf16.first!
private let selectionStartMark = "«".utf16.first!
private let selectionEndMark = "»".utf16.first!

/// Text with its selection written into it: `‸` is a caret, `«` and `»`
/// surround a selection.
func unmarked(_ marked: String) -> (text: String, selection: Range<Int>) {
    var units = Array(marked.utf16)
    if let caret = units.firstIndex(of: caretMark) {
        units.remove(at: caret)
        return (String(decoding: units, as: UTF16.self), caret..<caret)
    }
    let start = units.firstIndex(of: selectionStartMark)!
    units.remove(at: start)
    let end = units.firstIndex(of: selectionEndMark)!
    units.remove(at: end)
    return (String(decoding: units, as: UTF16.self), start..<end)
}

func marked(_ text: String, _ selection: Range<Int>) -> String {
    var units = Array(text.utf16)
    if selection.isEmpty {
        units.insert(caretMark, at: selection.lowerBound)
    } else {
        units.insert(selectionEndMark, at: selection.upperBound)
        units.insert(selectionStartMark, at: selection.lowerBound)
    }
    return String(decoding: units, as: UTF16.self)
}

/// Runs `edit` on marked text and returns the edited text, marked the same
/// way; nil when `edit` returns nil. Also checks that the edit is minimal.
func run(
    _ input: String,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ edit: (String, Range<Int>) -> TextEdit?
) -> String? {
    let (text, selection) = unmarked(input)
    guard let result = edit(text, selection) else { return nil }
    let replaced = Array(text.utf16)[result.range]
    let replacement = Array(result.replacement.utf16)
    if !replaced.isEmpty, !replacement.isEmpty {
        #expect(replaced.first != replacement.first && replaced.last != replacement.last,
                "Not minimal: \(result)", sourceLocation: sourceLocation)
    }
    let edited = result.applied(to: text)
    #expect(result.selection.upperBound <= edited.utf16.count, sourceLocation: sourceLocation)
    return marked(edited, result.selection)
}

func apply(_ command: FormattingCommand, _ input: String, sourceLocation: SourceLocation = #_sourceLocation) -> String? {
    run(input, sourceLocation: sourceLocation) { command.edit(in: $0, selection: $1) }
}

/// A command with marked input and the marked result it should give.
struct CommandCase: Sendable, CustomStringConvertible {
    var command: FormattingCommand
    var input: String
    var expected: String

    init(_ command: FormattingCommand, _ input: String, _ expected: String) {
        self.command = command
        self.input = input
        self.expected = expected
    }

    var description: String {
        "\(command) on \(input.debugDescription)"
    }
}
