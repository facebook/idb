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

/// Renders the latest simulator IOSurface to a `CGImage`. Not thread-safe by itself: it is owned and
/// confined by the `FBSimulatorImage` actor, which serializes `updateSurface` and `image()`.
public final class FBSurfaceImageGenerator {

  // MARK: - Properties

  private let logger: (any FBControlCoreLogger)?
  private let scaleFilter: CIFilter?
  /// Created once and reused across renders: CIContext construction is expensive (it builds a GPU
  /// pipeline) and the context carries no per-image state.
  private let context = CIContext(options: nil)

  private var surface: IOSurface?

  // MARK: - Initializers

  public convenience init(scale: NSDecimalNumber, purpose: String, logger: (any FBControlCoreLogger)?) {
    let namedLogger = logger?.withName("\(logger?.name ?? "")_\(purpose)")
    self.init(scale: scale, logger: namedLogger)
  }

  private init(scale: NSDecimalNumber, logger: (any FBControlCoreLogger)?) {
    self.logger = logger

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

  public func image() -> CGImage? {
    guard let surface = self.surface else {
      return nil
    }
    var ciImage = CIImage(ioSurface: unsafeBitCast(surface, to: IOSurfaceRef.self))
    if let scaleFilter = self.scaleFilter {
      scaleFilter.setValue(ciImage, forKey: kCIInputImageKey)
      guard let scaled = scaleFilter.outputImage else {
        return nil
      }
      ciImage = scaled
    }

    return context.createCGImage(ciImage, from: ciImage.extent)
  }

  // MARK: - Surface

  public func updateSurface(_ surface: IOSurface?) {
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
}
