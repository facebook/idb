/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBArtifactStaging
@testable import FBControlCore
import Foundation
import Testing

/// A URL install that ends early, because it is cancelled or because what arrives can't be extracted: whether the
/// download it started is stopped, or runs to its last byte. How long the call took is reported, not asserted, as other
/// suites sharing the process can hold up any of the threads it waits on.
@Suite
struct StagingCancellationTests {

  /// How a URL install ended, against a transfer of `total` bytes that takes about 20 seconds: long enough that a call
  /// which waits for it is told apart from one that doesn't on a loaded host.
  struct Ending {
    let returnedAfter: Duration
    let delivered: Int
    let total: Int
    let stoppedEarly: Bool
  }

  private let root = TemporaryDirectory(logger: ControlCoreGlobalConfiguration.defaultLogger).temporaryDirectory()
  private let logger = ControlCoreGlobalConfiguration.defaultLogger

  /// An uncompressed tar of one file of `size` bytes, which extracts as it arrives.
  private func tar(ofFileSized size: Int) throws -> Data {
    let directory = root.appendingPathComponent("payload-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data(repeating: 0x42, count: size).write(to: directory.appendingPathComponent("payload"))
    let archive = root.appendingPathComponent("payload-\(UUID().uuidString).tar")
    try ArchiveFixtures.run("/usr/bin/tar", ["-cf", archive.path, directory.lastPathComponent], in: root)
    return try Data(contentsOf: archive)
  }

  /// Stages `body` from a slow URL, cancelling the call after `cancelAfter` if it is given.
  private func stage(_ body: Data, cancelAfter: Duration?) async throws -> Ending {
    let url = SlowURLProtocol.serving(body, pause: .milliseconds(50))
    let staging = root.appendingPathComponent("staging")
    let task = Task {
      try await Staging.withMaterialized(
        .remoteURL(url), as: .application, downloadConfiguration: SlowURLProtocol.configuration,
        temporaryDirectory: TemporaryDirectory(rootDirectory: staging, logger: logger), logger: logger
      ) { _ in }
    }
    let start = ContinuousClock.now
    if let cancelAfter {
      try await Task.sleep(for: cancelAfter)
      task.cancel()
    }
    _ = await task.result
    let returnedAfter = ContinuousClock.now - start
    let transfer = SlowURLProtocol.transfer(url)
    return Ending(
      returnedAfter: returnedAfter, delivered: transfer?.delivered ?? 0, total: body.count,
      stoppedEarly: transfer?.stopped == true && transfer?.finished != true)
  }

  /// A cancelled URL install stops its transfer and returns without waiting for the rest of it.
  @Test
  func aCancelledURLInstallWaitsForItsTransfer() async throws {
    let ending = try await stage(try tar(ofFileSized: 400 * 64 * 1024), cancelAfter: .milliseconds(300))
    #expect(ending.delivered < ending.total, "delivered \(ending.delivered) of \(ending.total)")
    #expect(ending.stoppedEarly, "returned after \(ending.returnedAfter)")
  }

  /// A URL install whose payload fails extraction stops its transfer and returns without waiting for the rest of it.
  @Test
  func aURLInstallThatCannotBeExtractedWaitsForItsTransfer() async throws {
    let garbage = Data((0..<(400 * 64 * 1024)).map { UInt8(truncatingIfNeeded: $0 &* 2_654_435_761 >> 7) })
    let ending = try await stage(garbage, cancelAfter: nil)
    #expect(ending.delivered < ending.total, "delivered \(ending.delivered) of \(ending.total)")
    #expect(ending.stoppedEarly, "returned after \(ending.returnedAfter)")
  }
}
