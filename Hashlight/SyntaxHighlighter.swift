import AppKit

/// Simple syntax highlighter for code blocks
class SyntaxHighlighter {
    static let shared = SyntaxHighlighter()

    private init() {}

    // MARK: - Language Keywords

    private let swiftKeywords = Set([
        "func", "var", "let", "if", "else", "for", "while", "return", "import",
        "class", "struct", "enum", "protocol", "extension", "guard", "switch",
        "case", "default", "break", "continue", "throw", "throws", "try", "catch",
        "async", "await", "actor", "private", "public", "internal", "fileprivate",
        "static", "override", "final", "lazy", "weak", "unowned", "nil", "true",
        "false", "self", "Self", "super", "init", "deinit", "where", "in", "is",
        "as", "typealias", "associatedtype", "some", "any", "@State", "@Binding",
        "@Published", "@ObservedObject", "@StateObject", "@EnvironmentObject"
    ])

    private let pythonKeywords = Set([
        "def", "class", "if", "elif", "else", "for", "while", "return", "import",
        "from", "as", "try", "except", "finally", "raise", "with", "lambda",
        "pass", "break", "continue", "and", "or", "not", "in", "is", "None",
        "True", "False", "self", "global", "nonlocal", "yield", "async", "await"
    ])

    private let jsKeywords = Set([
        "function", "var", "let", "const", "if", "else", "for", "while", "return",
        "import", "export", "from", "class", "extends", "new", "this", "super",
        "try", "catch", "finally", "throw", "async", "await", "yield", "switch",
        "case", "default", "break", "continue", "typeof", "instanceof", "in",
        "of", "true", "false", "null", "undefined", "void", "delete"
    ])

    private let cKeywords = Set([
        "int", "char", "float", "double", "void", "long", "short", "unsigned",
        "signed", "if", "else", "for", "while", "do", "switch", "case", "default",
        "break", "continue", "return", "goto", "struct", "union", "enum", "typedef",
        "const", "static", "extern", "register", "volatile", "sizeof", "NULL",
        "true", "false", "inline", "restrict", "auto"
    ])

    private let javaKeywords = Set([
        "public", "private", "protected", "class", "interface", "extends", "implements",
        "abstract", "final", "static", "void", "int", "long", "double", "float",
        "boolean", "char", "byte", "short", "String", "new", "return", "if", "else",
        "for", "while", "do", "switch", "case", "default", "break", "continue",
        "try", "catch", "finally", "throw", "throws", "import", "package", "this",
        "super", "null", "true", "false", "instanceof", "synchronized", "volatile",
        "transient", "native", "enum", "assert", "var", "record", "sealed", "permits"
    ])

    private let bashKeywords = Set([
        "if", "then", "else", "elif", "fi", "for", "while", "do", "done", "case",
        "esac", "function", "return", "exit", "echo", "read", "local", "export",
        "source", "alias", "unalias", "set", "unset", "shift", "true", "false",
        "cd", "pwd", "ls", "cp", "mv", "rm", "mkdir", "rmdir", "cat", "grep",
        "sed", "awk", "find", "xargs", "sort", "uniq", "wc", "head", "tail"
    ])

    // Special action/status keywords for tree output
    private let actionKeywords = Set([
        "MAJOR", "REWRITE", "Update", "Review", "Add", "Remove", "Fix",
        "Verify", "Test", "Check", "SECURITY", "FIX", "TODO", "NOTE",
        "WARNING", "ERROR", "CRITICAL", "interface", "class", "enum",
        "struct", "protocol", "LOC", "files", "dependencies", "changes"
    ])

    private let sqlKeywords = Set([
        "SELECT", "FROM", "WHERE", "AND", "OR", "NOT", "IN", "LIKE", "BETWEEN",
        "IS", "NULL", "ORDER", "BY", "ASC", "DESC", "GROUP", "HAVING", "JOIN",
        "LEFT", "RIGHT", "INNER", "OUTER", "ON", "AS", "INSERT", "INTO", "VALUES",
        "UPDATE", "SET", "DELETE", "CREATE", "TABLE", "INDEX", "VIEW", "DROP",
        "ALTER", "ADD", "COLUMN", "PRIMARY", "KEY", "FOREIGN", "REFERENCES",
        "CONSTRAINT", "UNIQUE", "DEFAULT", "CHECK", "UNION", "ALL", "DISTINCT",
        "TOP", "LIMIT", "OFFSET", "CASE", "WHEN", "THEN", "ELSE", "END", "COUNT",
        "SUM", "AVG", "MIN", "MAX", "COALESCE", "NULLIF", "CAST", "CONVERT"
    ])

    // MARK: - Public API

    func highlight(code: String, language: String?, font: NSFont, theme: PreviewTheme) -> NSAttributedString {
        let result = NSMutableAttributedString(string: code, attributes: [
            .font: font,
            .foregroundColor: theme.textColor
        ])

        // Handle nil/empty language - check for tree structure
        let lang = language?.lowercased() ?? ""
        if lang.isEmpty {
            if looksLikeTree(code) {
                highlightTree(result, theme: theme)
            }
            return result
        }

        // Apply highlighting based on language
        switch lang {
        case "swift":
            highlightGeneric(result, keywords: swiftKeywords, theme: theme)
        case "python", "py":
            highlightPython(result, theme: theme)
        case "javascript", "js", "typescript", "ts":
            highlightGeneric(result, keywords: jsKeywords, theme: theme)
        case "c", "cpp", "c++", "objc", "objective-c":
            highlightGeneric(result, keywords: cKeywords, theme: theme)
        case "java", "kotlin":
            highlightGeneric(result, keywords: javaKeywords, theme: theme)
        case "bash", "sh", "shell", "zsh":
            // Check if it looks like a tree/directory structure
            if looksLikeTree(code) {
                highlightTree(result, theme: theme)
            } else {
                highlightBash(result, theme: theme)
            }
        case "tree", "directory", "output":
            highlightTree(result, theme: theme)
        case "sql":
            highlightSQL(result, theme: theme)
        case "json":
            highlightJSON(result, theme: theme)
        case "html", "xml":
            highlightHTML(result, theme: theme)
        default:
            // Check if it looks like a tree structure
            if looksLikeTree(code) {
                highlightTree(result, theme: theme)
            } else {
                // Generic highlighting for unknown languages
                highlightGeneric(result, keywords: swiftKeywords.union(jsKeywords).union(pythonKeywords), theme: theme)
            }
        }

        return result
    }

    // MARK: - Language-specific Highlighters

    private func highlightGeneric(_ result: NSMutableAttributedString, keywords: Set<String>, theme: PreviewTheme) {
        // Highlight strings (double and single quoted)
        highlightPattern(#""[^"\\]*(?:\\.[^"\\]*)*""#, in: result, color: theme.greenColor)
        highlightPattern(#"'[^'\\]*(?:\\.[^'\\]*)*'"#, in: result, color: theme.greenColor)

        // Highlight comments
        highlightPattern(#"//[^\n]*"#, in: result, color: theme.commentColor)
        highlightPattern(#"/\*[\s\S]*?\*/"#, in: result, color: theme.commentColor)

        // Highlight numbers
        highlightPattern(#"\b\d+\.?\d*\b"#, in: result, color: theme.orangeColor)

        // Highlight keywords
        highlightWords(keywords, in: result, color: theme.purpleColor)
    }

    private func highlightPython(_ result: NSMutableAttributedString, theme: PreviewTheme) {
        // Strings (including triple-quoted)
        highlightPattern(#"\"\"\"[\s\S]*?\"\"\""#, in: result, color: theme.greenColor)
        highlightPattern(#"'''[\s\S]*?'''"#, in: result, color: theme.greenColor)
        highlightPattern(#""[^"\\]*(?:\\.[^"\\]*)*""#, in: result, color: theme.greenColor)
        highlightPattern(#"'[^'\\]*(?:\\.[^'\\]*)*'"#, in: result, color: theme.greenColor)

        // Comments
        highlightPattern(#"#[^\n]*"#, in: result, color: theme.commentColor)

        // Numbers
        highlightPattern(#"\b\d+\.?\d*\b"#, in: result, color: theme.orangeColor)

        // Keywords
        highlightWords(pythonKeywords, in: result, color: theme.purpleColor)
    }

    private func highlightBash(_ result: NSMutableAttributedString, theme: PreviewTheme) {
        // Strings
        highlightPattern(#""[^"\\]*(?:\\.[^"\\]*)*""#, in: result, color: theme.greenColor)
        highlightPattern(#"'[^']*'"#, in: result, color: theme.greenColor)

        // Comments
        highlightPattern(#"#[^\n]*"#, in: result, color: theme.commentColor)

        // Variables
        highlightPattern(#"\$\w+"#, in: result, color: theme.yellowColor)
        highlightPattern(#"\$\{[^}]+\}"#, in: result, color: theme.yellowColor)

        // Keywords
        highlightWords(bashKeywords, in: result, color: theme.purpleColor)
    }

    private func highlightSQL(_ result: NSMutableAttributedString, theme: PreviewTheme) {
        // Strings
        highlightPattern(#"'[^']*'"#, in: result, color: theme.greenColor)

        // Comments
        highlightPattern(#"--[^\n]*"#, in: result, color: theme.commentColor)
        highlightPattern(#"/\*[\s\S]*?\*/"#, in: result, color: theme.commentColor)

        // Numbers
        highlightPattern(#"\b\d+\.?\d*\b"#, in: result, color: theme.orangeColor)

        // Keywords (case-insensitive for SQL). One cached alternation regex — the old
        // per-keyword loop bypassed regexCache and compiled ~60 fresh NSRegularExpressions on
        // EVERY call, and the preview highlights code blocks per line, so a 100-line SQL block
        // compiled ~6000 regexes per rebuild.
        if let regex = Self.sqlKeywordRegex {
            let text = result.string as NSString
            let matches = regex.matches(in: result.string, range: NSRange(location: 0, length: text.length))
            for match in matches {
                result.addAttribute(.foregroundColor, value: theme.purpleColor, range: match.range)
            }
        }
    }

    /// Compiled once: `\b(SELECT|FROM|...)\b`, case-insensitive. Built from `sqlKeywords`.
    private static let sqlKeywordRegex: NSRegularExpression? = {
        let alternation = SyntaxHighlighter.shared.sqlKeywords.joined(separator: "|")
        return try? NSRegularExpression(pattern: "\\b(?:\(alternation))\\b", options: .caseInsensitive)
    }()

    private func highlightJSON(_ result: NSMutableAttributedString, theme: PreviewTheme) {
        // Keys (strings before colons)
        highlightPattern(#""[^"]+"\s*:"#, in: result, color: theme.blueColor)

        // String values
        highlightPattern(#":\s*"[^"]*""#, in: result, color: theme.greenColor)

        // Numbers
        highlightPattern(#":\s*-?\d+\.?\d*"#, in: result, color: theme.orangeColor)

        // Booleans and null
        highlightPattern(#"\b(true|false|null)\b"#, in: result, color: theme.purpleColor)
    }

    private func highlightHTML(_ result: NSMutableAttributedString, theme: PreviewTheme) {
        // Tags
        highlightPattern(#"</?[\w-]+"#, in: result, color: theme.blueColor)
        highlightPattern(#"/?\s*>"#, in: result, color: theme.blueColor)

        // Attributes
        highlightPattern(#"\s[\w-]+="#, in: result, color: theme.yellowColor)

        // Attribute values
        highlightPattern(#""[^"]*""#, in: result, color: theme.greenColor)

        // Comments
        highlightPattern(#"<!--[\s\S]*?-->"#, in: result, color: theme.commentColor)
    }

    /// Check if code looks like a tree/directory structure
    private func looksLikeTree(_ code: String) -> Bool {
        let treeChars = ["├", "└", "│", "─", "├──", "└──"]
        let lines = code.components(separatedBy: .newlines)
        var treeLineCount = 0

        for line in lines {
            for char in treeChars {
                if line.contains(char) {
                    treeLineCount += 1
                    break
                }
            }
        }

        // If more than 30% of lines contain tree characters, treat as tree
        return lines.count > 0 && Double(treeLineCount) / Double(lines.count) > 0.3
    }

    /// Highlight tree/directory structure output (like from `tree` command or code structure diagrams)
    private func highlightTree(_ result: NSMutableAttributedString, theme: PreviewTheme) {
        let fileColor = theme.greenColor
        let labelColor = theme.yellowColor
        let treeCharColor = theme.commentColor
        let actionColor = theme.cyanColor
        let arrowColor = theme.redColor

        // 1. Highlight tree drawing characters (using alternation for Unicode safety)
        highlightPattern("├──|└──|│|─|├|└", in: result, color: treeCharColor)

        // 2. Highlight filenames with common extensions
        let filePattern = #"\b\w+\.(java|xml|swift|py|js|ts|json|yaml|yml|md|txt|html|css|sh|c|cpp|h|go|rs|properties|gradle)\b:?"#
        highlightPattern(filePattern, in: result, color: fileColor)

        // 3. Highlight labels ending with colon (like "pom.xml:" or "Source files:")
        highlightPattern(#"\b[\w\s]+:"#, in: result, color: labelColor)

        // 5. Highlight numbers
        highlightPattern(#"\b\d+\b"#, in: result, color: theme.orangeColor)

        // 6. Highlight action/status keywords
        for keyword in actionKeywords {
            highlightWord(keyword, in: result, color: actionColor)
        }

        // 7. Highlight arrows
        highlightPattern("→|->|=>|←|<-", in: result, color: arrowColor)

        // 8. Highlight version numbers (like 1.0.6, 2.3.x, 5.x)
        highlightPattern(#"\d+\.\d+[\.\dx]*"#, in: result, color: theme.greenColor)

        // 9. Highlight Java/code keywords that appear in tree
        let codeKeywords = ["API", "SDK", "LDAP", "HTTP", "SSL", "JWT", "OIDC", "Java", "Spring"]
        for keyword in codeKeywords {
            highlightWord(keyword, in: result, color: theme.blueColor)
        }
    }

    // MARK: - Helpers

    private static var regexCache: [String: NSRegularExpression] = [:]

    private static var keywordPatterns: [Set<String>: String] = [:]

    private func highlightWords(_ words: Set<String>, in result: NSMutableAttributedString, color: NSColor) {
        let pattern: String
        if let cached = Self.keywordPatterns[words] {
            pattern = cached
        } else {
            pattern = "\\b(?:" + words.sorted().map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|") + ")\\b"
            Self.keywordPatterns[words] = pattern
        }
        highlightPattern(pattern, in: result, color: color)
    }

    private func highlightPattern(_ pattern: String, in result: NSMutableAttributedString, color: NSColor) {
        let regex: NSRegularExpression
        if let cached = Self.regexCache[pattern] {
            regex = cached
        } else if let compiled = try? NSRegularExpression(pattern: pattern) {
            Self.regexCache[pattern] = compiled
            regex = compiled
        } else {
            return
        }
        let text = result.string as NSString
        let matches = regex.matches(in: result.string, range: NSRange(location: 0, length: text.length))

        for match in matches {
            result.addAttribute(.foregroundColor, value: color, range: match.range)
        }
    }

    private func highlightWord(_ word: String, in result: NSMutableAttributedString, color: NSColor) {
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: word))\\b"
        highlightPattern(pattern, in: result, color: color)
    }
}
