/// Bold, italic, strikethrough and inline code: markers around text.
enum InlineStyle {
    case bold
    case italic
    case strikethrough
    case code

    var marker: [UInt16] {
        switch self {
        case .bold:
            return [.asterisk, .asterisk]
        case .italic:
            return [.asterisk]
        case .strikethrough:
            return [.tilde, .tilde]
        case .code:
            return [.backtick]
        }
    }

    func matches(_ kind: SyntaxKind) -> Bool {
        switch self {
        case .bold:
            return kind == .strong
        case .italic:
            return kind == .emphasis
        case .strikethrough:
            return kind == .strikethrough
        case .code:
            return kind == .inlineCode
        }
    }
}

extension EditingDocument {
    /// Removes the style where the selection already has it — the markers may
    /// be inside or outside the selection — and adds it otherwise. A caret
    /// works on the word it is in; with no word it inserts a pair of markers.
    /// A selection over several lines is styled line by line.
    func toggle(_ style: InlineStyle) -> TextEdit? {
        let styled = SpanIndex(syntax) { style.matches($0.kind) && $0.markers.count == 2 }
        if selection.isEmpty {
            return toggleAtCaret(style, styled)
        }

        let segments = inlineSegments()
        guard !segments.isEmpty else { return nil }
        let wrappers = segments.map { styled.containing($0).first }
        var builder = EditBuilder(buffer)
        let targets: [Range<Int>]
        if wrappers.allSatisfy({ $0 != nil }) {
            targets = []
            var unwrapped = Set<Range<Int>>()
            for case let span? in wrappers where unwrapped.insert(span.range).inserted {
                removeMarkers(of: span, style, &builder)
            }
        } else {
            let unstyled = zip(segments, wrappers).filter { $0.1 == nil }.map { $0.0 }
            targets = merged(unstyled.map { extended($0, style, styled) })
            for target in targets {
                wrap(target, style, styled, &builder)
            }
        }

        let newSelection: Range<Int>
        if segments.count == 1 {
            // Keep the text selected, inside its new markers or without its old ones.
            let kept = targets.first ?? selection
            let lower = builder.map(kept.lowerBound, .after)
            newSelection = lower..<max(lower, builder.map(kept.upperBound, .before))
        } else {
            let lower = builder.map(selection.lowerBound, .before)
            newSelection = lower..<max(lower, builder.map(selection.upperBound, .after))
        }
        return builder.textEdit(selection: newSelection)
    }

    private func toggleAtCaret(_ style: InlineStyle, _ styled: SpanIndex) -> TextEdit? {
        let line = buffer.line(buffer.lineIndex(containing: selection.lowerBound))
        let caret = max(selection.lowerBound, line.textStart)
        guard !isInCodeBlock(caret) else { return nil }
        var builder = EditBuilder(buffer)

        if let word = buffer.word(at: caret) {
            if let span = styled.containing(word).first {
                removeMarkers(of: span, style, &builder)
                let position = builder.map(caret, .after)
                return builder.textEdit(selection: position..<position)
            }
            let target = extended(word, style, styled)
            wrap(target, style, styled, &builder)
            let position = builder.map(caret, caret == target.upperBound ? .before : .after)
            return builder.textEdit(selection: position..<position)
        }

        let enclosing = styled.containing(caret..<caret).first {
            $0.contentRange.lowerBound <= caret && caret <= $0.contentRange.upperBound
        }
        if let enclosing {
            removeMarkers(of: enclosing, style, &builder)
            let position = builder.map(caret, .after)
            return builder.textEdit(selection: position..<position)
        }

        // Between the two markers of an empty pair: take them out again.
        let marker = style.marker
        let width = marker.count
        if buffer.run(of: marker[0], endingAt: caret) == width, buffer.run(of: marker[0], startingAt: caret) == width {
            builder.delete((caret - width)..<(caret + width))
            return builder.textEdit(selection: (caret - width)..<(caret - width))
        }
        builder.insert(marker + marker, at: caret)
        return builder.textEdit(selection: (caret + width)..<(caret + width))
    }

    /// The selected text of each line, without the line's block syntax
    /// (quote, list and heading markers) and surrounding whitespace. Lines in
    /// code blocks are left out.
    func inlineSegments() -> [Range<Int>] {
        var segments: [Range<Int>] = []
        for index in buffer.lines(in: selection) {
            let line = buffer.line(index)
            let lower = max(selection.lowerBound, line.textStart)
            var upper = min(selection.upperBound, line.end)
            if let closing = line.heading?.closing {
                upper = min(upper, closing.lowerBound)
            }
            guard lower < upper else { continue }
            let segment = buffer.trimmed(lower..<upper)
            guard !segment.isEmpty, !isInCodeBlock(segment.lowerBound) else { continue }
            segments.append(segment)
        }
        return segments
    }

    /// Grows `target` so that adding markers around it keeps the Markdown
    /// valid: over spans of the same style it overlaps (their markers go),
    /// over code spans it touches (markers inside code are literal), and over
    /// a whole link when it starts or ends inside the link's `](url)`.
    func extended(_ target: Range<Int>, _ style: InlineStyle?, _ styled: SpanIndex?) -> Range<Int> {
        var target = target
        var changed = true
        while changed {
            changed = false
            var covering = styled?.overlapping(target) ?? []
            if style != .code {
                covering += inlineCodeSpans.overlapping(target)
            }
            for span in linkSpans.overlapping(target) {
                let cutsSyntax = span.markers.contains { marker in
                    (marker.lowerBound < target.lowerBound && target.lowerBound < marker.upperBound)
                        || (marker.lowerBound < target.upperBound && target.upperBound < marker.upperBound)
                }
                if cutsSyntax {
                    covering.append(span)
                }
            }
            for span in covering where span.range.lowerBound < target.lowerBound || span.range.upperBound > target.upperBound {
                target = min(target.lowerBound, span.range.lowerBound)..<max(target.upperBound, span.range.upperBound)
                changed = true
            }
        }
        return target
    }

    private func wrap(_ target: Range<Int>, _ style: InlineStyle, _ styled: SpanIndex, _ builder: inout EditBuilder) {
        // Spans of the same style inside merge into this one.
        for span in styled.overlapping(target) {
            for marker in span.markers {
                builder.delete(marker)
            }
        }
        var opening = style.marker
        var closing = style.marker
        if style == .code {
            // Longer than any run of backticks inside, and padded with a
            // space if the code starts or ends with one.
            let longest = buffer.longestRun(of: .backtick, in: target)
            opening = [UInt16](repeating: .backtick, count: longest + 1)
            closing = opening
            if units[target.lowerBound] == .backtick || units[target.upperBound - 1] == .backtick {
                opening.append(.space)
                closing.insert(.space, at: 0)
            }
        }
        builder.insert(opening, at: target.lowerBound)
        builder.insert(closing, at: target.upperBound)
    }

    private func removeMarkers(of span: SyntaxSpan, _ style: InlineStyle, _ builder: inout EditBuilder) {
        guard span.markers.count == 2 else { return }
        var opening = span.markers[0]
        var closing = span.markers[1]
        // Code padded with a space on each side: the spaces are padding too.
        let content = span.contentRange
        if style == .code, content.count >= 2, units[content.lowerBound] == .space,
           units[content.upperBound - 1] == .space, !units[content].allSatisfy({ $0 == .space }) {
            opening = opening.lowerBound..<(opening.upperBound + 1)
            closing = (closing.lowerBound - 1)..<closing.upperBound
        }
        builder.delete(opening)
        builder.delete(closing)
    }

    private func merged(_ ranges: [Range<Int>]) -> [Range<Int>] {
        var result: [Range<Int>] = []
        for range in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = result.last, range.lowerBound < last.upperBound {
                result[result.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else {
                result.append(range)
            }
        }
        return result
    }

    // MARK: - Links and images

    /// `[text](url)` with `url` selected; with no text, `[](url)` with the
    /// caret between the brackets. On a link, removes the link and keeps its
    /// text. Images work the same way, with `path` always selected.
    func toggleLink(isImage: Bool) -> TextEdit? {
        let links = SpanIndex(syntax) { (isImage ? $0.kind.isImage : $0.kind.isLink) && !$0.markers.isEmpty }
        var builder = EditBuilder(buffer)

        let probe = selection.isEmpty ? selection : buffer.trimmed(selection)
        let enclosing = links.containing(probe).first { span in
            !selection.isEmpty || (span.range.lowerBound < probe.lowerBound && probe.upperBound < span.range.upperBound)
        }
        if let link = enclosing {
            if link.markers.count == 2 {
                builder.delete(link.markers[0])
                builder.delete(link.markers[1])
                let lower = builder.map(link.contentRange.lowerBound, .after)
                return builder.textEdit(selection: lower..<max(lower, builder.map(link.contentRange.upperBound, .before)))
            }
            // `[](url)` has no text to keep: keep the destination.
            let destination = self.destination(of: link.range)
            builder.replace(link.range, with: destination)
            let lower = link.range.lowerBound
            return builder.textEdit(selection: lower..<(lower + destination.count))
        }

        let opening: [UInt16] = isImage ? [.exclamationMark, .openingBracket] : [.openingBracket]
        let placeholder = [UInt16](isImage ? "path" : "url")
        let closing = [UInt16]("](") + placeholder + [UInt16](")")

        var target: Range<Int>?
        if selection.isEmpty {
            let line = buffer.line(buffer.lineIndex(containing: selection.lowerBound))
            let caret = max(selection.lowerBound, line.textStart)
            target = buffer.word(at: caret) ?? caret..<caret
        } else {
            let segments = inlineSegments()
            if let first = segments.first, let last = segments.last {
                target = first.lowerBound..<last.upperBound
            }
        }
        guard var target else { return nil }

        if target.isEmpty {
            builder.insert(opening + closing, at: target.lowerBound)
            if isImage {
                let start = target.lowerBound + opening.count + 2
                return builder.textEdit(selection: start..<(start + placeholder.count))
            }
            let caret = target.lowerBound + opening.count
            return builder.textEdit(selection: caret..<caret)
        }

        target = extended(target, nil, nil)
        builder.insert(opening, at: target.lowerBound)
        builder.insert(closing, at: target.upperBound)
        let start = builder.map(target.upperBound, .before) + 2
        return builder.textEdit(selection: start..<(start + placeholder.count))
    }

    /// What is between `](` and the final `)`.
    private func destination(of range: Range<Int>) -> [UInt16] {
        let link = Array(units[range])
        guard let close = link.lastIndex(of: .closingParenthesis) else { return [] }
        var open = 0
        while open + 1 < close, !(link[open] == .closingBracket && link[open + 1] == UInt16(ascii: "(")) {
            open += 1
        }
        guard open + 1 < close else { return [] }
        return Array(link[(open + 2)..<close])
    }
}
