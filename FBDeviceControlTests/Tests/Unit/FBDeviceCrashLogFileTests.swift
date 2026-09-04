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

private let CrashReportMoverService = "com.apple.crashreportmover"
private let CrashReportCopyService = "com.apple.crashreportcopymobile"

/// A crash report shaped enough for `FBCrashLogStore` to parse an identifier out of.
private let crashReport = """
  Incident Identifier: 0BADF00D-0000-0000-0000-000000000001
  Hardware Model:      iPhone16,1
  Process:             SomeApp [1234]
  Path:                /private/var/containers/Bundle/Application/SomeApp.app/SomeApp
  Identifier:          com.example.someapp
  Version:             1.0
  Code Type:           ARM-64
  Parent Process:      launchd [1]
  Date/Time:           2026-01-01 00:00:00.000 +0000
  OS Version:          iPhone OS 17.0 (21A000)

  Exception Type:  EXC_CRASH (SIGABRT)
  """

/// The half of crash-log collection that runs over AFC: the mover answers `ping`, then the copy
/// service is listed and read as a remote filesystem.
@MainActor
// Serialized: the fake device's queues are the main queue, so parallel tests would interleave on it.
@Suite(.serialized)
struct FBDeviceCrashLogFileTests {

  private let amDevice = FakeAMDevice()
  private let afc = FakeAFC()

  private func makeDevice(remoteFiles: [String: String]) -> FBDevice {
    let device = amDevice.makeDevice()
    amDevice.service(CrashReportMoverService).readBuffer = Data("ping".utf8)
    amDevice.service(CrashReportCopyService).afc = afc
    afc.setContents(remoteFiles)

    // A store rooted somewhere disposable, and the scripted AFC table in place of MobileDevice's.
    let storeDirectory = (NSTemporaryDirectory() as NSString).appendingPathComponent(UUID().uuidString)
    let store = FBCrashLogStore.store(forDirectories: [storeDirectory], logger: device.logger)
    device.commandCache.register(
      FBDeviceCrashLogCommands(device: device, store: store, afcCalls: afc.calls),
      as: FBDeviceCrashLogCommands.self)
    amDevice.clearEvents()
    return device
  }

  private func allCrashes(_ device: FBDevice) async throws -> [FBCrashLogInfo] {
    try await device.crashes(matching: NSPredicate(value: true), useCache: false)
  }

  // MARK: - Ingesting

  @Test
  func ingestsACrashReportListedByTheCopyService() async throws {
    let device = makeDevice(remoteFiles: ["SomeApp-2026-01-01.ips": crashReport])

    let crashes = try await allCrashes(device)

    #expect(crashes.map(\.name) == ["SomeApp-2026-01-01.ips"])
  }

  @Test
  func ingestsEveryReportInTheListing() async throws {
    let device = makeDevice(remoteFiles: [
      "first.ips": crashReport,
      "second.ips": crashReport,
    ])

    let crashes = try await allCrashes(device)

    #expect(Set(crashes.map(\.name)) == ["first.ips", "second.ips"])
  }

  @Test
  func reportsNothingWhenTheDeviceHasNoCrashes() async throws {
    let device = makeDevice(remoteFiles: [:])

    let crashes = try await allCrashes(device)

    #expect(crashes.isEmpty)
  }

  /// A file the store cannot parse is skipped, not fatal — one bad report must not hide the rest.
  @Test
  func skipsAFileThatIsNotACrashReport() async throws {
    let device = makeDevice(remoteFiles: [
      "garbage.txt": "not a crash report",
      "good.ips": crashReport,
    ])

    let crashes = try await allCrashes(device)

    #expect(crashes.map(\.name) == ["good.ips"])
  }

  // MARK: - Pruning

  @Test
  func pruningRemovesTheReportFromTheDevice() async throws {
    let device = makeDevice(remoteFiles: ["SomeApp-2026-01-01.ips": crashReport])

    let pruned = try await device.pruneCrashes(matching: NSPredicate(value: true))

    #expect(pruned.map(\.name) == ["SomeApp-2026-01-01.ips"])
    #expect(afc.removedPaths == ["SomeApp-2026-01-01.ips"])
  }

  // MARK: - The service interaction

  @Test
  func startsTheMoverThenTheCopyService() async throws {
    let device = makeDevice(remoteFiles: [:])

    _ = try await allCrashes(device)

    let started = amDevice.events.filter { $0.hasPrefix("secure_start_service:") }
    #expect(
      started == [
        "secure_start_service:\(CrashReportMoverService)",
        "secure_start_service:\(CrashReportCopyService)",
      ])
  }
}
