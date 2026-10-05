/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorControl
import Foundation
import XCTest

final class SimulatorDisplayInteractionSmokeTests: ProvidedSimulatorTestCase {
  func testActiveDisplayHasIndependentAccessibilityAndTouchIdentities() async throws {
    let simulator = self.simulator!
    guard simulator.productFamily.hasTouchscreen else { throw XCTSkip("Requires a touchscreen simulator") }
    let commands = SimulatorDisplayCommands.commands(with: simulator)
    let display: SimulatorDisplay
    let accessibilityID: UInt32
    let digitizerTarget: UInt32
    do {
      switch try await commands.resolveDisplay() {
      case let .target(.sole(.identified(identified))), let .target(.selected(identified)):
        display = identified
      case .target(.sole(.legacy)), .fallback:
        throw XCTSkip("Provider does not expose active display identities")
      case .transitioning:
        return XCTFail("Display did not settle")
      }
      accessibilityID = try await commands.accessibilityID(for: display, transport: AXBridgeOneshotTransport(simulator: simulator))
      digitizerTarget = try await commands.digitizerTarget(for: display)
    } catch SimulatorCoreDeviceError.unsupported(let reason) {
      throw XCTSkip(reason)
    } catch SimulatorDisplayInteractionError.unsupportedCapability(let capability) {
      throw XCTSkip(capability)
    }
    XCTAssertTrue(display.isActive)
    XCTAssertTrue(display.isIntegrated)
    XCTAssertGreaterThan(accessibilityID, 0)
    XCTAssertGreaterThan(digitizerTarget, 0)
    let details = "\(display.uniqueID): AX \(accessibilityID), target \(digitizerTarget), points \(display.geometry.pointSize), \(display.rotation.rawValue)"
    let attachment = XCTAttachment(string: details)
    attachment.lifetime = .keepAlways
    add(attachment)
    NSLog("%@", details)
  }
}
