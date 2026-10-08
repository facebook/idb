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

private let ProcessControlChannel = "com.apple.instruments.server.services.processcontrol"

private func archived(_ value: Any) -> Data {
  // swiftlint:disable:next force_try
  try! NSKeyedArchiver.archivedData(withRootObject: value, requiringSecureCoding: false)
}

private extension Data {
  mutating func appendValue<T: FixedWidthInteger>(_ value: T) {
    Swift.withUnsafeBytes(of: value) { append(contentsOf: $0) }
  }
}

/// One single-fragment DTX message, as the device sends it.
private func dtxMessage(identifier: UInt32, conversationIndex: UInt32, returnValue: Any? = nil, auxiliary: Data = Data()) -> Data {
  let returnValueData = returnValue.map(archived) ?? Data()
  var payload = Data()
  payload.appendValue(UInt32(0)) // flags
  payload.appendValue(UInt32(auxiliary.count))
  payload.appendValue(UInt64(auxiliary.count + returnValueData.count))
  payload.append(auxiliary)
  payload.append(returnValueData)

  var message = Data()
  message.appendValue(UInt32(0x1F3D_5B79)) // magic
  message.appendValue(UInt32(32)) // header size
  message.appendValue(UInt16(0)) // fragment identifier
  message.appendValue(UInt16(1)) // fragment count
  message.appendValue(UInt32(payload.count))
  message.appendValue(identifier)
  message.appendValue(conversationIndex)
  message.appendValue(UInt32(0)) // channel code
  message.appendValue(UInt32(0)) // expects reply
  message.append(payload)
  return message
}

/// The handshake the device opens with, publishing `channels`.
private func handshake(publishing channels: [String]) -> Data {
  let published = Dictionary(uniqueKeysWithValues: channels.map { ($0, 1) })
  let auxiliary = InstrumentsClient.auxillaryData(fromArgumentsData: [InstrumentsClient.argumentData(forArgument: published)])
  return dtxMessage(identifier: 1, conversationIndex: 0, auxiliary: auxiliary)
}

/// The DTX exchange a client has with the device: the handshake, opening the process control
/// channel, then the call made on it.
@Suite
struct InstrumentsClientExchangeTests {

  private let amDevice = FakeAMDevice()

  private func makeConnection(replies: [Data]) -> (LockdownServiceConnection, FakeLockdownService) {
    let service = amDevice.service("com.apple.instruments.remoteserver")
    service.readBuffer = replies.reduce(Data(), +)
    let connection = LockdownServiceConnection(
      name: service.serviceName,
      connection: service,
      device: amDevice,
      calls: amDevice.calls,
      logger: ControlCoreGlobalConfiguration.defaultLogger)
    return (connection, service)
  }

  private func makeClient(_ connection: LockdownServiceConnection) throws -> InstrumentsClient {
    try InstrumentsClient(connection: connection, logger: ControlCoreGlobalConfiguration.defaultLogger)
  }

  private let launchConfiguration = ApplicationLaunchConfiguration(
    bundleID: "com.example.app",
    bundleName: "App",
    arguments: [],
    environment: [:],
    waitForDebugger: false,
    launchMode: .failIfRunning)

  @Test
  func launchingReturnsTheProcessIdentifierTheDeviceReports() throws {
    let (connection, service) = makeConnection(replies: [
      handshake(publishing: [ProcessControlChannel]),
      dtxMessage(identifier: 2, conversationIndex: 1),
      dtxMessage(identifier: 3, conversationIndex: 1, returnValue: NSNumber(value: 4242)),
    ])

    let client = try makeClient(connection)
    let processIdentifier = try client.launchApplication(launchConfiguration)

    #expect(processIdentifier == 4242)
    #expect(service.sentBytes.range(of: archived("com.example.app")) != nil)
  }

  @Test
  func killingSendsTheProcessIdentifierOnTheProcessControlChannel() throws {
    let (connection, service) = makeConnection(replies: [
      handshake(publishing: [ProcessControlChannel]),
      dtxMessage(identifier: 2, conversationIndex: 1),
      dtxMessage(identifier: 3, conversationIndex: 1),
    ])

    let client = try makeClient(connection)
    try client.killProcess(4242)

    #expect(service.sentBytes.range(of: archived("killPid:")) != nil)
    #expect(service.sentBytes.range(of: archived(NSNumber(value: 4242))) != nil)
  }

  @Test
  func launchingFailsWhenTheDeviceDoesNotPublishProcessControl() throws {
    let (connection, _) = makeConnection(replies: [handshake(publishing: ["com.example.other"])])

    let client = try makeClient(connection)

    #expect {
      _ = try client.launchApplication(launchConfiguration)
    } throws: { error in
      guard case let InstrumentsClientError.unknownChannel(identifier, _) = error else {
        return false
      }
      return identifier == ProcessControlChannel
    }
  }

  @Test
  func launchingFailsWithTheErrorTheDeviceReturns() throws {
    let deviceError = NSError(domain: "com.example.instruments", code: 7)
    let (connection, _) = makeConnection(replies: [
      handshake(publishing: [ProcessControlChannel]),
      dtxMessage(identifier: 2, conversationIndex: 1),
      dtxMessage(identifier: 3, conversationIndex: 1, returnValue: deviceError),
    ])

    let client = try makeClient(connection)

    #expect {
      _ = try client.launchApplication(launchConfiguration)
    } throws: { error in
      (error as NSError).domain == deviceError.domain && (error as NSError).code == deviceError.code
    }
  }
}
