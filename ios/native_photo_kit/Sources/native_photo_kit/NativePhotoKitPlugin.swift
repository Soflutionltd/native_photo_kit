import CoreImage
import Flutter
import ImageIO

/// Photos are decoded straight at the size they are needed (never at full
/// resolution to output 1080 px), with EXIF orientation and color profile
/// applied, then composited by Core Image on the GPU and encoded by ImageIO.
public final class NativePhotoKitPlugin: NSObject, FlutterPlugin {
  private static let channelName = "native_photo_kit"

  /// Several photos of the same import are processed in parallel.
  private static let queue = DispatchQueue(
    label: "native_photo_kit",
    qos: .userInitiated,
    attributes: .concurrent
  )
  private static let context = CIContext(options: [.cacheIntermediates: false])
  private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

  private static let backgroundBlurSigma = 12.0
  private static let backgroundDim = CIColor(red: 12 / 255, green: 12 / 255, blue: 12 / 255, alpha: 60 / 255)

  private struct PluginError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(NativePhotoKitPlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any] else {
      result(FlutterError(code: "bad_args", message: "Missing arguments for \(call.method)", details: nil))
      return
    }

    let work: () throws -> Any?
    switch call.method {
    case "encodeJpeg":
      work = { try FlutterStandardTypedData(bytes: Self.encodeJpeg(args)) }
    case "orientedSize":
      work = { try Self.orientedSize(args) }
    case "coverJpeg":
      work = { try Self.coverJpeg(args).map(FlutterStandardTypedData.init(bytes:)) }
    case "formatForFeed":
      work = { try Self.formatForFeed(args).map(FlutterStandardTypedData.init(bytes:)) }
    default:
      result(FlutterMethodNotImplemented)
      return
    }

    Self.queue.async {
      let reply: Any?
      do {
        reply = try autoreleasepool { try work() }
      } catch {
        reply = FlutterError(code: "native_photo_kit", message: "\(call.method): \(error)", details: nil)
      }
      DispatchQueue.main.async { result(reply) }
    }
  }

  // MARK: - Methods

  private static func encodeJpeg(_ args: [String: Any]) throws -> Data {
    guard let rgba = (args["rgba"] as? FlutterStandardTypedData)?.data,
          let width = args["width"] as? Int, width > 0,
          let height = args["height"] as? Int, height > 0,
          let quality = args["quality"] as? Int,
          rgba.count >= width * height * 4
    else { throw PluginError("invalid arguments") }

    guard let provider = CGDataProvider(data: rgba as CFData),
          let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: sRGB,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
          )
    else { throw PluginError("unreadable pixels (\(width)x\(height))") }

    return try jpegData(image, quality: quality)
  }

  private static func orientedSize(_ args: [String: Any]) throws -> [Int]? {
    guard let path = args["path"] as? String else { throw PluginError("missing path") }
    guard let photo = Photo(path: path) else { return nil }
    return [photo.width, photo.height]
  }

  private static func coverJpeg(_ args: [String: Any]) throws -> Data? {
    let target = try Target(args)
    guard let photo = Photo(path: target.path),
          let decoded = photo.decoded(covering: target.size)
    else { return nil }

    return try render(cover(decoded, target.size), target)
  }

  private static func formatForFeed(_ args: [String: Any]) throws -> Data? {
    let target = try Target(args)
    guard let photo = Photo(path: target.path),
          let decoded = photo.decoded(covering: target.size)
    else { return nil }

    let frame = CGRect(origin: .zero, size: target.size)
    let background = cover(decoded, target.size)
      .clampedToExtent()
      .applyingGaussianBlur(sigma: backgroundBlurSigma)
      .cropped(to: frame)
    let dim = CIImage(color: backgroundDim).cropped(to: frame)

    let scale = min(target.size.width / decoded.extent.width, target.size.height / decoded.extent.height)
    let foreground = resized(decoded, scale: scale)
    let offset = CGPoint(
      x: ((target.size.width - foreground.extent.width) / 2).rounded(),
      y: ((target.size.height - foreground.extent.height) / 2).rounded()
    )
    let placed = foreground.transformed(by: CGAffineTransform(
      translationX: offset.x - foreground.extent.minX,
      y: offset.y - foreground.extent.minY
    ))

    return try render(placed.composited(over: dim.composited(over: background)), target)
  }

  // MARK: - Helpers

  private struct Target {
    let path: String
    let size: CGSize
    let quality: Int

    init(_ args: [String: Any]) throws {
      guard let path = args["path"] as? String,
            let width = args["width"] as? Int, width > 0,
            let height = args["height"] as? Int, height > 0,
            let quality = args["quality"] as? Int
      else { throw PluginError("invalid arguments") }
      self.path = path
      self.size = CGSize(width: width, height: height)
      self.quality = quality
    }
  }

  /// Image file with its displayed dimensions.
  private struct Photo {
    let source: CGImageSource
    let width: Int
    let height: Int

    init?(path: String) {
      guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let pixelWidth = properties[kCGImagePropertyPixelWidth] as? Int, pixelWidth > 0,
            let pixelHeight = properties[kCGImagePropertyPixelHeight] as? Int, pixelHeight > 0
      else { return nil }

      // EXIF orientations 5 to 8 lay the sensor on its side: width and height swap.
      let orientation = properties[kCGImagePropertyOrientation] as? UInt32 ?? 1
      let swapsAxes = (5...8).contains(orientation)
      self.source = source
      self.width = swapsAxes ? pixelHeight : pixelWidth
      self.height = swapsAxes ? pixelWidth : pixelHeight
    }

    /// Oriented decode, just large enough to cover `size`, never upscaled.
    func decoded(covering size: CGSize) -> CIImage? {
      let scale = min(1, max(size.width / CGFloat(width), size.height / CGFloat(height)))
      let longestEdge = (CGFloat(max(width, height)) * scale).rounded(.up)
      let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceThumbnailMaxPixelSize: Int(longestEdge),
      ]
      guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
        return nil
      }
      return CIImage(cgImage: image)
    }
  }

  private static func resized(_ image: CIImage, scale: CGFloat) -> CIImage {
    image.applyingFilter("CILanczosScaleTransform", parameters: [
      kCIInputScaleKey: scale,
      kCIInputAspectRatioKey: 1.0,
    ])
  }

  /// Scales up or down to fill `size`, then crops around the center.
  private static func cover(_ image: CIImage, _ size: CGSize) -> CIImage {
    let scale = max(size.width / image.extent.width, size.height / image.extent.height)
    let scaled = resized(image, scale: scale)
    let crop = CGRect(
      x: scaled.extent.minX + ((scaled.extent.width - size.width) / 2).rounded(),
      y: scaled.extent.minY + ((scaled.extent.height - size.height) / 2).rounded(),
      width: size.width,
      height: size.height
    )
    // Lanczos can render a fraction of a pixel less than requested: the edge
    // is extended rather than left transparent.
    return scaled.clampedToExtent()
      .cropped(to: crop)
      .transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
  }

  private static func render(_ image: CIImage, _ target: Target) throws -> Data {
    guard let rendered = context.createCGImage(
      image,
      from: CGRect(origin: .zero, size: target.size),
      format: .RGBA8,
      colorSpace: sRGB
    ) else { throw PluginError("Core Image render failed") }
    return try jpegData(rendered, quality: target.quality)
  }

  private static func jpegData(_ image: CGImage, quality: Int) throws -> Data {
    let output = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(output, "public.jpeg" as CFString, 1, nil) else {
      throw PluginError("JPEG encoder unavailable")
    }
    let options = [kCGImageDestinationLossyCompressionQuality: Double(quality) / 100] as CFDictionary
    CGImageDestinationAddImage(destination, image, options)
    guard CGImageDestinationFinalize(destination) else { throw PluginError("JPEG encoding failed") }
    return output as Data
  }
}
