/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Darwin
import FBSimulatorBridgeProtocol
@testable import FBSimulatorControl
@testable import FBSimulatorServices
import Foundation
import Testing

/// A streamed response read off a connection whose far end is a socket this test plays the guest on.
@Suite
final class AXBridgeStreamTests {

  private var host: Int32 = -1
  private var guest: Int32 = -1
  private var connection: SimulatorFrameworkBridgeConnection?
  private let request = BridgeRequest(command: .accessibility(.quiescence(pid: nil, busyThresholdMs: nil, quietWindowMs: nil)))

  init() {
    var pair: [Int32] = [-1, -1]
    #expect(socketpair(AF_UNIX, SOCK_STREAM, 0, &pair) == 0)
    connection = SimulatorFrameworkBridgeConnection(fileDescriptor: pair[0], ownership: .shared(nil))
    host = pair[0]
    guest = pair[1]
    // As `SimulatorFrameworkBridgeConnection.connect` configures a real connection.
    var noSigPipe: Int32 = 1
    setsockopt(host, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
  }

  deinit {
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
    BridgeResult(exitCode: 0, accessibility: .quiescence(.touchesCompleted(pid: name == "one" ? 1 : 2)))
  }

  private func closeGuest() {
    close(guest)
    guest = -1
  }

  @Test
  func theRequestIsSentAndEveryResultIsYieldedUntilTheGuestCloses() async throws {
    let stream = try #require(connection).stream(request)
    #expect(try readGuestRequest() == request)
    try writeGuestResult(event("one"))
    try writeGuestResult(event("two"))
    closeGuest()

    var results: [BridgeResult] = []
    for try await result in stream {
      results.append(result)
    }
    #expect(results == [event("one"), event("two")])
  }

  @Test
  func aFrameAnsweringAnotherRequestIsAnError() async throws {
    let stream = try #require(connection).stream(request)
    _ = try readGuestRequest()
    try writeGuestResult(event("one"), id: "someone-else")
    do {
      for try await _ in stream {}
      Issue.record("a frame for another request must not be yielded")
    } catch {
      #expect(error as? BridgeProtocolError == .mismatchedResponse)
    }
  }

  @Test
  func aGuestThatClosesMidFrameIsAnError() async throws {
    let stream = try #require(connection).stream(request)
    _ = try readGuestRequest()
    let header: [UInt8] = [0, 0, 0, 9, 0x61]
    #expect(send(guest, header, header.count, 0) == header.count)
    closeGuest()
    do {
      for try await _ in stream {}
      Issue.record("a truncated frame must not read as the end of the stream")
    } catch {
      #expect(error.localizedDescription.contains("serve socket closed by peer"), "\(error.localizedDescription)")
    }
  }

  // Nothing bounds the silence between frames: a quiet application sends nothing for as long as it stays quiet.
  @Test
  func theReceiveDeadlineIsLiftedForAStream() async throws {
    var deadline = timeval(tv_sec: SimulatorFrameworkBridgeConnection.receiveTimeoutSeconds, tv_usec: 0)
    setsockopt(host, SOL_SOCKET, SO_RCVTIMEO, &deadline, socklen_t(MemoryLayout<timeval>.size))
    let stream = try #require(connection).stream(request)
    _ = try readGuestRequest()

    var lifted = timeval(tv_sec: -1, tv_usec: -1)
    var length = socklen_t(MemoryLayout<timeval>.size)
    #expect(getsockopt(host, SOL_SOCKET, SO_RCVTIMEO, &lifted, &length) == 0)
    #expect(lifted.tv_sec == 0)
    #expect(lifted.tv_usec == 0)
    closeGuest()
    for try await _ in stream {}
  }

  // The guest learns the consumer has gone from the connection closing, so it can stop and exit.
  @Test
  func aConsumerThatStopsClosesTheConnection() async throws {
    try await consumeFirstResult(of: #require(connection).stream(request))
    #expect(try SimulatorFrameworkBridgeConnection.readFrameUnlessClosed(guest, guest: nil) == nil)
  }

  // Takes the stream so that it is released on return, as a consumer that stops would release it.
  private func consumeFirstResult(of stream: AsyncThrowingStream<BridgeResult, Error>) async throws {
    _ = try readGuestRequest()
    try writeGuestResult(event("first"))
    for try await result in stream {
      #expect(result == event("first"))
      break
    }
  }

  @Test
  func theTransportYieldsEachResultAsItsAccessibilityResponse() async throws {
    let connection = try #require(connection)
    let transport = SimulatorFrameworkBridgePersistentTransport(connector: StreamOnlyConnector(stream: connection))
    let stream = try await transport.stream(.quiescence(pid: 42, busyThresholdMs: nil, quietWindowMs: nil))
    let sent = try readGuestRequest()
    #expect(sent.command == .accessibility(.quiescence(pid: 42, busyThresholdMs: nil, quietWindowMs: nil)))
    try SimulatorFrameworkBridgeConnection.writeFrame(guest, BridgeResponse(request: sent, result: event("one")).encoded())
    closeGuest()

    var answers: [BridgeAXAnswer] = []
    for try await answer in stream {
      answers.append(answer)
    }
    #expect(answers == [.quiescence(.touchesCompleted(pid: 1))])
  }

  // A consumer cancelled mid-silence, as a cancelled RPC is, must still reach the guest so that it stops.
  @Test
  func cancellingTheTransportsConsumerClosesTheConnection() async throws {
    var deadline = timeval(tv_sec: 5, tv_usec: 0)
    setsockopt(guest, SOL_SOCKET, SO_RCVTIMEO, &deadline, socklen_t(MemoryLayout<timeval>.size))
    let connection = try #require(connection)
    let transport = SimulatorFrameworkBridgePersistentTransport(connector: StreamOnlyConnector(stream: connection))
    let stream = try await transport.stream(.quiescence(pid: nil, busyThresholdMs: nil, quietWindowMs: nil))
    _ = try readGuestRequest()
    let consumer = Task { for try await _ in stream {} }
    consumer.cancel()
    _ = await consumer.result
    #expect(try SimulatorFrameworkBridgeConnection.readFrameUnlessClosed(guest, guest: nil) == nil)
  }

  @Test
  func aQuiescenceRequestCarriesItsTunables() throws {
    let request = AXBridgeRequest.quiescence(pid: 42, busyThresholdMs: 5, quietWindowMs: 7)
    #expect(
      request.payload as NSDictionary == ["verb": "quiet", "pid": 42, "busyThresholdMs": 5, "quietWindowMs": 7])
    #expect(!request.mayRetry)
  }

  // Absent rather than zero: zero is a real tunable, and an absent one takes the guest's default.
  @Test
  func aQuiescenceRequestFollowingTheFrontmostOmitsWhatWasNotGiven() throws {
    let request = AXBridgeRequest.quiescence(pid: nil, busyThresholdMs: nil, quietWindowMs: nil)
    #expect(request.payload as NSDictionary == ["verb": "quiet"])
  }
}

/// Connects only for streams, always to `stream`.
private struct StreamOnlyConnector: BridgeConnector {
  let stream: SimulatorFrameworkBridgeConnection

  func connection() async throws -> any BridgeConnection {
    throw AXBridgeError.bridgeUnavailable
  }

  func streamConnection() async throws -> SimulatorFrameworkBridgeConnection {
    stream
  }
}
