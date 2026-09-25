import Testing
@testable import MarkdownCore

@Suite("SourceIndex")
struct SourceIndexTests {
    @Test func splitsLinesOnLineFeedCRLFAndCarriageReturn() {
        let index = SourceIndex("a\r\nb\rc\nd")
        #expect(index.lineStarts == [0, 3, 5, 7])
        #expect(index.lineEnds == [1, 4, 6, 8])
        #expect(index.lineIndex(containing: 1) == 0)
        #expect(index.lineIndex(containing: 2) == 0)
        #expect(index.lineIndex(containing: 3) == 1)
    }

    @Test func convertsUTF8OffsetsToUTF16() {
        // а, б: 2 bytes, 1 unit each. 😀: 4 bytes, 2 units.
        let index = SourceIndex("аб\n😀x")
        #expect(index.utf16Count == 6)
        #expect(index.utf16Offset(atByte: 0) == 0)
        #expect(index.utf16Offset(atByte: 2) == 1)
        #expect(index.utf16Offset(atByte: 4) == 2)
        #expect(index.utf16Offset(atByte: 5) == 3)
        #expect(index.utf16Offset(atByte: 9) == 5)
        #expect(index.utf16Offset(atByte: 10) == 6)
    }

    @Test func convertsZWJSequencesByScalars() {
        // 👨‍👩‍👧 is three 4-byte scalars joined by two 3-byte ZWJs: 18 bytes, 8 units.
        let index = SourceIndex("👨‍👩‍👧 x")
        #expect(index.utf16Offset(atByte: 18) == 8)
        #expect(index.utf16Offset(atByte: 19) == 9)
    }

    @Test func clampsColumnsThatEndOnTheLineBreak() {
        let index = SourceIndex("abc\ndef")
        #expect(index.byteOffset(line: 1, column: 4) == 3)
        #expect(index.byteOffset(line: 1, column: 5) == 3)
        #expect(index.byteOffset(line: 2, column: 1) == 4)
    }

    @Test func followsColumnsPastTheLineBreakIntoLaterLines() {
        // cmark does this for a table that interrupts a paragraph.
        let index = SourceIndex("ab\ncdef")
        #expect(index.byteOffset(line: 1, column: 6) == 5)
    }

    @Test func findsWhereALinesTextStarts() {
        let index = SourceIndex(">  > x\n   y\nz\n>\t\tw")
        #expect(index.textStartColumn(line: 1, quoteDepth: 2) == 6)
        #expect(index.textStartColumn(line: 1, quoteDepth: 1) == 4)
        #expect(index.textStartColumn(line: 2, quoteDepth: 1) == 4)
        #expect(index.textStartColumn(line: 3, quoteDepth: 0) == 1)
        // Tabs count as one byte each.
        #expect(index.textStartColumn(line: 4, quoteDepth: 1) == 4)
    }
}
