/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// The native host engine behind `Subprocess.run`: `posix_spawn` with every
/// descriptor not explicitly mapped closed in the child and all signals reset
/// to their defaults, exit observed through a process dispatch source that
/// reaps with `waitpid`.
enum HostSubprocess {

  /// How long to keep draining an output pipe after the process has exited
  /// before giving up on end-of-file.
  static let drainTimeout: TimeInterval = 4

  static func spawn(
    executable: String,
    arguments: [String],
    environment: [String: String],
    standardOutput: Int32?,
    standardError: Int32?
  ) throws -> pid_t {
    var fileActions: posix_spawn_file_actions_t?
    try checked(posix_spawn_file_actions_init(&fileActions), executable)
    defer { posix_spawn_file_actions_destroy(&fileActions) }
    if let standardOutput {
      try checked(posix_spawn_file_actions_adddup2(&fileActions, standardOutput, STDOUT_FILENO), executable)
    }
    if let standardError {
      try checked(posix_spawn_file_actions_adddup2(&fileActions, standardError, STDERR_FILENO), executable)
    }

    var attributes: posix_spawnattr_t?
    try checked(posix_spawnattr_init(&attributes), executable)
    defer { posix_spawnattr_destroy(&attributes) }
    var signals = sigset_t()
    sigemptyset(&signals)
    try checked(posix_spawnattr_setsigmask(&attributes, &signals), executable)
    sigfillset(&signals)
    try checked(posix_spawnattr_setsigdefault(&attributes, &signals), executable)
    try checked(posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK)), executable)

    var processIdentifier: pid_t = 0
    let status = withCStringArray([executable] + arguments) { argv in
      withCStringArray(environment.map { "\($0.key)=\($0.value)" }) { envp in
        posix_spawn(&processIdentifier, executable, &fileActions, &attributes, argv, envp)
      }
    }
    guard status == 0 else {
      throw SubprocessError.launchFailed(executable: executable, message: String(cString: strerror(status)))
    }
    return processIdentifier
  }

  /// The spawn helpers return an error number rather than setting `errno`. An
  /// unchecked failure would leave the child with a partially applied set of
  /// file actions or attributes — the wrong descriptors on its streams, or an
  /// inherited signal disposition — instead of a launch that failed.
  private static func checked(_ result: Int32, _ executable: String) throws {
    guard result == 0 else {
      throw SubprocessError.launchFailed(executable: executable, message: String(cString: strerror(result)))
    }
  }

  /// Waits for `processIdentifier` to exit and returns the raw `wait(2)`
  /// status word.
  ///
  /// The event handler deliberately holds the only strong reference to its
  /// dispatch source and cancels it after the event fires. Weakening that
  /// capture deallocates the source before the exit arrives, `waitpid` never
  /// runs, and the wait never resolves — do not "fix" the cycle.
  ///
  /// Cancellation abandons observation without killing the process, and the
  /// source stays registered so the child is still reaped when it exits.
  static func waitForExit(of processIdentifier: pid_t, logger: (any ControlCoreLogger)?) async throws -> Int32 {
    let resumer = SingleResumer<Int32>()
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        resumer.register(continuation)
        let queue = DispatchQueue(label: "com.facebook.fbcontrolcore.subprocess.wait")
        let source = DispatchSource.makeProcessSource(identifier: processIdentifier, eventMask: .exit, queue: queue)
        source.setEventHandler {
          var statLoc: Int32 = 0
          // The event means the child is already a zombie, so the reap
          // returns it. Anything else leaves the status word at zero, which
          // decodes as a clean exit — a failed reap must not be mistaken for
          // one, so it falls back to a blocking wait before giving up.
          var reaped = waitpid(processIdentifier, &statLoc, WNOHANG)
          if reaped == 0 {
            reaped = waitpid(processIdentifier, &statLoc, 0)
          }
          if reaped != processIdentifier {
            logger?.log("Failed to get the exit status with waitpid: \(String(cString: strerror(errno)))")
          }
          resumer.resume(with: .success(statLoc))
          source.cancel()
        }
        source.resume()
      }
    } onCancel: {
      resumer.resume(with: .failure(CancellationError()))
    }
  }
}

/// Resolves a continuation exactly once, from whichever of the exit event and
/// task cancellation arrives first — in either order relative to the
/// continuation being registered.
///
// SAFETY: `continuation`, `pending` and `resumed` are only ever read or
// written inside `lock`, and the continuation is resumed after the lock is
// released, so no caller code runs under it.
// patternlint-disable-next-line unchecked-sendable
private final class SingleResumer<Value: Sendable>: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<Value, any Error>?
  private var pending: Result<Value, any Error>?
  private var resumed = false

  func register(_ continuation: CheckedContinuation<Value, any Error>) {
    let immediate: Result<Value, any Error>? = lock.withLock {
      if let pending, !resumed {
        resumed = true
        return pending
      }
      self.continuation = continuation
      return nil
    }
    if let immediate {
      continuation.resume(with: immediate)
    }
  }

  func resume(with result: Result<Value, any Error>) {
    let continuation: CheckedContinuation<Value, any Error>? = lock.withLock {
      guard !resumed else {
        return nil
      }
      guard let registered = self.continuation else {
        pending = result
        return nil
      }
      resumed = true
      self.continuation = nil
      return registered
    }
    continuation?.resume(with: result)
  }
}

private func withCStringArray<Result>(
  _ strings: [String],
  _ body: (UnsafePointer<UnsafeMutablePointer<CChar>?>) -> Result
) -> Result {
  var pointers: [UnsafeMutablePointer<CChar>?] = strings.map { strdup($0) }
  pointers.append(nil)
  defer {
    for pointer in pointers {
      free(pointer)
    }
  }
  return body(&pointers)
}

/// One resolved output stream of a host launch: the descriptor the child
/// receives, and the reader draining the parent's end where one exists.
struct HostSink {
  /// Duplicated onto the child's stream by the spawn; nil leaves the child's
  /// descriptor closed. The parent's copy must be closed once the child owns
  /// it, so that end-of-file on the drain is driven solely by the child
  /// exiting.
  private(set) var childDescriptor: Int32?
  let reader: FileReader?

  mutating func closeChildDescriptor() {
    if let childDescriptor {
      close(childDescriptor)
    }
    childDescriptor = nil
  }

  mutating func dispose() {
    closeChildDescriptor()
    if let reader {
      _ = reader.stopReading()
    }
  }
}

extension Subprocess.Output {

  /// Resolves the capture into the descriptor and drain for a host launch,
  /// paired with a reader for the captured value once the drain completes.
  ///
  /// The consumer compositions mirror `FBProcessOutput`'s exactly, so a sink
  /// observes the same delivery it always has.
  func resolveHost() throws -> (sink: HostSink, capture: () -> Captured) {
    switch kind {
    case .closed:
      return (HostSink(childDescriptor: nil, reader: nil), { Self.captured(()) })
    case .nullDevice:
      return (HostSink(childDescriptor: try Self.openSink(at: "/dev/null"), reader: nil), { Self.captured(()) })
    case .file(let url):
      return (HostSink(childDescriptor: try Self.openSink(at: url.path), reader: nil), { Self.captured(url) })
    case .consumer(let consumer):
      return (try Self.drainedSink(into: consumer, logger: nil), { Self.captured(()) })
    case .logger(let logger):
      return (try Self.drainedSink(into: FBLoggingDataConsumer(logger: logger), logger: logger), { Self.captured(()) })
    case .loggerCapturingErrorMessage(let logger):
      let buffer = FBDataBuffer.accumulatingBuffer(withCapacity: FBProcessOutputErrorMessageLength)
      return (try Self.drainedSink(into: buffer, logger: logger), { Self.captured(()) })
    case .lines(let sink):
      let consumer = FBBlockDataConsumer.asynchronousLineConsumer(sink)
      return (try Self.drainedSink(into: consumer, logger: nil), { Self.captured(()) })
    case .data:
      let backing = NSMutableData()
      let sink = try Self.drainedSink(into: FBDataBuffer.accumulatingBuffer(for: backing), logger: nil)
      return (sink, { Self.captured(backing as Data) })
    case .string:
      let backing = NSMutableData()
      let sink = try Self.drainedSink(into: FBDataBuffer.accumulatingBuffer(for: backing), logger: nil)
      return (sink, { Self.captured(Self.string(from: backing as Data)) })
    }
  }

  /// The engine's string capture has always stripped exactly one trailing
  /// newline byte, and decoded invalid UTF-8 to the empty string.
  private static func string(from data: Data) -> String {
    var data = data
    if data.last == UInt8(ascii: "\n") {
      data.removeLast()
    }
    return String(data: data, encoding: .utf8) ?? ""
  }

  /// Opens without `O_TRUNC`, as the engine always has; the explicit mode is
  /// new — the engine omits one, leaving created files with undefined
  /// permissions.
  private static func openSink(at path: String) throws -> Int32 {
    let descriptor = open(path, O_WRONLY | O_CREAT, 0o644)
    guard descriptor >= 0 else {
      throw SubprocessError.outputUnavailable(path: path, message: String(cString: strerror(errno)))
    }
    return descriptor
  }

  private static func drainedSink(into consumer: any DataConsumer, logger: (any ControlCoreLogger)?) throws -> HostSink {
    var descriptors: [Int32] = [0, 0]
    guard pipe(&descriptors) == 0 else {
      throw SubprocessError.outputUnavailable(path: "pipe", message: String(cString: strerror(errno)))
    }
    let composed: any DataConsumer
    if let logger {
      composed = FBCompositeDataConsumer(consumers: [consumer, FBLoggingDataConsumer(logger: logger)])
    } else {
      composed = consumer
    }
    let reader = FileReader.reader(withFileDescriptor: descriptors[0], closeOnEndOfFile: true, consumer: composed, logger: logger)
    return HostSink(childDescriptor: descriptors[1], reader: reader)
  }
}
