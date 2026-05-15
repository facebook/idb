/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

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
    commandCache.resolve { FBSimulatorLocationCommands.commands(with: self) }
  }

  func debuggerCommands() throws -> FBSimulatorDebuggerCommands {
    commandCache.resolve { FBSimulatorDebuggerCommands.commands(with: self) }
  }

  func fileCommands() throws -> FBSimulatorFileCommands {
    commandCache.resolve { FBSimulatorFileCommands.commands(with: self) }
  }

  func logCommands() throws -> FBSimulatorLogCommands {
    commandCache.resolve { FBSimulatorLogCommands.commands(with: self) }
  }

  func processSpawnCommands() throws -> FBSimulatorProcessSpawnCommands {
    commandCache.resolve { FBSimulatorProcessSpawnCommands.commands(with: self) }
  }

  func videoRecordingCommands() throws -> FBSimulatorVideoRecordingCommands {
    commandCache.resolve { FBSimulatorVideoRecordingCommands.commands(with: self) }
  }

  func launchCtlCommands() throws -> FBSimulatorLaunchCtlCommands {
    commandCache.resolve { FBSimulatorLaunchCtlCommands.commands(with: self) }
  }

  func instrumentsCommands() throws -> FBInstrumentsCommands {
    commandCache.resolve { FBInstrumentsCommands(target: self) }
  }

  func xctraceRecordCommands() throws -> FBXCTraceRecordCommands {
    commandCache.resolve { FBXCTraceRecordCommands.commands(with: self) }
  }

  // MARK: - Sim-only accessors

  func lifecycleCommands() throws -> FBSimulatorLifecycleCommands {
    commandCache.resolve { FBSimulatorLifecycleCommands.commands(with: self) }
  }

  func mediaCommands() throws -> FBSimulatorMediaCommands {
    commandCache.resolve { FBSimulatorMediaCommands.commands(with: self) }
  }

  func keychainCommands() throws -> FBSimulatorKeychainCommands {
    commandCache.resolve { FBSimulatorKeychainCommands.commands(with: self) }
  }

  func settingsCommands() throws -> FBSimulatorSettingsCommands {
    commandCache.resolve { FBSimulatorSettingsCommands.commands(with: self) }
  }

  func xctestExtendedCommands() throws -> FBSimulatorXCTestCommands {
    commandCache.resolve { FBSimulatorXCTestCommands.commands(with: self) }
  }

  func accessibilityCommands() throws -> FBSimulatorAccessibilityCommands {
    commandCache.resolve { FBSimulatorAccessibilityCommands.commands(with: self) }
  }

  func dapServerCommand() throws -> FBSimulatorDapServerCommand {
    commandCache.resolve { FBSimulatorDapServerCommand.commands(with: self) }
  }

  func notificationCommands() throws -> FBSimulatorNotificationCommands {
    commandCache.resolve { FBSimulatorNotificationCommands.commands(with: self) }
  }

  func memoryCommands() throws -> FBSimulatorMemoryCommands {
    commandCache.resolve { FBSimulatorMemoryCommands.commands(with: self) }
  }
}
