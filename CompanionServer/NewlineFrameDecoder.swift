/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@_implementationOnly import NIOCore

/// Splits the inbound byte stream into newline-delimited frames — one JSON-RPC
/// message per line — emitting each line with its trailing `\n` stripped. This
/// matches the newline-delimited JSON framing already used elsewhere in idb
/// (e.g. the REPL control socket).
struct NewlineFrameDecoder: ByteToMessageDecoder {
  typealias InboundOut = ByteBuffer

  mutating func decode(context: ChannelHandlerContext, buffer: inout ByteBuffer) throws -> DecodingState {
    guard let newlineIndex = buffer.readableBytesView.firstIndex(of: UInt8(ascii: "\n")) else {
      return .needMoreData
    }
    // `firstIndex` is an absolute index into the buffer; the view starts at the
    // reader index, so the line length is the distance from there. `lineLength <=
    // readableBytes` by construction, so the slice is always present.
    let lineLength = newlineIndex - buffer.readerIndex
    guard let line = buffer.readSlice(length: lineLength) else {
      return .needMoreData
    }
    buffer.moveReaderIndex(forwardBy: 1) // discard the newline delimiter
    context.fireChannelRead(wrapInboundOut(line))
    return .continue
  }

  mutating func decodeLast(context: ChannelHandlerContext, buffer: inout ByteBuffer, seenEOF: Bool) throws -> DecodingState {
    // Deliver any trailing bytes that arrived without a closing newline.
    if let line = buffer.readSlice(length: buffer.readableBytes), line.readableBytes > 0 {
      context.fireChannelRead(wrapInboundOut(line))
    }
    return .needMoreData
  }
}
