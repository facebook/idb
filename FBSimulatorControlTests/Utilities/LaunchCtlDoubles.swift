/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorControl
import Foundation

/// Test double for the launchctl command surface. Only `listServices()` is modelled —
/// the protocol's `serviceIsRunning(named:)` / `processIsRunning(withProcessIdentifier:)`
/// default implementations compute their verdict from it, so configuring `servicesResult`
/// exercises the real decision logic. Methods the suites do not use trap, keeping the
/// double honest about what it actually covers.
final class FBSimulatorControlTests_LaunchCtl_Double: LaunchCtlCommands {

  /// Mirrors `listServices()`: service-name -> `NSNumber(pid)` for a live service, `NSNull` for stopped.
  var servicesResult: [String: Any] = [:]

  /// Service names passed to `stopService(withName:)`, in call order — lets tests assert remediation.
  private(set) var stoppedServices: [String] = []

  /// Builds a double whose `listServices()` reports `running` as live pids and `stopped` as loaded-but-idle.
  static func with(running: [String: pid_t] = [:], stopped: [String] = []) -> FBSimulatorControlTests_LaunchCtl_Double {
    let double = FBSimulatorControlTests_LaunchCtl_Double()
    var services: [String: Any] = [:]
    for (name, pid) in running {
      services[name] = NSNumber(value: pid)
    }
    for name in stopped {
      services[name] = NSNull()
    }
    double.servicesResult = services
    return double
  }

  func listServices() async throws -> [String: Any] { servicesResult }

  func serviceName(forProcessIdentifier pid: pid_t) async throws -> String { fatalError("unused in tests") }
  func serviceName(forProcess process: FBProcessInfo) async throws -> String { fatalError("unused in tests") }
  func serviceNamesAndProcessIdentifiers(matching regex: NSRegularExpression) async throws -> [String: NSNumber] { fatalError("unused in tests") }
  func firstServiceNameAndProcessIdentifier(matching regex: NSRegularExpression) async throws -> (serviceName: String, processIdentifier: pid_t) { fatalError("unused in tests") }
  func processIsRunning(onSimulator process: FBProcessInfo) async throws -> Bool { fatalError("unused in tests") }
  func stopService(withName serviceName: String) async throws -> String {
    stoppedServices.append(serviceName)
    return ""
  }
  func startService(withName serviceName: String) async throws -> String { fatalError("unused in tests") }
}
