// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

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
  guard let context = context, let callbackDictionary = callbackDictionary else { return }
  let device = Unmanaged<AnyObject>.fromOpaque(context).takeUnretainedValue()
  if let logger = (device as? (any FBDeviceCommands))?.logger {
    logger.log("Mount Progress: \(FBCollectionInformation.oneLineDescription(from: callbackDictionary))")
  }
}

@objc(FBDeviceDeveloperDiskImageCommands)
public class FBDeviceDeveloperDiskImageCommands: NSObject, FBDeveloperDiskImageCommands {
  private(set) weak var device: FBDevice?

  // MARK: Initializers

  @objc public class func commands(with target: any FBiOSTarget) -> Self {
    return unsafeDowncast(FBDeviceDeveloperDiskImageCommands(device: target as! FBDevice), to: self)
  }

  init(device: FBDevice) {
    self.device = device
    super.init()
  }

  // MARK: FBDeveloperDiskImageCommands Implementation

  @objc public func mountedDiskImages() -> FBFuture<NSArray> {
    return mountInfoToDiskImage().onQueue(
      device!.asyncQueue,
      map: { (mountInfoToDiskImage: AnyObject) -> AnyObject in
        let dict = mountInfoToDiskImage as! NSDictionary
        return dict.allValues as NSArray as AnyObject
      }) as! FBFuture<NSArray>
  }

  @objc public func mountDiskImage(_ diskImage: FBDeveloperDiskImage) -> FBFuture<FBDeveloperDiskImage> {
    return mountDeveloperDiskImage(diskImage, imageType: DiskImageTypeDeveloper)
  }

  @objc public func unmountDiskImage(_ diskImage: FBDeveloperDiskImage) -> FBFuture<NSNull> {
    return mountedImageEntries().onQueue(
      device!.workQueue,
      fmap: { (entries: AnyObject) -> FBFuture<AnyObject> in
        let mountEntries = entries as! [[String: Any]]
        for mountEntry in mountEntries {
          let mountSignature = mountEntry[ImageSignatureKey] as? Data
          if mountSignature != diskImage.signature {
            continue
          }
          let mountPath = mountEntry[MountPathKey] as! String
          return self.unmountDiskImageAtPath(mountPath) as! FBFuture<AnyObject>
        }
        return FBDeviceControlError.describe("\(diskImage) does not appear to be mounted").failFuture()
      }) as! FBFuture<NSNull>
  }

  @objc public func mountableDiskImages() -> [FBDeveloperDiskImage] {
    return FBDeveloperDiskImage.allDiskImages
  }

  @objc public func ensureDeveloperDiskImageIsMounted() -> FBFuture<FBDeveloperDiskImage> {
    let targetVersion = FBOSVersion.operatingSystemVersion(fromName: device!.productVersion!)
    let diskImage: FBDeveloperDiskImage
    do {
      diskImage = try FBDeveloperDiskImage.developerDiskImage(targetVersion, logger: device!.logger)
    } catch {
      return FBFuture(error: error)
    }
    return mountDeveloperDiskImage(diskImage, imageType: DiskImageTypeDeveloper)
  }

  // MARK: Private

  private func mountInfoToDiskImage() -> FBFuture<NSDictionary> {
    let logger = device?.logger
    return mountedImageEntries().onQueue(
      device!.asyncQueue,
      map: { (entries: AnyObject) -> AnyObject in
        let mountEntries = entries as! [[String: Any]]
        let images = FBDeveloperDiskImage.allDiskImages
        var imagesBySignature: [Data: FBDeveloperDiskImage] = [:]
        for image in images {
          imagesBySignature[image.signature] = image
        }
        var mountEntryToDiskImage: [NSDictionary: FBDeveloperDiskImage] = [:]
        for mountEntry in mountEntries {
          let signature = mountEntry[ImageSignatureKey] as? Data
          var image = signature.flatMap { imagesBySignature[$0] }
          if image == nil {
            logger?.log("Could not find the location of the image mounted on the device \(mountEntry)")
            image = FBDeveloperDiskImage.unknownDiskImage(withSignature: signature ?? Data())
          }
          mountEntryToDiskImage[mountEntry as NSDictionary] = image
        }
        return mountEntryToDiskImage as NSDictionary as AnyObject
      }) as! FBFuture<NSDictionary>
  }

  private func mountedImageEntries() -> FBFuture<NSArray> {
    return device!.startService(ImageMounterService).onQueue(
      device!.asyncQueue,
      pop: { (connection: AnyObject) -> FBFuture<AnyObject> in
        let conn = connection as! FBAMDServiceConnection
        let request: [String: Any] = [
          CommandKey: "CopyDevices"
        ]
        do {
          let response = try conn.sendAndReceiveMessage(request) as! [String: Any]
          if let errorString = response["Error"] as? String {
            return FBDeviceControlError.describe("Could not get mounted image info: \(errorString)").failFuture()
          }
          let entries = response["EntryList"] as! NSArray
          return FBFuture(result: entries as AnyObject)
        } catch {
          return FBFuture(error: error)
        }
      }) as! FBFuture<NSArray>
  }

  private func signatureToDiskImageOfMountedDisks() -> FBFuture<NSDictionary> {
    return mountInfoToDiskImage().onQueue(
      device!.asyncQueue,
      map: { (mountInfo: AnyObject) -> AnyObject in
        let mountInfoToDiskImage = mountInfo as! [NSDictionary: FBDeveloperDiskImage]
        var signatureToDiskImage: [Data: FBDeveloperDiskImage] = [:]
        for image in mountInfoToDiskImage.values {
          signatureToDiskImage[image.signature] = image
        }
        return signatureToDiskImage as NSDictionary as AnyObject
      }) as! FBFuture<NSDictionary>
  }

  private func mountDeveloperDiskImage(_ diskImage: FBDeveloperDiskImage, imageType: String) -> FBFuture<FBDeveloperDiskImage> {
    let logger = device?.logger
    return signatureToDiskImageOfMountedDisks().onQueue(
      device!.asyncQueue,
      fmap: { (sigToImage: AnyObject) -> FBFuture<AnyObject> in
        let signatureToDiskImage = sigToImage as! [Data: FBDeveloperDiskImage]
        if signatureToDiskImage[diskImage.signature] != nil {
          logger?.log("Disk Image \(diskImage) is already mounted, avoiding re-mounting it")
          return FBFuture(result: diskImage as AnyObject)
        }
        return self.performDiskImageMount(diskImage, imageType: imageType) as! FBFuture<AnyObject>
      }) as! FBFuture<FBDeveloperDiskImage>
  }

  private func performDiskImageMount(_ diskImage: FBDeveloperDiskImage, imageType: String) -> FBFuture<FBDeveloperDiskImage> {
    return device!.connectToDevice(withPurpose: "mount_disk_image").onQueue(
      device!.asyncQueue,
      pop: { (d: AnyObject) -> FBFuture<AnyObject> in
        let device = d as! any FBDeviceCommands
        let options: [String: Any] = [
          ImageSignatureKey: diskImage.signature,
          ImageTypeKey: imageType,
        ]
        let context = Unmanaged.passUnretained(device as AnyObject).toOpaque()
        let status =
          device.calls.MountImage?(
            device.amDeviceRef,
            diskImage.diskImagePath as CFString,
            options as CFDictionary,
            mountCallback,
            context
          ) ?? -1
        if status == DiskImageMountingError {
          return FBDeviceControlError.describe("Failed to mount image '\(diskImage)', this can occur when the wrong disk image is mounted for the target OS, or a disk image of the same type is already mounted.").failFuture()
        } else if status != 0 {
          let internalMessage = device.calls.CopyErrorText?(status)?.takeRetainedValue() as String? ?? "Unknown error"
          return FBDeviceControlError.describe("Failed to mount image '\(diskImage.diskImagePath)' with error 0x\(String(UInt32(bitPattern: status), radix: 16)) (\(internalMessage))").failFuture()
        }
        return FBFuture(result: diskImage as AnyObject)
      }) as! FBFuture<FBDeveloperDiskImage>
  }

  private func unmountDiskImageAtPath(_ mountPath: String) -> FBFuture<NSNull> {
    return device!.startService(ImageMounterService).onQueue(
      device!.asyncQueue,
      pop: { (connection: AnyObject) -> FBFuture<AnyObject> in
        let conn = connection as! FBAMDServiceConnection
        let request: [String: Any] = [
          CommandKey: "UnmountImage",
          MountPathKey: mountPath,
        ]
        do {
          let _ = try conn.sendAndReceiveMessage(request)
          return FBFuture<NSNull>.empty() as! FBFuture<AnyObject>
        } catch {
          return FBFuture(error: error)
        }
      }) as! FBFuture<NSNull>
  }
}
