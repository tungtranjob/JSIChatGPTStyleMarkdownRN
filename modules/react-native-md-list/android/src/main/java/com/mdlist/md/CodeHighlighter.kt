package com.mdlist.md

/**
 * Deliberately small, allocation-light syntax highlighter.
 *
 * A real grammar engine (tree-sitter/Prism) is 100x the cost for a chat list; a
 * lexical pass over comments / strings / numbers / keywords gets ~95% of the
 * visual benefit for a few microseconds per code block, and it runs off the main
 * thread anyway.
 */
object CodeHighlighter {

    class Token(@JvmField val start: Int, @JvmField val end: Int, @JvmField val kind: Int)

    const val KIND_KEYWORD = 0
    const val KIND_STRING = 1
    const val KIND_NUMBER = 2
    const val KIND_COMMENT = 3
    const val KIND_TYPE = 4
    const val KIND_FUNC = 5

    private val COMMON = setOf(
        "if", "else", "for", "while", "return", "break", "continue", "switch", "case",
        "default", "do", "try", "catch", "finally", "throw", "new", "this", "null",
        "true", "false", "import", "from", "export", "class", "extends", "implements",
        "interface", "enum", "public", "private", "protected", "static", "final",
        "const", "let", "var", "function", "fun", "val", "def", "async", "await",
        "yield", "in", "is", "as", "not", "and", "or", "with", "lambda", "pass",
        "raise", "elif", "when", "object", "override", "suspend", "data", "sealed",
        "struct", "func", "guard", "defer", "protocol", "extension", "typealias",
        "where", "self", "init", "deinit", "nil", "package", "type", "range", "map",
        "select", "insert", "update", "delete", "where", "join", "group", "order",
    )

    private val TYPES = setOf(
        "String", "Int", "Double", "Float", "Boolean", "Bool", "Long", "Char", "Array",
        "List", "Map", "Set", "Any", "Void", "Unit", "Object", "Number", "Promise",
        "React", "View", "Text", "UIView", "NSString", "CGFloat", "Optional",
    )

    fun tokenize(code: String, language: String): List<Token> {
        val out = ArrayList<Token>(64)
        val lang = language.lowercase()
        val hashComments = lang in setOf("python", "py", "sh", "bash", "zsh", "ruby", "rb", "yaml", "yml", "toml", "makefile", "r", "perl")
        val dashComments = lang in setOf("sql", "lua", "haskell")
        var i = 0
        val n = code.length
        while (i < n) {
            val c = code[i]
            when {
                c == '/' && i + 1 < n && code[i + 1] == '/' -> {
                    val end = lineEnd(code, i); out.add(Token(i, end, KIND_COMMENT)); i = end
                }
                c == '/' && i + 1 < n && code[i + 1] == '*' -> {
                    val end = (code.indexOf("*/", i + 2).takeIf { it >= 0 }?.plus(2)) ?: n
                    out.add(Token(i, end, KIND_COMMENT)); i = end
                }
                c == '#' && hashComments -> {
                    val end = lineEnd(code, i); out.add(Token(i, end, KIND_COMMENT)); i = end
                }
                c == '-' && dashComments && i + 1 < n && code[i + 1] == '-' -> {
                    val end = lineEnd(code, i); out.add(Token(i, end, KIND_COMMENT)); i = end
                }
                c == '"' || c == '\'' || c == '`' -> {
                    var j = i + 1
                    while (j < n) {
                        if (code[j] == '\\') { j += 2; continue }
                        if (code[j] == c) { j++; break }
                        if (code[j] == '\n' && c != '`') break
                        j++
                    }
                    out.add(Token(i, j.coerceAtMost(n), KIND_STRING)); i = j
                }
                c.isDigit() && (i == 0 || !isWord(code[i - 1])) -> {
                    var j = i
                    while (j < n && (code[j].isLetterOrDigit() || code[j] == '.' || code[j] == '_')) j++
                    out.add(Token(i, j, KIND_NUMBER)); i = j
                }
                isWordStart(c) -> {
                    var j = i
                    while (j < n && isWord(code[j])) j++
                    val word = code.substring(i, j)
                    var k = j
                    while (k < n && code[k] == ' ') k++
                    when {
                        COMMON.contains(word) -> out.add(Token(i, j, KIND_KEYWORD))
                        TYPES.contains(word) || (word[0].isUpperCase() && word.length > 1) ->
                            out.add(Token(i, j, KIND_TYPE))
                        k < n && code[k] == '(' -> out.add(Token(i, j, KIND_FUNC))
                    }
                    i = j
                }
                else -> i++
            }
        }
        return out
    }

    private fun lineEnd(s: String, from: Int): Int {
        val idx = s.indexOf('\n', from)
        return if (idx < 0) s.length else idx
    }

    private fun isWordStart(c: Char) = c.isLetter() || c == '_' || c == '$'
    private fun isWord(c: Char) = c.isLetterOrDigit() || c == '_' || c == '$'
}
