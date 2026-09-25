/// Keys that edit lists: Return continues a list, Tab and Shift-Tab change
/// an item's level. Each returns nil where it does not apply, and the text
/// view then does what the key normally does.
///
/// Offsets are UTF-16 code units. Pass the editor's current `SyntaxMap` of
/// `text` if there is one; otherwise the text is parsed when needed.
public enum ListEditing {
    /// Return in a list item: a new item below with the same marker, the
    /// numbers after it moved up by one. Return on an empty item leaves the
    /// list, or moves a nested item one level out.
    public static func newline(in text: String, selection: Range<Int>, syntax: SyntaxMap? = nil) -> TextEdit? {
        EditingDocument(text, selection: selection, syntax: syntax).continueList()
    }

    /// Tab in a list item: nests the selected items, and what is nested in
    /// them, under the item above. An edit that changes nothing when there
    /// is no item above to nest under.
    public static func indent(in text: String, selection: Range<Int>, syntax: SyntaxMap? = nil) -> TextEdit? {
        EditingDocument(text, selection: selection, syntax: syntax).changeListLevel(outdent: false)
    }

    /// Shift-Tab in a list item: moves the selected items one level out. An
    /// edit that changes nothing for a top-level item.
    public static func outdent(in text: String, selection: Range<Int>, syntax: SyntaxMap? = nil) -> TextEdit? {
        EditingDocument(text, selection: selection, syntax: syntax).changeListLevel(outdent: true)
    }

    /// Checks or unchecks the task item on the line that contains `offset`,
    /// keeping `selection`. Nil when that line is not a task item.
    public static func toggleCheckbox(in text: String, at offset: Int, selection: Range<Int>) -> TextEdit? {
        EditingDocument(text, selection: selection, syntax: nil).toggleCheckbox(at: offset)
    }
}

/// A line of a list block as it will be after an edit.
struct ListLine {
    /// The line in the original text; nil for a line the edit inserts.
    var line: Int?
    var indent: Int
    /// Nil for a line that is not a list item.
    var kind: LineSyntax.ListKind?
    var hasCheckbox: Bool
    /// Width of the whitespace between the list symbol and the text.
    var spacing: Int
    var isEmpty: Bool
    /// Inside a code block, so not a list item whatever it looks like.
    var isCode: Bool
    /// Whether the item started a list before the edit.
    var startedList = false
    /// Made an ordered item by the edit, or moved: if it starts a list now,
    /// that list starts at 1.
    var isChanged = false

    init(_ syntax: LineSyntax, isCode: Bool) {
        line = syntax.line
        indent = syntax.indent
        isEmpty = syntax.isEmpty
        self.isCode = isCode
        if let list = syntax.list, !isCode {
            kind = list.kind
            hasCheckbox = syntax.checkbox != nil
            spacing = list.end - list.symbol.upperBound
        } else {
            kind = nil
            hasCheckbox = false
            spacing = 0
        }
    }

    /// The column where the item's text starts; lines indented this far
    /// belong to the item.
    var contentColumn: Int {
        guard let kind else { return indent }
        return indent + kind.symbol.count + max(spacing, 1)
    }
}

extension LineSyntax.ListKind {
    var symbol: [UInt16] {
        switch self {
        case .bullet(let character):
            return [character]
        case .ordered(let number, let delimiter):
            return [UInt16](String(number)) + [delimiter]
        }
    }

    var isOrdered: Bool {
        if case .ordered = self {
            return true
        }
        return false
    }

    /// Whether an item with this marker after one with `previous` is in the
    /// same list: a different bullet or delimiter starts a new list.
    func continues(_ previous: Self) -> Bool {
        switch (self, previous) {
        case let (.bullet(character), .bullet(previousCharacter)):
            return character == previousCharacter
        case let (.ordered(_, delimiter), .ordered(_, previousDelimiter)):
            return delimiter == previousDelimiter
        default:
            return false
        }
    }
}

/// Which items of a list block continue a list, and the numbers that follow.
enum ListNumbering {
    /// Calls `body` for each item with the previous item of its list, if it
    /// continues one; `body` returns the item's marker. Nesting follows
    /// CommonMark: an item indented to the content column of an open item is
    /// inside it; text after a blank line that is indented less closes items.
    private static func walk(_ lines: [ListLine], _ body: (Int, LineSyntax.ListKind?) -> LineSyntax.ListKind) {
        var open: [ListLine] = []
        var afterEmptyLine = false
        for index in lines.indices {
            var line = lines[index]
            if line.isEmpty {
                afterEmptyLine = true
                continue
            }
            guard let kind = line.kind else {
                if afterEmptyLine {
                    while let last = open.last, line.indent < last.contentColumn {
                        open.removeLast()
                    }
                }
                afterEmptyLine = false
                continue
            }
            afterEmptyLine = false
            var previous: ListLine?
            while let last = open.last, line.indent < last.contentColumn {
                previous = open.removeLast()
            }
            let previousKind = previous?.kind.flatMap { kind.continues($0) ? $0 : nil }
            line.kind = body(index, previousKind)
            open.append(line)
        }
    }

    /// Records which items start a list.
    static func markingStarts(_ lines: [ListLine]) -> [ListLine] {
        var result = lines
        walk(lines) { index, previous in
            result[index].startedList = previous == nil
            return lines[index].kind!
        }
        return result
    }

    /// Numbers the ordered items from `first` on: an item that continues a
    /// list follows the number before it; one that starts a list keeps its
    /// number, unless the edit made it or it did not start a list before.
    static func renumbered(_ lines: [ListLine], from first: Int) -> [ListLine] {
        var result = lines
        walk(lines) { index, previous in
            let line = lines[index]
            guard case .ordered(let own, let delimiter) = line.kind! else { return line.kind! }
            let number: Int
            if index < first {
                number = own
            } else if case .ordered(let previousNumber, _)? = previous {
                number = previousNumber + 1
            } else if line.isChanged || !line.startedList {
                number = 1
            } else {
                number = own
            }
            result[index].kind = .ordered(number: number, delimiter: delimiter)
            return result[index].kind!
        }
        return result
    }
}

extension EditingDocument {
    // MARK: - List commands

    /// Makes the selected lines items of a bulleted, numbered or task list,
    /// converting items of another kind and renumbering. When all of them
    /// already are, removes their markers. Indentation stays.
    func toggleList(_ type: LineSyntax.ListType) -> TextEdit? {
        let lines = buffer.lines(in: selection)
        var targets = lines.filter { !buffer.line($0).isEmpty && !isInCodeBlock(line: $0) }
        if targets.isEmpty {
            guard lines.count == 1, !isInCodeBlock(line: lines.lowerBound) else { return nil }
            targets = [lines.lowerBound]
        }
        let removing = targets.allSatisfy { buffer.line($0).listType == type }

        let block = listBlock(around: lines, becomingItems: removing ? [] : Set(targets))
        var planned = listLines(in: block)
        for target in targets {
            let index = target - block.lowerBound
            let wasOrdered = planned[index].kind?.isOrdered == true
            if removing {
                planned[index].kind = nil
                planned[index].hasCheckbox = false
                continue
            }
            switch type {
            case .bullet, .task:
                if planned[index].kind == nil || wasOrdered {
                    planned[index].kind = .bullet(.hyphen)
                }
                planned[index].hasCheckbox = type == .task
            case .ordered:
                if !wasOrdered {
                    planned[index].kind = .ordered(number: 1, delimiter: .period)
                    planned[index].isChanged = true
                }
                planned[index].hasCheckbox = false
            }
        }
        planned = ListNumbering.renumbered(planned, from: targets[0] - block.lowerBound)

        var builder = EditBuilder(buffer)
        apply(planned, &builder)
        return builder.textEdit(selection: lineSelection(after: builder))
    }

    /// Tab and Shift-Tab. Nil when the selection does not start in a list item.
    func changeListLevel(outdent: Bool) -> TextEdit? {
        let lines = buffer.lines(in: selection)
        guard buffer.line(lines.lowerBound).list != nil, !isInCodeBlock(line: lines.lowerBound) else { return nil }
        let block = listBlock(around: lines)
        var planned = listLines(in: block)
        let first = lines.lowerBound - block.lowerBound
        let last = lines.upperBound - block.lowerBound

        let indent = outdent ? parentIndent(of: first, in: planned) : previousSiblingContentColumn(of: first, in: planned)
        guard let indent else { return unchanged }
        let delta = indent - planned[first].indent
        for index in first...subtreeEnd(after: last, in: planned) where !planned[index].isEmpty {
            planned[index].indent = max(0, planned[index].indent + delta)
            if index <= last {
                planned[index].isChanged = true
            }
        }
        planned = ListNumbering.renumbered(planned, from: first)

        var builder = EditBuilder(buffer)
        apply(planned, &builder)
        let lower = builder.map(selection.lowerBound, .after)
        let upper = selection.isEmpty ? lower : builder.map(selection.upperBound, .after)
        return builder.textEdit(selection: lower..<max(lower, upper)) ?? unchanged
    }

    /// Return. Nil outside list items and for a selection over several lines.
    func continueList() -> TextEdit? {
        let index = buffer.lineIndex(containing: selection.lowerBound)
        let line = buffer.line(index)
        guard let list = line.list, selection.lowerBound >= line.textStart, selection.upperBound <= line.end,
              !isInCodeBlock(line: index) else { return nil }
        if units[line.textStart..<line.end].allSatisfy(\.isSpaceOrTab) {
            return leaveList(line)
        }

        let block = listBlock(around: index...index)
        var planned = listLines(in: block)
        let position = index - block.lowerBound
        var added = planned[position]
        added.line = nil
        added.isChanged = true
        planned.insert(added, at: position + 1)
        planned = ListNumbering.renumbered(planned, from: position + 1)

        var builder = EditBuilder(buffer)
        apply(planned, &builder)
        // The same quote markers, indentation and spacing as this item.
        var newItem = buffer.lineBreak + Array(units[line.start..<line.indentEnd])
        newItem += planned[position + 1].kind!.symbol + whitespace(list.symbol.upperBound..<list.end)
        if let checkbox = line.checkbox {
            newItem += [UInt16]("[ ]") + whitespace(checkbox.range.upperBound..<checkbox.end)
        }
        builder.replace(selection, with: newItem)
        let caret = builder.map(selection.upperBound, .after)
        return builder.textEdit(selection: caret..<caret)
    }

    /// Return on an empty item: a nested item moves one level out; a
    /// top-level one loses its marker, with a blank line after the list so
    /// that what is typed next is not part of the item above.
    private func leaveList(_ line: LineSyntax) -> TextEdit? {
        let block = listBlock(around: line.line...line.line)
        if parentIndent(of: line.line - block.lowerBound, in: listLines(in: block)) != nil {
            return changeListLevel(outdent: true)
        }
        var replacement: [UInt16] = []
        if line.line > 0, !buffer.line(line.line - 1).isEmpty {
            replacement = buffer.lineBreak + Array(units[line.start..<line.quoteEnd])
        }
        var builder = EditBuilder(buffer)
        builder.replace(line.quoteEnd..<line.end, with: replacement)
        let caret = line.quoteEnd + replacement.count
        return builder.textEdit(selection: caret..<caret)
    }

    func toggleCheckbox(at offset: Int) -> TextEdit? {
        let line = buffer.line(buffer.lineIndex(containing: min(max(offset, 0), buffer.count)))
        guard let checkbox = line.checkbox else { return nil }
        var builder = EditBuilder(buffer)
        let mark = checkbox.range.lowerBound + 1
        builder.replace(mark..<(mark + 1), with: [checkbox.isChecked ? .space : .lowercaseX])
        return builder.textEdit(selection: selection)
    }

    // MARK: - List structure

    /// The lines around `lines` that the same lists run through: every
    /// non-empty line next to them, and past empty lines where both sides are
    /// list items or indented. `becomingItems` count as items.
    func listBlock(around lines: ClosedRange<Int>, becomingItems: Set<Int> = []) -> ClosedRange<Int> {
        let depth = buffer.line(lines.lowerBound).quoteDepth
        func isListLine(_ index: Int) -> Bool {
            let line = buffer.line(index)
            return becomingItems.contains(index) || (line.quoteDepth == depth && (line.list != nil || line.indent > 0))
        }

        var first = lines.lowerBound
        while first > 0 {
            let above = buffer.line(first - 1)
            if !above.isEmpty {
                guard above.quoteDepth == depth else { break }
                first -= 1
                continue
            }
            var beyond = first - 1
            while beyond > 0, buffer.line(beyond).isEmpty {
                beyond -= 1
            }
            guard !buffer.line(beyond).isEmpty, isListLine(first), isListLine(beyond) else { break }
            first = beyond
        }

        var last = lines.upperBound
        while last + 1 < buffer.lineCount {
            let below = buffer.line(last + 1)
            if !below.isEmpty {
                guard below.quoteDepth == depth else { break }
                last += 1
                continue
            }
            var beyond = last + 1
            while beyond + 1 < buffer.lineCount, buffer.line(beyond).isEmpty {
                beyond += 1
            }
            guard !buffer.line(beyond).isEmpty, isListLine(last), isListLine(beyond) else { break }
            last = beyond
        }
        return first...last
    }

    func listLines(in block: ClosedRange<Int>) -> [ListLine] {
        ListNumbering.markingStarts(block.map { ListLine(buffer.line($0), isCode: isInCodeBlock(line: $0)) })
    }

    /// Where the item at `item` goes to nest under the item above it: that
    /// item's content column. Nil when no item above is at the same level.
    private func previousSiblingContentColumn(of item: Int, in lines: [ListLine]) -> Int? {
        let indent = lines[item].indent
        for line in lines[..<item].reversed() where line.kind != nil && line.indent <= indent {
            return indent < line.contentColumn ? line.contentColumn : nil
        }
        return nil
    }

    /// The indentation of the item that `item` is nested in; nil at the top level.
    private func parentIndent(of item: Int, in lines: [ListLine]) -> Int? {
        let indent = lines[item].indent
        for line in lines[..<item].reversed() where line.kind != nil && line.indent < indent && line.contentColumn <= indent {
            return line.indent
        }
        return nil
    }

    /// The last line of what is nested in the item that `last` belongs to.
    private func subtreeEnd(after last: Int, in lines: [ListLine]) -> Int {
        guard let item = lines[...last].lastIndex(where: { $0.kind != nil }) else { return last }
        let column = lines[item].contentColumn
        var end = last
        for index in (last + 1)..<lines.count where !lines[index].isEmpty {
            guard lines[index].indent >= column else { break }
            end = index
        }
        return end
    }

    /// Edits that turn the original lines of a block into `planned`.
    private func apply(_ planned: [ListLine], _ builder: inout EditBuilder) {
        for item in planned {
            guard let index = item.line else { continue }
            let line = buffer.line(index)
            if item.indent != line.indent, !line.isEmpty {
                let whitespace = line.quoteEnd..<line.indentEnd
                if item.indent > line.indent {
                    builder.insert([UInt16](repeating: .space, count: item.indent - line.indent), at: line.indentEnd)
                } else if units[whitespace].allSatisfy({ $0 == .space }) {
                    builder.delete((line.indentEnd - (line.indent - item.indent))..<line.indentEnd)
                } else {
                    builder.replace(whitespace, with: [UInt16](repeating: .space, count: item.indent))
                }
            }
            guard !item.isCode else { continue }

            switch (line.list, item.kind) {
            case (nil, nil):
                break
            case (nil, let kind?):
                let checkbox = item.hasCheckbox ? [UInt16]("[ ] ") : []
                builder.insert(kind.symbol + [.space] + checkbox, at: line.indentEnd)
            case (let list?, nil):
                builder.delete(list.symbol.lowerBound..<(line.checkbox?.end ?? list.end))
            case (let list?, let kind?):
                builder.replace(list.symbol, with: kind.symbol)
                if item.hasCheckbox, line.checkbox == nil {
                    let checkbox = list.end == list.symbol.upperBound ? " [ ] " : "[ ] "
                    builder.insert([UInt16](checkbox), at: list.end)
                } else if !item.hasCheckbox, let checkbox = line.checkbox {
                    builder.delete(checkbox.range.lowerBound..<checkbox.end)
                }
            }
        }
    }

    /// The whitespace in `range`, or one space if there is none.
    private func whitespace(_ range: Range<Int>) -> [UInt16] {
        range.isEmpty ? [.space] : Array(units[range])
    }
}
