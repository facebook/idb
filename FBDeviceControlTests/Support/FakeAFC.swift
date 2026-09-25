/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import FBDeviceControl
import Foundation

/// Maps the socket descriptor a service connection reports onto the fake behind it.
///
/// `AFCCalls.Create` is handed only a socket, not a context pointer, so unlike the AMDevice fakes
/// this object cannot travel as the opaque reference — it has to be looked up.
private final class FakeAFCRegistry: @unchecked Sendable {
  static let shared = FakeAFCRegistry()

  private struct WeakEntry {
    weak var afc: FakeAFC?
  }

  private let lock = NSLock()
  // Weakly held, so registration does not keep every test's fake — and everything it strdup'd —
  // alive for the life of the process.
  private var bySocket: [Int32: WeakEntry] = [:]
  private var nextSocket: Int32 = 0x4000

  func register(_ afc: FakeAFC) -> Int32 {
    lock.lock()
    defer { lock.unlock() }
    nextSocket += 1
    bySocket[nextSocket] = WeakEntry(afc: afc)
    return nextSocket
  }

  func afc(forSocket socket: Int32) -> FakeAFC? {
    lock.lock()
    defer { lock.unlock() }
    return bySocket[socket]?.afc
  }
}

private func afc(_ connection: AFCConnection?) -> FakeAFC? {
  connection as? FakeAFC
}

/// An in-memory stand-in for the file service an AFC connection talks to.
///
/// Only the operations the device file and crash-log commands actually perform are implemented —
/// listing a directory, reading a file whole, and removing a path. Anything else answers with a
/// failure rather than a plausible-looking success, so a test needing more fails loudly.
///
/// State is unsynchronised by design: the fake device's queues are both the main queue and the
/// suites that drive it are main-actor and serialized, so every mutation and assertion happens on
/// one thread. A test that moves the fake off the main queue needs to add locking here first.
final class FakeAFC: NSObject {

  /// The remote filesystem, as paths to contents. A directory is any path others sit beneath; it
  /// needs no entry of its own.
  var files: [String: Data] = [:]

  private(set) var removedPaths: [String] = []

  /// The socket the owning service connection reports, which is how `Create` finds this object.
  private(set) var socket: Int32 = 0

  private var openDirectories: [ObjectIdentifier: [String]] = [:]
  private var openFiles: [ObjectIdentifier: (data: Data, offset: Int)] = [:]
  private var handles: [AnyObject] = []
  /// Directory entries are handed out as C strings that AFC would own; they are duplicated here and
  /// kept for the life of the fake, because a pointer into a temporary `NSString` dangles as soon
  /// as the autorelease pool drains.
  private var entryStrings: [UnsafeMutablePointer<CChar>] = []

  override init() {
    super.init()
    socket = FakeAFCRegistry.shared.register(self)
  }

  func setContents(_ contents: [String: String]) {
    files = contents.mapValues { Data($0.utf8) }
  }

  // MARK: - The remote filesystem

  fileprivate func entries(inDirectory directory: String) -> [String] {
    let prefix = directory.isEmpty || directory == "." || directory == "/" ? "" : directory + "/"
    var names: Set<String> = []
    for path in files.keys where path.hasPrefix(prefix) {
      let remainder = String(path.dropFirst(prefix.count))
      guard !remainder.isEmpty else { continue }
      names.insert(remainder.split(separator: "/").first.map(String.init) ?? remainder)
    }
    return names.sorted()
  }

  fileprivate func openDirectory(_ path: String) -> AnyObject {
    let token = NSObject()
    handles.append(token)
    // AFC ends a listing with a null entry; the empty string stands in for it here.
    openDirectories[ObjectIdentifier(token)] = entries(inDirectory: path) + [""]
    return token
  }

  fileprivate func nextEntry(_ token: AnyObject) -> String? {
    let key = ObjectIdentifier(token)
    guard var remaining = openDirectories[key], !remaining.isEmpty else {
      return nil
    }
    let next = remaining.removeFirst()
    openDirectories[key] = remaining
    return next
  }

  fileprivate func closeDirectory(_ token: AnyObject) {
    openDirectories[ObjectIdentifier(token)] = nil
  }

  fileprivate func retainedCString(_ value: String) -> UnsafeMutablePointer<CChar> {
    let copied = strdup(value)!
    entryStrings.append(copied)
    return copied
  }

  deinit {
    entryStrings.forEach { free($0) }
  }

  fileprivate func openFile(_ path: String) -> AnyObject? {
    guard let data = files[path] else {
      return nil
    }
    let token = NSObject()
    handles.append(token)
    openFiles[ObjectIdentifier(token)] = (data, 0)
    return token
  }

  fileprivate func currentOffset(_ token: AnyObject) -> Int? {
    openFiles[ObjectIdentifier(token)]?.offset
  }

  /// Mirrors lseek's whence values, which is what AFC's seek takes: 0 from the start, 1 from the
  /// current position, 2 from the end.
  fileprivate func seek(_ token: AnyObject, offset: Int, whence: UInt64) {
    guard var handle = openFiles[ObjectIdentifier(token)] else { return }
    switch whence {
    case 1:
      handle.offset += offset
    case 2:
      handle.offset = handle.data.count + offset
    default:
      handle.offset = offset
    }
    openFiles[ObjectIdentifier(token)] = handle
  }

  fileprivate func read(_ token: AnyObject, upTo count: Int) -> Data {
    guard var handle = openFiles[ObjectIdentifier(token)] else { return Data() }
    let end = min(handle.offset + count, handle.data.count)
    let slice = handle.data[handle.offset..<end]
    handle.offset = end
    openFiles[ObjectIdentifier(token)] = handle
    return Data(slice)
  }

  fileprivate func closeFile(_ token: AnyObject) {
    openFiles[ObjectIdentifier(token)] = nil
  }

  /// Recorded only on success, so an assertion on `removedPaths` distinguishes a removal that
  /// happened from one that was merely attempted.
  fileprivate func remove(_ path: String) -> Bool {
    if files.removeValue(forKey: path) != nil {
      removedPaths.append(path)
      return true
    }
    // Removing a directory takes everything beneath it.
    let prefix = path + "/"
    let beneath = files.keys.filter { $0.hasPrefix(prefix) }
    guard !beneath.isEmpty else {
      return false
    }
    beneath.forEach { files.removeValue(forKey: $0) }
    removedPaths.append(path)
    return true
  }

  // MARK: - The call table

  var calls: AFCCalls {
    var calls = AFCCalls()

    calls.Create = { _, socket, _, _, _ in
      guard let found = FakeAFCRegistry.shared.afc(forSocket: socket) else {
        return nil
      }
      // The registry keeps this alive regardless; the retain balances whatever the connection
      // teardown releases.
      return Unmanaged.passRetained(found as AnyObject)
    }
    calls.ConnectionIsValid = { _ in 1 }
    calls.ConnectionOpen = { _, _, _ in 0 }
    calls.ConnectionClose = { _ in 0 }
    calls.SetSecureContext = { _, _ in }
    calls.ConnectionProcessOperation = { _, _ in 0 }
    calls.ConnectionCopyLastErrorInfo = { _ in
      Unmanaged.passRetained(NSDictionary() as CFDictionary)
    }

    calls.DirectoryOpen = { connection, path, directoryOut in
      guard let fake = afc(connection), let path, let directoryOut else {
        return 1
      }
      let directory = String(cString: path)
      // Only a directory that exists, or the root, can be opened.
      let isRoot = directory.isEmpty || directory == "." || directory == "/"
      guard isRoot || !fake.entries(inDirectory: directory).isEmpty else {
        return 1
      }
      directoryOut.pointee = Unmanaged.passRetained(fake.openDirectory(directory) as CFTypeRef)
      return 0
    }
    calls.DirectoryRead = { connection, directory, entryOut in
      guard let fake = afc(connection), let entryOut else {
        return 1
      }
      guard let next = fake.nextEntry(directory as AnyObject), !next.isEmpty else {
        // A null entry is how AFC signals the end of the listing.
        entryOut.pointee = nil
        return 0
      }
      entryOut.pointee = fake.retainedCString(next)
      return 0
    }
    calls.DirectoryClose = { connection, directory in
      afc(connection)?.closeDirectory(directory as AnyObject)
      return 0
    }

    calls.FileRefOpen = { connection, path, _, refOut in
      guard let fake = afc(connection), let token = fake.openFile(String(cString: path)) else {
        return 1
      }
      refOut.pointee = Unmanaged.passRetained(token as CFTypeRef)
      return 0
    }
    calls.FileRefSeek = { connection, ref, offset, whence in
      afc(connection)?.seek(ref as AnyObject, offset: Int(offset), whence: whence)
      return 0
    }
    calls.FileRefTell = { connection, ref, offsetOut in
      guard let fake = afc(connection), let offset = fake.currentOffset(ref as AnyObject) else {
        return 1
      }
      offsetOut.pointee = UInt64(offset)
      return 0
    }
    calls.FileRefRead = { connection, ref, buffer, length in
      guard let fake = afc(connection) else {
        return 1
      }
      let data = fake.read(ref as AnyObject, upTo: Int(length.pointee))
      data.withUnsafeBytes { source in
        guard let base = source.baseAddress else { return }
        buffer.copyMemory(from: base, byteCount: data.count)
      }
      length.pointee = UInt64(data.count)
      return 0
    }
    calls.FileRefClose = { connection, ref in
      afc(connection)?.closeFile(ref as AnyObject)
      return 0
    }

    // Writing and renaming are not part of what the crash-log and file commands exercise here, so
    // they report a failure rather than a plausible success. Operations answer as no-ops, which is
    // enough for the recursive-remove path to complete.
    calls.DirectoryCreate = { _, _ in 0 }
    calls.FileRefWrite = { _, _, _, _ in 1 }
    calls.RenamePath = { _, _, _ in 1 }
    calls.OperationGetResultStatus = { _ in 0 }
    calls.OperationCreateRemovePathAndContents = { _, path, _ in
      Unmanaged.passRetained((path as String? ?? "") as CFTypeRef)
    }
    calls.OperationGetResultObject = { _ in nil }
    // strdup'd rather than borrowed from a temporary: AFC owns this string, and a pointer into an
    // autoreleased `NSString` dangles the moment the pool drains.
    calls.ErrorString = { _ in strdup("fake AFC error") }

    calls.RemovePath = { connection, path in
      guard let fake = afc(connection), fake.remove(String(cString: path)) else {
        return 1
      }
      return 0
    }

    return calls
  }
}
