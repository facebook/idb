/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Darwin
@testable import FBSimulatorControl
import Foundation
@_implementationOnly import SimulatorFrameworkBridgeProtocol
import XCTest

/// A streamed response read off a connection whose far end is a socket this test plays the guest on.
final class AXBridgeStreamTests: XCTestCase {

  private var host: Int32 = -1
  private var guest: Int32 = -1
  private var connection: SimulatorFrameworkBridgeConnection?
  private let request = BridgeRequest(command: .accessibility(["verb": .string("quiet")]))

  override func setUpWithError() throws {
    var pair: [Int32] = [-1, -1]
    XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &pair), 0)
    connection = SimulatorFrameworkBridgeConnection(fileDescriptor: pair[0], ownership: .shared(nil))
    host = pair[0]
    guest = pair[1]
    // As `SimulatorFrameworkBridgeConnection.connect` configures a real connection.
    var noSigPipe: Int32 = 1
    setsockopt(host, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
  }

  override func tearDownWithError() throws {
    connection = nil
    if guest >= 0 {
      close(guest)
    }
  }

  private func readGuestRequest() throws -> BridgeRequest {
    try BridgeRequest.decode(SimulatorFrameworkBridgeConnection.readFrame(guest, guest: nil))
  }

  private func writeGuestResult(_ result: BridgeResult, id: String? = nil) throws {
    try SimulatorFrameworkBridgeConnection.writeFrame(guest, BridgeResponse(id: id ?? request.id, result: result).encoded())
  }

  private func event(_ name: String) -> BridgeResult {
    BridgeResult(exitCode: 0, values: [.object(["ok": .bool(true), "event": .string(name)])])
  }

  private func closeGuest() {
    close(guest)
    guest = -1
  }

  func testTheRequestIsSentAndEveryResultIsYieldedUntilTheGuestCloses() async throws {
    let stream = try XCTUnwrap(connection).stream(request)
    XCTAssertEqual(try readGuestRequest(), request)
    try writeGuestResult(event("one"))
    try writeGuestResult(event("two"))
    closeGuest()

    var results: [BridgeResult] = []
    for try await result in stream {
      results.append(result)
    }
    XCTAssertEqual(results, [event("one"), event("two")])
  }

  func testAFrameAnsweringAnotherRequestIsAnError() async throws {
    let stream = try XCTUnwrap(connection).stream(request)
    _ = try readGuestRequest()
    try writeGuestResult(event("one"), id: "someone-else")
    do {
      for try await _ in stream {}
      XCTFail("a frame for another request must not be yielded")
    } catch {
      XCTAssertEqual(error as? BridgeProtocolError, .mismatchedResponse)
    }
  }

  func testAGuestThatClosesMidFrameIsAnError() async throws {
    let stream = try XCTUnwrap(connection).stream(request)
    _ = try readGuestRequest()
    let header: [UInt8] = [0, 0, 0, 9, 0x61]
    XCTAssertEqual(send(guest, header, header.count, 0), header.count)
    closeGuest()
    do {
      for try await _ in stream {}
      XCTFail("a truncated frame must not read as the end of the stream")
    } catch {
      XCTAssertTrue(error.localizedDescription.contains("serve socket closed by peer"), error.localizedDescription)
    }
  }

  // Nothing bounds the silence between frames: a quiet application sends nothing for as long as it stays quiet.
  func testTheReceiveDeadlineIsLiftedForAStream() async throws {
    var deadline = timeval(tv_sec: SimulatorFrameworkBridgeConnection.receiveTimeoutSeconds, tv_usec: 0)
    setsockopt(host, SOL_SOCKET, SO_RCVTIMEO, &deadline, socklen_t(MemoryLayout<timeval>.size))
    let stream = try XCTUnwrap(connection).stream(request)
    _ = try readGuestRequest()

    var lifted = timeval(tv_sec: -1, tv_usec: -1)
    var length = socklen_t(MemoryLayout<timeval>.size)
    XCTAssertEqual(getsockopt(host, SOL_SOCKET, SO_RCVTIMEO, &lifted, &length), 0)
    XCTAssertEqual(lifted.tv_sec, 0)
    XCTAssertEqual(lifted.tv_usec, 0)
    closeGuest()
    for try await _ in stream {}
  }

  // The guest learns the consumer has gone from the connection closing, so it can stop and exit.
  func testAConsumerThatStopsClosesTheConnection() async throws {
    try await consumeFirstResult(of: XCTUnwrap(connection).stream(request))
    XCTAssertNil(try SimulatorFrameworkBridgeConnection.readFrameUnlessClosed(guest, guest: nil))
  }

  // Takes the stream so that it is released on return, as a consumer that stops would release it.
  private func consumeFirstResult(of stream: AsyncThrowingStream<BridgeResult, Error>) async throws {
    _ = try readGuestRequest()
    try writeGuestResult(event("first"))
    for try await result in stream {
      XCTAssertEqual(result, event("first"))
      break
    }
  }

  func testTheTransportYieldsEachResultAsItsAccessibilityResponse() async throws {
    let connection = try XCTUnwrap(connection)
    let transport = SimulatorFrameworkBridgePersistentTransport(
      establish: { throw AXBridgeError.bridgeUnavailable },
      establishStream: { connection }
    )
    let stream = try await transport.stream(.quiescence(pid: 42, busyThresholdMs: nil, quietWindowMs: nil))
    let sent = try readGuestRequest()
    XCTAssertEqual(sent.command, .accessibility(["verb": .string("quiet"), "pid": .integer(42)]))
    try SimulatorFrameworkBridgeConnection.writeFrame(guest, BridgeResponse(request: sent, result: event("one")).encoded())
    closeGuest()

    var envelopes: [NSDictionary] = []
    for try await data in stream {
      envelopes.append(try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? NSDictionary))
    }
    XCTAssertEqual(envelopes, [["ok": true, "event": "one"]])
  }

  // A consumer cancelled mid-silence, as a cancelled RPC is, must still reach the guest so that it stops.
  func testCancellingTheTransportsConsumerClosesTheConnection() async throws {
    var deadline = timeval(tv_sec: 5, tv_usec: 0)
    setsockopt(guest, SOL_SOCKET, SO_RCVTIMEO, &deadline, socklen_t(MemoryLayout<timeval>.size))
    let connection = try XCTUnwrap(connection)
    let transport = SimulatorFrameworkBridgePersistentTransport(
      establish: { throw AXBridgeError.bridgeUnavailable },
      establishStream: { connection }
    )
    let stream = try await transport.stream(.quiescence(pid: nil, busyThresholdMs: nil, quietWindowMs: nil))
    _ = try readGuestRequest()
    let consumer = Task { for try await _ in stream {} }
    consumer.cancel()
    _ = await consumer.result
    XCTAssertNil(try SimulatorFrameworkBridgeConnection.readFrameUnlessClosed(guest, guest: nil))
  }

  func testAQuiescenceRequestCarriesItsTunables() throws {
    let request = AXBridgeRequest.quiescence(pid: 42, busyThresholdMs: 5, quietWindowMs: 7)
    XCTAssertEqual(
      request.payload as NSDictionary,
      ["verb": "quiet", "pid": 42, "busyThresholdMs": 5, "quietWindowMs": 7])
    XCTAssertFalse(request.mayRetry)
  }

  // Absent rather than zero: zero is a real tunable, and an absent one takes the guest's default.
  func testAQuiescenceRequestFollowingTheFrontmostOmitsWhatWasNotGiven() throws {
    let request = AXBridgeRequest.quiescence(pid: nil, busyThresholdMs: nil, quietWindowMs: nil)
    XCTAssertEqual(request.payload as NSDictionary, ["verb": "quiet"])
  }
}
