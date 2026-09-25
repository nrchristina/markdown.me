/// One replacement in a document: what a formatting command does to it.
///
/// Offsets are UTF-16 code units, like `NSRange` in `NSTextView`. The editor
/// applies an edit with a single `replaceCharacters(in:with:)`, which is one
/// undo step, and then selects `selection`. `range` is as small as the change
/// allows, so undo restores exactly what changed.
public struct TextEdit: Hashable, Sendable {
    /// What to replace, in the text before the edit.
    public var range: Range<Int>
    public var replacement: String
    /// The selection after the edit, in the edited text.
    public var selection: Range<Int>

    public init(range: Range<Int>, replacement: String, selection: Range<Int>) {
        self.range = range
        self.replacement = replacement
        self.selection = selection
    }

    /// False for an edit that only sets the selection.
    public var changesText: Bool {
        !range.isEmpty || !replacement.isEmpty
    }

    /// `text` with the edit applied.
    public func applied(to text: String) -> String {
        var units = Array(text.utf16)
        units.replaceSubrange(range.clamped(to: 0..<units.count), with: Array(replacement.utf16))
        return String(decoding: units, as: UTF16.self)
    }
}

/// Collects the changes a command makes, all in offsets of the original text,
/// and joins them into one minimal `TextEdit`.
struct EditBuilder {
    /// Where an offset goes when text is inserted exactly at it.
    enum Stickiness {
        case before
        case after
    }

    private struct Change {
        var range: Range<Int>
        var replacement: [UInt16]
        var order: Int
    }

    private let units: [UInt16]
    private var changes: [Change] = []

    init(_ buffer: TextBuffer) {
        units = buffer.units
    }

    var isEmpty: Bool { changes.isEmpty }

    /// Changes must not overlap. Insertions at one offset keep their order and
    /// go before a replacement that starts there.
    mutating func replace(_ range: Range<Int>, with replacement: [UInt16]) {
        guard !units[range].elementsEqual(replacement) else { return }
        changes.append(Change(range: range, replacement: replacement, order: changes.count))
    }

    mutating func insert(_ text: [UInt16], at offset: Int) {
        replace(offset..<offset, with: text)
    }

    mutating func delete(_ range: Range<Int>) {
        replace(range, with: [])
    }

    /// Where `offset` of the original text ends up. An offset inside replaced
    /// text goes to the start of the replacement, or with `.after` to its end.
    func map(_ offset: Int, _ stickiness: Stickiness) -> Int {
        var delta = 0
        for change in sortedChanges() {
            let range = change.range
            if range.lowerBound > offset {
                break
            }
            if range.isEmpty {
                if range.lowerBound < offset || stickiness == .after {
                    delta += change.replacement.count
                }
                continue
            }
            if range.upperBound <= offset {
                delta += change.replacement.count - range.count
                continue
            }
            return range.lowerBound + delta + (stickiness == .after ? change.replacement.count : 0)
        }
        return offset + delta
    }

    /// The single edit that covers every change, trimmed of text that stays
    /// the same; nil when nothing changes.
    func textEdit(selection: Range<Int>) -> TextEdit? {
        let changes = sortedChanges()
        guard let first = changes.first else { return nil }
        let lower = first.range.lowerBound
        var upper = lower
        var replacement: [UInt16] = []
        for change in changes {
            guard change.range.lowerBound >= upper else {
                assertionFailure("Overlapping changes")
                continue
            }
            replacement += units[upper..<change.range.lowerBound]
            replacement += change.replacement
            upper = change.range.upperBound
        }

        let original = units[lower..<upper]
        var prefix = 0
        while prefix < original.count, prefix < replacement.count,
              units[lower + prefix] == replacement[prefix] {
            prefix += 1
        }
        var suffix = 0
        while suffix < original.count - prefix, suffix < replacement.count - prefix,
              units[upper - 1 - suffix] == replacement[replacement.count - 1 - suffix] {
            suffix += 1
        }
        // Never cut a surrogate pair in two.
        if prefix > 0, (lower + prefix < upper && UTF16.isTrailSurrogate(units[lower + prefix]))
            || (prefix < replacement.count && UTF16.isTrailSurrogate(replacement[prefix])) {
            prefix -= 1
        }
        if suffix > 0, UTF16.isTrailSurrogate(units[upper - suffix])
            || UTF16.isTrailSurrogate(replacement[replacement.count - suffix]) {
            suffix -= 1
        }
        if prefix + suffix == original.count, prefix + suffix == replacement.count {
            return nil
        }

        let length = units.count - original.count + replacement.count
        let selectionLower = min(max(selection.lowerBound, 0), length)
        let selectionUpper = min(max(selection.upperBound, selectionLower), length)
        return TextEdit(
            range: (lower + prefix)..<(upper - suffix),
            replacement: String(decoding: replacement[prefix..<(replacement.count - suffix)], as: UTF16.self),
            selection: selectionLower..<selectionUpper
        )
    }

    private func sortedChanges() -> [Change] {
        changes.sorted { lhs, rhs in
            if lhs.range.lowerBound != rhs.range.lowerBound {
                return lhs.range.lowerBound < rhs.range.lowerBound
            }
            if lhs.range.isEmpty != rhs.range.isEmpty {
                return lhs.range.isEmpty
            }
            return lhs.order < rhs.order
        }
    }
}
