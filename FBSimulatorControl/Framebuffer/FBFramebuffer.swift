/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation
@preconcurrency import IOSurface

// The FBSimulatorVideoStreamFramePusher protocol lives in FBSimulatorVideoStream.swift as a plain
// (non-@objc) Swift protocol; the pushers are only constructed and used from Swift.

/// Counters for framebuffer surface-change and frame-rendered callbacks, sampled for periodic
/// logging. There is no rect geometry: the underlying CoreSimulator callback is a per-frame change
/// signal only (see `FBFramebufferSurface`), so a frame-rendered callback carries no dimensions.
public struct FBFramebufferStats {
  public var frameRenderedCount: UInt = 0
  public var ioSurfaceChangeCount: UInt = 0

  public init() {}
}

/// Errors surfaced by `FBFramebuffer`.
public enum FBFramebufferError: Error, LocalizedError {
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
public enum FBFramebufferEvent: Sendable {
  /// The display's backing IOSurface changed (nil when the display has no surface).
  case surfaceChanged(IOSurface?)
  /// A new frame was rendered into the current surface. A bare per-frame signal — modern
  /// CoreSimulator reports no changed-region geometry (see `FBFramebufferSurface`).
  case frameRendered
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

  /// Attach to the framebuffer, receiving events as an ordered `AsyncStream` on the returned
  /// attachment. The stream carries every event from the moment of attachment (events yielded before
  /// iteration begins are buffered, never dropped). The attachment owns the registration: `cancel()`,
  /// or releasing the handle, unregisters and finishes the stream.
  ///
  /// Consumers must keep per-event work O(1) and non-suspending — the stream is unbounded so that a
  /// surface swap can never be dropped; heavy per-frame work belongs on a decoupled cadence, not in
  /// the event loop.
  public func attach() throws -> FBFramebufferAttachment {
    try register()
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

  /// Register with the display surface, producing an attachment whose event stream is fed directly
  /// from the surface callbacks. Events are yielded synchronously inside the callback (no thread
  /// hop) so the stream preserves the exact order the surface reported, across both event kinds.
  private func register() throws -> FBFramebufferAttachment {
    let token = UUID()
    let immediateSurface = surface.immediatelyAvailableSurface()

    let (events, continuation) = AsyncStream.makeStream(of: FBFramebufferEvent.self, bufferingPolicy: .unbounded)

    try surface.registerCallbacks(
      token: token,
      ioSurfaceChanged: { [statsRecorder] surface in
        statsRecorder.recordIOSurfaceChange(surface: surface)
        continuation.yield(.surfaceChanged(surface))
      },
      frameRendered: { [statsRecorder] in
        statsRecorder.recordFrameRendered()
        continuation.yield(.frameRendered)
      })

    return FBFramebufferAttachment(
      framebuffer: self,
      token: token,
      initialSurface: immediateSurface,
      events: events,
      continuation: continuation)
  }
}

/// The handle returned by `FBFramebuffer.attach`. Owns a single registration: cancelling (or
/// releasing) the handle unregisters from the display surface and finishes `events`.
public final class FBFramebufferAttachment: @unchecked Sendable {

  /// The surface available at attach time, if the framebuffer could vend one synchronously.
  public let initialSurface: IOSurface?

  /// Every framebuffer event since attachment, in the order the display surface reported them.
  /// Buffered without loss until iterated; finished by `cancel()`.
  public let events: AsyncStream<FBFramebufferEvent>

  private let token: UUID
  private weak var framebuffer: FBFramebuffer?
  private let continuation: AsyncStream<FBFramebufferEvent>.Continuation
  private let lock = NSLock()
  private var isCancelled = false

  init(
    framebuffer: FBFramebuffer,
    token: UUID,
    initialSurface: IOSurface?,
    events: AsyncStream<FBFramebufferEvent>,
    continuation: AsyncStream<FBFramebufferEvent>.Continuation
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

// MARK: - Legacy queue-based consumer (compatibility shim)

// The queue-based consumer contract, retained while consumers migrate to reading the event stream
// directly. It is defined entirely in terms of the public stream API — an extension with no extra
// state on the stream-based core — and is removed once the last consumer migrates.

public protocol FBFramebufferConsumer: AnyObject {
  func didChange(_ surface: IOSurface?)

  /// A new frame was rendered into the current surface. This is a bare per-frame signal — modern
  /// CoreSimulator reports no changed-region geometry (see `FBFramebufferSurface`) — and is what
  /// variable-frame-rate consumers use as their push stimulus.
  func didRenderFrame()
}

extension FBFramebuffer {

  /// Attach a consumer, delivering surface-change and frame-rendered callbacks on `queue`. The
  /// returned `FBFramebufferAttachment` owns the registration: call `cancel()`, or release it, to detach.
  ///
  /// A task drains the attachment's `events` and forwards each to the consumer on `queue`, in
  /// order. Because that task is the stream's single reader, a legacy attachment's `events` must
  /// not also be iterated by the caller. The task ends when the attachment cancels (finishing the
  /// stream) or the consumer deallocates.
  public func attach(_ consumer: any FBFramebufferConsumer, on queue: DispatchQueue) throws -> FBFramebufferAttachment {
    let attachment = try attach()
    // Capture the stream value, not the attachment: the forwarding task must not extend the
    // attachment's lifetime, so releasing the handle still detaches (deinit → cancel → the stream
    // finishes, ending this task).
    let events = attachment.events
    // The task holds the consumer weakly, upgrading per event: the in-tree consumers own their
    // attachment, so a strong capture here would keep a dropped consumer alive until a stream
    // finish that its own deinit is responsible for triggering — a cycle that leaks both.
    let consumerBox = WeakFramebufferConsumerBox(consumer)
    Task {
      for await event in events {
        guard let upgraded = consumerBox.consumer else { break }
        // SAFETY: the consumer is only ever messaged inside the `queue.async` block below, so every
        // delivery is serialized onto the consumer's own queue and the capture is never touched
        // concurrently. `FBFramebufferConsumer` is a reference type and cannot be made `Sendable`.
        // patternlint-disable-next-line swift-nonisolated-unsafe
        nonisolated(unsafe) let consumer = upgraded
        queue.async {
          switch event {
          case let .surfaceChanged(surface):
            consumer.didChange(surface)
          case .frameRendered:
            consumer.didRenderFrame()
          }
        }
      }
    }
    return attachment
  }
}

/// Weakly boxes the legacy consumer for the shim's forwarding task. `@unchecked Sendable`: the
/// weak reference is written once at init and only read (upgraded) from the forwarding task.
private final class WeakFramebufferConsumerBox: @unchecked Sendable {
  private(set) weak var consumer: (any FBFramebufferConsumer)?

  init(_ consumer: any FBFramebufferConsumer) {
    self.consumer = consumer
  }
}
