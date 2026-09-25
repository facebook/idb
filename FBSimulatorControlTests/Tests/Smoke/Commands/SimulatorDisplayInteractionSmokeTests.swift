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
    guard try await commands.activeIntegratedDisplayIfSupported() != nil else {
      throw XCTSkip("Provider does not expose active display identities")
    }
    let context: SimulatorDisplayInteractionContext
    do {
      context = try await commands.interactionContext()
    } catch SimulatorCoreDeviceError.unsupported(let reason) {
      throw XCTSkip(reason)
    } catch SimulatorDisplayInteractionError.unsupportedCapability(let capability) {
      throw XCTSkip(capability)
    }
    XCTAssertTrue(context.display.isActive)
    XCTAssertTrue(context.display.isIntegrated)
    XCTAssertGreaterThan(context.accessibilityDisplayID, 0)
    XCTAssertGreaterThan(context.digitizerTarget, 0)
    let center = try context.digitizerPoint(from: CGPoint(x: context.pointSize.width / 2, y: context.pointSize.height / 2))
    XCTAssertEqual(center, CGPoint(x: 0.5, y: 0.5))
    try await commands.validate(context)
    for display in try await commands.list() where display.isIntegrated && !display.isActive {
      do {
        _ = try await commands.interactionContext(for: display.uniqueID)
        XCTFail("Inactive display selection must fail")
      } catch SimulatorDisplayInteractionError.inactiveDisplay(let id) {
        XCTAssertEqual(id, display.uniqueID)
      }
    }
    let details = "\(context.display.uniqueID): AX \(context.accessibilityDisplayID), target \(context.digitizerTarget), points \(context.pointSize), \(context.display.rotation.rawValue)"
    let attachment = XCTAttachment(string: details)
    attachment.lifetime = .keepAlways
    add(attachment)
    NSLog("%@", details)
  }
}
