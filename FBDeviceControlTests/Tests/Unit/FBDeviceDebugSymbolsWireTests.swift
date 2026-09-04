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

private let FetchSymbolsService = "com.apple.dt.fetchsymbols"
private let ImageMounterService = "com.apple.mobile.mobile_image_mounter"

private let ListFilesPlistCommand: UInt32 = 0x3030_3030
private let GetFileCommand: UInt32 = 0x0100_0000

/// The service reads and writes fixed-width integers straight onto the connection, so the scripted
/// buffers are assembled in the same byte order the implementation uses: the command words in host
/// order, the file length big-endian on the wire.
private func hostBytes(_ value: UInt32) -> Data {
  withUnsafeBytes(of: value) { Data($0) }
}

private func wireLength(_ value: UInt64) -> Data {
  withUnsafeBytes(of: value.bigEndian) { Data($0) }
}

private func wireIndex(_ value: UInt32) -> Data {
  withUnsafeBytes(of: value.bigEndian) { Data($0) }
}

/// A provider handing back exactly the images a test names.
private struct StubDiskImages: DeveloperDiskImageProviding {
  let availableDiskImages: [FBDeveloperDiskImage]
}

/// Exercises the `com.apple.dt.fetchsymbols` exchange through `FBDevice`'s public API. Every step
/// the device would perform is scripted: the disk image the service requires is already mounted,
/// so the operation reaches the symbol service itself.
@MainActor
// Serialized: the fake device's queues are the main queue, so parallel tests would interleave on it.
@Suite(.serialized)
struct FBDeviceDebugSymbolsWireTests {

  private let amDevice = FakeAMDevice()

  private var symbols: FakeLockdownService {
    amDevice.service(FetchSymbolsService)
  }

  /// Each symbol operation opens its own connection and mounts first, so the mounter is given
  /// enough identical replies to answer however many times it is asked.
  private func makeDevice() -> FBDevice {
    let image = FBDeveloperDiskImage(
      diskImagePath: "/Images/DeveloperDiskImage-17.0.dmg",
      signature: Data([0x01]),
      version: OperatingSystemVersion(majorVersion: 17, minorVersion: 0, patchVersion: 0),
      xcodeVersion: OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0))
    let device = amDevice.makeDevice()
    device.commandCache.register(
      FBDeviceDeveloperDiskImageCommands(device: device, diskImages: StubDiskImages(availableDiskImages: [image])),
      as: FBDeviceDeveloperDiskImageCommands.self)
    let alreadyMounted: [String: Any] = ["EntryList": [["ImageSignature": image.signature, "MountPath": "/Developer"]]]
    amDevice.service(ImageMounterService).repeatingReply = alreadyMounted
    amDevice.clearEvents()
    return device
  }

  // MARK: - Listing

  @Test
  func listsTheSymbolFilesTheServiceReports() async throws {
    let device = makeDevice()
    symbols.readBuffer = hostBytes(ListFilesPlistCommand)
    symbols.messageReplies = [["files": ["/System/Library/Caches/a", "/System/Library/Caches/b"]]]

    let files = try await device.listSymbols()

    #expect(files == ["/System/Library/Caches/a", "/System/Library/Caches/b"])
  }

  @Test
  func sendsTheListFilesCommandWord() async throws {
    let device = makeDevice()
    symbols.readBuffer = hostBytes(ListFilesPlistCommand)
    symbols.messageReplies = [["files": []]]

    _ = try await device.listSymbols()

    #expect(symbols.sentBytes == hostBytes(ListFilesPlistCommand))
  }

  @Test
  func failsWhenTheServiceAcknowledgesWithAnotherCommand() async throws {
    let device = makeDevice()
    symbols.readBuffer = hostBytes(0xDEAD_BEEF)

    await assertThrows(expected: "Incorrect 'ListFilesPlist' ack from symbol service") {
      _ = try await device.listSymbols()
    }
  }

  @Test
  func failsWhenTheListingIsNotStrings() async throws {
    let device = makeDevice()
    symbols.readBuffer = hostBytes(ListFilesPlistCommand)
    symbols.messageReplies = [["files": [1, 2, 3]]]

    await assertThrows(expected: "ListFilesPlist expected Array<String> for 'files' but got [1, 2, 3]") {
      _ = try await device.listSymbols()
    }
  }

  // MARK: - Pulling a file

  @Test
  func pullsTheNamedFileByItsIndexInTheListing() async throws {
    let device = makeDevice()
    let payload = Data("symbol file contents".utf8)
    let destination = (NSTemporaryDirectory() as NSString).appendingPathComponent("pulled-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(atPath: destination) }

    // Two connections: the first resolves the name to an index, the second fetches it.
    symbols.readBuffer =
      hostBytes(ListFilesPlistCommand)
      + hostBytes(GetFileCommand) + wireLength(UInt64(payload.count)) + payload
    symbols.messageReplies = [["files": ["/first", "/wanted"]]]

    let written = try await device.pullSymbolFile("/wanted", toDestinationPath: destination)

    #expect(written == destination)
    #expect(FileManager.default.contents(atPath: destination) == payload)
  }

  /// The index is sent big-endian, unlike the command words either side of it.
  @Test
  func sendsTheFileIndexBigEndian() async throws {
    let device = makeDevice()
    let payload = Data("x".utf8)
    let destination = (NSTemporaryDirectory() as NSString).appendingPathComponent("pulled-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(atPath: destination) }

    symbols.readBuffer =
      hostBytes(ListFilesPlistCommand)
      + hostBytes(GetFileCommand) + wireLength(UInt64(payload.count)) + payload
    symbols.messageReplies = [["files": ["/first", "/wanted"]]]

    _ = try await device.pullSymbolFile("/wanted", toDestinationPath: destination)

    let expected = hostBytes(ListFilesPlistCommand) + hostBytes(GetFileCommand) + wireIndex(1)
    #expect(symbols.sentBytes == expected)
  }

  @Test
  func failsWhenTheNamedFileIsNotInTheListing() async throws {
    let device = makeDevice()
    symbols.readBuffer = hostBytes(ListFilesPlistCommand)
    symbols.messageReplies = [["files": ["/first"]]]

    await assertThrows(expected: "Could not find /absent within") {
      _ = try await device.pullSymbolFile("/absent", toDestinationPath: "/tmp/unused")
    }
  }

  @Test
  func failsWhenTheServiceReportsAZeroLengthFile() async throws {
    let device = makeDevice()
    let destination = (NSTemporaryDirectory() as NSString).appendingPathComponent("pulled-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(atPath: destination) }

    symbols.readBuffer =
      hostBytes(ListFilesPlistCommand)
      + hostBytes(GetFileCommand) + wireLength(0)
    symbols.messageReplies = [["files": ["/wanted"]]]

    await assertThrows(expected: "receiveLength not returned or is zero") {
      _ = try await device.pullSymbolFile("/wanted", toDestinationPath: destination)
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
