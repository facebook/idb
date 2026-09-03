/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
import FBControlCore
import Foundation

/// The ways screenshot capture can fail, as data rather than assembled strings. Everything after the
/// capture itself -- resolving the request against the screen, cropping, scaling, encoding -- is
/// shared with the other targets and reports `FBScreenshotGeometryError` or `FBScreenshotRenderError`.
public enum FBSimulatorScreenshotError: Error {
  case captureFailed
}

extension FBSimulatorScreenshotError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .captureFailed:
      return "Failed to capture a screenshot"
    }
  }
}

public final class FBSimulatorScreenshotCommands {

  // MARK: - Properties

  private weak var simulator: FBSimulator?
  private var image: FBSimulatorImage?

  // MARK: - Initializers

  public class func commands(with simulator: FBSimulator) -> FBSimulatorScreenshotCommands {
    FBSimulatorScreenshotCommands(simulator: simulator)
  }

  private init(simulator: FBSimulator) {
    self.simulator = simulator
  }

  // MARK: - Private

  /// The crop and scale are applied by the render itself rather than to its output, so all that is
  /// left here is to encode what comes back.
  fileprivate func takeScreenshotAsync(configuration: FBScreenshotConfiguration) async throws -> FBScreenshotResult {
    guard let simulator = self.simulator else {
      throw FBWeakTargetError.simulator
    }
    let image = try await connectToImage()
    let screenScale = simulator.screenInfo.map { Double($0.scale) }
    guard let captured = try await image.image(configuration: configuration, screenScale: screenScale) else {
      throw FBSimulatorScreenshotError.captureFailed
    }
    return try FBScreenshotRenderer.render(
      transformed: captured.image,
      sourceSize: captured.sourceSize,
      encoding: configuration.encoding,
      screenScale: screenScale
    )
  }

  private func connectToImage() async throws -> FBSimulatorImage {
    if let image = self.image {
      return image
    }
    guard let simulator = self.simulator else {
      throw FBWeakTargetError.simulator
    }
    let framebuffer = try await simulator.connectToFramebuffer()
    let image = FBSimulatorImage(framebuffer: framebuffer, logger: simulator.logger)
    self.image = image
    return image
  }

  /// The REPL's crop is in screen points, which is what `FBScreenshotUnit.points` means, so it needs
  /// no arithmetic of its own -- and going through the same path as every other caller is how the
  /// REPL and the gRPC API stay in agreement about what a crop rect denotes.
  fileprivate func replScreenshotData(cropRect: CGRect?, asPNG: Bool) async throws -> Data {
    let configuration = FBScreenshotConfiguration(
      encoding: asPNG ? .png : .tiff,
      cropRect: cropRect,
      unit: .points
    )
    return try await takeScreenshotAsync(configuration: configuration).imageData
  }
}

// MARK: - FBSimulator+ScreenshotCommands

extension FBSimulator: ScreenshotCommands {

  public func takeScreenshot(configuration: FBScreenshotConfiguration) async throws -> FBScreenshotResult {
    try await screenshot.takeScreenshotAsync(configuration: configuration)
  }

  /// Captures the current screen as uncompressed TIFF (default) or PNG, optionally
  /// cropped to `cropRect` (in screen points). Backs the REPL screenshot command.
  public func replScreenshot(cropRect: CGRect?, asPNG: Bool) async throws -> Data {
    try await screenshot.replScreenshotData(cropRect: cropRect, asPNG: asPNG)
  }
}
