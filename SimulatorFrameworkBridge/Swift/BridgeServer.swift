/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Darwin
import Foundation
import SimulatorFrameworkBridgeProtocol

@objc public final class BridgeSocketResponse: NSObject {
  @objc public let data: Data
  @objc public let shutdown: Bool

  @objc public init(data: Data, shutdown: Bool) {
    self.data = data
    self.shutdown = shutdown
    super.init()
  }
}

@objc public final class BridgeServer: NSObject {
  @objc public static let defaultIdleTimeoutSeconds: Int32 = 300
  @objc public static let serveBacklog: Int32 = 16
  public static func pollTimeoutMilliseconds(seconds: Int32) -> Int32 {
    Int32(clamping: Int64(max(1, seconds)) * 1000)
  }

  /// Runs synchronously; runtime preparation and request handling stay on the caller's thread.
  @objc public static func serve(
    socketPath: String,
    idleTimeoutSeconds: Int32,
    exitOnDisconnect: Bool,
    prepareRuntime: () -> Void,
    handleRequest: (Data) -> BridgeSocketResponse
  ) -> Int32 {
    serve(
      socketPath: socketPath,
      idleTimeoutSeconds: idleTimeoutSeconds,
      initialClientTimeoutSeconds: nil,
      exitOnDisconnect: exitOnDisconnect,
      prepareRuntime: prepareRuntime,
      handleRequest: handleRequest
    )
  }

  public static func serve(
    socketPath: String,
    idleTimeoutSeconds: Int32,
    initialClientTimeoutSeconds: Int32?,
    exitOnDisconnect: Bool,
    prepareRuntime: () -> Void,
    handleRequest: (Data) -> BridgeSocketResponse
  ) -> Int32 {
    let pathString = socketPath as NSString
    return withExtendedLifetime(pathString) {
      let path = pathString.fileSystemRepresentation
      let listenFD = socket(AF_UNIX, SOCK_STREAM, 0)
      guard listenFD >= 0 else {
        NSLog("[BridgeServer] socket() failed: %@", String(cString: strerror(errno)))
        return 1
      }
      defer { close(listenFD) }

      var address = sockaddr_un()
      address.sun_family = sa_family_t(AF_UNIX)
      let pathLength = strlen(path)
      guard pathLength < MemoryLayout.size(ofValue: address.sun_path) else {
        NSLog("[BridgeServer] socket path too long: %@", socketPath)
        return 1
      }
      withUnsafeMutableBytes(of: &address.sun_path) {
        $0.copyBytes(from: UnsafeRawBufferPointer(start: path, count: pathLength + 1))
      }
      // Keep the inode stable: unlinking a lock file lets another starter lock a different inode.
      let lockFD = open(socketPath + ".lock", O_CREAT | O_RDWR | O_NOFOLLOW, mode_t(0o600))
      guard lockFD >= 0 else { return 1 }
      defer { close(lockFD) }
      guard flock(lockFD, LOCK_EX | LOCK_NB) == 0 else {
        return errno == EWOULDBLOCK ? 0 : 1
      }
      unlink(path)
      let bound = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
          bind(listenFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
      }
      guard bound == 0 else {
        NSLog("[BridgeServer] bind(%@) failed: %@", socketPath, String(cString: strerror(errno)))
        return 1
      }
      guard listen(listenFD, serveBacklog) == 0 else {
        NSLog("[BridgeServer] listen() failed: %@", String(cString: strerror(errno)))
        return 1
      }
      defer { unlink(path) }

      prepareRuntime()
      var initialClientDeadline = initialClientTimeoutSeconds.map {
        ProcessInfo.processInfo.systemUptime + Double(max(1, $0))
      }
      NSLog("[BridgeServer] serving on %@ (idle timeout %ds)", socketPath, idleTimeoutSeconds)
      while true {
        var listener = pollfd(fd: listenFD, events: Int16(POLLIN), revents: 0)
        let timeout: Int32
        if let initialClientDeadline {
          let remaining = initialClientDeadline - ProcessInfo.processInfo.systemUptime
          guard remaining > 0 else { break }
          timeout = Int32(clamping: Int64(ceil(remaining * 1000)))
        } else {
          timeout = pollTimeoutMilliseconds(seconds: idleTimeoutSeconds)
        }
        let ready = poll(&listener, 1, timeout)
        if ready == 0 {
          if initialClientDeadline != nil {
            NSLog("[BridgeServer] initial client timeout; exiting")
          } else {
            NSLog("[BridgeServer] idle %ds with no client; exiting", idleTimeoutSeconds)
          }
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
        initialClientDeadline = nil
        let shutdown = serveConnection(connection, idleTimeoutSeconds: idleTimeoutSeconds, handleRequest: handleRequest)
        close(connection)
        if exitOnDisconnect {
          NSLog("[BridgeServer] exclusive client disconnected; exiting")
          break
        }
        if shutdown {
          NSLog("[BridgeServer] shutdown requested by client; exiting")
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
    handleRequest: (Data) -> BridgeSocketResponse
  ) -> Bool {
    var timeout = timeval(tv_sec: Int(idleTimeoutSeconds), tv_usec: 0)
    setsockopt(connection, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    setsockopt(connection, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    while true {
      let step: ConnectionStep = autoreleasepool {
        guard let header = readFully(connection, count: 4) else { return .disconnected }
        guard let length = try? BridgeFrame.size(fromHeader: header),
          let request = readFully(connection, count: length)
        else { return .disconnected }
        let response = handleRequest(request)
        guard let responseHeader = try? BridgeFrame.header(forSize: response.data.count),
          writeFully(connection, data: responseHeader), writeFully(connection, data: response.data)
        else { return .disconnected }
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
