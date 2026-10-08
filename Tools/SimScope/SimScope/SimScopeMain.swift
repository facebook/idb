/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

// patternlint-disable avoid-print-to-prevent-production-overhead

import AppKit
import FBControlCore
import FBSimulatorControl

// Programmatic AppKit entry point (no storyboard / nib).
@main
@MainActor
enum SimScopeMain {

  // `NSApplication.delegate` is a weak reference, so the delegate has to be owned for the lifetime
  // of the process.
  private static let delegate = AppDelegate()

  static func main() throws {
    if ProcessInfo.processInfo.arguments.contains("--check-installation") {
      for resource in [
        "SimulatorFrameworkBridge-iOS", "SimulatorFrameworkBridge-tvOS",
        "libShimulator-iOS.dylib", "libShimulator-macOS.dylib",
        "libRepl-iOS.dylib", "libRepl-macOS.dylib", "ReplHost.app", "IDBAPI.swiftinterface",
      ] {
        guard BundledResources.path(forItem: resource) != nil else {
          throw NSError(
            domain: "SimScope", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Missing bundled resource: \(resource)"])
        }
      }
      let configuration = SimulatorControlConfiguration(deviceSetPath: nil, logger: nil)
      let control = try SimulatorControlBootstrap.withConfiguration(configuration)
      print("SimScope installation OK (\(control.set.allSimulators.count) simulators available)")
      return
    }
    let application = NSApplication.shared
    application.delegate = delegate
    application.setActivationPolicy(.regular)
    application.run()
  }
}
