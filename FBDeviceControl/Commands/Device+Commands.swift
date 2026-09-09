/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

// Commands that own something outliving a single call — a notifier, an in-flight video, a set of
// AFC calls — are memoized through `commandCache` (`FBTargetCommandCache`), whose lock also stops
// two callers racing the first construction, and hold their device weakly so the cache slot does
// not close a cycle. Commands that only wrap the device are built per call and hold it strongly:
// nothing outlives the call that builds them.
extension FBDevice {

  // MARK: - Shared accessors

  var application: DeviceApplicationCommands {
    commandCache.resolve { DeviceApplicationCommands.commands(with: self) }
  }

  var crashLog: DeviceCrashLogCommands {
    commandCache.resolve { DeviceCrashLogCommands.commands(with: self) }
  }

  var screenshot: DeviceScreenshotCommands {
    DeviceScreenshotCommands.commands(with: self)
  }

  var location: DeviceLocationCommands {
    DeviceLocationCommands.commands(with: self)
  }

  var debugger: DeviceDebuggerCommands {
    DeviceDebuggerCommands.commands(with: self)
  }

  var file: DeviceFileCommands {
    commandCache.resolve { DeviceFileCommands.commands(with: self) }
  }

  var lifecycle: DeviceLifecycleCommands {
    DeviceLifecycleCommands.commands(with: self)
  }

  var log: DeviceLogCommands {
    DeviceLogCommands.commands(with: self)
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
    DeviceDiagnosticInformationCommands.commands(with: self)
  }

  var erase: DeviceEraseCommands {
    DeviceEraseCommands.commands(with: self)
  }

  var power: DevicePowerCommands {
    DevicePowerCommands.commands(with: self)
  }

  var provisioningProfile: DeviceProvisioningProfileCommands {
    DeviceProvisioningProfileCommands.commands(with: self)
  }

  var activation: DeviceActivationCommands {
    DeviceActivationCommands.commands(with: self)
  }

  var recovery: DeviceRecoveryCommands {
    DeviceRecoveryCommands.commands(with: self)
  }

  var debugSymbols: DeviceDebugSymbolsCommands {
    DeviceDebugSymbolsCommands(device: self)
  }

  var developerDiskImage: DeviceDeveloperDiskImageCommands {
    commandCache.resolve { DeviceDeveloperDiskImageCommands.commands(with: self) }
  }

  var socketForwarding: DeviceSocketForwardingCommands {
    DeviceSocketForwardingCommands.commands(with: self)
  }
}
