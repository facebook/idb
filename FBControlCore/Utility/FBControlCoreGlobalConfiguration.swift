/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

private let ConfirmShimsAreSignedEnv = "FBCONTROLCORE_CONFIRM_SIGNED_SHIMS"

@objc(FBControlCoreGlobalConfiguration)
public class FBControlCoreGlobalConfiguration: NSObject {

  nonisolated(unsafe) private static var _logger: (any FBControlCoreLogger)?

  // MARK: Timeouts

  @objc public class var fastTimeout: TimeInterval { return 10 }
  @objc public class var regularTimeout: TimeInterval { return 30 }
  @objc public class var slowTimeout: TimeInterval { return 120 }

  // MARK: Logger

  @objc public class var defaultLogger: any FBControlCoreLogger {
    get {
      if let existing = _logger { return existing }
      let created = createDefaultLogger()
      _logger = created
      return created
    }
    set {
      if _logger != nil {
        newValue.debug().log("Overriding the Default Logger with \(newValue)")
      }
      _logger = newValue
    }
  }

  // MARK: Configuration

  @objc public class var confirmCodesignaturesAreValid: Bool {
    guard let value = ProcessInfo.processInfo.environment[ConfirmShimsAreSignedEnv] else { return false }
    return (value as NSString).boolValue
  }

  @objc public class var safeSubprocessEnvironment: [String: String] {
    var modified: [String: String] = [:]
    for (key, value) in ProcessInfo.processInfo.environment {
      if key.contains("TERMCAP") { continue }
      modified[key] = value
    }
    return modified
  }

  // MARK: NSObject

  override public class func description() -> String {
    return "Default Logger \(_logger.map(String.init(describing:)) ?? "(nil)")"
  }

  public override var description: String {
    return Self.description()
  }

  // MARK: Private

  private class func createDefaultLogger() -> any FBControlCoreLogger {
    return FBControlCoreLoggerFactory.systemLoggerWriting(toStderr: stderrLoggingEnabledByDefault, withDebugLogging: debugLoggingEnabledByDefault)
  }

  private class var stderrLoggingEnabledByDefault: Bool {
    guard let value = ProcessInfo.processInfo.environment[FBControlCoreStderrLogging] else { return false }
    return (value as NSString).boolValue
  }

  private class var debugLoggingEnabledByDefault: Bool {
    guard let value = ProcessInfo.processInfo.environment[FBControlCoreDebugLogging] else { return false }
    return (value as NSString).boolValue
  }

  private class func readValue(forKey key: String, fromPlistAtPath plistPath: String) -> Any? {
    assert(FileManager.default.fileExists(atPath: plistPath), "plist does not exist at path '\(plistPath)'")
    guard let infoPlist = NSDictionary(contentsOfFile: plistPath) else {
      assertionFailure("Could not read plist at '\(plistPath)'")
      return nil
    }
    let value = infoPlist[key]
    assert(value != nil, "'\(key)' does not exist in plist '\(infoPlist.allKeys)'")
    return value
  }
}
