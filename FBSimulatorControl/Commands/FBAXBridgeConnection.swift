/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Darwin
@preconcurrency import FBControlCore
import Foundation

// SAFETY: the subprocess handle is retained for diagnostics and only queried through thread-safe futures.
enum FBAXBridgeGuestOwnership: @unchecked Sendable {
  case privateToThisHost(FBSubprocess<AnyObject, AnyObject, AnyObject>)
  case shared(FBSubprocess<AnyObject, AnyObject, AnyObject>?)

  var process: FBSubprocess<AnyObject, AnyObject, AnyObject>? {
    switch self {
    case let .privateToThisHost(process): process
    case let .shared(process): process
    }
  }

  var isPrivate: Bool {
    switch self {
    case .privateToThisHost: true
    case .shared: false
    }
  }
}

/// A serialized connection to a guest serving length-prefixed JSON over a Unix socket.
// SAFETY: stored state is immutable and all socket I/O runs on `queue`.
// patternlint-disable-next-line unchecked-sendable
final class FBAXBridgeConnection: @unchecked Sendable {
  private let fileDescriptor: Int32
  private let ownership: FBAXBridgeGuestOwnership
  private let queue = DispatchQueue(label: "com.facebook.FBSimulatorControl.axbridge.connection")

  /// The per-`recv` silence deadline, rather than a deadline for the whole response.
  static let receiveTimeoutSeconds = 30
  static let sunPathCapacity = MemoryLayout.size(ofValue: sockaddr_un().sun_path)

  var mayBeHeldBetweenRoundTrips: Bool {
    ownership.isPrivate
  }

  init(fileDescriptor: Int32, ownership: FBAXBridgeGuestOwnership) {
    self.fileDescriptor = fileDescriptor
    self.ownership = ownership
  }

  deinit {
    close(fileDescriptor)
  }

  func roundTrip(_ requestData: Data) async throws -> Data {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
      queue.async { [fileDescriptor, ownership] in
        do {
          try FBAXBridgeConnection.writeFrame(fileDescriptor, requestData)
          let responseData = try FBAXBridgeConnection.readFrame(fileDescriptor, guest: ownership.process)
          continuation.resume(returning: responseData)
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  static func connect(path: String, timeout: TimeInterval) async throws -> Int32 {
    guard path.utf8.count < sunPathCapacity else {
      throw FBAXBridgeError.socketPathTooLong(path: path, limit: sunPathCapacity)
    }
    return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int32, Error>) in
      DispatchQueue.global().async {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
          let fileDescriptor = socket(AF_UNIX, SOCK_STREAM, 0)
          if fileDescriptor >= 0 {
            if connectSocket(fileDescriptor, toPath: path) {
              var noSigPipe: Int32 = 1
              setsockopt(fileDescriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
              var readTimeout = timeval(tv_sec: receiveTimeoutSeconds, tv_usec: 0)
              setsockopt(fileDescriptor, SOL_SOCKET, SO_RCVTIMEO, &readTimeout, socklen_t(MemoryLayout<timeval>.size))
              continuation.resume(returning: fileDescriptor)
              return
            }
            close(fileDescriptor)
          }
          usleep(100_000)
        } while Date() < deadline
        continuation.resume(throwing: FBAXBridgeError.guestFailure("timed out connecting to the serve socket at \(path)"))
      }
    }
  }

  private static func connectSocket(_ fileDescriptor: Int32, toPath path: String) -> Bool {
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let capacity = MemoryLayout.size(ofValue: address.sun_path)
    let copied = path.withCString { source -> Bool in
      let length = strlen(source)
      guard length < capacity else { return false }
      withUnsafeMutablePointer(to: &address.sun_path) { pointer in
        pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { destination in
          _ = memcpy(destination, source, length + 1)
        }
      }
      return true
    }
    guard copied else { return false }
    let result = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.connect(fileDescriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
    return result == 0
  }

  static func writeFrame(_ fileDescriptor: Int32, _ payload: Data) throws {
    try writeAll(fileDescriptor, encodeLength(payload.count))
    try writeAll(fileDescriptor, payload)
  }

  static func readFrame(
    _ fileDescriptor: Int32,
    guest: FBSubprocess<AnyObject, AnyObject, AnyObject>?
  ) throws -> Data {
    let header = try readAll(fileDescriptor, count: 4, guest: guest)
    let length = decodeLength(header)
    guard length > 0, length < 16 * 1024 * 1024 else {
      throw FBAXBridgeError.guestFailure("invalid response frame length \(length)")
    }
    return try readAll(fileDescriptor, count: length, guest: guest)
  }

  private static func encodeLength(_ count: Int) -> Data {
    let value = UInt32(count)
    return Data([
      UInt8((value >> 24) & 0xff), UInt8((value >> 16) & 0xff), UInt8((value >> 8) & 0xff), UInt8(value & 0xff),
    ])
  }

  private static func decodeLength(_ data: Data) -> Int {
    let bytes = [UInt8](data)
    return (Int(bytes[0]) << 24) | (Int(bytes[1]) << 16) | (Int(bytes[2]) << 8) | Int(bytes[3])
  }

  private static func writeAll(_ fileDescriptor: Int32, _ data: Data) throws {
    try data.withUnsafeBytes { raw in
      guard let base = raw.baseAddress else { return }
      var offset = 0
      while offset < raw.count {
        let written = send(fileDescriptor, base + offset, raw.count - offset, 0)
        if written < 0 {
          if errno == EINTR { continue }
          throw FBAXBridgeError.guestFailure("socket write failed: \(String(cString: strerror(errno)))")
        }
        if written == 0 {
          throw FBAXBridgeError.guestFailure("socket write returned 0")
        }
        offset += written
      }
    }
  }

  static func socketClosedMessage(process: FBSubprocess<AnyObject, AnyObject, AnyObject>?) -> String {
    guard let process else {
      return socketClosedMessage(pid: nil, signal: nil, exitCode: nil)
    }
    return socketClosedMessage(
      pid: process.processIdentifier,
      signal: process.signal.hasCompleted ? process.signal.result?.intValue : nil,
      exitCode: process.exitCode.hasCompleted ? process.exitCode.result?.intValue : nil
    )
  }

  static func socketClosedMessage(pid: pid_t?, signal: Int?, exitCode: Int?) -> String {
    let base = "serve socket closed by peer"
    guard let pid else {
      return base
    }
    if let signal, signal != 0 {
      return "\(base): the guest (pid \(pid)) was killed by signal \(signal)"
    }
    if let exitCode {
      return "\(base): the guest (pid \(pid)) exited with code \(exitCode)"
    }
    return "\(base): the guest (pid \(pid)) is gone, with no exit status recorded"
  }

  private static func readAll(
    _ fileDescriptor: Int32,
    count: Int,
    guest: FBSubprocess<AnyObject, AnyObject, AnyObject>?
  ) throws -> Data {
    var buffer = Data(count: count)
    try buffer.withUnsafeMutableBytes { raw in
      guard let base = raw.baseAddress else { return }
      var offset = 0
      while offset < count {
        let received = recv(fileDescriptor, base + offset, count - offset, 0)
        if received < 0 {
          if errno == EINTR { continue }
          if errno == EAGAIN || errno == EWOULDBLOCK {
            throw FBAXBridgeError.guestFailure("serve read timed out after \(receiveTimeoutSeconds)s with no data")
          }
          throw FBAXBridgeError.guestFailure("socket read failed: \(String(cString: strerror(errno)))")
        }
        if received == 0 {
          throw FBAXBridgeError.guestFailure(FBAXBridgeConnection.socketClosedMessage(process: guest))
        }
        offset += received
      }
    }
    return buffer
  }
}
