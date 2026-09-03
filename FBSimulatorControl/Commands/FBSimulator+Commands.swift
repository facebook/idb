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
// for one would hold a box around a pointer back to the object owning the cache, closing a retain
// cycle.
//
// The cache is also how the accessibility commands are given a mock translation dispatcher in
// tests, via `commandCache.register(_:as:)`. That is a testing seam rather than a caching need,
// and the only one left.
extension FBSimulator {

  // MARK: - Shared accessors

  var applicationCommands: FBSimulatorApplicationCommands {
    commandCache.resolve { FBSimulatorApplicationCommands.commands(with: self) }
  }

  var crashLogCommands: FBSimulatorCrashLogCommands {
    commandCache.resolve { FBSimulatorCrashLogCommands.commands(with: self) }
  }

  var screenshotCommands: FBSimulatorScreenshotCommands {
    commandCache.resolve { FBSimulatorScreenshotCommands.commands(with: self) }
  }

  var locationCommands: FBSimulatorLocationCommands {
    FBSimulatorLocationCommands.commands(with: self)
  }

  var debuggerCommands: FBSimulatorDebuggerCommands {
    commandCache.resolve { FBSimulatorDebuggerCommands.commands(with: self) }
  }

  var fileCommands: FBSimulatorFileCommands {
    FBSimulatorFileCommands.commands(with: self)
  }

  var logCommands: FBSimulatorLogCommands {
    FBSimulatorLogCommands.commands(with: self)
  }

  var processSpawnCommands: FBSimulatorProcessSpawnCommands {
    FBSimulatorProcessSpawnCommands.commands(with: self)
  }

  var videoRecordingCommands: FBSimulatorVideoRecordingCommands {
    commandCache.resolve { FBSimulatorVideoRecordingCommands.commands(with: self) }
  }

  var launchCtlCommands: FBSimulatorLaunchCtlCommands {
    FBSimulatorLaunchCtlCommands.commands(with: self)
  }

  var xctraceRecordCommands: FBXCTraceRecordCommands {
    commandCache.resolve { FBXCTraceRecordCommands.commands(with: self) }
  }

  // MARK: - Sim-only accessors

  var lifecycleCommands: FBSimulatorLifecycleCommands {
    commandCache.resolve { FBSimulatorLifecycleCommands.commands(with: self) }
  }

  var mediaCommands: FBSimulatorMediaCommands {
    FBSimulatorMediaCommands.commands(with: self)
  }

  var keychainCommands: FBSimulatorKeychainCommands {
    FBSimulatorKeychainCommands.commands(with: self)
  }

  var settingsCommands: FBSimulatorSettingsCommands {
    FBSimulatorSettingsCommands.commands(with: self)
  }

  var xctestExtendedCommands: FBSimulatorXCTestCommands {
    commandCache.resolve { FBSimulatorXCTestCommands.commands(with: self) }
  }

  var accessibilityCommands: FBSimulatorAccessibilityCommands {
    commandCache.resolve { FBSimulatorAccessibilityCommands.commands(with: self) }
  }

  var dapServerCommand: FBSimulatorDapServerCommand {
    FBSimulatorDapServerCommand.commands(with: self)
  }

  var replCommands: FBSimulatorReplCommands {
    commandCache.resolve { FBSimulatorReplCommands.commands(with: self) }
  }

  var notificationCommands: FBSimulatorNotificationCommands {
    FBSimulatorNotificationCommands.commands(with: self)
  }

  var memoryCommands: FBSimulatorMemoryCommands {
    FBSimulatorMemoryCommands.commands(with: self)
  }
}
