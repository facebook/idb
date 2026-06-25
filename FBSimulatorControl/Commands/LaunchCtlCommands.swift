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
}
