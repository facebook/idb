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

/// The ways device activation can fail, as data rather than assembled strings.
public enum FBDeviceActivationError: Error {
  case invalidActivationState(state: String)
  case activationStateMismatch(expected: String, actual: String)
  case noActivationState(response: String)
  case noValueInResponse(response: String)
  case invalidDRMHandshakeURL(urlString: String)
  case invalidActivationURL(urlString: String)
  case non200Response(response: String)
  case noActivationRecord(response: String)
  case noResponseData(response: String)
  case notHTTPResponse(response: String)
}

extension FBDeviceActivationError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case let .invalidActivationState(state):
      return "\(state) is not a valid activation state"
    case let .activationStateMismatch(expected, actual):
      return "Activation State \(expected) is not equal to actual activation state \(actual)"
    case let .noActivationState(response):
      return "No Activation State in \(response)"
    case let .noValueInResponse(response):
      return "No 'Value' in \(response)"
    case let .invalidDRMHandshakeURL(urlString):
      return "\(urlString) is not a valid DRM handshake URL"
    case let .invalidActivationURL(urlString):
      return "\(urlString) is not a valid device activation URL"
    case let .non200Response(response):
      return "\(response) no 200"
    case let .noActivationRecord(response):
      return "No 'ActivationRecord' in \(response)"
    case let .noResponseData(response):
      return "No response data in response \(response)"
    case let .notHTTPResponse(response):
      return "Response is not an HTTPURLResponse: \(response)"
    }
  }
}

public final class FBDeviceActivationCommands {
  private weak var device: FBDevice?

  // MARK: - Initializers

  public class func commands(with device: FBDevice) -> FBDeviceActivationCommands {
    FBDeviceActivationCommands(device: device)
  }

  init(device: FBDevice) {
    self.device = device
  }

  // MARK: - Activation

  fileprivate func activate() async throws {
    guard let device else {
      throw FBDeviceNilError.deviceNil
    }
    let logger = device.logger
    let state = try await activationStateAsync()
    if state == FBDeviceActivationState.activated {
      logger.log("Device is already activated, nothing to activate")
      return
    }
    if state == FBDeviceActivationState.unactivated {
      logger.log("Device is not activated, starting activation")
      try await performActivationAsync()
      return
    }
    throw FBDeviceActivationError.invalidActivationState(state: String(describing: state))
  }

  // MARK: - Private

  private func confirmActivationStateAsync(_ activationState: FBDeviceActivationState) async throws {
    let actual = try await activationStateAsync()
    if activationState != actual {
      throw FBDeviceActivationError.activationStateMismatch(expected: String(describing: activationState), actual: String(describing: actual))
    }
  }

  private func performActivationAsync() async throws {
    guard let device else {
      throw FBDeviceNilError.deviceNil
    }
    let logger = device.logger
    try await confirmActivationStateAsync(FBDeviceActivationState.unactivated)
    logger.log("Building DRM Handshake Payload")
    let drmHandshakePayload = try await buildDRMHandshakePayloadAsync()
    logger.log("Obtaining Activation record from DRM Handshake Payload")
    let activationRecordPayload = try await activationRecordFromDRMHandshakePayloadAsync(drmHandshakePayload)
    logger.log("Performing activation from activation record")
    try await activateFromActivationRecordAsync(activationRecordPayload)
    logger.log("Confirming activation state is Activated")
    try await confirmActivationStateAsync(FBDeviceActivationState.activated)
  }

  private func withMobileActivationService<T>(_ body: (FBAMDServiceConnection) async throws -> T) async throws -> T {
    guard let device else {
      throw FBDeviceNilError.deviceNil
    }
    return try await device.withServiceConnection("com.apple.mobileactivationd", body)
  }

  private func activationStateAsync() async throws -> FBDeviceActivationState {
    try await withMobileActivationService { connection in
      let response = try connection.sendAndReceiveMessage(["Command": "GetActivationStateRequest"])
      guard let responseDict = response as? NSDictionary,
        let activationState = responseDict["Value"] as? String
      else {
        throw FBDeviceActivationError.noActivationState(response: String(describing: response))
      }
      return FBDeviceActivationStateCoerceFromString(activationState)
    }
  }

  private func buildDRMHandshakePayloadAsync() async throws -> Data {
    try await withMobileActivationService { connection in
      let response = try connection.sendAndReceiveMessage(["Command": "CreateTunnel1SessionInfoRequest"])
      guard let responseDict = response as? NSDictionary,
        let responsePayload = responseDict["Value"] as? [String: Any]
      else {
        throw FBDeviceActivationError.noValueInResponse(response: String(describing: response))
      }
      return try await Self.mobileActivationRequestAsync(forRequestPayload: responsePayload)
    }
  }

  private func activationRecordFromDRMHandshakePayloadAsync(_ handshakePayload: Data) async throws -> Data {
    try await withMobileActivationService { connection in
      let response = try connection.sendAndReceiveMessage(["Command": "CreateTunnel1ActivationInfoRequest", "Value": handshakePayload])
      guard let responseDict = response as? NSDictionary,
        let responsePayload = responseDict["Value"] as? [String: Any]
      else {
        throw FBDeviceActivationError.noValueInResponse(response: String(describing: response))
      }
      return try await Self.mobileActivationActivateAsync(forRequestPayload: responsePayload)
    }
  }

  private func activateFromActivationRecordAsync(_ activationRecord: Data) async throws {
    try await withMobileActivationService { connection in
      _ = try connection.sendAndReceiveMessage(["Command": "HandleActivationInfoWithSessionRequest", "Value": activationRecord])
    }
  }

  private static func mobileActivationRequestAsync(forRequestPayload requestPayload: [String: Any]) async throws -> Data {
    let body = try PropertyListSerialization.data(fromPropertyList: requestPayload, format: .xml, options: 0)

    let urlString = ProcessInfo.processInfo.environment["IDB_DRM_HANDSHAKE_URL"] ?? DefaultDRMHandshakeURL
    guard let url = URL(string: urlString) else {
      throw FBDeviceActivationError.invalidDRMHandshakeURL(urlString: urlString)
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.httpBody = body
    request.setValue("application/x-apple-plist", forHTTPHeaderField: "Content-Type")
    request.setValue("application/xml", forHTTPHeaderField: "Accept")
    request.setValue("idb (https://github.com/facebook/idb/blob/main/FBDeviceControl/Commands/FBDeviceActivationCommands.m)", forHTTPHeaderField: "User-Agent")

    let (responseData, httpResponse) = try await dataAsync(for: request)
    if httpResponse.statusCode != 200 {
      throw FBDeviceActivationError.non200Response(response: String(describing: httpResponse))
    }
    _ = try PropertyListSerialization.propertyList(from: responseData, options: [], format: nil)
    return responseData
  }

  private static func mobileActivationActivateAsync(forRequestPayload requestPayload: [String: Any]) async throws -> Data {
    let payloadData = try PropertyListSerialization.data(fromPropertyList: requestPayload, format: .xml, options: 0)

    // Multipart info
    let boundaryConstant = UUID().uuidString
    let contentType = "multipart/form-data; boundary=\(boundaryConstant)"

    let urlString = ProcessInfo.processInfo.environment["IDB_ACTIVATION_URL"] ?? DefaultDeviceActivationURL
    guard let url = URL(string: urlString) else {
      throw FBDeviceActivationError.invalidActivationURL(urlString: urlString)
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.httpBody = multipartData(fromRequestPayload: payloadData, key: "activation-info", boundary: boundaryConstant)
    request.setValue(contentType, forHTTPHeaderField: "Content-Type")
    request.setValue("idb (https://github.com/facebook/idb/blob/main/FBDeviceControl/Commands/FBDeviceActivationCommands.m)", forHTTPHeaderField: "User-Agent")

    let (responseData, httpResponse) = try await dataAsync(for: request)
    if httpResponse.statusCode != 200 {
      throw FBDeviceActivationError.non200Response(response: String(describing: httpResponse))
    }
    let responsePlist = try PropertyListSerialization.propertyList(from: responseData, options: [], format: nil)
    guard let responseDict = responsePlist as? [String: Any],
      let activationRecord = responseDict["ActivationRecord"]
    else {
      throw FBDeviceActivationError.noActivationRecord(response: String(describing: responsePlist))
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
          continuation.resume(throwing: FBDeviceActivationError.noResponseData(response: String(describing: response)))
          return
        }
        guard let httpResponse = response as? HTTPURLResponse else {
          continuation.resume(throwing: FBDeviceActivationError.notHTTPResponse(response: String(describing: response)))
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
    let dashesData = Data("--".utf8)
    let newlineData = Data("\r\n".utf8)
    let keyData = Data(key.utf8)
    let boundaryData = Data(boundary.utf8)
    let valueHeaderData = Data("Content-Disposition: form-data; name=".utf8)

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

// MARK: - FBDevice+ActivationCommands

extension FBDevice: ActivationCommands {

  public func activate() async throws {
    try await activation.activate()
  }
}
