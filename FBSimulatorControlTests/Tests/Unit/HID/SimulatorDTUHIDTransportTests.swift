/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
import FBControlCore
@testable import FBSimulatorControl
import XCTest
import XPC

final class SimulatorDTUHIDTransportTests: XCTestCase {

  // MARK: - Wire encoding (model + XPCEncoder, no connection needed)

  func testDigitizerEventEnvelopeShape() throws {
    let event = try encodeDigitizer(
      IndigoDigitizerEvent(pointOne: DigitizerPoint(x: 0.25, y: 0.75), eventType: .start))

    XCTAssertEqual(xpc_get_type(event), XPC_TYPE_DICTIONARY)
    XCTAssertEqual(messageString(event, "messageType"), "IndigoDigitizerEvent")
    XCTAssertEqual(messageString(event, "featureIdentifier"), SimulatorDTUHIDTransport.digitizerServiceName)

    // isBarrier must be an XPC bool, false.
    XCTAssertEqual(xpc_get_type(xpc_dictionary_get_value(event, "isBarrier")!), XPC_TYPE_BOOL)
    XCTAssertFalse(xpc_dictionary_get_bool(event, "isBarrier"))

    let payload = xpc_dictionary_get_dictionary(event, "payload")
    XCTAssertNotNil(payload)
    let pointOne = xpc_dictionary_get_dictionary(payload!, "pointOne")
    XCTAssertNotNil(pointOne)

    // Coordinates are XPC doubles.
    XCTAssertEqual(xpc_get_type(xpc_dictionary_get_value(pointOne!, "x")!), XPC_TYPE_DOUBLE)
    XCTAssertEqual(xpc_dictionary_get_double(pointOne!, "x"), 0.25, accuracy: 1e-9)
    XCTAssertEqual(xpc_dictionary_get_double(pointOne!, "y"), 0.75, accuracy: 1e-9)

    // Single-finger touch: the nil pointTwo writes no key.
    XCTAssertNil(xpc_dictionary_get_dictionary(payload!, "pointTwo"))
  }

  func testDigitizerEventIntegersAreUInt64() throws {
    // Decode-critical: dtuhidd's Swift Codable rejects these fields if sent as strings.
    let event = try encodeDigitizer(
      IndigoDigitizerEvent(pointOne: DigitizerPoint(x: 0.1, y: 0.2), eventType: .end))
    let payload = xpc_dictionary_get_dictionary(event, "payload")!
    for key in ["eventType", "edge", "target"] {
      XCTAssertEqual(xpc_get_type(xpc_dictionary_get_value(payload, key)!), XPC_TYPE_UINT64, "\(key) must be uint64")
    }
    XCTAssertEqual(xpc_dictionary_get_uint64(payload, "eventType"), 2) // .end
    XCTAssertEqual(xpc_dictionary_get_uint64(payload, "edge"), 0)
    XCTAssertEqual(xpc_dictionary_get_uint64(payload, "target"), 0)
  }

  // The edge rides the same `IndigoDigitizerEvent.edge` field `dtuhidd` already declares, using the
  // same 0...4 encoding the Indigo builder takes, so one `SimulatorHIDEdge` describes both wires.
  func testDigitizerEventCarriesTheEdge() throws {
    for edge in SimulatorHIDEdge.allCases {
      let event = try encodeDigitizer(
        IndigoDigitizerEvent(
          pointOne: DigitizerPoint(x: 0.5, y: 0.99),
          eventType: .start,
          edge: UInt64(edge.rawValue)))
      let payload = xpc_dictionary_get_dictionary(event, "payload")!
      XCTAssertEqual(
        xpc_get_type(xpc_dictionary_get_value(payload, "edge")!), XPC_TYPE_UINT64, "edge must be uint64")
      XCTAssertEqual(xpc_dictionary_get_uint64(payload, "edge"), UInt64(edge.rawValue), "\(edge.name) edge")
    }
  }

  func testEdgeRawValuesMatchTheIndigoEncoding() {
    // Indigo.h: IndigoHIDEdgeNone/Top/Left/Bottom/Right.
    XCTAssertEqual(SimulatorHIDEdge.none.rawValue, 0)
    XCTAssertEqual(SimulatorHIDEdge.top.rawValue, 1)
    XCTAssertEqual(SimulatorHIDEdge.left.rawValue, 2)
    XCTAssertEqual(SimulatorHIDEdge.bottom.rawValue, 3)
    XCTAssertEqual(SimulatorHIDEdge.right.rawValue, 4)
  }

  // MARK: - Contact-state machine

  func testContactTrackerMapsDownUpToStartPositionEnd() {
    var tracker = DigitizerContactTracker()
    XCTAssertEqual(tracker.eventType(for: .down), .start)
    XCTAssertEqual(tracker.eventType(for: .down), .position)
    XCTAssertEqual(tracker.eventType(for: .down), .position)
    XCTAssertEqual(tracker.eventType(for: .up), .end)
    // A subsequent gesture starts fresh.
    XCTAssertEqual(tracker.eventType(for: .down), .start)
    XCTAssertEqual(tracker.eventType(for: .up), .end)
  }

  func testDigitizerEventTypeRawValues() {
    XCTAssertEqual(DigitizerEventType.start.rawValue, 0)
    XCTAssertEqual(DigitizerEventType.position.rawValue, 1)
    XCTAssertEqual(DigitizerEventType.end.rawValue, 2)
  }

  // MARK: - Unimplemented primitives throw

  func testUnimplementedPrimitivesThrow() async {
    let transport = makeTransport(DrainRecorder())

    // Apple Pay has no single HID usage (it is a double side-button press), so it stays unimplemented.
    await assertThrowsNotImplemented { try await transport.sendButton(direction: .down, button: .applePay) }
  }

  func testTouchOnAppleTVThrows() async {
    let transport = makeTransport(DrainRecorder(), productFamily: .appleTV)

    await assertThrowsTouchUnsupported {
      try await transport.sendTouch(direction: .down, x: 10, y: 20, edge: .none)
    }
    await assertThrowsTouchUnsupported {
      try await transport.sendTwoFingerTouch(
        direction: .down, finger1: CGPoint(x: 10, y: 20), finger2: CGPoint(x: 30, y: 40))
    }
  }

  // MARK: - Two-finger encoding

  func testDigitizerEventWithTwoFingers() throws {
    let event = try encodeDigitizer(
      IndigoDigitizerEvent(
        pointOne: DigitizerPoint(x: 0.25, y: 0.5),
        pointTwo: DigitizerPoint(x: 0.75, y: 0.5),
        eventType: .start))
    let payload = xpc_dictionary_get_dictionary(event, "payload")!
    let pointOne = xpc_dictionary_get_dictionary(payload, "pointOne")!
    let pointTwo = xpc_dictionary_get_dictionary(payload, "pointTwo")
    XCTAssertNotNil(pointTwo, "a two-finger event must carry pointTwo")
    XCTAssertEqual(xpc_dictionary_get_double(pointOne, "x"), 0.25, accuracy: 1e-9)
    XCTAssertEqual(xpc_dictionary_get_double(pointTwo!, "x"), 0.75, accuracy: 1e-9)
    XCTAssertEqual(xpc_dictionary_get_double(pointTwo!, "y"), 0.5, accuracy: 1e-9)
  }

  // MARK: - Button encoding

  func testButtonUsageMapping() {
    XCTAssertEqual(SimulatorHIDButton.homeButton.identity.consumerUsage?.page, 0x0C)
    XCTAssertEqual(SimulatorHIDButton.homeButton.identity.consumerUsage?.code, 0x40)
    XCTAssertEqual(SimulatorHIDButton.lock.identity.consumerUsage?.code, 0x30)
    XCTAssertEqual(SimulatorHIDButton.sideButton.identity.consumerUsage?.code, 0x30)
    XCTAssertEqual(SimulatorHIDButton.siri.identity.consumerUsage?.code, 0xCF)
    XCTAssertEqual(SimulatorHIDButton.playPause.identity.consumerUsage?.page, 0x0C)
    XCTAssertEqual(SimulatorHIDButton.playPause.identity.consumerUsage?.code, 0xCD)
    XCTAssertEqual(SimulatorHIDButton.volumeUp.identity.consumerUsage?.code, 0xE9)
    XCTAssertEqual(SimulatorHIDButton.volumeDown.identity.consumerUsage?.code, 0xEA)
    XCTAssertNil(SimulatorHIDButton.applePay.identity.consumerUsage)
  }

  func testButtonEventEnvelope() throws {
    let down = try encodeButton(IndigoButtonEvent(usagePage: 0x0C, usageCode: 0x40, state: .down))
    XCTAssertEqual(xpc_get_type(down), XPC_TYPE_DICTIONARY)
    XCTAssertEqual(messageString(down, "messageType"), "IndigoButtonEvent")
    XCTAssertEqual(messageString(down, "featureIdentifier"), SimulatorDTUHIDTransport.digitizerServiceName)

    let payload = xpc_dictionary_get_dictionary(down, "payload")!
    for key in ["usagePage", "usageCode", "state"] {
      XCTAssertEqual(xpc_get_type(xpc_dictionary_get_value(payload, key)!), XPC_TYPE_UINT64, "\(key) must be uint64")
    }
    XCTAssertEqual(xpc_dictionary_get_uint64(payload, "usagePage"), 0x0C)
    XCTAssertEqual(xpc_dictionary_get_uint64(payload, "usageCode"), 0x40)
    XCTAssertEqual(xpc_dictionary_get_uint64(payload, "state"), 1) // down
  }

  // MARK: - Send pipeline (envelope shape)

  /// The connection's `encode` wraps any `Encodable` payload in the shared `DTUHIDMessage` envelope —
  /// `messageType` discriminator, `isBarrier` bool, the digitizer `featureIdentifier`, and the typed
  /// `payload`. Every capability rides this shape, so it is pinned here independent of any one model.
  func testEncodeWrapsPayloadInEnvelope() throws {
    struct Probe: Encodable {
      let value: UInt64
    }
    let dtuhid = makeConnection(DrainRecorder())

    let message = try dtuhid.encode(messageType: "Probe", payload: Probe(value: 7))

    XCTAssertEqual(xpc_get_type(message), XPC_TYPE_DICTIONARY)
    XCTAssertEqual(messageString(message, "messageType"), "Probe")
    XCTAssertEqual(messageString(message, "featureIdentifier"), SimulatorDTUHIDTransport.digitizerServiceName)
    XCTAssertEqual(xpc_get_type(xpc_dictionary_get_value(message, "isBarrier")!), XPC_TYPE_BOOL)
    XCTAssertFalse(xpc_dictionary_get_bool(message, "isBarrier"))
    let payload = xpc_dictionary_get_dictionary(message, "payload")
    XCTAssertNotNil(payload)
    XCTAssertEqual(xpc_dictionary_get_uint64(payload!, "value"), 7)
  }

  // MARK: - Keyboard encoding

  func testKeyboardButtonEventEnvelope() throws {
    let down = try encodeKeyboard(IndigoKeyboardButtonEvent(usageCode: 4, state: .down)) // 'a'
    XCTAssertEqual(xpc_get_type(down), XPC_TYPE_DICTIONARY)
    XCTAssertEqual(messageString(down, "messageType"), "IndigoKeyboardButtonEvent")
    XCTAssertEqual(messageString(down, "featureIdentifier"), SimulatorDTUHIDTransport.digitizerServiceName)

    let payload = xpc_dictionary_get_dictionary(down, "payload")!
    XCTAssertEqual(xpc_get_type(xpc_dictionary_get_value(payload, "usageCode")!), XPC_TYPE_UINT64)
    XCTAssertEqual(xpc_dictionary_get_uint64(payload, "usageCode"), 4)
    XCTAssertEqual(xpc_get_type(xpc_dictionary_get_value(payload, "state")!), XPC_TYPE_UINT64)
    XCTAssertEqual(xpc_dictionary_get_uint64(payload, "state"), 1) // down

    let up = try encodeKeyboard(IndigoKeyboardButtonEvent(usageCode: 0xE1, state: .up)) // left-shift up
    let upPayload = xpc_dictionary_get_dictionary(up, "payload")!
    XCTAssertEqual(xpc_dictionary_get_uint64(upPayload, "usageCode"), 0xE1)
    XCTAssertEqual(xpc_dictionary_get_uint64(upPayload, "state"), 2) // up
  }

  func testHIDButtonStateRawValues() {
    XCTAssertEqual(HIDButtonState.down.rawValue, 1)
    XCTAssertEqual(HIDButtonState.up.rawValue, 2)
  }

  // MARK: - Drain (driven through SimulatorHID, injected clock, synthetic dtuhidd)

  func testFlushWithoutAGestureIsANoOp() async throws {
    let recorder = DrainRecorder()
    let hid = makeHID(recorder)

    try await hid.flush()

    let sleeps = await recorder.sleeps
    XCTAssertEqual(sleeps, [])
  }

  func testADelayOnlyEventDrainsNothing() async throws {
    let recorder = DrainRecorder()
    let hid = makeHID(recorder)

    try await hid.send(event: .delay(0), logger: ControlCoreGlobalConfiguration.defaultLogger)

    let sleeps = await recorder.sleeps
    XCTAssertEqual(sleeps, [])
  }

  func testAGestureDrainsOnce() async throws {
    let recorder = DrainRecorder()
    let hid = makeHID(recorder)

    try await sendGesture(on: hid)

    let sleeps = await recorder.sleeps
    XCTAssertEqual(sleeps, [DTUHIDTiming.drain])
  }

  func testEachGestureDrains() async throws {
    let recorder = DrainRecorder()
    let hid = makeHID(recorder)

    try await sendGesture(on: hid)
    try await sendGesture(on: hid)

    let sleeps = await recorder.sleeps
    XCTAssertEqual(sleeps, [DTUHIDTiming.drain, DTUHIDTiming.drain])
  }

  func testRedundantFlushIsANoOp() async throws {
    let recorder = DrainRecorder()
    let hid = makeHID(recorder)

    try await sendGesture(on: hid)
    try await hid.flush()

    let sleeps = await recorder.sleeps
    XCTAssertEqual(sleeps, [DTUHIDTiming.drain])
  }

  func testDrainFailurePropagatesAndTheNextGestureDrains() async throws {
    let recorder = DrainRecorder()
    await recorder.setFailNextSleep()
    let hid = makeHID(recorder)

    do {
      try await sendGesture(on: hid)
      XCTFail("expected the drain to propagate its failure out of send")
    } catch is DrainFailure {
    } catch {
      XCTFail("unexpected error: \(error)")
    }

    try await sendGesture(on: hid)
    let sleeps = await recorder.sleeps
    XCTAssertEqual(sleeps, [DTUHIDTiming.drain])
  }

  func testOnCloseGesturesDrainOnceOnTheExplicitFlush() async throws {
    let recorder = DrainRecorder()
    let hid = makeHID(recorder)

    try await sendGesture(on: hid, drain: .onClose)
    try await sendGesture(on: hid, drain: .onClose)
    try await hid.flush()

    let sleeps = await recorder.sleeps
    XCTAssertEqual(sleeps, [DTUHIDTiming.drain])
  }

  func testSendDuringADrainIsDrainedByTheNextFlush() async throws {
    let recorder = DrainRecorder()
    let gate = SleepGate()
    let hid = makeHID(recorder, gate: gate)

    try await sendGesture(on: hid, drain: .onClose)
    let inFlight = Task { try await hid.flush() }
    await gate.awaitEntry()
    try await sendGesture(on: hid, drain: .onClose)
    await gate.open()
    try await inFlight.value

    try await hid.flush()

    let sleeps = await recorder.sleeps
    XCTAssertEqual(sleeps, [DTUHIDTiming.drain, DTUHIDTiming.drain])
  }

  // MARK: - Connect-time liveness

  func testLivenessProbePaysTheTailBeforeTheFirstDrain() async throws {
    let recorder = DrainRecorder()
    let connection = makeConnection(recorder)

    try await connection.confirmLiveness()
    try await connection.send(
      messageType: "IndigoKeyboardButtonEvent", payload: IndigoKeyboardButtonEvent(usageCode: 0, state: .up))
    try await connection.flush()

    let sleeps = await recorder.sleeps
    XCTAssertEqual(sleeps, [DTUHIDTiming.replyTail, DTUHIDTiming.drain])
  }

  func testLivenessProbeCarriesAnInertBarrier() async throws {
    let peer = Self.dtuhidd(.answer)
    let connection = makeConnection(DrainRecorder(), dtuhidd: peer)

    try await connection.confirmLiveness()

    let received = peer.received
    XCTAssertEqual(received.count, 1)
    let probe = try XCTUnwrap(received.first)
    XCTAssertTrue(xpc_dictionary_get_bool(probe, "isBarrier"))
    XCTAssertEqual(messageString(probe, "messageType"), "IndigoKeyboardButtonEvent")
    // Usage 0 is "no event indicated", so a guest that is listening still sees no keypress.
    let payload = try XCTUnwrap(xpc_dictionary_get_dictionary(probe, "payload"))
    XCTAssertEqual(xpc_dictionary_get_uint64(payload, "usageCode"), 0)
  }

  func testLivenessProbeFailurePaysNoTail() async throws {
    let recorder = DrainRecorder()
    let peer = Self.dtuhidd(.drop)
    let connection = makeConnection(recorder, dtuhidd: peer)

    do {
      try await connection.confirmLiveness()
      XCTFail("expected the probe to fail")
    } catch SimulatorXPCError.peerUnavailable {
    } catch {
      XCTFail("unexpected error: \(error)")
    }

    let sleeps = await recorder.sleeps
    XCTAssertEqual(sleeps, [])
  }

  func testConnectProbesBeforeHandingOutTheConnection() async throws {
    let recorder = DrainRecorder()
    let services = SyntheticXPCServices()
    let peer = services.register(SimulatorDTUHIDTransport.digitizerServiceName, respond: Self.dtuhiddResponder(.answer))

    let connection = try await SimulatorDTUHIDConnection.connect(
      using: services.connector, serviceName: SimulatorDTUHIDTransport.digitizerServiceName, clock: recordingClock(recorder))
    defer { connection.disconnect() }

    XCTAssertEqual(services.lookups, [SimulatorDTUHIDTransport.digitizerServiceName])
    XCTAssertEqual(peer.received.map { xpc_dictionary_get_bool($0, "isBarrier") }, [true])
    let sleeps = await recorder.sleeps
    XCTAssertEqual(sleeps, [DTUHIDTiming.replyTail])
  }

  func testConnectRetriesAnUnansweredProbeAndThenGivesUp() async throws {
    let recorder = DrainRecorder()
    let services = SyntheticXPCServices()
    let peer = services.register(SimulatorDTUHIDTransport.digitizerServiceName, respond: Self.dtuhiddResponder(.drop))

    do {
      _ = try await SimulatorDTUHIDConnection.connect(
        using: services.connector, serviceName: SimulatorDTUHIDTransport.digitizerServiceName, clock: recordingClock(recorder))
      XCTFail("expected the connect to give up")
    } catch let error as SimulatorHIDError {
      guard case .dtuhidUnresponsive(attempts: DTUHIDTiming.livenessAttempts, _) = error else {
        return XCTFail("unexpected error: \(error)")
      }
      XCTAssertTrue(error.isDTUHIDUnreachable)
    }

    XCTAssertEqual(services.lookups.count, DTUHIDTiming.livenessAttempts)
    XCTAssertEqual(peer.connections, DTUHIDTiming.livenessAttempts)
    let sleeps = await recorder.sleeps
    XCTAssertEqual(sleeps, Array(repeating: DTUHIDTiming.livenessRetryBackoff, count: DTUHIDTiming.livenessAttempts - 1))
  }

  // MARK: - A connection that has gone away

  func testASendAfterTheServiceIsInvalidatedThrows() async throws {
    let peer = Self.dtuhidd(.answer)
    let connection = makeConnection(DrainRecorder(), dtuhidd: peer)
    try await connection.confirmLiveness()

    peer.invalidate()
    // The first probe only finds its connection dropped; the reconnect it leaves behind is what
    // finds the service gone.
    for _ in 0..<2 {
      do {
        try await connection.confirmLiveness()
        XCTFail("expected the probe to fail once the service is gone")
      } catch SimulatorXPCError.peerUnavailable {}
    }

    do {
      try await connection.send(
        messageType: "IndigoKeyboardButtonEvent", payload: IndigoKeyboardButtonEvent(usageCode: 4, state: .down))
      XCTFail("expected the send to fail once the service is gone")
    } catch SimulatorHIDError.dtuhidConnectionInvalidated(name: SimulatorDTUHIDTransport.digitizerServiceName) {}
    XCTAssertEqual(peer.received.count, 1)
  }

  func testConnectToAServiceTheRuntimeDoesNotVend() async throws {
    let recorder = DrainRecorder()
    let services = SyntheticXPCServices()

    do {
      _ = try await SimulatorDTUHIDConnection.connect(
        using: services.connector, serviceName: SimulatorDTUHIDTransport.digitizerServiceName, clock: recordingClock(recorder))
      XCTFail("expected the connect to fail")
    } catch let error as SimulatorHIDError {
      XCTAssertTrue(error.isDTUHIDUnreachable)
      guard case .dtuhidServiceNotVended(name: SimulatorDTUHIDTransport.digitizerServiceName) = error else {
        return XCTFail("unexpected error: \(error)")
      }
    }

    XCTAssertEqual(services.lookups.count, 1)
    let sleeps = await recorder.sleeps
    XCTAssertEqual(sleeps.count, 0)
  }

  func testConnectWhileTheSimulatorIsBooting() async throws {
    let recorder = DrainRecorder()
    let services = SyntheticXPCServices()
    services.register(SimulatorDTUHIDTransport.digitizerServiceName, respond: Self.dtuhiddResponder(.answer))
    services.simulatorState = .booting

    let connection = try await SimulatorDTUHIDConnection.connect(
      using: services.connector, serviceName: SimulatorDTUHIDTransport.digitizerServiceName, clock: recordingClock(recorder))
    connection.disconnect()

    XCTAssertEqual(services.simulatorState, .booted)
    XCTAssertEqual(services.lookups.count, 1)
    let sleeps = await recorder.sleeps
    XCTAssertEqual(sleeps, [DTUHIDTiming.replyTail])
  }

  func testConnectToAShutDownSimulator() async throws {
    let recorder = DrainRecorder()
    let services = SyntheticXPCServices()
    services.register(SimulatorDTUHIDTransport.digitizerServiceName, respond: Self.dtuhiddResponder(.answer))
    services.simulatorState = .shutdown

    do {
      _ = try await SimulatorDTUHIDConnection.connect(
        using: services.connector, serviceName: SimulatorDTUHIDTransport.digitizerServiceName, clock: recordingClock(recorder))
      XCTFail("expected the connect to fail")
    } catch let error as SimulatorHIDError {
      XCTAssertFalse(error.isDTUHIDUnreachable)
      guard case .dtuhidSimulatorNotBooted(name: SimulatorDTUHIDTransport.digitizerServiceName, state: .shutdown) = error else {
        return XCTFail("unexpected error: \(error)")
      }
    }

    XCTAssertEqual(services.lookups.count, 0)
    let sleeps = await recorder.sleeps
    XCTAssertEqual(sleeps.count, 0)
  }

  func testATapReachesTheServiceAsStartThenEnd() async throws {
    let peer = Self.dtuhidd(.answer)
    let transport = makeTransport(DrainRecorder(), dtuhidd: peer)

    try await transport.sendTouch(direction: .down, x: 25, y: 50, edge: .none)
    try await transport.sendTouch(direction: .up, x: 25, y: 50, edge: .none)

    let received = await peer.received(atLeast: 2)
    XCTAssertEqual(received.map { messageString($0, "messageType") }, ["IndigoDigitizerEvent", "IndigoDigitizerEvent"])
    XCTAssertEqual(
      received.map { xpc_dictionary_get_uint64(xpc_dictionary_get_dictionary($0, "payload")!, "eventType") },
      [DigitizerEventType.start.rawValue, DigitizerEventType.end.rawValue])
    let pointOne = try XCTUnwrap(xpc_dictionary_get_dictionary(xpc_dictionary_get_dictionary(received[0], "payload")!, "pointOne"))
    XCTAssertEqual(xpc_dictionary_get_double(pointOne, "x"), 0.5, accuracy: 1e-9)
    XCTAssertEqual(xpc_dictionary_get_double(pointOne, "y"), 0.5, accuracy: 1e-9)
  }

  func testDisconnectClosesTheConnection() async throws {
    let peer = Self.dtuhidd(.answer)
    let connection = makeConnection(DrainRecorder(), dtuhidd: peer)
    try await connection.confirmLiveness()

    connection.disconnect()

    let closed = await peer.closed(atLeast: 1)
    XCTAssertEqual(closed, 1)
  }

  func testAMidRespawnLookupFailureIsRetriedRatherThanTerminal() {
    // A lookup or connect failure is not known to be permanent, and treating it as terminal falls
    // back to Indigo, which costs the keyboard.
    XCTAssertTrue(
      SimulatorHIDError.dtuhidDigitizerServiceUnavailable(underlying: nil).isTransientDTUHIDFailure)
    XCTAssertTrue(SimulatorHIDError.dtuhidConnectionFailed.isTransientDTUHIDFailure)
    // A toolchain without the `_4sim` symbols does not grow them by being asked again.
    XCTAssertFalse(SimulatorHIDError.dtuhidXPCSymbolsUnavailable.isTransientDTUHIDFailure)
  }

  func testUnresponsiveDTUHIDIsWorthFallingBackFrom() {
    // `SimulatorHID` negotiates around exactly the `isDTUHIDUnreachable` cases, so an unanswered
    // probe has to be one of them or a wedged daemon costs every input rather than the keyboard.
    XCTAssertTrue(
      SimulatorHIDError.dtuhidUnresponsive(attempts: 3, underlying: nil).isDTUHIDUnreachable)
  }

  // MARK: - Teardown

  func testCloseWithUndrainedSend() async throws {
    let recorder = DrainRecorder()
    let hid = makeHID(recorder)

    try await sendGesture(on: hid, drain: .onClose)
    await hid.close()

    let sleeps = await recorder.sleeps
    XCTAssertEqual(sleeps, [DTUHIDTiming.drain])
  }

  func testCloseAfterCancellation() async throws {
    let recorder = DrainRecorder()
    let hid = makeHID(recorder)
    try await sendGesture(on: hid)
    try await sendGesture(on: hid, drain: .onClose)

    let gate = SleepGate()
    let closing = Task {
      await gate.enter()
      await hid.close()
    }
    await gate.awaitEntry()
    closing.cancel()
    await gate.open()
    await closing.value

    let sleeps = await recorder.sleeps
    XCTAssertEqual(sleeps, [DTUHIDTiming.drain, DTUHIDTiming.drain])
  }

  func testCloseSkipsTheDrainWhenNothingWasSent() async throws {
    let recorder = DrainRecorder()
    let hid = makeHID(recorder)

    await hid.close()

    let sleeps = await recorder.sleeps
    XCTAssertEqual(sleeps, [])
  }

  // MARK: - Helpers

  /// A HID over a DTUHID transport whose drain waits are recorded rather than taken, talking to a
  /// synthetic `dtuhidd` that answers barriers.
  private func makeHID(_ recorder: DrainRecorder, gate: SleepGate? = nil) -> SimulatorHID {
    SimulatorHID(transport: .dtuhid(makeTransport(recorder, gate: gate)))
  }

  private func makeTransport(
    _ recorder: DrainRecorder, gate: SleepGate? = nil, dtuhidd: SyntheticXPCPeer? = nil, productFamily: ProductFamily = .iPhone
  ) -> SimulatorDTUHIDTransport {
    SimulatorDTUHIDTransport(
      connection: makeConnection(recorder, gate: gate, dtuhidd: dtuhidd),
      mainScreenSize: CGSize(width: 100, height: 200),
      mainScreenScale: 2.0,
      productFamily: productFamily)
  }

  /// A connection to `dtuhidd`, or to a fresh synthetic `dtuhidd` that answers barriers.
  private func makeConnection(
    _ recorder: DrainRecorder, gate: SleepGate? = nil, dtuhidd: SyntheticXPCPeer? = nil
  ) -> SimulatorDTUHIDConnection {
    let peer = dtuhidd ?? Self.dtuhidd(.answer)
    let connection = SimulatorDTUHIDConnection(
      channel: peer.channel(), serviceName: SimulatorDTUHIDTransport.digitizerServiceName, clock: recordingClock(recorder, gate: gate))
    addTeardownBlock {
      connection.disconnect()
      withExtendedLifetime(peer) {}
    }
    return connection
  }

  private static func dtuhidd(_ barrier: Barrier) -> SyntheticXPCPeer {
    SyntheticXPCServices().register(SimulatorDTUHIDTransport.digitizerServiceName, respond: dtuhiddResponder(barrier))
  }

  private enum Barrier {
    /// Replies, as a running `dtuhidd` does.
    case answer
    /// Drops the connection, as a daemon that aborts on launch does.
    case drop
  }

  /// A synthetic `dtuhidd`: events are one-way, and a barrier is answered or not.
  private static func dtuhiddResponder(_ barrier: Barrier) -> SyntheticXPCPeer.Responder {
    { request in
      guard xpc_dictionary_get_bool(request.message, "isBarrier") else { return }
      switch barrier {
      case .answer: request.reply(xpc_dictionary_create(nil, nil, 0))
      case .drop: request.interrupt()
      }
    }
  }

  /// One inert keypress. Usage `0` is "no event indicated", so a guest would ignore it even if one
  /// were listening.
  private func sendGesture(on hid: SimulatorHID, drain: SimulatorHIDDrain = .perEvent) async throws {
    try await hid.send(
      event: .keyboard(direction: .up, keyCode: 0),
      logger: ControlCoreGlobalConfiguration.defaultLogger,
      drain: drain)
  }

  private enum DrainFailure: Error {
    case injected
  }

  private actor DrainRecorder {
    var sleeps: [Duration] = []
    var failsNextSleep = false

    func setFailNextSleep() {
      failsNextSleep = true
    }

    func sleep(_ duration: Duration) throws {
      if failsNextSleep {
        failsNextSleep = false
        throw DrainFailure.injected
      }
      sleeps.append(duration)
    }
  }

  /// Parks the first caller until `open()`; later callers pass through.
  private actor SleepGate {
    private var entered = false
    private var opened = false
    private var entryWaiter: CheckedContinuation<Void, Never>?
    private var exitWaiter: CheckedContinuation<Void, Never>?

    func enter() async {
      guard !entered else {
        return
      }
      entered = true
      entryWaiter?.resume()
      entryWaiter = nil
      guard !opened else {
        return
      }
      await withCheckedContinuation { exitWaiter = $0 }
    }

    func awaitEntry() async {
      guard !entered else {
        return
      }
      await withCheckedContinuation { entryWaiter = $0 }
    }

    func open() {
      opened = true
      exitWaiter?.resume()
      exitWaiter = nil
    }
  }

  private func recordingClock(_ recorder: DrainRecorder, gate: SleepGate? = nil) -> DTUHIDDrainClock {
    DTUHIDDrainClock(sleep: { duration in
      try Task.checkCancellation()
      await gate?.enter()
      try await recorder.sleep(duration)
    })
  }

  private func encodeDigitizer(_ event: IndigoDigitizerEvent) throws -> xpc_object_t {
    try XPCEncoder().encode(
      DTUHIDMessage(
        messageType: "IndigoDigitizerEvent",
        featureIdentifier: SimulatorDTUHIDTransport.digitizerServiceName,
        payload: event))
  }

  private func encodeKeyboard(_ event: IndigoKeyboardButtonEvent) throws -> xpc_object_t {
    try XPCEncoder().encode(
      DTUHIDMessage(
        messageType: "IndigoKeyboardButtonEvent",
        featureIdentifier: SimulatorDTUHIDTransport.digitizerServiceName,
        payload: event))
  }

  private func encodeButton(_ event: IndigoButtonEvent) throws -> xpc_object_t {
    try XPCEncoder().encode(
      DTUHIDMessage(
        messageType: "IndigoButtonEvent",
        featureIdentifier: SimulatorDTUHIDTransport.digitizerServiceName,
        payload: event))
  }

  private func messageString(_ dictionary: xpc_object_t, _ key: String) -> String? {
    guard let cString = xpc_dictionary_get_string(dictionary, key) else {
      return nil
    }
    return String(cString: cString)
  }

  private func assertThrowsNotImplemented(
    _ block: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line
  ) async {
    do {
      try await block()
      XCTFail("expected notImplementedOnDTUHIDTransport to be thrown", file: file, line: line)
    } catch let error as SimulatorHIDError {
      if case .notImplementedOnDTUHIDTransport = error {
        return
      }
      XCTFail("unexpected SimulatorHIDError: \(error)", file: file, line: line)
    } catch {
      XCTFail("unexpected error: \(error)", file: file, line: line)
    }
  }

  private func assertThrowsTouchUnsupported(
    _ block: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line
  ) async {
    do {
      try await block()
      XCTFail("expected touchUnsupportedOnAppleTV to be thrown", file: file, line: line)
    } catch let error as SimulatorHIDError {
      if case .touchUnsupportedOnAppleTV = error {
        return
      }
      XCTFail("unexpected SimulatorHIDError: \(error)", file: file, line: line)
    } catch {
      XCTFail("unexpected error: \(error)", file: file, line: line)
    }
  }
}
