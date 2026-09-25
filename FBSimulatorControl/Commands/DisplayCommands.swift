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

  /// Identities already learned for display UUIDs, so a routed read does not ask again.
  var identities: DisplayIdentityCache { get }
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

  func accessibilityID(for uniqueID: String) -> UInt32? {
    lock.lock()
    defer { lock.unlock() }
    return accessibility[uniqueID]
  }

  func remember(_ inventory: [SimulatorAccessibilityDisplay]) {
    lock.lock()
    defer { lock.unlock() }
    accessibility = Dictionary(inventory.map { ($0.uniqueID, $0.displayID) }, uniquingKeysWith: { first, _ in first })
  }
}

extension DisplayCommands {

  /// The active display and its accessibility identity, or nil when the runtime cannot report displays.
  /// Only a simulator with several integrated displays asks the guest, and only for a display it has not seen.
  func accessibilityDisplay(transport: any AXBridgeTransport) async throws -> AXTranslationDisplay? {
    let target: SimulatorDisplayTarget
    do {
      target = try await interactionTarget()
    } catch SimulatorCoreDeviceError.unsupported {
      return nil
    }
    guard case let .selected(display) = target else {
      return AXTranslationDisplay(display: target.display, accessibilityID: nil)
    }
    if let accessibilityID = identities.accessibilityID(for: display.uniqueID) {
      return AXTranslationDisplay(display: target.display, accessibilityID: accessibilityID)
    }
    let inventory = try AXBridgeDisplayInventory.decode(await transport.send(.displays))
    let matches = inventory.filter { $0.uniqueID == display.uniqueID }
    guard matches.count == 1, let match = matches.first else {
      throw SimulatorDisplayInteractionError.missingMapping(display.uniqueID)
    }
    try await validate(target.display)
    identities.remember(inventory)
    return AXTranslationDisplay(display: target.display, accessibilityID: match.displayID)
  }

  /// Fails if the active display, or its geometry, differs from the snapshot.
  func validate(_ display: SimulatorInteractionDisplay) async throws {
    guard try await interactionTarget().display.hasSameConfiguration(as: display) else { throw SimulatorDisplayError.changed }
  }
}
