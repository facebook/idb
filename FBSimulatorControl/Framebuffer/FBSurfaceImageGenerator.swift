/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreImage
import FBControlCore
import Foundation
import IOSurface

public final class FBSurfaceImageGenerator: FBFramebufferConsumer {

  // MARK: - Properties

  private let logger: (any FBControlCoreLogger)?
  private let scaleFilter: CIFilter?

  private var surface: IOSurface?
  private var lastSeedValue: UInt32 = 0

  // MARK: - Initializers

  public convenience init(scale: NSDecimalNumber, purpose: String, logger: (any FBControlCoreLogger)?) {
    let namedLogger = logger?.withName("\(logger?.name ?? "")_\(purpose)")
    self.init(scale: scale, logger: namedLogger)
  }

  private init(scale: NSDecimalNumber, logger: (any FBControlCoreLogger)?) {
    self.logger = logger
    self.lastSeedValue = 0

    if scale.isEqual(to: NSDecimalNumber.one) {
      self.scaleFilter = nil
    } else {
      let filter = CIFilter(name: "CILanczosScaleTransform")
      filter?.setValue(scale, forKey: "inputScale")
      filter?.setValue(NSDecimalNumber.one, forKey: "inputAspectRatio")
      self.scaleFilter = filter
    }
  }

  // MARK: - Public

  public func availableImage() -> CGImage? {
    guard let surface = self.surface else {
      return nil
    }
    let currentSeed = surface.seed
    if currentSeed == lastSeedValue {
      return nil
    }
    lastSeedValue = currentSeed
    return image()
  }

  public func image() -> CGImage? {
    guard let surface = self.surface else {
      return nil
    }
    let context = CIContext(options: nil)
    var ciImage = CIImage(ioSurface: unsafeBitCast(surface, to: IOSurfaceRef.self))
    if let scaleFilter = self.scaleFilter {
      scaleFilter.setValue(ciImage, forKey: kCIInputImageKey)
      guard let scaled = scaleFilter.outputImage else {
        return nil
      }
      ciImage = scaled
      scaleFilter.setValue(ciImage, forKey: kCIInputImageKey)
    }

    return context.createCGImage(ciImage, from: ciImage.extent)
  }

  // MARK: - FBFramebufferConsumer

  public func didChange(_ surface: IOSurface?) {
    lastSeedValue = 0
    if let oldSurface = self.surface {
      logger?.info().log("Removing old surface \(oldSurface)")
      oldSurface.decrementUseCount()
      self.surface = nil
    }
    if let surface {
      surface.incrementUseCount()
      logger?.info().log("Received IOSurface from Framebuffer Service \(surface)")
      self.surface = surface
    }
  }

  public func didRenderFrame() {
  }
}
