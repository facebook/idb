/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

/// The display reads that route interactions. `SimulatorDisplayCommands` reads the simulator; the
/// routing built on these reads is shared by every conformance.
protocol DisplayCommands: AnyObject, Sendable {

  func report() async throws -> SimulatorDisplayReport

  func touchscreens() async throws -> [SimulatorTouchscreen]

  /// Identities already learned for display UUIDs, so a routed read does not ask again.
  var identities: DisplayIdentityCache { get }

  var transitionSettling: DisplayTransitionSettling { get }

  /// Numbers every report read through the routing below.
  var configurationTracker: DisplayConfigurationTracker { get }

  /// Each display report the runtime pushes, until the stream is cancelled. Throws when the runtime does not push.
  func reportPushes() throws -> AsyncThrowingStream<SimulatorDisplayReport, Error>

  var logger: (any ControlCoreLogger)? { get }

  /// The active display each time it may have changed while several integrated displays are attached,
  /// until the stream is cancelled. Nothing is yielded for a sole display or mid-transition.
  func activeDisplayUpdates() -> AsyncStream<SimulatorDisplay>
}

/// How long one-shot resolution keeps reading while a display transition settles, and how often.
@usableFromInline
struct DisplayTransitionSettling: Sendable {
  @usableFromInline let timeout: Duration
  let interval: Duration

  /// Live hinge changes have been seen to settle within about 4 seconds on a heavily loaded host.
  @usableFromInline static let standard = DisplayTransitionSettling(timeout: .seconds(5), interval: .milliseconds(100))
}

/// The display an interaction targets, and whether routing has to name it.
enum SimulatorDisplayTarget: Equatable, Sendable {
  /// The only integrated display. Accessibility and input reach it without naming it.
  case sole(SimulatorInteractionDisplay)
  /// The active one of several integrated displays. Accessibility and input have to name it.
  case selected(SimulatorDisplay)

  var display: SimulatorInteractionDisplay {
    switch self {
    case let .sole(display): display
    case let .selected(display): .identified(display)
    }
  }
}

/// Whether interactions route to a display the runtime reported, or fall back to the main display.
enum SimulatorDisplayResolution: Equatable, Sendable {
  /// The runtime cannot say which display interactions target. Accessibility and input reach the main
  /// display without naming one, as they did before runtimes reported displays.
  case fallback(SimulatorDisplayFallback)
  case target(SimulatorDisplayTarget)
  /// Layout has moved to a display whose backlight has not caught up, as after a hinge change.
  case transitioning

  /// The sole integrated display, active or not, or the active one of several.
  init(_ report: SimulatorDisplayReport) {
    switch report {
    case let .legacy(integrated):
      guard integrated.count == 1, let geometry = integrated.first else {
        self = .fallback(.legacyIntegratedDisplays(count: integrated.count))
        return
      }
      self = .target(.sole(.legacy(geometry)))
    case let .displays(displays):
      let integrated = displays.filter(\.isIntegrated)
      if integrated.contains(where: { $0.activity == .unknown }) {
        self = .fallback(.unknownActivity)
        return
      }
      if integrated.count == 1, let display = integrated.first {
        self = .target(.sole(.identified(display)))
        return
      }
      let active = integrated.filter(\.isActive)
      guard let display = active.first else {
        self = .fallback(.noActiveIntegratedDisplay)
        return
      }
      guard active.count == 1 else {
        self = .fallback(.ambiguousActiveDisplays(active.map(\.uniqueID)))
        return
      }
      self = .target(.selected(display))
    case .transitioning:
      self = .transitioning
    case let .failed(error):
      self = .fallback(.unreadable(error))
    }
  }
}

/// Why interactions fell back to the main display.
enum SimulatorDisplayFallback: Equatable, Sendable {
  /// The display read failed, including on runtimes that do not report displays.
  case unreadable(SimulatorCoreDeviceError)
  /// A runtime without display activity reports other than one integrated display.
  case legacyIntegratedDisplays(count: Int)
  /// The runtime reports an integrated display's backlight as `unknown`.
  case unknownActivity
  case noActiveIntegratedDisplay
  case ambiguousActiveDisplays([String])
}

/// A display snapshot and the accessibility identity that routes to it.
enum AXTranslationDisplay: Equatable, Sendable {
  /// The only integrated display, which accessibility reaches without naming it.
  case sole(SimulatorInteractionDisplay)
  /// The active one of several integrated displays, and the accessibility identity that reaches it.
  case selected(SimulatorDisplay, accessibilityID: UInt32)

  var interactionDisplay: SimulatorInteractionDisplay {
    switch self {
    case let .sole(display): display
    case let .selected(display, _): .identified(display)
    }
  }

  var accessibilityID: UInt32? {
    switch self {
    case .sole: nil
    case let .selected(_, accessibilityID): accessibilityID
    }
  }

  var geometry: SimulatorDisplayGeometry { interactionDisplay.geometry }

  var bounds: CGRect { CGRect(origin: .zero, size: geometry.pointSize) }
}

/// Numeric identities keyed by display UUID. The guest assigns them per display, so one is looked up
/// again only when a display it has not seen is selected.
// SAFETY: Every access to the mapping holds the lock.
// patternlint-disable-next-line unchecked-sendable
final class DisplayIdentityCache: @unchecked Sendable {
  private let lock = NSLock()
  private var accessibility: [String: UInt32] = [:]
  private var verified: AXBridgeDisplayCapabilities = []
  private var digitizers: [String: UInt32] = [:]

  /// Only an identity from an inventory that was checked for `capabilities` counts.
  func accessibilityID(for uniqueID: String, requiring capabilities: AXBridgeDisplayCapabilities = []) -> UInt32? {
    lock.lock()
    defer { lock.unlock() }
    guard verified.isSuperset(of: capabilities) else { return nil }
    return accessibility[uniqueID]
  }

  func remember(_ inventory: [SimulatorAccessibilityDisplay], verified capabilities: AXBridgeDisplayCapabilities = []) {
    lock.lock()
    defer { lock.unlock() }
    accessibility = Dictionary(inventory.map { ($0.uniqueID, $0.displayID) }, uniquingKeysWith: { first, _ in first })
    verified = capabilities
  }

  func digitizerTarget(for uniqueID: String) -> UInt32? {
    lock.lock()
    defer { lock.unlock() }
    return digitizers[uniqueID]
  }

  /// Keeps only displays reached by exactly one digitizer.
  func remember(_ touchscreens: [SimulatorTouchscreen]) {
    let targets = Dictionary(grouping: touchscreens.filter { $0.digitizerTarget > 0 }, by: \.displayUniqueID)
      .compactMapValues { $0.count == 1 ? $0[0].digitizerTarget : nil }
    lock.lock()
    defer { lock.unlock() }
    digitizers = targets
  }
}

extension DisplayCommands {

  var transitionSettling: DisplayTransitionSettling { .standard }

  func reportPushes() throws -> AsyncThrowingStream<SimulatorDisplayReport, Error> {
    throw SimulatorCoreDeviceError.unsupported("display pushes")
  }

  var logger: (any ControlCoreLogger)? { nil }

  /// The display interactions target once any display transition has settled. A hinge change moves layout to
  /// the new display before its backlight follows, and one-shot resolution waits that out. `.transitioning` only
  /// when the transition outlasts `transitionSettling`.
  func resolveDisplay() async throws -> SimulatorDisplayResolution {
    SimulatorDisplayResolution(try await settledReport())
  }

  /// Every identified display once any display transition has settled. A runtime that reports no display activity
  /// does not identify its displays, so none are listed.
  func describedDisplays() async throws -> TargetDetail<[TargetDisplayDescription]> {
    let report: SimulatorDisplayReport
    do {
      report = try await settledReport()
    } catch let error as CancellationError {
      throw error
    } catch {
      return .failed(error)
    }
    switch report {
    case let .displays(displays): return .read(displays.map(TargetDisplayDescription.init))
    case .legacy: return .read([])
    case .transitioning: return .failed(SimulatorDisplayError.transitioning)
    case let .failed(error): return .failed(error)
    }
  }

  /// `.transitioning` only when the transition outlasts `transitionSettling`.
  private func settledReport() async throws -> SimulatorDisplayReport {
    let settling = transitionSettling
    let deadline = ContinuousClock.now + settling.timeout
    while true {
      let current = try await observedReport()
      guard current == .transitioning, ContinuousClock.now < deadline else { return current }
      try await Task.sleep(for: settling.interval)
    }
  }

  /// One read of the display interactions target, without waiting for a transition to settle.
  func currentDisplay() async throws -> SimulatorDisplayResolution {
    SimulatorDisplayResolution(try await observedReport())
  }

  private func observedReport() async throws -> SimulatorDisplayReport {
    let report = try await report()
    _ = try? configurationTracker.observe(report)
    return report
  }

  /// The configuration once any display transition has settled. `.transitioning` only when the transition
  /// outlasts `timeout`.
  func settledConfiguration(within timeout: Duration) async throws -> SimulatorDisplayConfiguration {
    let deadline = ContinuousClock.now + timeout
    while true {
      let configuration = try configurationTracker.observe(await report())
      guard configuration.phase == .transitioning, ContinuousClock.now < deadline else { return configuration }
      try await Task.sleep(for: transitionSettling.interval)
    }
  }

  /// The accessibility identity of a display that has to be named. The guest is asked only for a display it
  /// has not seen, and only then are `capabilities` required of it.
  func accessibilityID(
    for display: SimulatorDisplay, transport: any AXBridgeTransport, requiring capabilities: AXBridgeDisplayCapabilities = []
  ) async throws -> UInt32 {
    if let accessibilityID = identities.accessibilityID(for: display.uniqueID, requiring: capabilities) {
      return accessibilityID
    }
    let inventory = try AXBridgeDisplayInventory.decode(await transport.send(.displays), requiring: capabilities)
    let matches = inventory.filter { $0.uniqueID == display.uniqueID }
    guard matches.count == 1, let match = matches.first else {
      throw SimulatorDisplayInteractionError.missingMapping(display.uniqueID)
    }
    try await validate(.identified(display))
    identities.remember(inventory, verified: capabilities)
    return match.displayID
  }

  /// The digitizer that reaches a display that has to be named. Touchscreens are read only for a display not
  /// seen before.
  func digitizerTarget(for display: SimulatorDisplay) async throws -> UInt32 {
    if let digitizerTarget = identities.digitizerTarget(for: display.uniqueID) {
      return digitizerTarget
    }
    let touchscreens = try await touchscreens()
    let matches = touchscreens.filter { $0.displayUniqueID == display.uniqueID }
    guard matches.count == 1, let touchscreen = matches.first, touchscreen.digitizerTarget > 0 else {
      throw SimulatorDisplayInteractionError.unsupportedCapability("a unique touchscreen target for display \(display.uniqueID)")
    }
    try await validate(.identified(display))
    identities.remember(touchscreens)
    return touchscreen.digitizerTarget
  }

  /// Fails if the active display, or its geometry, differs from the snapshot.
  func validate(_ display: SimulatorInteractionDisplay) async throws {
    switch try await resolveDisplay() {
    case let .target(target):
      guard target.display.hasSameConfiguration(as: display) else { throw SimulatorDisplayError.changed }
    case .fallback:
      throw SimulatorDisplayError.changed
    case .transitioning:
      throw SimulatorDisplayError.transitioning
    }
  }
}

extension DisplayCommands {

  func activeDisplayUpdates() -> AsyncStream<SimulatorDisplay> {
    polledActiveDisplayUpdates()
  }

  /// The current configuration, then each change to it, until the stream is cancelled. Follows `reportPushes()`,
  /// and polls every `interval` when the runtime does not push or its pushes stop. A failed read yields nothing.
  func followConfigurations(polling interval: Duration = .milliseconds(250)) -> AsyncStream<SimulatorDisplayConfiguration> {
    AsyncStream { continuation in
      let follow = Task {
        var last: SimulatorDisplayConfiguration?
        func observe(_ report: SimulatorDisplayReport) {
          guard let configuration = try? configurationTracker.observe(report), configuration != last else { return }
          last = configuration
          continuation.yield(configuration)
        }
        // Subscribing before the first read means a change between the two is pushed rather than missed.
        let subscription = Result { try reportPushes() }
        if let current = try? await report() {
          observe(current)
        }
        do {
          for try await pushed in try subscription.get() {
            observe(pushed)
          }
          if !Task.isCancelled {
            logger?.log("Display pushes ended, polling the display configuration")
          }
        } catch {
          logger?.log("Polling the display configuration, as display pushes are unavailable: \(error)")
        }
        while !Task.isCancelled {
          if let polled = try? await report() {
            observe(polled)
          }
          try? await Task.sleep(for: interval)
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in follow.cancel() }
    }
  }

  /// Every read of the active display while several integrated displays are attached, until the stream
  /// is cancelled. A read that fails, as one does mid-transition, or that finds a sole display yields nothing.
  func polledActiveDisplayUpdates(interval: Duration = .milliseconds(250)) -> AsyncStream<SimulatorDisplay> {
    AsyncStream { continuation in
      let poll = Task {
        while !Task.isCancelled {
          if case let .target(.selected(display))? = try? await currentDisplay() {
            continuation.yield(display)
          }
          try? await Task.sleep(for: interval)
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in poll.cancel() }
    }
  }
}
