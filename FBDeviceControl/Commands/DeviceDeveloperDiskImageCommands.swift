/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation

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

public enum FBDeviceDiskImageError: Error {
  case missingMountPath(key: String, entry: String)
  case imageNotMounted(imageDescription: String)
  case noProductVersion(deviceDescription: String)
  case copyDevicesResponseNotADictionary(response: String)
  case mountedImageInfoUnavailable(message: String)
  case missingEntryList(response: String)
  case wrongImageMounted(imageDescription: String)
  case mountFailed(imagePath: String, status: Int32, message: String)
}

extension FBDeviceDiskImageError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case let .missingMountPath(key, entry):
      return "No \(key) in mounted image entry \(entry)"
    case let .imageNotMounted(imageDescription):
      return "\(imageDescription) does not appear to be mounted"
    case let .noProductVersion(deviceDescription):
      return "No product version available for \(deviceDescription), cannot select a developer disk image"
    case let .copyDevicesResponseNotADictionary(response):
      return "CopyDevices response \(response) is not a dictionary"
    case let .mountedImageInfoUnavailable(message):
      return "Could not get mounted image info: \(message)"
    case let .missingEntryList(response):
      return "No EntryList of mounted images in \(response)"
    case let .wrongImageMounted(imageDescription):
      return "Failed to mount image '\(imageDescription)', this can occur when the wrong disk image is mounted for the target OS, or a disk image of the same type is already mounted."
    case let .mountFailed(imagePath, status, message):
      return "Failed to mount image '\(imagePath)' with error 0x\(String(UInt32(bitPattern: status), radix: 16)) (\(message))"
    }
  }
}

public final class FBDeviceDeveloperDiskImageCommands: DeveloperDiskImageCommands {
  private(set) weak var device: FBDevice?
  private let diskImages: any DeveloperDiskImageProviding

  // MARK: - Initializers

  public class func commands(with device: FBDevice) -> FBDeviceDeveloperDiskImageCommands {
    FBDeviceDeveloperDiskImageCommands(device: device)
  }

  init(device: FBDevice, diskImages: any DeveloperDiskImageProviding = InstalledDeveloperDiskImages()) {
    self.device = device
    self.diskImages = diskImages
  }

  // MARK: - DeveloperDiskImageCommands

  public func mountedDiskImages() async throws -> [FBDeveloperDiskImage] {
    let mountInfo = try await mountInfoToDiskImage()
    return Array(mountInfo.values)
  }

  public func mountDiskImage(_ diskImage: FBDeveloperDiskImage) async throws -> FBDeveloperDiskImage {
    try await mountDeveloperDiskImage(diskImage, imageType: DiskImageTypeDeveloper)
  }

  public func unmountDiskImage(_ diskImage: FBDeveloperDiskImage) async throws {
    let entries = try await mountedImageEntries()
    for mountEntry in entries {
      let mountSignature = mountEntry[ImageSignatureKey] as? Data
      if mountSignature != diskImage.signature {
        continue
      }
      guard let mountPath = mountEntry[MountPathKey] as? String else {
        throw FBDeviceDiskImageError.missingMountPath(key: MountPathKey, entry: String(describing: mountEntry))
      }
      try await unmountDiskImageAtPath(mountPath)
      return
    }
    throw FBDeviceDiskImageError.imageNotMounted(imageDescription: String(describing: diskImage))
  }

  public func mountableDiskImages() -> [FBDeveloperDiskImage] {
    return diskImages.availableDiskImages
  }

  public func ensureDeveloperDiskImageIsMounted() async throws -> FBDeveloperDiskImage {
    guard let device else {
      throw FBDeviceNilError.deviceNil
    }
    guard let productVersion = device.productVersion else {
      throw FBDeviceDiskImageError.noProductVersion(deviceDescription: String(describing: device))
    }
    let targetVersion = FBOSVersion.operatingSystemVersion(fromName: productVersion)
    let diskImage = try FBDeveloperDiskImage.bestImage(
      forImages: diskImages.availableDiskImages,
      targetVersion: targetVersion,
      logger: device.logger)
    return try await mountDeveloperDiskImage(diskImage, imageType: DiskImageTypeDeveloper)
  }

  // MARK: - Private

  private func mountInfoToDiskImage() async throws -> [NSDictionary: FBDeveloperDiskImage] {
    let logger = device?.logger
    let entries = try await mountedImageEntries()
    let images = diskImages.availableDiskImages
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

  private func mountedImageEntries() async throws -> [[String: Any]] {
    guard let device else {
      throw FBDeviceNilError.deviceNil
    }
    return try await device.withServiceConnection(ImageMounterService) { connection in
      let request: [String: Any] = [
        CommandKey: "CopyDevices"
      ]
      let message = try connection.sendAndReceiveMessage(request)
      guard let response = message as? [String: Any] else {
        throw FBDeviceDiskImageError.copyDevicesResponseNotADictionary(response: String(describing: message))
      }
      if let errorString = response["Error"] as? String {
        throw FBDeviceDiskImageError.mountedImageInfoUnavailable(message: errorString)
      }
      guard let entries = response["EntryList"] as? [[String: Any]] else {
        throw FBDeviceDiskImageError.missingEntryList(response: String(describing: response))
      }
      return entries
    }
  }

  private func signatureToDiskImageOfMountedDisks() async throws -> [Data: FBDeveloperDiskImage] {
    let mountInfo = try await mountInfoToDiskImage()
    var signatureToDiskImage: [Data: FBDeveloperDiskImage] = [:]
    for image in mountInfo.values {
      signatureToDiskImage[image.signature] = image
    }
    return signatureToDiskImage
  }

  private func mountDeveloperDiskImage(_ diskImage: FBDeveloperDiskImage, imageType: String) async throws -> FBDeveloperDiskImage {
    let logger = device?.logger
    let signatureToDiskImage = try await signatureToDiskImageOfMountedDisks()
    if signatureToDiskImage[diskImage.signature] != nil {
      logger?.log("Disk Image \(diskImage) is already mounted, avoiding re-mounting it")
      return diskImage
    }
    return try await performDiskImageMount(diskImage, imageType: imageType)
  }

  private func performDiskImageMount(_ diskImage: FBDeveloperDiskImage, imageType: String) async throws -> FBDeveloperDiskImage {
    guard let device else {
      throw FBDeviceNilError.deviceNil
    }
    return try await device.withConnectedDevice(purpose: "mount_disk_image") { connectedDevice in
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
        throw FBDeviceDiskImageError.wrongImageMounted(imageDescription: String(describing: diskImage))
      } else if status != 0 {
        let internalMessage = connectedDevice.calls.CopyErrorText?(status)?.takeRetainedValue() as String? ?? "Unknown error"
        throw FBDeviceDiskImageError.mountFailed(imagePath: diskImage.diskImagePath, status: status, message: internalMessage)
      }
      return diskImage
    }
  }

  private func unmountDiskImageAtPath(_ mountPath: String) async throws {
    guard let device else {
      throw FBDeviceNilError.deviceNil
    }
    try await device.withServiceConnection(ImageMounterService) { connection in
      let request: [String: Any] = [
        CommandKey: "UnmountImage",
        MountPathKey: mountPath,
      ]
      _ = try connection.sendAndReceiveMessage(request)
    }
  }
}

// MARK: - FBDevice+DeveloperDiskImageCommands

extension FBDevice: DeveloperDiskImageCommands {

  public func mountedDiskImages() async throws -> [FBDeveloperDiskImage] {
    try await developerDiskImage.mountedDiskImages()
  }

  public func mountDiskImage(_ diskImage: FBDeveloperDiskImage) async throws -> FBDeveloperDiskImage {
    try await developerDiskImage.mountDiskImage(diskImage)
  }

  public func unmountDiskImage(_ diskImage: FBDeveloperDiskImage) async throws {
    try await developerDiskImage.unmountDiskImage(diskImage)
  }

  public func mountableDiskImages() -> [FBDeveloperDiskImage] {
    developerDiskImage.mountableDiskImages()
  }

  public func ensureDeveloperDiskImageIsMounted() async throws -> FBDeveloperDiskImage {
    try await developerDiskImage.ensureDeveloperDiskImageIsMounted()
  }

}
