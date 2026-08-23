/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

// The mac target exists to host `xctest` logic-test and mac-app execution, so it
// already conforms to `ApplicationCommands`, `CrashLogCommands` and
// `XCTestExtendedCommands` in `FBMacDevice.swift`. `AsynciOSTarget` additionally
// composes a set of simulator/device-oriented command protocols that have no mac
// equivalent; the conformances below fail with a clear message rather than
// silently no-op, matching how the unimplemented `CrashLogCommands` methods behave.

// MARK: - Unsupported command helper

extension FBMacDevice {

  fileprivate func macUnsupported(_ command: String) -> any Error {
    FBMacDeviceError.commandUnsupported(command: command)
  }
}

// MARK: - FBMacDevice+VideoStreamCommands

extension FBMacDevice: VideoStreamCommands {

  public func createStream(configuration: FBVideoStreamConfiguration, to consumer: any FBDataConsumer) async throws -> any FBVideoStream {
    throw macUnsupported("createStream")
  }
}

// MARK: - FBMacDevice+DebuggerCommands

extension FBMacDevice: DebuggerCommands {

  public func launchDebugServer(forHostApplication application: FBBundleDescriptor, port: in_port_t) async throws -> any FBDebugServer {
    throw macUnsupported("launchDebugServer")
  }
}

// MARK: - FBMacDevice+EraseCommands

extension FBMacDevice: EraseCommands {

  public func erase() async throws {
    throw macUnsupported("erase")
  }
}

// MARK: - FBMacDevice+FileCommands

extension FBMacDevice: FileCommands {

  public func withFileCommandsForContainerApplication<R>(_ bundleID: String, body: (any AsyncFileContainer) async throws -> R) async throws -> R {
    throw macUnsupported("file commands for application container")
  }

  public func withFileCommandsForAuxillary<R>(body: (any AsyncFileContainer) async throws -> R) async throws -> R {
    throw macUnsupported("file commands for the auxillary directory")
  }

  public func withFileCommandsForApplicationContainers<R>(body: (any AsyncFileContainer) async throws -> R) async throws -> R {
    throw macUnsupported("file commands for application containers")
  }

  public func withFileCommandsForGroupContainers<R>(body: (any AsyncFileContainer) async throws -> R) async throws -> R {
    throw macUnsupported("file commands for group containers")
  }

  public func withFileCommandsForRootFilesystem<R>(body: (any AsyncFileContainer) async throws -> R) async throws -> R {
    throw macUnsupported("file commands for the root filesystem")
  }

  public func withFileCommandsForMediaDirectory<R>(body: (any AsyncFileContainer) async throws -> R) async throws -> R {
    throw macUnsupported("file commands for the media directory")
  }

  public func withFileCommandsForProvisioningProfiles<R>(body: (any AsyncFileContainer) async throws -> R) async throws -> R {
    throw macUnsupported("file commands for provisioning profiles")
  }

  public func withFileCommandsForMDMProfiles<R>(body: (any AsyncFileContainer) async throws -> R) async throws -> R {
    throw macUnsupported("file commands for MDM profiles")
  }

  public func withFileCommandsForSpringboardIconLayout<R>(body: (any AsyncFileContainer) async throws -> R) async throws -> R {
    throw macUnsupported("file commands for the springboard icon layout")
  }

  public func withFileCommandsForWallpaper<R>(body: (any AsyncFileContainer) async throws -> R) async throws -> R {
    throw macUnsupported("file commands for the wallpaper")
  }

  public func withFileCommandsForDiskImages<R>(body: (any AsyncFileContainer) async throws -> R) async throws -> R {
    throw macUnsupported("file commands for disk images")
  }

  public func withFileCommandsForSymbols<R>(body: (any AsyncFileContainer) async throws -> R) async throws -> R {
    throw macUnsupported("file commands for symbols")
  }
}

// MARK: - FBMacDevice+LocationCommands

extension FBMacDevice: LocationCommands {

  public func overrideLocation(longitude: Double, latitude: Double) async throws {
    throw macUnsupported("overrideLocation")
  }
}

// MARK: - FBMacDevice+LogCommands

extension FBMacDevice: LogCommands {

  public func tailLog(arguments: [String], consumer: any FBDataConsumer) async throws -> any LogOperation {
    throw macUnsupported("tailLog")
  }
}

// MARK: - FBMacDevice+ScreenshotCommands

extension FBMacDevice: ScreenshotCommands {

  public func takeScreenshot(format: FBScreenshotFormat) async throws -> Data {
    throw macUnsupported("takeScreenshot")
  }
}

// MARK: - FBMacDevice+VideoRecordingCommands

extension FBMacDevice: VideoRecordingCommands {

  public func startRecording(toFile filePath: String) async throws -> any FBVideoRecording {
    throw macUnsupported("startRecording")
  }
}

// MARK: - FBMacDevice+XCTraceRecordCommands

extension FBMacDevice: XCTraceRecordCommands {

  public func startXctraceRecord(configuration: FBXCTraceRecordConfiguration, logger: any FBControlCoreLogger) async throws -> FBXCTraceRecordOperation {
    throw macUnsupported("startXctraceRecord")
  }
}

// MARK: - FBMacDevice+InstrumentsCommands

extension FBMacDevice: InstrumentsCommands {

  public func startInstruments(configuration: FBInstrumentsConfiguration, logger: any FBControlCoreLogger) async throws -> FBInstrumentsOperation {
    throw macUnsupported("startInstruments")
  }
}

// MARK: - FBMacDevice+LifecycleCommands

extension FBMacDevice: LifecycleCommands {

  public func resolveState(_ state: FBiOSTargetState) async throws {
    throw macUnsupported("resolveState")
  }

  public func resolveLeavesState(_ state: FBiOSTargetState) async throws {
    throw macUnsupported("resolveLeavesState")
  }
}

// MARK: - FBMacDevice+PowerCommands

extension FBMacDevice: PowerCommands {

  public func shutdown() async throws {
    throw macUnsupported("shutdown")
  }

  public func reboot() async throws {
    throw macUnsupported("reboot")
  }
}

// MARK: - FBMacDevice+AsynciOSTarget

extension FBMacDevice: AsynciOSTarget {}
