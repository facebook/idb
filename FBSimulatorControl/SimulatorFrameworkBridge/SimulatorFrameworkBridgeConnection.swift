/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Darwin
@preconcurrency import FBControlCore
import Foundation
import SimulatorFrameworkBridgeProtocol
import SimulatorIPC

// SAFETY: the subprocess handle is retained for diagnostics and only queried through thread-safe futures.
enum BridgeGuestOwnership: @unchecked Sendable {
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
// SAFETY: socket I/O and `terminalError` are accessed only on `queue`.
// patternlint-disable-next-line unchecked-sendable
final class SimulatorFrameworkBridgeConnection: BridgeConnection, @unchecked Sendable {
  private let fileDescriptor: Int32
  private let ownership: BridgeGuestOwnership
  private let queue = DispatchQueue(label: "com.facebook.FBSimulatorControl.frameworkbridge.connection")

  private var terminalError: Error?

  /// The per-`recv` silence deadline, rather than a deadline for the whole response.
  static let receiveTimeoutSeconds = 30

  var mayBeHeldBetweenRoundTrips: Bool {
    ownership.isPrivate
  }

  init(fileDescriptor: Int32, ownership: BridgeGuestOwnership) {
    self.fileDescriptor = fileDescriptor
    self.ownership = ownership
  }

  deinit {
    close(fileDescriptor)
  }

  func roundTrip(_ requestData: Data) async throws -> Data {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
      queue.async { [self] in
        do {
          if let terminalError { throw terminalError }
          let request = try BridgeRequest.decode(requestData)
          try SimulatorFrameworkBridgeConnection.writeFrame(fileDescriptor, requestData)
          let responseData = try SimulatorFrameworkBridgeConnection.readFrame(fileDescriptor, guest: ownership.process)
          _ = try BridgeResponse.decode(responseData, for: request)
          continuation.resume(returning: responseData)
        } catch {
          terminalError = error
          continuation.resume(throwing: error)
        }
      }
    }
  }

  /// Sends `request` and yields the result of every response frame until the guest closes the connection.
  ///
  /// A stream may stay silent for as long as nothing happens, so the per-`recv` deadline is lifted.
  /// Ending the iteration shuts the socket down, which is how the guest learns to stop.
  func stream(_ request: BridgeRequest) -> AsyncThrowingStream<BridgeResult, Error> {
    AsyncThrowingStream { continuation in
      continuation.onTermination = { [self] _ in
        shutdown(fileDescriptor, SHUT_RDWR)
      }
      queue.async { [self] in
        do {
          var noDeadline = timeval()
          setsockopt(fileDescriptor, SOL_SOCKET, SO_RCVTIMEO, &noDeadline, socklen_t(MemoryLayout<timeval>.size))
          try SimulatorFrameworkBridgeConnection.writeFrame(fileDescriptor, request.encoded())
          while let frame = try SimulatorFrameworkBridgeConnection.readFrameUnlessClosed(fileDescriptor, guest: ownership.process) {
            continuation.yield(try BridgeResponse.decode(frame, for: request).result)
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
    }
  }

  /// Connects until the deadline or guest failure. A shared lock loser may exit before its winner binds.
  ///
  /// `guest` is the process expected to bind `path`, passed only when this host spawned it.
  static func connect(
    path: String,
    timeout: TimeInterval,
    guest: FBSubprocess<AnyObject, AnyObject, AnyObject>? = nil,
    scope: BridgeServiceScope = .exclusive,
    attempt: @escaping @Sendable (String) -> Int32? = attemptConnection
  ) async throws -> Int32 {
    guard path.utf8.count < IPCSocket.pathCapacity else {
      throw AXBridgeError.socketPathTooLong(path: path, limit: IPCSocket.pathCapacity)
    }
    return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int32, Error>) in
      DispatchQueue.global().async {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
          if let fileDescriptor = attempt(path) {
            continuation.resume(returning: fileDescriptor)
            return
          }
          // Our guest exiting does not mean the socket is unbound: the shared per-UDID path may be served by
          // another host's guest, so try once more before failing. `.done` rather than `hasCompleted`: a
          // cancelled or failed future is not evidence the process terminated.
          if let guest, guest.statLoc.state == .done {
            let exit = terminationCause(waitpidStatus: guest.statLoc.result?.int32Value)
            if scope != .shared || exit.signal != nil || exit.exitCode != 0 {
              if let fileDescriptor = attempt(path) {
                continuation.resume(returning: fileDescriptor)
                return
              }
              continuation.resume(
                throwing: AXBridgeError.guestDiedBeforeBinding(
                  pid: guest.processIdentifier, signal: exit.signal, exitCode: exit.exitCode, path: path))
              return
            }
          }
          usleep(100_000)
        } while Date() < deadline
        continuation.resume(throwing: AXBridgeError.guestFailure("timed out connecting to the serve socket at \(path)"))
      }
    }
  }

  /// One connect attempt, carrying the socket options a serving connection needs when it lands.
  private static func attemptConnection(toPath path: String) -> Int32? {
    (try? IPCSocket.connect(path: path, timeoutSeconds: receiveTimeoutSeconds)) ?? nil
  }

  static func writeFrame(_ fileDescriptor: Int32, _ payload: Data) throws {
    do {
      try IPCSocket.writeFrame(fileDescriptor, payload)
    } catch IPCError.closed {
      throw AXBridgeError.guestFailure("socket write returned 0")
    } catch let IPCError.failed(_, code) {
      throw AXBridgeError.guestFailure("socket write failed: \(String(cString: strerror(code)))")
    } catch {
      throw AXBridgeError.guestFailure("socket write failed: \(error)")
    }
  }

  static func readFrame(
    _ fileDescriptor: Int32,
    guest: FBSubprocess<AnyObject, AnyObject, AnyObject>?
  ) throws -> Data {
    do {
      return try IPCSocket.readFrame(fileDescriptor)
    } catch IPCError.closed {
      throw AXBridgeError.guestFailure(SimulatorFrameworkBridgeConnection.socketClosedMessage(process: guest))
    } catch IPCError.timedOut {
      throw AXBridgeError.guestFailure("serve read timed out after \(receiveTimeoutSeconds)s with no data")
    } catch let IPCError.failed(_, code) {
      throw AXBridgeError.guestFailure("socket read failed: \(String(cString: strerror(code)))")
    } catch {
      throw AXBridgeError.guestFailure("socket read failed: \(error)")
    }
  }

  /// A frame, or `nil` when the peer closed the connection at a frame boundary: the end of a stream
  /// rather than a truncated response.
  static func readFrameUnlessClosed(
    _ fileDescriptor: Int32,
    guest: FBSubprocess<AnyObject, AnyObject, AnyObject>?
  ) throws -> Data? {
    var byte: UInt8 = 0
    while true {
      let peeked = recv(fileDescriptor, &byte, 1, MSG_PEEK)
      if peeked == 0 {
        return nil
      }
      if peeked > 0 {
        return try readFrame(fileDescriptor, guest: guest)
      }
      if errno != EINTR {
        throw AXBridgeError.guestFailure("socket read failed: \(String(cString: strerror(errno)))")
      }
    }
  }

  static func socketClosedMessage(process: FBSubprocess<AnyObject, AnyObject, AnyObject>?) -> String {
    guard let process else {
      return socketClosedMessage(pid: nil, signal: nil, exitCode: nil)
    }
    // `result` blocks until the future resolves. EOF can arrive before process status, so completion
    // must be checked first to keep an error-reporting path from hanging.
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

  /// Splits a `waitpid` status into whichever of the two outcomes it encodes, or neither.
  ///
  /// Read from `statLoc` rather than from the sibling `signal` / `exitCode` futures because
  /// `resolveProcessFinished` resolves `statLoc` first and the other two a few statements later — a
  /// reader that catches that gap sees neither, and reports a death it cannot describe.
  ///
  /// Both nil for a stop rather than a termination, and for no status at all. A stop encodes the
  /// stopping signal in the byte an exit uses for its code, so reporting it either way names a number
  /// the process never produced.
  static func terminationCause(waitpidStatus: Int32?) -> (signal: Int?, exitCode: Int?) {
    guard let waitpidStatus else {
      return (signal: nil, exitCode: nil)
    }
    let status = waitpidStatus & 0x7f
    if status == 0x7f {
      return (signal: nil, exitCode: nil)
    }
    if status != 0 {
      return (signal: Int(status), exitCode: nil)
    }
    return (signal: nil, exitCode: Int((waitpidStatus >> 8) & 0xff))
  }
}
