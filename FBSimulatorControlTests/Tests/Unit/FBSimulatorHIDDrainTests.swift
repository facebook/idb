/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
import FBControlCore
@testable import FBSimulatorControl
import Foundation
import XCTest

/// `FBSimulatorHIDEvent` is a union of things a simulator can be told to do, and only some of them go
/// through the HID transport — orientation and lock are Purple mach messages, shake and the in-call
/// status bar are Darwin notifications, and `.delay` writes nothing at all. The drain exists so
/// `dtuhidd` consumes what was written before the connection is torn down, so it is a transport
/// concern and applies to no other path.
///
/// The behavioural half of this suite — a recording transport counting `flush()` calls — is gone,
/// because `FBSimulatorHIDTransport` is now a closed enum over two concrete transports and takes no
/// test double. What it asserted is now structural instead: Indigo cannot drain because it no longer
/// has a `flush` to call, and only the `.dtuhid` case is reachable from `FBSimulatorHID.flush()`.
final class FBSimulatorHIDDrainTests: XCTestCase {

  // The rule is about what a case *does*, not which case it is, so it is stated on the event itself.
  // The Purple and Darwin cases cannot be dispatched without a simulator, but the property that
  // decides their drain can be, and it is the same property the dispatch consults.
  func testOnlyTransportCasesReportWritingToTheTransport() throws {
    let surfaceOrigin = try XCTUnwrap(FBSimulatorTrackpadPoint(x: 0, y: 0))
    let writes: [FBSimulatorHIDEvent] = [
      .touch(direction: .down, x: 1, y: 2),
      .button(direction: .down, button: .sideButton),
      .keyboard(direction: .down, keyCode: 4),
      .twoFingerTouch(direction: .down, finger1: .zero, finger2: .zero),
      .trackpad(phase: .began, point: surfaceOrigin),
    ]
    for event in writes {
      XCTAssertTrue(event.writesToTransport, "\(event) rides the transport")
    }

    let doesNotWrite: [FBSimulatorHIDEvent] = [
      .deviceOrientation(.landscapeLeft), // Purple mach message
      .lockDevice, // Purple mach message
      .shake, // Darwin notification
      .toggleInCallStatusBar, // Darwin notification
      .delay(0), // pure sequencing
    ]
    for event in doesNotWrite {
      XCTAssertFalse(event.writesToTransport, "\(event) never reaches the transport")
    }

    XCTAssertFalse(
      FBSimulatorHIDEvent.composite([.shake, .delay(0)]).writesToTransport,
      "a composite of non-transport events writes nothing"
    )
    XCTAssertTrue(
      FBSimulatorHIDEvent.composite([.shake, .touch(direction: .up, x: 0, y: 0)]).writesToTransport,
      "one sub-event writing is enough to need the drain"
    )
  }
}
