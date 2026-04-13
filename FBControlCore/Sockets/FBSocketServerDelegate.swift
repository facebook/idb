/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// The Delegate for the Server.
@objc public protocol FBSocketServerDelegate: NSObjectProtocol {

  /// Called when the socket server has a new client connected.
  /// The File Descriptor will not be automatically be closed, so it's up to implementors to ensure that this happens so file descriptors do not leak.
  /// If you wish to reject the connection, close the file handle immediately.
  ///
  /// - Parameters:
  ///   - server: the socket server.
  ///   - address: the IP Address of the connected client.
  ///   - fileDescriptor: the file descriptor of the connected socket.
  @objc(socketServer:clientConnected:fileDescriptor:)
  func socketServer(_ server: FBSocketServer, clientConnected address: in6_addr, fileDescriptor: Int32)

  /// The Queue on which the Delegate will be called.
  /// This may be a serial or a concurrent queue.
  @objc var queue: DispatchQueue { get }
}
