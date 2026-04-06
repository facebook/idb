/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

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

  // MARK: - FBScreenshotCommands

  @objc
  public func takeScreenshot(_ format: FBScreenshotFormat) -> FBFuture<NSData> {
    return connectToImage()
      .onQueue(simulator.workQueue, fmap: { image -> FBFuture<AnyObject> in
        do {
          let data: Data
          if format == .JPEG {
            data = try image.jpegImageData()
          } else if format == .PNG {
            data = try image.pngImageData()
          } else {
            return FBSimulatorError.describe("\(format) is not a recognized screenshot format")
              .failFuture()
          }
          return FBFuture(result: data as NSData)
        } catch {
          return FBFuture(error: error)
        }
      }) as! FBFuture<NSData>
  }

  // MARK: - Private

  private func connectToImage() -> FBFuture<FBSimulatorImage> {
    if let image = self.image {
      return FBFuture(result: image)
    }
    return simulator.connectToFramebuffer()
      .onQueue(simulator.workQueue, fmap: { [weak self] framebuffer -> FBFuture<AnyObject> in
        let image = FBSimulatorImage(framebuffer: framebuffer, logger: self?.simulator.logger)
        self?.image = image
        return FBFuture(result: image)
      }) as! FBFuture<FBSimulatorImage>
  }
}
