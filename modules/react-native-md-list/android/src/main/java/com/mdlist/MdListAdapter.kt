package com.mdlist

import android.content.Context
import android.view.View
import android.view.ViewGroup
import androidx.recyclerview.widget.AsyncListDiffer
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.RecyclerView
import com.mdlist.md.BubbleRowLayout
import com.mdlist.md.CodeRowLayout
import com.mdlist.md.DividerRowLayout
import com.mdlist.md.MdLayoutEngine
import com.mdlist.md.MdRow
import com.mdlist.md.RowType
import com.mdlist.md.TableRowLayout
import com.mdlist.md.TextRowLayout
import com.mdlist.view.MdBubbleRowView
import com.mdlist.view.MdCodeRowView
import com.mdlist.view.MdDividerRowView
import com.mdlist.view.MdRowCallbacks
import com.mdlist.view.MdTableRowView
import com.mdlist.view.MdTextRowView

class MdListAdapter(
    private val context: Context,
    private var engine: MdLayoutEngine,
    private val callbacks: MdRowCallbacks,
) : RecyclerView.Adapter<MdListAdapter.Holder>() {

    class Holder(view: View) : RecyclerView.ViewHolder(view)

    private val differ = AsyncListDiffer(this, DIFF)

    /** Content width used for text layout; set by the host view. */
    @JvmField var rowWidth: Int = 0

    init {
        setHasStableIds(true)
    }

    val rows: List<MdRow> get() = differ.currentList

    fun submit(list: List<MdRow>, onCommitted: Runnable) = differ.submitList(list, onCommitted)

    fun updateEngine(next: MdLayoutEngine) {
        engine = next
        notifyDataSetChanged()
    }

    override fun getItemCount(): Int = differ.currentList.size

    override fun getItemId(position: Int): Long = differ.currentList[position].id.hashCode().toLong()

    override fun getItemViewType(position: Int): Int = differ.currentList[position].type.ordinal

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): Holder {
        val theme = engine.theme
        val view: View = when (RowType.entries[viewType]) {
            RowType.CODE -> MdCodeRowView(context, theme)
            RowType.TABLE -> MdTableRowView(context, theme)
            RowType.DIVIDER -> MdDividerRowView(context, theme)
            RowType.BUBBLE -> MdBubbleRowView(context, theme)
            else -> MdTextRowView(context, theme)
        }
        view.layoutParams = RecyclerView.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
        )
        return Holder(view)
    }

    override fun onBindViewHolder(holder: Holder, position: Int) {
        val row = differ.currentList[position]
        // Almost always a cache hit: the layout was built on the prefetch thread.
        val layout = engine.layoutFor(row, rowWidth)
        when (val v = holder.itemView) {
            is MdCodeRowView -> v.bind(layout as CodeRowLayout, callbacks)
            is MdTableRowView -> v.bind(layout as TableRowLayout)
            is MdDividerRowView -> v.bind(layout as DividerRowLayout)
            is MdBubbleRowView -> v.bind(layout as BubbleRowLayout, callbacks)
            is MdTextRowView -> v.bind(layout as TextRowLayout, callbacks)
        }
    }

    companion object {
        private val DIFF = object : DiffUtil.ItemCallback<MdRow>() {
            override fun areItemsTheSame(a: MdRow, b: MdRow) = a.id == b.id
            override fun areContentsTheSame(a: MdRow, b: MdRow) = a.contentHash == b.contentHash
        }
    }
}
