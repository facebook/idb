/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import Foundation
import XCTest
@preconcurrency import XPC
import os

private let service = "com.example.coredevice.feature.updates"

private func event(_ value: Int64) -> xpc_object_t {
  SimulatorCoreDevice.dictionary(["value": xpc_int64_create(value)])
}

private let completion = SimulatorCoreDevice.dictionary(["CoreDevice.output": xpc_dictionary_create(nil, nil, 0)])

/// What a synthetic provider does after its last push has been acknowledged.
private enum UpdatesEnd {
  case complete
  case fail
  case interrupt
  case stayOpen
}

/// A provider pushing `events`, each once the client has acknowledged the last. Every
/// acknowledgement's cancellation flag is kept.
private final class UpdatesProvider: Sendable {
  let services = SyntheticXPCServices()
  let peer: SyntheticXPCPeer
  private let acknowledged = OSAllocatedUnfairLock(initialState: [Bool]())

  init(events: [xpc_object_t], then end: UpdatesEnd) {
    let acknowledged = acknowledged
    peer = services.register(service) { request in
      @Sendable func push(_ index: Int) {
        guard index < events.count else {
          switch end {
          case .complete: request.reply(completion)
          case .fail:
            request.reply(
              SimulatorCoreDevice.dictionary([
                "CoreDevice.error": SimulatorCoreDevice.dictionary(["domain": xpc_string_create("com.example"), "code": xpc_int64_create(9)])
              ]))
          case .interrupt: request.interrupt()
          case .stayOpen: break
          }
          return
        }
        request.push(events[index]) { acknowledgement in
          guard xpc_get_type(acknowledgement) == XPC_TYPE_DICTIONARY else { return }
          acknowledged.withLock { $0.append(xpc_dictionary_get_bool(acknowledgement, SimulatorCoreDevice.cancellationKey)) }
          push(index + 1)
        }
      }
      push(0)
    }
  }

  var acknowledgements: [Bool] {
    acknowledged.withLock { $0 }
  }
}

final class CoreDeviceSubscriptionTests: XCTestCase {

  /// Reads each event's value, skipping negative ones.
  private func subscribe(to services: SyntheticXPCServices, timeout: DispatchTimeInterval = .seconds(5)) throws -> AsyncThrowingStream<Int64, Error> {
    let request = SimulatorCoreDevice.dictionary(["CoreDevice.actionIdentifier": xpc_string_create("com.example.action")])
    return CoreDeviceSession<Int64>(channel: try services.channel(to: service), timeout: timeout).subscribe(request) { event in
      let value = xpc_dictionary_get_int64(event, "value")
      return value < 0 ? nil : value
    }
  }

  func testYieldsEachPushUntilTheProviderFinishesWithoutAskingItToStop() async throws {
    let provider = UpdatesProvider(events: [event(1), event(-1), event(2)], then: .complete)
    var values: [Int64] = []
    for try await value in try subscribe(to: provider.services) {
      values.append(value)
    }
    XCTAssertEqual(values, [1, 2])
    XCTAssertEqual(provider.acknowledgements, [false, false, false])
  }

  func testAProviderErrorInTheFinalReplyFails() async throws {
    let provider = UpdatesProvider(events: [event(1)], then: .fail)
    var values: [Int64] = []
    do {
      for try await value in try subscribe(to: provider.services) {
        values.append(value)
      }
      XCTFail("Expected provider error")
    } catch {
      guard case let SimulatorCoreDeviceError.unavailable(detail) = error else { return XCTFail("Unexpected error: \(error)") }
      XCTAssertEqual(detail, "com.example (9)")
    }
    XCTAssertEqual(values, [1])
  }

  func testPeerLossFails() async throws {
    let provider = UpdatesProvider(events: [event(1)], then: .interrupt)
    do {
      for try await _ in try subscribe(to: provider.services) {}
      XCTFail("Expected connection error")
    } catch {
      guard case SimulatorCoreDeviceError.unavailable = error else { return XCTFail("Unexpected error: \(error)") }
    }
  }

  func testStoppingIterationClosesTheConnection() async throws {
    let provider = UpdatesProvider(events: [event(1)], then: .stayOpen)
    for try await value in try subscribe(to: provider.services) {
      XCTAssertEqual(value, 1)
      break
    }
    let closed = await provider.peer.closed(atLeast: 1)
    XCTAssertEqual(closed, 1)
  }

  func testNoPushBeforeTheDeadlineFails() async throws {
    let services = SyntheticXPCServices()
    let peer = services.register(service, respond: SyntheticXPCPeer.silent)
    do {
      for try await _ in try subscribe(to: services, timeout: .milliseconds(100)) {}
      XCTFail("Expected a timeout")
    } catch {
      guard case SimulatorCoreDeviceError.timedOut = error else { return XCTFail("Unexpected error: \(error)") }
    }
    let closed = await peer.closed(atLeast: 1)
    XCTAssertEqual(closed, 1)
  }

  func testTheDeadlineDoesNotEndAStreamThatHasPushed() async throws {
    let provider = UpdatesProvider(events: [event(1)], then: .stayOpen)
    let stream = try subscribe(to: provider.services, timeout: .milliseconds(100))
    let task = Task {
      var values: [Int64] = []
      for try await value in stream {
        values.append(value)
      }
      return values
    }
    try await Task.sleep(for: .milliseconds(300))
    task.cancel()
    let received = try await task.value
    XCTAssertEqual(received, [1])
  }
}
