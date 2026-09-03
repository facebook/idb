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
// tests, via `commandCache.register(_:as:)`. That is a testing seam rather than a caching need.
extension FBSimulator {

  // MARK: - Shared accessors

  var application: FBSimulatorApplicationCommands {
    commandCache.resolve { FBSimulatorApplicationCommands.commands(with: self) }
  }

  var crashLog: FBSimulatorCrashLogCommands {
    commandCache.resolve { FBSimulatorCrashLogCommands.commands(with: self) }
  }

  var screenshot: FBSimulatorScreenshotCommands {
    commandCache.resolve { FBSimulatorScreenshotCommands.commands(with: self) }
  }

  var location: FBSimulatorLocationCommands {
    FBSimulatorLocationCommands.commands(with: self)
  }

  var debugger: FBSimulatorDebuggerCommands {
    commandCache.resolve { FBSimulatorDebuggerCommands.commands(with: self) }
  }

  var file: FBSimulatorFileCommands {
    FBSimulatorFileCommands.commands(with: self)
  }

  var log: FBSimulatorLogCommands {
    FBSimulatorLogCommands.commands(with: self)
  }

  var processSpawn: FBSimulatorProcessSpawnCommands {
    FBSimulatorProcessSpawnCommands.commands(with: self)
  }

  var videoRecording: FBSimulatorVideoRecordingCommands {
    commandCache.resolve { FBSimulatorVideoRecordingCommands.commands(with: self) }
  }

  var launchCtl: FBSimulatorLaunchCtlCommands {
    FBSimulatorLaunchCtlCommands.commands(with: self)
  }

  var xctraceRecord: FBXCTraceRecordCommands {
    FBXCTraceRecordCommands.commands(with: self)
  }

  // MARK: - Sim-only accessors

  var lifecycle: FBSimulatorLifecycleCommands {
    commandCache.resolve { FBSimulatorLifecycleCommands.commands(with: self) }
  }

  var media: FBSimulatorMediaCommands {
    FBSimulatorMediaCommands.commands(with: self)
  }

  var keychain: FBSimulatorKeychainCommands {
    FBSimulatorKeychainCommands.commands(with: self)
  }

  var settings: FBSimulatorSettingsCommands {
    FBSimulatorSettingsCommands.commands(with: self)
  }

  var xctestExtended: FBSimulatorXCTestCommands {
    commandCache.resolve { FBSimulatorXCTestCommands.commands(with: self) }
  }

  var accessibility: FBSimulatorAccessibilityCommands {
    commandCache.resolve { FBSimulatorAccessibilityCommands.commands(with: self) }
  }

  var dapServer: FBSimulatorDapServerCommand {
    FBSimulatorDapServerCommand.commands(with: self)
  }

  var repl: FBSimulatorReplCommands {
    commandCache.resolve { FBSimulatorReplCommands.commands(with: self) }
  }

  var notification: FBSimulatorNotificationCommands {
    FBSimulatorNotificationCommands.commands(with: self)
  }

  var memory: FBSimulatorMemoryCommands {
    FBSimulatorMemoryCommands.commands(with: self)
  }
}
