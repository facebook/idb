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

  // MARK: FBDeviceProvisioningProfileCommands Implementation

  @objc public func allProvisioningProfiles() -> FBFuture<NSArray> {
    let ctx: FBFutureContext<NSArray> = listProvisioningProfiles()
    let popBlock: (NSArray) -> FBFuture<AnyObject> = { (merged: NSArray) -> FBFuture<AnyObject> in
      let device = merged[0] as! any FBDeviceCommands
      let profiles = merged.subarray(with: NSRange(location: 1, length: merged.count - 1))
      var allProfiles: [[String: Any]] = []
      for profile in profiles {
        let payloadRef = device.calls.ProvisioningProfileCopyPayload?(profile as CFTypeRef)
        var payload = payloadRef?.takeRetainedValue() as? [String: Any]
        if let p = payload {
          payload = FBCollectionOperations.recursiveFilteredJSONSerializableRepresentation(of: p)
        }
        if let payload {
          allProfiles.append(payload)
        }
      }
      return FBFuture(result: allProfiles as NSArray as AnyObject)
    }
    return unsafeBitCast(ctx.onQueue(device!.workQueue, pop: popBlock), to: FBFuture<NSArray>.self)
  }

  @objc public func removeProvisioningProfile(_ uuid: String) -> FBFuture<NSDictionary> {
    let ctx = device!.connectToDevice(withPurpose: "remove_provisioning_profile")
    let popBlock: (AnyObject) -> FBFuture<AnyObject> = { (d: AnyObject) -> FBFuture<AnyObject> in
      let device = d as! any FBDeviceCommands
      let status = device.calls.RemoveProvisioningProfile?(device.amDeviceRef, uuid as CFString) ?? -1
      if status != 0 {
        let errRef = device.calls.ProvisioningProfileCopyErrorStringForCode?(status)
        let errorDescription = errRef?.takeRetainedValue() as String? ?? "Unknown error"
        return FBControlCoreError.describe("Failed to remove profile \(uuid): \(errorDescription)").failFuture()
      }
      return FBFuture(result: [:] as NSDictionary as AnyObject)
    }
    return unsafeBitCast(ctx.onQueue(device!.workQueue, pop: popBlock), to: FBFuture<NSDictionary>.self)
  }

  @objc public func installProvisioningProfile(_ profileData: Data) -> FBFuture<NSDictionary> {
    let ctx = device!.connectToDevice(withPurpose: "install_provisioning_profile")
    func popBlock(_ d: AnyObject) -> FBFuture<AnyObject> {
      let device = d as! any FBDeviceCommands
      guard let profileUnmanaged = device.calls.ProvisioningProfileCreateWithData?(profileData as CFData) else {
        return FBControlCoreError.describe("Could not construct profile from data \(profileData)").failFuture()
      }
      let profile = profileUnmanaged.takeRetainedValue()
      let status = device.calls.InstallProvisioningProfile?(device.amDeviceRef, profile) ?? -1
      if status != 0 {
        let errRef = device.calls.ProvisioningProfileCopyErrorStringForCode?(status)
        let errorDescription = errRef?.takeRetainedValue() as String? ?? "Unknown error"
        return FBControlCoreError.describe("Failed to install profile \(profile): \(errorDescription)").failFuture()
      }
      let payloadRef = device.calls.ProvisioningProfileCopyPayload?(profile)
      var payload = payloadRef?.takeRetainedValue() as? [String: Any]
      if let p = payload {
        payload = FBCollectionOperations.recursiveFilteredJSONSerializableRepresentation(of: p)
      }
      guard let payload else {
        return FBControlCoreError.describe("Failed to get payload of \(profile)").failFuture()
      }
      return FBFuture(result: payload as NSDictionary as AnyObject)
    }
    return unsafeBitCast(ctx.onQueue(device!.workQueue, pop: popBlock), to: FBFuture<NSDictionary>.self)
  }

  // MARK: Private

  private func listProvisioningProfiles() -> FBFutureContext<NSArray> {
    let ctx = device!.connectToDevice(withPurpose: "list_provisioning_profiles")
    func pendBlock(_ d: AnyObject) -> FBFuture<AnyObject> {
      let device = d as! any FBDeviceCommands
      let profilesRef = device.calls.CopyProvisioningProfiles?(device.amDeviceRef)
      guard let profiles = profilesRef?.takeRetainedValue() as? [Any] else {
        return FBControlCoreError.describe("Failed to copy provisioning profiles").failFuture()
      }
      let result: NSArray = ([device] as [Any] + profiles) as NSArray
      return FBFuture(result: result as AnyObject)
    }
    return unsafeBitCast(ctx.onQueue(device!.workQueue, pend: pendBlock), to: FBFutureContext<NSArray>.self)
  }
}
