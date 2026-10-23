/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import Network
import os

/// Answers each connection on the loopback interface with a scripted response, and records the request it read: a
/// server whose replies a test controls byte for byte.
// SAFETY: `port` is written once, on `queue`, before `serving` returns, and read only after; `requests` is behind its
// own lock; everything else is immutable or confined to `queue`.
// patternlint-disable-next-line unchecked-sendable
final class ScriptedHTTPServer: @unchecked Sendable {

  /// What the server does once it has read a request.
  struct Reply: Sendable {
    /// Sent one after another, each once the last was taken.
    var parts: [Data]
    /// Whether to close the connection after the parts, rather than hold it open without sending anything more.
    var closes = true
  }

  private let listener: NWListener
  private let reply: Reply
  private let queue = DispatchQueue(label: "idb.tests.scripted-http")
  private let recorded = OSAllocatedUnfairLock<[String]>(initialState: [])
  private(set) var port: UInt16 = 0

  /// The heads of the requests read so far, in order.
  var requests: [String] { recorded.withLock { $0 } }

  private init(listener: NWListener, reply: Reply) {
    self.listener = listener
    self.reply = reply
  }

  static func serving(_ reply: Reply) async throws -> ScriptedHTTPServer {
    let parameters = NWParameters.tcp
    parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
    let server = ScriptedHTTPServer(listener: try NWListener(using: parameters), reply: reply)
    try await server.start()
    return server
  }

  /// A response with a `Content-Length` and `body`.
  static func serving(statusCode: Int = 200, body: Data) async throws -> ScriptedHTTPServer {
    let head = "HTTP/1.1 \(statusCode) Status\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
    return try await serving(Reply(parts: [Data(head.utf8), body]))
  }

  func stop() {
    listener.cancel()
  }

  private func start() async throws {
    listener.newConnectionHandler = { [weak self] connection in
      self?.serve(connection)
    }
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
      listener.stateUpdateHandler = { [weak self] state in
        switch state {
        case .ready:
          guard let self, let port = self.listener.port else {
            return
          }
          self.port = port.rawValue
          self.listener.stateUpdateHandler = nil
          continuation.resume()
        case .failed(let error):
          self?.listener.stateUpdateHandler = nil
          continuation.resume(throwing: error)
        case .setup, .waiting, .cancelled:
          break
        @unknown default:
          break
        }
      }
      listener.start(queue: queue)
    }
  }

  private func serve(_ connection: NWConnection) {
    connection.start(queue: queue)
    readRequest(connection, received: Data())
  }

  private func readRequest(_ connection: NWConnection, received: Data) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 64 << 10) { [weak self] data, _, isComplete, error in
      guard let self, error == nil else {
        connection.cancel()
        return
      }
      let received = received + (data ?? Data())
      guard let end = received.range(of: Data("\r\n\r\n".utf8)) else {
        if isComplete {
          connection.cancel()
        } else {
          self.readRequest(connection, received: received)
        }
        return
      }
      let head = String(decoding: received[..<end.lowerBound], as: UTF8.self)
      self.recorded.withLock { $0.append(head) }
      self.send(self.reply.parts[...], on: connection)
    }
  }

  private func send(_ parts: ArraySlice<Data>, on connection: NWConnection) {
    guard let part = parts.first else {
      if reply.closes {
        connection.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in connection.cancel() })
      }
      return
    }
    connection.send(
      content: part,
      completion: .contentProcessed { [weak self] error in
        guard let self, error == nil else {
          connection.cancel()
          return
        }
        self.send(parts.dropFirst(), on: connection)
      })
  }
}
