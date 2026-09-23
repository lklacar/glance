import AppKit
import ImageIO

public enum ViewerError: LocalizedError {
    case unreadable(String), emptyFolder, tooLarge
    public var errorDescription: String? {
        switch self {
        case .unreadable(let name): return "Couldn’t open “\(name)”. The file may be damaged or use a format this version of macOS cannot decode."
        case .emptyFolder: return "This folder doesn’t contain any supported images."
        case .tooLarge: return "This image’s dimensions are invalid or too large to display safely."
        }
    }
}

/// Loaded on a decoder queue, then handed off to the serial animation queue.
/// Cached instances share the immutable first frame; source access stays serial.
public final class DecodedImage {
    public let image: CGImage
    public let pixelSize: CGSize
    public let typeName: String
    public let frameCount: Int
    public let fileSize: Int
    public let isDownsampled: Bool
    private let source: CGImageSource?
    private let maximumDimension: Int

    init(image: CGImage, pixelSize: CGSize, typeName: String, frameCount: Int = 1,
         fileSize: Int, source: CGImageSource? = nil, maximumDimension: Int = 16384) {
        self.image = image; self.pixelSize = pixelSize; self.typeName = typeName
        self.frameCount = frameCount; self.fileSize = fileSize; self.source = source
        self.maximumDimension = maximumDimension
        isDownsampled = CGFloat(image.width) + 1 < pixelSize.width || CGFloat(image.height) + 1 < pixelSize.height
    }

    public func frame(at index: Int) -> CGImage? {
        guard let source, index > 0 else { return image }
        return ImageDecoder.thumbnail(source, index: index % frameCount, maximum: maximumDimension)
    }

    public func duration(at index: Int) -> TimeInterval {
        guard let source,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [String: Any] else { return 0.1 }
        for key in ["{GIF}", "{PNG}", "{WebP}", "{HEICS}"] {
            if let values = properties[key] as? [String: Any] {
                let seconds = (values["UnclampedDelayTime"] as? NSNumber)?.doubleValue
                    ?? (values["DelayTime"] as? NSNumber)?.doubleValue ?? 0.1
                return seconds < 0.011 ? 0.1 : min(seconds, 60)
            }
        }
        return 0.1
    }
}

public enum ImageDecoder {
    // Limit the decoded working set; the original file is never changed.
    public static let pixelBudget: Double = 48_000_000

    public static func load(_ url: URL) throws -> DecodedImage {
        guard url.isFileURL else { throw ViewerError.unreadable(url.lastPathComponent) }
        // Read once on the worker. ImageIO must not retain a file-backed provider
        // that could perform network I/O later during presentation or animation.
        let data = try Data(contentsOf: url)
        let fileSize = data.count
        if !["svg", "pdf"].contains(url.pathExtension.lowercased()),
           let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] {
            let width = (properties[kCGImagePropertyPixelWidth as String] as? NSNumber)?.doubleValue ?? 0
            let height = (properties[kCGImagePropertyPixelHeight as String] as? NSNumber)?.doubleValue ?? 0
            guard width > 0, height > 0, width.isFinite, height.isFinite else { throw ViewerError.tooLarge }
            let ratio = min(1, sqrt(pixelBudget / (width * height)), 16384 / max(width, height))
            let maximum = max(1, Int(max(width, height) * ratio))
            guard let image = thumbnail(source, index: 0, maximum: maximum) else {
                throw ViewerError.unreadable(url.lastPathComponent)
            }
            let orientation = (properties[kCGImagePropertyOrientation as String] as? NSNumber)?.intValue ?? 1
            let size = orientation >= 5 && orientation <= 8
                ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
            let type = CGImageSourceGetType(source) as String? ?? ""
            let animated = ["com.compuserve.gif", "public.png", "org.webmproject.webp"].contains(type)
            return DecodedImage(image: image, pixelSize: size, typeName: url.pathExtension.uppercased(),
                frameCount: animated ? CGImageSourceGetCount(source) : 1, fileSize: fileSize,
                source: animated ? source : nil, maximumDimension: maximum)
        }
        // AppKit handles SVG and PDF without a web view, network requests, or an external process.
        guard ["svg", "pdf"].contains(url.pathExtension.lowercased()), let vector = NSImage(data: data),
              vector.size.width > 0, vector.size.height > 0,
              vector.size.width.isFinite, vector.size.height.isFinite else {
            throw ViewerError.unreadable(url.lastPathComponent)
        }
        let originalSize = vector.size
        let ratio = min(4, 8192 / max(originalSize.width, originalSize.height),
                        sqrt(pixelBudget / (originalSize.width * originalSize.height)))
        let width = max(1, Int(originalSize.width * ratio)), height = max(1, Int(originalSize.height * ratio))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw ViewerError.tooLarge }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        vector.draw(in: CGRect(x: 0, y: 0, width: width, height: height), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        guard let image = context.makeImage() else { throw ViewerError.unreadable(url.lastPathComponent) }
        return DecodedImage(image: image, pixelSize: originalSize, typeName: url.pathExtension.uppercased(), fileSize: fileSize)
    }

    static func thumbnail(_ source: CGImageSource, index: Int, maximum: Int) -> CGImage? {
        CGImageSourceCreateThumbnailAtIndex(source, index, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximum,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceShouldCache: false
        ] as CFDictionary)
    }
}
