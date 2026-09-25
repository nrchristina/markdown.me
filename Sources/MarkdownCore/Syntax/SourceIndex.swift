/// Line table over a document's UTF-8 bytes.
///
/// cmark reports positions as a 1-based line and a 1-based column counted in
/// UTF-8 bytes. The editor works in UTF-16 offsets (`NSString`, `NSTextView`).
/// This type converts between the two and gives byte-level access for scanning
/// Markdown syntax characters, all of which are ASCII.
///
/// Line breaks follow cmark: `\n`, `\r\n` and a lone `\r` each end a line.
final class SourceIndex {
    let bytes: [UInt8]
    let utf16Count: Int

    /// Byte offset where each line starts (0-based line numbers).
    private(set) var lineStarts: [Int] = []
    /// Byte offset where each line's content ends, before its line break.
    private(set) var lineEnds: [Int] = []
    private var lineUTF16Starts: [Int] = []
    private var lineIsASCII: [Bool] = []
    /// Per-line byte → UTF-16 tables, built on first use for non-ASCII lines.
    private var utf16Tables: [[Int]?] = []

    init(_ text: String) {
        let bytes = Array(text.utf8)
        self.bytes = bytes

        var starts = [0]
        var ends: [Int] = []
        var utf16Starts = [0]
        var isASCII: [Bool] = []
        var utf16 = 0
        var lineASCII = true
        var i = 0
        while i < bytes.count {
            let byte = bytes[i]
            if byte == .lineFeed || byte == .carriageReturn {
                var next = i + 1
                if byte == .carriageReturn, next < bytes.count, bytes[next] == .lineFeed {
                    next += 1
                }
                ends.append(i)
                isASCII.append(lineASCII)
                utf16 += next - i
                starts.append(next)
                utf16Starts.append(utf16)
                lineASCII = true
                i = next
                continue
            }
            if byte >= 0x80 { lineASCII = false }
            utf16 += Self.utf16Width(ofByte: byte)
            i += 1
        }
        ends.append(bytes.count)
        isASCII.append(lineASCII)

        lineStarts = starts
        lineEnds = ends
        utf16Tables = Array(repeating: nil, count: starts.count)
        lineUTF16Starts = utf16Starts
        lineIsASCII = isASCII
        utf16Count = utf16
    }

    var lineCount: Int { lineStarts.count }

    /// 0-based index of the line that contains `offset`. A line break belongs to
    /// the line it ends.
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

    /// Byte offset of a cmark position (1-based line, 1-based UTF-8 column).
    ///
    /// cmark sometimes ends a block on its line break; such columns are
    /// clamped to the line's content. A column past the line break means cmark
    /// counted on into the following lines (it does for a table that
    /// interrupts a paragraph), so it is followed there.
    func byteOffset(line: Int, column: Int) -> Int {
        let lineIndex = min(max(line - 1, 0), lineCount - 1)
        let start = lineStarts[lineIndex]
        let length = lineEnds[lineIndex] - start
        let nextLineStart = lineIndex + 1 < lineCount ? lineStarts[lineIndex + 1] : bytes.count
        let relative = max(column - 1, 0)
        if start + relative <= nextLineStart {
            return start + min(relative, length)
        }
        return min(start + relative, bytes.count)
    }

    /// UTF-16 offset of the character that starts at byte `offset`.
    func utf16Offset(atByte offset: Int) -> Int {
        guard offset < bytes.count else { return utf16Count }
        let line = lineIndex(containing: max(offset, 0))
        let start = lineStarts[line]
        let relative = max(offset, 0) - start
        if lineIsASCII[line] {
            return lineUTF16Starts[line] + relative
        }
        let table = utf16Table(forLine: line)
        let contentLength = table.count - 1
        if relative <= contentLength {
            return lineUTF16Starts[line] + table[relative]
        }
        // Inside the line break, which is ASCII.
        return lineUTF16Starts[line] + table[contentLength] + (relative - contentLength)
    }

    func utf16Range(_ byteRange: Range<Int>) -> Range<Int> {
        utf16Offset(atByte: byteRange.lowerBound)..<utf16Offset(atByte: byteRange.upperBound)
    }

    /// 1-based column where a line's text begins: after indentation and up to
    /// `quoteDepth` block quote markers. This is where the text of a paragraph
    /// continuation line or a table row starts.
    func textStartColumn(line: Int, quoteDepth: Int) -> Int {
        guard line >= 1, line <= lineCount else { return 1 }
        let start = lineStarts[line - 1]
        let end = lineEnds[line - 1]
        var position = start
        var quotes = 0
        while true {
            while position < end, bytes[position].isSpaceOrTab {
                position += 1
            }
            if position < end, bytes[position] == .greaterThan, quotes < quoteDepth {
                position += 1
                quotes += 1
                continue
            }
            break
        }
        return position - start + 1
    }

    private func utf16Table(forLine line: Int) -> [Int] {
        if let table = utf16Tables[line] { return table }
        let start = lineStarts[line]
        let end = lineEnds[line]
        var table = [Int]()
        table.reserveCapacity(end - start + 1)
        var units = 0
        for offset in start..<end {
            table.append(units)
            units += Self.utf16Width(ofByte: bytes[offset])
        }
        table.append(units)
        utf16Tables[line] = table
        return table
    }

    /// UTF-16 code units contributed by one UTF-8 byte: a scalar's lead byte
    /// carries its whole width, continuation bytes carry nothing.
    private static func utf16Width(ofByte byte: UInt8) -> Int {
        if byte & 0xC0 == 0x80 { return 0 }
        return byte >= 0xF0 ? 2 : 1
    }
}

extension UInt8 {
    static let lineFeed = UInt8(ascii: "\n")
    static let carriageReturn = UInt8(ascii: "\r")
    static let space = UInt8(ascii: " ")
    static let tab = UInt8(ascii: "\t")
    static let greaterThan = UInt8(ascii: ">")

    var isSpaceOrTab: Bool { self == .space || self == .tab }
}
