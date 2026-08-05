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

/// Records what a dispatched event actually did to the transport, so the drain can be asserted rather
/// than inferred from timing.
///
/// SAFETY: the two counters are the only mutable state and are guarded by the lock.
// patternlint-disable-next-line unchecked-sendable
private final class RecordingHIDTransport: FBSimulatorHIDTransport, @unchecked Sendable {

  private let lock = NSLock()
  private var storedFlushCount = 0
  private var storedPrimitiveCount = 0

  /// How many times the transport was drained.
  var flushCount: Int {
    lock.withLock { storedFlushCount }
  }

  /// How many primitives were actually written to the transport.
  var primitiveCount: Int {
    lock.withLock { storedPrimitiveCount }
  }

  func disconnect() {}

  func sendTouch(direction: FBSimulatorHIDDirection, x: Double, y: Double) async throws {
    recordPrimitive()
  }

  func sendTwoFingerTouch(direction: FBSimulatorHIDDirection, finger1: CGPoint, finger2: CGPoint) async throws {
    recordPrimitive()
  }

  func sendButton(direction: FBSimulatorHIDDirection, button: FBSimulatorHIDButton) async throws {
    recordPrimitive()
  }

  func sendKeyboard(direction: FBSimulatorHIDDirection, keyCode: UInt32) async throws {
    recordPrimitive()
  }

  func sendTrackpad(point: FBSimulatorTrackpadPoint, phase: FBSimulatorTrackpadPhase) async throws {
    recordPrimitive()
  }

  func flush() async throws {
    lock.withLock { storedFlushCount += 1 }
  }

  private func recordPrimitive() {
    lock.withLock { storedPrimitiveCount += 1 }
  }
}

/// `FBSimulatorHIDEvent` is a union of things a simulator can be told to do, and only some of them go
/// through the HID transport — `FBSimulatorHIDTransport`'s own doc says orientation, lock, shake and
/// the in-call status bar "are not transport-switchable and stay on `FBSimulatorHID`'s Purple / Darwin
/// paths", and `.delay` writes nothing at all. The drain exists to let `dtuhidd` consume what was
/// written before the connection is torn down, so it is a transport concept.
///
/// These pin what the drain does today, ahead of making it follow what was written.
final class FBSimulatorHIDDrainTests: XCTestCase {

  /// A HID with no simulator attached. The transport primitives never touch the simulator, so they
  /// work; the Purple and Darwin paths throw `FBWeakTargetError.simulator`, which is why the
  /// non-transport events exercised here are the ones that need no simulator.
  private func makeHID(_ transport: RecordingHIDTransport) -> FBSimulatorHID {
    FBSimulatorHID(transport: transport, purple: FBSimulatorPurpleHID(), simulator: nil)
  }

  private var logger: any FBControlCoreLogger {
    FBControlCoreGlobalConfiguration.defaultLogger
  }

  // A `.delay` writes nothing to the transport — it is `Task.sleep`, pure sequencing — so there is
  // nothing to drain. It used to be drained anyway, which on DTUHID is an 80ms sleep for no reason.
  func testAnEventThatWritesNothingDoesNotDrainTheTransport() async throws {
    let transport = RecordingHIDTransport()
    try await makeHID(transport).send(event: .delay(0), logger: logger)

    XCTAssertEqual(transport.primitiveCount, 0, "a delay writes no primitive")
    XCTAssertEqual(transport.flushCount, 0, "so nothing is drained")
  }

  // A composite of nothing but non-transport events is the same story, and is what `ui rotate` or a
  // scripted `ui shell` line built from delays amounts to.
  func testACompositeThatWritesNothingDoesNotDrainTheTransport() async throws {
    let transport = RecordingHIDTransport()
    try await makeHID(transport).send(event: .composite([.delay(0), .delay(0)]), logger: logger)

    XCTAssertEqual(transport.primitiveCount, 0, "still nothing written")
    XCTAssertEqual(transport.flushCount, 0, "so still nothing drained")
  }

  // The rule is about what a case *does*, not which case it is, so it is stated on the event itself.
  // The Purple and Darwin cases cannot be dispatched here — they need a simulator — but the property
  // that decides their drain can be, and it is the same property the dispatch consults.
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

  // The case the drain is actually for: a gesture writes primitives, and is drained once at the end
  // rather than after each one. This must not change.
  func testAGestureIsDrainedExactlyOnceAfterAllItsPrimitives() async throws {
    let transport = RecordingHIDTransport()
    try await makeHID(transport).send(event: .tapAt(x: 10, y: 20), logger: logger)

    XCTAssertEqual(transport.primitiveCount, 2, "a tap is a touch down and a touch up")
    XCTAssertEqual(transport.flushCount, 1, "drained once for the gesture, not once per primitive")
  }

  // A mixed composite writes something, so it must still drain however the rule is expressed.
  func testAMixedCompositeIsDrained() async throws {
    let transport = RecordingHIDTransport()
    try await makeHID(transport).send(event: .composite([.delay(0), .touch(direction: .down, x: 1, y: 2)]), logger: logger)

    XCTAssertEqual(transport.primitiveCount, 1)
    XCTAssertEqual(transport.flushCount, 1, "one sub-event wrote, so the gesture needs draining")
  }
}
