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
public class FBDeviceDiagnosticInformationCommands: NSObject, FBDiagnosticInformationCommands {
  private weak var device: FBDevice?

  // MARK: - Initializers

  public class func commands(with target: any FBiOSTarget) -> Self {
    return self.init(device: target as! FBDevice)
  }

  required init(device: FBDevice) {
    self.device = device
    super.init()
  }

  // MARK: - FBDiagnosticInformationCommands

  public func fetchDiagnosticInformation() -> FBFuture<NSDictionary> {
    guard let device else {
      return FBFuture(error: FBDeviceControlError().describe("Device is nil").build())
    }
    return FBFuture<AnyObject>.combine([
      fetchInformationFromDiagnosticsRelay(),
      fetchInformationFromSpringboard(),
      fetchInformationFromMobileConfiguration(),
    ])
    .onQueue(
      device.asyncQueue,
      map: { results -> AnyObject in
        let resultsArray = results as [AnyObject]
        return FBCollectionOperations.recursiveFilteredJSONSerializableRepresentation(of: [
          DiagnosticsRelayService: resultsArray[0],
          FBSpringboardServicesClient.serviceName: resultsArray[1],
          FBManagedConfigClient.serviceName: resultsArray[2],
        ]) as AnyObject
      }) as! FBFuture<NSDictionary>
  }

  // MARK: - Private

  private func fetchInformationFromDiagnosticsRelay() -> FBFuture<AnyObject> {
    guard let device else {
      return FBFuture(error: FBDeviceControlError().describe("Device is nil").build())
    }
    return
      device
      .startService(DiagnosticsRelayService)
      .onQueue(
        device.asyncQueue,
        pop: { connection -> FBFuture<AnyObject> in
          do {
            guard let result = try connection.sendAndReceiveMessage(["Request": "All"]) as? NSDictionary else {
              return FBControlCoreError.describe("Unexpected response").failFuture()
            }
            if (result["Status"] as? String) != "Success" {
              return FBControlCoreError.describe("Not successful \(result)").failFuture()
            }
            guard let diagnostics = result["Diagnostics"] as? [String: Any] else {
              return FBFuture(result: NSDictionary() as AnyObject)
            }
            return FBFuture(result: FBCollectionOperations.recursiveFilteredJSONSerializableRepresentation(of: diagnostics) as AnyObject)
          } catch {
            return FBFuture(error: error)
          }
        })
  }

  private func fetchInformationFromSpringboard() -> FBFuture<AnyObject> {
    guard let device, let logger = device.logger else {
      return FBFuture(error: FBDeviceControlError().describe("Device is nil").build())
    }
    return
      device
      .startService(FBSpringboardServicesClient.serviceName)
      .onQueue(
        device.asyncQueue,
        pop: { connection -> FBFuture<AnyObject> in
          let client = FBSpringboardServicesClient(connection: connection, logger: logger)
          return client.getIconLayout() as! FBFuture<AnyObject>
        })
  }

  private func fetchInformationFromMobileConfiguration() -> FBFuture<AnyObject> {
    guard let device, let logger = device.logger else {
      return FBFuture(error: FBDeviceControlError().describe("Device is nil").build())
    }
    return
      device
      .startService(FBManagedConfigClient.serviceName)
      .onQueue(
        device.asyncQueue,
        pop: { connection -> FBFuture<AnyObject> in
          return FBManagedConfigClient.managedConfigClient(connection: connection, logger: logger).getCloudConfiguration() as! FBFuture<AnyObject>
        })
  }
}
