/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

private let DiagnosticsRelayService = "com.apple.mobile.diagnostics_relay"

/// The ways a diagnostics_relay exchange can fail, as data rather than assembled strings.
/// Shared with the power commands, which drive the same relay service.
public enum FBDiagnosticsRelayError: Error {
  case unexpectedResponse
  case unsuccessful(response: String)
}

extension FBDiagnosticsRelayError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .unexpectedResponse:
      return "Unexpected response"
    case let .unsuccessful(response):
      return "Not successful \(response)"
    }
  }
}

public final class FBDeviceDiagnosticInformationCommands: NSObject, FBiOSTargetCommand {
  private weak var device: FBDevice?

  // MARK: - Initializers

  public class func commands(with target: any FBiOSTarget) -> Self {
    guard let device = target as? FBDevice else {
      preconditionFailure("Expected FBDevice target, got \(target)")
    }
    return self.init(device: device)
  }

  required init(device: FBDevice) {
    self.device = device
    super.init()
  }

  // MARK: - Async

  fileprivate func fetchDiagnosticInformation() async throws -> [String: Any] {
    guard let device else {
      throw FBDeviceNilError.deviceNil
    }
    let diagnostics = try await fetchInformationFromDiagnosticsRelay(device: device)
    let springboard = try await fetchInformationFromSpringboard(device: device)
    let mobileConfig = try await fetchInformationFromMobileConfiguration(device: device)
    let merged: [String: Any] = [
      DiagnosticsRelayService: diagnostics,
      FBSpringboardServicesClient.serviceName: springboard,
      FBManagedConfigClient.serviceName: mobileConfig,
    ]
    return FBCollectionOperations.recursiveFilteredJSONSerializableRepresentation(of: merged) as [String: Any]
  }

  // MARK: - Private

  private func fetchInformationFromDiagnosticsRelay(device: FBDevice) async throws -> Any {
    try await device.withServiceConnection(DiagnosticsRelayService) { connection in
      guard let result = try connection.sendAndReceiveMessage(["Request": "All"]) as? NSDictionary else {
        throw FBDiagnosticsRelayError.unexpectedResponse
      }
      if (result["Status"] as? String) != "Success" {
        throw FBDiagnosticsRelayError.unsuccessful(response: String(describing: result))
      }
      guard let diagnostics = result["Diagnostics"] as? [String: Any] else {
        return [:] as [String: Any]
      }
      return FBCollectionOperations.recursiveFilteredJSONSerializableRepresentation(of: diagnostics) as [String: Any]
    }
  }

  private func fetchInformationFromSpringboard(device: FBDevice) async throws -> Any {
    let logger = device.logger
    return try await device.withServiceConnection(FBSpringboardServicesClient.serviceName) { connection in
      let client = FBSpringboardServicesClient(connection: connection, logger: logger)
      return try await client.getIconLayout().pages
    }
  }

  private func fetchInformationFromMobileConfiguration(device: FBDevice) async throws -> Any {
    let logger = device.logger
    return try await device.withServiceConnection(FBManagedConfigClient.serviceName) { connection in
      try await FBManagedConfigClient.managedConfigClient(connection: connection, logger: logger).getCloudConfiguration()
    }
  }
}

// MARK: - FBDevice+DiagnosticInformationCommands

extension FBDevice: DiagnosticInformationCommands {

  public func fetchDiagnosticInformation() async throws -> [String: Any] {
    try await diagnosticInformation.fetchDiagnosticInformation()
  }
}
