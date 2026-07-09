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
// Fork addition: the reverse-engineered SimScreen / SimScreenAdapter protocols for
// Xcode 27's Swift-rewritten SimulatorKit live in the SimulatorKit private module.
@_implementationOnly @preconcurrency import SimulatorKit

// The FBSimulatorVideoStreamFramePusher protocol lives in FBSimulatorVideoStream.swift as a plain
// (non-@objc) Swift protocol; the pushers are only constructed and used from Swift.

@objc public protocol FBFramebufferConsumer: NSObjectProtocol {
  @objc(didChangeIOSurface:)
  func didChange(_ surface: IOSurface?)

  func didReceiveDamageRect()
}

@objc(FBFramebuffer)
public final class FBFramebuffer: NSObject, @unchecked Sendable {

  // MARK: - Properties

  // Fork addition: on Xcode 27+ displays are vended as SimScreens instead of the
  // legacy SimDisplayRenderable surfaces, so the framebuffer is backed by one of two
  // display representations.
  private enum Backing {
    /// Xcode <= 26: SimDisplayIOSurfaceRenderable & SimDisplayRenderable.
    case legacy(AnyObject)
    /// Xcode 27+: the Swift-rewritten SimulatorKit's SimScreen.
    case screen(any SimScreen)
  }

  private let consumers: NSMapTable<AnyObject, NSUUID>
  private let logger: any FBControlCoreLogger
  private let backing: Backing

  private var stats: FBFramebufferStats
  private var lastLoggedStats: FBFramebufferStats
  private var statsTimer: FBPeriodicStatsTimer

  // MARK: - Initializers

  @objc(mainScreenSurfaceForSimulator:logger:error:)
  public class func mainScreenSurface(for simulator: FBSimulator, logger: any FBControlCoreLogger) throws -> FBFramebuffer {
    let ioClient = simulator.device.io!
    let ports: [Any]? = ioClient.ioPorts()
    guard let ports else {
      throw FBSimulatorError.describe("No IO ports available on \(ioClient)").build()
    }
    // iOS exposes the main display as displayClass 0. tvOS renders only on the TVOut display (a
    // non-zero class), so prefer class 0 but fall back to the first renderable display rather than
    // throwing — otherwise screenshots and video are impossible on a target with no class-0 display.
    var fallbackSurface: AnyObject?
    for port in ports {
      guard let portInterface = port as? SimDeviceIOPortInterface else {
        continue
      }
      let descriptor = portInterface.descriptor as AnyObject

      // Fork addition — Xcode 27+: SimulatorKit was rewritten in Swift and the headless
      // IOSurface path moved to the SimScreenAdapter / SimScreen protocols. Prefer this
      // when the descriptor conforms (runtime feature-detection, no version sniffing).
      if let adapter = descriptor as? SimScreenAdapter {
        if let screen = defaultScreen(for: adapter, logger: logger) {
          return FBFramebuffer(backing: .screen(screen), logger: logger)
        }
        logger.log("SimScreenAdapter \(descriptor) did not vend a usable screen, continuing")
        continue
      }

      guard descriptor.conforms(to: SimDisplayRenderable.self),
        descriptor.conforms(to: SimDisplayIOSurfaceRenderable.self)
      else {
        continue
      }
      guard descriptor.responds(to: NSSelectorFromString("state")) else {
        logger.log("SimDisplay \(descriptor) does not have a state, cannot determine if it is the main display")
        continue
      }
      let descriptorState = descriptor.perform(NSSelectorFromString("state"))?.takeUnretainedValue() as! SimDisplayDescriptorState
      let displayClass = descriptorState.displayClass
      if displayClass == 0 {
        return FBFramebuffer(backing: .legacy(descriptor), logger: logger)
      }
      if fallbackSurface == nil {
        logger.log("SimDisplay Class '\(displayClass)' is not the main display '0'; holding as fallback (e.g. tvOS TVOut)")
        fallbackSurface = descriptor
      }
    }
    if let fallbackSurface {
      return FBFramebuffer(backing: .legacy(fallbackSurface), logger: logger)
    }
    throw FBSimulatorError.describe("Could not find the Main Screen Surface for Clients \(FBCollectionInformation.oneLineDescription(from: ports)) in \(ioClient)").build()
  }

  /**
   Fork addition. Synchronously resolves the default `SimScreen` from a `SimScreenAdapter`.

   `mainScreenSurface(for:logger:)` is a synchronous factory, but the Xcode 27
   enumeration API is asynchronous, so we bridge it with a bounded semaphore wait.
   */
  private class func defaultScreen(for adapter: SimScreenAdapter, logger: any FBControlCoreLogger) -> (any SimScreen)? {
    guard adapter.responds(to: #selector(SimScreenAdapter.enumerateScreens(withCompletionQueue:completionHandler:))) else {
      logger.log("SimScreenAdapter \(adapter) does not respond to enumerateScreensWithCompletionQueue:completionHandler:")
      return nil
    }

    let semaphore = DispatchSemaphore(value: 0)
    let queue = DispatchQueue(label: "com.facebook.fbsimulatorcontrol.framebuffer.screenenumeration")
    nonisolated(unsafe) var resolvedScreen: (any SimScreen)?

    adapter.enumerateScreens(withCompletionQueue: queue) { screens, enumerationError in
      if let enumerationError {
        logger.log("Failed to enumerate SimScreens: \(enumerationError)")
      }
      let screens = screens ?? []
      resolvedScreen = screens.first { $0.responds(to: #selector(getter: SimScreen.isDefault)) && $0.isDefault } ?? screens.first
      semaphore.signal()
    }

    guard semaphore.wait(timeout: .now() + 10) == .success else {
      logger.log("Timed out waiting for SimScreenAdapter \(adapter) to enumerate screens")
      return nil
    }
    return resolvedScreen
  }

  private init(backing: Backing, logger: any FBControlCoreLogger) {
    self.consumers = NSMapTable(keyOptions: .weakMemory, valueOptions: .copyIn)
    self.logger = logger
    self.backing = backing
    self.stats = FBFramebufferStats()
    self.lastLoggedStats = FBFramebufferStats()
    self.statsTimer = FBPeriodicStatsTimerCreate(5.0)
    super.init()
  }

  // MARK: - Public Methods

  @objc(attachConsumer:onQueue:)
  public func attach(_ consumer: any FBFramebufferConsumer, on queue: DispatchQueue) -> IOSurface? {
    // Don't attach the same consumer twice
    assert(!isConsumerAttached(consumer), "Cannot re-attach the same consumer \(consumer)")
    let consumerUUID = NSUUID()

    // Attempt to return the surface synchronously (if supported).
    let immediateSurface = extractImmediatelyAvailableSurface()

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

  @objc
  public func currentStats() -> FBFramebufferStats {
    stats
  }

  @objc public var statsStartTime: CFTimeInterval {
    statsTimer.startTime
  }

  // MARK: - Private

  private func extractImmediatelyAvailableSurface() -> IOSurface? {
    switch backing {
    case .legacy(let surface):
      guard let renderable = surface as? SimDisplayIOSurfaceRenderable else {
        return nil
      }
      if let surface = try? FBObjCExceptionGuard.guarded({ renderable.framebufferSurface }) as? IOSurface {
        return surface
      }
      return try? FBObjCExceptionGuard.guarded({ renderable.ioSurface }) as? IOSurface
    case .screen(let screen):
      // Prefer the raw (unmasked) surface to mirror the legacy framebufferSurface.
      return screen.unmaskedSurface ?? screen.maskedSurface
    }
  }

  private func registerConsumer(_ consumer: any FBFramebufferConsumer, uuid: NSUUID, queue: DispatchQueue) {
    switch backing {
    case .legacy(let surface):
      registerLegacyConsumer(consumer, surface: surface, uuid: uuid, queue: queue)
    case .screen(let screen):
      registerScreenConsumer(consumer, screen: screen, uuid: uuid, queue: queue)
    }
  }

  /// Fork addition: consumer registration against Xcode 27's unified SimScreen callbacks.
  /// The per-frame callback maps onto `didReceiveDamageRect()` so deferred (damage-driven)
  /// video streaming keeps working on Xcode 27, where rect-level damage callbacks no longer exist.
  private func registerScreenConsumer(_ consumer: any FBFramebufferConsumer, screen: any SimScreen, uuid: NSUUID, queue: DispatchQueue) {
    nonisolated(unsafe) let consumerRef = consumer

    _ = try? FBObjCExceptionGuard.guarded {
      screen.registerScreenCallbacks(
        with: uuid as UUID,
        callbackQueue: queue,
        frameCallback: { [weak self] in
          guard let self else { return }
          self.stats.damageCallbackCount += 1
          self.logStatsIfNeeded()
          queue.async {
            consumerRef.didReceiveDamageRect()
          }
        },
        surfacesChangedCallback: { [weak self] unmaskedSurface, maskedSurface in
          guard let self else { return }
          self.stats.ioSurfaceChangeCount += 1
          // Prefer the raw (unmasked) surface to mirror the legacy framebufferSurface.
          nonisolated(unsafe) let surfaceRef = unmaskedSurface ?? maskedSurface
          if self.stats.ioSurfaceChangeCount == 1 {
            self.logger.info().log("First SimScreen surface change callback, surface=\(String(describing: surfaceRef))")
          }
          queue.async {
            consumerRef.didChange(surfaceRef)
          }
        },
        propertiesChangedCallback: { _ in })
    }
  }

  private func registerLegacyConsumer(_ consumer: any FBFramebufferConsumer, surface: AnyObject, uuid: NSUUID, queue: DispatchQueue) {
    let renderable = surface as! SimDisplayIOSurfaceRenderable
    nonisolated(unsafe) let consumerRef = consumer

    let ioSurfaceChanged: (Any?) -> Void = { [weak self] surfaceArg in
      guard let self else { return }
      self.stats.ioSurfaceChangeCount += 1
      if self.stats.ioSurfaceChangeCount == 1 {
        self.logger.info().log("First IOSurface change callback, surface=\(String(describing: surfaceArg))")
      }
      nonisolated(unsafe) let surfaceRef = surfaceArg
      queue.async {
        consumerRef.didChange(surfaceRef as? IOSurface)
      }
    }

    _ = try? FBObjCExceptionGuard.guarded {
      renderable.registerCallback(with: uuid as UUID, ioSurfacesChangeCallback: ioSurfaceChanged)
    }
    _ = try? FBObjCExceptionGuard.guarded {
      renderable.registerCallback(with: uuid as UUID, ioSurfaceChangeCallback: ioSurfaceChanged)
    }

    let displayRenderable = surface as! SimDisplayRenderable
    let damageCallback: ([Any]?) -> Void = { [weak self] frames in
      guard let self else { return }
      let frameArray = frames ?? []
      self.stats.damageCallbackCount += 1
      self.stats.damageRectCount += UInt(frameArray.count)
      if frameArray.isEmpty {
        self.stats.emptyDamageCallbackCount += 1
      }
      self.logStatsIfNeeded()
      queue.async {
        consumerRef.didReceiveDamageRect()
      }
    }
    _ = try? FBObjCExceptionGuard.guarded {
      displayRenderable.registerCallback(with: uuid as UUID, damageRectanglesCallback: damageCallback)
    }
  }

  private func logStatsIfNeeded() {
    var timer = statsTimer
    var intervalDuration: CFTimeInterval = 0
    var totalElapsed: CFTimeInterval = 0
    if !FBPeriodicStatsTimerTick(&timer, &intervalDuration, &totalElapsed) {
      if timer.startTime != statsTimer.startTime {
        statsTimer = timer
        logger.info().log("First damage callback received")
      }
      return
    }
    statsTimer = timer

    let current = stats
    let last = lastLoggedStats
    let intervalCallbacks = current.damageCallbackCount - last.damageCallbackCount
    let intervalRects = current.damageRectCount - last.damageRectCount
    let intervalEmpty = current.emptyDamageCallbackCount - last.emptyDamageCallbackCount
    let intervalIOSurface = current.ioSurfaceChangeCount - last.ioSurfaceChangeCount
    lastLoggedStats = current

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

  private func unregisterConsumer(uuid: NSUUID) {
    switch backing {
    case .legacy(let surface):
      let renderable = surface as! SimDisplayIOSurfaceRenderable
      _ = try? FBObjCExceptionGuard.guarded {
        renderable.unregisterIOSurfacesChangeCallback(with: uuid as UUID)
      }
      _ = try? FBObjCExceptionGuard.guarded {
        renderable.unregisterIOSurfaceChangeCallback(with: uuid as UUID)
      }
      let displayRenderable = surface as! SimDisplayRenderable
      _ = try? FBObjCExceptionGuard.guarded {
        displayRenderable.unregisterDamageRectanglesCallback(with: uuid as UUID)
      }
    case .screen(let screen):
      guard screen.responds(to: #selector(SimScreen.unregisterScreenCallbacks(with:))) else {
        return
      }
      _ = try? FBObjCExceptionGuard.guarded {
        screen.unregisterScreenCallbacks(with: uuid as UUID)
      }
    }
  }
}
