/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
import FBControlCore
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The ways screenshot capture can fail, as data rather than assembled strings.
public enum FBSimulatorScreenshotError: Error {
  case unrecognizedFormat(format: String)
  case captureFailed
  case cropRectOutOfBounds(cropRect: CGRect)
  case imageDestinationCreationFailed
  case encodingFailed
}

extension FBSimulatorScreenshotError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case let .unrecognizedFormat(format):
      return "\(format) is not a recognized screenshot format"
    case .captureFailed:
      return "Failed to capture a screenshot"
    case let .cropRectOutOfBounds(cropRect):
      return "Screenshot crop rect \(cropRect) is outside the screen bounds"
    case .imageDestinationCreationFailed:
      return "Failed to create an image destination"
    case .encodingFailed:
      return "Failed to encode the screenshot"
    }
  }
}

public final class FBSimulatorScreenshotCommands {

  // MARK: - Properties

  private let simulator: FBSimulator
  private var image: FBSimulatorImage?

  // MARK: - Initializers

  public class func commands(with simulator: FBSimulator) -> FBSimulatorScreenshotCommands {
    FBSimulatorScreenshotCommands(simulator: simulator)
  }

  private init(simulator: FBSimulator) {
    self.simulator = simulator
  }

  // MARK: - Private

  fileprivate func takeScreenshotAsync(format: FBScreenshotFormat) async throws -> Data {
    let image = try await connectToImage()
    if format == .jpeg {
      return try await image.jpegImageData()
    } else if format == .png {
      return try await image.pngImageData()
    } else {
      throw FBSimulatorScreenshotError.unrecognizedFormat(format: String(describing: format))
    }
  }

  private func connectToImage() async throws -> FBSimulatorImage {
    if let image = self.image {
      return image
    }
    let framebuffer = try await simulator.connectToFramebuffer()
    let image = FBSimulatorImage(framebuffer: framebuffer, logger: simulator.logger)
    self.image = image
    return image
  }

  fileprivate func replScreenshotData(cropRect: CGRect?, asPNG: Bool) async throws -> Data {
    let image = try await replScreenshotImage(cropRect: cropRect)
    return try Self.encode(image, asPNG: asPNG)
  }

  /// Captures the current screen, optionally cropped to `cropRect` (in screen
  /// points). The framebuffer image is at native pixel resolution, so the crop is
  /// scaled from points to pixels using the target's screen scale.
  private func replScreenshotImage(cropRect: CGRect?) async throws -> CGImage {
    let image = try await connectToImage()
    guard let full = try await image.image() else {
      throw FBSimulatorScreenshotError.captureFailed
    }
    guard let cropRect else {
      return full
    }
    let scale = CGFloat(simulator.screenInfo?.scale ?? 1)
    let pixelRect = CGRect(
      x: cropRect.origin.x * scale,
      y: cropRect.origin.y * scale,
      width: cropRect.size.width * scale,
      height: cropRect.size.height * scale
    ).integral
    let bounds = CGRect(x: 0, y: 0, width: full.width, height: full.height)
    let clamped = pixelRect.intersection(bounds)
    guard !clamped.isNull, clamped.width >= 1, clamped.height >= 1, let cropped = full.cropping(to: clamped) else {
      throw FBSimulatorScreenshotError.cropRectOutOfBounds(cropRect: cropRect)
    }
    return cropped
  }

  private static func encode(_ image: CGImage, asPNG: Bool) throws -> Data {
    let type: UTType = asPNG ? .png : .tiff
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else {
      throw FBSimulatorScreenshotError.imageDestinationCreationFailed
    }
    var properties: [CFString: Any] = [:]
    if !asPNG {
      // Uncompressed TIFF: preserve the pixels and color space with no codec cost.
      properties[kCGImagePropertyTIFFDictionary] = [kCGImagePropertyTIFFCompression: 1]
    }
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
      throw FBSimulatorScreenshotError.encodingFailed
    }
    return data as Data
  }
}

// MARK: - FBSimulator+ScreenshotCommands

extension FBSimulator: ScreenshotCommands {

  public func takeScreenshot(format: FBScreenshotFormat) async throws -> Data {
    try await screenshotCommands().takeScreenshotAsync(format: format)
  }

  /// Captures the current screen as uncompressed TIFF (default) or PNG, optionally
  /// cropped to `cropRect` (in screen points). Backs the REPL screenshot command.
  public func replScreenshot(cropRect: CGRect?, asPNG: Bool) async throws -> Data {
    try await screenshotCommands().replScreenshotData(cropRect: cropRect, asPNG: asPNG)
  }
}
