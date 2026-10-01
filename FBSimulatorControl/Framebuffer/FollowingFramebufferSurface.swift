/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation
import IOSurface
import os

/// A surface that moves to each display that becomes active, so its consumers keep rendering the display
/// in use. A move re-registers every consumer on the new display's screen and reports that screen's
/// surface, which a consumer handles as it does any other surface change.
// SAFETY: The current screen, the registrations and the follow task are guarded by the lock.
// patternlint-disable-next-line unchecked-sendable
final class FollowingFramebufferSurface: FramebufferSurface, @unchecked Sendable {

  typealias Locate = @Sendable (_ uniqueID: String) async throws -> any FramebufferSurface

  private struct Registration {
    let ioSurfaceChanged: (IOSurface?) -> Void
    let frameRendered: () -> Void
  }

  /// A screen being followed. Its gate closes when the screen is left, so a callback it delivers
  /// afterwards cannot report its surface over the new screen's.
  private struct Screen {
    let uniqueID: String
    let surface: any FramebufferSurface
    let gate = OSAllocatedUnfairLock(initialState: true)
  }

  private let lock = NSLock()
  private var screen: Screen
  private var registrations: [UUID: Registration] = [:]
  private var follow: Task<Void, Never>?
  private let updates: @Sendable () -> AsyncStream<SimulatorDisplay>
  private let locate: Locate
  private let logger: any ControlCoreLogger

  /// `updates` starts with the first registration and stops with the last one.
  init(
    displayUniqueID: String,
    surface: any FramebufferSurface,
    updates: @escaping @Sendable () -> AsyncStream<SimulatorDisplay>,
    locate: @escaping Locate,
    logger: any ControlCoreLogger
  ) {
    self.screen = Screen(uniqueID: displayUniqueID, surface: surface)
    self.updates = updates
    self.locate = locate
    self.logger = logger
  }

  deinit {
    follow?.cancel()
  }

  func immediatelyAvailableSurface() -> IOSurface? {
    lock.withLock { screen.surface.immediatelyAvailableSurface() }
  }

  func registerCallbacks(
    token: UUID,
    ioSurfaceChanged: @escaping (IOSurface?) -> Void,
    frameRendered: @escaping () -> Void
  ) throws {
    let registration = Registration(ioSurfaceChanged: ioSurfaceChanged, frameRendered: frameRendered)
    try lock.withLock {
      try Self.register(registration, token: token, on: screen)
      registrations[token] = registration
      if follow == nil {
        follow = Task { [weak self, updates] in await self?.follow(updates()) }
      }
    }
  }

  func unregisterCallbacks(token: UUID) {
    lock.withLock {
      screen.surface.unregisterCallbacks(token: token)
      registrations[token] = nil
      if registrations.isEmpty {
        follow?.cancel()
        follow = nil
      }
    }
  }

  private static func register(_ registration: Registration, token: UUID, on screen: Screen) throws {
    let gate = screen.gate
    try screen.surface.registerCallbacks(
      token: token,
      ioSurfaceChanged: { surface in
        if gate.withLock({ $0 }) { registration.ioSurfaceChanged(surface) }
      },
      frameRendered: {
        if gate.withLock({ $0 }) { registration.frameRendered() }
      })
  }

  /// A display that cannot be captured leaves the current one in place until a later update moves it.
  private func follow(_ updates: AsyncStream<SimulatorDisplay>) async {
    for await display in updates {
      let current = lock.withLock { screen.uniqueID }
      guard display.uniqueID != current else { continue }
      do {
        let surface = try await locate(display.uniqueID)
        try Task.checkCancellation()
        try move(to: Screen(uniqueID: display.uniqueID, surface: surface))
        logger.log("Framebuffer: following display \(display.uniqueID), previously \(current)")
      } catch is CancellationError {
        return
      } catch {
        logger.log("Framebuffer: staying on display \(current), as display \(display.uniqueID) could not be captured: \(error)")
      }
    }
  }

  /// Consumers learn of the new surface once the lock is released, so one may re-enter this surface.
  private func move(to next: Screen) throws {
    let (surface, consumers) = try lock.withLock {
      var registered: [UUID] = []
      do {
        for (token, registration) in registrations {
          try Self.register(registration, token: token, on: next)
          registered.append(token)
        }
      } catch {
        registered.forEach { next.surface.unregisterCallbacks(token: $0) }
        throw error
      }
      screen.gate.withLock { $0 = false }
      registrations.keys.forEach { screen.surface.unregisterCallbacks(token: $0) }
      screen = next
      return (next.surface.immediatelyAvailableSurface(), Array(registrations.values))
    }
    consumers.forEach { $0.ioSurfaceChanged(surface) }
  }
}
