/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation
// Uses XCTest to match the existing tests in this target; migrating the whole
// target to Swift Testing is a separate effort.
// ast-grep-ignore: swift-testing/swift/no-new-xctest
import XCTest

/// A recording double that records only whether it was stopped, returning a fixed
/// URL (the file it was told to record to).
private final class FakeRecording: FBVideoRecording, @unchecked Sendable {
  let url: URL
  private let lock = NSLock()
  private var stopCountValue = 0

  init(url: URL) {
    self.url = url
  }

  var stopCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return stopCountValue
  }

  func stop() async throws -> URL {
    lock.lock()
    stopCountValue += 1
    lock.unlock()
    return url
  }
}

final class ReplRecordingCoordinatorTests: XCTestCase {

  private var auxillaryDirectory: String = ""

  override func setUp() {
    super.setUp()
    auxillaryDirectory = (NSTemporaryDirectory() as NSString)
      .appendingPathComponent("idb_repl_recording_test_\(UUID().uuidString)")
    try? FileManager.default.createDirectory(atPath: auxillaryDirectory, withIntermediateDirectories: true)
  }

  override func tearDown() {
    try? FileManager.default.removeItem(atPath: auxillaryDirectory)
    super.tearDown()
  }

  private func makeCoordinator() -> ReplRecordingCoordinator {
    ReplRecordingCoordinator(auxillaryDirectory: auxillaryDirectory, logger: nil)
  }

  /// Places a recording into the coordinator's reserved slot, creating a file at the
  /// reserved path so drop/delete behavior can be observed. Returns the path, the id,
  /// and the double.
  @discardableResult
  private func startRecording(_ coordinator: ReplRecordingCoordinator) throws -> (path: String, id: UUID, recording: FakeRecording) {
    let path = try XCTUnwrap(coordinator.reserveRecordingPath())
    FileManager.default.createFile(atPath: path, contents: Data([0x00]))
    let recording = FakeRecording(url: URL(fileURLWithPath: path))
    let id = coordinator.activate(recording: recording, hostPath: path)
    return (path, id, recording)
  }

  func testReservedPathIsUnderRecordingsDirectory() throws {
    let coordinator = makeCoordinator()
    let path = try XCTUnwrap(coordinator.reserveRecordingPath())
    let expectedDirectory = (auxillaryDirectory as NSString).appendingPathComponent("idb-repl-recordings")
    XCTAssertEqual((path as NSString).deletingLastPathComponent, expectedDirectory)
    XCTAssertTrue(FileManager.default.fileExists(atPath: expectedDirectory))
  }

  func testSecondReservationIsRejectedWhilePending() throws {
    let coordinator = makeCoordinator()
    XCTAssertNotNil(coordinator.reserveRecordingPath())
    XCTAssertNil(coordinator.reserveRecordingPath(), "a pending reservation should block another")
  }

  func testCancelReservationFreesTheSlot() throws {
    let coordinator = makeCoordinator()
    XCTAssertNotNil(coordinator.reserveRecordingPath())
    coordinator.cancelReservation()
    XCTAssertNotNil(coordinator.reserveRecordingPath(), "cancelling should free the slot")
  }

  func testSecondReservationIsRejectedWhileActive() throws {
    let coordinator = makeCoordinator()
    _ = try startRecording(coordinator)
    XCTAssertNil(coordinator.reserveRecordingPath(), "an active recording should block another")
  }

  func testStopRecordingFinalizesAndReturnsPaths() async throws {
    let coordinator = makeCoordinator()
    let started = try startRecording(coordinator)

    let stopped = try await coordinator.stopRecording()
    let result = try XCTUnwrap(stopped)
    XCTAssertEqual(result.hostPath, started.path)
    XCTAssertEqual(result.containerPath, "idb-repl-recordings/" + (started.path as NSString).lastPathComponent)
    XCTAssertEqual(started.recording.stopCount, 1)
    // The slot is free again once stopped.
    XCTAssertNotNil(coordinator.reserveRecordingPath())
  }

  func testStopRecordingWhenIdleReturnsNil() async throws {
    let coordinator = makeCoordinator()
    let stopped = try await coordinator.stopRecording()
    XCTAssertNil(stopped)
  }

  func testDropActiveRecordingStopsAndDeletesFile() async throws {
    let coordinator = makeCoordinator()
    let started = try startRecording(coordinator)

    await coordinator.dropActiveRecording()
    XCTAssertEqual(started.recording.stopCount, 1)
    XCTAssertFalse(FileManager.default.fileExists(atPath: started.path), "a dropped recording's file is discarded")
    // A dropped recording is not reported: the slot is free and there is nothing to stop.
    XCTAssertNotNil(coordinator.reserveRecordingPath())
  }

  func testDropRecordingIgnoresNonMatchingID() async throws {
    let coordinator = makeCoordinator()
    let started = try startRecording(coordinator)

    await coordinator.dropRecording(id: UUID())
    XCTAssertEqual(started.recording.stopCount, 0, "a non-matching id must not drop the active recording")
    XCTAssertTrue(FileManager.default.fileExists(atPath: started.path))

    await coordinator.dropRecording(id: started.id)
    XCTAssertEqual(started.recording.stopCount, 1)
    XCTAssertFalse(FileManager.default.fileExists(atPath: started.path))
  }
}
