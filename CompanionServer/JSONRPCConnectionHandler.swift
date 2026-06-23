/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
@_implementationOnly import NIOCore

/// Per-connection handler sitting after `NewlineFrameDecoder`. It decodes the
/// first line as a `JSONRPCRequest`, hands it to the server's `submit` closure
/// (which dispatches it asynchronously and brackets it with the idle monitor),
/// then closes the connection. Closing is the client's "request received" signal:
/// the client keeps the connection open and reads until EOF, so the request is
/// reliably delivered before either side goes away. The request itself runs in a
/// detached task, independent of this connection.
final class JSONRPCConnectionHandler: ChannelInboundHandler {
  typealias InboundIn = ByteBuffer

  /// Hands a decoded request to the server for asynchronous processing.
  private let submit: @Sendable (JSONRPCRequest) -> Void

  init(submit: @escaping @Sendable (JSONRPCRequest) -> Void) {
    self.submit = submit
  }

  func channelActive(context: ChannelHandlerContext) {
    companionServerLog("CompanionServer: accepted connection")
    context.fireChannelActive()
  }

  func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    var buffer = unwrapInboundIn(data)
    let bytes = buffer.readBytes(length: buffer.readableBytes) ?? []
    let payload = Data(bytes)
    do {
      let request = try JSONDecoder().decode(JSONRPCRequest.self, from: payload)
      submit(request)
    } catch {
      companionServerLog("CompanionServer: ignoring non-JSON-RPC line: \(String(decoding: payload, as: UTF8.self))")
    }
    // One request per connection: close to acknowledge receipt to the client.
    context.close(promise: nil)
  }

  func errorCaught(context: ChannelHandlerContext, error: Error) {
    companionServerLog("CompanionServer: connection error: \(error)")
    context.close(promise: nil)
  }
}
