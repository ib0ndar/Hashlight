import Foundation

// Constants shared between the Hashlight app target and the HashlightQuickLook extension target.
// Lives outside SettingsManager.swift so the extension can compile MarkdownParser.swift without
// dragging in SettingsManager (ObservableObject, AppKit fonts, UserDefaults state).

/// CDN resource URLs for preview/export scripts. Both preview (WebRenderer) and exported HTML
/// (MarkdownParser.toHTML) reference the same strings — defining them once eliminates version
/// drift between the two consumers.
nonisolated enum CDN {
    // S2: pin Mermaid to an exact version (was the floating `mermaid@10`, which auto-adopted any
    // new 10.x without review) and carry a Subresource Integrity hash for every resource. The
    // `integrity` attribute makes the browser / WKWebView refuse a tampered script instead of
    // executing it — important because these run inside the unsandboxed app's WebView and in any
    // exported HTML opened by others. Hashes are the sha384 of the pinned files served by jsDelivr.
    static let mermaidJS = "https://cdn.jsdelivr.net/npm/mermaid@11.16.0/dist/mermaid.min.js"
    static let mermaidJSIntegrity = "sha384-T/0lMUdJpd2S1ZHtRiofG3htU3xPCrFVeAQ1UUE2TJwlEJSV5NUwn30kP28n238E"
    static let katexCSS = "https://cdn.jsdelivr.net/npm/katex@0.18.1/dist/katex.min.css"
    static let katexCSSIntegrity = "sha384-1vdNCNel6Tx/NQa8IR1mGOGKsbGreCkOPfbtPPnUURJ5Tu2PRVfQ/7KLZC+Pi1p1"
    static let katexJS = "https://cdn.jsdelivr.net/npm/katex@0.18.1/dist/katex.min.js"
    static let katexJSIntegrity = "sha384-ycJ6GAwiS15LoUPipwJOrWTvkUHl/YqELValBwI5I4awP1EeEQJYarj+w85ntcz7"
    static let katexAutoRenderJS = "https://cdn.jsdelivr.net/npm/katex@0.18.1/dist/contrib/auto-render.min.js"
    static let katexAutoRenderJSIntegrity = "sha384-bjyGPfbij8/NDKJhSGZNP/khQVgtHUE5exjm4Ydllo42FwIgYsdLO2lXGmRBf5Mz"
}

/// One editable header category used by both the in-app preview and Quick Look.
nonisolated struct MarkdownTableColumnCategory: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var name: String
    var weight: Double
    var words: [String]

    var canBeRemoved: Bool {
        id == "other" || !Self.predefinedIDs.contains(id)
    }

    static let predefinedIDs: Set<String> = [
        "descriptive", "operational-documentation", "compact", "identifier", "other"
    ]

    static let defaults: [MarkdownTableColumnCategory] = [
        .init(id: "descriptive", name: "Descriptive", weight: 2.4, words: [
            "comment", "comments", "description", "details", "message", "notes",
            "purpose", "reason", "remarks", "summary"
        ]),
        .init(id: "operational-documentation", name: "Operational / Documentation", weight: 1.5, words: [
            "operational", "documentation"
        ]),
        .init(id: "compact", name: "Compact", weight: 0.65, words: [
            "admin", "enabled", "flag", "id", "link", "mode", "mtu", "operational",
            "priority", "speed", "state", "status", "type", "vlan", "duplex", "count"
        ]),
        .init(id: "identifier", name: "Identifier", weight: 1.3, words: [
            "address", "gateway", "host", "interface", "ip", "mac", "name", "prefix", "url"
        ]),
        .init(id: "other", name: "Other", weight: 1.0, words: [])
    ]
}

/// Persisted category configuration. The single encoded snapshot keeps app and extension
/// readers from observing a partially updated set of categories, words, or priorities.
nonisolated struct MarkdownTableColumnConfiguration: Codable, Equatable, Sendable {
    var categories: [MarkdownTableColumnCategory]

    static let defaults = MarkdownTableColumnConfiguration(categories: MarkdownTableColumnCategory.defaults)
    static let fallbackWeight = 1.0
    private static let snapshotVersion = 1

    var cacheKey: String {
        (encodedSnapshot() ?? Data()).base64EncodedString()
    }

    func encodedSnapshot() -> Data? {
        let envelope = Snapshot(version: Self.snapshotVersion, categories: categories)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(envelope)
    }

    static func decodeSnapshot(_ data: Data) -> MarkdownTableColumnConfiguration? {
        guard let envelope = try? JSONDecoder().decode(Snapshot.self, from: data),
              envelope.version == snapshotVersion,
              isValid(envelope.categories) else { return nil }
        return MarkdownTableColumnConfiguration(categories: envelope.categories)
    }

    static func isValid(_ categories: [MarkdownTableColumnCategory]) -> Bool {
        var ids = Set<String>()
        return categories.allSatisfy { category in
            !category.id.isEmpty && ids.insert(category.id).inserted
                && category.weight.isFinite && category.weight > 0
        }
    }

    private struct Snapshot: Codable {
        let version: Int
        let categories: [MarkdownTableColumnCategory]
    }
}

/// Editing operations for Settings → Tables. Each returns a new configuration and leaves the
/// receiver unchanged when the edit does not apply. Category order is matching priority.
nonisolated extension MarkdownTableColumnConfiguration {
    var isDefault: Bool {
        self == .defaults
    }

    static func newCategory() -> MarkdownTableColumnCategory {
        MarkdownTableColumnCategory(id: UUID().uuidString.lowercased(), name: "New Category", weight: 1.0, words: [])
    }

    func category(withID id: String) -> MarkdownTableColumnCategory? {
        categories.first(where: { $0.id == id })
    }

    /// Appends `category`, or replaces the category with the same id.
    func savingCategory(_ category: MarkdownTableColumnCategory) -> MarkdownTableColumnConfiguration {
        var updated = self
        if let index = updated.categories.firstIndex(where: { $0.id == category.id }) {
            updated.categories[index] = category
        } else {
            updated.categories.append(category)
        }
        return Self.isValid(updated.categories) ? updated : self
    }

    /// Removes a category unless it is one of the built-in ones that cannot be removed.
    func removingCategory(withID id: String) -> MarkdownTableColumnConfiguration {
        guard let index = categories.firstIndex(where: { $0.id == id }),
              categories[index].canBeRemoved else { return self }
        var updated = self
        updated.categories.remove(at: index)
        return updated
    }

    /// Moves one category up (negative `offset`) or down (positive `offset`).
    func movingCategory(withID id: String, by offset: Int) -> MarkdownTableColumnConfiguration {
        guard let index = categories.firstIndex(where: { $0.id == id }),
              categories.indices.contains(index + offset) else { return self }
        var updated = self
        let category = updated.categories.remove(at: index)
        updated.categories.insert(category, at: index + offset)
        return updated
    }

    /// Moves the categories with `ids` to `destination`, an insertion index into the current
    /// order (what a drop between two rows reports). The moved categories keep their order.
    func movingCategories(withIDs ids: [String], to destination: Int) -> MarkdownTableColumnConfiguration {
        let moving = Set(ids)
        let moved = categories.filter { moving.contains($0.id) }
        guard !moved.isEmpty else { return self }
        let clamped = min(max(destination, 0), categories.count)
        let movedBeforeDestination = categories[..<clamped].filter { moving.contains($0.id) }.count
        var updated = self
        updated.categories.removeAll { moving.contains($0.id) }
        updated.categories.insert(contentsOf: moved, at: clamped - movedBeforeDestination)
        return updated
    }
}

/// Shared preferences bridge between Hashlight and its sandboxed Quick Look extension.
nonisolated enum MarkdownTableColumnPreferences {
#if DEBUG
    static let sharedDomain = "io.github.ib0ndar.hashlight.debug.table-column-layout"
#else
    static let sharedDomain = "io.github.ib0ndar.hashlight.table-column-layout"
#endif
    static let sharedKey = "configuration-v1"
    static let appKey = "markdownTableColumnConfiguration.v1"
    /// Whether the categories size columns at all. Off (or absent) sizes columns to their content
    /// in the app and leaves Quick Look tables to the browser's own layout.
    static let sharedEnabledKey = "weights-enabled"
    static let appEnabledKey = "markdownTableColumnWeightsEnabled"

    static func loadAppDefaults() -> MarkdownTableColumnConfiguration {
        load(from: .standard, key: appKey)
    }

    /// The configuration Quick Look applies, or nil while column weighting is off.
    static func loadQuickLookDefaults() -> MarkdownTableColumnConfiguration? {
        let sharedPreferences = UserDefaults(suiteName: sharedDomain)
        // Refresh this process's preference cache because Quick Look may reuse the extension
        // process after Hashlight has written a newer snapshot.
        _ = sharedPreferences?.synchronize()
        return enabledConfiguration(from: sharedPreferences)
    }

    static func enabledConfiguration(from sharedPreferences: UserDefaults?) -> MarkdownTableColumnConfiguration? {
        guard isEnabled(in: sharedPreferences, key: sharedEnabledKey) else { return nil }
        return load(from: sharedPreferences, key: sharedKey)
    }

    static func isEnabled(in defaults: UserDefaults?, key: String) -> Bool {
        defaults?.object(forKey: key) as? Bool ?? false
    }

    static func persistEnabled(
        _ isEnabled: Bool,
        appDefaults: UserDefaults = .standard,
        sharedPreferences: UserDefaults? = UserDefaults(suiteName: sharedDomain)
    ) {
        appDefaults.set(isEnabled, forKey: appEnabledKey)
        sharedPreferences?.set(isEnabled, forKey: sharedEnabledKey)
        _ = sharedPreferences?.synchronize()
    }

    static func load(from defaults: UserDefaults?, key: String) -> MarkdownTableColumnConfiguration {
        guard let data = defaults?.data(forKey: key),
              let configuration = MarkdownTableColumnConfiguration.decodeSnapshot(data) else {
            return .defaults
        }
        return configuration
    }

    static func persist(
        _ configuration: MarkdownTableColumnConfiguration,
        appDefaults: UserDefaults = .standard,
        sharedPreferences: UserDefaults? = UserDefaults(suiteName: sharedDomain)
    ) {
        guard MarkdownTableColumnConfiguration.isValid(configuration.categories),
              let data = configuration.encodedSnapshot() else { return }
        appDefaults.set(data, forKey: appKey)
        sharedPreferences?.set(data, forKey: sharedKey)
        _ = sharedPreferences?.synchronize()
    }
}

/// Header token matching and width allocation shared by AppKit and Quick Look HTML.
nonisolated enum MarkdownTableColumnLayout {
    static func tokens(in text: String) -> Set<String> {
        Set(text
            .replacingOccurrences(of: String(Unicode.Scalar(96)!), with: "")
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty })
    }

    static func weight(for header: String, configuration: MarkdownTableColumnConfiguration = .defaults) -> CGFloat {
        let headerTokens = tokens(in: header)
        for category in configuration.categories {
            let criteria = Set(category.words.flatMap { tokens(in: $0) })
            if !criteria.isDisjoint(with: headerTokens) {
                return CGFloat(category.weight)
            }
        }
        return CGFloat(configuration.categories.first(where: { $0.id == "other" })?.weight
            ?? MarkdownTableColumnConfiguration.fallbackWeight)
    }

    /// Content-sized column widths (weighting off), in points, after Xcode 27's Markdown tables
    /// (grid columns `minmax(4em, auto)` in a table that shrinks to fit): a column whose content
    /// fits gets its natural width, and the columns that do not fit share the rest equally.
    /// Two changes keep cells readable. The columns never add up to more than `available` (the
    /// minimum gives way first). And a column whose longest word would be split is widened to
    /// keep it whole, smallest shortfall first, with room taken from columns that wrap anyway and
    /// can narrow without splitting their own words; a column that cannot be made whole keeps its
    /// shared width. Columns that fit on one line are never narrowed.
    ///
    /// - Parameters:
    ///   - natural: each column's widest unwrapped line, as a whole-cell width.
    ///   - words: each column's longest unbreakable segment, as a whole-cell width.
    ///   - minimum: the narrowest a column gets while the columns fit (Xcode's 4em).
    ///   - spanning: the natural width of the widest row that spans the table, or 0.
    ///   - available: the width the table may take.
    static func fittedWidths(
        natural: [CGFloat],
        words: [CGFloat],
        minimum: CGFloat,
        spanning: CGFloat = 0,
        available: CGFloat
    ) -> [CGFloat] {
        let count = natural.count
        guard count > 0, words.count == count, available.isFinite, available > 0 else {
            return natural
        }
        func clean(_ value: CGFloat) -> CGFloat { value.isFinite ? max(value, 0) : 0 }
        let floor = min(clean(minimum), available / CGFloat(count))
        let wanted = natural.map { max(clean($0), floor) }

        var widths = wanted
        if wanted.reduce(0, +) > available {
            // Xcode: the shared level L — columns that want less keep their width, the rest get L.
            let shared = level(
                where: { level in wanted.reduce(0) { $0 + max(floor, min($1, level)) } },
                reaches: available,
                upTo: wanted.max() ?? 0
            )
            widths = wanted.map { max(floor, min($0, shared)) }

            // Keep words whole where the room exists.
            let keep = zip(words, wanted).map { max(floor, min(clean($0), $1)) }
            let receivers = widths.indices
                .filter { keep[$0] > widths[$0] + 0.01 }
                .sorted { keep[$0] - widths[$0] < keep[$1] - widths[$1] }
            var repaired = Set<Int>()
            for receiver in receivers {
                let shortfall = keep[receiver] - widths[receiver]
                let donors = widths.indices.filter {
                    $0 != receiver && !repaired.contains($0) && wanted[$0] > widths[$0] + 0.01 && widths[$0] > keep[$0]
                }
                let spare = donors.reduce(0) { $0 + widths[$1] - keep[$1] }
                guard spare >= shortfall else { continue }
                // Narrow the widest donors first, down to a common level T.
                let target = level(
                    where: { level in -donors.reduce(0) { $0 + widths[$1] - max(keep[$1], min(widths[$1], level)) } },
                    reaches: -shortfall,
                    upTo: donors.map { widths[$0] }.max() ?? 0
                )
                for donor in donors {
                    widths[donor] = max(keep[donor], min(widths[donor], target))
                }
                widths[receiver] = keep[receiver]
                repaired.insert(receiver)
            }
        }

        // A summary row that spans the table widens it, up to the available width.
        let sum = widths.reduce(0, +)
        if spanning > sum, sum > 0 {
            let scale = min(spanning, available) / sum
            if scale > 1 { widths = widths.map { $0 * scale } }
        }
        return widths
    }

    /// The largest level in 0...upper whose non-decreasing `total` stays at or below `target`.
    private static func level(where total: (CGFloat) -> CGFloat, reaches target: CGFloat, upTo upper: CGFloat) -> CGFloat {
        var low: CGFloat = 0
        var high = upper
        for _ in 0..<64 {
            let middle = (low + high) / 2
            if total(middle) <= target { low = middle } else { high = middle }
        }
        return low
    }

    static func widthPercentages(
        for rows: [[String]],
        configuration: MarkdownTableColumnConfiguration = .defaults
    ) -> [CGFloat] {
        let columnCount = rows.map(\.count).max() ?? 0
        guard columnCount > 0 else { return [] }

        let header = rows.first ?? []
        let weights = (0..<columnCount).map { column -> CGFloat in
            let title = column < header.count ? header[column] : ""
            let base = weight(for: title, configuration: configuration)
            let longestToken = rows.compactMap { row -> Int? in
                guard column < row.count else { return nil }
                return row[column]
                    .replacingOccurrences(of: String(Unicode.Scalar(96)!), with: "")
                    .split(whereSeparator: \.isWhitespace)
                    .map(\.count)
                    .max()
            }.max() ?? 0
            let identifierAllowance = min(0.75, CGFloat(max(0, longestToken - 8)) * 0.04)
            return base + identifierAllowance
        }

        // Keep a small floor for each column and stop one free-form description from taking
        // the whole table. Re-distribute the remaining space among columns that are not capped.
        let minimum = min(7.0, 100.0 / CGFloat(columnCount))
        let maximum = max(100.0 / CGFloat(columnCount), 45.0)
        var widths = Array(repeating: CGFloat.zero, count: columnCount)
        var remaining = Set(0..<columnCount)
        while !remaining.isEmpty {
            let remainingWidth = 100.0 - widths.reduce(0, +)
            let largestWeight = remaining.map { weights[$0] }.max() ?? 0
            guard largestWeight.isFinite, largestWeight > 0 else { break }
            let normalizedTotal = remaining.sorted().reduce(CGFloat.zero) {
                $0 + weights[$1] / largestWeight
            }
            guard normalizedTotal.isFinite, normalizedTotal > 0 else { break }
            let proposals = remaining.sorted().map {
                ($0, remainingWidth * (weights[$0] / largestWeight) / normalizedTotal)
            }
            let capped = proposals.filter { $0.1 < minimum || $0.1 > maximum }
            if capped.isEmpty {
                for (index, width) in proposals { widths[index] = width }
                break
            }
            for (index, proposed) in capped {
                widths[index] = min(maximum, max(minimum, proposed))
                remaining.remove(index)
            }
        }

        return widths
    }
}
