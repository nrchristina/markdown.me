import Markdown

/// Walks a swift-markdown tree and records one `SyntaxSpan` per element.
///
/// Work happens in UTF-8 byte offsets, because that is what cmark reports and
/// all Markdown syntax characters are ASCII; each span is converted to UTF-16
/// when it is emitted. Markers are only recorded after checking that the bytes
/// really are the expected syntax characters — a wrong marker would make Text
/// mode hide the user's text.
///
/// cmark's positions for inline content are unreliable in several places;
/// `InlinePositions.swift` corrects them.
struct SyntaxMapBuilder {
    struct Context {
        var quoteDepth = 0
        /// Number of enclosing lists.
        var listDepth = 0
        /// Set while walking the inline content of a paragraph, heading or
        /// table cell.
        var inline: InlinePositions?
        /// Set while walking a table row.
        var row: RowShift?

        func inList() -> Context {
            var copy = self
            copy.listDepth += 1
            return copy
        }

        func inQuote() -> Context {
            var copy = self
            copy.quoteDepth += 1
            return copy
        }
    }

    let index: SourceIndex
    private(set) var spans: [SyntaxSpan] = []

    init(index: SourceIndex) {
        self.index = index
    }

    mutating func visit(_ markup: Markup, _ context: Context) {
        switch markup {
        case is Text, is SoftBreak, is LineBreak:
            // The most common nodes; checked first so they skip the casts below.
            return
        case let heading as Heading:
            visitHeading(heading, context)
        case let paragraph as Paragraph:
            visitChildren(of: paragraph, inlineContext(for: paragraph, context))
        case let cell as Table.Cell:
            visitChildren(of: cell, inlineContext(for: cell, context))
        case let emphasis as Emphasis:
            visitDelimited(emphasis, .emphasis, delimiters: [.asterisk, .underscore], context)
        case let strong as Strong:
            visitDelimited(strong, .strong, delimiters: [.asterisk, .underscore], context)
        case let strikethrough as Strikethrough:
            visitDelimited(strikethrough, .strikethrough, delimiters: [.tilde], context)
        case let code as InlineCode:
            visitInlineCode(code, context)
        case let link as Link:
            visitLinkOrImage(link, .link(destination: link.destination), isImage: false, context)
        case let image as Image:
            visitLinkOrImage(image, .image(source: image.source), isImage: true, context)
        case let html as InlineHTML:
            emitWithoutMarkers(html, .inlineHTML, context)
        case let html as HTMLBlock:
            emitWithoutMarkers(html, .htmlBlock, context)
        case let codeBlock as CodeBlock:
            visitCodeBlock(codeBlock, context)
        case let quote as BlockQuote:
            visitBlockQuote(quote, context)
        case let list as UnorderedList:
            visitChildren(of: list, context.inList())
        case let list as OrderedList:
            visitChildren(of: list, context.inList())
        case let item as ListItem:
            visitListItem(item, context)
        case let rule as ThematicBreak:
            if let range = byteRange(of: rule, context) {
                emit(.thematicBreak, range: range, content: range.upperBound..<range.upperBound, markers: [range])
            }
        case let table as Table:
            visitTable(table, context)
        case let head as Table.Head:
            visitChildren(of: head, rowContext(for: head, isHeader: true, context))
        case let row as Table.Row:
            visitChildren(of: row, rowContext(for: row, isHeader: false, context))
        default:
            visitChildren(of: markup, context)
        }
    }

    // MARK: - Elements

    private mutating func visitHeading(_ heading: Heading, _ context: Context) {
        let inline = inlineContext(for: heading, context)
        defer { visitChildren(of: heading, inline) }
        guard let range = byteRange(of: heading, context), !range.isEmpty else { return }
        let kind = SyntaxKind.heading(level: heading.level)

        if index.bytes[range.lowerBound] == .numberSign {
            visitATXHeading(kind, range)
        } else {
            // Setext: the text, then a line of `=` or `-`. cmark's range can
            // run into the line after the underline, so find the underline
            // right after the text instead.
            let content = contentRange(of: heading, inline)
            let underline = content.flatMap { setextUnderline(after: $0.upperBound) }
            if let content, let underline {
                emit(kind, range: content.lowerBound..<underline.upperBound, content: content, markers: [underline])
            } else {
                emit(kind, range: range, content: content ?? range, markers: [])
            }
        }
    }

    /// `## Title ##`. The line is scanned directly: cmark reports misplaced
    /// ranges for some of a heading's children (a lone `~`, for one).
    private mutating func visitATXHeading(_ kind: SyntaxKind, _ range: Range<Int>) {
        let lineEnd = index.lineEnds[index.lineIndex(containing: range.lowerBound)]
        var position = range.lowerBound
        while position < lineEnd, index.bytes[position] == .numberSign {
            position += 1
        }
        while position < lineEnd, index.bytes[position].isSpaceOrTab {
            position += 1
        }
        let opening = range.lowerBound..<position

        var end = lineEnd
        while end > position, index.bytes[end - 1].isSpaceOrTab {
            end -= 1
        }
        // An optional closing run of `#`, preceded by a space unless the
        // heading has no text at all.
        var hashes = end
        while hashes > position, index.bytes[hashes - 1] == .numberSign {
            hashes -= 1
        }
        var contentEnd = end
        var closing: Range<Int>?
        if hashes < end, hashes == position || index.bytes[hashes - 1].isSpaceOrTab {
            var closingStart = hashes
            while closingStart > position, index.bytes[closingStart - 1].isSpaceOrTab {
                closingStart -= 1
            }
            closing = closingStart..<end
            contentEnd = closingStart
        }

        let content = position..<max(position, contentEnd)
        let whole = range.lowerBound..<(closing?.upperBound ?? content.upperBound)
        emit(kind, range: whole, content: content, markers: [opening] + (closing.map { [$0] } ?? []))
    }

    /// `**bold**`, `*em*`, `~~strike~~`. The markers are exactly the
    /// element's delimiters next to its content; a leftover delimiter that
    /// cmark includes in the range (`**foo*`) is literal text and stays out.
    private mutating func visitDelimited(_ markup: Markup, _ kind: SyntaxKind, delimiters: Set<UInt8>, _ context: Context) {
        defer { visitChildren(of: markup, context) }
        guard let range = byteRange(of: markup, context) else { return }
        guard let content = delimitedContent(of: markup, context),
              let width = delimiterWidth(of: markup, content: content),
              range.lowerBound <= content.lowerBound - width, content.upperBound + width <= range.upperBound else {
            emit(kind, range: range, content: range, markers: [])
            return
        }
        let opening = (content.lowerBound - width)..<content.lowerBound
        let closing = content.upperBound..<(content.upperBound + width)
        if consists(opening, of: delimiters), consists(closing, of: delimiters) {
            emit(kind, range: opening.lowerBound..<closing.upperBound, content: content, markers: [opening, closing])
        } else {
            emit(kind, range: range, content: range, markers: [])
        }
    }

    /// Range between the delimiters of an emphasis, strong or strikethrough.
    /// cmark gives `***a***` the same range for the outer and the inner
    /// element; the outer one's content is then the inner one with its
    /// delimiters.
    private func delimitedContent(of markup: Markup, _ context: Context) -> Range<Int>? {
        guard let range = byteRange(of: markup, context),
              let content = contentRange(of: markup, context) else { return nil }
        let children = markup.children.filter { $0.range != nil }
        if content == range, children.count == 1, let child = children.first,
           child is Emphasis || child is Strong || child is Strikethrough {
            guard let inner = delimitedContent(of: child, context),
                  let width = delimiterWidth(of: child, content: inner) else { return nil }
            return (inner.lowerBound - width)..<(inner.upperBound + width)
        }
        return content
    }

    private func delimiterWidth(of markup: Markup, content: Range<Int>) -> Int? {
        switch markup {
        case is Emphasis:
            return 1
        case is Strong:
            return 2
        default:
            // Strikethrough: `~` or `~~`, the same on both sides.
            var before = 0
            while before < 2, content.lowerBound - before - 1 >= 0,
                  index.bytes[content.lowerBound - before - 1] == .tilde {
                before += 1
            }
            var after = 0
            while after < 2, content.upperBound + after < index.bytes.count,
                  index.bytes[content.upperBound + after] == .tilde {
                after += 1
            }
            return before == after && before > 0 ? before : nil
        }
    }

    private mutating func visitInlineCode(_ code: InlineCode, _ context: Context) {
        guard let range = byteRange(of: code, context) else { return }
        var openingEnd = range.lowerBound
        while openingEnd < range.upperBound, index.bytes[openingEnd] == .backtick {
            openingEnd += 1
        }
        var closingStart = range.upperBound
        while closingStart > openingEnd, index.bytes[closingStart - 1] == .backtick {
            closingStart -= 1
        }
        let openingCount = openingEnd - range.lowerBound
        if openingCount > 0, openingCount == range.upperBound - closingStart {
            emit(.inlineCode, range: range, content: openingEnd..<closingStart,
                 markers: [range.lowerBound..<openingEnd, closingStart..<range.upperBound])
        } else {
            emit(.inlineCode, range: range, content: range, markers: [])
        }
    }

    /// `[text](url)`, `[text][ref]`, `<https://…>`, `![alt](src)`.
    private mutating func visitLinkOrImage(_ markup: Markup, _ kind: SyntaxKind, isImage: Bool, _ context: Context) {
        defer { visitChildren(of: markup, context) }
        guard let range = byteRange(of: markup, context) else { return }
        let openingPrefix = isImage ? "![" : "["

        guard let content = contentRange(of: markup, context),
              range.lowerBound <= content.lowerBound, content.upperBound <= range.upperBound else {
            // `[](url)`: there is no text, only syntax.
            let markers = starts(range, with: openingPrefix) ? [range] : []
            emit(kind, range: range, content: range.lowerBound..<range.lowerBound, markers: markers)
            return
        }

        let opening = range.lowerBound..<content.lowerBound
        let closing = content.upperBound..<range.upperBound
        let isBracketed = equals(opening, openingPrefix) && starts(closing, with: "]")
        let isAutolink = !isImage && equals(opening, "<") && equals(closing, ">")
        if isBracketed || isAutolink {
            emit(kind, range: range, content: content, markers: [opening, closing])
        } else {
            emit(kind, range: range, content: range, markers: [])
        }
    }

    private mutating func visitCodeBlock(_ block: CodeBlock, _ context: Context) {
        guard let range = byteRange(of: block, context), !range.isEmpty else { return }
        let kind = SyntaxKind.codeBlock(language: block.language)

        let firstLine = index.lineIndex(containing: range.lowerBound)
        let firstLineEnd = min(index.lineEnds[firstLine], range.upperBound)
        let fence = index.bytes[range.lowerBound]
        var fenceEnd = range.lowerBound
        while fenceEnd < firstLineEnd, index.bytes[fenceEnd] == fence {
            fenceEnd += 1
        }
        let fenceLength = fenceEnd - range.lowerBound
        // swift-markdown does not say whether a block is fenced. An indented
        // block keeps its first line in `code`; a fenced one does not.
        let firstLineText = String(decoding: index.bytes[range.lowerBound..<firstLineEnd], as: UTF8.self)
        let isFenced = (fence == .backtick || fence == .tilde) && fenceLength >= 3
            && !block.code.hasPrefix(firstLineText)
        guard isFenced else {
            emit(kind, range: range, content: range, markers: [])
            return
        }

        let opening = range.lowerBound..<firstLineEnd
        let lastLine = index.lineIndex(containing: range.upperBound - 1)
        let closing = lastLine > firstLine
            ? closingFence(onLine: lastLine, before: range.upperBound, fence: fence, minimumLength: fenceLength)
            : nil
        let nextLineStart = firstLine + 1 < index.lineCount ? index.lineStarts[firstLine + 1] : index.bytes.count
        let contentStart = min(nextLineStart, range.upperBound)
        let contentEnd = max(contentStart, closing == nil ? range.upperBound : index.lineStarts[lastLine])
        emit(kind, range: range, content: contentStart..<contentEnd, markers: [opening] + (closing.map { [$0] } ?? []))
    }

    private mutating func visitBlockQuote(_ quote: BlockQuote, _ context: Context) {
        let inner = context.inQuote()
        defer { visitChildren(of: quote, inner) }
        guard let range = byteRange(of: quote, context), !range.isEmpty else { return }

        let firstLine = index.lineIndex(containing: range.lowerBound)
        let lastLine = index.lineIndex(containing: range.upperBound - 1)
        var markers: [Range<Int>] = []
        for line in firstLine...lastLine {
            // The first line starts at this quote's own `>`. On later lines the
            // `>` of every enclosing quote comes first; lazy lines have none.
            let marker = line == firstLine
                ? quoteMarker(from: range.lowerBound, line: line, outerQuotes: 0)
                : quoteMarker(from: index.lineStarts[line], line: line, outerQuotes: context.quoteDepth)
            if let marker {
                markers.append(marker)
            }
        }
        let contentStart = markers.first?.upperBound ?? range.lowerBound
        emit(.blockQuote(depth: inner.quoteDepth), range: range, content: contentStart..<range.upperBound, markers: markers)
    }

    private mutating func visitListItem(_ item: ListItem, _ context: Context) {
        defer { visitChildren(of: item, context) }
        guard let range = byteRange(of: item, context), !range.isEmpty else { return }
        let ordinal = (item.parent as? OrderedList).map { Int($0.startIndex) + item.indexInParent }
        let kind = SyntaxKind.listItem(ordinal: ordinal, depth: max(context.listDepth - 1, 0))
        let lineEnd = index.lineEnds[index.lineIndex(containing: range.lowerBound)]

        // `-`, `+`, `*`, or digits followed by `.` or `)`.
        var position = range.lowerBound
        let first = index.bytes[position]
        if first == .hyphen || first == .plus || first == .asterisk {
            position += 1
        } else {
            while position < lineEnd, index.bytes[position].isASCIIDigit {
                position += 1
            }
            guard position > range.lowerBound, position < lineEnd,
                  index.bytes[position] == .period || index.bytes[position] == .closingParenthesis else {
                emit(kind, range: range, content: range, markers: [])
                return
            }
            position += 1
        }
        while position < lineEnd, index.bytes[position].isSpaceOrTab {
            position += 1
        }
        let marker = range.lowerBound..<position
        var contentStart = position

        if let checkbox = item.checkbox, position + 3 <= lineEnd,
           index.bytes[position] == .openingBracket, index.bytes[position + 2] == .closingBracket {
            let box = position..<(position + 3)
            emit(.taskCheckbox(isChecked: checkbox == .checked), range: box,
                 content: box.upperBound..<box.upperBound, markers: [box])
            contentStart = box.upperBound
            while contentStart < lineEnd, index.bytes[contentStart].isSpaceOrTab {
                contentStart += 1
            }
        }
        emit(kind, range: range, content: min(contentStart, range.upperBound)..<range.upperBound, markers: [marker])
    }

    private mutating func visitTable(_ table: Table, _ context: Context) {
        defer { visitChildren(of: table, context) }
        guard var range = byteRange(of: table, context) else { return }
        // A table that interrupts a paragraph is reported as starting with
        // the paragraph; it really starts on the line of its first cell.
        if let cellStart = firstCell(in: table)?.range?.lowerBound {
            let cellOffset = index.byteOffset(line: cellStart.line, column: cellStart.column)
            let lineStart = index.lineStarts[index.lineIndex(containing: cellOffset)]
            range = min(max(range.lowerBound, lineStart), range.upperBound)..<range.upperBound
        }
        emit(.table, range: range, content: range, markers: [])
    }

    private mutating func emitWithoutMarkers(_ markup: Markup, _ kind: SyntaxKind, _ context: Context) {
        guard let range = byteRange(of: markup, context) else { return }
        emit(kind, range: range, content: range, markers: [])
    }

    private mutating func visitChildren(of markup: Markup, _ context: Context) {
        for child in markup.children {
            visit(child, context)
        }
    }

    private mutating func emit(_ kind: SyntaxKind, range: Range<Int>, content: Range<Int>, markers: [Range<Int>]) {
        spans.append(SyntaxSpan(
            kind: kind,
            range: index.utf16Range(range),
            contentRange: index.utf16Range(content),
            markers: markers.filter { !$0.isEmpty }.map { index.utf16Range($0) }
        ))
    }

    // MARK: - Positions

    func byteRange(of markup: Markup, _ context: Context) -> Range<Int>? {
        guard let range = markup.range else { return nil }
        let lower = byteOffset(range.lowerBound, context)
        var upper = byteOffset(range.upperBound, context)
        guard lower <= upper else { return nil }
        // An end at the very start of a line means the element ended with the
        // previous line; never include that line break.
        let line = index.lineIndex(containing: upper)
        if upper > lower, line > 0, upper == index.lineStarts[line] {
            upper = max(lower, index.lineEnds[line - 1])
        }
        return lower..<upper
    }

    /// From the start of the first child to the end of the last one. Empty
    /// child ranges carry no position and are skipped.
    private func contentRange(of markup: Markup, _ context: Context) -> Range<Int>? {
        var lower = Int.max
        var upper = Int.min
        for child in markup.children {
            guard let range = byteRange(of: child, context), !range.isEmpty else { continue }
            lower = min(lower, range.lowerBound)
            upper = max(upper, range.upperBound)
        }
        return lower <= upper ? lower..<upper : nil
    }

    // MARK: - Scanning

    /// The `===` or `---` line right after a setext heading's text.
    private func setextUnderline(after contentEnd: Int) -> Range<Int>? {
        let line = index.lineIndex(containing: contentEnd) + 1
        guard line < index.lineCount else { return nil }
        var position = index.lineStarts[line]
        let end = index.lineEnds[line]
        while position < end, index.bytes[position].isSpaceOrTab || index.bytes[position] == .greaterThan {
            position += 1
        }
        guard position < end else { return nil }
        let character = index.bytes[position]
        guard character == .equalsSign || character == .hyphen else { return nil }
        let underlineStart = position
        while position < end, index.bytes[position] == character {
            position += 1
        }
        let underlineEnd = position
        while position < end, index.bytes[position].isSpaceOrTab {
            position += 1
        }
        return position == end ? underlineStart..<underlineEnd : nil
    }

    /// A fence of at least `minimumLength` on the block's last line, preceded
    /// only by indentation and quote markers.
    private func closingFence(onLine line: Int, before end: Int, fence: UInt8, minimumLength: Int) -> Range<Int>? {
        let lineStart = index.lineStarts[line]
        var position = min(end, index.lineEnds[line])
        while position > lineStart, index.bytes[position - 1].isSpaceOrTab {
            position -= 1
        }
        let fenceEnd = position
        while position > lineStart, index.bytes[position - 1] == fence {
            position -= 1
        }
        guard fenceEnd - position >= minimumLength,
              index.bytes[lineStart..<position].allSatisfy({ $0.isSpaceOrTab || $0 == .greaterThan }) else {
            return nil
        }
        return position..<fenceEnd
    }

    /// The `>` of the quote nested `outerQuotes` levels deep, plus one space.
    private func quoteMarker(from start: Int, line: Int, outerQuotes: Int) -> Range<Int>? {
        let end = index.lineEnds[line]
        var position = start
        var remaining = outerQuotes
        while true {
            while position < end, index.bytes[position].isSpaceOrTab {
                position += 1
            }
            guard position < end, index.bytes[position] == .greaterThan else { return nil }
            if remaining == 0 { break }
            remaining -= 1
            position += 1
        }
        var markerEnd = position + 1
        if markerEnd < end, index.bytes[markerEnd].isSpaceOrTab {
            markerEnd += 1
        }
        return position..<markerEnd
    }

    private func firstCell(in markup: Markup) -> Table.Cell? {
        for child in markup.children {
            if let cell = child as? Table.Cell {
                return cell
            }
            if let cell = firstCell(in: child) {
                return cell
            }
        }
        return nil
    }

    private func consists(_ range: Range<Int>, of allowed: Set<UInt8>) -> Bool {
        !range.isEmpty && range.allSatisfy { allowed.contains(index.bytes[$0]) }
    }

    private func equals(_ range: Range<Int>, _ string: String) -> Bool {
        index.bytes[range].elementsEqual(string.utf8)
    }

    private func starts(_ range: Range<Int>, with prefix: String) -> Bool {
        index.bytes[range].starts(with: prefix.utf8)
    }
}

extension UInt8 {
    static let numberSign = UInt8(ascii: "#")
    static let equalsSign = UInt8(ascii: "=")
    static let hyphen = UInt8(ascii: "-")
    static let plus = UInt8(ascii: "+")
    static let asterisk = UInt8(ascii: "*")
    static let underscore = UInt8(ascii: "_")
    static let tilde = UInt8(ascii: "~")
    static let backtick = UInt8(ascii: "`")
    static let period = UInt8(ascii: ".")
    static let closingParenthesis = UInt8(ascii: ")")
    static let openingBracket = UInt8(ascii: "[")
    static let closingBracket = UInt8(ascii: "]")
    static let backslash = UInt8(ascii: "\\")
    static let verticalBar = UInt8(ascii: "|")

    var isASCIIDigit: Bool { self >= UInt8(ascii: "0") && self <= UInt8(ascii: "9") }
}
