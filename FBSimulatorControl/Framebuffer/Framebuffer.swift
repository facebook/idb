/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation
@preconcurrency import IOSurface

/// Counters for framebuffer surface-change and frame-rendered callbacks, sampled for periodic
/// logging. There is no rect geometry: the underlying CoreSimulator callback is a per-frame change
/// signal only (see `FramebufferSurface`), so a frame-rendered callback carries no dimensions.
public struct FBFramebufferStats: Sendable {
  public var frameRenderedCount: UInt = 0
  var ioSurfaceChangeCount: UInt = 0

  public init() {}
}

/// Errors surfaced by `FBFramebuffer`.
public enum FramebufferError: Error, LocalizedError {
  /// No renderable main-display surface could be located for the simulator.
  case mainScreenSurfaceNotFound(description: String)
  /// The surface-change or frame-rendered callbacks could not be registered on the display surface.
  case surfaceCallbackRegistrationFailed(underlying: Error?)

  public var errorDescription: String? {
    switch self {
    case let .mainScreenSurfaceNotFound(description):
      return description
    case let .surfaceCallbackRegistrationFailed(underlying):
      if let underlying {
        return "Failed to register framebuffer surface callbacks: \(underlying)"
      }
      return "Failed to register framebuffer surface callbacks"
    }
  }
}

/// A single framebuffer occurrence, delivered in the order the display surface reported it. One
/// stream carries both kinds so that a surface swap can never be observed out of order with the
/// frame-rendered events around it.
public enum FramebufferEvent: Sendable {
  /// The display's backing IOSurface changed (nil when the display has no surface). Delivered only
  /// when the surface differs, by IOSurface ID, from the one the attachment last knew: the display
  /// re-reports its current surface right after registration, and the legacy path can report one
  /// swap through both the plural and singular callbacks. Neither reaches consumers.
  case surfaceChanged(IOSurface?)
  /// A new frame was rendered into the current surface. A bare per-frame signal — modern
  /// CoreSimulator reports no changed-region geometry (see `FramebufferSurface`).
  case frameRendered
}

/// Tracks the surface an attachment last reported and refuses re-reports of it. Compared by
/// IOSurface ID rather than object identity because the proxy may vend a distinct wrapper object for
/// the same underlying surface.
private final class SurfaceChangeFilter: @unchecked Sendable {
  private let lock = NSLock()
  private var currentSurfaceID: IOSurfaceID?

  init(initialSurface: IOSurface?) {
    currentSurfaceID = initialSurface.map { IOSurfaceGetID($0) }
  }

  /// True if `surface` differs from the last admitted one, recording it as current when it does.
  func admit(_ surface: IOSurface?) -> Bool {
    let surfaceID = surface.map { IOSurfaceGetID($0) }
    lock.lock()
    defer { lock.unlock() }
    if surfaceID == currentSurfaceID {
      return false
    }
    currentSurfaceID = surfaceID
    return true
  }
}

public final class FBFramebuffer: @unchecked Sendable {

  private let surface: any FramebufferSurface
  private let statsRecorder: FramebufferStatsRecorder
  private let logger: any FBControlCoreLogger

  public class func mainScreenSurface(for simulator: FBSimulator, logger: any FBControlCoreLogger) throws -> FBFramebuffer {
    let surface = try FramebufferSurfaceLocator.mainDisplaySurface(for: simulator, logger: logger)
    return FBFramebuffer(surface: surface, logger: logger)
  }

  init(surface: any FramebufferSurface, logger: any FBControlCoreLogger) {
    self.surface = surface
    self.statsRecorder = FramebufferStatsRecorder(logger: logger)
    self.logger = logger
  }

  /// Attach to the framebuffer, receiving events as an ordered `AsyncStream` on the returned
  /// attachment. The stream carries every event from the moment of attachment (events yielded before
  /// iteration begins are buffered, never dropped). The attachment owns the registration: `cancel()`,
  /// or releasing the handle, unregisters and finishes the stream.
  ///
  /// Consumers must keep per-event work O(1) and non-suspending — the stream is unbounded so that a
  /// surface swap can never be dropped; heavy per-frame work belongs on a decoupled cadence, not in
  /// the event loop.
  public func attach() throws -> FramebufferAttachment {
    try register()
  }

  fileprivate func detach(token: UUID) {
    surface.unregisterCallbacks(token: token)
  }

  // MARK: - Stats

  public func currentStats() -> FBFramebufferStats {
    statsRecorder.snapshot()
  }

  var statsStartTime: CFTimeInterval {
    statsRecorder.startTime
  }

  /// Register with the display surface, producing an attachment whose event stream is fed directly
  /// from the surface callbacks. Events are yielded synchronously inside the callback (no thread
  /// hop) so the stream preserves the exact order the surface reported, across both event kinds.
  /// Surface re-reports are dropped here (see `FramebufferEvent.surfaceChanged`), seeded with the
  /// attach-time surface so its registration echo is the first thing filtered.
  private func register() throws -> FramebufferAttachment {
    let token = UUID()
    let immediateSurface = surface.immediatelyAvailableSurface()
    let filter = SurfaceChangeFilter(initialSurface: immediateSurface)

    let (events, continuation) = AsyncStream.makeStream(of: FramebufferEvent.self, bufferingPolicy: .unbounded)

    try surface.registerCallbacks(
      token: token,
      ioSurfaceChanged: { [statsRecorder, logger] surface in
        statsRecorder.recordIOSurfaceChange(surface: surface)
        guard filter.admit(surface) else {
          logger.info().log("FBFramebuffer: ignoring surface change for the already-current surface \(surface.map { String(IOSurfaceGetID($0)) } ?? "nil")")
          return
        }
        continuation.yield(.surfaceChanged(surface))
      },
      frameRendered: { [statsRecorder] in
        statsRecorder.recordFrameRendered()
        continuation.yield(.frameRendered)
      })

    return FramebufferAttachment(
      framebuffer: self,
      token: token,
      initialSurface: immediateSurface,
      events: events,
      continuation: continuation)
  }
}

/// The handle returned by `FBFramebuffer.attach`. Owns a single registration: cancelling (or
/// releasing) the handle unregisters from the display surface and finishes `events`.
public final class FramebufferAttachment: @unchecked Sendable {

  /// The surface available at attach time, if the framebuffer could vend one synchronously.
  public let initialSurface: IOSurface?

  /// Every framebuffer event since attachment, in the order the display surface reported them.
  /// Buffered without loss until iterated; finished by `cancel()`.
  public let events: AsyncStream<FramebufferEvent>

  private let token: UUID
  private weak var framebuffer: FBFramebuffer?
  private let continuation: AsyncStream<FramebufferEvent>.Continuation
  private let lock = NSLock()
  private var isCancelled = false

  init(
    framebuffer: FBFramebuffer,
    token: UUID,
    initialSurface: IOSurface?,
    events: AsyncStream<FramebufferEvent>,
    continuation: AsyncStream<FramebufferEvent>.Continuation
  ) {
    self.framebuffer = framebuffer
    self.token = token
    self.initialSurface = initialSurface
    self.events = events
    self.continuation = continuation
  }

  /// Detach from the framebuffer and finish the event stream. Idempotent.
  public func cancel() {
    lock.lock()
    if isCancelled {
      lock.unlock()
      return
    }
    isCancelled = true
    lock.unlock()
    framebuffer?.detach(token: token)
    continuation.finish()
  }

  deinit {
    cancel()
  }
}
