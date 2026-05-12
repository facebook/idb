/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

private let DiagnosticsRelayService = "com.apple.mobile.diagnostics_relay"

@objc(FBDeviceDiagnosticInformationCommands)
public class FBDeviceDiagnosticInformationCommands: NSObject, FBiOSTargetCommand {
  private weak var device: FBDevice?

  // MARK: - Initializers

  public class func commands(with target: any FBiOSTarget) -> Self {
    return self.init(device: target as! FBDevice)
  }

  required init(device: FBDevice) {
    self.device = device
    super.init()
  }

  // MARK: - FBDiagnosticInformationCommands (legacy FBFuture entry point)

  public func fetchDiagnosticInformation() -> FBFuture<NSDictionary> {
    fbFutureFromAsync { [self] in
      try await fetchDiagnosticInformationAsync() as NSDictionary
    }
  }

  // MARK: - Async

  fileprivate func fetchDiagnosticInformationAsync() async throws -> [String: Any] {
    guard let device else {
      throw FBDeviceControlError().describe("Device is nil").build()
    }
    let diagnostics = try await fetchInformationFromDiagnosticsRelayAsync(device: device)
    let springboard = try await fetchInformationFromSpringboardAsync(device: device)
    let mobileConfig = try await fetchInformationFromMobileConfigurationAsync(device: device)
    let merged: [String: Any] = [
      DiagnosticsRelayService: diagnostics,
      FBSpringboardServicesClient.serviceName: springboard,
      FBManagedConfigClient.serviceName: mobileConfig,
    ]
    return FBCollectionOperations.recursiveFilteredJSONSerializableRepresentation(of: merged) as [String: Any]
  }

  // MARK: - Private

  private func fetchInformationFromDiagnosticsRelayAsync(device: FBDevice) async throws -> Any {
    try await withFBFutureContext(device.startService(DiagnosticsRelayService)) { connection in
      guard let result = try connection.sendAndReceiveMessage(["Request": "All"]) as? NSDictionary else {
        throw FBControlCoreError.describe("Unexpected response").build()
      }
      if (result["Status"] as? String) != "Success" {
        throw FBControlCoreError.describe("Not successful \(result)").build()
      }
      guard let diagnostics = result["Diagnostics"] as? [String: Any] else {
        return [:] as [String: Any]
      }
      return FBCollectionOperations.recursiveFilteredJSONSerializableRepresentation(of: diagnostics) as [String: Any]
    }
  }

  private func fetchInformationFromSpringboardAsync(device: FBDevice) async throws -> Any {
    guard let logger = device.logger else {
      throw FBDeviceControlError().describe("Device logger is nil").build()
    }
    return try await withFBFutureContext(device.startService(FBSpringboardServicesClient.serviceName)) { connection in
      let client = FBSpringboardServicesClient(connection: connection, logger: logger)
      return try await client.getIconLayoutAsync()
    }
  }

  private func fetchInformationFromMobileConfigurationAsync(device: FBDevice) async throws -> Any {
    guard let logger = device.logger else {
      throw FBDeviceControlError().describe("Device logger is nil").build()
    }
    return try await withFBFutureContext(device.startService(FBManagedConfigClient.serviceName)) { connection in
      try await FBManagedConfigClient.managedConfigClient(connection: connection, logger: logger).getCloudConfigurationAsync()
    }
  }
}

// MARK: - FBDevice+AsyncDiagnosticInformationCommands

extension FBDevice: AsyncDiagnosticInformationCommands {

  public func fetchDiagnosticInformation() async throws -> [String: Any] {
    try await diagnosticInformationCommands().fetchDiagnosticInformationAsync()
  }
}
