/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

// Commands that own something outliving a single call — a notifier, an in-flight video, a task —
// are memoized through `commandCache` (`FBTargetCommandCache`), whose lock also stops two callers
// racing the first construction. Commands that only wrap the simulator are built per call: a slot
// for one would hold a box around a pointer back to the object owning the cache, and caching one
// used to close a retain cycle.
//
// The cache is also how the accessibility commands are given a mock translation dispatcher in
// tests, via `commandCache.register(_:as:)`. That is a testing seam rather than a caching need,
// and the only one left.
extension FBSimulator {

  // MARK: - Shared accessors

  func applicationCommands() throws -> FBSimulatorApplicationCommands {
    commandCache.resolve { FBSimulatorApplicationCommands.commands(with: self) }
  }

  func crashLogCommands() throws -> FBSimulatorCrashLogCommands {
    commandCache.resolve { FBSimulatorCrashLogCommands.commands(with: self) }
  }

  func screenshotCommands() throws -> FBSimulatorScreenshotCommands {
    commandCache.resolve { FBSimulatorScreenshotCommands.commands(with: self) }
  }

  func locationCommands() throws -> FBSimulatorLocationCommands {
    FBSimulatorLocationCommands.commands(with: self)
  }

  func debuggerCommands() throws -> FBSimulatorDebuggerCommands {
    commandCache.resolve { FBSimulatorDebuggerCommands.commands(with: self) }
  }

  func fileCommands() throws -> FBSimulatorFileCommands {
    FBSimulatorFileCommands.commands(with: self)
  }

  func logCommands() throws -> FBSimulatorLogCommands {
    FBSimulatorLogCommands.commands(with: self)
  }

  func processSpawnCommands() throws -> FBSimulatorProcessSpawnCommands {
    FBSimulatorProcessSpawnCommands.commands(with: self)
  }

  func videoRecordingCommands() throws -> FBSimulatorVideoRecordingCommands {
    commandCache.resolve { FBSimulatorVideoRecordingCommands.commands(with: self) }
  }

  func launchCtlCommands() throws -> FBSimulatorLaunchCtlCommands {
    FBSimulatorLaunchCtlCommands.commands(with: self)
  }

  func xctraceRecordCommands() throws -> FBXCTraceRecordCommands {
    commandCache.resolve { FBXCTraceRecordCommands.commands(with: self) }
  }

  // MARK: - Sim-only accessors

  func lifecycleCommands() throws -> FBSimulatorLifecycleCommands {
    commandCache.resolve { FBSimulatorLifecycleCommands.commands(with: self) }
  }

  func mediaCommands() throws -> FBSimulatorMediaCommands {
    FBSimulatorMediaCommands.commands(with: self)
  }

  func keychainCommands() throws -> FBSimulatorKeychainCommands {
    FBSimulatorKeychainCommands.commands(with: self)
  }

  func settingsCommands() throws -> FBSimulatorSettingsCommands {
    FBSimulatorSettingsCommands.commands(with: self)
  }

  func xctestExtendedCommands() throws -> FBSimulatorXCTestCommands {
    commandCache.resolve { FBSimulatorXCTestCommands.commands(with: self) }
  }

  func accessibilityCommands() throws -> FBSimulatorAccessibilityCommands {
    commandCache.resolve { FBSimulatorAccessibilityCommands.commands(with: self) }
  }

  func dapServerCommand() throws -> FBSimulatorDapServerCommand {
    FBSimulatorDapServerCommand.commands(with: self)
  }

  func replCommands() throws -> FBSimulatorReplCommands {
    commandCache.resolve { FBSimulatorReplCommands.commands(with: self) }
  }

  func notificationCommands() throws -> FBSimulatorNotificationCommands {
    FBSimulatorNotificationCommands.commands(with: self)
  }

  func memoryCommands() throws -> FBSimulatorMemoryCommands {
    FBSimulatorMemoryCommands.commands(with: self)
  }
}
