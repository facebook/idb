/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// The server half of the REPL control socket, as `ReplSocketServer` serves it from inside the
/// injected process: length-prefixed binary property lists over a unix socket.
final class FakeReplShim: @unchecked Sendable {

  final class Connection: @unchecked Sendable {
    private let fd: Int32
    private let closeLock = NSLock()
    private var isClosed = false

    init(fd: Int32) {
      self.fd = fd
    }

    func send(_ message: [String: Any]) throws {
      let payload = try PropertyListSerialization.data(fromPropertyList: message, format: .binary, options: 0)
      let length = UInt32(payload.count).bigEndian
      var framed = withUnsafeBytes(of: length) { Data($0) }
      framed.append(payload)
      try framed.withUnsafeBytes { raw in
        var written = 0
        while written < raw.count {
          let n = Darwin.write(fd, raw.baseAddress! + written, raw.count - written)
          guard n > 0 else { throw POSIXError(.EPIPE) }
          written += n
        }
      }
    }

    /// Reads off the cooperative pool: the client under test needs a cooperative thread to service
    /// host commands while the shim waits for its answer.
    func receive() async throws -> [String: Any] {
      try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global().async {
          continuation.resume(with: Result { try self.receiveBlocking() })
        }
      }
    }

    private func receiveBlocking() throws -> [String: Any] {
      let header = try read(count: 4)
      let length = header.reduce(0) { ($0 << 8) | Int($1) }
      let payload = try read(count: length)
      guard let message = try PropertyListSerialization.propertyList(from: payload, format: nil) as? [String: Any] else {
        throw POSIXError(.EBADMSG)
      }
      return message
    }

    /// Idempotent: closing a descriptor twice could close one another test has since opened.
    func close() {
      closeLock.lock()
      defer { closeLock.unlock() }
      guard !isClosed else { return }
      isClosed = true
      Darwin.close(fd)
    }

    private func read(count: Int) throws -> Data {
      var data = Data(count: count)
      var total = 0
      while total < count {
        let n = data.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress! + total, count - total) }
        guard n > 0 else { throw POSIXError(.ECONNRESET) }
        total += n
      }
      return data
    }
  }

  let path = FakeReplShim.temporarySocketPath()
  private let listener: Int32
  private(set) var connection: Connection?

  init() throws {
    listener = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    _ = withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
      path.withCString { src in memcpy(ptr, src, path.utf8.count + 1) }
    }
    let bound = withUnsafePointer(to: &addr) { ptr in
      ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
    guard bound == 0, Darwin.listen(listener, 1) == 0 else {
      throw POSIXError(.EADDRNOTAVAIL)
    }
  }

  deinit {
    connection?.close()
    Darwin.close(listener)
    Darwin.unlink(path)
  }

  func accept() async throws -> Connection {
    let listener = self.listener
    let fd: Int32 = await withCheckedContinuation { continuation in
      DispatchQueue.global().async { continuation.resume(returning: Darwin.accept(listener, nil, nil)) }
    }
    guard fd >= 0 else { throw POSIXError(.ECONNABORTED) }
    let connection = Connection(fd: fd)
    self.connection = connection
    return connection
  }

  static func temporarySocketPath() -> String {
    "/tmp/idb_repl_test_\(UUID().uuidString.prefix(8)).sock"
  }
}
