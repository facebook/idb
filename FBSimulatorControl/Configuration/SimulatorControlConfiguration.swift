/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

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

public struct FBSimulatorControlConfiguration: Equatable, Hashable, CustomStringConvertible {

  public let deviceSetPath: String?
  public let logger: FBControlCoreLogger

  /// - Parameter logger: nil means `FBControlCoreGlobalConfiguration.defaultLogger`, which is
  ///   os_log-only unless the `FBCONTROLCORE_LOGGING`/`FBCONTROLCORE_DEBUG_LOGGING` environment
  ///   variables are set — see its documentation.
  public static func configuration(
    withDeviceSetPath deviceSetPath: String?,
    logger: (any FBControlCoreLogger)?
  ) -> FBSimulatorControlConfiguration {
    FBSimulatorControlConfiguration(
      deviceSetPath: deviceSetPath,
      logger: logger
    )
  }

  /// - Parameter logger: nil means `FBControlCoreGlobalConfiguration.defaultLogger` (os_log-only
  ///   by default — see its documentation).
  public init(deviceSetPath: String?, logger: (any FBControlCoreLogger)?) {
    self.deviceSetPath = deviceSetPath
    self.logger = logger ?? FBControlCoreGlobalConfiguration.defaultLogger
  }

  // MARK: - Equatable, Hashable

  /// Identity is the device set path alone; the logger is a dependency, not data.
  public static func == (lhs: FBSimulatorControlConfiguration, rhs: FBSimulatorControlConfiguration) -> Bool {
    lhs.deviceSetPath == rhs.deviceSetPath
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(deviceSetPath)
  }

  public var description: String {
    "Pool Config | Set Path \(deviceSetPath ?? "(null)")"
  }

  /// The default CoreSimulator device-set path. Loads the private frameworks on demand and throws
  /// when they cannot be loaded or the path cannot be resolved.
  public static func defaultDeviceSetPath() throws -> String {
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
