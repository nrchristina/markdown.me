import Testing
import MarkdownCore

// `‸` marks a caret, `«…»` a selection; see EditingSupport.swift.

@Suite("Inline formatting")
struct InlineFormattingTests {
    @Test(arguments: [
        // A caret styles the word it is in, or inserts a pair of markers.
        ("Hello wo‸rld", "Hello **wo‸rld**"),
        ("Hello ‸", "Hello **‸**"),
        ("Hello **‸**", "Hello ‸"),
        ("**wo‸rld**", "wo‸rld"),
        // A selection is styled as it is, without surrounding whitespace.
        ("Hello «world»", "Hello **«world»**"),
        ("«Hello world »", "**«Hello world»** "),
        // Already bold, with the markers outside or inside the selection.
        ("Hello **«world»**", "Hello «world»"),
        ("Hello «**world**»", "Hello «world»"),
        // Line by line, leaving list and heading markers out.
        ("«one\ntwo»", "«**one**\n**two**»"),
        ("«**one**\n**two**»", "«one\ntwo»"),
        ("«- one\n- two»", "«- **one**\n- **two**»"),
        ("«# Title»", "# **«Title»**"),
        // Bold that the selection only partly covers merges into the new bold.
        ("«**a** b»", "**«a b»**"),
        // Markers inside code would be literal, so they go around it.
        ("`co‸de`", "**`co‸de`**"),
        ("*it‸alic*", "***it‸alic***"),
        ("***it‸alic***", "*it‸alic*"),
        ("Привет, ми‸р 😀", "Привет, **ми‸р** 😀"),
        ("«😀 smile»", "**«😀 smile»**"),
        ("😀‸", "😀**‸**"),
    ])
    func bold(input: String, expected: String) {
        #expect(apply(.bold, input) == expected)
    }

    @Test(arguments: [
        ("wo‸rd", "*wo‸rd*"),
        ("*wo‸rd*", "wo‸rd"),
        ("_wo‸rd_", "wo‸rd"),
        ("**wo‸rd**", "***wo‸rd***"),
        ("snake_ca‸se", "*snake_ca‸se*"),
        ("«one\ntwo»", "«*one*\n*two*»"),
        ("«Привет»", "*«Привет»*"),
        ("Ключ ‸", "Ключ *‸*"),
    ])
    func italic(input: String, expected: String) {
        #expect(apply(.italic, input) == expected)
    }

    @Test(arguments: [
        ("wo‸rd", "~~wo‸rd~~"),
        ("~~wo‸rd~~", "wo‸rd"),
        ("a ‸", "a ~~‸~~"),
        ("a ~~‸~~", "a ‸"),
        ("«one\ntwo»", "«~~one~~\n~~two~~»"),
        ("«старый 😀»", "~~«старый 😀»~~"),
    ])
    func strikethrough(input: String, expected: String) {
        #expect(apply(.strikethrough, input) == expected)
    }

    @Test(arguments: [
        ("use co‸de", "use `co‸de`"),
        ("use `co‸de`", "use co‸de"),
        ("Ключ ‸", "Ключ `‸`"),
        // Backticks inside need a longer fence.
        ("«a`b»", "``«a`b»``"),
        ("``«a`b»``", "«a`b»"),
        ("«`x`»", "«x»"),
        ("«**bold**»", "`«**bold**»`"),
        ("«a\nb»", "«`a`\n`b`»"),
        ("«Код 😀»", "`«Код 😀»`"),
    ])
    func inlineCode(input: String, expected: String) {
        #expect(apply(.inlineCode, input) == expected)
    }

    @Test func nothingToStyleInACodeBlock() {
        #expect(apply(.bold, "```\nco‸de\n```") == nil)
        #expect(apply(.italic, "«   »") == nil)
    }

    @Test(arguments: [
        ("«Anthropic»", "[Anthropic](«url»)"),
        ("see Anth‸ropic", "see [Anthropic](«url»)"),
        ("see ‸", "see [‸](url)"),
        // On a link: the link goes, its text stays selected.
        ("[Anthropic](«url»)", "«Anthropic»"),
        ("[Anth‸ropic](https://x.com)", "«Anthropic»"),
        ("[a](http://ex‸ample.com)", "«a»"),
        ("[](«url»)", "«url»"),
        ("«Сайт 😀»", "[Сайт 😀](«url»)"),
        ("«one\ntwo»", "[one\ntwo](«url»)"),
    ])
    func link(input: String, expected: String) {
        #expect(apply(.link, input) == expected)
    }

    @Test(arguments: [
        ("«логотип»", "![логотип](«path»)"),
        ("![логотип](«path»)", "«логотип»"),
        ("‸", "![](«path»)"),
        ("a wo‸rd", "a ![word](«path»)"),
        ("«one\ntwo 😀»", "![one\ntwo 😀](«path»)"),
    ])
    func image(input: String, expected: String) {
        #expect(apply(.image, input) == expected)
    }

    @Test func usesASuppliedSyntaxMap() {
        let text = "Hello **world**"
        let syntax = SyntaxMap(parsing: text)
        let edit = FormattingCommand.bold.edit(in: text, selection: 9..<9, syntax: syntax)
        #expect(edit?.applied(to: text) == "Hello world")
        // A map of other text is ignored rather than trusted.
        let stale = FormattingCommand.bold.edit(in: text, selection: 9..<9, syntax: SyntaxMap(parsing: "x"))
        #expect(stale == edit)
    }
}
