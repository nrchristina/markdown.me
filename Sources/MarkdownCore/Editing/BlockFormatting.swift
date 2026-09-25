extension EditingDocument {
    // MARK: - Headings

    /// Makes every selected line a heading of `level`, or removes the heading
    /// when all of them already are one of that level. A nil `level` makes
    /// them plain text. Setext headings (`Title` over `===`) become ATX ones.
    func setHeading(level: Int?) -> TextEdit? {
        let lines = buffer.lines(in: selection)
        var targets: [Int] = []
        for line in lines where !isInCodeBlock(line: line) {
            if let setext = setextHeading(at: line) {
                for content in setext.contentLines where !targets.contains(content) {
                    targets.append(content)
                }
            } else if !buffer.line(line).isEmpty {
                targets.append(line)
            }
        }
        if targets.isEmpty {
            guard level != nil, lines.count == 1, !isInCodeBlock(line: lines.lowerBound) else { return nil }
            targets = [lines.lowerBound]
        }

        let removing = targets.allSatisfy { currentHeadingLevel(of: $0) == level }
        var builder = EditBuilder(buffer)
        var removedUnderlines = Set<Int>()
        for index in targets.sorted() {
            let line = buffer.line(index)
            if let level, !removing {
                let hashes = [UInt16](repeating: .numberSign, count: level)
                if let heading = line.heading {
                    builder.replace(heading.marker, with: hashes)
                } else {
                    builder.insert(hashes + [.space], at: line.textStart)
                }
            } else if let heading = line.heading {
                builder.delete(heading.marker.lowerBound..<heading.end)
                if let closing = heading.closing {
                    builder.delete(closing)
                }
            }
            // An ATX heading, or plain text, has no underline.
            if let setext = setextHeading(at: index), removedUnderlines.insert(setext.underline).inserted {
                let underline = setext.underline
                builder.delete(buffer.lineEnds[underline - 1]..<buffer.lineEnds[underline])
            }
        }
        return builder.textEdit(selection: lineSelection(after: builder))
    }

    private struct SetextHeading {
        var level: Int
        var contentLines: ClosedRange<Int>
        var underline: Int
    }

    /// The setext heading that `line` is part of, underline included.
    private func setextHeading(at line: Int) -> SetextHeading? {
        let probe = buffer.lineEnds[line]
        for span in singleMarkerHeadings.containing(probe..<probe) {
            guard case .heading(let level) = span.kind else { continue }
            let first = buffer.lineIndex(containing: span.range.lowerBound)
            let underline = buffer.lineIndex(containing: span.markers[0].lowerBound)
            if underline > first {
                return SetextHeading(level: level, contentLines: first...(underline - 1), underline: underline)
            }
        }
        return nil
    }

    private func currentHeadingLevel(of line: Int) -> Int? {
        buffer.line(line).heading?.level ?? setextHeading(at: line)?.level
    }

    // MARK: - Block quotes

    /// Adds `> ` to the selected lines, or removes one level of quoting when
    /// all of them are quoted. Blank lines between them become `>`.
    func toggleQuote() -> TextEdit? {
        let lines = buffer.lines(in: selection)
        var first = lines.lowerBound
        var last = lines.upperBound
        while first < last, buffer.isBlank(first) {
            first += 1
        }
        while last > first, buffer.isBlank(last) {
            last -= 1
        }
        let isQuoted = { (line: Int) in self.buffer.line(line).quoteDepth > 0 }
        let removing = (first...last).contains(where: isQuoted)
            && (first...last).allSatisfy { isQuoted($0) || buffer.isBlank($0) }

        var builder = EditBuilder(buffer)
        for index in first...last {
            let line = buffer.line(index)
            if removing {
                guard line.quoteDepth > 0 else { continue }
                var end = line.start
                while units[end] != .greaterThan {
                    end += 1
                }
                end += 1
                if end < line.end, units[end].isSpaceOrTab {
                    end += 1
                }
                builder.delete(line.start..<end)
            } else if line.quoteDepth == 0 {
                let isBetweenLines = buffer.isBlank(index) && first < last
                builder.insert(isBetweenLines ? [.greaterThan] : [.greaterThan, .space], at: line.start)
            }
        }
        return builder.textEdit(selection: lineSelection(after: builder))
    }

    // MARK: - Code blocks

    /// Puts the selected lines between ``` fences, with the caret where the
    /// language goes. Inside a fenced code block, removes its fences.
    func toggleCodeBlock() -> TextEdit? {
        var builder = EditBuilder(buffer)
        let fenced = SpanIndex(syntax) { $0.kind.isCodeBlock && !$0.markers.isEmpty }
        if let block = fenced.containing(selection).first {
            let opening = buffer.lineIndex(containing: block.markers[0].lowerBound)
            if block.markers.count == 2 {
                let closing = buffer.lineIndex(containing: block.markers[1].lowerBound)
                if closing == opening + 1 {
                    builder.delete(buffer.lineStarts[opening]..<buffer.lineEnds[closing])
                } else {
                    builder.delete(buffer.lineStarts[opening]..<buffer.nextLineStart(opening))
                    builder.delete(buffer.lineEnds[closing - 1]..<buffer.lineEnds[closing])
                }
            } else {
                builder.delete(buffer.lineStarts[opening]..<buffer.nextLineStart(opening))
            }
            let lower = builder.map(selection.lowerBound, .after)
            return builder.textEdit(selection: lower..<max(lower, builder.map(selection.upperBound, .before)))
        }

        let lines = buffer.lines(in: selection)
        let first = buffer.line(lines.lowerBound)
        // Fence lines go inside the same block quotes, at the same indentation.
        let prefix = Array(units[first.start..<first.indentEnd])
        let contents = buffer.lineStarts[lines.lowerBound]..<buffer.lineEnds[lines.upperBound]
        let longest = buffer.longestRun(of: .backtick, in: contents)
        let fence = [UInt16](repeating: .backtick, count: longest >= 3 ? longest + 1 : 3)
        builder.insert(prefix + fence + buffer.lineBreak, at: contents.lowerBound)
        builder.insert(buffer.lineBreak + prefix + fence, at: contents.upperBound)
        let caret = contents.lowerBound + prefix.count + fence.count
        return builder.textEdit(selection: caret..<caret)
    }

    // MARK: - Horizontal rule

    /// `---` on its own line after the selection, with a blank line on each
    /// side, and the caret on the line after it. On a rule, removes it.
    func toggleHorizontalRule() -> TextEdit? {
        let lines = buffer.lines(in: selection)
        var builder = EditBuilder(buffer)
        let rules = SpanIndex(syntax) { $0.kind == .thematicBreak }
        let isBlankLine = { (line: Int) in line < 0 || line >= self.buffer.lineCount || self.buffer.isBlank(line) }

        if lines.count == 1, !rules.containing(buffer.lineEnds[lines.lowerBound]..<buffer.lineEnds[lines.lowerBound]).isEmpty {
            let line = lines.lowerBound
            var removal: Range<Int>
            if line == 0 {
                removal = 0..<buffer.nextLineStart(0)
                if buffer.lineCount > 1, isBlankLine(1) {
                    removal = 0..<buffer.nextLineStart(1)
                }
            } else {
                removal = buffer.lineEnds[line - 1]..<buffer.lineEnds[line]
                // Blank lines on both sides would leave two: take one with it.
                if line >= 2, isBlankLine(line - 1), isBlankLine(line + 1) {
                    removal = buffer.lineEnds[line - 2]..<buffer.lineEnds[line]
                }
            }
            builder.delete(removal)
            let caret = builder.map(selection.lowerBound, .before)
            return builder.textEdit(selection: caret..<caret)
        }

        let line = lines.upperBound
        let rule = [UInt16]("---")
        let isLast = line + 1 == buffer.lineCount
        let lineAfter = isLast || !isBlankLine(line + 1) ? buffer.lineBreak : []
        let caret: Int
        if lines.count == 1, buffer.isBlank(line) {
            let lineBefore = line > 0 && !isBlankLine(line - 1) ? buffer.lineBreak : []
            let replacement = lineBefore + rule + lineAfter
            builder.replace(buffer.lineStarts[line]..<buffer.lineEnds[line], with: replacement)
            caret = lineAfter.isEmpty
                ? builder.map(buffer.nextLineStart(line), .after)
                : buffer.lineStarts[line] + replacement.count
        } else {
            let insertion = buffer.lineBreak + buffer.lineBreak + rule + lineAfter
            builder.insert(insertion, at: buffer.lineEnds[line])
            caret = lineAfter.isEmpty
                ? builder.map(buffer.nextLineStart(line), .after)
                : buffer.lineEnds[line] + insertion.count
        }
        return builder.textEdit(selection: caret..<caret)
    }
}
