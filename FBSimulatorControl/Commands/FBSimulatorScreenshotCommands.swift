/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

// swiftlint:disable force_cast

@objc(FBSimulatorScreenshotCommands)
public final class FBSimulatorScreenshotCommands: NSObject, FBScreenshotCommands {

  // MARK: - Properties

  private let simulator: FBSimulator
  private var image: FBSimulatorImage?

  // MARK: - Initializers

  @objc(commandsWithTarget:)
  public class func commands(with target: any FBiOSTarget) -> FBSimulatorScreenshotCommands {
    return FBSimulatorScreenshotCommands(simulator: target as! FBSimulator)
  }

  private init(simulator: FBSimulator) {
    self.simulator = simulator
    super.init()
  }

  // MARK: - FBScreenshotCommands (legacy FBFuture entry point)

  @objc
  public func takeScreenshot(_ format: FBScreenshotFormat) -> FBFuture<NSData> {
    fbFutureFromAsync { [self] in
      let data = try await takeScreenshotAsync(format: format)
      return data as NSData
    }
  }

  // MARK: - Private

  fileprivate func takeScreenshotAsync(format: FBScreenshotFormat) async throws -> Data {
    let image = try await connectToImage()
    if format == .jpeg {
      return try image.jpegImageData()
    } else if format == .png {
      return try image.pngImageData()
    } else {
      throw FBSimulatorError.describe("\(format) is not a recognized screenshot format").build()
    }
  }

  private func connectToImage() async throws -> FBSimulatorImage {
    if let image = self.image {
      return image
    }
    // The @objc protocol erases the generic; the runtime value is FBFramebuffer.
    let framebuffer = try await bridgeFBFuture(simulator.connectToFramebuffer()) as! FBFramebuffer
    let image = FBSimulatorImage(framebuffer: framebuffer, logger: simulator.logger)
    self.image = image
    return image
  }
}

// MARK: - AsyncScreenshotCommands

extension FBSimulatorScreenshotCommands: AsyncScreenshotCommands {

  public func takeScreenshot(format: FBScreenshotFormat) async throws -> Data {
    try await takeScreenshotAsync(format: format)
  }
}

// MARK: - FBSimulator+AsyncScreenshotCommands

extension FBSimulator: AsyncScreenshotCommands {

  public func takeScreenshot(format: FBScreenshotFormat) async throws -> Data {
    try await screenshotCommands().takeScreenshot(format: format)
  }
}
