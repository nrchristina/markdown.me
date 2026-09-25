import Testing
import MarkdownCore

// `‸` marks a caret, `«…»` a selection; see EditingSupport.swift.

@Suite("List editing")
struct ListEditingTests {
    @Test(arguments: [
        ("- one‸", "- one\n- ‸"),
        ("- ab‸cd", "- ab\n- ‸cd"),
        ("- a«b»c", "- a\n- ‸c"),
        ("1. one‸\n2. two", "1. one\n2. ‸\n3. two"),
        ("1. a\n2. b‸", "1. a\n2. b\n3. ‸"),
        ("1) a‸", "1) a\n2) ‸"),
        ("- [x] done‸", "- [x] done\n- [ ] ‸"),
        ("> - a‸", "> - a\n> - ‸"),
        ("  * a‸", "  * a\n  * ‸"),
        ("- Купить 🍎‸", "- Купить 🍎\n- ‸"),
        // Return on an empty item leaves the list, or its nested level.
        ("- one\n- ‸", "- one\n\n‸"),
        ("- ‸", "‸"),
        ("- a\n  - ‸", "- a\n- ‸"),
        ("1. a\n   1. ‸", "1. a\n2. ‸"),
    ])
    func newline(input: String, expected: String) {
        #expect(run(input) { ListEditing.newline(in: $0, selection: $1) } == expected)
    }

    @Test(arguments: ["text‸", "‸- a", "```\n- a‸\n```", "«- a\n- b»"])
    func newlineOutsideListItems(input: String) {
        #expect(run(input) { ListEditing.newline(in: $0, selection: $1) } == nil)
    }

    @Test(arguments: [
        ("- a\n- ‸b", "- a\n  - ‸b"),
        ("1. a\n2. ‸b\n3. c", "1. a\n   1. ‸b\n2. c"),
        // What is nested in the item moves with it.
        ("- a\n- ‸b\n  - c", "- a\n  - ‸b\n    - c"),
        ("- a\n«- b\n- c»", "- a\n  «- b\n  - c»"),
        ("- а\n- ‸б 😀", "- а\n  - ‸б 😀"),
    ])
    func indent(input: String, expected: String) {
        #expect(run(input) { ListEditing.indent(in: $0, selection: $1) } == expected)
    }

    @Test(arguments: [
        ("- a\n  - ‸b", "- a\n- ‸b"),
        ("- a\n  - ‸b\n  - c", "- a\n- ‸b\n  - c"),
        ("1. a\n   1. ‸b\n   2. c\n2. d", "1. a\n2. ‸b\n   1. c\n3. d"),
        ("- a\n\t- ‸b", "- a\n- ‸b"),
    ])
    func outdent(input: String, expected: String) {
        #expect(run(input) { ListEditing.outdent(in: $0, selection: $1) } == expected)
    }

    @Test func levelKeysOutsideListsAreNotHandled() {
        #expect(ListEditing.indent(in: "text", selection: 2..<2) == nil)
        #expect(ListEditing.outdent(in: "text", selection: 2..<2) == nil)
    }

    @Test func levelKeysWithNowhereToGoChangeNothing() throws {
        // The first item has no item above to nest under; a top-level item
        // has no level to move out to. The key is still handled.
        let indent = try #require(ListEditing.indent(in: "- a\n- b", selection: 2..<2))
        #expect(!indent.changesText)
        #expect(indent.selection == 2..<2)
        let outdent = try #require(ListEditing.outdent(in: "- a", selection: 3..<3))
        #expect(!outdent.changesText)
    }

    @Test(arguments: [
        ("- [ ] за‸дача", "- [x] за‸дача"),
        ("- [x] done‸", "- [ ] done‸"),
        ("- [X] done‸", "- [ ] done‸"),
        ("1. [ ] x‸", "1. [x] x‸"),
        ("> - [ ] 😀‸", "> - [x] 😀‸"),
    ])
    func toggleCheckbox(input: String, expected: String) {
        let result = run(input) { text, selection in
            ListEditing.toggleCheckbox(in: text, at: selection.lowerBound, selection: selection)
        }
        #expect(result == expected)
    }

    @Test func checkboxEditIsOneCharacter() throws {
        let edit = try #require(ListEditing.toggleCheckbox(in: "a\n- [ ] b", at: 4, selection: 0..<1))
        #expect(edit.range == 5..<6)
        #expect(edit.replacement == "x")
        #expect(edit.selection == 0..<1)
    }

    @Test(arguments: ["- item‸", "text‸", "- [] x‸"])
    func noCheckboxToToggle(input: String) {
        let result = run(input) { text, selection in
            ListEditing.toggleCheckbox(in: text, at: selection.lowerBound, selection: selection)
        }
        #expect(result == nil)
    }
}
