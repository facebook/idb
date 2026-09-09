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

  var application: DeviceApplicationCommands {
    commandCache.resolve { DeviceApplicationCommands.commands(with: self) }
  }

  var crashLog: DeviceCrashLogCommands {
    commandCache.resolve { DeviceCrashLogCommands.commands(with: self) }
  }

  var screenshot: DeviceScreenshotCommands {
    commandCache.resolve { DeviceScreenshotCommands.commands(with: self) }
  }

  var location: DeviceLocationCommands {
    commandCache.resolve { DeviceLocationCommands.commands(with: self) }
  }

  var debugger: DeviceDebuggerCommands {
    commandCache.resolve { DeviceDebuggerCommands.commands(with: self) }
  }

  var file: DeviceFileCommands {
    commandCache.resolve { DeviceFileCommands.commands(with: self) }
  }

  var lifecycle: DeviceLifecycleCommands {
    commandCache.resolve { DeviceLifecycleCommands.commands(with: self) }
  }

  var log: DeviceLogCommands {
    commandCache.resolve { DeviceLogCommands.commands(with: self) }
  }

  var videoRecording: DeviceVideoRecordingCommands {
    commandCache.resolve { DeviceVideoRecordingCommands.commands(with: self) }
  }

  var xctest: DeviceXCTestCommands {
    commandCache.resolve { DeviceXCTestCommands.commands(with: self) }
  }

  var xctraceRecord: FBXCTraceRecordCommands {
    FBXCTraceRecordCommands.commands(with: self)
  }

  // MARK: - Device-only accessors

  var diagnosticInformation: DeviceDiagnosticInformationCommands {
    commandCache.resolve { DeviceDiagnosticInformationCommands.commands(with: self) }
  }

  var erase: DeviceEraseCommands {
    commandCache.resolve { DeviceEraseCommands.commands(with: self) }
  }

  var power: DevicePowerCommands {
    commandCache.resolve { DevicePowerCommands.commands(with: self) }
  }

  var provisioningProfile: DeviceProvisioningProfileCommands {
    commandCache.resolve { DeviceProvisioningProfileCommands.commands(with: self) }
  }

  var activation: DeviceActivationCommands {
    commandCache.resolve { DeviceActivationCommands.commands(with: self) }
  }

  var recovery: DeviceRecoveryCommands {
    commandCache.resolve { DeviceRecoveryCommands.commands(with: self) }
  }

  var debugSymbols: DeviceDebugSymbolsCommands {
    commandCache.resolve { DeviceDebugSymbolsCommands(device: self) }
  }

  var developerDiskImage: DeviceDeveloperDiskImageCommands {
    commandCache.resolve { DeviceDeveloperDiskImageCommands.commands(with: self) }
  }

  var socketForwarding: DeviceSocketForwardingCommands {
    commandCache.resolve { DeviceSocketForwardingCommands.commands(with: self) }
  }
}
