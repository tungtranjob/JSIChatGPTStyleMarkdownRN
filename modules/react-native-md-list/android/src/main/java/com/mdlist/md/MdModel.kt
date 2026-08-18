package com.mdlist.md

/**
 * Flat, immutable representation of a parsed markdown document.
 *
 * A message is *flattened into rows* (one row = one block) instead of being kept
 * as a tree. That is the single most important decision for scrolling: a 4000
 * word assistant answer becomes ~60 small recyclable rows instead of one giant
 * cell, so RecyclerView/UITableView only ever measures + draws what is on screen.
 */

const val SPAN_BOLD = 1 shl 0
const val SPAN_ITALIC = 1 shl 1
const val SPAN_CODE = 1 shl 2
const val SPAN_STRIKE = 1 shl 3

class InlineSpan(
    @JvmField val start: Int,
    @JvmField val end: Int,
    @JvmField val style: Int,
    @JvmField val link: String?,
)

class InlineText(@JvmField val text: String, @JvmField val spans: List<InlineSpan>) {
    companion object {
        val EMPTY = InlineText("", emptyList())
    }
}

enum class RowType {
    /** assistant paragraph */
    PARAGRAPH,
    HEADING,
    LIST_ITEM,
    CODE,
    TABLE,
    DIVIDER,
    /** whole user message rendered as a right aligned bubble */
    BUBBLE,
}

const val ALIGN_LEFT = 0
const val ALIGN_CENTER = 1
const val ALIGN_RIGHT = 2

class MdTable(
    @JvmField val header: List<InlineText>,
    @JvmField val rows: List<List<InlineText>>,
    @JvmField val aligns: IntArray,
)

class MdRow(
    @JvmField val id: String,
    @JvmField val messageId: String,
    @JvmField val type: RowType,
    @JvmField val isUser: Boolean,
    @JvmField val inline: InlineText = InlineText.EMPTY,
    @JvmField val headingLevel: Int = 0,
    @JvmField val listMarker: String? = null,
    @JvmField val listDepth: Int = 0,
    @JvmField val quoteDepth: Int = 0,
    /** -1 = not a task item, 0 = unchecked, 1 = checked */
    @JvmField val checked: Int = -1,
    @JvmField val code: String? = null,
    @JvmField val language: String? = null,
    @JvmField val table: MdTable? = null,
    @JvmField val isFirstInMessage: Boolean = false,
    @JvmField val isLastInMessage: Boolean = false,
    /** true while the message is still streaming: its last row must never be cached */
    @JvmField val streaming: Boolean = false,
) {
    /** Cheap content fingerprint used by DiffUtil so unchanged rows are never re-bound. */
    @JvmField
    val contentHash: Int = run {
        var h = type.ordinal
        h = 31 * h + inline.text.hashCode()
        h = 31 * h + headingLevel
        h = 31 * h + (listMarker?.hashCode() ?: 0)
        h = 31 * h + listDepth
        h = 31 * h + quoteDepth
        h = 31 * h + checked
        h = 31 * h + (code?.hashCode() ?: 0)
        h = 31 * h + (language?.hashCode() ?: 0)
        h = 31 * h + (table?.let { t -> t.rows.size * 31 + t.header.size } ?: 0)
        h = 31 * h + (if (isFirstInMessage) 1 else 0)
        h = 31 * h + (if (isLastInMessage) 2 else 0)
        h
    }

    /** Layout cache key: identity + content, so a streamed edit invalidates only its own row. */
    @JvmField
    val layoutKey: String = "$id#$contentHash"
}
