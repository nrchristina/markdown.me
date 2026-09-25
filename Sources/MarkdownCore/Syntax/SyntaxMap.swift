
/// Semantic map of a Markdown document: which ranges of the source are
/// headings, emphasis, list markers and so on.
///
/// All ranges are UTF-16 offsets into the source string, which is what
/// `NSString` and `NSTextView` use; `NSRange(span.range)` converts one.
/// The editor styles `range`/`contentRange` and hides `markers` in Text mode.
public struct SyntaxMap: Hashable, Sendable {
    /// Every recognised element, ordered by start; an enclosing element comes
    /// before the elements nested in it.
    public let spans: [SyntaxSpan]

    /// All syntax characters of the document, sorted, with touching and
    /// overlapping ranges merged. This is what Text mode hides.
    public let markerRanges: [Range<Int>]

    /// Length of the parsed text in UTF-16 code units.
    public let utf16Length: Int

    public init(parsing text: String) {
        let index = SourceIndex(text)
        let document = CMarkDocument(parsing: text)
        var builder = SyntaxMapBuilder(index: index)
        withExtendedLifetime(document) {
            builder.visit(document.root, SyntaxMapBuilder.Context())
        }

        // By start, enclosing before enclosed; equal ranges (cmark gives
        // `***a***` the same range for its emphasis and its strong) keep the
        // tree's order.
        spans = builder.spans.enumerated().sorted { lhs, rhs in
            if lhs.element.range.lowerBound != rhs.element.range.lowerBound {
                return lhs.element.range.lowerBound < rhs.element.range.lowerBound
            }
            if lhs.element.range.upperBound != rhs.element.range.upperBound {
                return lhs.element.range.upperBound > rhs.element.range.upperBound
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
        markerRanges = Self.merged(spans.flatMap(\.markers))
        utf16Length = index.utf16Count
    }

    /// Spans that overlap `range`, plus empty spans positioned inside it.
    public func spans(intersecting range: Range<Int>) -> [SyntaxSpan] {
        spans.filter { span in
            span.range.overlaps(range)
                || (span.range.isEmpty && range.contains(span.range.lowerBound))
        }
    }

    private static func merged(_ ranges: [Range<Int>]) -> [Range<Int>] {
        var result: [Range<Int>] = []
        for range in ranges.filter({ !$0.isEmpty }).sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = result.last, range.lowerBound <= last.upperBound {
                result[result.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else {
                result.append(range)
            }
        }
        return result
    }
}

/// One Markdown element in the source.
public struct SyntaxSpan: Hashable, Sendable {
    public var kind: SyntaxKind

    /// The whole element, syntax characters included.
    public var range: Range<Int>

    /// The part that stays visible in Text mode. For inline elements and
    /// headings: the text between the opening and closing markers. For block
    /// quotes and list items: everything after the first line's marker.
    public var contentRange: Range<Int>

    /// Syntax characters that belong to this element — `**`, `# `, `> `, the
    /// `](url)` of a link. Empty when the element has none or when they could
    /// not be located reliably; the editor must never hide text that is not
    /// listed here.
    public var markers: [Range<Int>]

    public init(kind: SyntaxKind, range: Range<Int>, contentRange: Range<Int>, markers: [Range<Int>]) {
        self.kind = kind
        self.range = range
        self.contentRange = contentRange
        self.markers = markers
    }
}

public enum SyntaxKind: Hashable, Sendable {
    case heading(level: Int)
    case strong
    case emphasis
    case strikethrough
    case inlineCode
    /// Fenced or indented. An indented block has no markers.
    case codeBlock(language: String?)
    /// `depth` is 1 for a top-level quote, 2 for a quote inside it, and so on.
    case blockQuote(depth: Int)
    /// `ordinal` is the item's number in an ordered list, `nil` for bullets.
    /// `depth` is 0 for a top-level list.
    case listItem(ordinal: Int?, depth: Int)
    /// The `[ ]` / `[x]` of a task list item; the range covers the brackets.
    case taskCheckbox(isChecked: Bool)
    case link(destination: String?)
    case image(source: String?)
    case thematicBreak
    /// A GFM table. Its inline content is mapped; its pipes are not markers.
    case table
    /// A single inline HTML tag such as `<span style="color: red">`.
    case inlineHTML
    case htmlBlock
}
