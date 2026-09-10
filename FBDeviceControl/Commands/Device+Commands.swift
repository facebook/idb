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

  public var application: DeviceApplicationCommands {
    commandCache.resolve { DeviceApplicationCommands.commands(with: self) }
  }

  public var crashLog: DeviceCrashLogCommands {
    commandCache.resolve { DeviceCrashLogCommands.commands(with: self) }
  }

  public var screenshot: DeviceScreenshotCommands {
    DeviceScreenshotCommands.commands(with: self)
  }

  public var location: DeviceLocationCommands {
    DeviceLocationCommands.commands(with: self)
  }

  public var debugger: DeviceDebuggerCommands {
    DeviceDebuggerCommands.commands(with: self)
  }

  public var file: DeviceFileCommands {
    commandCache.resolve { DeviceFileCommands.commands(with: self) }
  }

  public var lifecycle: DeviceLifecycleCommands {
    DeviceLifecycleCommands.commands(with: self)
  }

  public var log: DeviceLogCommands {
    DeviceLogCommands.commands(with: self)
  }

  public var videoRecording: DeviceVideoRecordingCommands {
    commandCache.resolve { DeviceVideoRecordingCommands.commands(with: self) }
  }

  public var videoStream: DeviceVideoStreamCommands {
    DeviceVideoStreamCommands.commands(with: self)
  }

  public var xctest: DeviceXCTestCommands {
    commandCache.resolve { DeviceXCTestCommands.commands(with: self) }
  }

  public var xctraceRecord: FBXCTraceRecordCommands {
    FBXCTraceRecordCommands.commands(with: self)
  }

  public var instruments: DeviceInstrumentsCommands {
    DeviceInstrumentsCommands.commands(with: self)
  }

  // MARK: - Device-only accessors

  public var diagnosticInformation: DeviceDiagnosticInformationCommands {
    DeviceDiagnosticInformationCommands.commands(with: self)
  }

  public var erase: DeviceEraseCommands {
    DeviceEraseCommands.commands(with: self)
  }

  public var power: DevicePowerCommands {
    DevicePowerCommands.commands(with: self)
  }

  public var provisioningProfile: DeviceProvisioningProfileCommands {
    DeviceProvisioningProfileCommands.commands(with: self)
  }

  public var activation: DeviceActivationCommands {
    DeviceActivationCommands.commands(with: self)
  }

  public var recovery: DeviceRecoveryCommands {
    DeviceRecoveryCommands.commands(with: self)
  }

  public var debugSymbols: DeviceDebugSymbolsCommands {
    DeviceDebugSymbolsCommands(device: self)
  }

  public var developerDiskImage: DeviceDeveloperDiskImageCommands {
    commandCache.resolve { DeviceDeveloperDiskImageCommands.commands(with: self) }
  }

  public var socketForwarding: DeviceSocketForwardingCommands {
    DeviceSocketForwardingCommands.commands(with: self)
  }
}
