/// The state one editing command works on: the text, the selection, and the
/// syntax map, parsed only if the command needs it.
final class EditingDocument {
    let text: String
    let buffer: TextBuffer
    let selection: Range<Int>
    private let suppliedSyntax: SyntaxMap?

    init(_ text: String, selection: Range<Int>, syntax: SyntaxMap?) {
        self.text = text
        buffer = TextBuffer(text)
        self.selection = buffer.clamp(selection)
        // A map of some other text would point at the wrong characters.
        suppliedSyntax = syntax?.utf16Length == buffer.count ? syntax : nil
    }

    private(set) lazy var syntax: SyntaxMap = self.suppliedSyntax ?? SyntaxMap(parsing: self.text)

    private(set) lazy var codeBlocks = SpanIndex(self.syntax) { $0.kind.isCodeBlock }
    private(set) lazy var inlineCodeSpans = SpanIndex(self.syntax) { $0.kind == .inlineCode }
    private(set) lazy var linkSpans = SpanIndex(self.syntax) { $0.kind.isLink || $0.kind.isImage }
    /// Headings with one marker: setext ones, and ATX ones without a closing sequence.
    private(set) lazy var singleMarkerHeadings = SpanIndex(self.syntax) { $0.kind.isHeading && $0.markers.count == 1 }

    var units: [UInt16] { buffer.units }

    func isInCodeBlock(_ offset: Int) -> Bool {
        !codeBlocks.containing(offset..<offset).isEmpty
    }

    /// Whether a line is inside a code block, fences included.
    func isInCodeBlock(line: Int) -> Bool {
        isInCodeBlock(buffer.lineEnds[line])
    }

    /// The selection after a command that changed whole lines. A selection
    /// that started at a line start keeps what was inserted there; a caret
    /// moves past it.
    func lineSelection(after builder: EditBuilder) -> Range<Int> {
        let startsLine = !selection.isEmpty
            && selection.lowerBound == buffer.lineStarts[buffer.lineIndex(containing: selection.lowerBound)]
        let lower = builder.map(selection.lowerBound, startsLine ? .before : .after)
        let upper = selection.isEmpty ? lower : builder.map(selection.upperBound, .after)
        return lower..<max(lower, upper)
    }

    /// An edit that changes nothing: the command applies here but has no effect.
    var unchanged: TextEdit {
        TextEdit(range: selection.lowerBound..<selection.lowerBound, replacement: "", selection: selection)
    }
}

/// Spans of some kinds, sorted by start, for finding the ones around a range.
struct SpanIndex {
    let spans: [SyntaxSpan]
    /// Largest end among `spans[0...i]`: no span at or before `i` reaches past it.
    private let reach: [Int]

    init(_ map: SyntaxMap, _ isIncluded: (SyntaxSpan) -> Bool) {
        let spans = map.spans.filter(isIncluded)
        var reach: [Int] = []
        reach.reserveCapacity(spans.count)
        var farthest = Int.min
        for span in spans {
            farthest = max(farthest, span.range.upperBound)
            reach.append(farthest)
        }
        self.spans = spans
        self.reach = reach
    }

    /// Spans whose range contains `range`, innermost first. For an empty
    /// range, spans that contain its offset or end at it.
    func containing(_ range: Range<Int>) -> [SyntaxSpan] {
        var result: [SyntaxSpan] = []
        var index = prefixLength(where: { $0.range.lowerBound <= range.lowerBound }) - 1
        while index >= 0, reach[index] >= range.upperBound {
            if spans[index].range.upperBound >= range.upperBound {
                result.append(spans[index])
            }
            index -= 1
        }
        return result
    }

    /// Spans that overlap a non-empty `range`, in order.
    func overlapping(_ range: Range<Int>) -> [SyntaxSpan] {
        var result: [SyntaxSpan] = []
        var index = prefixLength(where: { $0.range.lowerBound < range.upperBound }) - 1
        while index >= 0, reach[index] > range.lowerBound {
            if spans[index].range.upperBound > range.lowerBound {
                result.append(spans[index])
            }
            index -= 1
        }
        return result.reversed()
    }

    /// How many spans from the start satisfy `isBefore`, which must hold for
    /// a prefix of `spans` and fail for the rest.
    private func prefixLength(where isBefore: (SyntaxSpan) -> Bool) -> Int {
        var low = 0
        var high = spans.count
        while low < high {
            let mid = (low + high) / 2
            if isBefore(spans[mid]) {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }
}

extension SyntaxKind {
    var isCodeBlock: Bool {
        if case .codeBlock = self {
            return true
        }
        return false
    }

    var isHeading: Bool {
        if case .heading = self {
            return true
        }
        return false
    }

    var isLink: Bool {
        if case .link = self {
            return true
        }
        return false
    }

    var isImage: Bool {
        if case .image = self {
            return true
        }
        return false
    }
}
