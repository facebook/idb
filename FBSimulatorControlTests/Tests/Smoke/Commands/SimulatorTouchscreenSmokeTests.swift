/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorControl
import XCTest

final class SimulatorTouchscreenSmokeTests: ProvidedSimulatorTestCase {
  func testConnectedTouchscreensHaveExplicitUniqueTargets() async throws {
    let simulator = self.simulator!
    let touchscreens: [SimulatorTouchscreen]
    do {
      touchscreens = try await SimulatorDisplayCommands.commands(with: simulator).touchscreens()
    } catch SimulatorCoreDeviceError.unsupported(let reason) {
      guard simulator.productFamily.hasTouchscreen else { throw SimulatorCoreDeviceError.unsupported(reason) }
      throw XCTSkip(reason)
    }
    guard simulator.productFamily.hasTouchscreen else {
      XCTAssertEqual(touchscreens, [])
      return
    }
    XCTAssertFalse(touchscreens.isEmpty)
    XCTAssertEqual(Set(touchscreens.map(\.displayUniqueID)).count, touchscreens.count)
    XCTAssertEqual(Set(touchscreens.map(\.digitizerTarget)).count, touchscreens.count)
    let attachment = XCTAttachment(string: touchscreens.map { "\($0.displayUniqueID): target \($0.digitizerTarget)" }.joined(separator: "\n"))
    attachment.lifetime = .keepAlways
    add(attachment)
    for touchscreen in touchscreens {
      XCTAssertFalse(touchscreen.displayUniqueID.isEmpty)
      XCTAssertGreaterThan(touchscreen.digitizerTarget, 0)
    }
  }
}
