/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation

@objc(FBDeviceProvisioningProfileCommands)
public class FBDeviceProvisioningProfileCommands: NSObject, FBProvisioningProfileCommands {
  private(set) weak var device: FBDevice?

  // MARK: Public

  @objc public class func commands(with target: any FBiOSTarget) -> Self {
    return unsafeDowncast(FBDeviceProvisioningProfileCommands(device: target as! FBDevice), to: self)
  }

  public init(device: FBDevice) {
    self.device = device
    super.init()
  }

  // MARK: FBDeviceProvisioningProfileCommands (legacy FBFuture entry points)

  @objc public func allProvisioningProfiles() -> FBFuture<NSArray> {
    fbFutureFromAsync { [self] in
      try await allProvisioningProfilesAsync() as NSArray
    }
  }

  @objc public func removeProvisioningProfile(_ uuid: String) -> FBFuture<NSDictionary> {
    fbFutureFromAsync { [self] in
      try await removeProvisioningProfileAsync(uuid: uuid) as NSDictionary
    }
  }

  @objc public func installProvisioningProfile(_ profileData: Data) -> FBFuture<NSDictionary> {
    fbFutureFromAsync { [self] in
      try await installProvisioningProfileAsync(profileData) as NSDictionary
    }
  }

  // MARK: - Async

  fileprivate func allProvisioningProfilesAsync() async throws -> [[String: Any]] {
    guard let device else {
      throw FBDeviceControlError().describe("Device is nil").build()
    }
    return try await withFBFutureContext(device.connectToDevice(withPurpose: "list_provisioning_profiles")) { connectedDevice in
      guard let profiles = connectedDevice.calls.CopyProvisioningProfiles?(connectedDevice.amDeviceRef)?.takeRetainedValue() as? [Any] else {
        throw FBControlCoreError.describe("Failed to copy provisioning profiles").build()
      }
      var allProfiles: [[String: Any]] = []
      for profile in profiles {
        let payloadRef = connectedDevice.calls.ProvisioningProfileCopyPayload?(profile as CFTypeRef)
        var payload = payloadRef?.takeRetainedValue() as? [String: Any]
        if let p = payload {
          payload = FBCollectionOperations.recursiveFilteredJSONSerializableRepresentation(of: p)
        }
        if let payload {
          allProfiles.append(payload)
        }
      }
      return allProfiles
    }
  }

  fileprivate func removeProvisioningProfileAsync(uuid: String) async throws -> [String: Any] {
    guard let device else {
      throw FBDeviceControlError().describe("Device is nil").build()
    }
    return try await withFBFutureContext(device.connectToDevice(withPurpose: "remove_provisioning_profile")) { connectedDevice in
      let status = connectedDevice.calls.RemoveProvisioningProfile?(connectedDevice.amDeviceRef, uuid as CFString) ?? -1
      if status != 0 {
        let errRef = connectedDevice.calls.ProvisioningProfileCopyErrorStringForCode?(status)
        let errorDescription = errRef?.takeRetainedValue() as String? ?? "Unknown error"
        throw FBControlCoreError.describe("Failed to remove profile \(uuid): \(errorDescription)").build()
      }
      return [:]
    }
  }

  fileprivate func installProvisioningProfileAsync(_ profileData: Data) async throws -> [String: Any] {
    guard let device else {
      throw FBDeviceControlError().describe("Device is nil").build()
    }
    return try await withFBFutureContext(device.connectToDevice(withPurpose: "install_provisioning_profile")) { connectedDevice in
      guard let profileUnmanaged = connectedDevice.calls.ProvisioningProfileCreateWithData?(profileData as CFData) else {
        throw FBControlCoreError.describe("Could not construct profile from data \(profileData)").build()
      }
      let profile = profileUnmanaged.takeRetainedValue()
      let status = connectedDevice.calls.InstallProvisioningProfile?(connectedDevice.amDeviceRef, profile) ?? -1
      if status != 0 {
        let errRef = connectedDevice.calls.ProvisioningProfileCopyErrorStringForCode?(status)
        let errorDescription = errRef?.takeRetainedValue() as String? ?? "Unknown error"
        throw FBControlCoreError.describe("Failed to install profile \(profile): \(errorDescription)").build()
      }
      let payloadRef = connectedDevice.calls.ProvisioningProfileCopyPayload?(profile)
      var payload = payloadRef?.takeRetainedValue() as? [String: Any]
      if let p = payload {
        payload = FBCollectionOperations.recursiveFilteredJSONSerializableRepresentation(of: p)
      }
      guard let payload else {
        throw FBControlCoreError.describe("Failed to get payload of \(profile)").build()
      }
      return payload
    }
  }
}

// MARK: - AsyncProvisioningProfileCommands

extension FBDeviceProvisioningProfileCommands: AsyncProvisioningProfileCommands {

  public func allProvisioningProfiles() async throws -> [[String: Any]] {
    try await allProvisioningProfilesAsync()
  }

  public func removeProvisioningProfile(uuid: String) async throws -> [String: Any] {
    try await removeProvisioningProfileAsync(uuid: uuid)
  }

  public func installProvisioningProfile(_ profileData: Data) async throws -> [String: Any] {
    try await installProvisioningProfileAsync(profileData)
  }
}
