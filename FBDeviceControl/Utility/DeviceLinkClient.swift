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

/// Carries the non-`Sendable` connection across the serial-queue boundary; only touched on that queue.
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

public enum FBDeviceLinkError: Error {
  case resultNotAnArray(result: String)
  case responseTypeNotAString(responseType: String, result: String)
  case unexpectedResponseType(responseType: String, expected: String)
  case responseBodyNotADictionary(body: String)
  case versionExchangeNotAnArray(plist: String)
  case handshakeVersionNotANumber(version: String)
  case deviceReadyMessageNotAString(message: String)
  case deviceNotReady(message: String, expected: String)
}

extension FBDeviceLinkError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case let .resultNotAnArray(result):
      return "Result is not an NSArray: \(result)"
    case let .responseTypeNotAString(responseType, result):
      return "\(responseType) is not an NSString in \(result)"
    case let .unexpectedResponseType(responseType, expected):
      return "\(responseType) should be a \(expected)"
    case let .responseBodyNotADictionary(body):
      return "\(body) is not an NSDictionary"
    case let .versionExchangeNotAnArray(plist):
      return "\(plist) is not an array in version exchange"
    case let .handshakeVersionNotANumber(version):
      return "\(version) is not an NSNumber for the handshake version"
    case let .deviceReadyMessageNotAString(message):
      return "\(message) is not an NSString for the device ready call"
    case let .deviceNotReady(message, expected):
      return "\(message) is not equal to \(expected)"
    }
  }
}

public final class FBDeviceLinkClient {
  private let connection: FBAMDServiceConnection
  private let queue: DispatchQueue

  public static func deviceLinkClient(connection: FBAMDServiceConnection) async throws -> FBDeviceLinkClient {
    let queue = DispatchQueue(label: "com.facebook.fbdevicecontrol.fbdevicelinkclient")
    try await performVersionExchange(connection: connection, queue: queue)
    return FBDeviceLinkClient(connection: connection, queue: queue)
  }

  init(connection: FBAMDServiceConnection, queue: DispatchQueue) {
    self.connection = connection
    self.queue = queue
  }

  func processMessage(_ message: Any) async throws -> NSDictionary {
    let connectionBox = ConnectionBox(connection)
    let messageBox = AnyBox(message)
    return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<NSDictionary, Error>) in
      queue.async {
        do {
          let result = try connectionBox.connection.sendAndReceiveMessage([ProcessMessage, messageBox.value])
          guard let resultArray = result as? NSArray else {
            continuation.resume(throwing: FBDeviceLinkError.resultNotAnArray(result: String(describing: result)))
            return
          }
          let responseType = resultArray[0]
          guard let responseString = responseType as? String else {
            continuation.resume(throwing: FBDeviceLinkError.responseTypeNotAString(responseType: String(describing: responseType), result: String(describing: resultArray)))
            return
          }
          if responseString != ProcessMessage {
            continuation.resume(throwing: FBDeviceLinkError.unexpectedResponseType(responseType: responseString, expected: ProcessMessage))
            return
          }
          guard let response = resultArray[1] as? NSDictionary else {
            continuation.resume(throwing: FBDeviceLinkError.responseBodyNotADictionary(body: String(describing: resultArray[1])))
            return
          }
          continuation.resume(returning: response)
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  private static func performVersionExchange(connection: FBAMDServiceConnection, queue: DispatchQueue) async throws {
    let connectionBox = ConnectionBox(connection)
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      queue.async {
        do {
          let plist = try connectionBox.connection.receiveMessage()
          guard let plistArray = plist as? NSArray else {
            continuation.resume(throwing: FBDeviceLinkError.versionExchangeNotAnArray(plist: String(describing: plist)))
            return
          }
          let versionNumber = plistArray[1]
          guard versionNumber is NSNumber else {
            continuation.resume(throwing: FBDeviceLinkError.handshakeVersionNotANumber(version: String(describing: versionNumber)))
            return
          }
          let response: [Any] = ["DLMessageVersionExchange", "DLVersionsOk", versionNumber]
          let reply = try connectionBox.connection.sendAndReceiveMessage(response)
          guard let replyArray = reply as? NSArray else {
            continuation.resume(throwing: FBDeviceLinkError.versionExchangeNotAnArray(plist: String(describing: reply)))
            return
          }
          let message = replyArray[0]
          guard let messageString = message as? String else {
            continuation.resume(throwing: FBDeviceLinkError.deviceReadyMessageNotAString(message: String(describing: message)))
            return
          }
          if messageString != DeviceReady {
            continuation.resume(throwing: FBDeviceLinkError.deviceNotReady(message: messageString, expected: DeviceReady))
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
