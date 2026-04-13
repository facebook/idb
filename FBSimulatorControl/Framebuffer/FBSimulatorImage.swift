/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreImage
import FBControlCore
import Foundation
import ImageIO

@objc(FBSimulatorImage)
public final class FBSimulatorImage: NSObject {

  // MARK: - Properties

  private let logger: FBControlCoreLogger
  private let writeQueue: DispatchQueue
  private let imageGenerator: FBSurfaceImageGenerator
  private let framebuffer: FBFramebuffer
  private var consumerUUID: UUID

  // MARK: - Initializers

  @objc(imageWithFramebuffer:logger:)
  public class func image(with framebuffer: FBFramebuffer, logger: (any FBControlCoreLogger)?) -> FBSimulatorImage {
    return FBSimulatorImage(framebuffer: framebuffer, logger: logger)
  }

  init(framebuffer: FBFramebuffer, logger: (any FBControlCoreLogger)?) {
    self.framebuffer = framebuffer
    self.logger = logger!
    self.consumerUUID = UUID()
    self.writeQueue = DispatchQueue(label: "com.facebook.FBSimulatorControl.framebuffer.image")
    self.imageGenerator = FBSurfaceImageGenerator(scale: NSDecimalNumber.one, purpose: "simulator_image", logger: logger)
    super.init()
  }

  // MARK: - Public Methods

  @objc
  public func image() -> CGImage? {
    if !framebuffer.isConsumerAttached(imageGenerator) {
      logger.log("Image Generator \(imageGenerator) not attached, attaching")
      let surface: IOSurface? = framebuffer.attach(imageGenerator, on: writeQueue)
      if let surface {
        logger.log("Surface \(surface) immediately available, adding to Image Generator \(imageGenerator)")
        imageGenerator.didChange(surface)
      } else {
        logger.log("Surface for ImageGenerator not immedately available")
      }
    }

    let img = imageGenerator.image()
    if img != nil {
      return img
    }
    return imageGenerator.image()
  }

  @objc
  public func jpegImageData() throws -> Data {
    return try FBSimulatorImage.jpegImageData(from: image())
  }

  @objc
  public func pngImageData() throws -> Data {
    return try FBSimulatorImage.pngImageData(from: image())
  }

  // MARK: - Private

  private class func jpegImageData(from image: CGImage?) throws -> Data {
    return try imageData(from: image, type: kUTTypeJPEG)
  }

  private class func pngImageData(from image: CGImage?) throws -> Data {
    return try imageData(from: image, type: kUTTypePNG)
  }

  private class func imageData(from image: CGImage?, type: CFString) throws -> Data {
    guard let image else {
      throw
        FBSimulatorError
        .describe("No Image available to encode")
        .build()
    }

    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, type, 1, nil) else {
      throw
        FBSimulatorError
        .describe("Could not create image destination")
        .build()
    }
    CGImageDestinationAddImage(destination, image, nil)
    if !CGImageDestinationFinalize(destination) {
      throw
        FBSimulatorError
        .describe("Could not finalize the creation of the Image")
        .build()
    }
    return data as Data
  }
}
