/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@_implementationOnly @preconcurrency import CoreSimDeviceIO
@preconcurrency import CoreSimulator
@preconcurrency import FBControlCore
import Foundation
import IOSurface

/// A batch of display regions reported by a framebuffer damage callback. Each rect is in the
/// surface's pixel coordinate space. An empty batch is a valid "surface changed, no rects reported"
/// signal.
struct FBFramebufferDamage {
  let rects: [CGRect]
}

/// The seam between `FBFramebuffer` and the private CoreSimulator display surface. Expressed purely
/// in public/standard types so the private `@_implementationOnly` renderable protocols never leak
/// into `FBFramebuffer`'s logic and a fake can be substituted in tests.
protocol FBFramebufferSurface: AnyObject {
  /// The surface available right now, if the underlying renderable can vend one synchronously.
  func immediatelyAvailableSurface() -> IOSurface?

  /// Register per-consumer callbacks keyed by `token`. Throws if the surface-change callback could
  /// not be installed on either the plural or singular renderable entry point.
  func registerCallbacks(
    token: UUID,
    ioSurfaceChanged: @escaping (IOSurface?) -> Void,
    damageReceived: @escaping (FBFramebufferDamage) -> Void
  ) throws

  /// Best-effort removal of the callbacks registered under `token`.
  func unregisterCallbacks(token: UUID)
}

/// The production `FBFramebufferSurface`, wrapping the private CoreSimulator renderable. This is the
/// single place that touches the `@_implementationOnly` renderable protocols, `FBObjCExceptionGuard`,
/// and the `NSValue`→`CGRect` damage decode; it is `fileprivate` so those private types never appear
/// in any interface reachable via `@testable import`.
private final class SimDisplayRenderableSurface: FBFramebufferSurface {
  private let surface: any SimDisplayIOSurfaceRenderable & SimDisplayRenderable
  private let logger: any FBControlCoreLogger

  init(surface: any SimDisplayIOSurfaceRenderable & SimDisplayRenderable, logger: any FBControlCoreLogger) {
    self.surface = surface
    self.logger = logger
  }

  func immediatelyAvailableSurface() -> IOSurface? {
    if let surface = try? FBObjCExceptionGuard.guarded({ self.surface.framebufferSurface }) as? IOSurface {
      return surface
    }
    return try? FBObjCExceptionGuard.guarded({ self.surface.ioSurface }) as? IOSurface
  }

  func registerCallbacks(
    token: UUID,
    ioSurfaceChanged: @escaping (IOSurface?) -> Void,
    damageReceived: @escaping (FBFramebufferDamage) -> Void
  ) throws {
    // Register the plural and singular IOSurface entry points and the damage callback independently
    // and best-effort, mirroring the pre-seam framebuffer: the underlying ROCKRemoteProxy may
    // implement only some of these, and one failing must not prevent the others.
    let ioSurfaceBlock: (Any?) -> Void = { ioSurfaceChanged($0 as? IOSurface) }
    _ = try? FBObjCExceptionGuard.guarded { self.surface.registerCallback(with: token, ioSurfacesChangeCallback: ioSurfaceBlock) }
    _ = try? FBObjCExceptionGuard.guarded { self.surface.registerCallback(with: token, ioSurfaceChangeCallback: ioSurfaceBlock) }

    let damageBlock: ([NSValue]?) -> Void = { frames in
      // The `[NSValue]` element type is nominal: the proxy vends an untyped NSArray and Swift's block
      // bridging does not validate elements, so cast each dynamically and drop anything that is not
      // an NSValue rather than force-messaging `rectValue`.
      let rects = (frames ?? []).compactMap { ($0 as AnyObject) as? NSValue }.map(\.rectValue)
      damageReceived(FBFramebufferDamage(rects: rects))
    }
    _ = try? FBObjCExceptionGuard.guarded { self.surface.registerCallback(with: token, damageRectanglesCallback: damageBlock) }
  }

  func unregisterCallbacks(token: UUID) {
    _ = try? FBObjCExceptionGuard.guarded { self.surface.unregisterIOSurfacesChangeCallback(with: token) }
    _ = try? FBObjCExceptionGuard.guarded { self.surface.unregisterIOSurfaceChangeCallback(with: token) }
    _ = try? FBObjCExceptionGuard.guarded { self.surface.unregisterDamageRectanglesCallback(with: token) }
  }
}

/// Locates the simulator's main-display surface among its IO ports and wraps it in a production
/// `FBFramebufferSurface`. Kept separate from `FBFramebuffer` so that discovery, adaptation, and
/// consumer fan-out are distinct concerns.
enum FBFramebufferSurfaceLocator {
  static func mainDisplaySurface(for simulator: FBSimulator, logger: any FBControlCoreLogger) throws -> any FBFramebufferSurface {
    guard let ioClient = simulator.device.io else {
      throw FBSimulatorError.describe("No IO client available on \(simulator.device)").build()
    }
    guard let ports = ioClient.ioPorts() else {
      throw FBSimulatorError.describe("No IO ports available on \(ioClient)").build()
    }

    // iOS exposes the main display as displayClass 0. tvOS renders only on the TVOut display (a
    // non-zero class), so prefer class 0 but fall back to the first renderable display rather than
    // throwing — otherwise screenshots and video are impossible on a target with no class-0 display.
    var fallback: (any SimDisplayIOSurfaceRenderable & SimDisplayRenderable)?
    for portInterface in ports {
      let descriptor = portInterface.descriptor as AnyObject
      guard let renderable = descriptor as? (any SimDisplayIOSurfaceRenderable & SimDisplayRenderable) else {
        continue
      }
      guard descriptor.responds(to: NSSelectorFromString("state")) else {
        logger.log("SimDisplay \(descriptor) does not have a state, cannot determine if it is the main display")
        continue
      }
      guard let descriptorState = descriptor.perform(NSSelectorFromString("state"))?.takeUnretainedValue() as? SimDisplayDescriptorState else {
        logger.log("SimDisplay \(descriptor) state is not a SimDisplayDescriptorState")
        continue
      }
      let displayClass = descriptorState.displayClass
      if displayClass == 0 {
        return SimDisplayRenderableSurface(surface: renderable, logger: logger)
      }
      if fallback == nil {
        logger.log("SimDisplay Class '\(displayClass)' is not the main display '0'; holding as fallback (e.g. tvOS TVOut)")
        fallback = renderable
      }
    }
    if let fallback {
      return SimDisplayRenderableSurface(surface: fallback, logger: logger)
    }
    throw FBSimulatorError.describe("Could not find the Main Screen Surface for Clients \(FBCollectionInformation.oneLineDescription(from: ports)) in \(ioClient)").build()
  }
}
