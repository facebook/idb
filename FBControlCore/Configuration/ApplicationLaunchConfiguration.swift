/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

public enum ApplicationLaunchMode: UInt {
  case failIfRunning = 0
  case foregroundIfRunning = 1
  case relaunchIfRunning = 2
}

/// Where a launched application's standard output or standard error goes.
public enum ApplicationOutput: Equatable, Sendable {
  case nullDevice
  /// Forwarded to the consumer, which receives end-of-file once the application exits.
  case consumer(any DataConsumer)

  public static func == (lhs: ApplicationOutput, rhs: ApplicationOutput) -> Bool {
    switch (lhs, rhs) {
    case (.nullDevice, .nullDevice):
      return true
    case let (.consumer(lhs), .consumer(rhs)):
      return lhs === rhs
    default:
      return false
    }
  }
}

public struct ApplicationLaunchConfiguration: Equatable, CustomStringConvertible {

  public let bundleID: String
  public let bundleName: String?
  public let arguments: [String]
  public let environment: [String: String]
  public let waitForDebugger: Bool
  public let stdOut: ApplicationOutput
  public let stdErr: ApplicationOutput
  public let launchMode: ApplicationLaunchMode

  public init(bundleID: String, bundleName: String?, arguments: [String], environment: [String: String], waitForDebugger: Bool, stdOut: ApplicationOutput = .nullDevice, stdErr: ApplicationOutput = .nullDevice, launchMode: ApplicationLaunchMode) {
    self.bundleID = bundleID
    self.bundleName = bundleName
    self.arguments = arguments
    self.environment = environment
    self.waitForDebugger = waitForDebugger
    self.stdOut = stdOut
    self.stdErr = stdErr
    self.launchMode = launchMode
  }

  public var description: String {
    "App Launch \(bundleID) (\(bundleName ?? "(null)"))"
  }
}
