import Foundation

/// Lexical highlighter, port of the Kotlin one. Offsets are UTF-16 so they can be
/// applied to an NSAttributedString directly.
enum MdCodeHighlighter {

    enum Kind: Int {
        case keyword, string, number, comment, type, function
    }

    struct Token {
        let start: Int
        let end: Int
        let kind: Kind
    }

    private static let keywords: Set<String> = [
        "if", "else", "for", "while", "return", "break", "continue", "switch", "case",
        "default", "do", "try", "catch", "finally", "throw", "new", "this", "null",
        "true", "false", "import", "from", "export", "class", "extends", "implements",
        "interface", "enum", "public", "private", "protected", "static", "final",
        "const", "let", "var", "function", "fun", "val", "def", "async", "await",
        "yield", "in", "is", "as", "not", "and", "or", "with", "lambda", "pass",
        "raise", "elif", "when", "object", "override", "suspend", "data", "sealed",
        "struct", "func", "guard", "defer", "protocol", "extension", "typealias",
        "where", "self", "init", "deinit", "nil", "package", "type", "select",
        "insert", "update", "delete", "join", "group", "order",
    ]

    private static let types: Set<String> = [
        "String", "Int", "Double", "Float", "Boolean", "Bool", "Long", "Char", "Array",
        "List", "Map", "Set", "Any", "Void", "Unit", "Object", "Number", "Promise",
        "React", "View", "Text", "UIView", "NSString", "CGFloat", "Optional",
    ]

    private static let hashCommentLangs: Set<String> = [
        "python", "py", "sh", "bash", "zsh", "ruby", "rb", "yaml", "yml", "toml", "makefile", "r", "perl",
    ]
    private static let dashCommentLangs: Set<String> = ["sql", "lua", "haskell"]

    static func tokenize(_ code: String, language: String) -> [Token] {
        let chars = Array(code)
        // char index -> utf16 offset
        var offsets = [Int](repeating: 0, count: chars.count + 1)
        var acc = 0
        for (i, c) in chars.enumerated() {
            offsets[i] = acc
            acc += String(c).utf16.count
        }
        offsets[chars.count] = acc

        let lang = language.lowercased()
        let hash = hashCommentLangs.contains(lang)
        let dash = dashCommentLangs.contains(lang)

        var tokens: [Token] = []
        var i = 0
        let n = chars.count

        func push(_ from: Int, _ to: Int, _ kind: Kind) {
            tokens.append(Token(start: offsets[from], end: offsets[min(to, n)], kind: kind))
        }

        while i < n {
            let c = chars[i]
            if c == "/", i + 1 < n, chars[i + 1] == "/" {
                let end = lineEnd(chars, i); push(i, end, .comment); i = end
            } else if c == "/", i + 1 < n, chars[i + 1] == "*" {
                var j = i + 2
                while j + 1 < n, !(chars[j] == "*" && chars[j + 1] == "/") { j += 1 }
                let end = min(j + 2, n)
                push(i, end, .comment); i = end
            } else if c == "#", hash {
                let end = lineEnd(chars, i); push(i, end, .comment); i = end
            } else if c == "-", dash, i + 1 < n, chars[i + 1] == "-" {
                let end = lineEnd(chars, i); push(i, end, .comment); i = end
            } else if c == "\"" || c == "'" || c == "`" {
                var j = i + 1
                while j < n {
                    if chars[j] == "\\" { j += 2; continue }
                    if chars[j] == c { j += 1; break }
                    if chars[j] == "\n" && c != "`" { break }
                    j += 1
                }
                let end = min(j, n)
                push(i, end, .string); i = end
            } else if c.isNumber, i == 0 || !isWord(chars[i - 1]) {
                var j = i
                while j < n, chars[j].isLetter || chars[j].isNumber || chars[j] == "." || chars[j] == "_" { j += 1 }
                push(i, j, .number); i = j
            } else if isWordStart(c) {
                var j = i
                while j < n, isWord(chars[j]) { j += 1 }
                let word = String(chars[i..<j])
                var k = j
                while k < n, chars[k] == " " { k += 1 }
                if keywords.contains(word) {
                    push(i, j, .keyword)
                } else if types.contains(word) || (word.count > 1 && (word.first?.isUppercase ?? false)) {
                    push(i, j, .type)
                } else if k < n, chars[k] == "(" {
                    push(i, j, .function)
                }
                i = j
            } else {
                i += 1
            }
        }
        return tokens
    }

    private static func lineEnd(_ chars: [Character], _ from: Int) -> Int {
        var i = from
        while i < chars.count, chars[i] != "\n" { i += 1 }
        return i
    }

    private static func isWordStart(_ c: Character) -> Bool { c.isLetter || c == "_" || c == "$" }
    private static func isWord(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" || c == "$" }
}
