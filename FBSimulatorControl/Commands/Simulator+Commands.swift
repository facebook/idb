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
extension FBSimulator {

  // MARK: - Shared accessors

  var application: FBSimulatorApplicationCommands {
    FBSimulatorApplicationCommands.commands(with: self)
  }

  var crashLog: SimulatorCrashLogCommands {
    commandCache.resolve { SimulatorCrashLogCommands.commands(with: self) }
  }

  var screenshot: SimulatorScreenshotCommands {
    commandCache.resolve { SimulatorScreenshotCommands.commands(with: self) }
  }

  var location: SimulatorLocationCommands {
    SimulatorLocationCommands.commands(with: self)
  }

  var debugger: SimulatorDebuggerCommands {
    commandCache.resolve { SimulatorDebuggerCommands.commands(with: self) }
  }

  var file: SimulatorFileCommands {
    SimulatorFileCommands.commands(with: self)
  }

  var log: SimulatorLogCommands {
    SimulatorLogCommands.commands(with: self)
  }

  var processSpawn: SimulatorProcessSpawnCommands {
    SimulatorProcessSpawnCommands.commands(with: self)
  }

  var videoRecording: FBSimulatorVideoRecordingCommands {
    commandCache.resolve { FBSimulatorVideoRecordingCommands.commands(with: self) }
  }

  var launchCtl: SimulatorLaunchCtlCommands {
    SimulatorLaunchCtlCommands.commands(with: self)
  }

  var xctraceRecord: FBXCTraceRecordCommands {
    FBXCTraceRecordCommands.commands(with: self)
  }

  // MARK: - Sim-only accessors

  var lifecycle: FBSimulatorLifecycleCommands {
    commandCache.resolve { FBSimulatorLifecycleCommands.commands(with: self) }
  }

  var media: SimulatorMediaCommands {
    SimulatorMediaCommands.commands(with: self)
  }

  var keychain: SimulatorKeychainCommands {
    SimulatorKeychainCommands.commands(with: self)
  }

  var settings: SimulatorSettingsCommands {
    SimulatorSettingsCommands.commands(with: self)
  }

  var xctestExtended: SimulatorXCTestCommands {
    commandCache.resolve { SimulatorXCTestCommands.commands(with: self) }
  }

  var accessibility: SimulatorAccessibilityCommands {
    commandCache.resolve { SimulatorAccessibilityCommands.commands(with: self) }
  }

  var dapServer: SimulatorDapServerCommand {
    SimulatorDapServerCommand.commands(with: self)
  }

  var repl: FBSimulatorReplCommands {
    FBSimulatorReplCommands.commands(with: self)
  }

  var notification: SimulatorNotificationCommands {
    SimulatorNotificationCommands.commands(with: self)
  }

  var memory: SimulatorMemoryCommands {
    SimulatorMemoryCommands.commands(with: self)
  }
}
