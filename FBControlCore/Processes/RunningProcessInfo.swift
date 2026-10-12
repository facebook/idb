/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// A process in the host's process table, as read by `ProcessFetcher`.
public struct RunningProcessInfo: Sendable, CustomStringConvertible {

  public let processIdentifier: pid_t
  public let launchPath: String
  public let arguments: [String]
  public let environment: [String: String]

  public var processName: String {
    (launchPath as NSString).lastPathComponent
  }

  public init(processIdentifier: pid_t, launchPath: String, arguments: [String], environment: [String: String]) {
    self.processIdentifier = processIdentifier
    self.launchPath = launchPath
    self.arguments = arguments
    self.environment = environment
  }

  public var description: String {
    "Process \(processName) | PID \(processIdentifier)"
  }
}
