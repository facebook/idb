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

private let CrashReportMoverService = "com.apple.crashreportmover"

/// The handshake every crash-log operation performs before it reaches the file service: the mover
/// is started and must answer `ping`. This is the half of crash-log collection that needs no AFC,
/// so it is reachable through `FBDevice`'s public API as things stand.
@MainActor
// Serialized: these tests drive an `FBAMDevice` whose work and async queues are the main queue,
// from main-actor tests. Run in parallel they interleave on that one queue, which is why the other
// device-driving suites in this target are serialized too.
@Suite(.serialized)
struct FBDeviceCrashLogPingbackTests {

  // Fresh per test: each test in a Swift Testing suite gets its own suite instance.
  private let amDevice = FakeAMDevice()

  private var mover: FakeLockdownService {
    amDevice.service(CrashReportMoverService)
  }

  private func makeDevice(answering answer: Data?) -> FBDevice {
    let device = amDevice.makeDevice()
    if let answer {
      mover.readBuffer = answer
    }
    amDevice.clearEvents()
    return device
  }

  private func collectCrashes(_ device: FBDevice) async throws {
    _ = try await device.crashes(matching: NSPredicate(value: true), useCache: false)
  }

  /// The mover is the first service started — the copy service must not be reached before the
  /// mover has answered.
  @Test
  func startsTheMoverServiceFirst() async throws {
    let device = makeDevice(answering: Data("nope".utf8))

    try? await collectCrashes(device)

    let started = amDevice.events.filter { $0.hasPrefix("secure_start_service:") }
    #expect(started.first == "secure_start_service:\(CrashReportMoverService)")
  }

  @Test
  func failsWhenTheMoverAnswersSomethingOtherThanPing() async throws {
    let device = makeDevice(answering: Data("nope".utf8))

    let error = await capture { try await collectCrashes(device) }

    #expect(error == "Pingback from \(CrashReportMoverService) is 'nope' not 'ping'")
  }

  @Test
  func failsWhenTheMoverAnswersNothing() async throws {
    let device = makeDevice(answering: nil)

    let error = await capture { try await collectCrashes(device) }

    #expect(error == "Failed to get pingback from \(CrashReportMoverService)")
  }

  /// The pingback is read as ASCII, so bytes that are not decodable are reported as such rather
  /// than compared as an empty string.
  @Test
  func failsWhenTheMoverAnswerIsNotDecodable() async throws {
    let device = makeDevice(answering: Data([0xFF, 0xFE, 0xFD, 0xFC]))

    let error = await capture { try await collectCrashes(device) }

    #expect(error == "Failed to decode pingback from \(CrashReportMoverService)")
  }

  /// The connection is released whichever way the handshake ends.
  @Test
  func invalidatesTheMoverConnectionAfterAFailedHandshake() async throws {
    let device = makeDevice(answering: Data("nope".utf8))

    try? await collectCrashes(device)

    #expect(mover.isInvalidated)
  }

  // MARK: - Helpers

  private func capture(_ body: () async throws -> Void) async -> String? {
    do {
      try await body()
      return nil
    } catch {
      return (error as NSError).localizedDescription
    }
  }
}
