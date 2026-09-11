/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

extension Subprocess {

  /// Where one of the child's output streams goes, and what the caller gets
  /// back for it when the process completes.
  ///
  /// An `Output` is an argument to a launch call, not stored configuration,
  /// so `Captured` flows into the result: launching with `.string` yields a
  /// `String` in the corresponding `Completed` field, launching with a sink
  /// that captures nothing yields `Void`. The two dev-null spellings are
  /// deliberately distinct: `.closed` hands the child no descriptor at all,
  /// `.nullDevice` hands it an open `/dev/null`.
  public struct Output<Captured: Sendable> {

    enum Kind {
      case closed
      case nullDevice
      case consumer(any FBDataConsumer)
      case logger(any FBControlCoreLogger)
      case loggerCapturingErrorMessage(any FBControlCoreLogger)
      case lines(@Sendable (String) -> Void)
      case data
      case string
      case file(URL)
    }

    let kind: Kind

    private init(_ kind: Kind) {
      self.kind = kind
    }
  }

  /// A finished process: its identity, how it ended, and whatever its
  /// output captures produced.
  public struct Completed<Out: Sendable, Err: Sendable>: Sendable {
    public let executable: String
    public let processIdentifier: pid_t
    public let terminationStatus: TerminationStatus
    public let standardOutput: Out
    public let standardError: Err

    public init(
      executable: String,
      processIdentifier: pid_t,
      terminationStatus: TerminationStatus,
      standardOutput: Out,
      standardError: Err
    ) {
      self.executable = executable
      self.processIdentifier = processIdentifier
      self.terminationStatus = terminationStatus
      self.standardOutput = standardOutput
      self.standardError = standardError
    }

    /// Throws `makeError(code)` for a non-zero exit, and the standard
    /// termination error for a signal, so a run-and-check caller reads as a
    /// single statement instead of a status switch.
    public func checkExitedCleanly(onExitCode makeError: (Int32) -> any Error) throws {
      switch terminationStatus {
      case .exited(0):
        return
      case .exited(let code):
        throw makeError(code)
      case .signalled(let signo):
        throw ProcessTerminationError.exitedWithSignal(
          processIdentifier: processIdentifier,
          processName: (executable as NSString).lastPathComponent,
          signal: signo)
      }
    }

    /// Throws `error` for any termination that is not a clean exit, for a
    /// caller whose failure is described by the command it ran rather than by
    /// how the command ended.
    public func checkExitedCleanly(orThrow error: @autoclosure () -> any Error) throws {
      guard terminationStatus == .exited(0) else {
        throw error()
      }
    }
  }
}

// SAFETY: storage is a single immutable `let`. The non-Sendable payloads
// (`any FBDataConsumer`, `any FBControlCoreLogger`) are read once, at launch,
// to construct the IO attachment; thereafter the engine confines all calls to
// them to its own serial queues.
// patternlint-disable-next-line unchecked-sendable
extension Subprocess.Output: @unchecked Sendable {}

extension Subprocess.Output where Captured == Void {

  /// No descriptor is handed to the child: writes to this stream fail with
  /// `EBADF`.
  public static var closed: Self {
    .init(.closed)
  }

  /// The child writes to an open `/dev/null`.
  public static var nullDevice: Self {
    .init(.nullDevice)
  }

  /// Output is forwarded to `consumer` as it arrives.
  public static func consumer(_ consumer: any FBDataConsumer) -> Self {
    .init(.consumer(consumer))
  }

  /// Output is logged, line by line, to `logger`.
  public static func logger(_ logger: any FBControlCoreLogger) -> Self {
    .init(.logger(logger))
  }

  /// Output is logged to `logger`, and its tail is retained for use in
  /// error messages.
  public static func loggerCapturingErrorMessage(_ logger: any FBControlCoreLogger) -> Self {
    .init(.loggerCapturingErrorMessage(logger))
  }

  /// Each line of output is passed to `sink` as it arrives.
  public static func lines(_ sink: @escaping @Sendable (String) -> Void) -> Self {
    .init(.lines(sink))
  }
}

extension Subprocess.Output where Captured == Data {

  /// Output accumulates in memory and is returned as `Data` on completion.
  public static var data: Self {
    .init(.data)
  }
}

extension Subprocess.Output where Captured == String {

  /// Output accumulates in memory and is returned as a `String` on
  /// completion.
  public static var string: Self {
    .init(.string)
  }
}

extension Subprocess.Output where Captured == URL {

  /// Output is written to the file at `url`, which is returned on
  /// completion.
  public static func file(_ url: URL) -> Self {
    .init(.file(url))
  }
}
