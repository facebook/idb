/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

/// The ways device-set resolution can fail, as data rather than assembled strings.
public enum FBSimulatorDeviceSetError: Error, LocalizedError {
  case simDeviceSetUnavailable
  case defaultPathUnavailable

  public var errorDescription: String? {
    switch self {
    case .simDeviceSetUnavailable:
      return "SimDeviceSet is not present after loading CoreSimulator"
    case .defaultPathUnavailable:
      return "SimDeviceSet did not provide a default device set path"
    }
  }
}

@objc(FBSimulatorControlConfiguration)
public class FBSimulatorControlConfiguration: NSObject, NSCopying {

  // MARK: - Properties

  @objc public let deviceSetPath: String?
  @objc public let logger: FBControlCoreLogger
  @objc public let reporter: FBEventReporter?

  // MARK: - Initializers

  /// - Parameter logger: nil means `FBControlCoreGlobalConfiguration.defaultLogger`, which is
  ///   os_log-only unless the `FBCONTROLCORE_LOGGING`/`FBCONTROLCORE_DEBUG_LOGGING` environment
  ///   variables are set — see its documentation.
  @objc(configurationWithDeviceSetPath:logger:reporter:)
  public class func configuration(
    withDeviceSetPath deviceSetPath: String?,
    logger: (any FBControlCoreLogger)?,
    reporter: (any FBEventReporter)?
  ) -> FBSimulatorControlConfiguration {
    FBSimulatorControlConfiguration(
      deviceSetPath: deviceSetPath,
      logger: logger,
      reporter: reporter
    )
  }

  /// - Parameter logger: nil means `FBControlCoreGlobalConfiguration.defaultLogger` (os_log-only
  ///   by default — see its documentation).
  @objc
  public init(deviceSetPath: String?, logger: (any FBControlCoreLogger)?, reporter: (any FBEventReporter)?) {
    self.deviceSetPath = deviceSetPath
    self.logger = logger ?? FBControlCoreGlobalConfiguration.defaultLogger
    self.reporter = reporter
    super.init()
  }

  // MARK: - NSCopying

  public func copy(with zone: NSZone? = nil) -> Any {
    self
  }

  // MARK: - NSObject

  public override var hash: Int {
    deviceSetPath?.hash ?? 0
  }

  public override func isEqual(_ object: Any?) -> Bool {
    guard let other = object as? FBSimulatorControlConfiguration else {
      return false
    }
    return deviceSetPath == other.deviceSetPath
  }

  public override var description: String {
    "Pool Config | Set Path \(deviceSetPath ?? "(null)")"
  }

  // MARK: - Helpers

  /// The default CoreSimulator device-set path. Loads the private frameworks on demand and throws
  /// when they cannot be loaded or the path cannot be resolved.
  @objc(defaultDeviceSetPathAndReturnError:)
  public class func defaultDeviceSetPath() throws -> String {
    try FBSimulatorControlFrameworkLoader.essentialFrameworks.loadPrivateFrameworks(nil)
    guard let deviceSetClass = objc_lookUpClass("SimDeviceSet") else {
      throw FBSimulatorDeviceSetError.simDeviceSetUnavailable
    }
    let cls = deviceSetClass as AnyObject
    if let result = cls.perform(NSSelectorFromString("defaultSetPath"))?.takeUnretainedValue() as? String {
      return result
    }
    guard
      let defaultSet = cls.perform(NSSelectorFromString("defaultSet"))?.takeUnretainedValue(),
      let setPath = (defaultSet as AnyObject).perform(NSSelectorFromString("setPath"))?.takeUnretainedValue() as? String
    else {
      throw FBSimulatorDeviceSetError.defaultPathUnavailable
    }
    return setPath
  }
}
