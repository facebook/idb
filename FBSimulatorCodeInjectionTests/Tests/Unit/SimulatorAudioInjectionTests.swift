/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Darwin
@testable import FBSimulatorCodeInjection
import Foundation
// Matches the XCTest-based suite this moved from (SimulatorAudioSettingsTests et al. in FBSimulatorControl).
// ast-grep-ignore: swift-testing/swift/no-new-xctest
import XCTest

final class SimulatorAudioInjectionTests: XCTestCase {
  private typealias Commands = SimulatorAudioInjectionCommands

  private func appEnvironment(
    _ requested: [String: String] = [:], inherited: String = ""
  ) -> [String: String] {
    Commands.appLaunchEnvironment(
      requested, shimPath: "/tmp/current/libShimulator-iOS.dylib", inheritedLibraries: inherited)
  }

  private func report(
    _ state: Commands.InjectionState, _ process: String = "Recorder", message: String? = nil, alive: Bool = true
  ) -> Commands.InjectionReport {
    Commands.InjectionReport(state: state, process: process, message: message, processIsAlive: alive)
  }

  private func progress(
    _ reports: [Commands.InjectionReport], after previous: Commands.InjectionProgress? = nil, claimed: Bool = false,
    claimExpired: Bool = false, playbackExpired: Bool = false
  ) -> Commands.InjectionProgress {
    Commands.injectionProgress(
      reports: reports, claimed: previous?.claimed ?? claimed,
      confirmingCompletion: previous?.confirmingCompletion ?? false, claimExpired: claimExpired,
      playbackExpired: playbackExpired)
  }

  func testAutomaticallyPreparesOnlyTheAppEnvironment() {
    let original = ["MAGIC": "unchanged"]
    let prepared = appEnvironment(original, inherited: "/tmp/libProfiler.dylib")
    XCTAssertEqual(prepared["IDB_AUDIO_INJECTION"], "1")
    XCTAssertEqual(prepared["DYLD_INSERT_LIBRARIES"], "/tmp/libProfiler.dylib:/tmp/current/libShimulator-iOS.dylib")
    XCTAssertEqual(prepared["MAGIC"], "unchanged")
    XCTAssertEqual(original, ["MAGIC": "unchanged"])
    XCTAssertEqual(appEnvironment(prepared), prepared)
  }

  func testCallerLibrariesReplaceInheritedAndKeepRepl() {
    let prepared = appEnvironment(
      ["DYLD_INSERT_LIBRARIES": "/tmp/old/libShimulator-iOS.dylib:/tmp/libProfiler.dylib:/tmp/libRepl-iOS.dylib"],
      inherited: "/tmp/inherited/libProfiler.dylib")
    XCTAssertEqual(
      prepared["DYLD_INSERT_LIBRARIES"],
      "/tmp/libProfiler.dylib:/tmp/libRepl-iOS.dylib:/tmp/current/libShimulator-iOS.dylib")
  }

  func testInheritedOldShimIsReplaced() {
    let prepared = appEnvironment(inherited: "/tmp/old/libShimulator-iOS.dylib:/tmp/libProfiler.dylib")
    XCTAssertEqual(prepared["DYLD_INSERT_LIBRARIES"], "/tmp/libProfiler.dylib:/tmp/current/libShimulator-iOS.dylib")
    XCTAssertEqual(
      appEnvironment(["DYLD_INSERT_LIBRARIES": ""], inherited: "/tmp/libProfiler.dylib")["DYLD_INSERT_LIBRARIES"],
      "/tmp/current/libShimulator-iOS.dylib")
  }

  func testExplicitAppArmingValuesArePreserved() {
    for value in ["1", "0", "", "custom"] {
      XCTAssertEqual(appEnvironment(["IDB_AUDIO_INJECTION": value])["IDB_AUDIO_INJECTION"], value)
    }
  }

  func testAnUnpreparedLaunchStillGoesAheadAndExplainsTheUnclaimedInjection() async {
    struct LaunchctlFailed: LocalizedError {
      var errorDescription: String? { "launchctl getenv exited 1" }
    }
    let preparation = AudioInjectionPreparation()
    var logged: [String] = []
    let original = ["MAGIC": "unchanged"]

    let unprepared = await Commands.appLaunchEnvironment(
      original, recordingIn: preparation, log: { logged.append($0) }, prepare: { throw LaunchctlFailed() })

    XCTAssertEqual(unprepared, original)
    XCTAssertEqual(preparation.lastFailure, "launchctl getenv exited 1")
    XCTAssertEqual(logged, ["Launching the app without microphone injection: launchctl getenv exited 1"])
    let unclaimed = AudioInjectionError.unclaimed(
      udid: "UDID", preparationFailure: preparation.lastFailure
    ).localizedDescription
    XCTAssertTrue(
      unclaimed.contains("could not be prepared for microphone injection, so it could not hear injected audio: launchctl getenv exited 1."),
      unclaimed)
    XCTAssertTrue(unclaimed.contains("have it start recording"), unclaimed)
  }

  func testAPreparedLaunchClearsAnEarlierFailure() async {
    let preparation = AudioInjectionPreparation()
    preparation.record(failure: "the shim is missing")

    let prepared = await Commands.appLaunchEnvironment(
      [:], recordingIn: preparation, log: { XCTFail("unexpected log: \($0)") },
      prepare: { ["IDB_AUDIO_INJECTION": "1"] })

    XCTAssertEqual(prepared, ["IDB_AUDIO_INJECTION": "1"])
    XCTAssertNil(preparation.lastFailure)
    let unclaimed = AudioInjectionError.unclaimed(
      udid: "UDID", preparationFailure: preparation.lastFailure
    ).localizedDescription
    XCTAssertFalse(unclaimed.contains("could not be prepared"), unclaimed)
    XCTAssertTrue(unclaimed.contains("Launch the app under test through idb"), unclaimed)
  }

  func testDefersIsolatedGuestFailureUntilTheClaimDeadline() {
    let reports = [report(.failed, message: "permission denied")]
    XCTAssertEqual(progress(reports).decision, .wait)
    XCTAssertEqual(
      progress(reports, claimExpired: true).decision, .failed(process: "Recorder", message: "permission denied"))
  }

  func testMixedFinishedAndPlayingReportsFailAtThePlaybackDeadline() {
    let reports = [report(.finished, "First"), report(.playing, "Second")]
    XCTAssertEqual(progress(reports, claimed: true, claimExpired: true, playbackExpired: true).decision, .didNotFinish)
  }

  func testFinishedReportIsConfirmedBeforeCompleting() {
    let first = progress([report(.finished)])
    XCTAssertEqual(first.decision, .wait)
    XCTAssertEqual(progress([report(.finished)], after: first).decision, .completed)
  }

  func testCompletionConfirmationResetsWhenALateResponderAppears() {
    let finished = report(.finished, "First")
    let first = progress([finished], claimed: true)
    XCTAssertTrue(first.confirmingCompletion)

    let late = progress([finished, report(.playing, "Late")], after: first)
    XCTAssertEqual(late.decision, .wait)
    XCTAssertFalse(late.confirmingCompletion)

    let settled = progress([finished], after: late)
    XCTAssertEqual(settled.decision, .wait)
    XCTAssertTrue(settled.confirmingCompletion)
  }

  func testFinishedReportIgnoresExitedPlayingProcess() {
    let reports = [report(.playing, "ExitedRecorder", alive: false), report(.finished)]
    let first = progress(reports, claimed: true, claimExpired: true)
    XCTAssertEqual(first.decision, .wait)
    XCTAssertEqual(progress(reports, after: first, claimExpired: true).decision, .completed)
  }

  func testUnclaimedInjectionFailsAtTheClaimDeadline() {
    XCTAssertEqual(progress([], claimExpired: true).decision, .unclaimed)
  }

  // MARK: - Bounded host WAV input

  func testWAVReadsThe32MiBLimitToEOFAndRejectsKnownOversizeBeforeReading() throws {
    // GIVEN
    let directory = try makeWAVDirectory()
    defer { removeWAVDirectory(directory) }
    let url = directory.appendingPathComponent("boundary.wav")
    try writeWAVFixture(Self.oneSampleWAV, to: url, size: Self.wavLimit)
    var descriptors: [Int32] = []
    var requests: [Int] = []
    var counts: [Int] = []
    var total = 0

    // WHEN
    let audio = try XCTUnwrap(
      Commands.wav(
        of: url,
        read: { descriptor, buffer, requested in
          descriptors.append(descriptor)
          requests.append(requested)
          XCTAssertGreaterThan(requested, 0)
          XCTAssertLessThanOrEqual(requested, min(65_536, Self.wavLimit + 1 - total))
          guard requested <= Self.wavLimit + 1 - total else { throw WAVFixtureError.invalidReadRequest }
          if counts.isEmpty {
            let statusFlags = fcntl(descriptor, F_GETFL)
            let descriptorFlags = fcntl(descriptor, F_GETFD)
            XCTAssertGreaterThanOrEqual(statusFlags, 0)
            XCTAssertGreaterThanOrEqual(descriptorFlags, 0)
            XCTAssertNotEqual(statusFlags & O_NONBLOCK, 0)
            XCTAssertNotEqual(descriptorFlags & FD_CLOEXEC, 0)
          }
          let count = try self.readWAVFixture(descriptor, into: buffer, requested: requested)
          XCTAssertLessThanOrEqual(count, requested)
          total += count
          counts.append(count)
          return count
        }))

    // THEN
    try assertWAVDescriptorClosed(descriptors.first)
    XCTAssertEqual(Set(descriptors).count, 1)
    XCTAssertEqual(requests.last, 1)
    XCTAssertEqual(counts.last, 0)
    XCTAssertTrue(counts.dropLast().allSatisfy { $0 > 0 })
    XCTAssertEqual(total, Self.wavLimit)
    XCTAssertEqual(audio.data.count, Self.wavLimit)
    XCTAssertEqual(Data(audio.data.prefix(Self.oneSampleWAV.count)), Self.oneSampleWAV)
    XCTAssertEqual(audio.duration, .seconds(1.0 / 8_000))

    try resizeWAVFixture(url, to: Self.wavLimit + 3)
    var oversizeReads = 0
    XCTAssertThrowsError(
      try Commands.wav(
        of: url,
        read: { descriptor, buffer, requested in
          oversizeReads += 1
          return try self.readWAVFixture(descriptor, into: buffer, requested: requested)
        })
    ) { error in
      self.assertWAVTooLarge(error, path: url.path, size: Self.wavLimit + 3)
    }
    XCTAssertEqual(oversizeReads, 0)
  }

  func testWAVGrowthAfterAdmissionReadsOnlyLimitPlusOneAndCloses() throws {
    // GIVEN
    let directory = try makeWAVDirectory()
    defer { removeWAVDirectory(directory) }
    let url = directory.appendingPathComponent("growing.wav")
    try writeWAVFixture(Self.oneSampleWAV, to: url)
    var descriptors: [Int32] = []
    var requests: [Int] = []
    var total = 0

    // WHEN
    XCTAssertThrowsError(
      try Commands.wav(
        of: url,
        read: { descriptor, buffer, requested in
          if descriptors.isEmpty {
            var metadata = stat()
            guard fstat(descriptor, &metadata) == 0 else { throw self.wavPOSIXError() }
            XCTAssertEqual(metadata.st_size, off_t(Self.oneSampleWAV.count))
            try self.resizeWAVFixture(url, to: Self.wavLimit + 3)
          }
          descriptors.append(descriptor)
          requests.append(requested)
          XCTAssertGreaterThan(requested, 0)
          XCTAssertLessThanOrEqual(requested, min(65_536, Self.wavLimit + 1 - total))
          guard requested <= Self.wavLimit + 1 - total else { throw WAVFixtureError.invalidReadRequest }
          let count = try self.readWAVFixture(descriptor, into: buffer, requested: requested)
          XCTAssertLessThanOrEqual(count, requested)
          total += count
          return count
        })
    ) { error in
      self.assertWAVTooLarge(error, path: url.path, size: Self.wavLimit + 3)
    }

    // THEN
    try assertWAVDescriptorClosed(descriptors.first)
    XCTAssertEqual(Set(descriptors).count, 1)
    XCTAssertEqual(requests.last, 1)
    XCTAssertEqual(total, Self.wavLimit + 1)
  }

  func testWAVRetriesEINTRAndContinuesShortReadsUntilRealEOF() throws {
    // GIVEN
    let directory = try makeWAVDirectory()
    defer { removeWAVDirectory(directory) }
    let url = directory.appendingPathComponent("short-reads.wav")
    try writeWAVFixture(Self.oneSampleWAV, to: url)
    var descriptors: [Int32] = []
    var requests: [Int] = []
    var counts: [Int] = []

    // WHEN
    let audio = try XCTUnwrap(
      Commands.wav(
        of: url,
        read: { descriptor, buffer, requested in
          descriptors.append(descriptor)
          requests.append(requested)
          if counts.isEmpty {
            counts.append(-1)
            errno = EINTR
            return -1
          }
          if counts.count == 1 {
            XCTAssertEqual(lseek(descriptor, 0, SEEK_CUR), 0)
          }
          let count = try self.readWAVFixture(descriptor, into: buffer, requested: min(3, requested))
          counts.append(count)
          return count
        }))

    // THEN
    try assertWAVDescriptorClosed(descriptors.first)
    XCTAssertEqual(Set(descriptors).count, 1)
    XCTAssertTrue(requests.allSatisfy { $0 > 0 && $0 <= 65_536 })
    XCTAssertEqual(counts.first, -1)
    XCTAssertEqual(counts.last, 0)
    XCTAssertTrue(counts.dropFirst().dropLast().allSatisfy { (1...3).contains($0) })
    XCTAssertEqual(counts.dropFirst().reduce(0, +), Self.oneSampleWAV.count)
    XCTAssertEqual(audio.data, Self.oneSampleWAV)
    XCTAssertEqual(audio.duration, .seconds(1.0 / 8_000))
  }

  func testWAVUsesTheOpenedFileDespitePathReplacement() throws {
    // GIVEN
    let directory = try makeWAVDirectory()
    defer { removeWAVDirectory(directory) }
    let url = directory.appendingPathComponent("pinned.wav")
    let replacement = directory.appendingPathComponent("replacement.wav")
    let malformed = Data([0x00, 0x01, 0x02])
    try writeWAVFixture(Self.oneSampleWAV, to: url)
    try writeWAVFixture(malformed, to: replacement)
    let original = try wavMetadata(at: url)
    var descriptors: [Int32] = []

    // WHEN
    let audio = try XCTUnwrap(
      Commands.wav(
        of: url,
        read: { descriptor, buffer, requested in
          if descriptors.isEmpty {
            guard Darwin.rename(replacement.path, url.path) == 0 else { throw self.wavPOSIXError() }
            var opened = stat()
            guard fstat(descriptor, &opened) == 0 else { throw self.wavPOSIXError() }
            XCTAssertEqual(opened.st_dev, original.st_dev)
            XCTAssertEqual(opened.st_ino, original.st_ino)
          }
          descriptors.append(descriptor)
          return try self.readWAVFixture(descriptor, into: buffer, requested: requested)
        }))

    // THEN
    try assertWAVDescriptorClosed(descriptors.first)
    XCTAssertEqual(Set(descriptors).count, 1)
    XCTAssertNotEqual(try wavMetadata(at: url).st_ino, original.st_ino)
    XCTAssertEqual(try Data(contentsOf: url), malformed)
    XCTAssertEqual(audio.data, Self.oneSampleWAV)
    XCTAssertEqual(audio.duration, .seconds(1.0 / 8_000))
  }

  func testWAVFollowsRegularSymlinksAndRetainsOwnedBytesAfterSourceRewrite() throws {
    // GIVEN
    let directory = try makeWAVDirectory()
    defer { removeWAVDirectory(directory) }
    let target = directory.appendingPathComponent("source.wav")
    let link = directory.appendingPathComponent("link.wav")
    try writeWAVFixture(Self.oneSampleWAV, to: target)
    guard Darwin.symlink(target.path, link.path) == 0 else { throw wavPOSIXError() }
    let before = try wavMetadata(at: target)

    // WHEN
    let audio = try XCTUnwrap(Commands.wav(of: link))
    XCTAssertEqual(audio.data, Self.oneSampleWAV)
    XCTAssertEqual(audio.duration, .seconds(1.0 / 8_000))
    try writeWAVFixture(Self.zeroFrameWAV, to: target)
    let after = try wavMetadata(at: target)
    let reread = try XCTUnwrap(Commands.wav(of: target))

    // THEN
    XCTAssertEqual(after.st_dev, before.st_dev)
    XCTAssertEqual(after.st_ino, before.st_ino)
    XCTAssertEqual(try Data(contentsOf: target), Self.zeroFrameWAV)
    XCTAssertEqual(reread.data, Self.zeroFrameWAV)
    XCTAssertEqual(reread.duration, .zero)
    XCTAssertEqual(audio.data, Self.oneSampleWAV)
    XCTAssertEqual(audio.duration, .seconds(1.0 / 8_000))
  }

  func testWAVReadErrorIsUnreadableAndClosesTheDescriptor() throws {
    // GIVEN
    let directory = try makeWAVDirectory()
    defer { removeWAVDirectory(directory) }
    let url = directory.appendingPathComponent("read-error.wav")
    try writeWAVFixture(Self.oneSampleWAV, to: url)
    var descriptors: [Int32] = []

    // WHEN
    XCTAssertThrowsError(
      try Commands.wav(
        of: url,
        read: { descriptor, _, requested in
          descriptors.append(descriptor)
          XCTAssertGreaterThan(requested, 0)
          XCTAssertLessThanOrEqual(requested, 65_536)
          errno = EIO
          return -1
        })
    ) { error in
      self.assertWAVUnreadable(error, path: url.path)
    }

    // THEN
    try assertWAVDescriptorClosed(descriptors.first)
    XCTAssertEqual(descriptors.count, 1)
  }

  func testWAVRejectsDirectoryAndMissingInputBeforeReading() throws {
    // GIVEN
    let directory = try makeWAVDirectory()
    defer { removeWAVDirectory(directory) }
    let missing = directory.appendingPathComponent("missing.wav")
    var reads = 0

    // WHEN / THEN
    XCTAssertThrowsError(
      try Commands.wav(
        of: directory,
        read: { descriptor, buffer, requested in
          reads += 1
          return try self.readWAVFixture(descriptor, into: buffer, requested: requested)
        })
    ) { error in
      self.assertWAVUnreadable(error, path: directory.path, requiresRegularFileReason: true)
    }
    XCTAssertEqual(reads, 0)
    XCTAssertThrowsError(
      try Commands.wav(
        of: missing,
        read: { descriptor, buffer, requested in
          reads += 1
          return try self.readWAVFixture(descriptor, into: buffer, requested: requested)
        })
    ) { error in
      self.assertWAVUnreadable(error, path: missing.path)
    }
    XCTAssertEqual(reads, 0)
  }

  func testWAVDistinguishesEmptyInputFromZeroFrameAudio() throws {
    // GIVEN
    let directory = try makeWAVDirectory()
    defer { removeWAVDirectory(directory) }
    let url = directory.appendingPathComponent("empty.wav")
    try writeWAVFixture(Data(), to: url)

    // WHEN / THEN
    XCTAssertNil(try Commands.wav(of: url))
    try writeWAVFixture(Self.zeroFrameWAV, to: url)
    let audio = try XCTUnwrap(Commands.wav(of: url))
    XCTAssertEqual(audio.data, Self.zeroFrameWAV)
    XCTAssertEqual(audio.duration, .zero)
  }

  // MARK: - Real file fixtures

  private static let wavLimit = 32 * 1024 * 1024

  // RIFF size 38, PCM mono, 8 kHz, 16-bit, one sample (0x1234).
  private static let oneSampleWAV = Data([
    0x52, 0x49, 0x46, 0x46, 0x26, 0x00, 0x00, 0x00, 0x57, 0x41, 0x56, 0x45,
    0x66, 0x6D, 0x74, 0x20, 0x10, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00,
    0x40, 0x1F, 0x00, 0x00, 0x80, 0x3E, 0x00, 0x00, 0x02, 0x00, 0x10, 0x00,
    0x64, 0x61, 0x74, 0x61, 0x02, 0x00, 0x00, 0x00, 0x34, 0x12,
  ])

  // RIFF size 36 with a valid fmt chunk and a zero-length data chunk.
  private static let zeroFrameWAV = Data([
    0x52, 0x49, 0x46, 0x46, 0x24, 0x00, 0x00, 0x00, 0x57, 0x41, 0x56, 0x45,
    0x66, 0x6D, 0x74, 0x20, 0x10, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00,
    0x40, 0x1F, 0x00, 0x00, 0x80, 0x3E, 0x00, 0x00, 0x02, 0x00, 0x10, 0x00,
    0x64, 0x61, 0x74, 0x61, 0x00, 0x00, 0x00, 0x00,
  ])

  private enum WAVFixtureError: Error {
    case invalidReadRequest
    case writeMadeNoProgress
  }

  private func wavPOSIXError() -> POSIXError {
    POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
  }

  private func makeWAVDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("bounded-wav-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    return url
  }

  private func removeWAVDirectory(_ url: URL) {
    do {
      try FileManager.default.removeItem(at: url)
    } catch {
      XCTFail("Could not remove WAV fixture directory: \(error)")
    }
  }

  private func writeWAVFixture(_ data: Data, to url: URL, size: Int? = nil) throws {
    let descriptor = open(url.path, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0o600)
    guard descriptor >= 0 else { throw wavPOSIXError() }
    defer { XCTAssertEqual(Darwin.close(descriptor), 0) }
    try data.withUnsafeBytes { buffer in
      var offset = 0
      while offset < buffer.count {
        let count = Darwin.write(descriptor, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
        if count < 0 {
          if errno == EINTR { continue }
          throw wavPOSIXError()
        }
        guard count > 0 else { throw WAVFixtureError.writeMadeNoProgress }
        offset += count
      }
    }
    if let size {
      guard ftruncate(descriptor, off_t(size)) == 0 else { throw wavPOSIXError() }
    }
  }

  private func resizeWAVFixture(_ url: URL, to size: Int) throws {
    let descriptor = open(url.path, O_WRONLY | O_CLOEXEC)
    guard descriptor >= 0 else { throw wavPOSIXError() }
    defer { XCTAssertEqual(Darwin.close(descriptor), 0) }
    guard ftruncate(descriptor, off_t(size)) == 0 else { throw wavPOSIXError() }
  }

  private func wavMetadata(at url: URL) throws -> stat {
    var metadata = stat()
    guard fstatat(AT_FDCWD, url.path, &metadata, 0) == 0 else { throw wavPOSIXError() }
    return metadata
  }

  private func readWAVFixture(_ descriptor: Int32, into buffer: UnsafeMutableRawPointer, requested: Int) throws -> Int {
    // Reject invalid requests before a mutant can overrun the production buffer in the test.
    guard requested > 0, requested <= 65_536 else { throw WAVFixtureError.invalidReadRequest }
    let count = Darwin.read(descriptor, buffer, requested)
    guard count >= 0 else { throw wavPOSIXError() }
    return count
  }

  private func assertWAVDescriptorClosed(_ descriptor: Int32?, file: StaticString = #filePath, line: UInt = #line) throws {
    let descriptor = try XCTUnwrap(descriptor, file: file, line: line)
    errno = 0
    let result = fcntl(descriptor, F_GETFD)
    let error = errno
    XCTAssertEqual(result, -1, file: file, line: line)
    XCTAssertEqual(error, EBADF, file: file, line: line)
  }

  private func assertWAVTooLarge(
    _ error: Error, path: String, size: Int, file: StaticString = #filePath, line: UInt = #line
  ) {
    guard let audioError = error as? AudioInjectionError,
      case let .fileTooLarge(actualPath, actualSize, maximum) = audioError
    else {
      XCTFail("Expected fileTooLarge, got \(error)", file: file, line: line)
      return
    }
    XCTAssertEqual(actualPath, path, file: file, line: line)
    XCTAssertEqual(actualSize, size, file: file, line: line)
    XCTAssertEqual(maximum, Self.wavLimit, file: file, line: line)
  }

  private func assertWAVUnreadable(
    _ error: Error, path: String, requiresRegularFileReason: Bool = false,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    guard let audioError = error as? AudioInjectionError,
      case let .fileUnreadable(actualPath, reason) = audioError
    else {
      XCTFail("Expected fileUnreadable, got \(error)", file: file, line: line)
      return
    }
    XCTAssertEqual(actualPath, path, file: file, line: line)
    XCTAssertFalse(reason.isEmpty, file: file, line: line)
    if requiresRegularFileReason {
      XCTAssertTrue(reason.contains("regular file"), file: file, line: line)
    }
  }
}
