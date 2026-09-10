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

  public var application: FBSimulatorApplicationCommands {
    FBSimulatorApplicationCommands.commands(with: self)
  }

  public var crashLog: SimulatorCrashLogCommands {
    commandCache.resolve { SimulatorCrashLogCommands.commands(with: self) }
  }

  public var screenshot: SimulatorScreenshotCommands {
    commandCache.resolve { SimulatorScreenshotCommands.commands(with: self) }
  }

  public var location: SimulatorLocationCommands {
    SimulatorLocationCommands.commands(with: self)
  }

  public var debugger: SimulatorDebuggerCommands {
    commandCache.resolve { SimulatorDebuggerCommands.commands(with: self) }
  }

  public var file: SimulatorFileCommands {
    SimulatorFileCommands.commands(with: self)
  }

  public var log: SimulatorLogCommands {
    SimulatorLogCommands.commands(with: self)
  }

  public var processSpawn: SimulatorProcessSpawnCommands {
    SimulatorProcessSpawnCommands.commands(with: self)
  }

  public var videoRecording: FBSimulatorVideoRecordingCommands {
    commandCache.resolve { FBSimulatorVideoRecordingCommands.commands(with: self) }
  }

  public var videoStream: SimulatorVideoStreamCommands {
    SimulatorVideoStreamCommands.commands(with: self)
  }

  public var launchCtl: SimulatorLaunchCtlCommands {
    SimulatorLaunchCtlCommands.commands(with: self)
  }

  public var xctraceRecord: FBXCTraceRecordCommands {
    FBXCTraceRecordCommands.commands(with: self)
  }

  public var instruments: SimulatorInstrumentsCommands {
    SimulatorInstrumentsCommands.commands(with: self)
  }

  // MARK: - Sim-only accessors

  public var lifecycle: SimulatorLifecycleCommands {
    commandCache.resolve { SimulatorLifecycleCommands.commands(with: self) }
  }

  public var power: SimulatorPowerCommands {
    SimulatorPowerCommands.commands(with: self)
  }

  public var erase: SimulatorEraseCommands {
    SimulatorEraseCommands.commands(with: self)
  }

  public var media: SimulatorMediaCommands {
    SimulatorMediaCommands.commands(with: self)
  }

  public var keychain: SimulatorKeychainCommands {
    SimulatorKeychainCommands.commands(with: self)
  }

  public var privacy: SimulatorPrivacyCommands {
    SimulatorPrivacyCommands.commands(with: self)
  }

  public var preferences: SimulatorPreferencesCommands {
    SimulatorPreferencesCommands.commands(with: self)
  }

  public var statusBar: SimulatorStatusBarCommands {
    SimulatorStatusBarCommands.commands(with: self)
  }

  public var network: SimulatorNetworkCommands {
    SimulatorNetworkCommands.commands(with: self)
  }

  public var health: SimulatorHealthCommands {
    SimulatorHealthCommands.commands(with: self)
  }

  public var contacts: SimulatorContactsCommands {
    SimulatorContactsCommands.commands(with: self)
  }

  public var photos: SimulatorPhotosCommands {
    SimulatorPhotosCommands.commands(with: self)
  }

  public var xctestExtended: SimulatorXCTestCommands {
    commandCache.resolve { SimulatorXCTestCommands.commands(with: self) }
  }

  var accessibility: SimulatorAccessibilityCommands {
    commandCache.resolve { SimulatorAccessibilityCommands.commands(with: self) }
  }

  public var dapServer: SimulatorDapServerCommand {
    SimulatorDapServerCommand.commands(with: self)
  }

  public var repl: FBSimulatorReplCommands {
    FBSimulatorReplCommands.commands(with: self)
  }

  public var notification: SimulatorNotificationCommands {
    SimulatorNotificationCommands.commands(with: self)
  }

  public var memory: SimulatorMemoryCommands {
    SimulatorMemoryCommands.commands(with: self)
  }
}
