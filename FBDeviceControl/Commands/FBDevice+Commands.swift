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

  var applicationCommands: FBDeviceApplicationCommands {
    commandCache.resolve { FBDeviceApplicationCommands.commands(with: self) }
  }

  var crashLogCommands: FBDeviceCrashLogCommands {
    commandCache.resolve { FBDeviceCrashLogCommands.commands(with: self) }
  }

  var screenshotCommands: FBDeviceScreenshotCommands {
    commandCache.resolve { FBDeviceScreenshotCommands.commands(with: self) }
  }

  var locationCommands: FBDeviceLocationCommands {
    commandCache.resolve { FBDeviceLocationCommands.commands(with: self) }
  }

  var debuggerCommands: FBDeviceDebuggerCommands {
    commandCache.resolve { FBDeviceDebuggerCommands.commands(with: self) }
  }

  var fileCommands: FBDeviceFileCommands {
    commandCache.resolve { FBDeviceFileCommands.commands(with: self) }
  }

  var lifecycleCommands: FBDeviceLifecycleCommands {
    commandCache.resolve { FBDeviceLifecycleCommands.commands(with: self) }
  }

  var logCommands: FBDeviceLogCommands {
    commandCache.resolve { FBDeviceLogCommands.commands(with: self) }
  }

  var videoRecordingCommands: FBDeviceVideoRecordingCommands {
    commandCache.resolve { FBDeviceVideoRecordingCommands.commands(with: self) }
  }

  var xctestCommands: FBDeviceXCTestCommands {
    commandCache.resolve { FBDeviceXCTestCommands.commands(with: self) }
  }

  var xctraceRecordCommands: FBXCTraceRecordCommands {
    commandCache.resolve { FBXCTraceRecordCommands.commands(with: self) }
  }

  // MARK: - Device-only accessors

  var diagnosticInformationCommands: FBDeviceDiagnosticInformationCommands {
    commandCache.resolve { FBDeviceDiagnosticInformationCommands.commands(with: self) }
  }

  var eraseCommands: FBDeviceEraseCommands {
    commandCache.resolve { FBDeviceEraseCommands.commands(with: self) }
  }

  var powerCommands: FBDevicePowerCommands {
    commandCache.resolve { FBDevicePowerCommands.commands(with: self) }
  }

  var provisioningProfileCommands: FBDeviceProvisioningProfileCommands {
    commandCache.resolve { FBDeviceProvisioningProfileCommands.commands(with: self) }
  }

  var activationCommands: FBDeviceActivationCommands {
    commandCache.resolve { FBDeviceActivationCommands.commands(with: self) }
  }

  var recoveryCommands: FBDeviceRecoveryCommands {
    commandCache.resolve { FBDeviceRecoveryCommands.commands(with: self) }
  }

  var debugSymbolsCommands: FBDeviceDebugSymbolsCommands {
    commandCache.resolve { FBDeviceDebugSymbolsCommands(device: self) }
  }

  var developerDiskImageCommands: FBDeviceDeveloperDiskImageCommands {
    commandCache.resolve { FBDeviceDeveloperDiskImageCommands.commands(with: self) }
  }

  var socketForwardingCommands: FBDeviceSocketForwardingCommands {
    commandCache.resolve { FBDeviceSocketForwardingCommands.commands(with: self) }
  }
}
