/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

public enum SocketServerError: Error, LocalizedError {
  case alreadyListening
  case notListening
  case socketCreationFailed(reason: String)
  case bindFailed(port: in_port_t, reason: String)
  case listenFailed(port: in_port_t, reason: String)

  public var errorDescription: String? {
    switch self {
    case .alreadyListening:
      return "Cannot start listening, socket is already listening"
    case .notListening:
      return "Cannot stop listening, there is no active socket"
    case let .socketCreationFailed(reason):
      return "Failed to create a socket with error '\(reason)'"
    case let .bindFailed(port, reason):
      return "Failed to bind the socket on port \(port) with error '\(reason)'"
    case let .listenFailed(port, reason):
      return "Failed to listen on the socket on port \(port) error '\(reason)'"
    }
  }
}

/// A generic socket server.
@objc
public final class FBSocketServer: NSObject {

  /// The port the server is bound on.
  public private(set) var port: in_port_t

  private let delegate: any SocketServerDelegate
  private var acceptSource: DispatchSourceRead?

  /// Creates a socket server for the provided port and delegate.
  public init(onPort port: in_port_t, delegate: any SocketServerDelegate) {
    self.port = port
    self.delegate = delegate
    super.init()
  }

  /// Create and listen to the socket.
  public func startListening() -> FBFuture<NSNull> {
    if acceptSource != nil {
      return FBFuture<NSNull>(error: SocketServerError.alreadyListening)
    }
    do {
      try createSocket(port: port)
    } catch {
      return FBFuture<NSNull>(error: error)
    }
    return FBFuture<NSNull>.empty()
  }

  /// Stop listening to the socket.
  @discardableResult
  public func stopListening() -> FBFuture<NSNull> {
    guard let acceptSource else {
      return FBFuture<NSNull>(error: SocketServerError.notListening)
    }
    acceptSource.cancel()
    self.acceptSource = nil
    return FBFuture<NSNull>.empty()
  }

  private func createSocket(port: in_port_t) throws {
    let socketDescriptor = socket(PF_INET6, SOCK_STREAM, IPPROTO_TCP)
    guard socketDescriptor > 0 else {
      throw SocketServerError.socketCreationFailed(reason: Self.lastErrorDescription())
    }
    var flagTrue: Int32 = 1
    setsockopt(socketDescriptor, SOL_SOCKET, SO_REUSEADDR, &flagTrue, socklen_t(MemoryLayout<Int32>.size))

    var address = sockaddr_in6()
    address.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
    address.sin6_family = sa_family_t(AF_INET6)
    address.sin6_port = port.bigEndian
    address.sin6_addr = in6addr_any
    guard Self.withSocketAddress(&address, { bind(socketDescriptor, $0, socklen_t(MemoryLayout<sockaddr_in6>.size)) }) == 0 else {
      throw SocketServerError.bindFailed(port: port, reason: Self.lastErrorDescription())
    }
    guard listen(socketDescriptor, 10) == 0 else {
      throw SocketServerError.listenFailed(port: port, reason: Self.lastErrorDescription())
    }

    // Since the client queue may be concurrent, accept() calls are serialized on a queue of their
    // own: they update internal state.
    let clientQueue = delegate.queue
    let acceptQueue = DispatchQueue(label: "\(clientQueue.label).accept")
    let acceptSource = DispatchSource.makeReadSource(fileDescriptor: socketDescriptor, queue: acceptQueue)
    acceptSource.setEventHandler { [weak self] in
      self?.accept(socketDescriptor, clientQueue: clientQueue)
    }
    acceptSource.setCancelHandler {
      close(socketDescriptor)
    }
    self.acceptSource = acceptSource
    acceptSource.resume()

    // Read back the port the kernel actually bound, since 0 requests an ephemeral one.
    var bound = sockaddr_in6()
    var boundLength = socklen_t(MemoryLayout<sockaddr_in6>.size)
    _ = Self.withSocketAddress(&bound) { getsockname(socketDescriptor, $0, &boundLength) }
    self.port = bound.sin6_port.bigEndian
  }

  private func accept(_ socketDescriptor: Int32, clientQueue: DispatchQueue) {
    var address = sockaddr_in6()
    var addressLength = socklen_t(MemoryLayout<sockaddr_in6>.size)
    let acceptDescriptor = Self.withSocketAddress(&address) { Darwin.accept(socketDescriptor, $0, &addressLength) }
    guard acceptDescriptor > 0 else {
      return
    }
    let clientAddress = address.sin6_addr
    clientQueue.async {
      self.delegate.socketServer(self, clientConnected: clientAddress, fileDescriptor: acceptDescriptor)
    }
  }

  private static func withSocketAddress<Result>(
    _ address: inout sockaddr_in6,
    _ body: (UnsafeMutablePointer<sockaddr>) -> Result
  ) -> Result {
    withUnsafeMutablePointer(to: &address) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1, body)
    }
  }

  private static func lastErrorDescription() -> String {
    String(cString: strerror(errno))
  }
}
