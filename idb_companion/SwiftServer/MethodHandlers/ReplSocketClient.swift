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
          guard json["type"] as? String == "greeting" else {
            throw GRPCStatus(code: .internalError, message: "repl: expected a 'greeting' message, got type '\(json["type"] as? String ?? "nil")'")
          }
          let interfaces = json["interfaces"] as? [String] ?? []
          continuation.resume(returning: interfaces)
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  /// Services a `host_command` the served process sends back *while* an `execute`
  /// is in flight. Returns whether the command succeeded plus a JSON string: the
  /// command's result value on success, or an error message on failure.
  typealias HostCommandHandler = (_ name: String, _ args: [String: Any]) async -> (success: Bool, resultJSON: String)

  /// Sends a `{dylib, symbol}` command to the shim and returns its result. While
  /// the served process runs the injected code it may send nested `host_command`
  /// messages back; each is serviced via `hostCommandHandler` and answered with a
  /// `host_result` before the loop continues. The loop ends when the final
  /// `result` for this execute arrives. A `read` returning EOF/error before a
  /// complete message means the shim closed the socket mid-exchange (e.g. the test
  /// process crashed), surfaced as a disconnect.
  func execute(dylibPath: String, symbol: String, hostCommandHandler: @escaping HostCommandHandler) async throws -> (success: Bool, output: String) {
    let fd = self.fd
    return try await withCheckedThrowingContinuation { continuation in
      ioQueue.async {
        do {
          try Self.writeLine(["type": "execute", "dylib": dylibPath, "symbol": symbol], to: fd)

          while true {
            let responseData = try Self.readLine(fd: fd)
            guard let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
              throw GRPCStatus(code: .internalError, message: "repl: invalid response from test process")
            }
            switch json["type"] as? String {
            case "host_command":
              let name = json["name"] as? String ?? ""
              let args = json["args"] as? [String: Any] ?? [:]
              let hostResult = Self.runHostCommand(hostCommandHandler, name: name, args: args)
              try Self.writeLine(Self.hostResultMessage(hostResult), to: fd)

            case "result":
              let success = json["success"] as? Bool ?? false
              let output =
                success
                ? (json["result"] as? String ?? "")
                : "Error: \(json["error"] as? String ?? "unknown")"
              continuation.resume(returning: (success, output))
              return

            case let other:
              throw GRPCStatus(code: .internalError, message: "repl: unexpected control-socket message type '\(other ?? "nil")'")
            }
          }
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  /// Runs the async `hostCommandHandler` to completion from the synchronous
  /// `ioQueue`, bridging with a semaphore. The `ioQueue` is dedicated to this
  /// socket, so blocking it here is fine.
  private static func runHostCommand(_ handler: @escaping HostCommandHandler, name: String, args: [String: Any]) -> (success: Bool, resultJSON: String) {
    final class Box: @unchecked Sendable { var value: (success: Bool, resultJSON: String) = (false, "null") }
    let box = Box()
    let semaphore = DispatchSemaphore(value: 0)
    Task {
      box.value = await handler(name, args)
      semaphore.signal()
    }
    semaphore.wait()
    return box.value
  }

  /// Builds a `host_result` message from a handler's `(success, resultJSON)`: the
  /// JSON string becomes the `result` value on success, or the `error` on failure.
  private static func hostResultMessage(_ result: (success: Bool, resultJSON: String)) -> [String: Any] {
    if result.success {
      let value = (try? JSONSerialization.jsonObject(with: Data(result.resultJSON.utf8), options: [.fragmentsAllowed])) ?? NSNull()
      return ["type": "host_result", "success": true, "result": value]
    }
    return ["type": "host_result", "success": false, "error": result.resultJSON]
  }

  /// Reads one newline-terminated message from `fd`, throwing on EOF/error.
  private static func readLine(fd: Int32) throws -> Data {
    var data = Data()
    var byte: UInt8 = 0
    while true {
      let bytesRead = Darwin.read(fd, &byte, 1)
      if bytesRead > 0 {
        if byte == 0x0A { return data }
        data.append(byte)
      } else if bytesRead == 0 {
        throw GRPCStatus(code: .unavailable, message: "repl: control socket closed before a complete message was received (the test process may have crashed)")
      } else {
        throw GRPCStatus(code: .internalError, message: "repl: failed to read from control socket: \(String(cString: strerror(errno)))")
      }
    }
  }

  /// Writes `message` as a newline-terminated JSON line to `fd`.
  private static func writeLine(_ message: [String: Any], to fd: Int32) throws {
    var data = try JSONSerialization.data(withJSONObject: message)
    data.append(0x0A)
    try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
      guard let base = raw.baseAddress else { return }
      var written = 0
      while written < raw.count {
        let n = Darwin.write(fd, base + written, raw.count - written)
        guard n > 0 else {
          throw GRPCStatus(code: .internalError, message: "repl: failed to write to control socket")
        }
        written += n
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
