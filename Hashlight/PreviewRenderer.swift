import AppKit

/// What a preview build cannot make by itself: the pictures a document references and its
/// Mermaid and KaTeX renders. The app's preview (`MarkdownTextView`) loads and renders them,
/// returning nil until one is ready and rebuilding when it lands. The Quick Look extension has
/// no source: it shows a placeholder for pictures and the source of diagrams and math.
protocol PreviewResourceSource {
    /// A picture the document references (block or inline), or nil for its placeholder.
    func image(path: String) -> NSImage?
    /// The rendered Mermaid diagram, or nil while it renders.
    func mermaidDiagram(_ code: String) -> NSImage?
    /// The rendered KaTeX math, or nil while it renders.
    func math(_ latex: String, displayMode: Bool) -> NSImage?
}

/// Builds the native preview's attributed text, one parsed Markdown element at a time. The
/// app's preview and the Quick Look extension both use it, so they render a document the same
/// way; layout (column width, alignment, margins) belongs to `PreviewTextView`.
struct PreviewRenderer {
    let mainFontID: String
    let fixedFontID: String
    /// Body text and code-block sizes at 100 % zoom (Settings → Viewing → Fonts). Every size in
    /// the build is written for the defaults and scaled by `mainScale` or `fixedScale`.
    let mainFontSize: CGFloat
    let fixedFontSize: CGFloat
    let theme: PreviewTheme
    let zoomLevel: CGFloat
    /// Images and diagrams are sized once at build time from the column's preset width.
    let contentWidth: PreviewContentWidth
    /// Header-category column sizing; nil (column weighting off) sizes columns to their content.
    let tableColumnConfiguration: MarkdownTableColumnConfiguration?
    /// The document's location, for relative pictures in HTML blocks.
    let baseURL: URL?
    let resources: (any PreviewResourceSource)?

    /// Scale of every proportional size against the 16 pt default body text.
    private var mainScale: CGFloat {
        mainFontSize / CGFloat(PreviewFontCatalog.defaultMainSize)
    }

    /// Scale of every monospaced size against the 13 pt default code blocks.
    private var fixedScale: CGFloat {
        fixedFontSize / CGFloat(PreviewFontCatalog.defaultFixedSize)
    }

    /// The whole document without the app's element cache, as Quick Look shows it.
    func attributedString(for elements: [MarkdownParser.Element], showsFrontmatter: Bool, frontmatterExpanded: Bool) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        for element in elements {
            // With frontmatter off the document starts at its first content element.
            if case .frontmatter = element, !showsFrontmatter { continue }
            render(element, to: result, frontmatterExpanded: frontmatterExpanded)
        }
        return result
    }

    /// Dispatch a parsed element to the appropriate append method
    func render(_ element: MarkdownParser.Element, to result: NSMutableAttributedString, frontmatterExpanded: Bool) {
        switch element {
        case .heading1(let text): appendHeading(text: text, level: 1, to: result)
        case .heading2(let text): appendHeading(text: text, level: 2, to: result)
        case .heading3(let text): appendHeading(text: text, level: 3, to: result)
        case .heading4(let text): appendHeading(text: text, level: 4, to: result)
        case .heading5(let text): appendHeading(text: text, level: 5, to: result)
        case .heading6(let text): appendHeading(text: text, level: 6, to: result)
        case .paragraph(let text): appendParagraph(text: text, to: result)
        case .frontmatter(let lines): appendFrontmatter(lines: lines, expanded: frontmatterExpanded, to: result)
        case .list(let items): appendList(items: items, to: result)
        case .codeBlock(let code, let language): appendCodeBlock(code: code, language: language, to: result)
        case .mermaidBlock(let code): appendMermaidBlock(code: code, to: result)
        case .displayMath(let latex): appendDisplayMath(latex: latex, to: result)
        case .table(let rows, let alignments): appendTable(rows: rows, alignments: alignments, to: result)
        case .image(let alt, let path): appendImage(alt: alt, path: path, to: result)
        case .horizontalRule: appendHorizontalRule(to: result)
        case .blockquote(let text): appendBlockquote(text: text, to: result)
        case .alert(let kind, let text): appendAlert(kind: kind, text: text, to: result)
        case .htmlBlock(let html): appendHTMLBlock(html: html, to: result)
        }
    }

    // MARK: - Append Methods

    private func appendHeading(text: String, level: Int, to result: NSMutableAttributedString) {
        let sizes: [Int: CGFloat] = [1: 28, 2: 24, 3: 20, 4: 18, 5: 16, 6: 15]
        let size = (sizes[level] ?? 16) * zoomLevel
        let font = mainFont(size: size).withWeight(.semibold)

        // Heading color hierarchy
        let headingColors: [Int: NSColor] = [
            1: theme.blueColor,
            2: theme.blueColor.withAlphaComponent(0.85),
            3: theme.strongTextColor,
            4: theme.secondaryTextColor,
            5: theme.secondaryTextColor,
            6: theme.secondaryTextColor
        ]
        let color = headingColors[level] ?? theme.textColor

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.paragraphSpacingBefore = level == 1 ? 24 : (level == 2 ? 20 : 16)
        paragraphStyle.paragraphSpacing = (level <= 2) ? 4 : 8

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle
        ]

        let formatted = formatInlineMarkdown(text, attributes: attributes)
        result.append(formatted)
        result.append(NSAttributedString(string: "\n"))

        // H1 and H2 get a subtle underline divider
        if level <= 2 {
            let dividerStyle = NSMutableParagraphStyle()
            dividerStyle.paragraphSpacing = 10
            let dividerLength = level == 1 ? 50 : 35
            let dividerColor = theme.blueColor.withAlphaComponent(level == 1 ? 0.4 : 0.25)
            result.append(NSAttributedString(string: String(repeating: "─", count: dividerLength) + "\n", attributes: [
                .font: NSFont.systemFont(ofSize: 6),
                .foregroundColor: dividerColor,
                .paragraphStyle: dividerStyle
            ]))
        }
    }

    private func appendParagraph(text: String, to result: NSMutableAttributedString) {
        let font = mainFont(size: 16 * zoomLevel)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.paragraphSpacing = 10
        paragraphStyle.lineSpacing = 4

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: theme.textColor,
            .paragraphStyle: paragraphStyle
        ]

        let formatted = formatInlineMarkdown(text, attributes: attributes)
        result.append(formatted)
        result.append(NSAttributedString(string: "\n"))
    }

    private func appendList(items: [(level: Int, text: String, isOrdered: Bool, startNumber: Int?)], to result: NSMutableAttributedString) {
        let font = mainFont(size: 16 * zoomLevel)

        // Track ordered list counters per nesting level. The list's first item carries an
        // optional startNumber from the source markdown; subsequent items at the same level
        // continue sequentially. A list opening with `4. foo` renders as `4.`, not `1.`.
        var orderedCounters: [Int: Int] = [:]

        for (level, text, isOrdered, startNumber) in items {
            // Calculate indentation based on nesting level
            let baseIndent: CGFloat = 16
            let levelIndent: CGFloat = CGFloat(level) * 20

            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.headIndent = baseIndent + levelIndent + 24
            paragraphStyle.firstLineHeadIndent = baseIndent + levelIndent
            paragraphStyle.paragraphSpacing = 3
            paragraphStyle.lineSpacing = 3

            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: theme.textColor,
                .paragraphStyle: paragraphStyle
            ]

            var bulletPrefix: String
            var itemText = text

            // Task list items (read-only: the viewer never changes the file).
            if let isChecked = MarkdownParser.taskState(ofItemText: text) {
                bulletPrefix = isChecked ? "☑  " : "☐  "
                itemText = String(text.dropFirst(4))
                orderedCounters[level] = nil
            } else if isOrdered {
                let counter: Int
                if let existing = orderedCounters[level] {
                    counter = existing + 1
                } else if let start = startNumber {
                    // First item at this level — honor the explicit start number from source.
                    counter = start
                } else {
                    counter = 1
                }
                orderedCounters[level] = counter
                bulletPrefix = "\(counter).  "
            } else {
                // Determine bullet style based on nesting level
                let bullets = ["•", "◦", "▪", "▹"]
                let bullet = bullets[min(level, bullets.count - 1)]
                bulletPrefix = "\(bullet)  "
                orderedCounters[level] = nil
            }

            let bulletColor = theme.blueColor.withAlphaComponent(0.8)
            let bulletAttr = NSMutableAttributedString(string: bulletPrefix, attributes: [
                .font: font,
                .foregroundColor: bulletColor,
                .paragraphStyle: paragraphStyle
            ])
            result.append(bulletAttr)

            let formatted = formatInlineMarkdown(itemText, attributes: attributes)
            result.append(formatted)
            result.append(NSAttributedString(string: "\n"))
        }
    }

    private func appendFrontmatter(lines: [String], expanded: Bool, to result: NSMutableAttributedString) {
        guard !lines.isEmpty else { return }

        // The typesetter ignores paragraphSpacingBefore on the container's first paragraph, and
        // the frontmatter is always first, so the card would lose its top inset. A paragraph of
        // (near) zero height ahead of the card makes the header the second paragraph; the
        // text view clips drawing to the container, so the card cannot simply extend upward.
        if result.length == 0 {
            let spacerStyle = NSMutableParagraphStyle()
            spacerStyle.maximumLineHeight = 0.01
            spacerStyle.lineSpacing = 0
            spacerStyle.paragraphSpacing = 0
            result.append(NSAttributedString(string: "\n", attributes: [
                .font: NSFont.systemFont(ofSize: 1),
                .paragraphStyle: spacerStyle
            ]))
        }
        let blockStart = result.length

        // Xcode's rendering: a bordered card holding a disclosure row labelled with the
        // document's title (or a generic label), and, when open, the YAML as written in
        // monospace. PreviewTextView toggles the block when the header row is clicked
        // (frontmatterToggleKey); the pointer shows a hand over it.
        let labelFont = mainFont(size: 12 * zoomLevel)
        let yamlFont = fixedFont(size: 12 * zoomLevel)
        let yamlLines = lines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        let title = yamlLines.lazy.compactMap { line -> String? in
            guard let colon = line.firstIndex(of: ":"),
                  line[..<colon].trimmingCharacters(in: .whitespaces).lowercased() == "title" else { return nil }
            let value = Self.unquotedYAMLScalar(String(line[line.index(after: colon)...]))
            return value.isEmpty ? nil : value
        }.first

        let header = NSMutableAttributedString(string: (expanded ? FrontmatterFold.expandedMarker : FrontmatterFold.collapsedMarker) + " ", attributes: [
            .font: labelFont,
            .foregroundColor: theme.secondaryTextColor
        ])
        header.append(NSAttributedString(string: title ?? "Document Info", attributes: [
            .font: labelFont,
            .foregroundColor: theme.secondaryTextColor
        ]))
        if title == nil, !expanded {
            let keys = yamlLines.compactMap { line -> String? in
                guard let colon = line.firstIndex(of: ":") else { return nil }
                let key = line[..<colon].trimmingCharacters(in: .whitespaces)
                return key.isEmpty ? nil : key
            }
            if !keys.isEmpty {
                var summary = keys.joined(separator: ", ")
                if summary.count > 60 {
                    summary = String(summary.prefix(57)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
                }
                header.append(NSAttributedString(string: "   \(summary)", attributes: [
                    .font: labelFont,
                    .foregroundColor: theme.commentColor
                ]))
            }
        }
        header.addAttributes([
            PreviewTextView.frontmatterToggleKey: expanded ? "expanded" : "collapsed",
            .cursor: NSCursor.pointingHand
        ], range: NSRange(location: 0, length: header.length))
        header.append(NSAttributedString(string: "\n", attributes: [.font: labelFont]))

        // The card's padding comes from the paragraph styles, as for code blocks: spacing
        // before the first line and after the last, indents on every line.
        let headerStyle = NSMutableParagraphStyle()
        headerStyle.firstLineHeadIndent = FrontmatterFold.horizontalPadding
        headerStyle.headIndent = FrontmatterFold.horizontalPadding
        headerStyle.tailIndent = -FrontmatterFold.horizontalPadding
        headerStyle.paragraphSpacingBefore = FrontmatterFold.verticalPadding
        headerStyle.paragraphSpacing = expanded ? 4 : FrontmatterFold.verticalPadding
        header.addAttribute(.paragraphStyle, value: headerStyle, range: NSRange(location: 0, length: header.length))
        result.append(header)

        if expanded {
            for (index, line) in yamlLines.enumerated() {
                let lineStyle = NSMutableParagraphStyle()
                lineStyle.firstLineHeadIndent = FrontmatterFold.horizontalPadding
                lineStyle.headIndent = FrontmatterFold.horizontalPadding
                lineStyle.tailIndent = -FrontmatterFold.horizontalPadding
                lineStyle.lineSpacing = 2
                if index == yamlLines.count - 1 {
                    lineStyle.paragraphSpacing = FrontmatterFold.verticalPadding
                }
                result.append(NSAttributedString(string: line + "\n", attributes: [
                    .font: yamlFont,
                    .foregroundColor: theme.textColor,
                    .paragraphStyle: lineStyle
                ]))
            }
        }

        // A bordered card on the page color, like Xcode's; no fill, so it stays quieter than a
        // code block.
        result.addAttribute(
            PreviewTextView.cardKey,
            value: PreviewCardPayload(style: CodeBlockCard.Style(fill: theme.backgroundColor, border: theme.selectionColor)),
            range: NSRange(location: blockStart, length: result.length - blockStart)
        )

        // Spacing after the card
        result.append(NSAttributedString(string: "\n"))
    }

    /// A YAML scalar without its surrounding quotes, if any (`title: "Rendering check"`).
    nonisolated static func unquotedYAMLScalar(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2, let first = trimmed.first, let last = trimmed.last,
              first == last, first == "\"" || first == "'" else { return trimmed }
        return String(trimmed.dropFirst().dropLast())
    }

    private func appendCodeBlock(code: String, language: String? = nil, to result: NSMutableAttributedString) {
        // A rounded card: PreviewLayoutManager draws the fill, border, and language label behind
        // the range tagged below, so the text carries only the code. Paragraph spacing before
        // the first line and after the last one is the card's vertical padding (line fragment
        // rects include it); the indents are its horizontal padding.
        let blockStart = result.length
        let codeFont = fixedFont(size: 13 * zoomLevel)

        let label: NSAttributedString? = language.map {
            NSAttributedString(string: $0.lowercased(), attributes: [
                .font: fixedFont(size: 10.5 * zoomLevel),
                .foregroundColor: theme.commentColor
            ])
        }
        let labelWidth = label.map { ceil($0.size().width) + CodeBlockCard.labelGap } ?? 0

        // Highlighted as a whole (comments and strings can span lines), then every line is a
        // paragraph of its own for the card's padding.
        let codeLines = code.components(separatedBy: .newlines)
        let block = NSMutableAttributedString(attributedString: SyntaxHighlighter.shared.highlight(
            code: codeLines.joined(separator: "\n"),
            language: language,
            font: codeFont,
            theme: theme
        ))
        block.append(NSAttributedString(string: "\n", attributes: [.font: codeFont]))
        var lineStart = 0
        for (index, line) in codeLines.enumerated() {
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.firstLineHeadIndent = CodeBlockCard.horizontalPadding
            paragraphStyle.headIndent = CodeBlockCard.horizontalPadding
            // The first line leaves room for the label in the card's top-right corner.
            paragraphStyle.tailIndent = -(CodeBlockCard.horizontalPadding + (index == 0 ? labelWidth : 0))
            if index == 0 {
                paragraphStyle.paragraphSpacingBefore = CodeBlockCard.verticalPadding
            }
            if index == codeLines.count - 1 {
                paragraphStyle.paragraphSpacing = CodeBlockCard.verticalPadding
            }
            // The line and its line break.
            let length = (line as NSString).length + 1
            block.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: lineStart, length: length))
            lineStart += length
        }
        result.append(block)

        // Tag the block with its RAW source (the copy button and context menu copy it) and with
        // the card's appearance, so the layout manager draws it from the text alone. A fresh
        // object per block keeps adjacent blocks from merging into one effective range
        // (attribute runs coalesce on value equality; NSObject = identity).
        let payload = CodeBlockPayload(
            code: code,
            label: label,
            style: CodeBlockCard.Style(fill: theme.raisedBackgroundColor, border: theme.selectionColor)
        )
        let blockRange = NSRange(location: blockStart, length: result.length - blockStart)
        result.addAttribute(PreviewTextView.codeBlockKey, value: payload, range: blockRange)
        result.addAttribute(PreviewTextView.cardKey, value: payload, range: blockRange)

        // Add spacing after code block
        result.append(NSAttributedString(string: "\n"))
    }

    private func appendBlockquote(text: String, to result: NSMutableAttributedString) {
        let font = mainFont(size: 16 * zoomLevel).withTraits(.italic)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.headIndent = 24
        paragraphStyle.firstLineHeadIndent = 24
        paragraphStyle.paragraphSpacingBefore = 8
        paragraphStyle.paragraphSpacing = 8

        // Accent-colored bar character
        let barAttr = NSAttributedString(string: "  ┃ ", attributes: [
            .font: NSFont.systemFont(ofSize: 16 * zoomLevel * mainScale),
            .foregroundColor: theme.cyanColor.withAlphaComponent(0.75),
            .paragraphStyle: paragraphStyle
        ])
        result.append(barAttr)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: theme.secondaryTextColor,
            .paragraphStyle: paragraphStyle
        ]

        result.append(formatInlineMarkdown(text, attributes: attributes))
        result.append(NSAttributedString(string: "\n", attributes: attributes))
    }

    /// GitHub-style alert: colored bar, icon + bold kind title, then the body in regular (not
    /// italic) text — an alert is a callout, not a quotation. Adaptive system colors, so it
    /// reads correctly in both appearances without baking RGB into the cached fragment.
    private func appendAlert(kind: MarkdownParser.AlertKind, text: String, to result: NSMutableAttributedString) {
        let color: NSColor
        switch kind {
        case .note: color = theme.blueColor
        case .tip: color = theme.greenColor
        case .important: color = theme.purpleColor
        case .warning: color = theme.orangeColor
        case .caution: color = theme.redColor
        }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.headIndent = 24
        paragraphStyle.firstLineHeadIndent = 24
        paragraphStyle.paragraphSpacingBefore = 2
        paragraphStyle.paragraphSpacing = 2
        paragraphStyle.lineSpacing = 3

        let titleStyle = paragraphStyle.mutableCopy() as! NSMutableParagraphStyle
        titleStyle.paragraphSpacingBefore = 10

        let lastStyle = paragraphStyle.mutableCopy() as! NSMutableParagraphStyle
        lastStyle.paragraphSpacing = 10

        func bar(_ style: NSParagraphStyle) -> NSAttributedString {
            NSAttributedString(string: "  ┃ ", attributes: [
                .font: NSFont.systemFont(ofSize: 16 * zoomLevel * mainScale),
                .foregroundColor: color,
                .paragraphStyle: style
            ])
        }

        // Title row: bar, tinted SF Symbol, bold kind name.
        let titleFont = mainFont(size: 15 * zoomLevel).withWeight(.semibold)
        result.append(bar(titleStyle))
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 14 * zoomLevel * mainScale, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        if let symbol = NSImage(systemSymbolName: kind.symbolName, accessibilityDescription: kind.title)?
            .withSymbolConfiguration(symbolConfig) {
            let attachment = NSTextAttachment()
            attachment.image = symbol
            // Drop the glyph slightly so it sits on the text baseline rather than floating.
            attachment.bounds = NSRect(x: 0, y: -2.5 * zoomLevel * mainScale, width: symbol.size.width, height: symbol.size.height)
            let icon = NSMutableAttributedString(attachment: attachment)
            icon.addAttribute(.paragraphStyle, value: titleStyle, range: NSRange(location: 0, length: icon.length))
            result.append(icon)
            result.append(NSAttributedString(string: " ", attributes: [.font: titleFont, .paragraphStyle: titleStyle]))
        }
        result.append(NSAttributedString(string: kind.title + "\n", attributes: [
            .font: titleFont,
            .foregroundColor: color,
            .paragraphStyle: titleStyle
        ]))

        let paragraphs = MarkdownParser.alertParagraphs(text)
        for (index, paragraph) in paragraphs.enumerated() {
            let style = index == paragraphs.count - 1 ? lastStyle : paragraphStyle
            let attributes: [NSAttributedString.Key: Any] = [
                .font: mainFont(size: 16 * zoomLevel),
                .foregroundColor: theme.textColor,
                .paragraphStyle: style
            ]
            result.append(bar(style))
            result.append(formatInlineMarkdown(paragraph, attributes: attributes))
            result.append(NSAttributedString(string: "\n", attributes: attributes))
        }
    }

    private func appendTable(rows: [[String]], alignments: [MarkdownParser.TableAlignment], to result: NSMutableAttributedString) {
        guard !rows.isEmpty else { return }

        // Body-size text, as in Xcode and on GitHub; the header row is semibold.
        let font = mainFont(size: 16 * zoomLevel)
        let boldFont = font.withWeight(.semibold)
        let columnCount = rows.map { $0.count }.max() ?? 1

        let table = NSTextTable()
        table.numberOfColumns = columnCount
        table.setContentWidth(100, type: .percentageValueType)
        table.layoutAlgorithm = .fixedLayoutAlgorithm
        table.hidesEmptyCells = false
        // With column weighting on, the categories give each column a percentage of the text
        // column. Off, columns are sized to their content: measured here, fitted to the text
        // column's width by PreviewTableLayout.fitTables after the build and on every resize.
        let weightedWidths = tableColumnConfiguration.map {
            MarkdownTableColumnLayout.widthPercentages(for: rows, configuration: $0)
        }
        var naturalText = [CGFloat](repeating: 0, count: columnCount)
        var longestWord = [CGFloat](repeating: 0, count: columnCount)
        var spanningText: CGFloat = 0
        let measurer = weightedWidths == nil ? TableCellMeasurer() : nil
        let minimumWidth = PreviewTableLayout.minimumColumnEms * font.pointSize
        // Words narrower than this leave a column at its minimum width, so they need no measuring.
        let minimumWord = minimumWidth - PreviewTableLayout.cellWidth(forText: 0)

        let borderColor = theme.selectionColor
        let tableStart = result.length

        for (rowIndex, row) in rows.enumerated() {
            let isHeader = rowIndex == 0
            // A summary row (first cell filled, the rest empty) becomes one cell across the table.
            let isFullSpan = MarkdownParser.isFullSpanTableRow(row, rowIndex: rowIndex)
            let cells = isFullSpan ? [row[0]] : (0..<columnCount).map { $0 < row.count ? row[$0] : "" }

            for (colIndex, cellText) in cells.enumerated() {
                let block = NSTextTableBlock(
                    table: table,
                    startingRow: rowIndex,
                    rowSpan: 1,
                    startingColumn: colIndex,
                    columnSpan: isFullSpan ? columnCount : 1
                )
                if let weightedWidths, !isFullSpan {
                    block.setContentWidth(weightedWidths[colIndex], type: .percentageValueType)
                }
                block.setBorderColor(borderColor)
                block.setWidth(PreviewTableLayout.borderWidth, type: .absoluteValueType, for: .border)
                for edge in [NSRectEdge.minX, .maxX] {
                    block.setWidth(PreviewTableLayout.horizontalPadding, type: .absoluteValueType, for: .padding, edge: edge)
                }
                for edge in [NSRectEdge.minY, .maxY] {
                    block.setWidth(PreviewTableLayout.verticalPadding, type: .absoluteValueType, for: .padding, edge: edge)
                }
                if isHeader {
                    block.backgroundColor = PreviewTableLayout.headerBackground
                }

                let cellStyle = NSMutableParagraphStyle()
                cellStyle.textBlocks = [block]
                cellStyle.lineSpacing = 4
                if !isFullSpan, colIndex < alignments.count {
                    switch alignments[colIndex] {
                    case .center: cellStyle.alignment = .center
                    case .right: cellStyle.alignment = .right
                    case .left: cellStyle.alignment = .left
                    case .none: break
                    }
                }

                let attrs: [NSAttributedString.Key: Any] = [
                    .font: isHeader ? boldFont : font,
                    .foregroundColor: theme.textColor
                ]
                let formattedCell = NSMutableAttributedString(attributedString: formatInlineMarkdown(cellText, attributes: attrs))
                if let measurer {
                    if isFullSpan {
                        spanningText = max(spanningText, measurer.measure(formattedCell, knownWord: .infinity).natural)
                    } else {
                        let size = measurer.measure(formattedCell, knownWord: max(longestWord[colIndex], minimumWord))
                        naturalText[colIndex] = max(naturalText[colIndex], size.natural)
                        longestWord[colIndex] = max(longestWord[colIndex], size.longestWord)
                    }
                }
                formattedCell.addAttribute(.paragraphStyle, value: cellStyle, range: NSRange(location: 0, length: formattedCell.length))
                result.append(formattedCell)
                result.append(NSAttributedString(string: "\n", attributes: attrs.merging([.paragraphStyle: cellStyle]) { $1 }))
            }
        }

        let tableRange = NSRange(location: tableStart, length: result.length - tableStart)
        var metrics: TableColumnMetrics?
        if weightedWidths == nil {
            let columnMetrics = TableColumnMetrics(
                natural: naturalText.map(PreviewTableLayout.cellWidth(forText:)),
                words: longestWord.map(PreviewTableLayout.cellWidth(forText:)),
                minimum: minimumWidth,
                spanning: spanningText > 0 ? PreviewTableLayout.cellWidth(forText: spanningText) : 0
            )
            metrics = columnMetrics
            // A first fit for the preset width; the build's caller fits it to the real column.
            PreviewTableLayout.apply(
                PreviewTableLayout.widths(for: columnMetrics, available: contentWidth.points ?? 960),
                toTableIn: tableRange,
                of: result
            )
        }

        // PreviewLayoutManager clips the cells to a rounded rectangle and strokes its outline,
        // so the table's corners match the code-block cards (NSTextBlock borders are square).
        // A fresh object per table keeps adjacent tables from merging into one effective range.
        result.addAttribute(
            PreviewTextView.tableKey,
            value: TablePayload(borderColor: borderColor, columnMetrics: metrics),
            range: tableRange
        )

        // Spacing after table
        result.append(NSAttributedString(string: "\n"))
    }

    private func appendHorizontalRule(to result: NSMutableAttributedString) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.paragraphSpacingBefore = 16
        paragraphStyle.paragraphSpacing = 16

        // Gradient-like rule: accent fading to transparent
        let accentColor = theme.blueColor
        let segments = 40
        let ruleStr = NSMutableAttributedString()
        for i in 0..<segments {
            let progress = CGFloat(i) / CGFloat(segments)
            // Bell curve: strong in center, fading at edges
            let intensity = sin(progress * .pi)
            let color = accentColor.withAlphaComponent(intensity * 0.5)
            ruleStr.append(NSAttributedString(string: "─", attributes: [
                .font: NSFont.systemFont(ofSize: 10),
                .foregroundColor: color,
                .paragraphStyle: paragraphStyle
            ]))
        }
        ruleStr.append(NSAttributedString(string: "\n"))
        result.append(ruleStr)
    }

    private func appendImage(alt: String, path: String, to result: NSMutableAttributedString) {
        if let image = resources?.image(path: path) {
            let attachment = NSTextAttachment()
            let scale = contentWidth.attachmentMaxWidth.map {
                min(1.0, $0 / image.size.width)
            } ?? 1.0
            let newSize = NSSize(width: image.size.width * scale, height: image.size.height * scale)

            attachment.image = image
            attachment.bounds = NSRect(origin: .zero, size: newSize)

            let imageString = NSAttributedString(attachment: attachment)
            result.append(NSAttributedString(string: "\n"))
            result.append(imageString)
            result.append(NSAttributedString(string: "\n\n"))
        } else {
            // Show placeholder for missing image
            let attributes: [NSAttributedString.Key: Any] = [
                .font: mainFont(size: 14 * zoomLevel),
                .foregroundColor: theme.secondaryTextColor
            ]
            result.append(NSAttributedString(string: "[Image: \(alt.isEmpty ? path : alt)]\n", attributes: attributes))
        }
    }

    // MARK: - Mermaid & Math

    private func appendMermaidBlock(code: String, to result: NSMutableAttributedString) {
        // Without a renderer (Quick Look) the diagram's source is the best rendering.
        guard let resources else {
            appendCodeBlock(code: code, language: "mermaid", to: result)
            return
        }
        if let cached = resources.mermaidDiagram(code) {
            // Embed cached image
            let attachment = NSTextAttachment()
            let scale = contentWidth.attachmentMaxWidth.map {
                min(1.0, $0 / cached.size.width)
            } ?? 1.0
            let newSize = NSSize(width: cached.size.width * scale, height: cached.size.height * scale)
            attachment.image = cached
            attachment.bounds = NSRect(origin: .zero, size: newSize)
            result.append(NSAttributedString(string: "\n"))
            result.append(NSAttributedString(attachment: attachment))
            result.append(NSAttributedString(string: "\n\n"))
        } else {
            // Show styled loading placeholder
            let placeholderStyle = NSMutableParagraphStyle()
            placeholderStyle.alignment = .center
            placeholderStyle.paragraphSpacingBefore = 12
            placeholderStyle.paragraphSpacing = 12

            let placeholder = NSMutableAttributedString()
            placeholder.append(NSAttributedString(string: "\n", attributes: [:]))
            placeholder.append(NSAttributedString(string: "    Rendering diagram...\n", attributes: [
                .font: NSFont.systemFont(ofSize: 13 * zoomLevel * mainScale, weight: .medium),
                .foregroundColor: theme.secondaryTextColor,
                .paragraphStyle: placeholderStyle
            ]))
            placeholder.append(NSAttributedString(string: "\n", attributes: [:]))
            result.append(placeholder)
        }
    }

    private func appendDisplayMath(latex: String, to result: NSMutableAttributedString) {
        guard let resources else {
            appendCodeBlock(code: latex, language: "latex", to: result)
            return
        }
        if let cached = resources.math(latex, displayMode: true) {
            let attachment = NSTextAttachment()
            attachment.image = cached
            result.append(NSAttributedString(string: "\n"))
            result.append(NSAttributedString(attachment: attachment))
            result.append(NSAttributedString(string: "\n\n"))
        } else {
            // Show styled loading placeholder
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            paragraphStyle.paragraphSpacing = 8
            result.append(NSAttributedString(string: "  Rendering math...\n", attributes: [
                .font: NSFont.systemFont(ofSize: 13 * zoomLevel * mainScale, weight: .medium),
                .foregroundColor: theme.secondaryTextColor,
                .paragraphStyle: paragraphStyle
            ]))
        }
    }

    // MARK: - HTML Block Support

    private func appendHTMLBlock(html: String, to result: NSMutableAttributedString) {
        let textColor = theme.textHex
        let bgColor = theme.backgroundHex
        let linkColor = theme.palette.base0D
        let mainCSSFamily = PreviewFontCatalog.cssFamily(id: mainFontID, monospaced: false)
        let fixedCSSFamily = PreviewFontCatalog.cssFamily(id: fixedFontID, monospaced: true)
        let fontSize = 16 * zoomLevel

        // Resolve relative image src paths to absolute file paths
        let baseDir = baseURL?.deletingLastPathComponent()
        var resolvedHTML = html
        if let baseDir = baseDir {
            let imgPattern = #"(<img\s[^>]*src\s*=\s*")([^"]+)("[^>]*>)"#
            if let regex = try? NSRegularExpression(pattern: imgPattern, options: .caseInsensitive) {
                let nsHTML = resolvedHTML as NSString
                let matches = regex.matches(in: resolvedHTML, range: NSRange(location: 0, length: nsHTML.length)).reversed()
                for match in matches {
                    guard match.numberOfRanges >= 4 else { continue }
                    let srcRange = match.range(at: 2)
                    let src = nsHTML.substring(with: srcRange)
                    // Skip URLs that are already absolute
                    if src.hasPrefix("http://") || src.hasPrefix("https://") || src.hasPrefix("file://") { continue }
                    let resolved = baseDir.appendingPathComponent(src)
                    if FileManager.default.fileExists(atPath: resolved.path) {
                        resolvedHTML = (resolvedHTML as NSString).replacingCharacters(in: srcRange, with: resolved.absoluteString)
                    }
                }
            }
        }

        // Wrap HTML with styling that matches the app theme
        let styledHTML = """
        <html><head><meta charset="utf-8"><style>
        body { font-family: \(mainCSSFamily);
               font-size: \(fontSize * mainScale)px; color: \(textColor); background: \(bgColor);
               line-height: 1.5; margin: 0; padding: 0; }
        a { color: \(linkColor); }
        code, pre, kbd, samp { font-family: \(fixedCSSFamily); }
        img { max-width: 100%; height: auto; }
        h1, h2, h3, h4, h5, h6 { margin-top: 0.5em; margin-bottom: 0.3em; }
        p { margin: 0.3em 0; }
        </style></head><body>\(resolvedHTML)</body></html>
        """

        // Explicit .characterEncoding is required. The `NSAttributedString(html:baseURL:…)`
        // convenience initializer takes no encoding, so AppKit's HTML importer GUESSES and
        // falls back to Windows-1252 — turning UTF-8 "—" into "â€"", "·" into "Â·", and "×"
        // into "Ã—" throughout any block containing non-ASCII text. ExportManager already
        // passes this option; the preview path did not. (The <meta charset> above is a second
        // belt on the same trousers.)
        guard let data = styledHTML.data(using: .utf8),
              let attributed = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue,
                    .baseURL: baseDir ?? URL(fileURLWithPath: "/")
                ],
                documentAttributes: nil
              ) else {
            // Fallback: render as plain text
            let font = mainFont(size: fontSize)
            result.append(NSAttributedString(string: html + "\n", attributes: [
                .font: font,
                .foregroundColor: theme.textColor
            ]))
            return
        }

        result.append(attributed)
        // Ensure trailing newline
        if !attributed.string.hasSuffix("\n") {
            result.append(NSAttributedString(string: "\n"))
        }
    }

    // MARK: - Inline Formatting

    /// Sentinel attribute marking ranges that came from an inline code span. Subsequent inline
    /// passes (bold, italic, strike, link) skip ranges carrying this attribute so that
    /// `` `*foo*` `` renders with literal asterisks instead of treating them as italic markers.
    /// Cleared at the end of formatInlineMarkdown so it never leaks to the storage.
    private static let codeSpanSentinel = NSAttributedString.Key("Hashlight.codeSpanSentinel")

    private func formatInlineMarkdown(_ text: String, attributes: [NSAttributedString.Key: Any], stripCodeSpanSentinel: Bool = true) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let baseFont = attributes[.font] as? NSFont ?? NSFont.systemFont(ofSize: 16)

        for token in InlineMarkdown.tokenize(text) {
            var tokenAttributes = attributes
            switch token {
            case .text(let text):
                result.append(NSAttributedString(string: text, attributes: tokenAttributes))
            case .lineBreak:
                result.append(NSAttributedString(string: "\n", attributes: tokenAttributes))
            case .code(let text):
                tokenAttributes[Self.codeSpanSentinel] = true
                // Inline code sits in a line of prose: a point below its text at the default
                // size, following the main size only (the fixed size is for code blocks).
                tokenAttributes[.font] = PreviewFontCatalog.fixedFont(id: fixedFontID, size: baseFont.pointSize - mainScale)
                tokenAttributes[.foregroundColor] = theme.greenColor
                tokenAttributes[.backgroundColor] = theme.raisedBackgroundColor
                result.append(NSAttributedString(string: text, attributes: tokenAttributes))
            case .math(let text):
                result.append(NSAttributedString(string: "$\(text)$", attributes: tokenAttributes))
            case .strong(let text):
                tokenAttributes[.font] = baseFont.withWeight(.bold)
                result.append(formatInlineMarkdown(text, attributes: tokenAttributes, stripCodeSpanSentinel: false))
            case .emphasis(let text):
                tokenAttributes[.font] = baseFont.withTraits(.italic)
                result.append(formatInlineMarkdown(text, attributes: tokenAttributes, stripCodeSpanSentinel: false))
            case .strikethrough(let text):
                tokenAttributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                result.append(formatInlineMarkdown(text, attributes: tokenAttributes, stripCodeSpanSentinel: false))
            case .highlight(let text):
                tokenAttributes[.backgroundColor] = theme.yellowColor.withAlphaComponent(0.35)
                result.append(formatInlineMarkdown(text, attributes: tokenAttributes, stripCodeSpanSentinel: false))
            case .image(let alt, let source):
                if let image = resources?.image(path: source) {
                    let attachment = NSTextAttachment()
                    let maxHeight = baseFont.pointSize * 2.2
                    let scale = image.size.height > 0 ? min(1.0, maxHeight / image.size.height) : 1.0
                    let displaySize = NSSize(width: image.size.width * scale, height: image.size.height * scale)
                    let displayImage = (image.copy() as? NSImage) ?? image
                    displayImage.size = displaySize
                    attachment.image = displayImage
                    attachment.bounds = CGRect(x: 0, y: -4, width: displaySize.width, height: displaySize.height)
                    let replacement = NSMutableAttributedString(attachment: attachment)
                    replacement.addAttributes(tokenAttributes, range: NSRange(location: 0, length: replacement.length))
                    result.append(replacement)
                } else {
                    let label = "[Image: \(alt.isEmpty ? source : alt)]"
                    result.append(NSAttributedString(string: label, attributes: tokenAttributes))
                }
            case .link(let label, let destination):
                tokenAttributes[.link] = URL(string: destination)
                tokenAttributes[.foregroundColor] = theme.blueColor
                tokenAttributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
                result.append(formatInlineMarkdown(label, attributes: tokenAttributes, stripCodeSpanSentinel: false))
            }
        }

        // Inline math $...$ — moved up to run BEFORE bold/italic/strike (M3) so a math span like
        // `$a^{**}$` doesn't get its `**` consumed by the bold pass.
        applyInlineMathPattern(to: result)

        // Strip the sentinel before returning so it doesn't ride along into NSTextStorage.
        if stripCodeSpanSentinel {
            let fullRange = NSRange(location: 0, length: result.length)
            result.removeAttribute(Self.codeSpanSentinel, range: fullRange)
        }

        return result
    }

    private static var regexCache: [String: NSRegularExpression] = [:]

    private static func cachedRegex(_ pattern: String) -> NSRegularExpression? {
        if let cached = regexCache[pattern] { return cached }
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        regexCache[pattern] = regex
        return regex
    }

    private func rangeIntersectsCodeSpan(_ range: NSRange, in attributed: NSAttributedString) -> Bool {
        guard range.location + range.length <= attributed.length else { return false }
        var found = false
        attributed.enumerateAttribute(Self.codeSpanSentinel, in: range, options: []) { value, _, stop in
            if value != nil {
                found = true
                stop.pointee = true
            }
        }
        return found
    }

    private func applyInlineMathPattern(to result: NSMutableAttributedString) {
        // Pandoc-style inline-math rule:
        //   - opening `$` not preceded by `$` (so `$$` is display math)
        //   - opening `$` not followed by `$`, space, OR digit (so `$1`, `$10.50` are money,
        //     not math openers — without this, paragraphs containing `…thanks ($1) for …
        //     thanks ($10) for …` matched the entire span between the two `$` as math)
        //   - closing `$` not preceded by space, not followed by `$` or digit
        //   - content capped at 200 chars to bound runaway lazy matches
        let pattern = MarkdownParser.inlineMathPattern  // C7: shared canonical pattern
        guard let regex = Self.cachedRegex(pattern) else { return }
        let string = result.string as NSString

        let matches = regex.matches(in: result.string, range: NSRange(location: 0, length: string.length)).reversed()

        for match in matches {
            guard match.numberOfRanges >= 2 else { continue }
            let fullRange = match.range(at: 0)
            if rangeIntersectsCodeSpan(fullRange, in: result) { continue }

            let contentRange = match.range(at: 1)
            let latex = string.substring(with: contentRange)

            // Preserve the existing attributes (especially .paragraphStyle, which carries the
            // table-cell textBlocks attribute). NSAttributedString(attachment:) and a fresh
            // dictionary both strip the paragraph style; without it, table cells containing math
            // lose their textBlock binding and render as full-width rows outside the table.
            let existing = result.attributes(at: fullRange.location, effectiveRange: nil)

            if let cached = resources?.math(latex, displayMode: false) {
                // Replace with image attachment, sized to match the surrounding line height.
                // takeSnapshot returns NSImages whose pixel dimensions are at the device scale
                // (2x on retina), and NSTextAttachment displays at NSImage.size in points —
                // without explicit bounds, math renders 2x bigger than text and breaks line
                // metrics + table cell widths. Scale to the body font's point size, preserving
                // aspect ratio, with a small descent offset so the math sits on the baseline.
                let attachment = NSTextAttachment()
                attachment.image = cached
                let baseFontSize: CGFloat = mainFont(size: 14 * zoomLevel).pointSize
                let aspect = cached.size.height > 0 ? cached.size.width / cached.size.height : 1
                let displayHeight = baseFontSize * 1.1
                let displayWidth = displayHeight * aspect
                attachment.bounds = CGRect(x: 0, y: -2, width: displayWidth, height: displayHeight)
                let replacement = NSMutableAttributedString(attachment: attachment)
                replacement.addAttributes(existing, range: NSRange(location: 0, length: replacement.length))
                result.replaceCharacters(in: fullRange, with: replacement)
            } else {
                // The source as a code-like placeholder until the render lands (the app), or
                // for good (Quick Look). Merge math styling on top of the existing attrs so
                // paragraph style is preserved (see above).
                var attributes = existing
                attributes[.font] = fixedFont(size: 13 * zoomLevel)
                attributes[.foregroundColor] = theme.purpleColor
                result.replaceCharacters(in: fullRange, with: NSAttributedString(string: latex, attributes: attributes))
            }
        }
    }

    // MARK: - Helpers

    /// Fonts are requested at their default-size values; these apply the Settings sizes.
    private func mainFont(size: CGFloat) -> NSFont {
        PreviewFontCatalog.mainFont(id: mainFontID, size: size * mainScale)
    }

    private func fixedFont(size: CGFloat) -> NSFont {
        PreviewFontCatalog.fixedFont(id: fixedFontID, size: size * fixedScale)
    }
}
