/// A toolbar or Format menu command, as a pure function of the text and the
/// selection. It works the same in both editor modes, since both edit the
/// same Markdown.
public enum FormattingCommand: Hashable, Sendable {
    case bold
    case italic
    case strikethrough
    case inlineCode
    /// Levels 1 to 6; out-of-range levels are clamped.
    case heading(level: Int)
    /// Plain text: removes headings.
    case paragraph
    case bulletList
    case numberedList
    case taskList
    case blockquote
    case codeBlock
    case link
    case image
    case horizontalRule

    /// The edit that applies this formatting to the selection, or removes it
    /// where the selection already has it. Nil when there is nothing to change.
    ///
    /// - Parameters:
    ///   - selection: UTF-16 offsets; empty for a caret.
    ///   - syntax: the editor's current map of `text`, to save parsing it again.
    public func edit(in text: String, selection: Range<Int>, syntax: SyntaxMap? = nil) -> TextEdit? {
        let document = EditingDocument(text, selection: selection, syntax: syntax)
        switch self {
        case .bold:
            return document.toggle(.bold)
        case .italic:
            return document.toggle(.italic)
        case .strikethrough:
            return document.toggle(.strikethrough)
        case .inlineCode:
            return document.toggle(.code)
        case .heading(let level):
            return document.setHeading(level: min(max(level, 1), 6))
        case .paragraph:
            return document.setHeading(level: nil)
        case .bulletList:
            return document.toggleList(.bullet)
        case .numberedList:
            return document.toggleList(.ordered)
        case .taskList:
            return document.toggleList(.task)
        case .blockquote:
            return document.toggleQuote()
        case .codeBlock:
            return document.toggleCodeBlock()
        case .link:
            return document.toggleLink(isImage: false)
        case .image:
            return document.toggleLink(isImage: true)
        case .horizontalRule:
            return document.toggleHorizontalRule()
        }
    }
}
