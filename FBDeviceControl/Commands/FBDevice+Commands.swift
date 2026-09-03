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

  var application: FBDeviceApplicationCommands {
    commandCache.resolve { FBDeviceApplicationCommands.commands(with: self) }
  }

  var crashLog: FBDeviceCrashLogCommands {
    commandCache.resolve { FBDeviceCrashLogCommands.commands(with: self) }
  }

  var screenshot: FBDeviceScreenshotCommands {
    commandCache.resolve { FBDeviceScreenshotCommands.commands(with: self) }
  }

  var location: FBDeviceLocationCommands {
    commandCache.resolve { FBDeviceLocationCommands.commands(with: self) }
  }

  var debugger: FBDeviceDebuggerCommands {
    commandCache.resolve { FBDeviceDebuggerCommands.commands(with: self) }
  }

  var file: FBDeviceFileCommands {
    commandCache.resolve { FBDeviceFileCommands.commands(with: self) }
  }

  var lifecycle: FBDeviceLifecycleCommands {
    commandCache.resolve { FBDeviceLifecycleCommands.commands(with: self) }
  }

  var log: FBDeviceLogCommands {
    commandCache.resolve { FBDeviceLogCommands.commands(with: self) }
  }

  var videoRecording: FBDeviceVideoRecordingCommands {
    commandCache.resolve { FBDeviceVideoRecordingCommands.commands(with: self) }
  }

  var xctest: FBDeviceXCTestCommands {
    commandCache.resolve { FBDeviceXCTestCommands.commands(with: self) }
  }

  var xctraceRecord: FBXCTraceRecordCommands {
    commandCache.resolve { FBXCTraceRecordCommands.commands(with: self) }
  }

  // MARK: - Device-only accessors

  var diagnosticInformation: FBDeviceDiagnosticInformationCommands {
    commandCache.resolve { FBDeviceDiagnosticInformationCommands.commands(with: self) }
  }

  var erase: FBDeviceEraseCommands {
    commandCache.resolve { FBDeviceEraseCommands.commands(with: self) }
  }

  var power: FBDevicePowerCommands {
    commandCache.resolve { FBDevicePowerCommands.commands(with: self) }
  }

  var provisioningProfile: FBDeviceProvisioningProfileCommands {
    commandCache.resolve { FBDeviceProvisioningProfileCommands.commands(with: self) }
  }

  var activation: FBDeviceActivationCommands {
    commandCache.resolve { FBDeviceActivationCommands.commands(with: self) }
  }

  var recovery: FBDeviceRecoveryCommands {
    commandCache.resolve { FBDeviceRecoveryCommands.commands(with: self) }
  }

  var debugSymbols: FBDeviceDebugSymbolsCommands {
    commandCache.resolve { FBDeviceDebugSymbolsCommands(device: self) }
  }

  var developerDiskImage: FBDeviceDeveloperDiskImageCommands {
    commandCache.resolve { FBDeviceDeveloperDiskImageCommands.commands(with: self) }
  }

  var socketForwarding: FBDeviceSocketForwardingCommands {
    commandCache.resolve { FBDeviceSocketForwardingCommands.commands(with: self) }
  }
}
