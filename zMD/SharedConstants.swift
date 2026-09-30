import Foundation

// Constants shared between the zMD app target and the zMDQuickLook extension target.
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

/// Shared preferences bridge between zMD Viewer and its sandboxed Quick Look extension.
nonisolated enum MarkdownTableColumnPreferences {
#if DEBUG
    static let sharedDomain = "com.zmd.viewer.debug.table-column-layout"
#else
    static let sharedDomain = "com.zmd.viewer.table-column-layout"
#endif
    static let sharedKey = "configuration-v1"
    static let appKey = "markdownTableColumnConfiguration.v1"

    static func loadAppDefaults() -> MarkdownTableColumnConfiguration {
        load(from: .standard, key: appKey)
    }

    static func loadQuickLookDefaults() -> MarkdownTableColumnConfiguration {
        let sharedPreferences = UserDefaults(suiteName: sharedDomain)
        // Refresh this process's preference cache because Quick Look may reuse the extension
        // process after zMD has written a newer snapshot.
        _ = sharedPreferences?.synchronize()
        return load(from: sharedPreferences, key: sharedKey)
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
