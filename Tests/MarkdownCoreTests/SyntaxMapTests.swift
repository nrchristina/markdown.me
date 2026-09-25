import Foundation
import Testing
import MarkdownCore

@Suite("SyntaxMap")
struct SyntaxMapTests {
    @Test func rangesAreUTF16OffsetsForCyrillic() throws {
        let map = SyntaxMap(parsing: "Привет *мир*")
        let emphasis = try #require(map.spans.first)
        #expect(emphasis.kind == .emphasis)
        #expect(emphasis.range == 7..<12)
        #expect(emphasis.contentRange == 8..<11)
        #expect(emphasis.markers == [7..<8, 11..<12])
    }

    @Test func rangesCountSurrogatePairsAsTwoUnits() throws {
        let map = SyntaxMap(parsing: "😀 *e*")
        let emphasis = try #require(map.spans.first)
        #expect(emphasis.range == 3..<6)
        #expect(map.utf16Length == 6)
    }

    @Test func markerRangesAreSortedAndMerged() {
        let map = SyntaxMap(parsing: "> **a** `b`")
        // `> ` and `**` touch, so they merge.
        #expect(map.markerRanges == [0..<4, 5..<7, 8..<9, 10..<11])
    }

    @Test func findsSpansIntersectingARange() {
        let map = SyntaxMap(parsing: "- [ ] x *y*")
        let kinds = map.spans(intersecting: 3..<4).map(\.kind)
        #expect(kinds == [.listItem(ordinal: nil, depth: 0), .taskCheckbox(isChecked: false)])
        #expect(map.spans(intersecting: 9..<10).map(\.kind) == [.listItem(ordinal: nil, depth: 0), .emphasis])
    }

    @Test func emptyAndPlainDocumentsHaveNoSpans() {
        #expect(SyntaxMap(parsing: "").spans.isEmpty)
        #expect(SyntaxMap(parsing: "").utf16Length == 0)
        #expect(SyntaxMap(parsing: "just text\nover two lines").spans.isEmpty)
    }

    @Test func enclosingSpansComeFirst() {
        let kinds = SyntaxMap(parsing: "> - **a**").spans.map(\.kind)
        #expect(kinds == [.blockQuote(depth: 1), .listItem(ordinal: nil, depth: 0), .strong])
    }
}

/// Properties that must hold for any input: Text mode hides `markers`, so a
/// marker must never cover anything but syntax characters of its element.
@Suite("SyntaxMap invariants")
struct SyntaxMapInvariantTests {
    @Test func markersAreSyntaxOnlyInGeneratedDocuments() {
        var generator = DocumentGenerator(seed: 0x4D44_2D35)
        for _ in 0..<400 {
            let document = generator.document()
            let problems = invariantViolations(in: document)
            #expect(problems.isEmpty, "\(document.debugDescription): \(problems)")
        }
    }

    @Test(arguments: [
        "**foo*", "*foo**", "***foo**", "****foo*", "__foo_", "_foo____",
        "# ~*с*", "# ~", "#\n\n# #", "~a~ ~~b~~ ~~~c~~~",
        "[foo]: /url\n===\n[foo]", "a\\\n  b *c*", "> a\\\n>   *b*",
        "| a | b |\n|---|---|\n| \\| *x* | y |", "- > a||\n  >-|-\n  >ё",
    ])
    func markersAreSyntaxOnlyInEdgeCases(_ document: String) {
        #expect(invariantViolations(in: document).isEmpty)
    }
}

private func invariantViolations(in source: String) -> [String] {
    var problems: [String] = []
    for span in SyntaxMap(parsing: source).spans {
        let rendered = RenderedSpan(span, in: source)
        if !(span.range.lowerBound <= span.contentRange.lowerBound && span.contentRange.upperBound <= span.range.upperBound) {
            problems.append("content outside range: \(rendered)")
        }
        for marker in span.markers {
            if !(span.range.lowerBound <= marker.lowerBound && marker.upperBound <= span.range.upperBound) {
                problems.append("marker outside range: \(rendered)")
            }
            if span.kind.isQuote == false, marker.overlaps(span.contentRange) {
                problems.append("marker overlaps content: \(rendered)")
            }
            let text = source[utf16: marker]
            if !span.kind.allowsMarker(text) {
                problems.append("unexpected marker \(text.debugDescription): \(rendered)")
            }
        }
    }
    return problems
}

extension SyntaxKind {
    fileprivate var isQuote: Bool {
        if case .blockQuote = self { return true }
        return false
    }

    fileprivate func allowsMarker(_ marker: String) -> Bool {
        func matches(_ pattern: String) -> Bool {
            (try? Regex(pattern).wholeMatch(in: marker)) != nil
        }
        switch self {
        case .emphasis: return matches("[*_]")
        case .strong: return matches(#"\*\*|__"#)
        case .strikethrough: return matches("~~?")
        case .inlineCode: return matches("`+")
        case .heading: return matches(#"#{1,6}[ \t]*|[ \t]*#+|=+|-+"#)
        case .blockQuote: return matches(#">[ \t]?"#)
        case .listItem: return matches(#"([-+*]|[0-9]{1,9}[.)])[ \t]*"#)
        case .taskCheckbox: return matches(#"\[[ xX]\]"#)
        case .thematicBreak: return matches(#"[-*_ \t]+"#)
        case .codeBlock: return matches("(`{3,}|~{3,}).*")
        case .link: return marker == "[" || marker == "<" || marker == ">" || marker.hasPrefix("]") || marker.hasPrefix("[")
        case .image: return marker == "![" || marker.hasPrefix("]") || marker.hasPrefix("![")
        case .table, .inlineHTML, .htmlBlock: return false
        }
    }
}

/// Deterministic random Markdown: nested quotes and lists, tables, code,
/// every inline element, Cyrillic and emoji, CRLF and backslash breaks.
struct DocumentGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func document() -> String {
        var blocks: [String] = []
        for _ in 0..<int(1...6) {
            blocks.append(block(depth: 0))
        }
        let text = blocks.joined(separator: "\n\n") + "\n"
        return int(0...4) == 0 ? text.replacingOccurrences(of: "\n", with: "\r\n") : text
    }

    private mutating func block(depth: Int) -> String {
        switch depth < 3 ? int(0...9) : 0 {
        case 1:
            return String(repeating: "#", count: int(1...6)) + " " + inline() + pick(["", " ##"])
        case 2:
            // Quote every line, leaving some later lines lazy.
            let lines = block(depth: depth + 1).components(separatedBy: "\n")
            var quoted: [String] = []
            for (offset, line) in lines.enumerated() {
                if offset == 0 || int(0...4) > 0 {
                    quoted.append(">" + pick([" ", ""]) + line)
                } else {
                    quoted.append(line)
                }
            }
            return quoted.joined(separator: "\n")
        case 3:
            let ordered = int(0...1) == 0
            var items: [String] = []
            for number in 0..<int(1...3) {
                let marker = ordered ? "\(number + 1)." : pick(["-", "*", "+"])
                let indent = String(repeating: " ", count: marker.count + 1)
                let lines = block(depth: depth + 1).components(separatedBy: "\n")
                var item = marker + " " + pick(["", "", "[ ] ", "[x] "]) + lines[0]
                for line in lines.dropFirst() {
                    item += "\n" + (line.isEmpty ? line : indent + line)
                }
                items.append(item)
            }
            return items.joined(separator: "\n")
        case 4:
            return pick(["```", "~~~", "````"]) + pick(["", "swift"]) + "\n" + inline() + "\n" + pick(["```", "~~~", "````"])
        case 5:
            return pick(["---", "***", "* * *"])
        case 6:
            return inline() + "\n" + pick(["===", "---"])
        case 7:
            return "| a | b |\n|---|:-:|\n| " + inline().replacingOccurrences(of: "|", with: "") + " | x\\|y |"
        case 8:
            return "    " + inline()
        default:
            let separator = pick(["\n", "\n", "  \n", "\\\n"])
            var lines: [String] = []
            for _ in 0..<int(1...3) {
                lines.append(inline())
            }
            return lines.joined(separator: separator)
        }
    }

    private mutating func inline(depth: Int = 0) -> String {
        var parts: [String] = []
        for _ in 0..<int(1...5) {
            let word = pick(["слово", "word", "😀", "👨‍👩‍👧", "ё", "abc", "текст", "x"])
            switch depth < 2 ? int(0...11) : 0 {
            case 1: parts.append("*\(inline(depth: depth + 1))*")
            case 2: parts.append("**\(inline(depth: depth + 1))**")
            case 3: parts.append("~~\(inline(depth: depth + 1))~~")
            case 4: parts.append("`\(word)`")
            case 5: parts.append("[\(inline(depth: depth + 1))](http://e.com/\(word))")
            case 6: parts.append("![\(word)](i/\(word).png)")
            case 7: parts.append("<span style=\"color: red\">\(word)</span>")
            case 8: parts.append("<https://x.y/\(int(0...9))>")
            case 9: parts.append("_\(word)_")
            default: parts.append(word)
            }
        }
        return parts.joined(separator: " ")
    }

    private mutating func pick(_ options: [String]) -> String {
        options[int(0...(options.count - 1))]
    }

    /// SplitMix64.
    private mutating func int(_ range: ClosedRange<Int>) -> Int {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        value ^= value >> 31
        return range.lowerBound + Int(value % UInt64(range.count))
    }
}
