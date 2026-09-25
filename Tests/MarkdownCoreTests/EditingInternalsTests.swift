import Testing
@testable import MarkdownCore

@Suite("TextEdit and EditBuilder")
struct EditBuilderTests {
    @Test func appliesInUTF16Offsets() {
        let edit = TextEdit(range: 3..<3, replacement: "**", selection: 5..<5)
        #expect(edit.applied(to: "😀 a") == "😀 **a")
        #expect(edit.changesText)
        #expect(!TextEdit(range: 1..<1, replacement: "", selection: 0..<0).changesText)
    }

    @Test func joinsChangesIntoOneMinimalEdit() throws {
        var builder = EditBuilder(TextBuffer("# Title"))
        builder.replace(0..<1, with: [UInt16]("##"))
        let edit = try #require(builder.textEdit(selection: 0..<0))
        #expect(edit.range == 1..<1)
        #expect(edit.replacement == "#")

        builder = EditBuilder(TextBuffer("a b c"))
        builder.insert([UInt16]("*"), at: 0)
        builder.insert([UInt16]("*"), at: 5)
        let wrapped = try #require(builder.textEdit(selection: 0..<0))
        #expect(wrapped.range == 0..<5)
        #expect(wrapped.replacement == "*a b c*")
    }

    @Test func neverSplitsASurrogatePair() throws {
        // 😀 and 😃 share their first UTF-16 unit.
        var builder = EditBuilder(TextBuffer("😀a"))
        builder.replace(0..<2, with: [UInt16]("😃"))
        let edit = try #require(builder.textEdit(selection: 0..<0))
        #expect(edit.range == 0..<2)
        #expect(edit.replacement == "😃")
    }

    @Test func returnsNilWhenNothingChanges() {
        var builder = EditBuilder(TextBuffer("abc"))
        builder.replace(0..<1, with: [UInt16]("a"))
        #expect(builder.isEmpty)
        #expect(builder.textEdit(selection: 0..<0) == nil)
    }

    @Test func mapsOffsetsThroughChanges() {
        var builder = EditBuilder(TextBuffer("abcdef"))
        builder.insert([UInt16]("**"), at: 2)
        builder.delete(4..<5)
        #expect(builder.map(1, .after) == 1)
        #expect(builder.map(2, .before) == 2)
        #expect(builder.map(2, .after) == 4)
        #expect(builder.map(3, .before) == 5)
        // Inside deleted text: where it was.
        #expect(builder.map(4, .after) == 6)
        #expect(builder.map(5, .before) == 6)
        #expect(builder.map(6, .after) == 7)
    }
}

@Suite("TextBuffer")
struct TextBufferTests {
    @Test func findsLinesASelectionTouches() {
        let buffer = TextBuffer("ab\ncd\r\nef")
        #expect(buffer.lineStarts == [0, 3, 7])
        #expect(buffer.lineEnds == [2, 5, 9])
        #expect(buffer.lineBreak == [UInt16]("\n"))
        #expect(buffer.lines(in: 1..<1) == 0...0)
        #expect(buffer.lines(in: 1..<4) == 0...1)
        // Ending at the start of a line does not take that line.
        #expect(buffer.lines(in: 0..<3) == 0...0)
        #expect(buffer.lines(in: 3..<3) == 1...1)
        #expect(TextBuffer("a\r\nb").lineBreak == [UInt16]("\r\n"))
    }

    @Test(arguments: [
        ("hello world", 2, "hello"),
        ("hello world", 5, "hello"),
        ("hello world", 6, "world"),
        ("Привет, мир", 3, "Привет"),
        ("Привет, мир", 7, nil),
        ("don't stop", 2, "don't"),
        ("'quoted'", 3, "quoted"),
        ("snake_case", 3, "snake_case"),
        ("__init__", 4, "init"),
        ("😀 x", 2, nil),
        ("a😀b", 1, "a"),
        ("12:30", 1, "12"),
        ("и\u{0306}ти", 1, "и\u{0306}ти"),
    ] as [(text: String, offset: Int, word: String?)])
    func findsTheWordAtACaret(_ testCase: (text: String, offset: Int, word: String?)) {
        let buffer = TextBuffer(testCase.text)
        let found = buffer.word(at: testCase.offset).map { String(decoding: buffer.units[$0], as: UTF16.self) }
        #expect(found == testCase.word)
    }
}

@Suite("LineSyntax")
struct LineSyntaxTests {
    private func syntax(_ line: String) -> LineSyntax {
        TextBuffer(line).line(0)
    }

    @Test func readsQuotesIndentationAndListMarkers() throws {
        let line = syntax("> >   12) [x] text")
        #expect(line.quoteDepth == 2)
        #expect(line.quoteEnd == 4)
        #expect(line.indent == 2)
        let list = try #require(line.list)
        #expect(list.kind == .ordered(number: 12, delimiter: .closingParenthesis))
        #expect(list.symbol == 6..<9)
        #expect(line.checkbox?.isChecked == true)
        #expect(line.listType == .task)
        #expect(line.textStart == 14)
    }

    @Test func readsHeadings() throws {
        let heading = try #require(syntax("## Title ##").heading)
        #expect(heading.level == 2)
        #expect(heading.marker == 0..<2)
        #expect(heading.end == 3)
        #expect(heading.closing == 8..<11)
        #expect(syntax("# C#").heading?.closing == nil)
        #expect(syntax("#hashtag").heading == nil)
        #expect(syntax("####### seven").heading == nil)
        #expect(syntax("- # In a list").heading?.level == 1)
        #expect(syntax("    # code").heading == nil)
    }

    @Test(arguments: ["---", "* * *", "**bold**", "-x", "1.5 kg", "1234567890. big"])
    func notListItems(line: String) {
        #expect(syntax(line).list == nil)
    }

    @Test func tabsIndentToMultiplesOfFour() {
        #expect(syntax("\t- a").indent == 4)
        #expect(syntax("  \t- a").indent == 4)
        #expect(syntax(" \t  - a").indent == 6)
    }

    @Test func emptyLinesInQuotes() {
        #expect(syntax(">").isEmpty)
        #expect(syntax("> ").isEmpty)
        #expect(!syntax("> -").isEmpty)
        #expect(syntax("   ").isEmpty)
    }
}
