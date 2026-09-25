import MarkdownCore

extension String {
    /// The text at a UTF-16 range — what the editor sees at that `NSRange`.
    subscript(utf16 range: Range<Int>) -> String {
        let units = Array(utf16)
        return String(decoding: units[range.clamped(to: 0..<units.count)], as: UTF16.self)
    }
}

/// A span described by its text, so expectations read like the Markdown.
struct RenderedSpan: Equatable, Sendable, CustomStringConvertible {
    var kind: SyntaxKind
    var text: String
    var content: String
    var markers: [String]

    init(_ kind: SyntaxKind, _ text: String, content: String, markers: [String]) {
        self.kind = kind
        self.text = text
        self.content = content
        self.markers = markers
    }

    init(_ span: SyntaxSpan, in source: String) {
        self.init(
            span.kind,
            source[utf16: span.range],
            content: source[utf16: span.contentRange],
            markers: span.markers.map { source[utf16: $0] }
        )
    }

    var description: String {
        "\(kind) \(text.debugDescription) content: \(content.debugDescription) markers: \(markers)"
    }
}

func rendered(_ source: String) -> [RenderedSpan] {
    SyntaxMap(parsing: source).spans.map { RenderedSpan($0, in: source) }
}
