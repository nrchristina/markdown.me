import cmark_gfm
import cmark_gfm_extensions

/// A 1-based line and a 1-based column counted in UTF-8 bytes, as cmark
/// reports positions.
struct SourcePosition: Hashable, Comparable {
    var line: Int
    var column: Int

    static func < (lhs: SourcePosition, rhs: SourcePosition) -> Bool {
        (lhs.line, lhs.column) < (rhs.line, rhs.column)
    }
}

/// A document parsed by cmark-gfm with the GFM table, strikethrough and task
/// list extensions. The node tree lives as long as this object.
///
/// cmark's own tree is walked directly: building swift-markdown's tree on
/// top of it costs more than the whole syntax map may take.
final class CMarkDocument {
    let root: CMarkNode

    init(parsing text: String) {
        cmark_gfm_core_extensions_ensure_registered()
        let parser = cmark_parser_new(CMARK_OPT_SOURCEPOS | CMARK_OPT_TABLE_SPANS)
        defer { cmark_parser_free(parser) }
        for name in ["table", "strikethrough", "tasklist"] {
            cmark_parser_attach_syntax_extension(parser, cmark_find_syntax_extension(name))
        }
        cmark_parser_feed(parser, text, text.utf8.count)
        root = CMarkNode(cmark_parser_finish(parser))
    }

    deinit {
        cmark_node_free(root.pointer)
    }
}

/// A node of a `CMarkDocument`. Valid only while its document is alive.
struct CMarkNode {
    enum Kind: Equatable {
        case document, blockQuote, bulletList, orderedList, item, codeBlock, htmlBlock
        case paragraph, heading, thematicBreak
        case text, softBreak, lineBreak, code, htmlInline, emphasis, strong, link, image
        case strikethrough, table, tableHeader, tableRow, tableCell
        case other
    }

    let pointer: UnsafeMutablePointer<cmark_node>

    init(_ pointer: UnsafeMutablePointer<cmark_node>) {
        self.pointer = pointer
    }

    var kind: Kind {
        switch cmark_node_get_type(pointer) {
        case CMARK_NODE_DOCUMENT: return .document
        case CMARK_NODE_BLOCK_QUOTE: return .blockQuote
        case CMARK_NODE_LIST:
            return cmark_node_get_list_type(pointer) == CMARK_ORDERED_LIST ? .orderedList : .bulletList
        case CMARK_NODE_ITEM: return .item
        case CMARK_NODE_CODE_BLOCK: return .codeBlock
        case CMARK_NODE_HTML_BLOCK: return .htmlBlock
        case CMARK_NODE_PARAGRAPH: return .paragraph
        case CMARK_NODE_HEADING: return .heading
        case CMARK_NODE_THEMATIC_BREAK: return .thematicBreak
        case CMARK_NODE_TEXT: return .text
        case CMARK_NODE_SOFTBREAK: return .softBreak
        case CMARK_NODE_LINEBREAK: return .lineBreak
        case CMARK_NODE_CODE: return .code
        case CMARK_NODE_HTML_INLINE: return .htmlInline
        case CMARK_NODE_EMPH: return .emphasis
        case CMARK_NODE_STRONG: return .strong
        case CMARK_NODE_LINK: return .link
        case CMARK_NODE_IMAGE: return .image
        default:
            // Extension node types are only identifiable by name.
            switch typeName {
            case "strikethrough": return .strikethrough
            case "table": return .table
            case "table_header": return .tableHeader
            case "table_row":
                return cmark_gfm_extensions_get_table_row_is_header(pointer) != 0 ? .tableHeader : .tableRow
            case "table_cell": return .tableCell
            default: return .other
            }
        }
    }

    /// The node's range with swift-markdown's conventions: the end is
    /// exclusive, a code span includes its backticks, and positions cmark
    /// does not track are `nil`.
    var range: Range<SourcePosition>? {
        let startLine = Int(cmark_node_get_start_line(pointer))
        let startColumn = Int(cmark_node_get_start_column(pointer))
        let endLine = Int(cmark_node_get_end_line(pointer))
        let endColumn = Int(cmark_node_get_end_column(pointer)) + 1
        guard startLine > 0, startColumn > 0, endLine > 0, endColumn > 0 else { return nil }
        let backticks = Int(cmark_node_get_backtick_count(pointer))
        let start = SourcePosition(line: startLine, column: startColumn - backticks)
        let end = SourcePosition(line: endLine, column: endColumn + backticks)
        return start <= end ? start..<end : nil
    }

    var children: Children {
        Children(current: cmark_node_first_child(pointer))
    }

    struct Children: Sequence, IteratorProtocol {
        var current: UnsafeMutablePointer<cmark_node>?

        mutating func next() -> CMarkNode? {
            guard let node = current else { return nil }
            current = cmark_node_next(node)
            return CMarkNode(node)
        }
    }

    var headingLevel: Int {
        Int(cmark_node_get_heading_level(pointer))
    }

    /// The info string of a fenced code block.
    var fenceInfo: String? {
        guard let info = cmark_node_get_fence_info(pointer) else { return nil }
        let string = String(cString: info)
        return string.isEmpty ? nil : string
    }

    var isFenced: Bool {
        var length: Int32 = 0
        var offset: Int32 = 0
        var character: CChar = 0
        return cmark_node_get_fenced(pointer, &length, &offset, &character) != 0
    }

    var listStart: Int {
        Int(cmark_node_get_list_start(pointer))
    }

    /// For a task list item, whether it is checked; `nil` for other items.
    var isChecked: Bool? {
        guard typeName == "tasklist" else { return nil }
        return cmark_gfm_extensions_get_tasklist_item_checked(pointer)
    }

    /// A link's destination or an image's source.
    var url: String? {
        guard let url = cmark_node_get_url(pointer) else { return nil }
        let string = String(cString: url)
        return string.isEmpty ? nil : string
    }

    /// The text of a text node.
    var literal: String {
        guard let literal = cmark_node_get_literal(pointer) else { return "" }
        return String(cString: literal)
    }

    private var typeName: String {
        String(cString: cmark_node_get_type_string(pointer))
    }
}
