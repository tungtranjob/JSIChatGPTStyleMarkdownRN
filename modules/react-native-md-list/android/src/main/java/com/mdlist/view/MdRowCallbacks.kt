package com.mdlist.view

interface MdRowCallbacks {
    fun onLinkPress(url: String)
    fun onCopyCode(code: String, language: String)
    fun onCopyText(text: CharSequence)
}
