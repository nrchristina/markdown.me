/// A document as UTF-16 code units with a line table: the units and offsets
/// the editor's selection uses.
///
/// Line breaks follow cmark: `\n`, `\r\n` and a lone `\r` each end a line.
struct TextBuffer {
    let units: [UInt16]
    /// Offset where each line starts (0-based line numbers).
    let lineStarts: [Int]
    /// Offset where each line's content ends, before its line break.
    let lineEnds: [Int]
    /// The line break for new lines: the one the document already uses.
    let lineBreak: [UInt16]

    init(_ text: String) {
        let units = Array(text.utf16)
        var starts = [0]
        var ends: [Int] = []
        var lineBreak: [UInt16]?
        var index = 0
        while index < units.count {
            let unit = units[index]
            if unit == .lineFeed || unit == .carriageReturn {
                var next = index + 1
                if unit == .carriageReturn, next < units.count, units[next] == .lineFeed {
                    next += 1
                }
                if lineBreak == nil {
                    lineBreak = Array(units[index..<next])
                }
                ends.append(index)
                starts.append(next)
                index = next
            } else {
                index += 1
            }
        }
        ends.append(units.count)

        self.units = units
        lineStarts = starts
        lineEnds = ends
        self.lineBreak = lineBreak ?? [.lineFeed]
    }

    var count: Int { units.count }
    var lineCount: Int { lineStarts.count }

    func clamp(_ range: Range<Int>) -> Range<Int> {
        let lower = min(max(range.lowerBound, 0), units.count)
        return lower..<min(max(range.upperBound, lower), units.count)
    }

    /// 0-based line that contains `offset`; a line break belongs to the line it ends.
    func lineIndex(containing offset: Int) -> Int {
        var low = 0
        var high = lineStarts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lineStarts[mid] <= offset {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return low
    }

    /// Start of the line after `line`, or the end of the text.
    func nextLineStart(_ line: Int) -> Int {
        line + 1 < lineCount ? lineStarts[line + 1] : units.count
    }

    /// Lines a selection touches. A selection that ends at the very start of a
    /// line does not include that line.
    func lines(in selection: Range<Int>) -> ClosedRange<Int> {
        let first = lineIndex(containing: selection.lowerBound)
        var last = lineIndex(containing: selection.upperBound)
        if last > first, selection.upperBound == lineStarts[last] {
            last -= 1
        }
        return first...last
    }

    /// Whether the line has nothing but spaces and tabs.
    func isBlank(_ line: Int) -> Bool {
        units[lineStarts[line]..<lineEnds[line]].allSatisfy(\.isSpaceOrTab)
    }

    func line(_ index: Int) -> LineSyntax {
        LineSyntax(self, line: index)
    }

    /// `range` without leading and trailing whitespace and line breaks.
    func trimmed(_ range: Range<Int>) -> Range<Int> {
        var lower = range.lowerBound
        var upper = range.upperBound
        while lower < upper, units[lower].isWhitespace {
            lower += 1
        }
        while upper > lower, units[upper - 1].isWhitespace {
            upper -= 1
        }
        return lower..<upper
    }

    /// Length of the run of `unit` that ends at `offset`.
    func run(of unit: UInt16, endingAt offset: Int) -> Int {
        var start = offset
        while start > 0, units[start - 1] == unit {
            start -= 1
        }
        return offset - start
    }

    /// Length of the run of `unit` that starts at `offset`.
    func run(of unit: UInt16, startingAt offset: Int) -> Int {
        var end = offset
        while end < units.count, units[end] == unit {
            end += 1
        }
        return end - offset
    }

    /// Length of the longest run of `unit` inside `range`.
    func longestRun(of unit: UInt16, in range: Range<Int>) -> Int {
        var longest = 0
        var current = 0
        for index in range {
            current = units[index] == unit ? current + 1 : 0
            longest = max(longest, current)
        }
        return longest
    }

    // MARK: - Words

    /// The word at a caret: letters, digits and combining marks around
    /// `offset`, joined by apostrophes or underscores. Nil between words.
    func word(at offset: Int) -> Range<Int>? {
        var lower = offset
        var upper = offset
        while let previous = scalar(endingAt: lower) {
            let joinsWords = previous.value.isWordConnector
                && isWordCharacter(startingAt: lower)
                && isWordCharacter(endingAt: previous.bound)
            guard previous.value.isWordCharacter || previous.value.isMark || joinsWords else { break }
            lower = previous.bound
        }
        while let next = scalar(startingAt: upper) {
            let joinsWords = next.value.isWordConnector
                && isWordCharacter(endingAt: upper)
                && isWordCharacter(startingAt: next.bound)
            guard next.value.isWordCharacter || next.value.isMark || joinsWords else { break }
            upper = next.bound
        }
        // A mark with no letter before it is not a word, as in the variation
        // selector after an emoji.
        while lower < upper, let first = scalar(startingAt: lower), !first.value.isWordCharacter {
            lower = first.bound
        }
        return lower < upper ? lower..<upper : nil
    }

    private struct FoundScalar {
        var value: Unicode.Scalar
        /// Where the scalar ends when searching forward, starts when searching back.
        var bound: Int
    }

    private func isWordCharacter(startingAt offset: Int) -> Bool {
        scalar(startingAt: offset)?.value.isWordCharacter ?? false
    }

    private func isWordCharacter(endingAt offset: Int) -> Bool {
        scalar(endingAt: offset)?.value.isWordCharacter ?? false
    }

    private func scalar(startingAt offset: Int) -> FoundScalar? {
        guard offset >= 0, offset < units.count else { return nil }
        let unit = units[offset]
        if UTF16.isLeadSurrogate(unit), offset + 1 < units.count, UTF16.isTrailSurrogate(units[offset + 1]) {
            return FoundScalar(value: Self.scalar(lead: unit, trail: units[offset + 1]), bound: offset + 2)
        }
        return FoundScalar(value: Unicode.Scalar(unit) ?? "\u{FFFD}", bound: offset + 1)
    }

    private func scalar(endingAt offset: Int) -> FoundScalar? {
        guard offset > 0, offset <= units.count else { return nil }
        let unit = units[offset - 1]
        if UTF16.isTrailSurrogate(unit), offset >= 2, UTF16.isLeadSurrogate(units[offset - 2]) {
            return FoundScalar(value: Self.scalar(lead: units[offset - 2], trail: unit), bound: offset - 2)
        }
        return FoundScalar(value: Unicode.Scalar(unit) ?? "\u{FFFD}", bound: offset - 1)
    }

    private static func scalar(lead: UInt16, trail: UInt16) -> Unicode.Scalar {
        let value = 0x10000 + ((UInt32(lead) - 0xD800) << 10) + (UInt32(trail) - 0xDC00)
        return Unicode.Scalar(value) ?? "\u{FFFD}"
    }
}

private extension Unicode.Scalar {
    var isWordCharacter: Bool {
        properties.isAlphabetic || properties.numericType != nil
    }

    var isMark: Bool {
        switch properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark:
            return true
        default:
            return false
        }
    }

    /// Joins two words into one: `don't`, `snake_case`.
    var isWordConnector: Bool {
        self == "'" || self == "\u{2019}" || self == "_"
    }
}

extension UInt16 {
    init(ascii scalar: Unicode.Scalar) {
        self = UInt16(scalar.value)
    }

    static let lineFeed = UInt16(ascii: "\n")
    static let carriageReturn = UInt16(ascii: "\r")
    static let space = UInt16(ascii: " ")
    static let tab = UInt16(ascii: "\t")
    static let greaterThan = UInt16(ascii: ">")
    static let hyphen = UInt16(ascii: "-")
    static let plus = UInt16(ascii: "+")
    static let asterisk = UInt16(ascii: "*")
    static let underscore = UInt16(ascii: "_")
    static let tilde = UInt16(ascii: "~")
    static let backtick = UInt16(ascii: "`")
    static let numberSign = UInt16(ascii: "#")
    static let period = UInt16(ascii: ".")
    static let closingParenthesis = UInt16(ascii: ")")
    static let openingBracket = UInt16(ascii: "[")
    static let closingBracket = UInt16(ascii: "]")
    static let exclamationMark = UInt16(ascii: "!")
    static let lowercaseX = UInt16(ascii: "x")
    static let uppercaseX = UInt16(ascii: "X")

    var isSpaceOrTab: Bool { self == .space || self == .tab }
    var isWhitespace: Bool { isSpaceOrTab || self == .lineFeed || self == .carriageReturn }
    var isASCIIDigit: Bool { self >= UInt16(ascii: "0") && self <= UInt16(ascii: "9") }
}

extension Array where Element == UInt16 {
    init(_ string: String) {
        self.init(string.utf16)
    }
}
