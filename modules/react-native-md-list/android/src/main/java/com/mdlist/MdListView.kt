package com.mdlist

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.LruCache
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.ProgressBar
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.ReactContext
import com.facebook.react.bridge.ReadableArray
import com.facebook.react.bridge.WritableMap
import com.facebook.react.uimanager.UIManagerHelper
import com.facebook.react.uimanager.events.Event
import com.mdlist.md.MarkdownParser
import com.mdlist.md.MdLayoutEngine
import com.mdlist.md.MdRow
import com.mdlist.md.MdTheme
import com.mdlist.view.MdRowCallbacks
import java.util.concurrent.Executors
import kotlin.math.max
import kotlin.math.min

/**
 * The whole chat list lives here, natively.
 *
 * Pipeline per messages update:
 *   JS props -> [main] cheap string copy -> [parser thread] parse only the messages
 *   whose content hash changed -> flatten to rows -> [main] AsyncListDiffer ->
 *   RecyclerView rebinds only what actually changed. Text layout for rows near the
 *   viewport is warmed on a second worker thread so binding is a cache hit.
 */
class MdListView(context: Context) : FrameLayout(context), MdRowCallbacks {

    private class Msg(val id: String, val role: String, val markdown: String, val streaming: Boolean)

    private val recycler = RecyclerView(context)
    private val layoutManager = LinearLayoutManager(context).apply { stackFromEnd = true }
    private val spinner = ProgressBar(context)

    private var theme = MdTheme(false, 16f, resources.displayMetrics.density, resources.configuration.fontScale)
    private var engine = MdLayoutEngine(theme)
    private val adapter = MdListAdapter(context, engine, this)

    private val parseExecutor = Executors.newSingleThreadExecutor { r -> Thread(r, "md-parse") }
    private val warmExecutor = Executors.newSingleThreadExecutor { r -> Thread(r, "md-layout") }
    private val main = Handler(Looper.getMainLooper())
    private val parseCache = object : LruCache<String, List<MdRow>>(80) {}

    private var pending: List<Msg> = emptyList()
    private var generation = 0
    private var lastWarmGeneration = 0

    private var atBottom = true
    private var startReachedFor: String? = null
    private var lastVisibleFirst = -1
    private var lastVisibleLast = -1

    // ---- props -------------------------------------------------------------
    private var colorScheme = "light"
    private var fontSize = 16.0
    private var topInset = 0
    private var bottomInset = 0
    private var prefetchRows = 12
    private var autoScrollToBottom = true
    private var startReachedThreshold = 600.0

    init {
        recycler.layoutManager = layoutManager
        recycler.adapter = adapter
        recycler.setHasFixedSize(true)
        // Rows never animate: an item animator would re-run layout while streaming.
        recycler.itemAnimator = null
        recycler.setItemViewCacheSize(24)
        recycler.clipToPadding = false
        recycler.overScrollMode = View.OVER_SCROLL_IF_CONTENT_SCROLLS
        layoutManager.isItemPrefetchEnabled = true
        layoutManager.initialPrefetchItemCount = 6
        recycler.recycledViewPool.apply {
            setMaxRecycledViews(0, 32) // paragraphs
            setMaxRecycledViews(2, 24) // list items
        }
        addView(recycler, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))

        spinner.visibility = View.GONE
        addView(
            spinner,
            LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT, Gravity.TOP or Gravity.CENTER_HORIZONTAL).apply {
                topMargin = theme.dp(12f).toInt()
            },
        )
        applyBackground()

        recycler.addOnScrollListener(object : RecyclerView.OnScrollListener() {
            override fun onScrollStateChanged(rv: RecyclerView, state: Int) {
                if (state == RecyclerView.SCROLL_STATE_DRAGGING) {
                    // don't let a React ScrollView ancestor steal the gesture
                    parent?.requestDisallowInterceptTouchEvent(true)
                }
            }

            override fun onScrolled(rv: RecyclerView, dx: Int, dy: Int) {
                onListScrolled()
            }
        })
    }

    // ------------------------------------------------------------------ props

    fun setMessages(array: ReadableArray?) {
        val next = ArrayList<Msg>(array?.size() ?: 0)
        for (i in 0 until (array?.size() ?: 0)) {
            val m = array!!.getMap(i) ?: continue
            next.add(
                Msg(
                    id = m.getString("id") ?: i.toString(),
                    role = m.getString("role") ?: "assistant",
                    markdown = m.getString("markdown") ?: "",
                    streaming = m.hasKey("streaming") && !m.isNull("streaming") && m.getBoolean("streaming"),
                )
            )
        }
        pending = next
        // Coalesce prop bursts (streaming pushes a new array every token) into one
        // parse per frame.
        main.removeCallbacks(parseRunnable)
        main.post(parseRunnable)
    }

    fun setColorScheme(value: String?) {
        val next = value ?: "light"
        if (next == colorScheme) return
        colorScheme = next
        rebuildTheme()
    }

    fun setFontSize(value: Double) {
        if (value == fontSize || value <= 0) return
        fontSize = value
        rebuildTheme()
    }

    fun setTopInset(value: Double) {
        topInset = theme.dp(value.toFloat()).toInt()
        applyInsets()
    }

    fun setBottomInset(value: Double) {
        bottomInset = theme.dp(value.toFloat()).toInt()
        applyInsets()
    }

    fun setLoadingOlder(value: Boolean) {
        spinner.visibility = if (value) View.VISIBLE else View.GONE
        if (!value) startReachedFor = null
    }

    fun setPrefetchRows(value: Int) {
        prefetchRows = value.coerceIn(0, 60)
    }

    fun setAutoScrollToBottom(value: Boolean) {
        autoScrollToBottom = value
    }

    fun setStartReachedThreshold(value: Double) {
        startReachedThreshold = value
    }

    // --------------------------------------------------------------- commands

    fun scrollToBottom(animated: Boolean) {
        val last = adapter.itemCount - 1
        if (last < 0) return
        if (animated) recycler.smoothScrollToPosition(last) else recycler.scrollToPosition(last)
    }

    fun scrollToMessage(messageId: String, animated: Boolean) {
        val index = adapter.rows.indexOfFirst { it.messageId == messageId }
        if (index < 0) return
        if (animated) recycler.smoothScrollToPosition(index)
        else layoutManager.scrollToPositionWithOffset(index, 0)
    }

    // ------------------------------------------------------------- pipeline

    private val parseRunnable = Runnable { startParse() }

    private fun startParse() {
        val input = pending
        val gen = ++generation
        parseExecutor.execute {
            val rows = ArrayList<MdRow>(input.size * 8)
            for (m in input) {
                val key = "${m.id}|${m.role}|${m.markdown.length}|${m.markdown.hashCode()}"
                var parsed = if (m.streaming) null else parseCache.get(key)
                if (parsed == null) {
                    parsed = MarkdownParser.parse(m.id, m.role, m.markdown, m.streaming)
                    if (!m.streaming) parseCache.put(key, parsed)
                }
                rows.addAll(parsed)
            }
            main.post {
                if (gen == generation) applyRows(rows)
            }
        }
    }

    private fun applyRows(rows: List<MdRow>) {
        val wasAtBottom = atBottom
        adapter.rowWidth = contentWidth()
        adapter.submit(rows) {
            if (autoScrollToBottom && wasAtBottom && rows.isNotEmpty()) {
                recycler.scrollToPosition(rows.size - 1)
            }
            warmAround()
        }
    }

    private fun contentWidth(): Int {
        val w = if (recycler.width > 0) recycler.width else width
        return max(0, w - recycler.paddingLeft - recycler.paddingRight)
    }

    /** Lays out the rows just outside the viewport on a worker thread. */
    private fun warmAround() {
        val width = adapter.rowWidth
        if (width <= 0) return
        val rows = adapter.rows
        if (rows.isEmpty()) return
        val first = layoutManager.findFirstVisibleItemPosition().let { if (it < 0) 0 else it }
        val last = layoutManager.findLastVisibleItemPosition().let { if (it < 0) min(rows.size - 1, 8) else it }
        val from = max(0, first - prefetchRows)
        val to = min(rows.size - 1, last + prefetchRows)
        val slice = ArrayList<MdRow>(to - from + 1)
        for (i in from..to) slice.add(rows[i])
        val gen = ++lastWarmGeneration
        // pin the engine: a theme change swaps it out on the main thread
        val target = engine
        warmExecutor.execute {
            for (row in slice) {
                if (gen != lastWarmGeneration) return@execute
                target.layoutFor(row, width)
            }
        }
    }

    private fun onListScrolled() {
        val rows = adapter.rows
        if (rows.isEmpty()) return

        val first = layoutManager.findFirstVisibleItemPosition()
        val last = layoutManager.findLastVisibleItemPosition()
        if (first != lastVisibleFirst || last != lastVisibleLast) {
            lastVisibleFirst = first
            lastVisibleLast = last
            emit("topVisibleRangeChange", Arguments.createMap().apply {
                putInt("firstIndex", first)
                putInt("lastIndex", last)
                putInt("blockCount", rows.size)
            })
            warmAround()
        }

        val nowAtBottom = !recycler.canScrollVertically(1)
        if (nowAtBottom != atBottom) {
            atBottom = nowAtBottom
            emit("topAtBottomChange", Arguments.createMap().apply { putBoolean("atBottom", nowAtBottom) })
        }

        // "load older" trigger: distance from the top of the content in px
        val offset = recycler.computeVerticalScrollOffset()
        if (offset < theme.dp(startReachedThreshold.toFloat())) {
            val oldest = rows.firstOrNull()?.messageId ?: return
            if (startReachedFor != oldest) {
                startReachedFor = oldest
                emit("topStartReached", Arguments.createMap().apply { putString("oldestId", oldest) })
            }
        }
    }

    // ------------------------------------------------------------- callbacks

    override fun onLinkPress(url: String) {
        emit("topLinkPress", Arguments.createMap().apply { putString("url", url) })
    }

    override fun onCopyCode(code: String, language: String) {
        copyToClipboard(code)
        emit("topCodeCopy", Arguments.createMap().apply {
            putString("code", code)
            putString("language", language)
        })
    }

    override fun onCopyText(text: CharSequence) {
        copyToClipboard(text.toString())
    }

    private fun copyToClipboard(text: String) {
        val cm = context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager ?: return
        cm.setPrimaryClip(ClipData.newPlainText("markdown", text))
    }

    private fun emit(name: String, payload: WritableMap) {
        val reactContext = context as? ReactContext ?: return
        val dispatcher = UIManagerHelper.getEventDispatcherForReactTag(reactContext, id) ?: return
        dispatcher.dispatchEvent(MdEvent(UIManagerHelper.getSurfaceId(this), id, name, payload))
    }

    private class MdEvent(
        surfaceId: Int,
        viewId: Int,
        private val name: String,
        private val payload: WritableMap,
    ) : Event<MdEvent>(surfaceId, viewId) {
        override fun getEventName(): String = name
        override fun getEventData(): WritableMap = payload
    }

    // ------------------------------------------------------------------ theme

    private fun rebuildTheme() {
        theme = MdTheme(
            dark = colorScheme == "dark",
            baseSp = fontSize.toFloat(),
            density = resources.displayMetrics.density,
            fontScale = resources.configuration.fontScale,
        )
        engine = MdLayoutEngine(theme)
        adapter.updateEngine(engine)
        applyBackground()
        applyInsets()
        warmAround()
    }

    private fun applyBackground() {
        setBackgroundColor(theme.background)
    }

    private fun applyInsets() {
        recycler.setPadding(0, topInset, 0, bottomInset)
    }

    // ------------------------------------------------- React layout plumbing

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        if (w != oldw && w > 0) {
            adapter.rowWidth = contentWidth()
            adapter.notifyDataSetChanged()
            warmAround()
        }
    }

    /**
     * React Native does not run the Android measure/layout pass on views it does
     * not own, so a native ViewGroup has to schedule it itself.
     */
    override fun requestLayout() {
        super.requestLayout()
        if (!isLayoutRequestPosted && width > 0 && height > 0) {
            isLayoutRequestPosted = true
            post(measureAndLayout)
        }
    }

    private var isLayoutRequestPosted = false

    private val measureAndLayout = Runnable {
        isLayoutRequestPosted = false
        measure(
            MeasureSpec.makeMeasureSpec(width, MeasureSpec.EXACTLY),
            MeasureSpec.makeMeasureSpec(height, MeasureSpec.EXACTLY),
        )
        layout(left, top, right, bottom)
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        main.removeCallbacks(parseRunnable)
    }

    fun onDropView() {
        main.removeCallbacks(parseRunnable)
        parseExecutor.shutdownNow()
        warmExecutor.shutdownNow()
        engine.clear()
        parseCache.evictAll()
    }
}
