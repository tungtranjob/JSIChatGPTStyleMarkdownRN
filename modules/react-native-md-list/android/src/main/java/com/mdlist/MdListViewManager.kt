package com.mdlist

import com.facebook.react.bridge.ReadableArray
import com.facebook.react.module.annotations.ReactModule
import com.facebook.react.uimanager.SimpleViewManager
import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.uimanager.ViewManagerDelegate
import com.facebook.react.uimanager.annotations.ReactProp
import com.facebook.react.viewmanagers.MdListViewManagerDelegate
import com.facebook.react.viewmanagers.MdListViewManagerInterface

@ReactModule(name = MdListViewManager.NAME)
class MdListViewManager :
    SimpleViewManager<MdListView>(),
    MdListViewManagerInterface<MdListView> {

    private val mDelegate = MdListViewManagerDelegate<MdListView, MdListViewManager>(this)

    override fun getDelegate(): ViewManagerDelegate<MdListView> = mDelegate

    override fun getName(): String = NAME

    override fun createViewInstance(reactContext: ThemedReactContext): MdListView =
        MdListView(reactContext)

    override fun onDropViewInstance(view: MdListView) {
        view.onDropView()
        super.onDropViewInstance(view)
    }

    @ReactProp(name = "messages")
    override fun setMessages(view: MdListView, value: ReadableArray?) = view.setMessages(value)

    @ReactProp(name = "colorScheme")
    override fun setColorScheme(view: MdListView, value: String?) = view.setColorScheme(value)

    @ReactProp(name = "fontSize", defaultDouble = 16.0)
    override fun setFontSize(view: MdListView, value: Double) = view.setFontSize(value)

    @ReactProp(name = "topInset", defaultDouble = 0.0)
    override fun setTopInset(view: MdListView, value: Double) = view.setTopInset(value)

    @ReactProp(name = "bottomInset", defaultDouble = 0.0)
    override fun setBottomInset(view: MdListView, value: Double) = view.setBottomInset(value)

    @ReactProp(name = "loadingOlder", defaultBoolean = false)
    override fun setLoadingOlder(view: MdListView, value: Boolean) = view.setLoadingOlder(value)

    @ReactProp(name = "startReachedThreshold", defaultDouble = 600.0)
    override fun setStartReachedThreshold(view: MdListView, value: Double) =
        view.setStartReachedThreshold(value)

    @ReactProp(name = "prefetchRows", defaultInt = 12)
    override fun setPrefetchRows(view: MdListView, value: Int) = view.setPrefetchRows(value)

    @ReactProp(name = "autoScrollToBottom", defaultBoolean = true)
    override fun setAutoScrollToBottom(view: MdListView, value: Boolean) =
        view.setAutoScrollToBottom(value)

    override fun scrollToBottom(view: MdListView, animated: Boolean) = view.scrollToBottom(animated)

    override fun scrollToMessage(view: MdListView, messageId: String, animated: Boolean) =
        view.scrollToMessage(messageId, animated)

    override fun getExportedCustomDirectEventTypeConstants(): MutableMap<String, Any> {
        val map = HashMap<String, Any>()
        super.getExportedCustomDirectEventTypeConstants()?.let { map.putAll(it) }
        map["topStartReached"] = mapOf("registrationName" to "onStartReached")
        map["topLinkPress"] = mapOf("registrationName" to "onLinkPress")
        map["topCodeCopy"] = mapOf("registrationName" to "onCodeCopy")
        map["topAtBottomChange"] = mapOf("registrationName" to "onAtBottomChange")
        map["topVisibleRangeChange"] = mapOf("registrationName" to "onVisibleRangeChange")
        return map
    }

    companion object {
        const val NAME = "MdListView"
    }
}
