/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

// FBMacDevice has no equivalent for these simulator/device-oriented commands; each throws rather than silently no-ops.

// MARK: - Unsupported command helper

extension FBMacDevice {

  fileprivate func macUnsupported(_ command: String) -> any Error {
    MacDeviceError.commandUnsupported(command: command)
  }
}

// MARK: - Command nouns

// `FBMacDevice` implements every capability inline rather than through command types, so each noun
// resolves to the device itself. Splitting those implementations into command types is a separate
// change; the nouns can be stated regardless.
extension FBMacDevice {

  public var application: FBMacDevice { self }

  public var crashLog: FBMacDevice { self }

  public var debugger: FBMacDevice { self }

  public var erase: FBMacDevice { self }

  public var file: FBMacDevice { self }

  public var instruments: FBMacDevice { self }

  public var lifecycle: FBMacDevice { self }

  public var location: FBMacDevice { self }

  public var log: FBMacDevice { self }

  public var power: FBMacDevice { self }

  public var processSpawn: FBMacDevice { self }

  public var screenshot: FBMacDevice { self }

  public var videoRecording: FBMacDevice { self }

  public var videoStream: FBMacDevice { self }

  public var xctest: FBMacDevice { self }

  public var xctraceRecord: FBMacDevice { self }
}

// MARK: - FBMacDevice+VideoStreamCommands

extension FBMacDevice: VideoStreamCommands {

  public func createStream(configuration: FBVideoStreamConfiguration, to consumer: any FBDataConsumer) async throws -> any FBVideoStream {
    throw macUnsupported("createStream")
  }
}

// MARK: - FBMacDevice+DebuggerCommands

extension FBMacDevice: DebuggerCommands {

  public func launchDebugServer(forHostApplication application: FBBundleDescriptor, port: in_port_t) async throws -> any DebugServer {
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

  public func withContainerApplication<R>(_ bundleID: String, body: (any AsyncFileContainer) async throws -> R) async throws -> R {
    throw macUnsupported("file commands for application container")
  }

  public func withAuxiliary<R>(body: (any AsyncFileContainer) async throws -> R) async throws -> R {
    throw macUnsupported("file commands for the auxillary directory")
  }

  public func withApplicationContainers<R>(body: (any AsyncFileContainer) async throws -> R) async throws -> R {
    throw macUnsupported("file commands for application containers")
  }

  public func withGroupContainers<R>(body: (any AsyncFileContainer) async throws -> R) async throws -> R {
    throw macUnsupported("file commands for group containers")
  }

  public func withRootFilesystem<R>(body: (any AsyncFileContainer) async throws -> R) async throws -> R {
    throw macUnsupported("file commands for the root filesystem")
  }

  public func withMediaDirectory<R>(body: (any AsyncFileContainer) async throws -> R) async throws -> R {
    throw macUnsupported("file commands for the media directory")
  }

  public func withProvisioningProfiles<R>(body: (any AsyncFileContainer) async throws -> R) async throws -> R {
    throw macUnsupported("file commands for provisioning profiles")
  }

  public func withMDMProfiles<R>(body: (any AsyncFileContainer) async throws -> R) async throws -> R {
    throw macUnsupported("file commands for MDM profiles")
  }

  public func withSpringboardIconLayout<R>(body: (any AsyncFileContainer) async throws -> R) async throws -> R {
    throw macUnsupported("file commands for the springboard icon layout")
  }

  public func withWallpaper<R>(body: (any AsyncFileContainer) async throws -> R) async throws -> R {
    throw macUnsupported("file commands for the wallpaper")
  }

  public func withDiskImages<R>(body: (any AsyncFileContainer) async throws -> R) async throws -> R {
    throw macUnsupported("file commands for disk images")
  }

  public func withSymbols<R>(body: (any AsyncFileContainer) async throws -> R) async throws -> R {
    throw macUnsupported("file commands for symbols")
  }
}

// MARK: - FBMacDevice+LocationCommands

extension FBMacDevice: LocationCommands {

  public func set(longitude: Double, latitude: Double) async throws {
    throw macUnsupported("set")
  }
}

// MARK: - FBMacDevice+LogCommands

extension FBMacDevice: LogCommands {

  public func tail(arguments: [String], consumer: any FBDataConsumer) async throws -> any LogOperation {
    throw macUnsupported("tail")
  }
}

// MARK: - FBMacDevice+ScreenshotCommands

extension FBMacDevice: ScreenshotCommands {

  public func take(configuration: ScreenshotConfiguration) async throws -> ScreenshotResult {
    throw macUnsupported("take")
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

  public func start(configuration: XCTraceRecordConfiguration, logger: any FBControlCoreLogger) async throws -> XCTraceRecordOperation {
    throw macUnsupported("start")
  }
}

// MARK: - FBMacDevice+InstrumentsCommands

extension FBMacDevice: InstrumentsCommands {

  public func start(configuration: InstrumentsConfiguration, logger: any FBControlCoreLogger) async throws -> InstrumentsOperation {
    throw macUnsupported("start")
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

// MARK: - FBMacDevice+LogicTestTarget

extension FBMacDevice: LogicTestTarget {}
