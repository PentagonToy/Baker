import AppKit
import ImageIO

/// Owns eagerly encoded clipboard data, independent of the source image's lifetime.
public enum ImageClipboard {
    public struct Payload: Sendable {
        fileprivate let png: Data
        fileprivate let tiff: Data
    }

    /// Image reading and encoding may run away from the UI thread.
    public static func prepare(imageURL: URL) throws -> Payload {
        guard imageURL.isFileURL else { throw BakerError(message: "Choose a local image to copy.", code: .invalidInput) }
        let values = try imageURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, let size = values.fileSize,
              size > 0, size <= CaptureArchive.maximumSourceBytes else {
            throw BakerError(message: "Choose a regular image no larger than 128 MB.", code: .invalidInput)
        }
        guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) == 1,
              let type = CGImageSourceGetType(source) as String?,
              ["public.png", "public.jpeg", "public.tiff", "public.heic", "public.heif", "com.microsoft.bmp"].contains(type),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else {
            throw BakerError(message: "Choose a PNG, JPEG, TIFF, HEIC, HEIF or BMP still image to copy.", code: .invalidInput)
        }
        let w = width.intValue, h = height.intValue
        guard w > 0, h > 0, w <= CaptureArchive.maximumDimension, h <= CaptureArchive.maximumDimension,
              w * h <= CaptureArchive.maximumPixels else {
            throw BakerError(message: "Copied images must fit within 8192 pixels per side and 32 megapixels.", code: .resourceLimit)
        }
        // Decode at the original pixel size, applying EXIF orientation rather than
        // carrying a lazy URL-backed NSImage into the pasteboard.
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(w, h),
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary), image.width * image.height <= CaptureArchive.maximumPixels else {
            throw BakerError(message: "The image could not be decoded for copying.", code: .clipboardFailed)
        }
        let png = try encode(image, type: "public.png")
        let tiff = try encode(image, type: "public.tiff")
        return Payload(png: png, tiff: tiff)
    }

    public static func write(_ payload: Payload, to pasteboard: NSPasteboard = .general) throws {
        let item = NSPasteboardItem()
        guard item.setData(payload.png, forType: .png), item.setData(payload.tiff, forType: .tiff) else {
            throw BakerError(message: "Could not prepare the image clipboard formats.", code: .clipboardFailed)
        }
        // Preserve existing clipboard content if reading or encoding failed.
        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else {
            throw BakerError(message: "The image could not be written to the clipboard.", code: .clipboardFailed)
        }
    }

    public static func write(imageURL: URL, to pasteboard: NSPasteboard = .general) throws {
        try write(prepare(imageURL: imageURL), to: pasteboard)
    }

    private static func encode(_ image: CGImage, type: String) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type as CFString, 1, nil) else {
            throw BakerError(message: "The image clipboard encoder is unavailable.", code: .clipboardFailed)
        }
        var properties: [CFString: Any] = [kCGImagePropertyOrientation: 1]
        if type == "public.tiff" { properties[kCGImagePropertyTIFFDictionary] = [kCGImagePropertyTIFFCompression: 5] }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination), data.length > 0 else {
            throw BakerError(message: "The image could not be encoded for copying.", code: .clipboardFailed)
        }
        return data as Data
    }
}
