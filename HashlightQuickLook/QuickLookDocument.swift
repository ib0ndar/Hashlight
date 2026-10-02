import Foundation

/// Pure, Foundation-only helpers for the Quick Look preview extension: bounded file reading and
/// text decoding.
///
/// Deliberately free of any QuickLookUI / AppKit dependency so the same file can be compiled
/// into the HashlightTests target and unit-tested without hosting an app extension.
nonisolated enum QuickLookDocument {
    /// Upper bound on how much of a file is read for a preview. Quick Look runs while the user is
    /// arrowing through Finder; a multi-hundred-MB log file renamed `.md` must not stall it.
    static let maxInputBytes = 2 * 1024 * 1024

    /// Shown after the rendered text when the file was cut at `maxInputBytes`. It is added
    /// AFTER rendering: the cut lands at an arbitrary byte, often inside a fenced code / `$$` /
    /// HTML block, and a notice appended to the Markdown gets swallowed by that open block as
    /// literal text — the user would never learn the preview is incomplete.
    static let truncationNotice = "Preview truncated — open the file in Hashlight to see the whole document."

    // MARK: - Reading

    /// Reads at most `maxBytes` from `url`. `truncated` is true when the file had more.
    static func readPrefix(of url: URL, maxBytes: Int = maxInputBytes) throws -> (data: Data, truncated: Bool) {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        // Ask for one extra byte: that is how we learn the file continues past the cap without a
        // separate (and, inside the sandbox, not always permitted) attributes lookup.
        let data = try handle.read(upToCount: maxBytes + 1) ?? Data()
        if data.count > maxBytes {
            return (data.prefix(maxBytes), true)
        }
        return (data, false)
    }

    // MARK: - Decoding

    /// UTF-8 first, then BOM-marked UTF-16, then Windows-1252 as the catch-all.
    ///
    /// UTF-16 is only accepted with a BOM: `String(data:encoding: .utf16)` "succeeds" on nearly
    /// any even-length byte string, so trying it blind would turn every Latin-1 file into CJK
    /// garbage before CP1252 ever got a chance. This mirrors the app's own
    /// `DocumentManager.decodeFileData` ordering.
    ///
    /// - Parameter truncated: the data was cut at an arbitrary byte offset, so a trailing
    ///   partial UTF-8 sequence is expected and must not push the file into the CP1252 fallback.
    static func decode(_ data: Data, truncated: Bool = false) -> String {
        let bytes = [UInt8](data.prefix(2))
        let hasUTF16BOM = bytes == [0xFF, 0xFE] || bytes == [0xFE, 0xFF]

        if !hasUTF16BOM {
            // Dropping up to 3 bytes covers the longest incomplete UTF-8 tail (a 4-byte scalar
            // missing its last byte). Only done for truncated input — a complete file with a bad
            // tail is genuinely not UTF-8.
            let maxTrim = truncated ? 3 : 0
            for trim in 0...maxTrim where data.count >= trim {
                if let text = String(data: data.dropLast(trim), encoding: .utf8) {
                    return stripBOM(text)
                }
            }
        } else {
            // An odd byte count can only come from truncation mid code unit; drop the stray byte.
            let even = data.count % 2 == 0 ? data : data.dropLast()
            if let text = String(data: even, encoding: .utf16) {
                return stripBOM(text)
            }
        }

        if let text = String(data: data, encoding: .windowsCP1252) {
            return text
        }
        // CP1252 leaves five byte values undefined; Latin-1 maps every byte.
        if let text = String(data: data, encoding: .isoLatin1) {
            return text
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func stripBOM(_ text: String) -> String {
        text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
    }
}
