/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

extension FBDevice {

  // MARK: - Shared accessors

  func applicationCommands() throws -> FBDeviceApplicationCommands {
    commandCache.resolve { FBDeviceApplicationCommands.commands(with: self) }
  }

  func crashLogCommands() throws -> FBDeviceCrashLogCommands {
    commandCache.resolve { FBDeviceCrashLogCommands.commands(with: self) }
  }

  func screenshotCommands() throws -> FBDeviceScreenshotCommands {
    commandCache.resolve { FBDeviceScreenshotCommands.commands(with: self) }
  }

  func locationCommands() throws -> FBDeviceLocationCommands {
    commandCache.resolve { FBDeviceLocationCommands.commands(with: self) }
  }

  func debuggerCommands() throws -> FBDeviceDebuggerCommands {
    commandCache.resolve { FBDeviceDebuggerCommands.commands(with: self) }
  }

  func fileCommands() throws -> FBDeviceFileCommands {
    commandCache.resolve { FBDeviceFileCommands.commands(with: self) }
  }

  func lifecycleCommands() throws -> FBDeviceLifecycleCommands {
    commandCache.resolve { FBDeviceLifecycleCommands.commands(with: self) }
  }

  func logCommands() throws -> FBDeviceLogCommands {
    commandCache.resolve { FBDeviceLogCommands.commands(with: self) }
  }

  func videoRecordingCommands() throws -> FBDeviceVideoRecordingCommands {
    commandCache.resolve { FBDeviceVideoRecordingCommands.commands(with: self) }
  }

  func xctestCommands() throws -> FBDeviceXCTestCommands {
    commandCache.resolve { FBDeviceXCTestCommands.commands(with: self) }
  }

  func instrumentsCommands() throws -> FBInstrumentsCommands {
    commandCache.resolve { FBInstrumentsCommands(target: self) }
  }

  func xctraceRecordCommands() throws -> FBXCTraceRecordCommands {
    commandCache.resolve { FBXCTraceRecordCommands.commands(with: self) }
  }

  // MARK: - Device-only accessors

  func diagnosticInformationCommands() throws -> FBDeviceDiagnosticInformationCommands {
    commandCache.resolve { FBDeviceDiagnosticInformationCommands.commands(with: self) }
  }

  func eraseCommands() throws -> FBDeviceEraseCommands {
    commandCache.resolve { FBDeviceEraseCommands.commands(with: self) }
  }

  func powerCommands() throws -> FBDevicePowerCommands {
    commandCache.resolve { FBDevicePowerCommands.commands(with: self) }
  }

  func provisioningProfileCommands() throws -> FBDeviceProvisioningProfileCommands {
    commandCache.resolve { FBDeviceProvisioningProfileCommands.commands(with: self) }
  }

  func activationCommands() throws -> FBDeviceActivationCommands {
    commandCache.resolve { FBDeviceActivationCommands.commands(with: self) }
  }

  func recoveryCommands() throws -> FBDeviceRecoveryCommands {
    commandCache.resolve { FBDeviceRecoveryCommands.commands(with: self) }
  }

  func debugSymbolsCommands() throws -> FBDeviceDebugSymbolsCommands {
    commandCache.resolve { FBDeviceDebugSymbolsCommands(device: self) }
  }

  func developerDiskImageCommands() throws -> FBDeviceDeveloperDiskImageCommands {
    commandCache.resolve { FBDeviceDeveloperDiskImageCommands.commands(with: self) }
  }
}
