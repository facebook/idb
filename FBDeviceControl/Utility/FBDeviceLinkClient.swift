/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation

private let ProcessMessage = "DLMessageProcessMessage"
private let DeviceReady = "DLMessageDeviceReady"

/// Wraps the non-`Sendable` `FBAMDServiceConnection` so it can be captured by
/// the `@Sendable` closure dispatched onto the serial queue. The queue
/// guarantees serial access to the connection in practice.
private final class ConnectionBox: @unchecked Sendable {
  let connection: FBAMDServiceConnection
  init(_ connection: FBAMDServiceConnection) {
    self.connection = connection
  }
}

/// Wraps an `Any` payload so it can be captured by a `@Sendable` closure.
private final class AnyBox: @unchecked Sendable {
  let value: Any
  init(_ value: Any) {
    self.value = value
  }
}

@objc(FBDeviceLinkClient)
public class FBDeviceLinkClient: NSObject {
  private let connection: FBAMDServiceConnection
  private let queue: DispatchQueue

  // MARK: Initializers

  @objc public static func deviceLinkClient(connection: FBAMDServiceConnection) -> FBFuture<FBDeviceLinkClient> {
    fbFutureFromAsync {
      try await deviceLinkClientAsync(connection: connection)
    }
  }

  public static func deviceLinkClientAsync(connection: FBAMDServiceConnection) async throws -> FBDeviceLinkClient {
    let queue = DispatchQueue(label: "com.facebook.fbdevicecontrol.fbdevicelinkclient")
    try await performVersionExchangeAsync(connection: connection, queue: queue)
    return FBDeviceLinkClient(connection: connection, queue: queue)
  }

  init(connection: FBAMDServiceConnection, queue: DispatchQueue) {
    self.connection = connection
    self.queue = queue
    super.init()
  }

  // MARK: Public Methods

  public func processMessage(_ message: Any) -> FBFuture<NSDictionary> {
    fbFutureFromAsync { [self] in
      try await processMessageAsync(message)
    }
  }

  public func processMessageAsync(_ message: Any) async throws -> NSDictionary {
    let connectionBox = ConnectionBox(connection)
    let messageBox = AnyBox(message)
    return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<NSDictionary, Error>) in
      queue.async {
        do {
          let result = try connectionBox.connection.sendAndReceiveMessage([ProcessMessage, messageBox.value])
          guard let resultArray = result as? NSArray else {
            continuation.resume(throwing: FBDeviceControlError.describe("Result is not an NSArray: \(String(describing: result))").build())
            return
          }
          let responseType = resultArray[0]
          guard let responseString = responseType as? String else {
            continuation.resume(throwing: FBDeviceControlError.describe("\(responseType) is not an NSString in \(resultArray)").build())
            return
          }
          if responseString != ProcessMessage {
            continuation.resume(throwing: FBDeviceControlError.describe("\(responseString) should be a \(ProcessMessage)").build())
            return
          }
          guard let response = resultArray[1] as? NSDictionary else {
            continuation.resume(throwing: FBDeviceControlError.describe("\(resultArray[1]) is not a NSDictionary").build())
            return
          }
          continuation.resume(returning: response)
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  // MARK: Private

  private static func performVersionExchangeAsync(connection: FBAMDServiceConnection, queue: DispatchQueue) async throws {
    let connectionBox = ConnectionBox(connection)
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      queue.async {
        do {
          let plist = try connectionBox.connection.receiveMessage()
          guard let plistArray = plist as? NSArray else {
            continuation.resume(throwing: FBDeviceControlError.describe("\(String(describing: plist)) is not an array in version exchange").build())
            return
          }
          let versionNumber = plistArray[1]
          guard versionNumber is NSNumber else {
            continuation.resume(throwing: FBDeviceControlError.describe("\(versionNumber) is not a NSNumber for the handshake version").build())
            return
          }
          let response: [Any] = ["DLMessageVersionExchange", "DLVersionsOk", versionNumber]
          let reply = try connectionBox.connection.sendAndReceiveMessage(response)
          guard let replyArray = reply as? NSArray else {
            continuation.resume(throwing: FBDeviceControlError.describe("\(String(describing: reply)) is not an array in version exchange").build())
            return
          }
          let message = replyArray[0]
          guard let messageString = message as? String else {
            continuation.resume(throwing: FBDeviceControlError.describe("\(message) is not a NSString for the device ready call").build())
            return
          }
          if messageString != DeviceReady {
            continuation.resume(throwing: FBDeviceControlError.describe("\(messageString) is not equal to \(DeviceReady)").build())
            return
          }
          continuation.resume(returning: ())
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }
}
