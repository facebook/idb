/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation
import IOSurface

// The FBSimulatorVideoStreamFramePusher protocol lives in FBSimulatorVideoStream.swift as a plain
// (non-@objc) Swift protocol; the pushers are only constructed and used from Swift.

/// Counters for framebuffer surface-change and damage callbacks, sampled for periodic logging.
public struct FBFramebufferStats {
  public var damageCallbackCount: UInt = 0
  public var damageRectCount: UInt = 0
  public var emptyDamageCallbackCount: UInt = 0
  public var ioSurfaceChangeCount: UInt = 0

  public init() {}
}

public protocol FBFramebufferConsumer: AnyObject {
  func didChange(_ surface: IOSurface?)

  func didReceiveDamageRect()
}

public final class FBFramebuffer: @unchecked Sendable {

  // MARK: - Properties

  private let surface: any FBFramebufferSurface
  private let statsRecorder: FBFramebufferStatsRecorder

  // MARK: - Initializers

  public class func mainScreenSurface(for simulator: FBSimulator, logger: any FBControlCoreLogger) throws -> FBFramebuffer {
    let surface = try FBFramebufferSurfaceLocator.mainDisplaySurface(for: simulator, logger: logger)
    return FBFramebuffer(surface: surface, logger: logger)
  }

  init(surface: any FBFramebufferSurface, logger: any FBControlCoreLogger) {
    self.surface = surface
    self.statsRecorder = FBFramebufferStatsRecorder(logger: logger)
  }

  // MARK: - Public Methods

  /// Attach a consumer, delivering surface-change and damage callbacks on `queue`. The returned
  /// `FBFramebufferAttachment` owns the registration: call `cancel()`, or release it, to detach.
  public func attach(_ consumer: any FBFramebufferConsumer, on queue: DispatchQueue) -> FBFramebufferAttachment {
    let token = UUID()
    let immediateSurface = surface.immediatelyAvailableSurface()
    registerConsumer(consumer, token: token, queue: queue)
    return FBFramebufferAttachment(framebuffer: self, token: token, initialSurface: immediateSurface)
  }

  fileprivate func detach(token: UUID) {
    surface.unregisterCallbacks(token: token)
  }

  // MARK: - Stats

  public func currentStats() -> FBFramebufferStats {
    statsRecorder.snapshot()
  }

  public var statsStartTime: CFTimeInterval {
    statsRecorder.startTime
  }

  // MARK: - Private

  private func registerConsumer(_ consumer: any FBFramebufferConsumer, token: UUID, queue: DispatchQueue) {
    // SAFETY: the consumer is only ever messaged inside the `queue.async` blocks below, so every
    // delivery is serialized onto the consumer's own queue and the capture is never touched
    // concurrently. `FBFramebufferConsumer` is a reference type and cannot be made `Sendable`.
    // patternlint-disable-next-line swift-nonisolated-unsafe
    nonisolated(unsafe) let consumerRef = consumer

    let ioSurfaceChanged: (IOSurface?) -> Void = { [weak self] surfaceArg in
      guard let self else { return }
      self.statsRecorder.recordIOSurfaceChange(surface: surfaceArg)
      queue.async {
        consumerRef.didChange(surfaceArg)
      }
    }

    let damageReceived: (FBFramebufferDamage) -> Void = { [weak self] damage in
      guard let self else { return }
      self.statsRecorder.recordDamage(damage)
      queue.async {
        consumerRef.didReceiveDamageRect()
      }
    }

    _ = try? surface.registerCallbacks(token: token, ioSurfaceChanged: ioSurfaceChanged, damageReceived: damageReceived)
  }
}

/// The handle returned by `FBFramebuffer.attach`. Owns a single consumer registration: the consumer
/// is detached when `cancel()` is called or when this handle is released.
public final class FBFramebufferAttachment {

  /// The surface available at attach time, if the framebuffer could vend one synchronously.
  public let initialSurface: IOSurface?

  private let token: UUID
  private weak var framebuffer: FBFramebuffer?
  private let lock = NSLock()
  private var isCancelled = false

  init(framebuffer: FBFramebuffer, token: UUID, initialSurface: IOSurface?) {
    self.framebuffer = framebuffer
    self.token = token
    self.initialSurface = initialSurface
  }

  /// Detach the consumer. Idempotent.
  public func cancel() {
    lock.lock()
    if isCancelled {
      lock.unlock()
      return
    }
    isCancelled = true
    lock.unlock()
    framebuffer?.detach(token: token)
  }

  deinit {
    cancel()
  }
}
