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

/// The seam between `FBFramebuffer` and the private CoreSimulator display surface. Expressed purely
/// in public/standard types so the private `@_implementationOnly` renderable protocols never leak
/// into `FBFramebuffer`'s logic and a fake can be substituted in tests.
protocol FBFramebufferSurface: AnyObject {
  /// The surface available right now, if the underlying renderable can vend one synchronously.
  func immediatelyAvailableSurface() -> IOSurface?

  /// Register per-consumer callbacks keyed by `token`. `frameRendered` fires once per presented
  /// frame (a bare change signal — see the registration note below). Throws if the surface-change
  /// callback could not be installed on either the plural or singular renderable entry point.
  func registerCallbacks(
    token: UUID,
    ioSurfaceChanged: @escaping (IOSurface?) -> Void,
    frameRendered: @escaping () -> Void
  ) throws

  /// Best-effort removal of the callbacks registered under `token`.
  func unregisterCallbacks(token: UUID)
}

/// The production `FBFramebufferSurface`, wrapping the private CoreSimulator renderable. This is the
/// single place that touches the `@_implementationOnly` renderable protocols and `FBObjCExceptionGuard`;
/// it is `fileprivate` so those private types never appear in any interface reachable via
/// `@testable import`.
private final class SimDisplayRenderableSurface: FBFramebufferSurface {
  private let surface: any SimDisplayIOSurfaceRenderable & SimDisplayRenderable
  private let logger: any FBControlCoreLogger
  /// Dedicated serial queue the new-style `SimScreen` callbacks are delivered on, keeping frame and
  /// surface-changed events ordered. The render server delivers each callback with `clientQueue.sync`
  /// — it blocks its own notify thread until the callback returns, donating ~`.userInteractive` QoS —
  /// so this queue is `.userInteractive` (matches the donated QoS, avoiding priority-inversion churn)
  /// and is used only for these callbacks so the `sync` never waits behind unrelated work. The
  /// callbacks must stay minimal and non-suspending: anything heavy back-pressures the server's frame
  /// notifications for this display. Unused by the old-style path (which delivers on the framework's
  /// own threads).
  private let callbackQueue = DispatchQueue(label: "com.facebook.FBSimulatorControl.framebuffer-callbacks", qos: .userInteractive)

  init(surface: any SimDisplayIOSurfaceRenderable & SimDisplayRenderable, logger: any FBControlCoreLogger) {
    self.surface = surface
    self.logger = logger
  }

  func immediatelyAvailableSurface() -> IOSurface? {
    guardedValue { self.surface.framebufferSurface } ?? guardedValue { self.surface.ioSurface }
  }

  func registerCallbacks(
    token: UUID,
    ioSurfaceChanged: @escaping (IOSurface?) -> Void,
    frameRendered: @escaping () -> Void
  ) throws {
    // Prefer the new-style `SimScreen` grouped callbacks — `frameCallback` is a real per-present
    // tick and `surfacesChangedCallback` supersedes the two legacy IOSurface variants. Fall back to
    // the old-style callbacks where the descriptor does not vend `SimScreen` (older CoreSimulator).
    if registerScreenCallbacks(token: token, ioSurfaceChanged: ioSurfaceChanged, frameRendered: frameRendered) {
      return
    }
    try registerLegacyCallbacks(token: token, ioSurfaceChanged: ioSurfaceChanged, frameRendered: frameRendered)
    logger.info().log("FBFramebuffer: registered old-style framebuffer callbacks")
  }

  /// New-style path: register the grouped `SimScreen` callbacks. Returns `true` if they were
  /// installed, `false` if the descriptor does not vend `SimScreen` or the registration raised (in
  /// which case the caller falls back to the old-style callbacks).
  private func registerScreenCallbacks(
    token: UUID,
    ioSurfaceChanged: @escaping (IOSurface?) -> Void,
    frameRendered: @escaping () -> Void
  ) -> Bool {
    guard let screen = surface as? (any SimScreen) else { return false }
    let error = guardedCall {
      screen.registerScreenCallbacks(
        uuid: token,
        callbackQueue: self.callbackQueue,
        frameCallback: { frameRendered() },
        // Arg 0 is the primary `framebufferSurface` to render; arg 1 is the notch/corner-masked
        // variant we ignore (see SimScreen-Protocol.h / SimDisplayIOSurfaceRenderable-Protocol.h).
        surfacesChangedCallback: { framebuffer, _ in ioSurfaceChanged(framebuffer as? IOSurface) },
        propertiesChangedCallback: { _ in })
    }
    if let error {
      // Roll back in case the raise happened after the remote side installed the callbacks —
      // otherwise the old-style fallback would double-register under the same token.
      _ = guardedCall { screen.unregisterScreenCallbacks(uuid: token) }
      logger.log("FBFramebuffer: new-style SimScreen registration failed (\(error)); using old-style callbacks")
      return false
    }
    logger.info().log("FBFramebuffer: registered new-style SimScreen frame callbacks")
    return true
  }

  /// The legacy registration: the plural/singular IOSurface-change callbacks plus the
  /// `damageRectanglesCallback` (which on modern CoreSimulator is a bare per-frame signal, not
  /// geometry — the render server is a whole-frame compositor that invokes it with an empty array).
  private func registerLegacyCallbacks(
    token: UUID,
    ioSurfaceChanged: @escaping (IOSurface?) -> Void,
    frameRendered: @escaping () -> Void
  ) throws {
    // The underlying ROCKRemoteProxy may implement only the plural or only the singular surface
    // callback (see SimDisplayIOSurfaceRenderable-Protocol.h). Attempt both — each is guarded
    // independently so a raise from one does not skip the other — and require at least one to install.
    let ioSurfaceBlock: (Any?) -> Void = { ioSurfaceChanged($0 as? IOSurface) }
    let pluralError = guardedCall { self.surface.registerCallback(with: token, ioSurfacesChangeCallback: ioSurfaceBlock) }
    let singularError = guardedCall { self.surface.registerCallback(with: token, ioSurfaceChangeCallback: ioSurfaceBlock) }
    guard pluralError == nil || singularError == nil else {
      throw FBFramebufferError.surfaceCallbackRegistrationFailed(underlying: pluralError)
    }

    let frameRenderedBlock: ([NSValue]?) -> Void = { _ in frameRendered() }
    if let error = guardedCall({ self.surface.registerCallback(with: token, damageRectanglesCallback: frameRenderedBlock) }) {
      // Roll back the IOSurface callback so a failed registration leaves nothing behind.
      unregisterCallbacks(token: token)
      throw FBFramebufferError.surfaceCallbackRegistrationFailed(underlying: error)
    }
  }

  func unregisterCallbacks(token: UUID) {
    // Best-effort across both registration styles; a token registered one way is a no-op for the
    // other's unregister.
    if let screen = surface as? (any SimScreen) {
      _ = guardedCall { screen.unregisterScreenCallbacks(uuid: token) }
    }
    _ = guardedCall { self.surface.unregisterIOSurfacesChangeCallback(with: token) }
    _ = guardedCall { self.surface.unregisterIOSurfaceChangeCallback(with: token) }
    _ = guardedCall { self.surface.unregisterDamageRectanglesCallback(with: token) }
  }

  // MARK: - Guarded proxy access
  //
  // Every call into the private renderable can raise an ObjC exception through the ROCK proxy, so
  // each is wrapped in `FBObjCExceptionGuard`. These two helpers are the single place that does the
  // wrapping: `guardedValue` for reads (nil on raise or type mismatch) and `guardedCall` for actions
  // (the raised error, or nil on success, so a caller can fall back or surface the failure).

  /// Read an untyped (`id`) value from the proxy, cast to the expected type. nil if the proxy raises
  /// or the value is not a `T` — folding the `as?` in keeps every proxy read a single expression.
  private func guardedValue<T>(_ body: @escaping () -> Any?) -> T? {
    guard let value = try? FBObjCExceptionGuard.guarded(body) else { return nil }
    return value as? T
  }

  private func guardedCall(_ body: @escaping () -> Void) -> Error? {
    do {
      try FBObjCExceptionGuard.guarded(body)
      return nil
    } catch {
      return error
    }
  }
}

/// Locates the simulator's main-display surface among its IO ports and wraps it in a production
/// `FBFramebufferSurface`. Kept separate from `FBFramebuffer` so that discovery, adaptation, and
/// consumer fan-out are distinct concerns.
enum FBFramebufferSurfaceLocator {
  static func mainDisplaySurface(for simulator: FBSimulator, logger: any FBControlCoreLogger) throws -> any FBFramebufferSurface {
    guard let ioClient = simulator.device.io else {
      throw FBFramebufferError.mainScreenSurfaceNotFound(description: "No IO client available on \(simulator.device)")
    }
    guard let ports = ioClient.ioPorts() else {
      throw FBFramebufferError.mainScreenSurfaceNotFound(description: "No IO ports available on \(ioClient)")
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
    throw FBFramebufferError.mainScreenSurfaceNotFound(
      description: "Could not find the Main Screen Surface for Clients \(FBCollectionInformation.oneLineDescription(from: ports)) in \(ioClient)")
  }
}
