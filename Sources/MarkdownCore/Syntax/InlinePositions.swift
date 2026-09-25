import Markdown

// cmark reports inline positions relative to the paragraph it is parsing,
// and several of its shortcuts leave them wrong in the source:
//
// - On a paragraph's continuation lines it counts columns from where the
//   first line's text started, not from where that line's text starts
//   (lazy lines `> a` / `b`, deeper or shallower indentation).
// - After a backslash hard break (`\` at the end of a line) it does not
//   start a new line at all: positions stay on the previous line number with
//   columns running on, and every later line of the paragraph lags by one.
// - Link reference definitions at the start of a paragraph are removed from
//   its text, but lines are still counted from the paragraph's first line.
// - Table rows: body rows are placed at the header row's column, header rows
//   before their leading spaces, and `\|` inside a cell shifts everything
//   after it by the removed backslash.
//
// The fix: walk the inline content in order, keep track of the true line,
// and calibrate each line on its first element — after a line break the next
// element always starts where that line's text starts. The resulting
// segments map any reported position to the source.

/// Maps cmark's reported positions of one inline block (paragraph, heading,
/// table cell) to true source positions.
struct InlinePositions {
    struct Segment {
        /// Reported position where the segment starts.
        var line: Int
        var column: Int
        /// Source line of the segment and the column correction for it.
        var trueLine: Int
        var shift: Int
    }

    var blockStart: SourceLocation
    /// Ascending by reported position; the first starts at `blockStart`.
    var segments: [Segment]
    /// Byte offsets of the backslashes of `\|` in a table cell.
    var escapedPipes: [Int] = []
}

/// Column correction for the table row being walked.
struct RowShift {
    var line: Int
    var shift: Int
}

extension SyntaxMapBuilder {
    func byteOffset(_ location: SourceLocation, _ context: Context) -> Int {
        let position = trueLocation(location, context.inline, quoteDepth: context.quoteDepth)
        var column = position.column
        if let row = context.row, row.line == position.line {
            column += row.shift
        }
        var offset = index.byteOffset(line: position.line, column: column)
        for pipe in context.inline?.escapedPipes ?? [] {
            guard pipe < offset else { break }
            offset += 1
        }
        return offset
    }

    func trueLocation(_ location: SourceLocation, _ positions: InlinePositions?, quoteDepth: Int) -> (line: Int, column: Int) {
        guard let positions, positions.blockStart <= location, var segment = positions.segments.first else {
            return (location.line, location.column)
        }
        for candidate in positions.segments where (candidate.line, candidate.column) <= (location.line, location.column) {
            segment = candidate
        }
        if location.line == segment.line {
            return (segment.trueLine, location.column + segment.shift)
        }
        // A later line without a segment of its own, e.g. inside a code span
        // that spans lines: assume cmark counted from the block's column.
        let line = segment.trueLine + (location.line - segment.line)
        let shift = index.textStartColumn(line: line, quoteDepth: quoteDepth) - positions.blockStart.column
        return (line, location.column + shift)
    }

    /// Context for walking the inline content of `block`.
    func inlineContext(for block: Markup, _ context: Context) -> Context {
        var result = context
        guard let start = block.range?.lowerBound else {
            result.inline = nil
            return result
        }

        var escapedPipes: [Int] = []
        if block is Table.Cell, let range = byteRange(of: block, context), range.count > 1 {
            escapedPipes = (range.lowerBound..<(range.upperBound - 1)).filter {
                index.bytes[$0] == .backslash && index.bytes[$0 + 1] == .verticalBar
            }
        }
        result.inline = positions(for: block, start: start, firstLine: start.line, escapedPipes: escapedPipes, context)

        // Link reference definitions removed from the paragraph: the text
        // then starts on a later line than cmark says. Only a paragraph that
        // starts with `[` can have them; find the line where its first text
        // really is.
        let startOffset = index.byteOffset(line: start.line, column: start.column)
        guard !(block is Table.Cell),
              let text = firstText(in: block),
              !textMatches(text, result),
              startOffset < index.bytes.count, index.bytes[startOffset] == .openingBracket,
              let end = block.range?.upperBound else {
            return result
        }
        for firstLine in stride(from: start.line + 1, through: end.line, by: 1) {
            var candidate = context
            candidate.inline = positions(for: block, start: start, firstLine: firstLine, escapedPipes: escapedPipes, context)
            if textMatches(text, candidate) {
                return candidate
            }
        }
        return result
    }

    /// Context for walking a table row's cells.
    func rowContext(for row: Markup, isHeader: Bool, _ context: Context) -> Context {
        guard let start = row.range?.lowerBound else { return context }
        let shift: Int
        if isHeader {
            // The header row may be placed before its leading spaces.
            let from = index.byteOffset(line: start.line, column: start.column)
            let end = index.lineEnds[index.lineIndex(containing: from)]
            var position = from
            while position < end, index.bytes[position].isSpaceOrTab {
                position += 1
            }
            shift = position - from
        } else {
            // Body rows are placed at the header's column.
            shift = index.textStartColumn(line: start.line, quoteDepth: context.quoteDepth) - start.column
        }
        var result = context
        result.row = RowShift(line: start.line, shift: shift)
        return result
    }

    private struct Calibration {
        /// True source line of the text being walked.
        var line: Int
        /// A line break was passed and the next line is not calibrated yet.
        var pending = false
        var leadingSpaces: Int?
        /// Bytes of text without a usable range seen since the line break.
        var skippedBytes = 0
        /// End of the last element with a range since the line break.
        var previousEnd: SourceLocation?
    }

    private func positions(for block: Markup, start: SourceLocation, firstLine: Int, escapedPipes: [Int], _ context: Context) -> InlinePositions {
        let firstShift = firstLine == start.line
            ? 0
            : index.textStartColumn(line: firstLine, quoteDepth: context.quoteDepth) - start.column
        var positions = InlinePositions(
            blockStart: start,
            segments: [.init(line: start.line, column: start.column, trueLine: firstLine, shift: firstShift)],
            escapedPipes: escapedPipes
        )
        var calibration = Calibration(line: firstLine)
        calibrate(block, &positions, &calibration, quoteDepth: context.quoteDepth)
        return positions
    }

    private func calibrate(_ markup: Markup, _ positions: inout InlinePositions, _ state: inout Calibration, quoteDepth: Int) {
        for child in markup.children {
            if child is SoftBreak || child is LineBreak {
                if let previousEnd = state.previousEnd {
                    state.line = trueLocation(previousEnd, positions, quoteDepth: quoteDepth).line
                }
                state.line += 1
                state.pending = true
                state.leadingSpaces = nil
                state.skippedBytes = 0
                state.previousEnd = nil
                continue
            }
            if state.pending, state.leadingSpaces == nil {
                // After a backslash break cmark keeps the next line's leading
                // spaces as text; otherwise text starts at the first
                // non-space character.
                let literal = (child as? Text)?.string ?? ""
                state.leadingSpaces = literal.utf8.prefix { $0.isSpaceOrTab }.count
            }
            if let range = child.range, range.lowerBound < range.upperBound {
                if state.pending {
                    let start = range.lowerBound
                    let textStart = index.textStartColumn(line: state.line, quoteDepth: quoteDepth)
                    let shift = textStart - (state.leadingSpaces ?? 0) + state.skippedBytes - start.column
                    positions.segments.append(.init(line: start.line, column: start.column, trueLine: state.line, shift: shift))
                    state.pending = false
                }
                state.previousEnd = range.upperBound
            } else if state.pending, let text = child as? Text {
                // cmark gives some text (a lone `~`) no usable range.
                state.skippedBytes += text.string.utf8.count
            }
            calibrate(child, &positions, &state, quoteDepth: quoteDepth)
        }
    }

    private func firstText(in markup: Markup) -> Text? {
        for child in markup.children {
            if let text = child as? Text, text.range != nil, !text.string.isEmpty {
                return text
            }
            if let text = firstText(in: child) {
                return text
            }
        }
        return nil
    }

    private func textMatches(_ text: Text, _ context: Context) -> Bool {
        guard let range = byteRange(of: text, context) else { return false }
        return index.bytes[range].elementsEqual(text.string.utf8)
    }
}
