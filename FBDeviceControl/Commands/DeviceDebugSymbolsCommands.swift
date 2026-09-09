/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation

private let FetchSymbolsService = "com.apple.dt.fetchsymbols"

private let ListFilesPlistCommand: UInt32 = 0x3030_3030
private let ListFilesPlistAck = ListFilesPlistCommand
private let GetFileCommand: UInt32 = 0x0100_0000
private let GetFileAck = GetFileCommand

private let SharedCachePathPrefix = "/System/Library"
private let SharedCachePathFragment = "shared_cache"

// Signature from the open-source dyld: https://opensource.apple.com/source/dyld/dyld-433.5/launch-cache/dsc_extractor.cpp.auto.html
private typealias SharedCacheExtractor =
  @convention(c) (
    UnsafePointer<CChar>?,
    UnsafePointer<CChar>?,
    @convention(block) (Int32, Int32) -> Void
  ) -> Int32

public enum FBDeviceDebugSymbolsError: Error {
  case destinationDirectoryNotCreated(message: String)
  case listingReceiveFailed(message: String)
  case listingNotStrings(files: String)
  case commandSendFailed(command: String, message: String)
  case commandResponseFailed(command: String, message: String)
  case commandAckMismatch(command: String, received: UInt32, expected: UInt32)
  case fileIndexSendFailed(index: UInt32, message: String)
  case fileLengthReceiveFailed(message: String)
  case fileLengthZero
  case destinationFileNotCreated(path: String)
  case destinationFileNotOpened(path: String)
  case fileNotInListing(file: String, listing: String)
  case sharedCacheNotFound(paths: String)
  case extractorNotFound(path: String)
  case extractorNotLoaded(path: String)
  case extractorSymbolNotFound(name: String, path: String)
  case extractionFailed(sharedCache: String, destination: String, status: Int32)
}

extension FBDeviceDebugSymbolsError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case let .destinationDirectoryNotCreated(message):
      return "Failed to create destination directory for symbol extraction: \(message)"
    case let .listingReceiveFailed(message):
      return "Failed to receive ListFiles plist message \(message)"
    case let .listingNotStrings(files):
      return "ListFilesPlist expected Array<String> for 'files' but got \(files)"
    case let .commandSendFailed(command, message):
      return "Failed to send '\(command)' command to symbol service \(message)"
    case let .commandResponseFailed(command, message):
      return "Failed to receive '\(command)' response from \(message)"
    case let .commandAckMismatch(command, received, expected):
      return "Incorrect '\(command)' ack from symbol service; got \(received) expected \(expected)"
    case let .fileIndexSendFailed(index, message):
      return "Failed to send GetFile file index \(index) packet \(message)"
    case let .fileLengthReceiveFailed(message):
      return "Failed to receive GetFile file length \(message)"
    case .fileLengthZero:
      return "Failed to get file length, receiveLength not returned or is zero."
    case let .destinationFileNotCreated(path):
      return "Failed to create destination file at path \(path)"
    case let .destinationFileNotOpened(path):
      return "Failed to open file for writing at \(path)"
    case let .fileNotInListing(file, listing):
      return "Could not find \(file) within \(listing)"
    case let .sharedCacheNotFound(paths):
      return "Could not find the shared cache file within \(paths)"
    case let .extractorNotFound(path):
      return "Expected dyld_shared_cache extractor library was not found at path \(path)"
    case let .extractorNotLoaded(path):
      return "Failed to dlopen() \(path)"
    case let .extractorSymbolNotFound(name, path):
      return "\(name) could not be located in \(path)"
    case let .extractionFailed(sharedCache, destination, status):
      return "Failed to get extract shared cache directory \(sharedCache) to \(destination) with status \(status)"
    }
  }
}

public final class FBDeviceDebugSymbolsCommands: DebugSymbolsCommands {
  private weak var device: FBDevice?

  init(device: FBDevice) {
    self.device = device
  }

  // MARK: - DebugSymbolsCommands

  public func listSymbols() async throws -> [String] {
    try await withSymbolServiceConnection { connection in
      try Self.obtainFileListing(from: connection)
    }
  }

  public func pullSymbolFile(_ fileName: String, toDestinationPath destinationPath: String) async throws -> String {
    let index = try await indexOfSymbolFile(fileName)
    return try await writeSymbolFile(index: index, toFileAtPath: destinationPath)
  }

  public func pullAndExtractSymbols(toDestinationDirectory destinationDirectory: String) async throws -> String {
    do {
      try FileManager.default.createDirectory(atPath: destinationDirectory, withIntermediateDirectories: true)
    } catch {
      throw FBDeviceDebugSymbolsError.destinationDirectoryNotCreated(message: String(describing: error))
    }
    guard let device else {
      throw FBDeviceNilError.deviceNil
    }
    let logger = device.logger

    let indicesToRemotePaths = try await indicesAndRemotePathsOfSharedCache()
    logger.log("Extracting remote symbols \(FBCollectionInformation.oneLineDescription(from: Array(indicesToRemotePaths.values)))")

    var extractedPaths: [String] = []
    for (index, remotePath) in indicesToRemotePaths {
      let localPath = (destinationDirectory as NSString).appendingPathComponent((remotePath as NSString).lastPathComponent)
      extractedPaths.append(try await writeSymbolFile(index: index, toFileAtPath: localPath))
    }

    let sharedCachePath = try Self.extractSharedCachePath(fromPaths: extractedPaths)
    try Self.extractSharedCacheFile(sharedCachePath, toDestinationDirectory: destinationDirectory, logger: logger)
    for extractedPath in extractedPaths {
      try? FileManager.default.removeItem(atPath: extractedPath)
    }
    return destinationDirectory
  }

  // MARK: - Private

  /// Each operation takes its own connection, as the service's protocol is per-connection state:
  /// once a file has been requested the connection is spent.
  private func withSymbolServiceConnection<T>(_ body: (FBAMDServiceConnection) async throws -> T) async throws -> T {
    guard let device else {
      throw FBDeviceNilError.deviceNil
    }
    _ = try await device.developerDiskImage.ensureDeveloperDiskImageIsMounted()
    return try await device.withServiceConnection(FetchSymbolsService, body)
  }

  private func indicesAndRemotePathsOfSharedCache() async throws -> [Int: String] {
    try await withSymbolServiceConnection { connection in
      let files = try Self.obtainFileListing(from: connection)
      return try Self.matchFiles(Self.matchingPathsOfSharedCache(files), againstFileIndices: files)
    }
  }

  private func indexOfSymbolFile(_ fileName: String) async throws -> Int {
    try await withSymbolServiceConnection { connection in
      let files = try Self.obtainFileListing(from: connection)
      guard let index = files.firstIndex(of: fileName) else {
        throw FBDeviceDebugSymbolsError.fileNotInListing(
          file: fileName,
          listing: FBCollectionInformation.oneLineDescription(from: files))
      }
      return index
    }
  }

  private func writeSymbolFile(index: Int, toFileAtPath destinationPath: String) async throws -> String {
    try await withSymbolServiceConnection { connection in
      try Self.getFile(index: UInt32(index), toDestinationPath: destinationPath, on: connection)
      return destinationPath
    }
  }

  // MARK: - The symbol service protocol

  private static func obtainFileListing(from connection: FBAMDServiceConnection) throws -> [String] {
    try sendCommand(ListFilesPlistCommand, withAck: ListFilesPlistAck, named: "ListFilesPlist", on: connection)
    let message: Any
    do {
      message = try connection.receiveMessage()
    } catch {
      throw FBDeviceDebugSymbolsError.listingReceiveFailed(message: String(describing: error))
    }
    let raw = (message as? [String: Any])?["files"]
    guard let files = raw as? [String] else {
      let described = (raw as? [Any]).map { FBCollectionInformation.oneLineDescription(from: $0) } ?? String(describing: raw)
      throw FBDeviceDebugSymbolsError.listingNotStrings(files: described)
    }
    return files
  }

  private static func sendCommand(
    _ command: UInt32,
    withAck ack: UInt32,
    named commandName: String,
    on connection: FBAMDServiceConnection
  ) throws {
    do {
      try connection.sendUnsignedInt32(command)
    } catch {
      throw FBDeviceDebugSymbolsError.commandSendFailed(command: commandName, message: String(describing: error))
    }
    var response: UInt32 = 0
    do {
      try connection.receiveUnsignedInt32(&response)
    } catch {
      throw FBDeviceDebugSymbolsError.commandResponseFailed(command: commandName, message: String(describing: error))
    }
    guard response == ack else {
      throw FBDeviceDebugSymbolsError.commandAckMismatch(command: commandName, received: response, expected: ack)
    }
  }

  private static func getFile(
    index: UInt32,
    toDestinationPath destinationPath: String,
    on connection: FBAMDServiceConnection
  ) throws {
    try sendCommand(GetFileCommand, withAck: GetFileAck, named: "GetFiles", on: connection)
    do {
      try connection.sendUnsignedInt32(index.bigEndian)
    } catch {
      throw FBDeviceDebugSymbolsError.fileIndexSendFailed(index: index, message: String(describing: error))
    }
    var receiveLengthWire: UInt64 = 0
    do {
      try connection.receiveUnsignedInt64(&receiveLengthWire)
    } catch {
      throw FBDeviceDebugSymbolsError.fileLengthReceiveFailed(message: String(describing: error))
    }
    guard receiveLengthWire != 0 else {
      throw FBDeviceDebugSymbolsError.fileLengthZero
    }
    guard FileManager.default.createFile(atPath: destinationPath, contents: nil) else {
      throw FBDeviceDebugSymbolsError.destinationFileNotCreated(path: destinationPath)
    }
    guard let fileHandle = FileHandle(forWritingAtPath: destinationPath) else {
      throw FBDeviceDebugSymbolsError.destinationFileNotOpened(path: destinationPath)
    }
    try connection.receive(Int(UInt64(bigEndian: receiveLengthWire)), toFile: fileHandle)
  }

  // MARK: - Locating the shared cache within the listing

  static func matchingPathsOfSharedCache(_ files: [String]) -> [String] {
    files.filter { $0.hasPrefix(SharedCachePathPrefix) && $0.contains(SharedCachePathFragment) }
  }

  static func matchFiles(_ files: [String], againstFileIndices fileIndices: [String]) throws -> [Int: String] {
    var indexToFileName: [Int: String] = [:]
    for file in files {
      guard let index = fileIndices.firstIndex(of: file) else {
        throw FBDeviceDebugSymbolsError.fileNotInListing(
          file: file,
          listing: FBCollectionInformation.oneLineDescription(from: fileIndices))
      }
      indexToFileName[index] = file
    }
    return indexToFileName
  }

  /// The shared cache is the only pulled file without an extension; the rest are its sidecars.
  static func extractSharedCachePath(fromPaths paths: [String]) throws -> String {
    guard let sharedCache = paths.first(where: { ($0 as NSString).pathExtension.isEmpty }) else {
      throw FBDeviceDebugSymbolsError.sharedCacheNotFound(
        paths: FBCollectionInformation.oneLineDescription(from: paths))
    }
    return sharedCache
  }

  // MARK: - Extracting the shared cache

  private static func extractSharedCacheFile(
    _ sharedCacheFile: String,
    toDestinationDirectory destinationDirectory: String,
    logger: any FBControlCoreLogger
  ) throws {
    let extractor = try sharedCacheExtractor()
    logger.log("Extracting shared cache at \(sharedCacheFile) to directory at \(destinationDirectory)")
    let status = extractor(sharedCacheFile, destinationDirectory) { completed, total in
      logger.log("Completed \(completed) Total \(total)")
    }
    guard status == 0 else {
      throw FBDeviceDebugSymbolsError.extractionFailed(
        sharedCache: sharedCacheFile,
        destination: destinationDirectory,
        status: status)
    }
    logger.log("Shared cache extracted to \(destinationDirectory)")
  }

  private static func sharedCacheExtractor() throws -> SharedCacheExtractor {
    let path = try pathForSharedCacheExtractor()
    guard let handle = dlopen(path, RTLD_LAZY) else {
      throw FBDeviceDebugSymbolsError.extractorNotLoaded(path: path)
    }
    let name = "dyld_shared_cache_extract_dylibs_progress"
    guard let address = FBGetSymbolFromHandleOptional(handle, name) else {
      throw FBDeviceDebugSymbolsError.extractorSymbolNotFound(name: name, path: path)
    }
    return unsafeBitCast(address, to: SharedCacheExtractor.self)
  }

  private static func pathForSharedCacheExtractor() throws -> String {
    let path = (FBXcodeConfiguration.developerDirectory as NSString)
      .appendingPathComponent("Platforms/iPhoneOS.platform/usr/lib/dsc_extractor.bundle")
    guard FileManager.default.fileExists(atPath: path) else {
      throw FBDeviceDebugSymbolsError.extractorNotFound(path: path)
    }
    return path
  }
}
