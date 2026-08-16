/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Environment variable; when truthy, the default logger mirrors its output to stderr.
public let FBControlCoreStderrLogging = "FBCONTROLCORE_LOGGING"
/// Environment variable; when truthy, the default logger emits debug-level output.
public let FBControlCoreDebugLogging = "FBCONTROLCORE_DEBUG_LOGGING"

private let ConfirmShimsAreSignedEnv = "FBCONTROLCORE_CONFIRM_SIGNED_SHIMS"

@objc(FBControlCoreGlobalConfiguration)
public class FBControlCoreGlobalConfiguration: NSObject {

  // Guarded by _loggerLock. nonisolated(unsafe) only silences static-variable isolation
  // checking; the lock is what provides the synchronization.
  nonisolated(unsafe) private static var _logger: (any FBControlCoreLogger)?
  private static let _loggerLock = NSLock()

  // MARK: Timeouts

  @objc public class var fastTimeout: TimeInterval { 10 }
  @objc public class var regularTimeout: TimeInterval { 30 }
  @objc public class var slowTimeout: TimeInterval { 120 }

  // MARK: Logger

  /// The logger used wherever a nullable logger parameter is passed as nil.
  ///
  /// By default this logger is close to silent from a consumer's point of view: it writes to
  /// os_log (subsystem `com.facebook.fbcontrolcore`) at info level and nowhere else. In a process
  /// without a terminal — a GUI app, a launchd job — nothing reaches stderr, so framework
  /// diagnostics (including framework-loading failures) are only visible via
  /// `log stream --predicate 'subsystem == "com.facebook.fbcontrolcore"'`.
  ///
  /// Two environment variables lift this: `FBCONTROLCORE_LOGGING` mirrors output to stderr, and
  /// `FBCONTROLCORE_DEBUG_LOGGING` raises the level to debug. Consumers that want diagnostics
  /// somewhere they will actually look should pass their own logger instead of relying on nil.
  @objc public class var defaultLogger: any FBControlCoreLogger {
    get {
      _loggerLock.lock()
      defer { _loggerLock.unlock() }
      if let existing = _logger { return existing }
      let created = createDefaultLogger()
      _logger = created
      return created
    }
    set {
      _loggerLock.lock()
      let previous = _logger
      _logger = newValue
      _loggerLock.unlock()
      // Outside the critical section: logging through an arbitrary logger implementation must
      // not run under the lock.
      if previous != nil {
        newValue.debug().log("Overriding the Default Logger with \(newValue)")
      }
    }
  }

  // MARK: Configuration

  @objc public class var confirmCodesignaturesAreValid: Bool {
    guard let value = ProcessInfo.processInfo.environment[ConfirmShimsAreSignedEnv] else { return false }
    return (value as NSString).boolValue
  }

  // MARK: NSObject

  override public class func description() -> String {
    _loggerLock.lock()
    let logger = _logger
    _loggerLock.unlock()
    // Stringified outside the critical section: an arbitrary logger implementation must not run
    // under the lock.
    return "Default Logger \(logger.map(String.init(describing:)) ?? "(nil)")"
  }

  public override var description: String {
    Self.description()
  }

  // MARK: Private

  private class func createDefaultLogger() -> any FBControlCoreLogger {
    FBControlCoreLoggerFactory.systemLoggerWriting(toStderr: stderrLoggingEnabledByDefault, withDebugLogging: debugLoggingEnabledByDefault)
  }

  private class var stderrLoggingEnabledByDefault: Bool {
    guard let value = ProcessInfo.processInfo.environment[FBControlCoreStderrLogging] else { return false }
    return (value as NSString).boolValue
  }

  private class var debugLoggingEnabledByDefault: Bool {
    guard let value = ProcessInfo.processInfo.environment[FBControlCoreDebugLogging] else { return false }
    return (value as NSString).boolValue
  }
}
