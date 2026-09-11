/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
import FBControlCore
import Foundation

/// Everything after the capture itself -- resolving the request against the screen, cropping, scaling,
/// encoding -- is shared with the other targets and reports `FBScreenshotGeometryError` or
/// `ScreenshotRenderError`.
public enum SimulatorScreenshotError: Error {
  case captureFailed
}

extension SimulatorScreenshotError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .captureFailed:
      return "Failed to capture a screenshot"
    }
  }
}

public final class SimulatorScreenshotCommands: ScreenshotCommands {

  private weak var simulator: FBSimulator?
  private var image: SimulatorImage?

  public class func commands(with simulator: FBSimulator) -> SimulatorScreenshotCommands {
    SimulatorScreenshotCommands(simulator: simulator)
  }

  private init(simulator: FBSimulator) {
    self.simulator = simulator
  }

  /// The crop and scale are applied by the render itself rather than to its output, so all that is
  /// left here is to encode what comes back.
  public func take(configuration: FBScreenshotConfiguration) async throws -> FBScreenshotResult {
    guard let simulator = self.simulator else {
      throw WeakTargetError.simulator
    }
    let image = try await connectToImage()
    let screenScale = simulator.screenInfo.map { Double($0.scale) }
    guard let captured = try await image.image(configuration: configuration, screenScale: screenScale) else {
      throw SimulatorScreenshotError.captureFailed
    }
    return try ScreenshotRenderer.render(
      transformed: captured.image,
      sourceSize: captured.sourceSize,
      encoding: configuration.encoding,
      screenScale: screenScale
    )
  }

  private func connectToImage() async throws -> SimulatorImage {
    if let image = self.image {
      return image
    }
    guard let simulator = self.simulator else {
      throw WeakTargetError.simulator
    }
    let framebuffer = try await simulator.lifecycle.connectToFramebuffer()
    let image = SimulatorImage(framebuffer: framebuffer, logger: simulator.logger)
    self.image = image
    return image
  }

  /// The REPL's crop is in screen points (`FBScreenshotUnit.points`).
  public func takeForRepl(cropRect: CGRect?, asPNG: Bool) async throws -> Data {
    let configuration = FBScreenshotConfiguration(
      encoding: asPNG ? .png : .tiff,
      cropRect: cropRect,
      unit: .points
    )
    return try await take(configuration: configuration).imageData
  }
}
