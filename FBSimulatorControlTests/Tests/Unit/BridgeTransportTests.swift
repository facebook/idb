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

func decodedBridgeAXArguments(_ request: AXBridgeRequest) throws -> [String: Any] {
  let arguments = try request.arguments
  XCTAssertEqual(arguments.count, 2)
  XCTAssertEqual(arguments.first, "rpc")
  let decoded = try BridgeRequest.decode(Data(arguments[1].utf8))
  guard case let .accessibility(parameters) = decoded.command else {
    XCTFail("expected accessibility command")
    return [:]
  }
  return parameters.mapValues(\.foundationValue)
}

final class BridgeTransportTests: XCTestCase {
  func testFailedConnectionRejectsLaterMutationsBeforeWriting() async throws {
    var descriptors: [Int32] = [-1, -1]
    XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors), 0)
    let peer = descriptors[1]
    defer { close(peer) }
    let connection = SimulatorFrameworkBridgeConnection(fileDescriptor: descriptors[0], ownership: .shared(nil))
    let request = BridgeRequest(command: .clearPhotos)
    let data = try request.encoded()
    XCTAssertEqual(shutdown(peer, SHUT_WR), 0)

    do {
      _ = try await connection.roundTrip(data)
      XCTFail("peer EOF must fail the first request")
    } catch {
      XCTAssertEqual(error.localizedDescription, AXBridgeError.guestFailure("serve socket closed by peer").localizedDescription)
    }
    XCTAssertEqual(try SimulatorFrameworkBridgeConnection.readFrame(peer, guest: nil), data)

    do {
      _ = try await connection.roundTrip(data)
      XCTFail("failed connections must reject later requests")
    } catch {
      XCTAssertEqual(error.localizedDescription, AXBridgeError.guestFailure("serve socket closed by peer").localizedDescription)
    }
    var byte: UInt8 = 0
    XCTAssertEqual(recv(peer, &byte, 1, MSG_DONTWAIT), -1)
    XCTAssertEqual(errno, EAGAIN, "a second mutation must never reach the peer")
  }

  private func validationSocketPair() throws -> (SimulatorFrameworkBridgeConnection, Int32) {
    var descriptors: [Int32] = [-1, -1]
    guard socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0 else {
      throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
    for descriptor in descriptors {
      var timeout = timeval(tv_sec: 5, tv_usec: 0)
      var noSigPipe: Int32 = 1
      XCTAssertEqual(setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size)), 0)
      XCTAssertEqual(setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size)), 0)
      XCTAssertEqual(setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size)), 0)
    }
    return (SimulatorFrameworkBridgeConnection(fileDescriptor: descriptors[0], ownership: .shared(nil)), descriptors[1])
  }

  func testInvalidFramedResponsesRejectOutstandingMutationsBeforeWriting() async throws {
    let firstRequest = BridgeRequest(command: .clearPhotos, id: "first")
    let secondRequest = BridgeRequest(command: .clearContacts, id: "second")
    let firstData = try firstRequest.encoded()
    let secondData = try secondRequest.encoded()
    let cases: [(Data, BridgeProtocolError?)] = [
      (Data("{".utf8), nil),
      (Data(#"{"version":2,"id":"first","result":{"exitCode":0,"values":[]}}"#.utf8), .unsupportedVersion(2)),
      (try BridgeResponse(id: "wrong", result: BridgeResult(exitCode: 0)).encoded(), .mismatchedResponse),
    ]
    for (payload, expectedError) in cases {
      let (connection, peer) = try validationSocketPair()
      defer {
        shutdown(peer, SHUT_RDWR)
        close(peer)
      }
      let first = Task.detached { try await connection.roundTrip(firstData) }
      XCTAssertEqual(try SimulatorFrameworkBridgeConnection.readFrame(peer, guest: nil), firstData)
      let second = Task.detached { try await connection.roundTrip(secondData) }
      try SimulatorFrameworkBridgeConnection.writeFrame(peer, payload)
      XCTAssertEqual(shutdown(peer, SHUT_WR), 0)

      for task in [first, second] {
        do {
          _ = try await task.value
          XCTFail("an invalid response must fail its request and subsequent requests on the connection")
        } catch {
          if let expectedError {
            XCTAssertEqual(error as? BridgeProtocolError, expectedError)
          } else {
            XCTAssertTrue(error is DecodingError, "unexpected error: \(error)")
          }
        }
      }
      withExtendedLifetime(connection) {
        var byte: UInt8 = 0
        XCTAssertEqual(recv(peer, &byte, 1, MSG_DONTWAIT), -1)
        XCTAssertEqual(errno, EAGAIN, "the second mutation must not reach the invalid connection")
      }
    }
  }

  func testMatchingServiceFailuresKeepTheConnectionUsable() async throws {
    let (connection, peer) = try validationSocketPair()
    defer {
      shutdown(peer, SHUT_RDWR)
      close(peer)
    }
    let requests = [
      BridgeRequest(command: .clearPhotos, id: "failed"),
      BridgeRequest(command: .clearContacts, id: "next"),
    ]
    let results = [
      BridgeResult(exitCode: 23, values: [.string("partial")]),
      BridgeResult(exitCode: 0),
    ]
    for (request, result) in zip(requests, results) {
      try SimulatorFrameworkBridgeConnection.writeFrame(peer, BridgeResponse(request: request, result: result).encoded())
      let response = try await connection.roundTrip(request.encoded())
      XCTAssertEqual(try BridgeResponse.decode(response, for: request).result, result)
      XCTAssertEqual(try SimulatorFrameworkBridgeConnection.readFrame(peer, guest: nil), try request.encoded())
    }
  }

  func testOneshotUsesTypedArgumentsAndPreservesPartialFailure() async throws {
    let request = BridgeRequest(command: .notifications(.delivered(bundleID: "app")), id: "oneshot")
    let result = BridgeResult(exitCode: 23, values: [.object(["id": .string("one")])])
    let transport = SimulatorFrameworkBridgeOneshotTransport { arguments in
      XCTAssertEqual(arguments, try request.arguments)
      return InSimulatorToolOutput(stdout: try BridgeResponse(request: request, result: result).encoded(), stderr: Data(), exitCode: 23)
    }
    let response = try await transport.send(request)
    XCTAssertEqual(response, result)
  }

  func testOneshotRejectsMismatchedResponseAndProcessStatus() async throws {
    let request = BridgeRequest(command: .clearPhotos, id: "right")
    for output in [
      InSimulatorToolOutput(stdout: try BridgeResponse(request: BridgeRequest(command: .clearPhotos, id: "wrong"), result: BridgeResult(exitCode: 0)).encoded(), stderr: Data(), exitCode: 0),
      InSimulatorToolOutput(stdout: try BridgeResponse(request: request, result: BridgeResult(exitCode: 0)).encoded(), stderr: Data(), exitCode: 9),
      InSimulatorToolOutput(stdout: Data(), stderr: Data("failure".utf8), exitCode: 1),
    ] {
      let transport = SimulatorFrameworkBridgeOneshotTransport { _ in output }
      do {
        _ = try await transport.send(request)
        XCTFail("invalid response accepted")
      } catch {
        XCTAssertTrue(error is BridgeProtocolError || error is AXBridgeError)
      }
    }
  }

  func testAccessibilityFailureWithoutAResponseCarriesTheGuestDiagnostic() throws {
    XCTAssertThrowsError(try BridgeResult(exitCode: 1, error: "could not decode accessibility output").accessibilityData()) { error in
      guard case let .guestFailure(message)? = error as? AXBridgeError else { return XCTFail("\(error)") }
      XCTAssertEqual(message, "could not decode accessibility output")
    }
    XCTAssertThrowsError(try BridgeResult(exitCode: 1).accessibilityData()) { error in
      guard case let .guestFailure(message)? = error as? AXBridgeError else { return XCTFail("\(error)") }
      XCTAssertEqual(message, "accessibility returned 0 values instead of one response object")
    }
  }

  func testMutationIsNeverReplayedAfterAnAmbiguousFailure() async throws {
    for command: BridgeCommand in [.clearContacts, .dns(.clear), .accessibility(["verb": .string("perform"), "automationMode": .bool(true)])] {
      let connection = RecordingBridgeConnection(failures: 1)
      let factory = RecordingBridgeFactory([connection])
      let transport = SimulatorFrameworkBridgePersistentTransport { try await factory.connect() }
      do {
        _ = try await transport.send(BridgeRequest(command: command))
        XCTFail("expected dropped response")
      } catch {
        XCTAssertEqual(error as? BridgeTestFailure, .dropped)
      }
      let calls = await connection.commands
      let connections = await factory.count
      XCTAssertEqual(calls, [command])
      XCTAssertEqual(connections, 1)
    }
  }

  func testReadRetriesOnceAndShutdownDiscardsARetainedConnection() async throws {
    let connection = RecordingBridgeConnection(failures: 1)
    let factory = RecordingBridgeFactory([connection])
    let transport = SimulatorFrameworkBridgePersistentTransport { try await factory.connect() }
    _ = try await transport.send(BridgeRequest(command: .dns(.list)))
    let afterRetry = await factory.count
    XCTAssertEqual(afterRetry, 2)
    _ = try await transport.send(BridgeRequest(command: .shutdown))
    _ = try await transport.send(BridgeRequest(command: .clearPhotos))
    let connections = await factory.count
    let calls = await connection.commands
    XCTAssertEqual(connections, 3)
    XCTAssertEqual(calls, [.dns(.list), .dns(.list), .shutdown, .clearPhotos])
  }

  func testPersistentRejectsWrongIdentityWithoutReplayingAMutation() async throws {
    let connection = RecordingBridgeConnection(failures: 0, wrongID: true)
    let factory = RecordingBridgeFactory([connection])
    let transport = SimulatorFrameworkBridgePersistentTransport { try await factory.connect() }
    do {
      _ = try await transport.send(BridgeRequest(command: .clearContacts))
      XCTFail("wrong response identity accepted")
    } catch {
      XCTAssertEqual(error as? BridgeProtocolError, .mismatchedResponse)
    }
    let commands = await connection.commands
    XCTAssertEqual(commands, [.clearContacts])
  }

  func testReadRetryIsBoundedAndReportedFailuresAreNotReplayed() async throws {
    let dropped = RecordingBridgeConnection(failures: 2)
    let factory = RecordingBridgeFactory([dropped])
    let transport = SimulatorFrameworkBridgePersistentTransport { try await factory.connect() }
    do {
      _ = try await transport.send(BridgeRequest(command: .dns(.list)))
      XCTFail("two dropped responses must fail")
    } catch {
      XCTAssertEqual(error as? BridgeTestFailure, .dropped)
    }
    let connections = await factory.count
    XCTAssertEqual(connections, 2)

    let failure = BridgeResult(exitCode: 23, values: [.string("partial")])
    let reported = RecordingBridgeConnection(failures: 0, result: failure)
    let responseTransport = SimulatorFrameworkBridgePersistentTransport { reported }
    let response = try await responseTransport.send(BridgeRequest(command: .dns(.list)))
    XCTAssertEqual(response, failure)
    let commands = await reported.commands
    XCTAssertEqual(commands, [.dns(.list)])
  }

  func testAnOldFailureCannotDiscardANewerConnection() async throws {
    let firstStarted = expectation(description: "first request started")
    let secondStarted = expectation(description: "second request started")
    let old = GatedBridgeConnection(firstStarted: firstStarted, secondStarted: secondStarted)
    let next = RecordingBridgeConnection(failures: 0)
    let factory = RecordingBridgeFactory([old, next])
    let transport = SimulatorFrameworkBridgePersistentTransport { try await factory.connect() }
    let first = Task { try await transport.send(BridgeRequest(command: .clearPhotos, id: "first")) }
    await fulfillment(of: [firstStarted], timeout: 5)
    let second = Task { try await transport.send(BridgeRequest(command: .clearPhotos, id: "second")) }
    await fulfillment(of: [secondStarted], timeout: 5)
    await old.completeFirst()
    _ = try await first.value
    _ = try await transport.send(BridgeRequest(command: .clearPhotos, id: "third"))
    await old.failSecond()
    do {
      _ = try await second.value
      XCTFail("expected failure")
    } catch {
      XCTAssertEqual(error as? BridgeTestFailure, .dropped)
    }
    _ = try await transport.send(BridgeRequest(command: .clearPhotos, id: "fourth"))
    let connections = await factory.count
    XCTAssertEqual(connections, 2)
  }
}

private enum BridgeTestFailure: Error, Equatable { case dropped }

private actor RecordingBridgeConnection: BridgeConnection {
  nonisolated let mayBeHeldBetweenRoundTrips = true
  private var failures: Int
  private let wrongID: Bool
  private let result: BridgeResult
  private(set) var commands: [BridgeCommand] = []

  init(failures: Int, wrongID: Bool = false, result: BridgeResult = BridgeResult(exitCode: 0)) {
    self.failures = failures
    self.wrongID = wrongID
    self.result = result
  }

  func roundTrip(_ requestData: Data) async throws -> Data {
    let request = try BridgeRequest.decode(requestData)
    commands.append(request.command)
    if failures > 0 {
      failures -= 1
      throw BridgeTestFailure.dropped
    }
    return try BridgeResponse(id: wrongID ? "wrong" : request.id, result: result).encoded()
  }
}

private actor RecordingBridgeFactory {
  let connections: [any BridgeConnection]
  private(set) var count = 0
  init(_ connections: [any BridgeConnection]) { self.connections = connections }
  func connect() throws -> any BridgeConnection {
    defer { count += 1 }
    return connections[min(count, connections.count - 1)]
  }
}

private actor GatedBridgeConnection: BridgeConnection {
  nonisolated let mayBeHeldBetweenRoundTrips = false
  let firstStarted: XCTestExpectation
  let secondStarted: XCTestExpectation
  private var first: (BridgeRequest, CheckedContinuation<Data, Error>)?
  private var second: CheckedContinuation<Data, Error>?

  init(firstStarted: XCTestExpectation, secondStarted: XCTestExpectation) {
    self.firstStarted = firstStarted
    self.secondStarted = secondStarted
  }

  func roundTrip(_ requestData: Data) async throws -> Data {
    let request = try BridgeRequest.decode(requestData)
    return try await withCheckedThrowingContinuation { continuation in
      if request.id == "first" {
        first = (request, continuation)
        firstStarted.fulfill()
      } else {
        second = continuation
        secondStarted.fulfill()
      }
    }
  }

  func completeFirst() {
    guard let first else { return }
    self.first = nil
    first.1.resume(with: Result { try BridgeResponse(request: first.0, result: BridgeResult(exitCode: 0)).encoded() })
  }

  func failSecond() {
    second?.resume(throwing: BridgeTestFailure.dropped)
    second = nil
  }
}
