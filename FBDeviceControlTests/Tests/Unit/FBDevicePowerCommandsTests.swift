/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import FBDeviceControl
import XCTest

private let DiagnosticsRelayService = "com.apple.mobile.diagnostics_relay"

/// Driven entirely through `FBDevice`'s public API against a scripted `AMDCalls` table, so what is
/// asserted is the AMDevice interaction a caller actually provokes rather than an internal helper.
///
/// Pinned to the main actor because the fake records events from the device's work and async
/// queues, both of which are the main queue.
@MainActor
final class FBDevicePowerCommandsTests: XCTestCase {

  private var amDevice = FakeAMDevice()

  override func setUp() {
    super.setUp()
    amDevice = FakeAMDevice()
  }

  private func makeDevice(replying reply: Any?) -> FBDevice {
    let device = amDevice.makeDevice()
    if let reply {
      amDevice.service(DiagnosticsRelayService).messageReplies = [reply]
    }
    amDevice.clearEvents()
    return device
  }

  // MARK: - The exchange

  func testRebootSendsRestartToTheDiagnosticsRelay() async throws {
    let device = makeDevice(replying: ["Status": "Success"])

    try await device.reboot()

    let sent = try XCTUnwrap(amDevice.service(DiagnosticsRelayService).sentMessages.first as? [String: String])
    XCTAssertEqual(sent, ["Request": "Restart"])
  }

  func testShutdownSendsShutdownToTheDiagnosticsRelay() async throws {
    let device = makeDevice(replying: ["Status": "Success"])

    try await device.shutdown()

    let sent = try XCTUnwrap(amDevice.service(DiagnosticsRelayService).sentMessages.first as? [String: String])
    XCTAssertEqual(sent, ["Request": "Shutdown"])
  }

  // MARK: - The AMDevice interaction

  /// The sequence a single service-backed command provokes, end to end. This is the assertion that
  /// makes a refactor of the connection handling provable: the session is released as soon as the
  /// service has started, and the connection is invalidated after the caller is done with it.
  func testDrivesTheFullConnectSessionServiceSequence() async throws {
    let device = makeDevice(replying: ["Status": "Success"])

    try await device.reboot()

    XCTAssertEqual(
      amDevice.events,
      [
        "connect",
        "is_paired",
        "validate_pairing",
        "start_session",
        "secure_start_service:\(DiagnosticsRelayService)",
        "stop_session",
        "disconnect",
      ])
  }

  func testInvalidatesTheServiceConnection() async throws {
    let device = makeDevice(replying: ["Status": "Success"])

    try await device.reboot()

    XCTAssertTrue(amDevice.service(DiagnosticsRelayService).isInvalidated)
  }

  // MARK: - Failures

  func testFailsWhenTheRelayReportsAnUnsuccessfulStatus() async throws {
    let device = makeDevice(replying: ["Status": "Failure"])

    do {
      try await device.reboot()
      XCTFail("Expected an unsuccessful status to fail the reboot")
    } catch {
      XCTAssertEqual((error as NSError).localizedDescription, "Not successful {\n    Status = Failure;\n}")
    }
  }

  func testFailsWhenTheRelayReplyIsNotADictionary() async throws {
    let device = makeDevice(replying: ["not", "a", "dictionary"])

    do {
      try await device.reboot()
      XCTFail("Expected a non-dictionary reply to fail the reboot")
    } catch {
      XCTAssertEqual((error as NSError).localizedDescription, "Unexpected response")
    }
  }

  /// A reply that never arrives is a receive failure, not a hang.
  func testFailsWhenTheRelayDoesNotReply() async throws {
    let device = makeDevice(replying: nil)

    do {
      try await device.reboot()
      XCTFail("Expected an absent reply to fail the reboot")
    } catch {
      XCTAssertTrue(
        (error as NSError).localizedDescription.hasPrefix("Failed to receive message"),
        "got \((error as NSError).localizedDescription)")
    }
  }

  /// The connection is released whichever way the body leaves, which is the property the scoped
  /// `withServiceConnection` exists to guarantee.
  func testInvalidatesTheServiceConnectionAfterAFailure() async throws {
    let device = makeDevice(replying: ["Status": "Failure"])

    try? await device.reboot()

    XCTAssertTrue(amDevice.service(DiagnosticsRelayService).isInvalidated)
  }
}
