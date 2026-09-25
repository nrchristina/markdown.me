import Testing
import MarkdownCore

/// Expected spans for documents that exercise every element and the places
/// where cmark's positions need correcting. Expectations were checked
/// against cmark-gfm's own output while developing the builder.
struct GoldenCase: Sendable, CustomTestStringConvertible {
    let name: String
    let markdown: String
    let spans: [RenderedSpan]

    init(_ name: String, _ markdown: String, _ spans: [RenderedSpan]) {
        self.name = name
        self.markdown = markdown
        self.spans = spans
    }

    var testDescription: String { name }
}

@Suite("SyntaxMap golden documents")
struct SyntaxMapGoldenTests {
    @Test(arguments: goldenCases)
    func producesExpectedSpans(_ golden: GoldenCase) {
        #expect(rendered(golden.markdown) == golden.spans)
    }
}

let goldenCases: [GoldenCase] = [
    GoldenCase("strong", "a **bold** b", [
        .init(.strong, "**bold**", content: "bold", markers: ["**", "**"]),
    ]),
    GoldenCase("cyrillic inline", "Привет *мир* и `код` и ``a`b`` ~~del~~", [
        .init(.emphasis, "*мир*", content: "мир", markers: ["*", "*"]),
        .init(.inlineCode, "`код`", content: "код", markers: ["`", "`"]),
        .init(.inlineCode, "``a`b``", content: "a`b", markers: ["``", "``"]),
        .init(.strikethrough, "~~del~~", content: "del", markers: ["~~", "~~"]),
    ]),
    GoldenCase("nested and underscore delimiters", "***both*** and _under_ __strong__", [
        .init(.emphasis, "***both***", content: "**both**", markers: ["*", "*"]),
        .init(.strong, "**both**", content: "both", markers: ["**", "**"]),
        .init(.emphasis, "_under_", content: "under", markers: ["_", "_"]),
        .init(.strong, "__strong__", content: "strong", markers: ["__", "__"]),
    ]),
    GoldenCase("links, images, autolinks, references", "[текст](http://a.b \"t\") ![alt *x*](img.png) <https://x.y> [ref][r]\n\n[r]: http://r", [
        .init(.link(destination: "http://a.b"), "[текст](http://a.b \"t\")", content: "текст", markers: ["[", "](http://a.b \"t\")"]),
        .init(.image(source: "img.png"), "![alt *x*](img.png)", content: "alt *x*", markers: ["![", "](img.png)"]),
        .init(.emphasis, "*x*", content: "x", markers: ["*", "*"]),
        .init(.link(destination: "https://x.y"), "<https://x.y>", content: "https://x.y", markers: ["<", ">"]),
        .init(.link(destination: "http://r"), "[ref][r]", content: "ref", markers: ["[", "][r]"]),
    ]),
    GoldenCase("links without text", "[](empty) ![](i.png)", [
        .init(.link(destination: "empty"), "[](empty)", content: "", markers: ["[](empty)"]),
        .init(.image(source: "i.png"), "![](i.png)", content: "", markers: ["![](i.png)"]),
    ]),
    GoldenCase("inline HTML", "a <span style=\"color: red\">red</span> b", [
        .init(.inlineHTML, "<span style=\"color: red\">", content: "<span style=\"color: red\">", markers: []),
        .init(.inlineHTML, "</span>", content: "</span>", markers: []),
    ]),
    GoldenCase("emoji", "👨\u{200D}👩\u{200D}👧 *e* 😀", [
        .init(.emphasis, "*e*", content: "e", markers: ["*", "*"]),
    ]),
    GoldenCase("code span with backticks inside", "`` ` a ` ``", [
        .init(.inlineCode, "`` ` a ` ``", content: " ` a ` ", markers: ["``", "``"]),
    ]),
    GoldenCase("unmatched delimiters", "**foo*", [
        .init(.emphasis, "*foo*", content: "foo", markers: ["*", "*"]),
    ]),
    GoldenCase("entities", "&#42;foo&#42;\n*foo*", [
        .init(.emphasis, "*foo*", content: "foo", markers: ["*", "*"]),
    ]),
    GoldenCase("indented continuation line", "Para *a\n   b* c", [
        .init(.emphasis, "*a\n   b*", content: "a\n   b", markers: ["*", "*"]),
    ]),
    GoldenCase("lazy quote line", "> lazy\ncontinuation *em*", [
        .init(.blockQuote(depth: 1), "> lazy\ncontinuation *em*", content: "lazy\ncontinuation *em*", markers: ["> "]),
        .init(.emphasis, "*em*", content: "em", markers: ["*", "*"]),
    ]),
    GoldenCase("lazy line of a nested quote", "> > a *x\n> y* z", [
        .init(.blockQuote(depth: 1), "> > a *x\n> y* z", content: "> a *x\n> y* z", markers: ["> ", "> "]),
        .init(.blockQuote(depth: 2), "> a *x\n> y* z", content: "a *x\n> y* z", markers: ["> "]),
        .init(.emphasis, "*x\n> y*", content: "x\n> y", markers: ["*", "*"]),
    ]),
    GoldenCase("indented lazy line in a quote in a list", "- item\n\n    > quote in item\n    > continues *x\n    y*", [
        .init(.listItem(ordinal: nil, depth: 0), "- item\n\n    > quote in item\n    > continues *x\n    y*", content: "item\n\n    > quote in item\n    > continues *x\n    y*", markers: ["- "]),
        .init(.blockQuote(depth: 1), "> quote in item\n    > continues *x\n    y*", content: "quote in item\n    > continues *x\n    y*", markers: ["> ", "> "]),
        .init(.emphasis, "*x\n    y*", content: "x\n    y", markers: ["*", "*"]),
    ]),
    GoldenCase("hard breaks", "hard  \nbreak *x*\\\nnext *y*", [
        .init(.emphasis, "*x*", content: "x", markers: ["*", "*"]),
        .init(.emphasis, "*y*", content: "y", markers: ["*", "*"]),
    ]),
    GoldenCase("line numbers after a backslash break", "a\\\nb\nc *d*", [
        .init(.emphasis, "*d*", content: "d", markers: ["*", "*"]),
    ]),
    GoldenCase("backslash break in a quote", "> q *a*\\\n> b **c**\n> d `e`", [
        .init(.blockQuote(depth: 1), "> q *a*\\\n> b **c**\n> d `e`", content: "q *a*\\\n> b **c**\n> d `e`", markers: ["> ", "> ", "> "]),
        .init(.emphasis, "*a*", content: "a", markers: ["*", "*"]),
        .init(.strong, "**c**", content: "c", markers: ["**", "**"]),
        .init(.inlineCode, "`e`", content: "e", markers: ["`", "`"]),
    ]),
    GoldenCase("code span over two lines", "a `code\nspans` *b*", [
        .init(.inlineCode, "`code\nspans`", content: "code\nspans", markers: ["`", "`"]),
        .init(.emphasis, "*b*", content: "b", markers: ["*", "*"]),
    ]),
    GoldenCase("reference definition before text", "[foo]: /url\n\"title\" ok *x*", [
        .init(.emphasis, "*x*", content: "x", markers: ["*", "*"]),
    ]),
    GoldenCase("reference definition before a setext heading", "[foo]: /url\nbar *y*\n===", [
        .init(.heading(level: 1), "bar *y*\n===", content: "bar *y*", markers: ["==="]),
        .init(.emphasis, "*y*", content: "y", markers: ["*", "*"]),
    ]),
    GoldenCase("lone tilde at a line start", " s\n~[d](u) *e*", [
        .init(.link(destination: "u"), "[d](u)", content: "d", markers: ["[", "](u)"]),
        .init(.emphasis, "*e*", content: "e", markers: ["*", "*"]),
    ]),
    GoldenCase("backslash break before an indented lazy line", ">\\\n ~~😀~~", [
        .init(.blockQuote(depth: 1), ">\\\n ~~😀~~", content: "\\\n ~~😀~~", markers: [">"]),
        .init(.strikethrough, "~~😀~~", content: "😀", markers: ["~~", "~~"]),
    ]),
    GoldenCase("CRLF", "# H1\r\n\r\n- *a*\r\n- b\r\n", [
        .init(.heading(level: 1), "# H1", content: "H1", markers: ["# "]),
        .init(.listItem(ordinal: nil, depth: 0), "- *a*", content: "*a*", markers: ["- "]),
        .init(.emphasis, "*a*", content: "a", markers: ["*", "*"]),
        .init(.listItem(ordinal: nil, depth: 0), "- b", content: "b", markers: ["- "]),
    ]),
    GoldenCase("byte order mark", "\u{FEFF}# H *e*\n", [
        .init(.heading(level: 1), "# H *e*", content: "H *e*", markers: ["# "]),
        .init(.emphasis, "*e*", content: "e", markers: ["*", "*"]),
    ]),
    GoldenCase("ATX heading with closing sequence", "# Заголовок **жирный** ##", [
        .init(.heading(level: 1), "# Заголовок **жирный** ##", content: "Заголовок **жирный**", markers: ["# ", " ##"]),
        .init(.strong, "**жирный**", content: "жирный", markers: ["**", "**"]),
    ]),
    GoldenCase("ATX heading trailing spaces", "### Title ###  ", [
        .init(.heading(level: 3), "### Title ###", content: "Title", markers: ["### ", " ###"]),
    ]),
    GoldenCase("empty ATX headings", "#\n\n# #\n\n## a#", [
        .init(.heading(level: 1), "#", content: "", markers: ["#"]),
        .init(.heading(level: 1), "# #", content: "", markers: ["# ", "#"]),
        .init(.heading(level: 2), "## a#", content: "a#", markers: ["## "]),
    ]),
    GoldenCase("lone tilde in a heading", "# ~*с*", [
        .init(.heading(level: 1), "# ~*с*", content: "~*с*", markers: ["# "]),
        .init(.emphasis, "*с*", content: "с", markers: ["*", "*"]),
    ]),
    GoldenCase("setext heading followed by text", "Title *x*\n=====\nnext", [
        .init(.heading(level: 1), "Title *x*\n=====", content: "Title *x*", markers: ["====="]),
        .init(.emphasis, "*x*", content: "x", markers: ["*", "*"]),
    ]),
    GoldenCase("setext heading in a quote", "> Title *a*\n> ---", [
        .init(.blockQuote(depth: 1), "> Title *a*\n> ---", content: "Title *a*\n> ---", markers: ["> ", "> "]),
        .init(.heading(level: 2), "Title *a*\n> ---", content: "Title *a*", markers: ["---"]),
        .init(.emphasis, "*a*", content: "a", markers: ["*", "*"]),
    ]),
    GoldenCase("fenced code blocks", "```swift\nlet a = 1\n```\n\n~~~~\nx\n~~~~~~", [
        .init(.codeBlock(language: "swift"), "```swift\nlet a = 1\n```", content: "let a = 1\n", markers: ["```swift", "```"]),
        .init(.codeBlock(language: nil), "~~~~\nx\n~~~~~~", content: "x\n", markers: ["~~~~", "~~~~~~"]),
    ]),
    GoldenCase("unclosed fence", "```\nunclosed", [
        .init(.codeBlock(language: nil), "```\nunclosed", content: "unclosed", markers: ["```"]),
    ]),
    GoldenCase("indented code that looks like a fence", "para\n\n    code line\n    ```", [
        .init(.codeBlock(language: nil), "code line\n    ```", content: "code line\n    ```", markers: []),
    ]),
    GoldenCase("fenced code in a list item", "- item\n\n  ```\n  code\n  ```", [
        .init(.listItem(ordinal: nil, depth: 0), "- item\n\n  ```\n  code\n  ```", content: "item\n\n  ```\n  code\n  ```", markers: ["- "]),
        .init(.codeBlock(language: nil), "```\n  code\n  ```", content: "  code\n", markers: ["```", "```"]),
    ]),
    GoldenCase("fenced code in a quote", "> ```\n> code\n> ```", [
        .init(.blockQuote(depth: 1), "> ```\n> code\n> ```", content: "```\n> code\n> ```", markers: ["> ", "> ", "> "]),
        .init(.codeBlock(language: nil), "```\n> code\n> ```", content: "> code\n", markers: ["```", "```"]),
    ]),
    GoldenCase("task list and nested ordered list", "- [ ] задача\n- [x] done\n  1. one\n  2. two", [
        .init(.listItem(ordinal: nil, depth: 0), "- [ ] задача", content: "задача", markers: ["- "]),
        .init(.taskCheckbox(isChecked: false), "[ ]", content: "", markers: ["[ ]"]),
        .init(.listItem(ordinal: nil, depth: 0), "- [x] done\n  1. one\n  2. two", content: "done\n  1. one\n  2. two", markers: ["- "]),
        .init(.taskCheckbox(isChecked: true), "[x]", content: "", markers: ["[x]"]),
        .init(.listItem(ordinal: 1, depth: 1), "1. one", content: "one", markers: ["1. "]),
        .init(.listItem(ordinal: 2, depth: 1), "2. two", content: "two", markers: ["2. "]),
    ]),
    GoldenCase("ordered list start and empty item", "3) three\n4) four\n\n-\n  foo", [
        .init(.listItem(ordinal: 3, depth: 0), "3) three", content: "three", markers: ["3) "]),
        .init(.listItem(ordinal: 4, depth: 0), "4) four", content: "four", markers: ["4) "]),
        .init(.listItem(ordinal: nil, depth: 0), "-\n  foo", content: "\n  foo", markers: ["-"]),
    ]),
    GoldenCase("thematic breaks", "* * *\n\nFoo\nbar\n\n---\n\nbaz", [
        .init(.thematicBreak, "* * *", content: "", markers: ["* * *"]),
        .init(.thematicBreak, "---", content: "", markers: ["---"]),
    ]),
    GoldenCase("table", "| a | b |\n|---|:-:|\n| *x* | y |", [
        .init(.table, "| a | b |\n|---|:-:|\n| *x* | y |", content: "| a | b |\n|---|:-:|\n| *x* | y |", markers: []),
        .init(.emphasis, "*x*", content: "x", markers: ["*", "*"]),
    ]),
    GoldenCase("table interrupting a paragraph", "123\n456\n| a | b |\n| ---| --- |\nd | *e* |", [
        .init(.table, "| a | b |\n| ---| --- |\nd | *e* |", content: "| a | b |\n| ---| --- |\nd | *e* |", markers: []),
        .init(.emphasis, "*e*", content: "e", markers: ["*", "*"]),
    ]),
    GoldenCase("table in a quote", ">a|b\n>-|-\n> [c](u) | *d*", [
        .init(.blockQuote(depth: 1), ">a|b\n>-|-\n> [c](u) | *d*", content: "a|b\n>-|-\n> [c](u) | *d*", markers: [">", ">", "> "]),
        .init(.table, "a|b\n>-|-\n> [c](u) | *d*", content: "a|b\n>-|-\n> [c](u) | *d*", markers: []),
        .init(.link(destination: "u"), "[c](u)", content: "c", markers: ["[", "](u)"]),
        .init(.emphasis, "*d*", content: "d", markers: ["*", "*"]),
    ]),
    GoldenCase("table in a list item", "- a|b\n  -|-\n  c | *d*", [
        .init(.listItem(ordinal: nil, depth: 0), "- a|b\n  -|-\n  c | *d*", content: "a|b\n  -|-\n  c | *d*", markers: ["- "]),
        .init(.table, "a|b\n  -|-\n  c | *d*", content: "a|b\n  -|-\n  c | *d*", markers: []),
        .init(.emphasis, "*d*", content: "d", markers: ["*", "*"]),
    ]),
    GoldenCase("escaped pipes in a table", "| f\\|oo | *x* |\n| --- | --- |\n| `\\|` *a* | b |", [
        .init(.table, "| f\\|oo | *x* |\n| --- | --- |\n| `\\|` *a* | b |", content: "| f\\|oo | *x* |\n| --- | --- |\n| `\\|` *a* | b |", markers: []),
        .init(.emphasis, "*x*", content: "x", markers: ["*", "*"]),
        .init(.inlineCode, "`\\|`", content: "\\|", markers: ["`", "`"]),
        .init(.emphasis, "*a*", content: "a", markers: ["*", "*"]),
    ]),
    GoldenCase("HTML block", "<div>\n*not em*\n</div>\n\n*em*", [
        .init(.htmlBlock, "<div>\n*not em*\n</div>", content: "<div>\n*not em*\n</div>", markers: []),
        .init(.emphasis, "*em*", content: "em", markers: ["*", "*"]),
    ]),
]
