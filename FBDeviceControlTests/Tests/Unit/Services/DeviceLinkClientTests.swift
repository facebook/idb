/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBDeviceControl
import Foundation
import Testing

/// The device link protocol: a version exchange and a ready message, then process-message requests
/// each answered with a `[type, body]` reply.
@MainActor
// Serialized: the fake device's queues are the main queue, so parallel tests would interleave on it.
@Suite(.serialized)
struct DeviceLinkClientTests {

  private static let serviceName = "com.example.devicelink"
  private let amDevice = FakeAMDevice()

  private var service: FakeLockdownService {
    amDevice.service(Self.serviceName)
  }

  private func process(_ message: Any, replies: [Any]) async throws -> NSDictionary {
    let device = amDevice.makeDevice()
    service.messageReplies = [["DLMessageVersionExchange", 300, 0], ["DLMessageDeviceReady"]] + replies
    return try await device.withDeviceLinkClient(Self.serviceName) { client in
      try await client.processMessage(message)
    }
  }

  private func error(processing message: Any, replies: [Any]) async -> String? {
    do {
      _ = try await process(message, replies: replies)
      return nil
    } catch {
      return error.localizedDescription
    }
  }

  @Test
  func aProcessedMessageReturnsTheReplysBody() async throws {
    let response = try await process(["MessageType": "ScreenShotRequest"], replies: [["DLMessageProcessMessage", ["ScreenShotData": Data([1, 2, 3])]]])

    #expect(response["ScreenShotData"] as? Data == Data([1, 2, 3]))
    #expect(service.sentMessages.count == 2)
    #expect((service.sentMessages[0] as? [Any])?.first as? String == "DLMessageVersionExchange")
    #expect((service.sentMessages[1] as? [Any])?.first as? String == "DLMessageProcessMessage")
  }

  @Test
  func aReplyOfAnotherTypeIsRejected() async {
    let error = await error(processing: [:], replies: [["DLMessageDisconnect", [:]]])

    #expect(error == "DLMessageDisconnect should be a DLMessageProcessMessage")
  }

  @Test
  func aReplyWhoseBodyIsNotADictionaryIsRejected() async {
    let error = await error(processing: [:], replies: [["DLMessageProcessMessage", "nope"]])

    #expect(error == "nope is not an NSDictionary")
  }

  @Test
  func aReplyThatIsNotAnArrayIsRejected() async {
    let error = await error(processing: [:], replies: ["nope"])

    #expect(error == "Result is not an NSArray: nope")
  }

  @Test
  func aReplyWithoutABodyIsRejected() async {
    let error = await error(processing: [:], replies: [["DLMessageProcessMessage"]])

    #expect(error?.hasSuffix("has fewer than 2 elements") == true)
  }

  @Test
  func aDeviceThatIsNotReadyIsRejected() async {
    let device = amDevice.makeDevice()
    service.messageReplies = [["DLMessageVersionExchange", 300, 0], ["DLMessageDisconnect"]]

    await #expect(throws: DeviceLinkError.self) {
      try await device.withDeviceLinkClient(Self.serviceName) { _ in }
    }
  }
}
