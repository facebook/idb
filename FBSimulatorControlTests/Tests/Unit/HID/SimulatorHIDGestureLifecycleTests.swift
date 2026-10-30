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
import Testing
import XPC

/// What happens to a gesture when it cannot finish: an interrupted `dtuhidd`, an operation that fails
/// part way, a cleanup that fails too, and a delay that cannot be slept for.
@Suite
struct SimulatorHIDGestureLifecycleTests {

  // MARK: - An interrupted dtuhidd

  @Test
  func aContactStartedBeforeAnInterruptionCannotBeContinued() throws {
    var tracker = DigitizerContactTracker()
    let started = try tracker.eventType(for: .down, interruptions: 0)
    #expect(started == .start)
    #expect(throws: SimulatorHIDError.self) {
      try tracker.eventType(for: .down, interruptions: 1)
    }
    let restarted = try tracker.eventType(for: .down, interruptions: 1)
    let moved = try tracker.eventType(for: .down, interruptions: 1)
    #expect([restarted, moved] == [.start, .position])
  }

  @Test
  func aContactLostToAnInterruptionFailsAndTheNextStartsAfresh() async throws {
    let digitizer = Service(SimulatorDigitizerHIDTransport.serviceName)
    let transport = digitizer.transport()

    try await transport.sendTouch(direction: .down, x: 25, y: 50, edge: .none)
    digitizer.connection.observe(.interrupted)
    await #expect {
      try await transport.sendTouch(direction: .down, x: 30, y: 50, edge: .none)
    } throws: { error in
      guard case .dtuhidGestureInterrupted = error as? SimulatorHIDError else { return false }
      return true
    }
    try await transport.sendTouch(direction: .down, x: 30, y: 50, edge: .none)

    let received = await digitizer.peer.received(atLeast: 2)
    #expect(received.map { xpc_dictionary_get_uint64(xpc_dictionary_get_dictionary($0, "payload")!, "eventType") } == [0, 0])
    digitizer.connection.disconnect()
  }
  /// A synthetic `dtuhidd` service and an unprobed connection to it.
  private struct Service {
    let peer: SyntheticXPCPeer
    let connection: SimulatorDTUHIDConnection

    init(_ name: String, sleeper: any DTUHIDSleeper = NoSleep()) {
      peer = SyntheticXPCServices().register(name) { _ in }
      connection = SimulatorDTUHIDConnection(channel: peer.channel(), serviceName: name, sleeper: sleeper)
    }

    func transport() -> SimulatorDigitizerHIDTransport {
      SimulatorDigitizerHIDTransport(
        connection: connection, mainScreenSize: CGSize(width: 100, height: 200), mainScreenScale: 2.0, productFamily: .iPhone)
    }
  }

  private struct NoSleep: DTUHIDSleeper {
    func sleep(for duration: Duration) async throws {}
  }

}
