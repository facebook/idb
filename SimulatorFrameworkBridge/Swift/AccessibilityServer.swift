/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Darwin
import Foundation

@objc public final class FBAXBridgeSocketResponse: NSObject {
  @objc public let data: Data
  @objc public let shutdown: Bool

  @objc public init(data: Data, shutdown: Bool) {
    self.data = data
    self.shutdown = shutdown
    super.init()
  }
}

@objc public final class FBAXBridgeServer: NSObject {
  @objc public static let defaultIdleTimeoutSeconds: Int32 = 300
  @objc public static let serveBacklog: Int32 = 16
  private static let maxFrameBytes: UInt32 = 16 * 1024 * 1024

  /// Runs synchronously; runtime preparation and request handling stay on the caller's thread.
  @objc public static func serve(
    socketPath: String,
    idleTimeoutSeconds: Int32,
    exitOnDisconnect: Bool,
    prepareRuntime: () -> Void,
    handleRequest: (Data) -> FBAXBridgeSocketResponse
  ) -> Int32 {
    let pathString = socketPath as NSString
    return withExtendedLifetime(pathString) {
      let path = pathString.fileSystemRepresentation
      let listenFD = socket(AF_UNIX, SOCK_STREAM, 0)
      guard listenFD >= 0 else {
        NSLog("[AccessibilityService] socket() failed: %@", String(cString: strerror(errno)))
        return 1
      }
      defer { close(listenFD) }

      var address = sockaddr_un()
      address.sun_family = sa_family_t(AF_UNIX)
      let pathLength = strlen(path)
      guard pathLength < MemoryLayout.size(ofValue: address.sun_path) else {
        NSLog("[AccessibilityService] socket path too long: %@", socketPath)
        return 1
      }
      withUnsafeMutableBytes(of: &address.sun_path) {
        $0.copyBytes(from: UnsafeRawBufferPointer(start: path, count: pathLength + 1))
      }
      unlink(path)
      let bound = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
          bind(listenFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
      }
      guard bound == 0 else {
        NSLog("[AccessibilityService] bind(%@) failed: %@", socketPath, String(cString: strerror(errno)))
        return 1
      }
      guard listen(listenFD, serveBacklog) == 0 else {
        NSLog("[AccessibilityService] listen() failed: %@", String(cString: strerror(errno)))
        return 1
      }
      defer { unlink(path) }

      prepareRuntime()
      NSLog("[AccessibilityService] serving accessibility on %@ (idle timeout %ds)", socketPath, idleTimeoutSeconds)
      while true {
        var listener = pollfd(fd: listenFD, events: Int16(POLLIN), revents: 0)
        let ready = poll(&listener, 1, idleTimeoutSeconds &* 1000)
        if ready == 0 {
          NSLog("[AccessibilityService] idle %ds with no client; exiting", idleTimeoutSeconds)
          break
        }
        if ready < 0 {
          if errno == EINTR { continue }
          break
        }
        let connection = accept(listenFD, nil, nil)
        if connection < 0 {
          if errno == EINTR { continue }
          break
        }
        let shutdown = serveConnection(connection, idleTimeoutSeconds: idleTimeoutSeconds, handleRequest: handleRequest)
        close(connection)
        if exitOnDisconnect {
          NSLog("[AccessibilityService] exclusive client disconnected; exiting")
          break
        }
        if shutdown {
          NSLog("[AccessibilityService] shutdown requested by client; exiting")
          break
        }
      }
      return 0
    }
  }

  private enum ConnectionStep {
    case next, disconnected, shutdown
  }

  private static func serveConnection(
    _ connection: Int32,
    idleTimeoutSeconds: Int32,
    handleRequest: (Data) -> FBAXBridgeSocketResponse
  ) -> Bool {
    var timeout = timeval(tv_sec: Int(idleTimeoutSeconds), tv_usec: 0)
    setsockopt(connection, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    while true {
      let step: ConnectionStep = autoreleasepool {
        guard let header = readFully(connection, count: 4) else { return .disconnected }
        let length = header.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard length > 0, length <= maxFrameBytes,
          let request = readFully(connection, count: Int(length))
        else { return .disconnected }
        let response = handleRequest(request)
        var responseLength = UInt32(truncatingIfNeeded: response.data.count).bigEndian
        let responseHeader = withUnsafeBytes(of: &responseLength) { Data($0) }
        guard writeFully(connection, data: responseHeader), writeFully(connection, data: response.data) else { return .disconnected }
        return response.shutdown ? .shutdown : .next
      }
      switch step {
      case .next: continue
      case .disconnected: return false
      case .shutdown: return true
      }
    }
  }

  private static func readFully(_ fd: Int32, count: Int) -> Data? {
    var data = Data(count: count)
    let complete = data.withUnsafeMutableBytes { buffer -> Bool in
      guard let base = buffer.baseAddress else { return false }
      var offset = 0
      while offset < count {
        let received = recv(fd, base.advanced(by: offset), count - offset, 0)
        if received < 0, errno == EINTR { continue }
        guard received > 0 else { return false }
        offset += received
      }
      return true
    }
    return complete ? data : nil
  }

  private static func writeFully(_ fd: Int32, data: Data) -> Bool {
    if data.isEmpty { return true }
    return data.withUnsafeBytes { buffer in
      guard let base = buffer.baseAddress else { return false }
      var offset = 0
      while offset < buffer.count {
        let written = send(fd, base.advanced(by: offset), buffer.count - offset, MSG_NOSIGNAL)
        if written < 0, errno == EINTR { continue }
        guard written > 0 else { return false }
        offset += written
      }
      return true
    }
  }
}
