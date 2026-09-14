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
  // same 0...4 encoding the Indigo builder takes, so one `FBSimulatorHIDEdge` describes both wires.
  func testDigitizerEventCarriesTheEdge() throws {
    for edge in FBSimulatorHIDEdge.allCases {
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
    XCTAssertEqual(FBSimulatorHIDEdge.none.rawValue, 0)
    XCTAssertEqual(FBSimulatorHIDEdge.top.rawValue, 1)
    XCTAssertEqual(FBSimulatorHIDEdge.left.rawValue, 2)
    XCTAssertEqual(FBSimulatorHIDEdge.bottom.rawValue, 3)
    XCTAssertEqual(FBSimulatorHIDEdge.right.rawValue, 4)
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
    let connection = xpc_connection_create("com.facebook.fbsimulatorcontrol.test.dtuhid", nil)
    xpc_connection_set_event_handler(connection) { _ in }
    xpc_connection_resume(connection)
    let transport = SimulatorDTUHIDTransport(
      connection: connection,
      mainScreenSize: CGSize(width: 100, height: 200),
      mainScreenScale: 2.0,
      productFamily: .familyiPhone)
    defer { transport.disconnect() }

    // Apple Pay has no single HID usage (it is a double side-button press), so it stays unimplemented.
    await assertThrowsNotImplemented { try await transport.sendButton(direction: .down, button: .applePay) }
  }

  func testTouchOnAppleTVThrows() async {
    let connection = xpc_connection_create("com.facebook.fbsimulatorcontrol.test.dtuhid", nil)
    xpc_connection_set_event_handler(connection) { _ in }
    xpc_connection_resume(connection)
    let transport = SimulatorDTUHIDTransport(
      connection: connection,
      mainScreenSize: CGSize(width: 100, height: 200),
      mainScreenScale: 2.0,
      productFamily: .familyAppleTV)
    defer { transport.disconnect() }

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
    XCTAssertEqual(FBSimulatorHIDButton.homeButton.identity.consumerUsage?.page, 0x0C)
    XCTAssertEqual(FBSimulatorHIDButton.homeButton.identity.consumerUsage?.code, 0x40)
    XCTAssertEqual(FBSimulatorHIDButton.lock.identity.consumerUsage?.code, 0x30)
    XCTAssertEqual(FBSimulatorHIDButton.sideButton.identity.consumerUsage?.code, 0x30)
    XCTAssertEqual(FBSimulatorHIDButton.siri.identity.consumerUsage?.code, 0xCF)
    XCTAssertEqual(FBSimulatorHIDButton.playPause.identity.consumerUsage?.page, 0x0C)
    XCTAssertEqual(FBSimulatorHIDButton.playPause.identity.consumerUsage?.code, 0xCD)
    XCTAssertEqual(FBSimulatorHIDButton.volumeUp.identity.consumerUsage?.code, 0xE9)
    XCTAssertEqual(FBSimulatorHIDButton.volumeDown.identity.consumerUsage?.code, 0xEA)
    XCTAssertNil(FBSimulatorHIDButton.applePay.identity.consumerUsage)
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

  // MARK: - Send pipeline (envelope shape, no connection needed)

  /// The transport's `encode` wraps any `Encodable` payload in the shared `DTUHIDMessage` envelope —
  /// `messageType` discriminator, `isBarrier` bool, the digitizer `featureIdentifier`, and the typed
  /// `payload`. Every capability rides this shape, so it is pinned here independent of any one model.
  func testEncodeWrapsPayloadInEnvelope() throws {
    struct Probe: Encodable {
      let value: UInt64
    }
    let connection = xpc_connection_create("com.facebook.fbsimulatorcontrol.test.dtuhid", nil)
    xpc_connection_set_event_handler(connection) { _ in }
    xpc_connection_resume(connection)
    let transport = SimulatorDTUHIDTransport(
      connection: connection,
      mainScreenSize: CGSize(width: 100, height: 200),
      mainScreenScale: 2.0,
      productFamily: .familyiPhone)
    defer { transport.disconnect() }

    let message = try transport.encode(messageType: "Probe", payload: Probe(value: 7))

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

  // MARK: - Drain (driven through FBSimulatorHID, injected clock, no daemon)

  func testFlushWithoutAGestureIsANoOp() async throws {
    let recorder = DrainRecorder()
    let hid = makeHID(recorder)

    try await hid.flush()

    let replies = await recorder.replies
    let sleeps = await recorder.sleeps
    XCTAssertEqual(replies, 0)
    XCTAssertEqual(sleeps, [])
  }

  func testFirstGestureSendsBarrierAndTailsAfterReply() async throws {
    let recorder = DrainRecorder()
    let hid = makeHID(recorder)

    try await sendGesture(on: hid)

    let replies = await recorder.replies
    let barriers = await recorder.barriers
    let sleeps = await recorder.sleeps
    XCTAssertEqual(replies, 1)
    let barrier = barriers.first!
    XCTAssertEqual(xpc_get_type(xpc_dictionary_get_value(barrier, "isBarrier")!), XPC_TYPE_BOOL)
    XCTAssertTrue(xpc_dictionary_get_bool(barrier, "isBarrier"))
    XCTAssertEqual(messageString(barrier, "messageType"), "IndigoKeyboardButtonEvent")
    XCTAssertEqual(sleeps, [DTUHIDTiming.replyTail])
  }

  func testLaterGesturesDrainWarm() async throws {
    let recorder = DrainRecorder()
    let hid = makeHID(recorder)

    try await sendGesture(on: hid)
    try await sendGesture(on: hid)

    let replies = await recorder.replies
    let sleeps = await recorder.sleeps
    XCTAssertEqual(replies, 1)
    XCTAssertEqual(sleeps, [DTUHIDTiming.replyTail, DTUHIDTiming.drain])
  }

  func testRedundantFlushIsANoOp() async throws {
    let recorder = DrainRecorder()
    let hid = makeHID(recorder)

    try await sendGesture(on: hid)
    try await hid.flush()

    let sleeps = await recorder.sleeps
    XCTAssertEqual(sleeps, [DTUHIDTiming.replyTail])
  }

  func testConcurrentFirstGesturesShareOneReplyAwait() async throws {
    let recorder = DrainRecorder()
    let hid = makeHID(recorder)

    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask { try await self.sendGesture(on: hid) }
      group.addTask { try await self.sendGesture(on: hid) }
      for try await _ in group {}
    }

    let replies = await recorder.replies
    XCTAssertEqual(replies, 1)
  }

  func testReplyTimeoutFallsBackToLongDrain() async throws {
    let recorder = DrainRecorder()
    let hid = makeHID(recorder, reply: .timeout)

    try await sendGesture(on: hid)

    let replies = await recorder.replies
    let sleeps = await recorder.sleeps
    XCTAssertEqual(replies, 1)
    XCTAssertEqual(sleeps, [DTUHIDTiming.fallbackDrain])
  }

  func testDrainFailurePropagatesAndRetriesCold() async throws {
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
    let replies = await recorder.replies
    let sleeps = await recorder.sleeps
    XCTAssertEqual(replies, 2)
    XCTAssertEqual(sleeps, [DTUHIDTiming.replyTail])
  }

  func testStreamedGesturesDrainOnceOnTheExplicitFlush() async throws {
    let recorder = DrainRecorder()
    let hid = makeHID(recorder)
    hid.flushesAfterEachEvent = false

    try await sendGesture(on: hid)
    try await sendGesture(on: hid)
    try await hid.flush()

    let sleeps = await recorder.sleeps
    XCTAssertEqual(sleeps, [DTUHIDTiming.replyTail])
  }

  func testOverlappingFlushDrainsASendAfterTheColdBarrier() async throws {
    let recorder = DrainRecorder()
    let gate = SleepGate()
    let transport = makeTransport(recorder, gate: gate)

    try await transport.send(
      messageType: "IndigoKeyboardButtonEvent", payload: IndigoKeyboardButtonEvent(usageCode: 0, state: .up))
    let firstFlush = Task { try await transport.flush() }
    await gate.awaitEntry()
    try await transport.send(
      messageType: "IndigoKeyboardButtonEvent", payload: IndigoKeyboardButtonEvent(usageCode: 0, state: .up))

    func flushThenRelease(_ transport: isolated SimulatorDTUHIDTransport) async throws {
      // The release can run on this actor only once flush has suspended on the cold drain.
      let release = Task {
        _ = transport
        await gate.open()
      }
      try await transport.flush()
      await release.value
    }
    try await flushThenRelease(transport)
    try await firstFlush.value
    try await transport.flush()

    let sleeps = await recorder.sleeps
    XCTAssertEqual(sleeps, [DTUHIDTiming.replyTail, DTUHIDTiming.drain])
  }

  func testSendDuringADrainIsDrainedByTheNextFlush() async throws {
    let recorder = DrainRecorder()
    let gate = SleepGate()
    let hid = makeHID(recorder, gate: gate)
    hid.flushesAfterEachEvent = false

    try await sendGesture(on: hid)
    let inFlight = Task { try await hid.flush() }
    await gate.awaitEntry()
    try await sendGesture(on: hid)
    await gate.open()
    try await inFlight.value

    try await hid.flush()

    let sleeps = await recorder.sleeps
    XCTAssertEqual(sleeps, [DTUHIDTiming.replyTail, DTUHIDTiming.drain])
  }

  // MARK: - Helpers

  /// A HID over a DTUHID transport whose drain waits are recorded rather than taken. The connection
  /// names no real service, so writes resolve locally and never reach a daemon.
  private func makeHID(
    _ recorder: DrainRecorder, reply: DrainReply = .answer, gate: SleepGate? = nil
  ) -> FBSimulatorHID {
    FBSimulatorHID(
      transport: .dtuhid(makeTransport(recorder, reply: reply, gate: gate)),
      purple: SimulatorPurpleHIDTransport(simulator: nil),
      notification: SimulatorDarwinNotificationTransport(simulator: nil),
      simulator: nil)
  }

  private func makeTransport(
    _ recorder: DrainRecorder, reply: DrainReply = .answer, gate: SleepGate? = nil
  ) -> SimulatorDTUHIDTransport {
    let connection = xpc_connection_create("com.facebook.fbsimulatorcontrol.test.dtuhid", nil)
    xpc_connection_set_event_handler(connection) { _ in }
    xpc_connection_resume(connection)
    let transport = SimulatorDTUHIDTransport(
      connection: connection,
      mainScreenSize: CGSize(width: 100, height: 200),
      mainScreenScale: 2.0,
      productFamily: .familyiPhone,
      clock: recordingClock(recorder, reply: reply, gate: gate))
    addTeardownBlock { transport.disconnect() }
    return transport
  }

  /// One inert keypress. Usage `0` is "no event indicated", so a guest would ignore it even if one
  /// were listening.
  private func sendGesture(on hid: FBSimulatorHID) async throws {
    try await hid.send(
      event: .keyboard(direction: .up, keyCode: 0),
      logger: FBControlCoreGlobalConfiguration.defaultLogger)
  }

  private enum DrainReply {
    case answer
    case timeout
  }

  private enum DrainFailure: Error {
    case injected
  }

  private actor DrainRecorder {
    var sleeps: [Duration] = []
    var replies = 0
    var barriers: [xpc_object_t] = []
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

    func reply(_ message: xpc_object_t) {
      replies += 1
      barriers.append(message)
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

  private func recordingClock(
    _ recorder: DrainRecorder, reply: DrainReply = .answer, gate: SleepGate? = nil
  ) -> DTUHIDDrainClock {
    DTUHIDDrainClock(
      sleep: { duration in
        await gate?.enter()
        try await recorder.sleep(duration)
      },
      awaitBarrierReply: { _, message in
        await recorder.reply(message)
        if reply == .timeout {
          throw DTUHIDDrainTimeout.expired
        }
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
