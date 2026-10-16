/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import AccessibilityPlatformTranslation
import FBControlCore
@testable import FBSimulatorAX
@testable import FBSimulatorControl
import XCTest
@preconcurrency import XPC

final class AXTranslationTransportTests: XCTestCase {

  private static func request(type: UInt64 = 5, clientType: UInt64 = 4) throws -> AXPTranslatorRequest {
    let request = try XCTUnwrap((NSClassFromString("AXPTranslatorRequest") as? NSObject.Type)?.init() as? AXPTranslatorRequest)
    request.requestType = type
    request.clientType = clientType
    request.parameters = ["attributes": [45, 33]]
    return request
  }

  private static var emptyResponse: AXPTranslatorResponse {
    AXPTranslatorResponse.empty() as! AXPTranslatorResponse
  }

  /// A reply as the bridge sends one: the archived response in the service's envelope.
  private static func reply(with response: AXPTranslatorResponse) throws -> xpc_object_t {
    let data = try NSKeyedArchiver.archivedData(withRootObject: response, requiringSecureCoding: true)
    return AXTranslationWire.envelope(className: "AXPTranslatorResponse", key: AXTranslationWire.responseKey, data: data)
  }

  private static func decodedRequest(_ message: xpc_object_t) throws -> AXPTranslatorRequest {
    let data = try XCTUnwrap(
      AXTranslationWire.payload(of: message, className: "AXPTranslatorRequest", key: AXTranslationWire.requestKey))
    return try XCTUnwrap(NSKeyedUnarchiver.unarchivedObject(ofClass: AXPTranslatorRequest.self, from: data))
  }

  // MARK: - Wire

  func testARequestIsArchivedIntoTheServiceEnvelope() throws {
    let message = try XCTUnwrap(AXTranslationWire.message(for: Self.request()))
    let decoded = try Self.decodedRequest(message)
    XCTAssertEqual(decoded.requestType, 5)
    XCTAssertEqual(decoded.clientType, 4)
    XCTAssertEqual(decoded.parameters as NSDictionary?, ["attributes": [45, 33]] as NSDictionary)
  }

  func testAResponseIsReadFromTheServiceEnvelope() throws {
    XCTAssertNotNil(AXTranslationWire.response(from: try Self.reply(with: Self.emptyResponse)))
  }

  func testAReplyNamingAnotherClassIsNotAResponse() throws {
    let data = try NSKeyedArchiver.archivedData(withRootObject: Self.emptyResponse, requiringSecureCoding: true)
    let reply = AXTranslationWire.envelope(className: "AXPTranslatorRequest", key: AXTranslationWire.responseKey, data: data)
    XCTAssertNil(AXTranslationWire.response(from: reply))
  }

  // MARK: - Transport

  private let services = SyntheticXPCServices()

  private var transport: CoreSimulatorBridgeAXTranslationTransport {
    CoreSimulatorBridgeAXTranslationTransport(connector: services.connector)
  }

  func testARequestReachesTheServiceAndItsReplyIsTheResponse() async throws {
    let peer = services.register(CoreSimulatorBridgeAXTranslationTransport.serviceName, respond: SyntheticXPCPeer.replying(try Self.reply(with: Self.emptyResponse)))
    let transport = self.transport

    XCTAssertNotNil(transport.send(try Self.request(), timeout: 5))

    let received = await peer.received(atLeast: 1)
    XCTAssertEqual(try Self.decodedRequest(try XCTUnwrap(received.first)).clientType, 4)
  }

  func testRequestsShareOneConnection() throws {
    let peer = services.register(CoreSimulatorBridgeAXTranslationTransport.serviceName, respond: SyntheticXPCPeer.replying(try Self.reply(with: Self.emptyResponse)))
    let transport = self.transport

    for _ in 0..<3 {
      XCTAssertNotNil(transport.send(try Self.request(), timeout: 5))
    }
    XCTAssertEqual(peer.connections, 1)
    XCTAssertEqual(services.lookups.count, 1)
  }

  func testAnUnansweredRequestYieldsNothingWhenItsTimeoutPasses() throws {
    services.register(CoreSimulatorBridgeAXTranslationTransport.serviceName, respond: SyntheticXPCPeer.silent)
    XCTAssertNil(transport.send(try Self.request(), timeout: 0.2))
  }

  func testARequestWhoseReplyComesLateIsCountedUntilItArrives() async throws {
    let reply = try Self.reply(with: Self.emptyResponse)
    let late = DispatchSemaphore(value: 0)
    services.register(CoreSimulatorBridgeAXTranslationTransport.serviceName) { request in
      DispatchQueue.global().async {
        late.wait()
        request.reply(reply)
      }
    }
    let transport = self.transport

    XCTAssertNil(transport.send(try Self.request(), timeout: 0.1))
    XCTAssertEqual(transport.abandonedRequests, 1, "the service still owes the abandoned request its answer")

    late.signal()
    try await pollUntilTrue(
      on: .global(), interval: 0.01, deadline: PollDeadline(timeout: 5, waitingFor: "the late answer to arrive")
    ) { transport.abandonedRequests == 0 }
  }

  func testACoreSimulatorRequestWhoseAnswerComesLateIsCountedUntilItArrives() async throws {
    let device = SimDeviceAccessibilityDouble()
    let response = Self.emptyResponse
    let late = DispatchSemaphore(value: 0)
    device.accessibilityResponseHandler = { _, respond in
      DispatchQueue.global().async {
        late.wait()
        respond(response)
      }
    }
    let transport = CoreSimulatorAXTranslationTransport(device: SimulatorTestSupport.testableSimulator(withDevice: device).device)

    XCTAssertNil(transport.send(try Self.request(), timeout: 0.1))
    XCTAssertEqual(transport.abandonedRequests, 1, "CoreSimulator's client still owes the abandoned request its answer")

    late.signal()
    try await pollUntilTrue(
      on: .global(), interval: 0.01, deadline: PollDeadline(timeout: 5, waitingFor: "the late answer to arrive")
    ) { transport.abandonedRequests == 0 }
  }

  func testAServiceTheSimulatorDoesNotVendFailsToConnect() throws {
    let transport = self.transport
    XCTAssertThrowsError(try transport.connect())
    XCTAssertNil(transport.send(try Self.request(), timeout: 1))
  }

  func testTheServiceIsLookedUpAgainAfterTheBridgeGoesAway() throws {
    let reply = try Self.reply(with: Self.emptyResponse)
    let first = services.register(CoreSimulatorBridgeAXTranslationTransport.serviceName, respond: SyntheticXPCPeer.replying(reply))
    let transport = self.transport
    XCTAssertNotNil(transport.send(try Self.request(), timeout: 5))

    // CoreSimulatorBridge restarting: the old service goes away for good and a new one takes its name.
    first.invalidate()
    let second = services.register(CoreSimulatorBridgeAXTranslationTransport.serviceName, respond: SyntheticXPCPeer.replying(reply))

    // The first send after the restart may still be answered by XPC on the old connection's behalf.
    let answered = try (0..<3).contains { _ in transport.send(try Self.request(), timeout: 5) != nil }
    XCTAssertTrue(answered, "a send after the restart reaches the new service")
    XCTAssertEqual(second.connections, 1)
  }
}

// MARK: - Choosing a transport

final class AXTranslationTransportSelectionTests: XCTestCase {

  private let services = SyntheticXPCServices()

  func testTheBridgeIsPreferredWhenItsServiceCanBeReached() {
    services.register(CoreSimulatorBridgeAXTranslationTransport.serviceName, respond: SyntheticXPCPeer.silent)
    let transport = SimulatorAccessibilityCommands.preferredTransport(connector: services.connector, logger: nil) {
      AXTranslationTransportDouble()
    }
    XCTAssertTrue(transport is CoreSimulatorBridgeAXTranslationTransport)
  }

  func testCoreSimulatorsClientIsTheFallbackWhenTheServiceCannotBeReached() {
    let transport = SimulatorAccessibilityCommands.preferredTransport(connector: services.connector, logger: nil) {
      AXTranslationTransportDouble()
    }
    XCTAssertTrue(transport is AXTranslationTransportDouble)
    XCTAssertEqual(services.lookups, [CoreSimulatorBridgeAXTranslationTransport.serviceName])
  }

  func testAnUnbootedSimulatorFallsBackWithoutLookingUp() {
    services.simulatorState = .shutdown
    let transport = SimulatorAccessibilityCommands.preferredTransport(connector: services.connector, logger: nil) {
      AXTranslationTransportDouble()
    }
    XCTAssertTrue(transport is AXTranslationTransportDouble)
  }
}
