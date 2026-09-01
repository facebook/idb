/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import FBDeviceControl
import Foundation
import Testing

private let ImageMounterService = "com.apple.mobile.mobile_image_mounter"

/// Signatures that cannot match a disk image installed alongside Xcode, so what the mounter
/// reports is resolved the same way whether or not this host has any device support directories.
private let firstSignature = Data([0xF0, 0x0D])
private let secondSignature = Data([0xBE, 0xEF])

@MainActor
// Serialized: these tests drive an `FBAMDevice` whose work and async queues are the main queue,
// from main-actor tests. Run in parallel they interleave on that one queue, which is why the other
// device-driving suites in this target are serialized too.
@Suite(.serialized)
struct FBDeviceDeveloperDiskImageCommandsTests {

  // Fresh per test: each test in a Swift Testing suite gets its own suite instance.
  private let amDevice = FakeAMDevice()

  private var mounter: FakeLockdownService {
    amDevice.service(ImageMounterService)
  }

  private func makeDevice(mounterReplies: [Any]) -> FBDevice {
    let device = amDevice.makeDevice()
    mounter.messageReplies = mounterReplies
    amDevice.clearEvents()
    return device
  }

  private func copyDevicesReply(_ entries: [[String: Any]]) -> [String: Any] {
    ["EntryList": entries]
  }

  // MARK: - Listing what is mounted

  @Test
  func asksTheMounterToCopyDevices() async throws {
    let device = makeDevice(mounterReplies: [copyDevicesReply([])])

    _ = try await device.mountedDiskImages()

    let sent = try #require(mounter.sentMessages.first as? [String: String])
    #expect(sent == ["Command": "CopyDevices"])
  }

  @Test
  func reportsOneImagePerMountedEntry() async throws {
    let device = makeDevice(
      mounterReplies: [
        copyDevicesReply([
          ["ImageSignature": firstSignature, "MountPath": "/Developer"],
          ["ImageSignature": secondSignature, "MountPath": "/Developer2"],
        ])
      ])

    let mounted = try await device.mountedDiskImages()

    #expect(Set(mounted.map(\.signature)) == [firstSignature, secondSignature])
  }

  /// An entry whose signature matches nothing known is still reported, with the signature carried
  /// through, so a caller can unmount an image this host has no copy of.
  @Test
  func reportsUnrecognizedSignaturesRatherThanDroppingThem() async throws {
    let device = makeDevice(
      mounterReplies: [copyDevicesReply([["ImageSignature": firstSignature, "MountPath": "/Developer"]])])

    let mounted = try await device.mountedDiskImages()

    #expect(mounted.count == 1)
    #expect(mounted.first?.signature == firstSignature)
  }

  // MARK: - Listing failures

  @Test
  func failsWhenTheMounterReplyIsNotADictionary() async throws {
    let device = makeDevice(mounterReplies: [["not", "a", "dictionary"]])

    await assertThrows(expected: "is not a dictionary") {
      _ = try await device.mountedDiskImages()
    }
  }

  @Test
  func failsWhenTheMounterReportsAnError() async throws {
    let device = makeDevice(mounterReplies: [["Error": "ImageMountFailed"]])

    await assertThrows(expected: "Could not get mounted image info: ImageMountFailed") {
      _ = try await device.mountedDiskImages()
    }
  }

  @Test
  func failsWhenTheMounterOmitsTheEntryList() async throws {
    let device = makeDevice(mounterReplies: [["Status": "Complete"]])

    await assertThrows(expected: "No EntryList of mounted images") {
      _ = try await device.mountedDiskImages()
    }
  }

  // MARK: - Unmounting

  @Test
  func unmountsTheEntryMatchingTheImageSignature() async throws {
    let device = makeDevice(
      mounterReplies: [
        copyDevicesReply([
          ["ImageSignature": firstSignature, "MountPath": "/Developer"],
          ["ImageSignature": secondSignature, "MountPath": "/Developer2"],
        ]),
        ["Status": "Complete"],
      ])

    try await device.unmountDiskImage(FBDeveloperDiskImage.unknownDiskImage(withSignature: secondSignature))

    let unmount = try #require(mounter.sentMessages.last as? [String: String])
    #expect(unmount == ["Command": "UnmountImage", "MountPath": "/Developer2"])
  }

  @Test
  func failsToUnmountAnImageThatIsNotMounted() async throws {
    let device = makeDevice(
      mounterReplies: [copyDevicesReply([["ImageSignature": firstSignature, "MountPath": "/Developer"]])])

    await assertThrows(expected: "does not appear to be mounted") {
      try await device.unmountDiskImage(FBDeveloperDiskImage.unknownDiskImage(withSignature: secondSignature))
    }
  }

  @Test
  func failsToUnmountAMatchedEntryWithNoMountPath() async throws {
    let device = makeDevice(mounterReplies: [copyDevicesReply([["ImageSignature": firstSignature]])])

    await assertThrows(expected: "No MountPath in mounted image entry") {
      try await device.unmountDiskImage(FBDeveloperDiskImage.unknownDiskImage(withSignature: firstSignature))
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
