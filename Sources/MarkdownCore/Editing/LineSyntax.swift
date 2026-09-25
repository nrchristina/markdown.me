/// The block syntax at the start of one line, read from the line alone:
/// block quote markers, indentation, a list marker with its task checkbox,
/// an ATX heading marker.
///
/// Commands that work on whole lines need exactly this, including for lines
/// that are not list items or headings yet, which a parse of the document
/// cannot tell them.
struct LineSyntax {
    enum ListKind: Equatable {
        case bullet(UInt16)
        case ordered(number: Int, delimiter: UInt16)
    }

    enum ListType: Equatable {
        case bullet
        case ordered
        case task
    }

    struct ListMarker {
        var kind: ListKind
        /// `-` or `12.`
        var symbol: Range<Int>
        /// After the whitespace that follows the symbol.
        var end: Int
    }

    struct Checkbox {
        /// `[ ]`
        var range: Range<Int>
        var isChecked: Bool
        /// After the whitespace that follows the brackets.
        var end: Int
    }

    struct Heading {
        var level: Int
        /// The `#`s.
        var marker: Range<Int>
        /// After the whitespace that follows the `#`s.
        var end: Int
        /// An optional closing sequence, ` ##`, with the whitespace before it.
        var closing: Range<Int>?
    }

    let line: Int
    let start: Int
    let end: Int
    private(set) var quoteDepth = 0
    /// After the `>` markers and the space that follows each.
    private(set) var quoteEnd: Int
    /// After the whitespace that follows the quote markers.
    private(set) var indentEnd: Int
    /// Width of that whitespace in columns, tabs stopping at multiples of 4.
    private(set) var indent = 0
    private(set) var list: ListMarker?
    private(set) var checkbox: Checkbox?
    private(set) var heading: Heading?

    init(_ buffer: TextBuffer, line: Int) {
        let units = buffer.units
        self.line = line
        start = buffer.lineStarts[line]
        end = buffer.lineEnds[line]

        // `>`, after up to three spaces, and one space after it.
        var position = start
        while true {
            var probe = position
            while probe < end, probe - position < 3, units[probe] == .space {
                probe += 1
            }
            guard probe < end, units[probe] == .greaterThan else { break }
            probe += 1
            if probe < end, units[probe].isSpaceOrTab {
                probe += 1
            }
            position = probe
            quoteDepth += 1
        }
        quoteEnd = position

        var column = 0
        while position < end, units[position].isSpaceOrTab {
            column = units[position] == .tab ? (column / 4 + 1) * 4 : column + 1
            position += 1
        }
        indentEnd = position
        indent = column

        if !Self.isThematicBreak(units[position..<end]) {
            list = Self.listMarker(units, at: position, end: end)
        }
        if let list {
            checkbox = Self.checkbox(units, after: list, end: end)
            heading = Self.heading(units, at: checkbox?.end ?? list.end, end: end)
        } else if column <= 3 {
            heading = Self.heading(units, at: position, end: end)
        }
    }

    /// Nothing but quote markers and whitespace.
    var isEmpty: Bool {
        indentEnd == end
    }

    /// Where the line's own text begins, after all the syntax above.
    var textStart: Int {
        heading?.end ?? checkbox?.end ?? list?.end ?? indentEnd
    }

    var listType: ListType? {
        guard let list else { return nil }
        if checkbox != nil {
            return .task
        }
        switch list.kind {
        case .bullet:
            return .bullet
        case .ordered:
            return .ordered
        }
    }

    // MARK: - Parsing

    private static func isThematicBreak(_ units: ArraySlice<UInt16>) -> Bool {
        var character: UInt16?
        var count = 0
        for unit in units where !unit.isSpaceOrTab {
            guard unit == .hyphen || unit == .asterisk || unit == .underscore,
                  character == nil || character == unit else { return false }
            character = unit
            count += 1
        }
        return count >= 3
    }

    /// `-`, `*`, `+`, or up to nine digits and `.` or `)`, followed by
    /// whitespace or the end of the line.
    private static func listMarker(_ units: [UInt16], at start: Int, end: Int) -> ListMarker? {
        guard start < end else { return nil }
        let first = units[start]
        let kind: ListKind
        var symbolEnd = start
        if first == .hyphen || first == .asterisk || first == .plus {
            kind = .bullet(first)
            symbolEnd += 1
        } else {
            var number = 0
            while symbolEnd < end, symbolEnd - start < 9, units[symbolEnd].isASCIIDigit {
                number = number * 10 + Int(units[symbolEnd] - UInt16(ascii: "0"))
                symbolEnd += 1
            }
            guard symbolEnd > start, symbolEnd < end,
                  units[symbolEnd] == .period || units[symbolEnd] == .closingParenthesis else { return nil }
            kind = .ordered(number: number, delimiter: units[symbolEnd])
            symbolEnd += 1
        }
        guard symbolEnd == end || units[symbolEnd].isSpaceOrTab else { return nil }

        var markerEnd = symbolEnd
        while markerEnd < end, units[markerEnd].isSpaceOrTab {
            markerEnd += 1
        }
        // Text indented further than that is code inside the item, so only
        // one space belongs to the marker.
        if markerEnd < end, markerEnd - symbolEnd > 4 {
            markerEnd = symbolEnd + 1
        }
        return ListMarker(kind: kind, symbol: start..<symbolEnd, end: markerEnd)
    }

    private static func checkbox(_ units: [UInt16], after list: ListMarker, end: Int) -> Checkbox? {
        let start = list.end
        guard start > list.symbol.upperBound, start + 3 <= end,
              units[start] == .openingBracket, units[start + 2] == .closingBracket else { return nil }
        let mark = units[start + 1]
        guard mark == .space || mark == .lowercaseX || mark == .uppercaseX else { return nil }
        let boxEnd = start + 3
        guard boxEnd == end || units[boxEnd].isSpaceOrTab else { return nil }
        var textStart = boxEnd
        while textStart < end, units[textStart].isSpaceOrTab {
            textStart += 1
        }
        return Checkbox(range: start..<boxEnd, isChecked: mark != .space, end: textStart)
    }

    private static func heading(_ units: [UInt16], at start: Int, end: Int) -> Heading? {
        var hashesEnd = start
        while hashesEnd < end, units[hashesEnd] == .numberSign {
            hashesEnd += 1
        }
        let level = hashesEnd - start
        guard (1...6).contains(level), hashesEnd == end || units[hashesEnd].isSpaceOrTab else { return nil }
        var textStart = hashesEnd
        while textStart < end, units[textStart].isSpaceOrTab {
            textStart += 1
        }

        // A closing run of `#`s, alone or after whitespace, then only whitespace.
        var contentEnd = end
        while contentEnd > textStart, units[contentEnd - 1].isSpaceOrTab {
            contentEnd -= 1
        }
        var hashesStart = contentEnd
        while hashesStart > textStart, units[hashesStart - 1] == .numberSign {
            hashesStart -= 1
        }
        var closing: Range<Int>?
        if hashesStart < contentEnd {
            if hashesStart == textStart {
                closing = hashesStart..<end
            } else if units[hashesStart - 1].isSpaceOrTab {
                var closingStart = hashesStart
                while closingStart > textStart, units[closingStart - 1].isSpaceOrTab {
                    closingStart -= 1
                }
                closing = closingStart..<end
            }
        }
        return Heading(level: level, marker: start..<hashesEnd, end: textStart, closing: closing)
    }
}
