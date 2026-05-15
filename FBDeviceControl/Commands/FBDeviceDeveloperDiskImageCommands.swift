/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation

// swiftlint:disable force_cast force_unwrapping

private let MountPathKey = "MountPath"
private let ImageTypeKey = "ImageType"
private let ImageSignatureKey = "ImageSignature"
private let CommandKey = "Command"

private let DiskImageTypeDeveloper = "Developer"
private let ImageMounterService = "com.apple.mobile.mobile_image_mounter"

private let DiskImageMountingError: Int32 = -402653066 // 0xe8000076

private func mountCallback(_ callbackDictionary: [String: Any]?, _ context: UnsafeMutableRawPointer?) {
  guard let context, let callbackDictionary else { return }
  let device = Unmanaged<AnyObject>.fromOpaque(context).takeUnretainedValue()
  if let logger = (device as? (any FBDeviceCommands))?.logger {
    logger.log("Mount Progress: \(FBCollectionInformation.oneLineDescription(from: callbackDictionary))")
  }
}

@objc(FBDeviceDeveloperDiskImageCommands)
public class FBDeviceDeveloperDiskImageCommands: NSObject, FBiOSTargetCommand {
  private(set) weak var device: FBDevice?

  // MARK: Initializers

  @objc public class func commands(with target: any FBiOSTarget) -> Self {
    return unsafeDowncast(FBDeviceDeveloperDiskImageCommands(device: target as! FBDevice), to: self)
  }

  init(device: FBDevice) {
    self.device = device
    super.init()
  }

  // MARK: FBDeveloperDiskImageCommands (legacy FBFuture entry points)

  @objc public func mountedDiskImages() -> FBFuture<NSArray> {
    fbFutureFromAsync { [self] in
      try await mountedDiskImagesAsync() as NSArray
    }
  }

  @objc public func mountDiskImage(_ diskImage: FBDeveloperDiskImage) -> FBFuture<FBDeveloperDiskImage> {
    fbFutureFromAsync { [self] in
      try await mountDeveloperDiskImageAsync(diskImage, imageType: DiskImageTypeDeveloper)
    }
  }

  @objc public func unmountDiskImage(_ diskImage: FBDeveloperDiskImage) -> FBFuture<NSNull> {
    fbFutureFromAsync { [self] in
      try await unmountDiskImageAsync(diskImage)
      return NSNull()
    }
  }

  @objc public func mountableDiskImages() -> [FBDeveloperDiskImage] {
    return FBDeveloperDiskImage.allDiskImages
  }

  @objc public func ensureDeveloperDiskImageIsMounted() -> FBFuture<FBDeveloperDiskImage> {
    fbFutureFromAsync { [self] in
      try await ensureDeveloperDiskImageIsMountedAsync()
    }
  }

  // MARK: - Async

  fileprivate func mountedDiskImagesAsync() async throws -> [FBDeveloperDiskImage] {
    let mountInfo = try await mountInfoToDiskImageAsync()
    return Array(mountInfo.values)
  }

  fileprivate func unmountDiskImageAsync(_ diskImage: FBDeveloperDiskImage) async throws {
    let entries = try await mountedImageEntriesAsync()
    for mountEntry in entries {
      let mountSignature = mountEntry[ImageSignatureKey] as? Data
      if mountSignature != diskImage.signature {
        continue
      }
      let mountPath = mountEntry[MountPathKey] as! String
      try await unmountDiskImageAtPathAsync(mountPath)
      return
    }
    throw FBDeviceControlError.describe("\(diskImage) does not appear to be mounted").build()
  }

  fileprivate func ensureDeveloperDiskImageIsMountedAsync() async throws -> FBDeveloperDiskImage {
    guard let device else {
      throw FBDeviceControlError().describe("Device is nil").build()
    }
    let targetVersion = FBOSVersion.operatingSystemVersion(fromName: device.productVersion!)
    let diskImage = try FBDeveloperDiskImage.developerDiskImage(targetVersion, logger: device.logger)
    return try await mountDeveloperDiskImageAsync(diskImage, imageType: DiskImageTypeDeveloper)
  }

  // MARK: - Private

  private func mountInfoToDiskImageAsync() async throws -> [NSDictionary: FBDeveloperDiskImage] {
    let logger = device?.logger
    let entries = try await mountedImageEntriesAsync()
    let images = FBDeveloperDiskImage.allDiskImages
    var imagesBySignature: [Data: FBDeveloperDiskImage] = [:]
    for image in images {
      imagesBySignature[image.signature] = image
    }
    var mountEntryToDiskImage: [NSDictionary: FBDeveloperDiskImage] = [:]
    for mountEntry in entries {
      let signature = mountEntry[ImageSignatureKey] as? Data
      var image = signature.flatMap { imagesBySignature[$0] }
      if image == nil {
        logger?.log("Could not find the location of the image mounted on the device \(mountEntry)")
        image = FBDeveloperDiskImage.unknownDiskImage(withSignature: signature ?? Data())
      }
      mountEntryToDiskImage[mountEntry as NSDictionary] = image
    }
    return mountEntryToDiskImage
  }

  private func mountedImageEntriesAsync() async throws -> [[String: Any]] {
    guard let device else {
      throw FBDeviceControlError().describe("Device is nil").build()
    }
    return try await withFBFutureContext(device.startService(ImageMounterService)) { connection in
      let request: [String: Any] = [
        CommandKey: "CopyDevices"
      ]
      let response = try connection.sendAndReceiveMessage(request) as! [String: Any]
      if let errorString = response["Error"] as? String {
        throw FBDeviceControlError.describe("Could not get mounted image info: \(errorString)").build()
      }
      let entries = response["EntryList"] as! [[String: Any]]
      return entries
    }
  }

  private func signatureToDiskImageOfMountedDisksAsync() async throws -> [Data: FBDeveloperDiskImage] {
    let mountInfo = try await mountInfoToDiskImageAsync()
    var signatureToDiskImage: [Data: FBDeveloperDiskImage] = [:]
    for image in mountInfo.values {
      signatureToDiskImage[image.signature] = image
    }
    return signatureToDiskImage
  }

  private func mountDeveloperDiskImageAsync(_ diskImage: FBDeveloperDiskImage, imageType: String) async throws -> FBDeveloperDiskImage {
    let logger = device?.logger
    let signatureToDiskImage = try await signatureToDiskImageOfMountedDisksAsync()
    if signatureToDiskImage[diskImage.signature] != nil {
      logger?.log("Disk Image \(diskImage) is already mounted, avoiding re-mounting it")
      return diskImage
    }
    return try await performDiskImageMountAsync(diskImage, imageType: imageType)
  }

  private func performDiskImageMountAsync(_ diskImage: FBDeveloperDiskImage, imageType: String) async throws -> FBDeveloperDiskImage {
    guard let device else {
      throw FBDeviceControlError().describe("Device is nil").build()
    }
    return try await withFBFutureContext(device.connectToDevice(withPurpose: "mount_disk_image")) { connectedDevice in
      let options: [String: Any] = [
        ImageSignatureKey: diskImage.signature,
        ImageTypeKey: imageType,
      ]
      let context = Unmanaged.passUnretained(connectedDevice as AnyObject).toOpaque()
      let status =
        connectedDevice.calls.MountImage?(
          connectedDevice.amDeviceRef,
          diskImage.diskImagePath as CFString,
          options as CFDictionary,
          mountCallback,
          context
        ) ?? -1
      if status == DiskImageMountingError {
        throw FBDeviceControlError.describe("Failed to mount image '\(diskImage)', this can occur when the wrong disk image is mounted for the target OS, or a disk image of the same type is already mounted.").build()
      } else if status != 0 {
        let internalMessage = connectedDevice.calls.CopyErrorText?(status)?.takeRetainedValue() as String? ?? "Unknown error"
        throw FBDeviceControlError.describe("Failed to mount image '\(diskImage.diskImagePath)' with error 0x\(String(UInt32(bitPattern: status), radix: 16)) (\(internalMessage))").build()
      }
      return diskImage
    }
  }

  private func unmountDiskImageAtPathAsync(_ mountPath: String) async throws {
    guard let device else {
      throw FBDeviceControlError().describe("Device is nil").build()
    }
    try await withFBFutureContext(device.startService(ImageMounterService)) { connection in
      let request: [String: Any] = [
        CommandKey: "UnmountImage",
        MountPathKey: mountPath,
      ]
      _ = try connection.sendAndReceiveMessage(request)
    }
  }
}

// MARK: - FBDevice+FBDeveloperDiskImageCommands

extension FBDevice: FBDeveloperDiskImageCommands {

  @objc public func mountedDiskImages() -> FBFuture<NSArray> {
    do {
      return try developerDiskImageCommands().mountedDiskImages()
    } catch {
      return FBFuture(error: error)
    }
  }

  @objc(mountDiskImage:)
  public func mountDiskImage(_ diskImage: FBDeveloperDiskImage) -> FBFuture<FBDeveloperDiskImage> {
    do {
      return try developerDiskImageCommands().mountDiskImage(diskImage)
    } catch {
      return FBFuture(error: error)
    }
  }

  @objc(unmountDiskImage:)
  public func unmountDiskImage(_ diskImage: FBDeveloperDiskImage) -> FBFuture<NSNull> {
    do {
      return try developerDiskImageCommands().unmountDiskImage(diskImage)
    } catch {
      return FBFuture(error: error)
    }
  }

  @objc public func mountableDiskImages() -> [FBDeveloperDiskImage] {
    do {
      return try developerDiskImageCommands().mountableDiskImages()
    } catch {
      return []
    }
  }

  @objc public func ensureDeveloperDiskImageIsMounted() -> FBFuture<FBDeveloperDiskImage> {
    do {
      return try developerDiskImageCommands().ensureDeveloperDiskImageIsMounted()
    } catch {
      return FBFuture(error: error)
    }
  }
}
