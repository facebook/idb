/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import GRPC

/// A client for the REPL control socket served by the injected shim inside the
/// test process. The shim is the server (it binds the socket); the companion
/// connects to it and forwards `dlopen`/`dlsym`/call requests.
///
/// All blocking socket I/O runs on a dedicated dispatch queue so the gRPC
/// handler's cooperative thread is never blocked (a user's compiled code may run
/// for an arbitrary amount of time).
final class ReplSocketClient {

  private let fd: Int32
  private let ioQueue = DispatchQueue(label: "com.facebook.idb.repl.socket")
  private let closeLock = NSLock()
  private var isClosed = false

  private init(fd: Int32) {
    self.fd = fd
  }

  /// Connects to the shim's socket, retrying until `timeout` elapses (the socket
  /// only appears once the test process has launched and the shim has bound it).
  static func connect(path: String, timeout: TimeInterval) async throws -> ReplSocketClient {
    let queue = DispatchQueue(label: "com.facebook.idb.repl.connect")
    let fd: Int32 = try await withCheckedThrowingContinuation { continuation in
      queue.async {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
          continuation.resume(throwing: GRPCStatus(code: .internalError, message: "repl: failed to create socket"))
          return
        }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxLength = MemoryLayout.size(ofValue: addr.sun_path)
        guard path.utf8.count < maxLength else {
          Darwin.close(fd)
          continuation.resume(throwing: GRPCStatus(code: .invalidArgument, message: "repl: socket path too long (\(path.utf8.count) bytes): \(path)"))
          return
        }
        _ = withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
          path.withCString { src in memcpy(ptr, src, path.utf8.count + 1) }
        }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let deadline = Date().addingTimeInterval(timeout)
        while true {
          let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
              Darwin.connect(fd, sockPtr, size)
            }
          }
          if result == 0 {
            continuation.resume(returning: fd)
            return
          }
          if Date() >= deadline {
            Darwin.close(fd)
            continuation.resume(throwing: GRPCStatus(code: .deadlineExceeded, message: "repl: timed out connecting to control socket at \(path)"))
            return
          }
          usleep(100_000)
        }
      }
    }
    return ReplSocketClient(fd: fd)
  }

  /// Reads the shim's one-line greeting, sent once on connect before any
  /// command, and returns the `.swiftinterface` paths it advertises (possibly
  /// empty). Must be called exactly once, before the first `execute`.
  func readGreeting() async throws -> [String] {
    let fd = self.fd
    return try await withCheckedThrowingContinuation { continuation in
      ioQueue.async {
        do {
          var greetingData = Data()
          var byte: UInt8 = 0
          while true {
            let bytesRead = Darwin.read(fd, &byte, 1)
            if bytesRead > 0 {
              if byte == 0x0A { break }
              greetingData.append(byte)
            } else if bytesRead == 0 {
              throw GRPCStatus(code: .unavailable, message: "repl: control socket closed before the greeting was received (the test process may have crashed)")
            } else {
              throw GRPCStatus(code: .internalError, message: "repl: failed to read greeting from control socket: \(String(cString: strerror(errno)))")
            }
          }
          guard let json = try JSONSerialization.jsonObject(with: greetingData) as? [String: Any] else {
            throw GRPCStatus(code: .internalError, message: "repl: invalid greeting from test process")
          }
          let interfaces = json["interfaces"] as? [String] ?? []
          continuation.resume(returning: interfaces)
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  /// Sends a `{dylib, symbol}` command to the shim and returns its result.
  func execute(dylibPath: String, symbol: String) async throws -> (success: Bool, output: String) {
    let fd = self.fd
    return try await withCheckedThrowingContinuation { continuation in
      ioQueue.async {
        do {
          let command = ["dylib": dylibPath, "symbol": symbol]
          var data = try JSONSerialization.data(withJSONObject: command)
          data.append(0x0A)
          try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.baseAddress else { return }
            var written = 0
            while written < raw.count {
              let n = Darwin.write(fd, base + written, raw.count - written)
              guard n > 0 else {
                throw GRPCStatus(code: .internalError, message: "repl: failed to write command to control socket")
              }
              written += n
            }
          }

          // Read the newline-terminated response one byte at a time. A `read` of
          // 0 (clean EOF) or -1 (error) before the newline means the shim closed
          // the control socket mid-response (e.g. the test process crashed);
          // surface that as a disconnect rather than falling through to parse a
          // partial or empty buffer.
          var responseData = Data()
          var byte: UInt8 = 0
          while true {
            let bytesRead = Darwin.read(fd, &byte, 1)
            if bytesRead > 0 {
              if byte == 0x0A { break }
              responseData.append(byte)
            } else if bytesRead == 0 {
              throw GRPCStatus(code: .unavailable, message: "repl: control socket closed by the test process before a complete response was received (the test process may have crashed)")
            } else {
              throw GRPCStatus(code: .internalError, message: "repl: failed to read response from control socket: \(String(cString: strerror(errno)))")
            }
          }

          guard let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            throw GRPCStatus(code: .internalError, message: "repl: invalid response from test process")
          }
          let success = json["success"] as? Bool ?? false
          let output: String
          if success {
            output = json["result"] as? String ?? ""
          } else {
            output = "Error: \(json["error"] as? String ?? "unknown")"
          }
          continuation.resume(returning: (success, output))
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  /// Closes the socket. This is what tears the session down: the shim's `accept`
  /// loop ends, `TestRepl/start` returns, and the test process exits. Closing
  /// the fd directly also interrupts any in-flight blocking read.
  func close() {
    closeLock.lock()
    defer { closeLock.unlock() }
    guard !isClosed else { return }
    isClosed = true
    Darwin.close(fd)
  }
}
