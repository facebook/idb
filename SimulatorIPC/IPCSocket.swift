/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Darwin
import Foundation

public enum IPCSocket {
  public static let pathCapacity = MemoryLayout.size(ofValue: sockaddr_un().sun_path)
  public static let ownerOnlyPermissions = 0o700

  public static func connect(path: String, timeoutSeconds: Int) throws -> Int32? {
    var address = try self.address(path: path)
    let fileDescriptor = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fileDescriptor >= 0 else { return nil }
    let connected = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.connect(fileDescriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
    guard connected == 0 else {
      close(fileDescriptor)
      return nil
    }
    var noSigPipe: Int32 = 1
    setsockopt(fileDescriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
    setTimeout(fileDescriptor, seconds: timeoutSeconds)
    return fileDescriptor
  }

  public static func setTimeout(_ fileDescriptor: Int32, seconds: Int) {
    var timeout = timeval(tv_sec: seconds, tv_usec: 0)
    setsockopt(fileDescriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    setsockopt(fileDescriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
  }

  public static func writeFrame(_ fileDescriptor: Int32, _ payload: Data) throws {
    try writeAll(fileDescriptor, IPCFrame.header(forSize: payload.count))
    try writeAll(fileDescriptor, payload)
  }

  public static func readFrame(_ fileDescriptor: Int32) throws -> Data {
    let length = try IPCFrame.size(fromHeader: readAll(fileDescriptor, count: 4))
    return try readAll(fileDescriptor, count: length)
  }

  public static func prepareDirectory(_ path: String) throws {
    let manager = FileManager.default
    try manager.createDirectory(
      atPath: path,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: ownerOnlyPermissions]
    )
    try manager.setAttributes([.posixPermissions: ownerOnlyPermissions], ofItemAtPath: path)
  }

  static func address(path: String) throws -> sockaddr_un {
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8)
    guard bytes.count < pathCapacity else { throw IPCError.pathTooLong(path: path, limit: pathCapacity) }
    withUnsafeMutableBytes(of: &address.sun_path) {
      $0.copyBytes(from: bytes)
      $0[bytes.count] = 0
    }
    return address
  }

  private static func writeAll(_ fileDescriptor: Int32, _ data: Data) throws {
    try data.withUnsafeBytes { buffer in
      guard let base = buffer.baseAddress else { return }
      var offset = 0
      while offset < buffer.count {
        let written = send(fileDescriptor, base + offset, buffer.count - offset, MSG_NOSIGNAL)
        if written < 0 {
          if errno == EINTR { continue }
          throw IPCError.failed(operation: "write", errno: errno)
        }
        guard written > 0 else { throw IPCError.closed }
        offset += written
      }
    }
  }

  private static func readAll(_ fileDescriptor: Int32, count: Int) throws -> Data {
    var data = Data(count: count)
    try data.withUnsafeMutableBytes { buffer in
      guard let base = buffer.baseAddress else { return }
      var offset = 0
      while offset < count {
        let received = recv(fileDescriptor, base + offset, count - offset, 0)
        if received < 0 {
          if errno == EINTR { continue }
          if errno == EAGAIN || errno == EWOULDBLOCK { throw IPCError.timedOut }
          throw IPCError.failed(operation: "read", errno: errno)
        }
        guard received > 0 else { throw IPCError.closed }
        offset += received
      }
    }
    return data
  }
}

public final class IPCListener {
  public let fileDescriptor: Int32
  private let lockFileDescriptor: Int32
  private let path: String

  public static func bind(path: String, backlog: Int32) throws -> IPCListener? {
    var address = try IPCSocket.address(path: path)
    let fileDescriptor = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fileDescriptor >= 0 else { throw IPCError.failed(operation: "socket", errno: errno) }
    // Keep the inode stable: unlinking a lock file lets another starter lock a different inode.
    let lockFileDescriptor = open(path + ".lock", O_CREAT | O_RDWR | O_NOFOLLOW, mode_t(0o600))
    guard lockFileDescriptor >= 0 else {
      let error = IPCError.failed(operation: "open lock", errno: errno)
      close(fileDescriptor)
      throw error
    }
    guard flock(lockFileDescriptor, LOCK_EX | LOCK_NB) == 0 else {
      let contended = errno == EWOULDBLOCK
      let error = IPCError.failed(operation: "lock", errno: errno)
      close(lockFileDescriptor)
      close(fileDescriptor)
      if contended { return nil }
      throw error
    }
    unlink(path)
    let bound = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.bind(fileDescriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
    guard bound == 0, listen(fileDescriptor, backlog) == 0 else {
      let error = IPCError.failed(operation: bound == 0 ? "listen" : "bind", errno: errno)
      if bound == 0 { unlink(path) }
      close(lockFileDescriptor)
      close(fileDescriptor)
      throw error
    }
    return IPCListener(fileDescriptor: fileDescriptor, lockFileDescriptor: lockFileDescriptor, path: path)
  }

  private init(fileDescriptor: Int32, lockFileDescriptor: Int32, path: String) {
    self.fileDescriptor = fileDescriptor
    self.lockFileDescriptor = lockFileDescriptor
    self.path = path
  }

  deinit {
    unlink(path)
    close(lockFileDescriptor)
    close(fileDescriptor)
  }
}
