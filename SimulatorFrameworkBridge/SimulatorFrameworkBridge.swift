/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

// The open-source build compiles this file into the Support module itself.
#if canImport(SimulatorFrameworkBridgeSupport)
import SimulatorFrameworkBridgeSupport
#endif

@main
struct SimulatorFrameworkBridgeMain {
  static func main() {
    exit(autoreleasepool { FBBridgeCommand.run(arguments: CommandLine.arguments) })
  }
}
