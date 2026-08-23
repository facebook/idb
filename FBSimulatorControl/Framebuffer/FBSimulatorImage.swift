/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreImage
@preconcurrency import FBControlCore
import Foundation
@preconcurrency import IOSurface
import ImageIO
import UniformTypeIdentifiers

/// The ways image encoding can fail, as data rather than assembled strings.
public enum FBSimulatorImageError: Error, LocalizedError {
  case noImage
  case destinationCreationFailed
  case finalizationFailed

  public var errorDescription: String? {
    switch self {
    case .noImage:
      return "No Image available to encode"
    case .destinationCreationFailed:
      return "Could not create image destination"
    case .finalizationFailed:
      return "Could not finalize the creation of the Image"
    }
  }
}

public actor FBSimulatorImage {

  // MARK: - Properties

  private let logger: (any FBControlCoreLogger)?
  private let imageGenerator: FBSurfaceImageGenerator
  private let framebuffer: FBFramebuffer
  private var attachment: FBFramebufferAttachment?
  private var eventTask: Task<Void, Never>?

  // MARK: - Initializers

  public static func image(with framebuffer: FBFramebuffer, logger: (any FBControlCoreLogger)?) -> FBSimulatorImage {
    FBSimulatorImage(framebuffer: framebuffer, logger: logger)
  }

  init(framebuffer: FBFramebuffer, logger: (any FBControlCoreLogger)?) {
    self.framebuffer = framebuffer
    self.logger = logger
    self.imageGenerator = FBSurfaceImageGenerator(scale: NSDecimalNumber.one, purpose: "simulator_image", logger: logger)
  }

  deinit {
    // Finishing the stream ends the event task, which releases the attachment.
    attachment?.cancel()
    eventTask?.cancel()
  }

  // MARK: - Public Methods

  public func image() throws -> CGImage? {
    try attachIfNeeded()
    return imageGenerator.image()
  }

  public func jpegImageData() throws -> Data {
    try FBSimulatorImage.jpegImageData(from: image())
  }

  public func pngImageData() throws -> Data {
    try FBSimulatorImage.pngImageData(from: image())
  }

  // MARK: - Private

  /// One-time lazy attach; actor isolation makes this attach-exactly-once regardless of caller
  /// threading. The generator's surface is seeded synchronously from `initialSurface`, then kept
  /// current by a task consuming the attachment's ordered event stream.
  private func attachIfNeeded() throws {
    guard attachment == nil else {
      return
    }
    logger?.log("Image Generator \(imageGenerator) not attached, attaching")
    let attachment = try framebuffer.attach()
    self.attachment = attachment
    if let surface = attachment.initialSurface {
      logger?.log("Surface \(surface) immediately available, adding to Image Generator \(imageGenerator)")
      imageGenerator.updateSurface(surface)
    } else {
      logger?.log("Surface for ImageGenerator not immediately available")
    }
    eventTask = Task { [weak self] in
      for await event in attachment.events {
        guard case let .surfaceChanged(surface) = event else {
          continue
        }
        await self?.applySurface(surface)
      }
    }
  }

  private func applySurface(_ surface: IOSurface?) {
    imageGenerator.updateSurface(surface)
  }

  // MARK: - Encoding

  private static func jpegImageData(from image: CGImage?) throws -> Data {
    try imageData(from: image, type: .jpeg)
  }

  private static func pngImageData(from image: CGImage?) throws -> Data {
    try imageData(from: image, type: .png)
  }

  private static func imageData(from image: CGImage?, type: UTType) throws -> Data {
    guard let image else {
      throw FBSimulatorImageError.noImage
    }

    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, type.identifier as CFString, 1, nil) else {
      throw FBSimulatorImageError.destinationCreationFailed
    }
    CGImageDestinationAddImage(destination, image, nil)
    if !CGImageDestinationFinalize(destination) {
      throw FBSimulatorImageError.finalizationFailed
    }
    return data as Data
  }
}
