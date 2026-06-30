/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

public protocol LaunchCtlCommands: AnyObject {

  func serviceName(forProcessIdentifier pid: pid_t) async throws -> String

  func serviceName(forProcess process: FBProcessInfo) async throws -> String

  func serviceNamesAndProcessIdentifiers(matching regex: NSRegularExpression) async throws -> [String: NSNumber]

  func firstServiceNameAndProcessIdentifier(matching regex: NSRegularExpression) async throws -> (serviceName: String, processIdentifier: pid_t)

  func processIsRunning(onSimulator process: FBProcessInfo) async throws -> Bool

  func listServices() async throws -> [String: Any]

  func stopService(withName serviceName: String) async throws -> String

  func startService(withName serviceName: String) async throws -> String

  func serviceIsRunning(named serviceName: String) async throws -> Bool

  func processIsRunning(withProcessIdentifier pid: pid_t) async throws -> Bool
}

public extension LaunchCtlCommands {

  /// True when `serviceName` is a launchctl service bound to a live pid. A loaded-but-stopped
  /// service (the "-" placeholder, surfaced as `NSNull` by `listServices()`) reads as not running.
  func serviceIsRunning(named serviceName: String) async throws -> Bool {
    guard let processIdentifier = try await listServices()[serviceName] as? NSNumber else {
      return false
    }
    return processIdentifier.int32Value > 0
  }

  /// True when `pid` owns a live launchctl service. Unlike `serviceName(forProcessIdentifier:)`,
  /// returns `false` instead of throwing when the pid is not a registered service.
  func processIsRunning(withProcessIdentifier pid: pid_t) async throws -> Bool {
    try await listServices().values.contains { ($0 as? NSNumber)?.int32Value == pid }
  }
}
