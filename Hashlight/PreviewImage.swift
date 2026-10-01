import AppKit
import ImageIO

/// Raster preparation and decoded-memory accounting for preview and web-render caches.
enum PreviewImage {
    /// Bounds unusually tall/wide thumbnails as well as ordinary width-limited photos.
    static let maximumThumbnailPixels: Double = 8 * 1024 * 1024

    static func decodedByteCost(_ image: NSImage) -> Int {
        let costs = image.representations.map { representation -> Int in
            if let bitmap = representation as? NSBitmapImageRep {
                return saturatedProduct(bitmap.bytesPerRow, bitmap.pixelsHigh, bitmap.isPlanar ? bitmap.numberOfPlanes : 1)
            }
            // CGImage-backed snapshots expose pixel dimensions even when their logical size
            // is in points. Vector representations have no fixed decoded backing to count.
            return saturatedProduct(max(0, representation.pixelsWide), max(0, representation.pixelsHigh), 4)
        }
        return max(1, costs.reduce(0) { sum, cost in
            let (total, overflow) = sum.addingReportingOverflow(cost)
            return overflow ? Int.max : total
        })
    }

    private static func saturatedProduct(_ a: Int, _ b: Int, _ c: Int) -> Int {
        let (ab, firstOverflow) = a.multipliedReportingOverflow(by: b)
        let (abc, secondOverflow) = ab.multipliedReportingOverflow(by: c)
        return firstOverflow || secondOverflow ? Int.max : max(0, abc)
    }

    static func load(contentsOf url: URL, maximumPixelWidth: Int?) -> NSImage? {
        if let maximumPixelWidth,
           let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
           let image = thumbnail(source: source, maximumPixelWidth: maximumPixelWidth) {
            return image
        }
        return NSImage(contentsOf: url)
    }

    static func load(data: Data, maximumPixelWidth: Int?) -> NSImage? {
        if let maximumPixelWidth,
           let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
           let image = thumbnail(source: source, maximumPixelWidth: maximumPixelWidth) {
            return image
        }
        return NSImage(data: data)
    }

    private static func thumbnail(source: CGImageSource, maximumPixelWidth: Int) -> NSImage? {
        // Preserve animations, multi-representation icons, and formats AppKit handles itself.
        guard maximumPixelWidth > 0, CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let pixelWidth = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let pixelHeight = properties[kCGImagePropertyPixelHeight] as? NSNumber else { return nil }
        let width = pixelWidth.doubleValue
        let height = pixelHeight.doubleValue
        guard width.isFinite, height.isFinite, width > 0, height > 0 else { return nil }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let rotated = (5...8).contains(orientation)
        let orientedWidth = rotated ? height : width
        let ratio = min(1, Double(maximumPixelWidth) / orientedWidth,
                        sqrt(maximumThumbnailPixels / width / height))
        let dimension = max(1, ceil(max(width, height) * ratio))
        guard dimension.isFinite, dimension < Double(Int.max),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: Int(dimension),
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }

        func dpi(_ key: CFString) -> Double {
            let value = (properties[key] as? NSNumber)?.doubleValue ?? 72
            return value.isFinite && value > 0 ? value : 72
        }
        let naturalSize = NSSize(width: width * 72 / dpi(kCGImagePropertyDPIWidth),
                                 height: height * 72 / dpi(kCGImagePropertyDPIHeight))
        let size = rotated ? NSSize(width: naturalSize.height, height: naturalSize.width) : naturalSize
        let bitmap = NSBitmapImageRep(cgImage: thumbnail)
        bitmap.size = size
        let image = NSImage(size: size)
        image.addRepresentation(bitmap)
        return image
    }
}

/// Bridges cache eviction and asynchronous rebuilds. Completed results stay alive until
/// consumed; afterwards a weak index reuses images still owned by the preview's attachments.
/// This avoids both repeated rendering of over-budget documents and retaining removed images.
final class PreviewImageResources {
    private var documentId: UUID?
    private var content: String?
    private var style: String?
    private let images = NSMapTable<NSString, NSImage>.strongToWeakObjects()
    private var completed: [String: NSImage] = [:]
    private(set) var generation: UInt = 0

    func prepare(documentId: UUID, content: String, style: String) {
        guard self.documentId != documentId || self.content != content || self.style != style else { return }
        if self.documentId != documentId || self.style != style {
            images.removeAllObjects()
        }
        self.documentId = documentId
        self.content = content
        self.style = style
        generation &+= 1
        completed.removeAll()
    }

    func image(forKey key: String, cache: NSCache<NSString, NSImage>) -> NSImage? {
        guard let image = completed.removeValue(forKey: key)
            ?? images.object(forKey: key as NSString)
            ?? cache.object(forKey: key as NSString) else { return nil }
        images.setObject(image, forKey: key as NSString)
        return image
    }

    func insert(_ image: NSImage, forKey key: String, generation: UInt) {
        guard generation == self.generation else { return }
        completed[key] = image
    }
}
