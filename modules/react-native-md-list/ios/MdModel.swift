import Foundation

/// Mirror of the Kotlin model: a message is flattened into small, recyclable rows.
/// Keeping both platforms on the same data shape means one mental model, one set
/// of edge cases, and identical rendering rules.

struct MdInlineStyle: OptionSet {
    let rawValue: Int
    static let bold = MdInlineStyle(rawValue: 1 << 0)
    static let italic = MdInlineStyle(rawValue: 1 << 1)
    static let code = MdInlineStyle(rawValue: 1 << 2)
    static let strike = MdInlineStyle(rawValue: 1 << 3)
}

struct MdSpan {
    let start: Int   // UTF-16 offset
    let end: Int     // UTF-16 offset
    let style: MdInlineStyle
    let link: String?
}

struct MdInlineText {
    let text: String
    let spans: [MdSpan]
    static let empty = MdInlineText(text: "", spans: [])
}

enum MdRowType: Int {
    case paragraph = 0
    case heading = 1
    case listItem = 2
    case code = 3
    case table = 4
    case divider = 5
    case bubble = 6
}

enum MdAlign: Int {
    case left = 0, center = 1, right = 2
}

struct MdTable {
    let header: [MdInlineText]
    let rows: [[MdInlineText]]
    let aligns: [MdAlign]
}

final class MdRow {
    let id: String
    let messageId: String
    let type: MdRowType
    let inline: MdInlineText
    let headingLevel: Int
    let listMarker: String?
    let listDepth: Int
    let quoteDepth: Int
    /// -1 none, 0 unchecked, 1 checked
    let checked: Int
    let code: String?
    let language: String?
    let table: MdTable?
    var isFirstInMessage: Bool
    var isLastInMessage: Bool
    let streaming: Bool

    /// Content fingerprint: drives both diffing and the layout cache key.
    private(set) lazy var contentHash: Int = {
        var hasher = Hasher()
        hasher.combine(type.rawValue)
        hasher.combine(inline.text)
        hasher.combine(headingLevel)
        hasher.combine(listMarker)
        hasher.combine(listDepth)
        hasher.combine(quoteDepth)
        hasher.combine(checked)
        hasher.combine(code)
        hasher.combine(language)
        hasher.combine(table?.rows.count ?? 0)
        hasher.combine(isFirstInMessage)
        hasher.combine(isLastInMessage)
        return hasher.finalize()
    }()

    var layoutKey: String { "\(id)#\(contentHash)" }

    init(
        id: String,
        messageId: String,
        type: MdRowType,
        inline: MdInlineText = .empty,
        headingLevel: Int = 0,
        listMarker: String? = nil,
        listDepth: Int = 0,
        quoteDepth: Int = 0,
        checked: Int = -1,
        code: String? = nil,
        language: String? = nil,
        table: MdTable? = nil,
        isFirstInMessage: Bool = false,
        isLastInMessage: Bool = false,
        streaming: Bool = false
    ) {
        self.id = id
        self.messageId = messageId
        self.type = type
        self.inline = inline
        self.headingLevel = headingLevel
        self.listMarker = listMarker
        self.listDepth = listDepth
        self.quoteDepth = quoteDepth
        self.checked = checked
        self.code = code
        self.language = language
        self.table = table
        self.isFirstInMessage = isFirstInMessage
        self.isLastInMessage = isLastInMessage
        self.streaming = streaming
    }
}
