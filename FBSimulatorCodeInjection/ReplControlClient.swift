/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// A client for the REPL control socket served by the injected shim inside the
/// REPL host. The shim is the server (it binds the socket at
/// `LaunchedRepl.socketPath`); a client connects to it and sends it
/// `dlopen`/`dlsym`/call requests.
///
/// Messages are length-prefixed binary property-list frames (a 4-byte big-endian
/// byte count then that many bytes of a binary plist), matching
/// `ReplSocketServer`. Length framing lets payloads carry arbitrary binary, so
/// command values round-trip exactly.
///
/// All blocking socket I/O runs on a dedicated dispatch queue so the caller's
/// cooperative thread is never blocked (a user's compiled code may run
/// for an arbitrary amount of time).
public final class ReplControlClient: @unchecked Sendable {

  private let fd: Int32
  private let ioQueue = DispatchQueue(label: "com.facebook.idb.repl.socket")
  private let closeLock = NSLock()
  private var isClosed = false

  private init(fd: Int32) {
    self.fd = fd
  }

  /// Connects to the shim's socket, retrying until `timeout` elapses (the socket
  /// only appears once the test process has launched and the shim has bound it).
  public static func connect(path: String, timeout: TimeInterval) async throws -> ReplControlClient {
    let queue = DispatchQueue(label: "com.facebook.idb.repl.connect")
    let fd: Int32 = try await withCheckedThrowingContinuation { continuation in
      queue.async {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
          continuation.resume(throwing: ReplControlError.socketCreationFailed)
          return
        }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxLength = MemoryLayout.size(ofValue: addr.sun_path)
        guard path.utf8.count < maxLength else {
          Darwin.close(fd)
          continuation.resume(throwing: ReplControlError.socketPathTooLong(path: path))
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
            continuation.resume(throwing: ReplControlError.connectTimedOut(path: path))
            return
          }
          usleep(100_000)
        }
      }
    }
    return ReplControlClient(fd: fd)
  }

  /// The shim's greeting: the `.swiftinterface` paths it advertises (possibly
  /// empty), the next run index to number compiled dylibs from (nonzero only when
  /// the app persisted a higher value across reconnects), and the host's stable
  /// session id (the same across reconnects to a still-running app, regenerated on
  /// relaunch).
  public struct Greeting: Sendable {
    public let interfaces: [String]
    public let nextRunIndex: UInt32
    public let sessionID: String
  }

  /// Reads the shim's greeting frame, sent once on connect before any command.
  /// Must be called exactly once, before the first `execute`.
  public func readGreeting() async throws -> Greeting {
    let fd = self.fd
    return try await withCheckedThrowingContinuation { continuation in
      ioQueue.async {
        do {
          let message = try Self.readMessage(fd: fd)
          guard message["type"] as? String == "greeting" else {
            throw ReplControlError.missingGreeting(received: message["type"] as? String)
          }
          let interfaces = message["interfaces"] as? [String] ?? []
          let nextRunIndex = (message["nextRunIndex"] as? NSNumber)?.uint32Value ?? 0
          let sessionID = message["sessionID"] as? String ?? ""
          continuation.resume(returning: Greeting(interfaces: interfaces, nextRunIndex: nextRunIndex, sessionID: sessionID))
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  /// Services a `host_command` the served process sends back *while* an `execute`
  /// is in flight. Receives the raw encoded command bytes (a binary property list
  /// of a `ReplCommand`) and returns the command's outcome.
  public typealias HostCommandHandler = (_ commandData: Data) async -> ReplHostCommandResult

  /// Sends a `{dylib, symbol}` command to the shim and returns its result. While
  /// the served process runs the injected code it may send nested `host_command`
  /// messages back; each is serviced via `hostCommandHandler` and answered with a
  /// `host_result` before the loop continues. The loop ends when the final
  /// `result` for this execute arrives. A `read` returning EOF/error before a
  /// complete message means the shim closed the socket mid-exchange (e.g. the test
  /// process crashed), surfaced as a disconnect.
  public func execute(dylibPath: String, symbol: String, hostCommandHandler: @escaping HostCommandHandler) async throws -> (success: Bool, output: String, nextRunIndex: Int32) {
    let fd = self.fd
    return try await withCheckedThrowingContinuation { continuation in
      // Not Sendable, so rebound as nonisolated(unsafe) for the ioQueue closure to capture.
      nonisolated(unsafe) let hostCommandHandler = hostCommandHandler
      ioQueue.async {
        do {
          try Self.writeMessage(["type": "execute", "dylib": dylibPath, "symbol": symbol], to: fd)

          while true {
            let message = try Self.readMessage(fd: fd)
            switch message["type"] as? String {
            case "host_command":
              let commandData = (message["command"] as? Data) ?? Data()
              let hostResult = Self.runHostCommand(hostCommandHandler, commandData: commandData)
              try Self.writeMessage(Self.hostResultMessage(hostResult), to: fd)

            case "result":
              let success = message["success"] as? Bool ?? false
              let output =
                success
                ? (message["result"] as? String ?? "")
                : "Error: \(message["error"] as? String ?? "unknown")"
              let nextRunIndex = (message["nextRunIndex"] as? NSNumber)?.int32Value ?? 0
              continuation.resume(returning: (success, output, nextRunIndex))
              return

            case let other:
              throw ReplControlError.unexpectedMessage(received: other)
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
  private static func runHostCommand(_ handler: @escaping HostCommandHandler, commandData: Data) -> ReplHostCommandResult {
    final class Box: @unchecked Sendable { var value: ReplHostCommandResult = .failure(ReplControlError.hostCommandDidNotComplete) }
    let box = Box()
    let semaphore = DispatchSemaphore(value: 0)
    nonisolated(unsafe) let commandHandler = handler
    Task {
      box.value = await commandHandler(commandData)
      semaphore.signal()
    }
    semaphore.wait()
    return box.value
  }

  private static func hostResultMessage(_ result: ReplHostCommandResult) -> [String: Any] {
    switch result {
    case .success(let data):
      return ["type": "host_result", "success": true, "result": data]
    case .failure(let error):
      return ["type": "host_result", "success": false, "error": "\(error)"]
    }
  }

  // MARK: - Framing

  private static func readFrame(fd: Int32) throws -> Data {
    let header = try readBytes(fd: fd, count: 4)
    let length = (Int(header[0]) << 24) | (Int(header[1]) << 16) | (Int(header[2]) << 8) | Int(header[3])
    guard length > 0 else { return Data() }
    return try readBytes(fd: fd, count: length)
  }

  private static func readBytes(fd: Int32, count: Int) throws -> Data {
    var data = Data(count: count)
    var total = 0
    while total < count {
      let n = data.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) -> Int in
        guard let base = raw.baseAddress else { return 0 }
        return Darwin.read(fd, base + total, count - total)
      }
      if n > 0 {
        total += n
      } else if n == 0 {
        throw ReplControlError.disconnected
      } else {
        throw ReplControlError.readFailed(errno: errno)
      }
    }
    return data
  }

  private static func readMessage(fd: Int32) throws -> [String: Any] {
    let frame = try readFrame(fd: fd)
    guard let message = try PropertyListSerialization.propertyList(from: frame, options: [], format: nil) as? [String: Any] else {
      throw ReplControlError.invalidMessage
    }
    return message
  }

  private static func writeMessage(_ message: [String: Any], to fd: Int32) throws {
    let payload = try PropertyListSerialization.data(fromPropertyList: message, format: .binary, options: 0)
    try writeFrame(payload, to: fd)
  }

  private static func writeFrame(_ payload: Data, to fd: Int32) throws {
    let length = payload.count
    var framed = Data([
      UInt8((length >> 24) & 0xFF),
      UInt8((length >> 16) & 0xFF),
      UInt8((length >> 8) & 0xFF),
      UInt8(length & 0xFF),
    ])
    framed.append(payload)
    try framed.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
      guard let base = raw.baseAddress else { return }
      var written = 0
      while written < raw.count {
        let n = Darwin.write(fd, base + written, raw.count - written)
        guard n > 0 else {
          throw ReplControlError.writeFailed
        }
        written += n
      }
    }
  }

  /// Closes the socket. This is what tears the session down: the shim's `accept`
  /// loop ends, `TestRepl/start` returns, and the test process exits. Closing
  /// the fd directly also interrupts any in-flight blocking read.
  public func close() {
    closeLock.lock()
    defer { closeLock.unlock() }
    guard !isClosed else { return }
    isClosed = true
    Darwin.close(fd)
  }
}

/// The outcome of a host command the injected code sent back mid-execute: on success, the
/// serialized result payload (empty when the command has no return value); on failure, the error,
/// whose description reaches the injected code.
public enum ReplHostCommandResult {
  case success(Data)
  case failure(any Error)
}

public enum ReplControlError: Error, Equatable {
  case socketCreationFailed
  case socketPathTooLong(path: String)
  case connectTimedOut(path: String)
  case missingGreeting(received: String?)
  case unexpectedMessage(received: String?)
  case invalidMessage
  case disconnected
  case readFailed(errno: Int32)
  case writeFailed
  case hostCommandDidNotComplete
}

extension ReplControlError: CustomStringConvertible, LocalizedError {
  public var description: String {
    switch self {
    case .socketCreationFailed:
      return "repl: failed to create socket"
    case let .socketPathTooLong(path):
      return "repl: socket path too long (\(path.utf8.count) bytes): \(path)"
    case let .connectTimedOut(path):
      return "repl: timed out connecting to control socket at \(path)"
    case let .missingGreeting(received):
      return "repl: expected a 'greeting' message, got type '\(received ?? "nil")'"
    case let .unexpectedMessage(received):
      return "repl: unexpected control-socket message type '\(received ?? "nil")'"
    case .invalidMessage:
      return "repl: invalid control-socket message"
    case .disconnected:
      return "repl: control socket closed before a complete message was received (the test process may have crashed)"
    case let .readFailed(errno):
      return "repl: failed to read from control socket: \(String(cString: strerror(errno)))"
    case .writeFailed:
      return "repl: failed to write to control socket"
    case .hostCommandDidNotComplete:
      return "repl: host command did not complete"
    }
  }

  public var errorDescription: String? { description }
}
