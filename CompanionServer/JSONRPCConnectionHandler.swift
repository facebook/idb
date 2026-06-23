/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
@_implementationOnly import NIOCore

/// Per-connection handler sitting after `NewlineFrameDecoder`. Each inbound frame
/// is one line; it decodes the line as a `JSONRPCRequest` and forwards it to the
/// server's request handler. Malformed lines are reported but do not close the
/// connection.
final class JSONRPCConnectionHandler: ChannelInboundHandler {
  typealias InboundIn = ByteBuffer

  private let onRequest: CompanionServer.RequestHandler

  init(onRequest: @escaping CompanionServer.RequestHandler) {
    self.onRequest = onRequest
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
      onRequest(request)
    } catch {
      companionServerLog("CompanionServer: ignoring non-JSON-RPC line: \(String(decoding: payload, as: UTF8.self))")
    }
  }

  func errorCaught(context: ChannelHandlerContext, error: Error) {
    companionServerLog("CompanionServer: connection error: \(error)")
    context.close(promise: nil)
  }
}
