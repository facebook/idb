/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBDeviceControl
import Foundation
import Testing

private let ImageMounterService = "com.apple.mobile.mobile_image_mounter"

/// The status MobileDevice returns when the image does not suit the OS on the device.
private let WrongImageStatus: Int32 = -402653066

/// A provider handing back exactly the images a test names.
private struct StubDiskImages: DeveloperDiskImageProviding {
  let availableDiskImages: [FBDeveloperDiskImage]
}

@MainActor
// Serialized: these tests drive an `FBAMDevice` whose work and async queues are the main queue,
// from main-actor tests. Run in parallel they interleave on that one queue, which is why the other
// device-driving suites in this target are serialized too.
@Suite(.serialized)
struct FBDeviceDiskImageMountingTests {

  // Fresh per test: each test in a Swift Testing suite gets its own suite instance.
  private let amDevice = FakeAMDevice()

  private func diskImage(_ major: Int, _ minor: Int, signature: Data) -> FBDeveloperDiskImage {
    FBDeveloperDiskImage(
      diskImagePath: "/Images/DeveloperDiskImage-\(major).\(minor).dmg",
      signature: signature,
      version: OperatingSystemVersion(majorVersion: major, minorVersion: minor, patchVersion: 0),
      xcodeVersion: OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0))
  }

  /// Wires a device whose only available images are the ones given, so selection is decided by the
  /// test rather than by whatever device support directories this host happens to have.
  private func makeDevice(
    productVersion: String? = "17.0",
    available: [FBDeveloperDiskImage],
    mounted: [FBDeveloperDiskImage] = []
  ) -> FBDevice {
    if let productVersion {
      amDevice.values["ProductVersion"] = productVersion
    } else {
      amDevice.values.removeValue(forKey: "ProductVersion")
    }
    let device = amDevice.makeDevice()
    device.commandCache.register(
      FBDeviceDeveloperDiskImageCommands(device: device, diskImages: StubDiskImages(availableDiskImages: available)),
      as: FBDeviceDeveloperDiskImageCommands.self)
    amDevice.service(ImageMounterService).messageReplies = [
      ["EntryList": mounted.map { ["ImageSignature": $0.signature, "MountPath": "/Developer"] }]
    ]
    amDevice.clearEvents()
    return device
  }

  // MARK: - Selecting and mounting

  @Test
  func mountsTheImageMatchingTheDeviceOSVersion() async throws {
    let matching = diskImage(17, 0, signature: Data([0x01]))
    let device = makeDevice(available: [diskImage(16, 0, signature: Data([0x02])), matching])

    let mounted = try await device.ensureDeveloperDiskImageIsMounted()

    #expect(mounted.diskImagePath == matching.diskImagePath)
    #expect(amDevice.mountedImagePaths == [matching.diskImagePath])
  }

  /// An exact minor match is not required — the closest image of the same major version is used.
  @Test
  func mountsTheClosestImageOfTheSameMajorVersion() async throws {
    let device = makeDevice(
      productVersion: "17.4",
      available: [diskImage(16, 0, signature: Data([0x02])), diskImage(17, 0, signature: Data([0x01]))])

    let mounted = try await device.ensureDeveloperDiskImageIsMounted()

    #expect(mounted.version.majorVersion == 17)
    #expect(amDevice.mountedImagePaths == ["/Images/DeveloperDiskImage-17.0.dmg"])
  }

  @Test
  func doesNotRemountAnImageAlreadyMounted() async throws {
    let alreadyMounted = diskImage(17, 0, signature: Data([0x01]))
    let device = makeDevice(available: [alreadyMounted], mounted: [alreadyMounted])

    let mounted = try await device.ensureDeveloperDiskImageIsMounted()

    #expect(mounted.diskImagePath == alreadyMounted.diskImagePath)
    #expect(amDevice.mountedImagePaths == [], "the image was already mounted, so nothing should be mounted again")
  }

  // MARK: - Failures

  @Test
  func failsWhenTheDeviceReportsNoProductVersion() async throws {
    let device = makeDevice(productVersion: nil, available: [diskImage(17, 0, signature: Data([0x01]))])

    await assertThrows(expected: "No product version available") {
      _ = try await device.ensureDeveloperDiskImageIsMounted()
    }
  }

  @Test
  func failsWhenNoImageSharesTheDeviceMajorVersion() async throws {
    let device = makeDevice(available: [diskImage(16, 0, signature: Data([0x02]))])

    await assertThrows(expected: "is not suitable for 17.0") {
      _ = try await device.ensureDeveloperDiskImageIsMounted()
    }
  }

  @Test
  func failsWhenNoImagesAreAvailableAtAll() async throws {
    let device = makeDevice(available: [])

    await assertThrows(expected: "No disk images provided") {
      _ = try await device.ensureDeveloperDiskImageIsMounted()
    }
  }

  @Test
  func reportsAMountFailureWithItsStatus() async throws {
    amDevice.mountImageStatus = 5
    let device = makeDevice(available: [diskImage(17, 0, signature: Data([0x01]))])

    await assertThrows(expected: "Failed to mount image '/Images/DeveloperDiskImage-17.0.dmg'") {
      _ = try await device.ensureDeveloperDiskImageIsMounted()
    }
  }

  /// The one status singled out from the rest, because it is the common operator error.
  @Test
  func reportsTheWrongImageStatusDistinctly() async throws {
    amDevice.mountImageStatus = WrongImageStatus
    let device = makeDevice(available: [diskImage(17, 0, signature: Data([0x01]))])

    await assertThrows(expected: "the wrong disk image is mounted") {
      _ = try await device.ensureDeveloperDiskImageIsMounted()
    }
  }

  // MARK: - Helpers

  private func assertThrows(
    expected: String,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column),
    _ body: () async throws -> Void
  ) async {
    do {
      try await body()
      Issue.record("Expected a failure containing '\(expected)'", sourceLocation: sourceLocation)
    } catch {
      let description = (error as NSError).localizedDescription
      #expect(description.contains(expected), "got '\(description)'", sourceLocation: sourceLocation)
    }
  }
}
