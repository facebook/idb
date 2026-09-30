/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// The display reads that route interactions. `SimulatorDisplayCommands` reads the simulator; the
/// routing built on these reads is shared by every conformance.
protocol DisplayCommands: AnyObject, Sendable {

  func interactionTarget() async throws -> SimulatorDisplayTarget

  func touchscreens() async throws -> [SimulatorTouchscreen]

  /// Identities already learned for display UUIDs, so a routed read does not ask again.
  var identities: DisplayIdentityCache { get }

  var transitionSettling: DisplayTransitionSettling { get }
}

/// How long one-shot resolution keeps reading while a display transition settles, and how often.
struct DisplayTransitionSettling: Sendable {
  let timeout: Duration
  let interval: Duration

  /// Live hinge changes have been seen to settle within about 4 seconds on a heavily loaded host.
  static let standard = DisplayTransitionSettling(timeout: .seconds(5), interval: .milliseconds(100))
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
}

/// Why interactions fell back to the main display.
enum SimulatorDisplayFallback: Equatable, Sendable {
  /// The runtime does not report displays.
  case unreported(String)
}

/// A display snapshot and the accessibility identity that routes to it.
struct AXTranslationDisplay: Equatable, Sendable {
  let display: SimulatorInteractionDisplay
  /// Nil for the only integrated display, which accessibility reaches without naming it.
  let accessibilityID: UInt32?

  var bounds: CGRect { CGRect(origin: .zero, size: display.geometry.pointSize) }
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

  /// The display interactions target once any display transition has settled. A hinge change moves layout to
  /// the new display before its backlight follows, and one-shot resolution waits that out rather than failing.
  func resolveDisplay() async throws -> SimulatorDisplayResolution {
    let settling = transitionSettling
    let deadline = ContinuousClock.now + settling.timeout
    while true {
      do {
        return try await currentDisplay()
      } catch SimulatorDisplayError.transitioning where ContinuousClock.now < deadline {
        try await Task.sleep(for: settling.interval)
      }
    }
  }

  /// One read of the display interactions target, failing rather than waiting while a transition settles.
  func currentDisplay() async throws -> SimulatorDisplayResolution {
    do {
      return .target(try await interactionTarget())
    } catch let SimulatorCoreDeviceError.unsupported(detail) {
      return .fallback(.unreported(detail))
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
    guard case let .target(target) = try await resolveDisplay(), target.display.hasSameConfiguration(as: display) else {
      throw SimulatorDisplayError.changed
    }
  }
}
