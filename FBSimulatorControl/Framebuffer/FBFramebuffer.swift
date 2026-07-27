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

@objc public protocol FBFramebufferConsumer: NSObjectProtocol {
  @objc(didChangeIOSurface:)
  func didChange(_ surface: IOSurface?)

  func didReceiveDamageRect()
}

@objc(FBFramebuffer)
public final class FBFramebuffer: NSObject, @unchecked Sendable {

  // MARK: - Properties

  private let consumers: NSMapTable<AnyObject, NSUUID>
  private let logger: any FBControlCoreLogger
  private let surface: any FBFramebufferSurface

  // `statsLock` guards `stats`, `lastLoggedStats`, and `statsTimer`: the IOSurface and damage
  // callbacks below fire on arbitrary private-framework threads, while `currentStats()` and
  // `statsStartTime` are read from a consumer's queue.
  private let statsLock = NSLock()
  private var stats: FBFramebufferStats
  private var lastLoggedStats: FBFramebufferStats
  private var statsTimer: FBPeriodicStatsTimer

  // MARK: - Initializers

  @objc(mainScreenSurfaceForSimulator:logger:error:)
  public class func mainScreenSurface(for simulator: FBSimulator, logger: any FBControlCoreLogger) throws -> FBFramebuffer {
    let surface = try FBFramebufferSurfaceLocator.mainDisplaySurface(for: simulator, logger: logger)
    return FBFramebuffer(surface: surface, logger: logger)
  }

  init(surface: any FBFramebufferSurface, logger: any FBControlCoreLogger) {
    self.consumers = NSMapTable(keyOptions: .weakMemory, valueOptions: .copyIn)
    self.logger = logger
    self.surface = surface
    self.stats = FBFramebufferStats()
    self.lastLoggedStats = FBFramebufferStats()
    self.statsTimer = FBPeriodicStatsTimer(interval: 5.0)
    super.init()
  }

  // MARK: - Public Methods

  @objc(attachConsumer:onQueue:)
  public func attach(_ consumer: any FBFramebufferConsumer, on queue: DispatchQueue) -> IOSurface? {
    // Don't attach the same consumer twice
    assert(!isConsumerAttached(consumer), "Cannot re-attach the same consumer \(consumer)")
    let consumerUUID = NSUUID()

    // Attempt to return the surface synchronously (if supported).
    let immediateSurface = surface.immediatelyAvailableSurface()

    // Register the consumer.
    consumers.setObject(consumerUUID, forKey: consumer as AnyObject)
    registerConsumer(consumer, uuid: consumerUUID, queue: queue)

    return immediateSurface
  }

  @objc(detachConsumer:)
  public func detach(_ consumer: any FBFramebufferConsumer) {
    guard let uuid = consumers.object(forKey: consumer as AnyObject) else {
      return
    }
    consumers.removeObject(forKey: consumer as AnyObject)
    unregisterConsumer(uuid: uuid)
  }

  @objc(isConsumerAttached:)
  public func isConsumerAttached(_ consumer: any FBFramebufferConsumer) -> Bool {
    let enumerator = consumers.keyEnumerator()
    while let existingConsumer = enumerator.nextObject() {
      if existingConsumer as AnyObject === consumer as AnyObject {
        return true
      }
    }
    return false
  }

  // MARK: - Stats

  public func currentStats() -> FBFramebufferStats {
    statsLock.lock()
    defer { statsLock.unlock() }
    return stats
  }

  @objc public var statsStartTime: CFTimeInterval {
    statsLock.lock()
    defer { statsLock.unlock() }
    return statsTimer.firstTickTime
  }

  // MARK: - Private

  private func registerConsumer(_ consumer: any FBFramebufferConsumer, uuid: NSUUID, queue: DispatchQueue) {
    // SAFETY: the consumer is only ever messaged inside the `queue.async` blocks below, so every
    // delivery is serialized onto the consumer's own queue and the capture is never touched
    // concurrently. `FBFramebufferConsumer` is a reference type and cannot be made `Sendable`.
    // patternlint-disable-next-line swift-nonisolated-unsafe
    nonisolated(unsafe) let consumerRef = consumer

    let ioSurfaceChanged: (IOSurface?) -> Void = { [weak self] surfaceArg in
      guard let self else { return }
      self.statsLock.lock()
      self.stats.ioSurfaceChangeCount += 1
      let isFirstChange = self.stats.ioSurfaceChangeCount == 1
      self.statsLock.unlock()
      if isFirstChange {
        self.logger.info().log("First IOSurface change callback, surface=\(String(describing: surfaceArg))")
      }
      queue.async {
        consumerRef.didChange(surfaceArg)
      }
    }

    let damageReceived: (FBFramebufferDamage) -> Void = { [weak self] damage in
      guard let self else { return }
      self.statsLock.lock()
      self.stats.damageCallbackCount += 1
      self.stats.damageRectCount += UInt(damage.rects.count)
      if damage.rects.isEmpty {
        self.stats.emptyDamageCallbackCount += 1
      }
      self.statsLock.unlock()
      self.logStatsIfNeeded()
      queue.async {
        consumerRef.didReceiveDamageRect()
      }
    }

    _ = try? surface.registerCallbacks(token: uuid as UUID, ioSurfaceChanged: ioSurfaceChanged, damageReceived: damageReceived)
  }

  private func logStatsIfNeeded() {
    statsLock.lock()
    switch statsTimer.tick() {
    case .started:
      statsLock.unlock()
      logger.info().log("First damage callback received")
    case .pending:
      statsLock.unlock()
    case let .elapsed(intervalDuration, totalElapsed):
      let current = stats
      let last = lastLoggedStats
      lastLoggedStats = current
      statsLock.unlock()

      let intervalCallbacks = current.damageCallbackCount - last.damageCallbackCount
      let intervalRects = current.damageRectCount - last.damageRectCount
      let intervalEmpty = current.emptyDamageCallbackCount - last.emptyDamageCallbackCount
      let intervalIOSurface = current.ioSurfaceChangeCount - last.ioSurfaceChangeCount

      let intervalRate = intervalDuration > 0 ? Double(intervalCallbacks) / intervalDuration : 0
      let totalRate = totalElapsed > 0 ? Double(current.damageCallbackCount) / totalElapsed : 0

      logger.info().log(
        String(
          format: "Framebuffer stats (interval): %lu damage callbacks in %.1fs (%.1f/s, %lu rects, %lu empty) — %lu IOSurface changes",
          intervalCallbacks, intervalDuration, intervalRate, intervalRects, intervalEmpty, intervalIOSurface))
      logger.info().log(
        String(
          format: "Framebuffer stats (total): %lu damage callbacks in %.1fs (%.1f/s, %lu rects, %lu empty) — %lu IOSurface changes",
          current.damageCallbackCount, totalElapsed, totalRate, current.damageRectCount, current.emptyDamageCallbackCount, current.ioSurfaceChangeCount))
    }
  }

  private func unregisterConsumer(uuid: NSUUID) {
    surface.unregisterCallbacks(token: uuid as UUID)
  }
}
