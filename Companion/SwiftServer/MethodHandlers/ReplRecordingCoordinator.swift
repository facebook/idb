/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

/// Coordinates the single in-progress REPL screen recording for a target.
///
/// Unlike other host commands, a recording outlives the `repl` stream that started
/// it: in the app context the app -- and the recording -- keeps running across
/// reconnects, so the recording state lives here, on the long-lived per-target
/// companion, rather than in the per-stream `ReplHostCommandState`. This is what
/// makes a later invocation able to stop a recording an earlier one started, and
/// what keeps the recording out of the per-session artifacts directory that is
/// deleted when a stream ends.
///
/// A recording is collected only by an explicit `stopRecording()`. If it is still
/// running when the app it belongs to exits, or when a disposable (test/simulator)
/// session tears down, it is dropped instead: stopped to release the framebuffer,
/// its file discarded.
///
/// `@unchecked Sendable`: `state` is guarded by `lock`. The async work (starting and
/// stopping the underlying recording) always runs after the state transition has
/// been made under the lock, so the lock is never held across an `await`.
final class ReplRecordingCoordinator: @unchecked Sendable {

  /// A stopped recording's files, ready to be reported to the driver as an artifact.
  struct StoppedRecording {
    let hostPath: String
    let containerPath: String
  }

  private final class ActiveRecording {
    let id = UUID()
    let recording: any FBVideoRecording
    let hostPath: String
    let containerPath: String

    init(recording: any FBVideoRecording, hostPath: String, containerPath: String) {
      self.recording = recording
      self.hostPath = hostPath
      self.containerPath = containerPath
    }
  }

  /// The recording lifecycle. `pending` reserves the single slot between the caller
  /// deciding to start and the underlying capture actually starting, so a concurrent
  /// start (e.g. a second connection) is rejected without racing the framebuffer.
  private enum State {
    case idle
    case pending
    case active(ActiveRecording)
  }

  /// The subdirectory of the target's auxillary directory recordings are written to.
  /// It doubles as the path relative to the AUXILLARY container root used to pull a
  /// recording back when the driver does not share our filesystem.
  private static let subdirectoryName = "idb-repl-recordings"

  private let recordingsDirectory: URL
  private let logger: FBControlCoreLogger?
  private let lock = NSLock()
  private var state: State = .idle
  private var counter = 0

  init(auxillaryDirectory: String, logger: FBControlCoreLogger?) {
    self.recordingsDirectory = URL(fileURLWithPath: auxillaryDirectory).appendingPathComponent(Self.subdirectoryName)
    self.logger = logger
  }

  /// Reserves the single recording slot and returns the file path to record to, or
  /// nil if a recording is already in progress. On success the caller must follow up
  /// with `activate` (once the capture has started) or `cancelReservation` (if it
  /// failed to start).
  func reserveRecordingPath() -> String? {
    let filename: String
    lock.lock()
    guard case .idle = state else {
      lock.unlock()
      return nil
    }
    state = .pending
    counter += 1
    filename = "video_\(counter).mp4"
    lock.unlock()

    try? FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)
    return recordingsDirectory.appendingPathComponent(filename).path
  }

  /// Records the started recording in the reserved slot and returns an identifier
  /// the app-exit watcher uses to drop only this recording.
  @discardableResult
  func activate(recording: any FBVideoRecording, hostPath: String) -> UUID {
    let filename = (hostPath as NSString).lastPathComponent
    lock.lock()
    defer { lock.unlock() }
    let active = ActiveRecording(
      recording: recording,
      hostPath: hostPath,
      containerPath: Self.subdirectoryName + "/" + filename)
    state = .active(active)
    return active.id
  }

  /// Releases a reservation whose underlying capture failed to start.
  func cancelReservation() {
    lock.lock()
    defer { lock.unlock() }
    if case .pending = state {
      state = .idle
    }
  }

  /// Stops the active recording, finalizes its file, and returns it for delivery, or
  /// nil if no recording is in progress.
  func stopRecording() async throws -> StoppedRecording? {
    guard let active = take(matching: nil) else {
      return nil
    }
    let url = try await active.recording.stop()
    return StoppedRecording(hostPath: url.path, containerPath: active.containerPath)
  }

  /// Drops the active recording if any -- stops it to release the framebuffer, then
  /// discards its file. Used when a disposable session tears down with a recording
  /// still running.
  func dropActiveRecording() async {
    await drop(take(matching: nil))
  }

  /// Drops the recording identified by `id` if it is still the active one. Used by
  /// the app-exit watcher; a no-op if the recording was already stopped or replaced.
  func dropRecording(id: UUID) async {
    await drop(take(matching: id))
  }

  // MARK: - Private

  /// Atomically clears and returns the active recording, when there is one and it
  /// matches `id` (any recording when `id` is nil). Leaves the slot idle so a new
  /// recording can start.
  private func take(matching id: UUID?) -> ActiveRecording? {
    lock.lock()
    defer { lock.unlock() }
    guard case let .active(active) = state else {
      return nil
    }
    if let id, active.id != id {
      return nil
    }
    state = .idle
    return active
  }

  private func drop(_ active: ActiveRecording?) async {
    guard let active else {
      return
    }
    _ = try? await active.recording.stop()
    try? FileManager.default.removeItem(atPath: active.hostPath)
    logger?.info().log("Dropped in-progress REPL recording at \(active.hostPath)")
  }
}
