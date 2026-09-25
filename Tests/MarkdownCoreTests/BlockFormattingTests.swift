import Testing
import MarkdownCore

// `‸` marks a caret, `«…»` a selection; see EditingSupport.swift.

@Suite("Block formatting")
struct BlockFormattingTests {
    @Test(arguments: [
        CommandCase(.heading(level: 1), "Ti‸tle", "# Ti‸tle"),
        CommandCase(.heading(level: 1), "# Ti‸tle", "Ti‸tle"),
        CommandCase(.heading(level: 2), "# Ti‸tle", "## Ti‸tle"),
        CommandCase(.heading(level: 9), "Ti‸tle", "###### Ti‸tle"),
        CommandCase(.paragraph, "### Ti‸tle", "Ti‸tle"),
        CommandCase(.paragraph, "## Ti‸tle ##", "Ti‸tle"),
        CommandCase(.heading(level: 1), "‸", "# ‸"),
        // Every selected line; the same level again removes it.
        CommandCase(.heading(level: 2), "«one\ntwo»", "«## one\n## two»"),
        CommandCase(.heading(level: 2), "«## one\ntwo»", "«## one\n## two»"),
        CommandCase(.heading(level: 2), "«## one\n## two»", "«one\ntwo»"),
        CommandCase(.heading(level: 1), "«one\n\ntwo»", "«# one\n\n# two»"),
        // After list and quote markers.
        CommandCase(.heading(level: 3), "- it‸em", "- ### it‸em"),
        CommandCase(.heading(level: 1), "> quo‸te", "> # quo‸te"),
        // Setext headings lose their underline.
        CommandCase(.heading(level: 1), "Ti‸tle\n=====", "Ti‸tle"),
        CommandCase(.heading(level: 2), "Ti‸tle\n=====", "## Ti‸tle"),
        CommandCase(.paragraph, "Ti‸tle\n-----", "Ti‸tle"),
        CommandCase(.heading(level: 1), "«Title\n=====»", "«Title»"),
        CommandCase(.heading(level: 3), "Заголо‸вок 😀", "### Заголо‸вок 😀"),
    ])
    func headings(_ testCase: CommandCase) {
        #expect(apply(testCase.command, testCase.input) == testCase.expected)
    }

    @Test func paragraphLeavesPlainTextAlone() {
        #expect(apply(.paragraph, "Ti‸tle") == nil)
        #expect(apply(.heading(level: 1), "```\nco‸de\n```") == nil)
    }

    @Test(arguments: [
        CommandCase(.bulletList, "it‸em", "- it‸em"),
        CommandCase(.bulletList, "- it‸em", "it‸em"),
        CommandCase(.bulletList, "‸", "- ‸"),
        CommandCase(.bulletList, "> it‸em", "> - it‸em"),
        CommandCase(.bulletList, "«a\n\nb»", "«- a\n\n- b»"),
        CommandCase(.numberedList, "«one\ntwo»", "«1. one\n2. two»"),
        CommandCase(.numberedList, "«1. one\n2. two»", "«one\ntwo»"),
        CommandCase(.taskList, "- it‸em", "- [ ] it‸em"),
        CommandCase(.taskList, "- [x] it‸em", "it‸em"),
        CommandCase(.taskList, "«Купить 🍎\nПродать»", "«- [ ] Купить 🍎\n- [ ] Продать»"),
        // Conversion between kinds keeps the indentation.
        CommandCase(.numberedList, "«- a\n- b»", "«1. a\n2. b»"),
        CommandCase(.bulletList, "«1. a\n- b»", "«- a\n- b»"),
        CommandCase(.bulletList, "- [ ] it‸em", "- it‸em"),
        CommandCase(.numberedList, "- a\n  - ‸b", "- a\n  1. ‸b"),
        // Renumbering: the items after a change follow it.
        CommandCase(.bulletList, "1. a\n2. ‸b\n3. c", "1. a\n- ‸b\n1. c"),
        CommandCase(.numberedList, "1. a\n2. b\n\n‸c", "1. a\n2. b\n\n3. ‸c"),
        CommandCase(.numberedList, "1. a\n‸b\n2. c", "1. a\n2. ‸b\n3. c"),
        CommandCase(.numberedList, "7. a\n‸b", "7. a\n8. ‸b"),
    ])
    func lists(_ testCase: CommandCase) {
        #expect(apply(testCase.command, testCase.input) == testCase.expected)
    }

    @Test(arguments: [
        ("te‸xt", "> te‸xt"),
        ("> te‸xt", "te‸xt"),
        ("«a\n\nb»", "«> a\n>\n> b»"),
        ("«> a\n>\n> b»", "«a\n\nb»"),
        ("> a\n‸b", "> a\n> ‸b"),
        ("> > a‸", "> a‸"),
        ("«Цитата 😀»", "«> Цитата 😀»"),
    ])
    func blockquote(input: String, expected: String) {
        #expect(apply(.blockquote, input) == expected)
    }

    @Test(arguments: [
        ("let x = 1‸", "```‸\nlet x = 1\n```"),
        ("```‸\nlet x = 1\n```", "‸let x = 1"),
        ("```\nco‸de", "co‸de"),
        ("«a\nb»", "```‸\na\nb\n```"),
        ("‸", "```‸\n\n```"),
        ("say ```hi‸```", "````‸\nsay ```hi```\n````"),
        ("> co‸de", "> ```‸\n> code\n> ```"),
        ("Привет 😀‸", "```‸\nПривет 😀\n```"),
    ])
    func codeBlock(input: String, expected: String) {
        #expect(apply(.codeBlock, input) == expected)
    }

    @Test(arguments: [
        ("abc‸", "abc\n\n---\n‸"),
        ("abc‸\ndef", "abc\n\n---\n‸\ndef"),
        ("abc‸\n\ndef", "abc\n\n---\n‸\ndef"),
        ("abc\n‸\ndef", "abc\n\n---\n‸\ndef"),
        ("«abc\ndef»", "abc\ndef\n\n---\n‸"),
        ("‸", "---\n‸"),
        ("Текст 😀‸", "Текст 😀\n\n---\n‸"),
        // On a rule: it goes, with one of the blank lines around it.
        ("abc\n\n---‸\n\ndef", "abc‸\n\ndef"),
    ])
    func horizontalRule(input: String, expected: String) {
        #expect(apply(.horizontalRule, input) == expected)
    }

    @Test func keepsCRLFLineBreaks() {
        #expect(apply(.codeBlock, "a‸\r\nb") == "```‸\r\na\r\n```\r\nb")
        #expect(apply(.horizontalRule, "a‸\r\nb") == "a\r\n\r\n---\r\n‸\r\nb")
    }
}
