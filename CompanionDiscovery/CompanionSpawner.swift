/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Dispatch
import Foundation

/// Launches `idb_companion` processes.
public struct CompanionSpawner {
  private let companionPath: String
  private let deviceSetPath: String?
  /// Seconds to wait for the companion to print its startup line.
  private let readinessTimeout: TimeInterval

  /// - Parameter companionPath: path to the `idb_companion` binary to launch.
  ///   Defaults to `CompanionPaths.defaultCompanionExecutable`; callers can
  ///   override it with a specific binary.
  public init(companionPath: String = CompanionPaths.defaultCompanionExecutable, deviceSetPath: String? = nil, readinessTimeout: TimeInterval = 30) {
    self.companionPath = companionPath
    self.deviceSetPath = deviceSetPath
    self.readinessTimeout = readinessTimeout
  }

  /// Spawns a companion for `udid` bound to `path`, returning a record for it.
  ///
  /// - Note: Unlike the Python client, the spawned process is not yet detached
  ///   into its own process group (`reparent=True` / `preexec_fn=os.setpgrp`).
  ///   It survives a normal exit of this process, but would receive terminal
  ///   signals (e.g. Ctrl-C) delivered to this process's group. Proper
  ///   detachment is left for the lifecycle/hookup work.
  public func spawnDomainSocketServer(udid: String, only: String? = nil, path: String) async throws -> CompanionInfo {
    try CompanionPaths.ensureLogsDirectory()
    let logPath = CompanionPaths.logFilePath(forUDID: udid)
    let logHandle = try appendHandle(forPath: logPath)
    defer { try? logHandle.close() }

    var arguments = ["--udid", udid, "--grpc-domain-sock", path]
    arguments += onlyArguments(only)
    if let deviceSetPath {
      arguments += ["--device-set-path", deviceSetPath]
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: companionPath)
    process.arguments = arguments
    let stdoutPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = logHandle

    do {
      try process.run()
    } catch {
      throw CompanionDiscoveryError.spawnFailed(reason: "\(error). \(logTail(logPath))")
    }

    let line: String
    do {
      line = try await readFirstLine(from: stdoutPipe.fileHandleForReading, timeout: readinessTimeout)
    } catch {
      process.terminate()
      throw CompanionDiscoveryError.companionNotReady(reason: "couldn't read startup report. \(logTail(logPath))")
    }

    guard let report = parseJSONObject(line), let grpcPath = report["grpc_path"] as? String, !grpcPath.isEmpty else {
      process.terminate()
      throw CompanionDiscoveryError.companionNotReady(reason: "no grpc_path in startup report '\(line)'. \(logTail(logPath))")
    }
    guard grpcPath == path else {
      process.terminate()
      throw CompanionDiscoveryError.socketPathMismatch(expected: path, actual: grpcPath)
    }

    return CompanionInfo(udid: udid, isLocal: true, pid: process.processIdentifier, address: .domainSocket(path: path))
  }

  // MARK: - Helpers

  /// A `mac` target takes no filter; others map to `--only <value>`. nil means
  /// "search all target sets".
  private func onlyArguments(_ only: String?) -> [String] {
    guard let only, !only.isEmpty, only != "mac" else {
      return []
    }
    return ["--only", only]
  }

  private func appendHandle(forPath path: String) throws -> FileHandle {
    if !FileManager.default.fileExists(atPath: path) {
      FileManager.default.createFile(atPath: path, contents: nil)
    }
    let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
    try handle.seekToEnd()
    return handle
  }
}

/// Reads a single newline-terminated line from `handle`, returning its content
/// without the trailing newline. Throws if no line arrives within `timeout`, or
/// if EOF is reached before any bytes are read.
///
/// The read is event-driven (`FileHandle.readabilityHandler`) and bridged to
/// `async`, so it never parks a thread while waiting, and it is torn down on
/// completion, timeout, or cancellation rather than left running in the
/// background.
private func readFirstLine(from handle: FileHandle, timeout: TimeInterval) async throws -> String {
  let state = LineReadState()
  return try await withTaskCancellationHandler {
    try await withCheckedThrowingContinuation { continuation in
      state.begin(handle: handle, timeout: timeout, continuation: continuation)
    }
  } onCancel: {
    state.cancel()
  }
}

/// Drives reading a single line from a `FileHandle` and bridges it to a
/// continuation. Bytes are delivered by the handle's readability handler (so no
/// thread is parked on the read) and a timer enforces the timeout. A lock
/// serialises the handler, the timer, and cancellation so the continuation is
/// resumed exactly once and the read is always torn down afterwards.
private final class LineReadState: @unchecked Sendable {
  private let lock = NSLock()
  private var bytes = [UInt8]()
  private var continuation: CheckedContinuation<String, Error>?
  private var handle: FileHandle?
  private var timer: DispatchSourceTimer?
  private var cancelled = false

  /// Starts the read and the timeout timer. If cancellation already happened,
  /// resumes immediately instead.
  func begin(handle: FileHandle, timeout: TimeInterval, continuation: CheckedContinuation<String, Error>) {
    lock.lock()
    defer { lock.unlock() }
    if cancelled {
      continuation.resume(throwing: CancellationError())
      return
    }
    self.handle = handle
    self.continuation = continuation

    let timer = DispatchSource.makeTimerSource()
    timer.schedule(deadline: .now() + timeout)
    timer.setEventHandler { [weak self] in
      self?.finish(.failure(CompanionDiscoveryError.companionNotReady(reason: "timed out after \(Int(timeout))s")))
    }
    self.timer = timer

    handle.readabilityHandler = { [weak self] fileHandle in
      self?.consume(fileHandle.availableData)
    }
    timer.resume()
  }

  /// Stops the read and resumes with a cancellation error if still pending.
  func cancel() {
    finish(.failure(CancellationError()))
  }

  private func consume(_ chunk: Data) {
    lock.lock()
    defer { lock.unlock() }
    guard continuation != nil else { return }
    if chunk.isEmpty {
      // EOF: the process closed stdout before a full line.
      finishLocked(
        bytes.isEmpty
          ? .failure(CompanionDiscoveryError.companionNotReady(reason: "no output"))
          : .success(String(decoding: bytes, as: UTF8.self)))
      return
    }
    for byte in chunk {
      if byte == UInt8(ascii: "\n") {
        finishLocked(.success(String(decoding: bytes, as: UTF8.self)))
        return
      }
      bytes.append(byte)
    }
  }

  /// Finishes the read (also closing the cancel-before-`begin` race) and resumes
  /// with `result` if still pending.
  private func finish(_ result: Result<String, Error>) {
    lock.lock()
    defer { lock.unlock() }
    cancelled = true
    finishLocked(result)
  }

  /// Resumes the continuation at most once and tears down the timer and reader so
  /// nothing is left running. The caller must hold `lock`.
  private func finishLocked(_ result: Result<String, Error>) {
    timer?.cancel()
    timer = nil
    handle?.readabilityHandler = nil
    handle = nil
    guard let continuation else { return }
    self.continuation = nil
    continuation.resume(with: result)
  }
}

/// Parses a single JSON object line into a dictionary, or nil if it isn't valid
/// JSON. Mirrors `parse_json_line`.
private func parseJSONObject(_ line: String) -> [String: Any]? {
  guard let data = line.data(using: .utf8),
    let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
  else {
    return nil
  }
  return object
}

/// Returns up to the last `count` lines of the file at `path`, for error
/// context. Mirrors the use of `get_last_n_lines` in the Python spawn errors.
private func logTail(_ path: String, count: Int = 30) -> String {
  guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
    return ""
  }
  let tail = contents.split(separator: "\n", omittingEmptySubsequences: false).suffix(count).joined(separator: "\n")
  return tail.isEmpty ? "" : "stderr:\n\(tail)"
}
