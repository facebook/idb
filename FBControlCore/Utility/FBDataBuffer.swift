/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// The non-mutating methods of a buffer.
@objc public protocol FBAccumulatingBuffer: FBDataConsumer, FBDataConsumerLifecycle {
  /// Obtains a copy of the current output data.
  func data() -> Data

  /// Obtains a copy of the current output data.
  func lines() -> [String]
}

/// The mutating methods of a buffer. All methods are fully synchronized.
@objc public protocol FBConsumableBuffer: FBAccumulatingBuffer {
  /// Consume the remainder of the buffer available, returning it as Data.
  func consumeCurrentData() -> Data

  /// Consume the remainder of the buffer available, returning it as a String.
  func consumeCurrentString() -> String?

  /// Consumes an amount of data from the buffer.
  func consumeLength(_ length: UInt) -> Data?

  /// Consumes until data received.
  @objc(consumeUntil:)
  func consume(until terminal: Data) -> Data?

  /// Consume a line if one is available, returning it as Data.
  func consumeLineData() -> Data?

  /// Consume a line if one is available, returning it as a String.
  func consumeLineString() -> String?
}

/// A Consumable buffer that also allows forwarding and notifying.
@objc public protocol FBNotifyingBuffer: FBConsumableBuffer {
  /// Forwards to another data consumer, notifying every time a terminal is passed.
  func consume(_ consumer: FBDataConsumer, onQueue queue: DispatchQueue?, untilTerminal terminal: Data, error: NSErrorPointer) -> Bool

  /// Notifies when there has been consumption to a terminal.
  @objc(consumeAndNotifyWhen:)
  func consumeAndNotify(when terminal: Data) -> FBFuture<NSData>

  /// Consumes based upon a fixed-length header, that can be parsed.
  func consumeHeaderLength(_ headerLength: UInt, derivedLength: @escaping (Data) -> UInt) -> FBFuture<NSData>
}

/// Internal forwarding protocol used by FBDataBuffer implementations.
@objc public protocol FBDataBuffer_Forwarder: NSObjectProtocol {
  func run(_ buffer: FBConsumableBuffer)
  var consumer: FBDataConsumer { get }
}
