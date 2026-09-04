/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation

private let AFCCodeKey = "AFCCode"
private let AFCDomainKey = "AFCDomain"

/// The entries AFC itself inserts into every directory listing.
private let SingleDot = "."
private let DoubleDot = ".."

private func afcConnectionCallback(
  _ connectionRefPtr: UnsafeMutableRawPointer?,
  _ arg1: UnsafeMutableRawPointer?,
  _ afcOperationPtr: UnsafeMutableRawPointer?
) {
  let logger = FBControlCoreGlobalConfiguration.defaultLogger
  logger.log("Connection \(String(describing: connectionRefPtr)), operation \(String(describing: afcOperationPtr))")
}

/// The ways an AFC exchange can fail, as data rather than assembled strings.
public enum FBAFCConnectionError: Error {
  case createDirectoryFailed(message: String)
  case openDirectoryFailed(path: String, message: String)
  case openFileFailed(path: String, message: String)
  case readFileFailed(path: String, message: String)
  case writeFileFailed(path: String, message: String)
  case removePathFailed(path: String, message: String)
  case renamePathFailed(path: String, destination: String, message: String)
  case pathNotEncodable(path: String)
  case pathOrDestinationNotEncodable(path: String, destination: String)
  case containerPathNotEncodable(path: String)
  case hostFileMissing(path: String)
  case noConnectionToClose
  case closeFailed(status: Int32)
  case connectionNotValid(description: String)
  case removalOperationNotCreated(path: String)
  case operationNotProcessed(status: Int32)
  case operationFailed(status: Int32, resultObject: String)
  case operationFailedWithUnderlying(info: String, code: Int)
}

extension FBAFCConnectionError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case let .createDirectoryFailed(message):
      return "Error when creating directory: \(message)"
    case let .openDirectoryFailed(path, message):
      return "Error when opening directory \(path): \(message)"
    case let .openFileFailed(path, message):
      return "Error when opening file \(path): \(message)"
    case let .readFileFailed(path, message):
      return "Error when reading file \(path): \(message)"
    case let .writeFileFailed(path, message):
      return "Error when writing file \(path): \(message)"
    case let .removePathFailed(path, message):
      return "Error when removing path \(path): \(message)"
    case let .renamePathFailed(path, destination, message):
      return "Error when renaming from \(path) to \(destination): \(message)"
    case let .pathNotEncodable(path):
      return "Could not encode path \(path) as UTF-8"
    case let .pathOrDestinationNotEncodable(path, destination):
      return "Could not encode path \(path) or destination \(destination) as UTF-8"
    case let .containerPathNotEncodable(path):
      return "Could not encode container path \(path) as UTF-8"
    case let .hostFileMissing(path):
      return "Could not find file on host: \(path)"
    case .noConnectionToClose:
      return "Cannot close a non-existant connection"
    case let .closeFailed(status):
      return "Failed to close connection with error \(status)"
    case let .connectionNotValid(description):
      return "Created AFC Connection \(description) is not valid"
    case let .removalOperationNotCreated(path):
      return "Operation for path removal \(path) couldn't be created"
    case let .operationNotProcessed(status):
      return "Operation couldn't be processed (\(status))"
    case let .operationFailed(status, resultObject):
      return "AFCOperation failed. status: \(status), result object: \(resultObject)"
    case let .operationFailedWithUnderlying(info, _):
      return "AFCOperation failed. underlying error: \(info)"
    }
  }
}

/// An Object-Wrapper around AFCConnectionRef.
public final class FBAFCConnection {

  // MARK: - Properties

  public let calls: AFCCalls
  public let logger: (any FBControlCoreLogger)?

  /// Held unretained. Unlike the service connection, `AFCConnectionClose` does release it, so
  /// closing nils this out without a release of its own.
  private var connectionRef: Unmanaged<AnyObject>?

  public var connection: AFCConnection? {
    connectionRef?.takeUnretainedValue()
  }

  // MARK: - Initializers

  public init(connection: AFCConnection?, calls: AFCCalls, logger: (any FBControlCoreLogger)?) {
    self.connectionRef = connection.map { Unmanaged.passUnretained($0 as AnyObject) }
    self.calls = calls
    self.logger = logger
  }

  /// Wraps a service connection in an AFC client, which the caller then owns and must close.
  static func afc(
    from serviceConnection: FBAMDServiceConnection,
    calls: AFCCalls,
    logger: any FBControlCoreLogger
  ) throws -> FBAFCConnection {
    let connection = serviceConnection.asAFCConnection(
      calls: calls, callback: afcConnectionCallback, logger: logger)
    guard connection.connectionIsValid else {
      throw FBAFCConnectionError.connectionNotValid(description: String(describing: connection))
    }
    return connection
  }

  // MARK: - Public

  public func copy(fromHost hostPath: String, toContainerPath containerPath: String) throws {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: hostPath, isDirectory: &isDirectory) else {
      throw FBAFCConnectionError.hostFileMissing(path: hostPath)
    }
    let lastComponent = (hostPath as NSString).lastPathComponent
    if isDirectory.boolValue {
      let nested = (containerPath as NSString).appendingPathComponent(lastComponent)
      try createDirectory(nested)
      try copyContents(ofHostDirectory: hostPath, toContainerPath: nested)
    } else {
      try copyFile(
        fromHost: hostPath,
        toContainerPath: (containerPath as NSString).appendingPathComponent(lastComponent))
    }
  }

  public func createDirectory(_ path: String) throws {
    logger?.log("Creating Directory \(path)")
    let result = calls.DirectoryCreate(connection, path)
    guard result == 0 else {
      throw FBAFCConnectionError.createDirectoryFailed(message: errorMessage(code: result))
    }
    logger?.log("Created Directory \(path)")
  }

  public func contents(ofDirectory path: String) throws -> [String] {
    logger?.log("Listing contents of directory \(path)")
    var directory: Unmanaged<CFTypeRef>?
    let result = calls.DirectoryOpen(connection, path, &directory)
    guard result == 0 else {
      throw FBAFCConnectionError.openDirectoryFailed(path: path, message: errorMessage(code: result))
    }
    let directoryRef = directory?.takeUnretainedValue()

    var entries: [String] = []
    while true {
      var listing: UnsafeMutablePointer<CChar>?
      _ = calls.DirectoryRead(connection, directoryRef, &listing)
      guard let listing else {
        break
      }
      let entry = String(cString: listing)
      if entry == SingleDot || entry == DoubleDot {
        continue
      }
      entries.append(entry)
    }

    _ = calls.DirectoryClose(connection, directoryRef)
    logger?.log("Contents of directory \(path) \(FBCollectionInformation.oneLineDescription(from: entries))")
    return entries
  }

  public func contents(ofPath path: String) throws -> Data {
    logger?.log("Contents of path \(path)")
    var file: Unmanaged<CFTypeRef>?
    let result = calls.FileRefOpen(connection, path, FBAFCReadOnlyMode, &file)
    guard result == 0 else {
      throw FBAFCConnectionError.openFileFailed(path: path, message: errorMessage(code: result))
    }
    let fileRef = file?.takeUnretainedValue()

    // Seek to the end to discover the length, then back to the start to read it.
    _ = calls.FileRefSeek(connection, fileRef, 0, 2)
    var offset: UInt64 = 0
    _ = calls.FileRefTell(connection, fileRef, &offset)
    _ = calls.FileRefSeek(connection, fileRef, 0, 0)

    let length = Int(offset)
    var buffer = Data(count: length)
    var readResult: Int32 = 0
    buffer.withUnsafeMutableBytes { destination in
      guard let base = destination.baseAddress else {
        return
      }
      var toRead = offset
      while toRead > 0 {
        var read = toRead
        readResult = calls.FileRefRead(connection, fileRef, base.advanced(by: length - Int(toRead)), &read)
        toRead -= read
        if readResult != 0 {
          return
        }
      }
    }
    _ = calls.FileRefClose(connection, fileRef)
    guard readResult == 0 else {
      throw FBAFCConnectionError.readFileFailed(path: path, message: errorMessage(code: readResult))
    }
    logger?.log("Read \(buffer.count) bytes from path \(path)")
    return buffer
  }

  func removePath(_ path: String, recursively: Bool) throws {
    if recursively {
      try removePathAndContents(path)
      return
    }
    logger?.log("Removing file path \(path)")
    let result = calls.RemovePath(connection, path)
    guard result == 0 else {
      throw FBAFCConnectionError.removePathFailed(path: path, message: errorMessage(code: result))
    }
    logger?.log("Removed file path \(path)")
  }

  func renamePath(_ path: String, destination: String) throws {
    let result = calls.RenamePath(connection, path, destination)
    guard result == 0 else {
      throw FBAFCConnectionError.renamePathFailed(
        path: path, destination: destination, message: errorMessage(code: result))
    }
  }

  public func close() throws {
    guard let connectionRef else {
      throw FBAFCConnectionError.noConnectionToClose
    }
    let reference = connectionRef.takeUnretainedValue()
    let connectionDescription = CFCopyDescription(reference) as String? ?? "unknown"
    logger?.log("Closing \(connectionDescription)")
    let status = calls.ConnectionClose(reference)
    guard status == 0 else {
      throw FBAFCConnectionError.closeFailed(status: status)
    }
    logger?.log("Closed AFC Connection \(connectionDescription)")
    // AFCConnectionClose does release the connection.
    self.connectionRef = nil
  }

  var connectionIsValid: Bool {
    calls.ConnectionIsValid(connection) != 0
  }

  // MARK: - AFC Calls

  public static let defaultCalls: AFCCalls = {
    var calls = AFCCalls()
    // `Bundle(identifier:)` answers for a bundle that has not been loaded, and asking such a
    // bundle for its executable path asserts. Reading this before the private frameworks are up is
    // then fatal rather than empty, so the loaded check comes first.
    guard let bundle = Bundle(identifier: "com.apple.mobiledevice"), bundle.isLoaded else {
      return calls
    }
    let handle = bundle.dlopenExecutablePath()
    calls.ConnectionClose = symbol(handle, "AFCConnectionClose")
    calls.ConnectionCopyLastErrorInfo = symbol(handle, "AFCConnectionCopyLastErrorInfo")
    calls.ConnectionIsValid = symbol(handle, "AFCConnectionIsValid")
    calls.ConnectionOpen = symbol(handle, "AFCConnectionOpen")
    calls.ConnectionProcessOperation = symbol(handle, "AFCConnectionProcessOperation")
    calls.Create = symbol(handle, "AFCConnectionCreate")
    calls.DirectoryClose = symbol(handle, "AFCDirectoryClose")
    calls.DirectoryCreate = symbol(handle, "AFCDirectoryCreate")
    calls.DirectoryOpen = symbol(handle, "AFCDirectoryOpen")
    calls.DirectoryRead = symbol(handle, "AFCDirectoryRead")
    calls.ErrorString = symbol(handle, "AFCErrorString")
    calls.FileRefClose = symbol(handle, "AFCFileRefClose")
    calls.FileRefOpen = symbol(handle, "AFCFileRefOpen")
    calls.FileRefRead = symbol(handle, "AFCFileRefRead")
    calls.FileRefSeek = symbol(handle, "AFCFileRefSeek")
    calls.FileRefTell = symbol(handle, "AFCFileRefTell")
    calls.FileRefWrite = symbol(handle, "AFCFileRefWrite")
    calls.OperationCreateRemovePathAndContents = symbol(handle, "AFCOperationCreateRemovePathAndContents")
    calls.OperationGetResultObject = symbol(handle, "AFCOperationGetResultObject")
    calls.OperationGetResultStatus = symbol(handle, "AFCOperationGetResultStatus")
    calls.RemovePath = symbol(handle, "AFCRemovePath")
    calls.RenamePath = symbol(handle, "AFCRenamePath")
    calls.SetSecureContext = symbol(handle, "AFCConnectionSetSecureContext")
    return calls
  }()

  // MARK: - Private

  private func copyFile(fromHost hostPath: String, toContainerPath containerPath: String) throws {
    logger?.log("Copying \(hostPath) to \(containerPath)")
    guard let data = FileManager.default.contents(atPath: hostPath) else {
      throw FBAFCConnectionError.hostFileMissing(path: hostPath)
    }
    var fileReference: Unmanaged<CFTypeRef>?
    let result = calls.FileRefOpen(connection, containerPath, FBAFCreateReadAndWrite, &fileReference)
    guard result == 0 else {
      throw FBAFCConnectionError.openFileFailed(path: containerPath, message: errorMessage(code: result))
    }
    let fileRef = fileReference?.takeUnretainedValue()

    // Written region by region with an early stop: flattening a non-contiguous Data first would
    // materialize the whole file in memory.
    var writeResult: Int32 = 0
    for region in data.regions where !region.isEmpty {
      region.withUnsafeBytes { bytes in
        guard let base = bytes.baseAddress else {
          return
        }
        writeResult = calls.FileRefWrite(connection, fileRef, base, UInt64(bytes.count))
      }
      if writeResult != 0 {
        break
      }
    }
    _ = calls.FileRefClose(connection, fileRef)
    guard writeResult == 0 else {
      throw FBAFCConnectionError.writeFileFailed(path: containerPath, message: errorMessage(code: writeResult))
    }
    logger?.log("Copied from \(hostPath) to \(containerPath)")
  }

  private func copyContents(ofHostDirectory hostDirectory: String, toContainerPath containerPath: String) throws {
    logger?.log("Copying from \(hostDirectory) to \(containerPath)")
    let urls = FileManager.default.enumerator(
      at: URL(fileURLWithPath: hostDirectory),
      includingPropertiesForKeys: [.isDirectoryKey],
      options: .skipsSubdirectoryDescendants)
    // Bound in two steps: folding the cast into the loop condition would end the traversal
    // silently at the first non-URL element, while still logging the copy as complete.
    while let next = urls?.nextObject() {
      guard let url = next as? URL else {
        continue
      }
      do {
        try copy(fromHost: url.path, toContainerPath: containerPath)
      } catch {
        logger?.log("Failed to copy \(url) to \(containerPath) with error \(error)")
        throw error
      }
    }
    logger?.log("Copied from \(hostDirectory) to \(containerPath)")
  }

  private func removePathAndContents(_ path: String) throws {
    logger?.log("Removing path \(path) and contents")
    guard
      let operation = calls.OperationCreateRemovePathAndContents(
        CFGetAllocator(connection), path as CFString, nil)?.takeRetainedValue()
    else {
      throw FBAFCConnectionError.removalOperationNotCreated(path: path)
    }
    let processResult = calls.ConnectionProcessOperation(connection, operation)
    guard processResult == 0 else {
      throw FBAFCConnectionError.operationNotProcessed(status: processResult)
    }
    try checkOperationSucceeded(operation)
  }

  private func checkOperationSucceeded(_ operation: CFTypeRef) throws {
    let status = calls.OperationGetResultStatus(operation)
    if status == 0 {
      return
    }
    let resultObject = calls.OperationGetResultObject(operation)?.takeUnretainedValue()
    guard let info = resultObject as? [String: Any] else {
      throw FBAFCConnectionError.operationFailed(status: status, resultObject: String(describing: resultObject))
    }
    guard let code = info[AFCCodeKey] as? NSNumber, info[AFCDomainKey] is String else {
      throw FBAFCConnectionError.operationFailed(status: status, resultObject: String(describing: info))
    }
    throw FBAFCConnectionError.operationFailedWithUnderlying(
      info: String(describing: info), code: code.intValue)
  }

  private func errorMessage(code: Int32) -> String {
    let name = calls.ErrorString(code).map { String(cString: $0) } ?? ""
    let info = calls.ConnectionCopyLastErrorInfo(connection)?.takeRetainedValue() as? [String: Any] ?? [:]
    return "\(name) \(FBCollectionInformation.oneLineDescription(from: info))"
  }
}

/// Reinterprets a `dlsym` result as the function pointer the call table expects.
private func symbol<T>(_ handle: UnsafeMutableRawPointer, _ name: String) -> T {
  unsafeBitCast(FBGetSymbolFromHandle(handle, name), to: T.self)
}
