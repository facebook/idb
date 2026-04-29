/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation

private let DefaultDRMHandshakeURL = "https://albert.apple.com/deviceservices/drmHandshake"
private let DefaultDeviceActivationURL = "https://albert.apple.com/deviceservices/deviceActivation"

@objc(FBDeviceActivationCommands)
public class FBDeviceActivationCommands: NSObject, FBDeviceActivationCommandsProtocol, FBiOSTargetCommand {
  private weak var device: FBDevice?

  // MARK: - Initializers

  public class func commands(with target: any FBiOSTarget) -> Self {
    return self.init(device: target as! FBDevice)
  }

  required init(device: FBDevice) {
    self.device = device
    super.init()
  }

  // MARK: - FBDeviceActivationCommands (legacy FBFuture entry point)

  public func activate() -> FBFuture<NSNull> {
    fbFutureFromAsync { [self] in
      try await activateAsync()
      return NSNull()
    }
  }

  // MARK: - Async

  fileprivate func activateAsync() async throws {
    guard let device else {
      throw FBDeviceControlError().describe("Device is nil").build()
    }
    let logger = device.logger
    let state = try await activationStateAsync()
    if state == FBDeviceActivationState.activated {
      logger?.log("Device is already activated, nothing to activate")
      return
    }
    if state == FBDeviceActivationState.unactivated {
      logger?.log("Device is not activated, starting activation")
      try await performActivationAsync()
      return
    }
    throw FBControlCoreError.describe("\(state) is not a valid activation state").build()
  }

  // MARK: - Private

  private func confirmActivationStateAsync(_ activationState: FBDeviceActivationState) async throws {
    let actual = try await activationStateAsync()
    if activationState != actual {
      throw FBControlCoreError.describe("Activation State \(activationState) is not equal to actual activation state \(actual)").build()
    }
  }

  private func performActivationAsync() async throws {
    guard let device else {
      throw FBDeviceControlError().describe("Device is nil").build()
    }
    let logger = device.logger
    try await confirmActivationStateAsync(FBDeviceActivationState.unactivated)
    logger?.log("Building DRM Handshake Payload")
    let drmHandshakePayload = try await buildDRMHandshakePayloadAsync()
    logger?.log("Obtaining Activation record from DRM Handshake Payload")
    let activationRecordPayload = try await activationRecordFromDRMHandshakePayloadAsync(drmHandshakePayload)
    logger?.log("Performing activation from activation record")
    try await activateFromActivationRecordAsync(activationRecordPayload)
    logger?.log("Confirming activation state is Activated")
    try await confirmActivationStateAsync(FBDeviceActivationState.activated)
  }

  private func mobileActivationService() -> FBFutureContext<FBAMDServiceConnection> {
    guard let device else {
      return FBDeviceControlError().describe("Device is nil").failFutureContext() as! FBFutureContext<FBAMDServiceConnection>
    }
    return device.startService("com.apple.mobileactivationd")
  }

  private func activationStateAsync() async throws -> FBDeviceActivationState {
    return try await withFBFutureContext(mobileActivationService()) { connection in
      let response = try connection.sendAndReceiveMessage(["Command": "GetActivationStateRequest"])
      guard let responseDict = response as? NSDictionary,
        let activationState = responseDict["Value"] as? String
      else {
        throw FBControlCoreError.describe("No Activation State in \(String(describing: response))").build()
      }
      return FBDeviceActivationStateCoerceFromString(activationState)
    }
  }

  private func buildDRMHandshakePayloadAsync() async throws -> Data {
    return try await withFBFutureContext(mobileActivationService()) { connection in
      let response = try connection.sendAndReceiveMessage(["Command": "CreateTunnel1SessionInfoRequest"])
      guard let responseDict = response as? NSDictionary,
        let responsePayload = responseDict["Value"] as? [String: Any]
      else {
        throw FBControlCoreError.describe("No 'Value' in \(String(describing: response))").build()
      }
      return try await Self.mobileActivationRequestAsync(forRequestPayload: responsePayload)
    }
  }

  private func activationRecordFromDRMHandshakePayloadAsync(_ handshakePayload: Data) async throws -> Data {
    return try await withFBFutureContext(mobileActivationService()) { connection in
      let response = try connection.sendAndReceiveMessage(["Command": "CreateTunnel1ActivationInfoRequest", "Value": handshakePayload])
      guard let responseDict = response as? NSDictionary,
        let responsePayload = responseDict["Value"] as? [String: Any]
      else {
        throw FBControlCoreError.describe("No 'Value' in \(String(describing: response))").build()
      }
      return try await Self.mobileActivationActivateAsync(forRequestPayload: responsePayload)
    }
  }

  private func activateFromActivationRecordAsync(_ activationRecord: Data) async throws {
    try await withFBFutureContext(mobileActivationService()) { connection in
      _ = try connection.sendAndReceiveMessage(["Command": "HandleActivationInfoWithSessionRequest", "Value": activationRecord])
    }
  }

  private static func mobileActivationRequestAsync(forRequestPayload requestPayload: [String: Any]) async throws -> Data {
    let body = try PropertyListSerialization.data(fromPropertyList: requestPayload, format: .xml, options: 0)

    let url = URL(string: ProcessInfo.processInfo.environment["IDB_DRM_HANDSHAKE_URL"] ?? DefaultDRMHandshakeURL)!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.httpBody = body
    request.setValue("application/x-apple-plist", forHTTPHeaderField: "Content-Type")
    request.setValue("application/xml", forHTTPHeaderField: "Accept")
    request.setValue("idb (https://github.com/facebook/idb/blob/main/FBDeviceControl/Commands/FBDeviceActivationCommands.m)", forHTTPHeaderField: "User-Agent")

    let (responseData, httpResponse) = try await dataAsync(for: request)
    if httpResponse.statusCode != 200 {
      throw FBControlCoreError.describe("\(httpResponse) no 200").build()
    }
    _ = try PropertyListSerialization.propertyList(from: responseData, options: [], format: nil)
    return responseData
  }

  private static func mobileActivationActivateAsync(forRequestPayload requestPayload: [String: Any]) async throws -> Data {
    let payloadData = try PropertyListSerialization.data(fromPropertyList: requestPayload, format: .xml, options: 0)

    // Multipart info
    let boundaryConstant = UUID().uuidString
    let contentType = "multipart/form-data; boundary=\(boundaryConstant)"

    let url = URL(string: ProcessInfo.processInfo.environment["IDB_ACTIVATION_URL"] ?? DefaultDeviceActivationURL)!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.httpBody = multipartData(fromRequestPayload: payloadData, key: "activation-info", boundary: boundaryConstant)
    request.setValue(contentType, forHTTPHeaderField: "Content-Type")
    request.setValue("idb (https://github.com/facebook/idb/blob/main/FBDeviceControl/Commands/FBDeviceActivationCommands.m)", forHTTPHeaderField: "User-Agent")

    let (responseData, httpResponse) = try await dataAsync(for: request)
    if httpResponse.statusCode != 200 {
      throw FBControlCoreError.describe("\(httpResponse) no 200").build()
    }
    let responsePlist = try PropertyListSerialization.propertyList(from: responseData, options: [], format: nil)
    guard let responseDict = responsePlist as? [String: Any],
      let activationRecord = responseDict["ActivationRecord"]
    else {
      throw FBControlCoreError.describe("No 'ActivationRecord' in \(String(describing: responsePlist))").build()
    }
    return try PropertyListSerialization.data(fromPropertyList: activationRecord, format: .xml, options: 0)
  }

  private static func dataAsync(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>) in
      let task = URLSession.shared.dataTask(with: request) { responseData, response, error in
        if let error {
          continuation.resume(throwing: error)
          return
        }
        guard let responseData else {
          continuation.resume(throwing: FBControlCoreError.describe("No response data in response \(String(describing: response))").build())
          return
        }
        guard let httpResponse = response as? HTTPURLResponse else {
          continuation.resume(throwing: FBControlCoreError.describe("Response is not an HTTPURLResponse: \(String(describing: response))").build())
          return
        }
        continuation.resume(returning: (responseData, httpResponse))
      }
      task.resume()
    }
  }

  private static func multipartData(
    fromRequestPayload payload: Data,
    key: String,
    boundary: String
  ) -> Data {
    let dashesData = "--".data(using: .utf8)!
    let newlineData = "\r\n".data(using: .utf8)!
    let keyData = key.data(using: .utf8)!
    let boundaryData = boundary.data(using: .utf8)!
    let valueHeaderData = "Content-Disposition: form-data; name=".data(using: .utf8)!

    var data = Data()

    // Header prefixed with dashes.
    data.append(contentsOf: dashesData)
    data.append(contentsOf: boundaryData)
    data.append(contentsOf: newlineData)

    // Then the key-value
    data.append(contentsOf: valueHeaderData)
    data.append(contentsOf: keyData)
    data.append(contentsOf: newlineData)
    data.append(contentsOf: newlineData)
    data.append(contentsOf: payload)
    data.append(contentsOf: newlineData)

    // Then the trailer, suffixed with dashes
    data.append(contentsOf: dashesData)
    data.append(contentsOf: boundaryData)
    data.append(contentsOf: dashesData)
    data.append(contentsOf: newlineData)

    return data
  }
}
