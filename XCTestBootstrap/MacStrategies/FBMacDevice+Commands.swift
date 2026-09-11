/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

// MacDevice has no equivalent for these simulator/device-oriented commands; each throws rather than silently no-ops.

// MARK: - Unsupported command helper

extension MacDevice {

  fileprivate func macUnsupported(_ command: String) -> any Error {
    MacDeviceError.commandUnsupported(command: command)
  }
}

// MARK: - Command nouns

// `MacDevice` implements every capability inline rather than through command types, so each noun
// resolves to the device itself. Splitting those implementations into command types is a separate
// change; the nouns can be stated regardless.
extension MacDevice {

  public var application: MacDevice { self }

  public var crashLog: MacDevice { self }

  public var debugger: MacDevice { self }

  public var erase: MacDevice { self }

  public var file: MacDevice { self }

  public var instruments: MacDevice { self }

  public var lifecycle: MacDevice { self }

  public var location: MacDevice { self }

  public var log: MacDevice { self }

  public var power: MacDevice { self }

  public var processSpawn: MacDevice { self }

  public var screenshot: MacDevice { self }

  public var videoRecording: MacDevice { self }

  public var videoStream: MacDevice { self }

  public var xctest: MacDevice { self }

  public var xctraceRecord: MacDevice { self }
}

// MARK: - MacDevice+VideoStreamCommands

extension MacDevice: VideoStreamCommands {

  public func createStream(configuration: FBVideoStreamConfiguration, to consumer: any FBDataConsumer) async throws -> any FBVideoStream {
    throw macUnsupported("createStream")
  }
}

// MARK: - MacDevice+DebuggerCommands

extension MacDevice: DebuggerCommands {

  public func launchDebugServer(forHostApplication application: FBBundleDescriptor, port: in_port_t) async throws -> any DebugServer {
    throw macUnsupported("launchDebugServer")
  }
}

// MARK: - MacDevice+EraseCommands

extension MacDevice: EraseCommands {

  public func erase() async throws {
    throw macUnsupported("erase")
  }
}

// MARK: - MacDevice+FileCommands

extension MacDevice: FileCommands {

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

// MARK: - MacDevice+LocationCommands

extension MacDevice: LocationCommands {

  public func set(longitude: Double, latitude: Double) async throws {
    throw macUnsupported("set")
  }
}

// MARK: - MacDevice+LogCommands

extension MacDevice: LogCommands {

  public func tail(arguments: [String], consumer: any FBDataConsumer) async throws -> any LogOperation {
    throw macUnsupported("tail")
  }
}

// MARK: - MacDevice+ScreenshotCommands

extension MacDevice: ScreenshotCommands {

  public func take(configuration: ScreenshotConfiguration) async throws -> ScreenshotResult {
    throw macUnsupported("take")
  }
}

// MARK: - MacDevice+VideoRecordingCommands

extension MacDevice: VideoRecordingCommands {

  public func startRecording(toFile filePath: String) async throws -> any FBVideoRecording {
    throw macUnsupported("startRecording")
  }
}

// MARK: - MacDevice+XCTraceRecordCommands

extension MacDevice: XCTraceRecordCommands {

  public func start(configuration: XCTraceRecordConfiguration, logger: any FBControlCoreLogger) async throws -> XCTraceRecordOperation {
    throw macUnsupported("start")
  }
}

// MARK: - MacDevice+InstrumentsCommands

extension MacDevice: InstrumentsCommands {

  public func start(configuration: InstrumentsConfiguration, logger: any FBControlCoreLogger) async throws -> InstrumentsOperation {
    throw macUnsupported("start")
  }
}

// MARK: - MacDevice+LifecycleCommands

extension MacDevice: LifecycleCommands {

  public func resolveState(_ state: FBiOSTargetState) async throws {
    throw macUnsupported("resolveState")
  }

  public func resolveLeavesState(_ state: FBiOSTargetState) async throws {
    throw macUnsupported("resolveLeavesState")
  }
}

// MARK: - MacDevice+PowerCommands

extension MacDevice: PowerCommands {

  public func shutdown() async throws {
    throw macUnsupported("shutdown")
  }

  public func reboot() async throws {
    throw macUnsupported("reboot")
  }
}

// MARK: - MacDevice+LogicTestTarget

extension MacDevice: LogicTestTarget {}
