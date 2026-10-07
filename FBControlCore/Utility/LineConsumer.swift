/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// A consumer that splits what it receives on newlines and delivers each line, without its newline.
///
/// End-of-file delivers a trailing chunk with no newline as the last line, and `finishedConsuming`
/// resolves once every line has been delivered.
// SAFETY: `pending` is only touched under `lock`; `FBMutableFuture` is internally synchronized.
public final class LineConsumer: NSObject, DataConsumer, DataConsumerLifecycle, @unchecked Sendable {
  public enum Delivery: Sendable {
    /// Lines are delivered on the thread that consumed the data.
    case synchronous
    /// Lines are delivered in order on `queue`, which must be serial.
    case queue(DispatchQueue)
  }

  private let delivery: Delivery
  private let consumer: (Data) -> Void
  private let lock = NSLock()
  /// `nil` once end-of-file has been consumed.
  private var pending: Data? = Data()
  private let finishedConsumingFuture = FBMutableFuture<NSNull>()

  /// Delivers each line as data.
  public init(delivery: Delivery = .queue(LineConsumer.privateQueue()), dataConsumer: @escaping (Data) -> Void) {
    self.delivery = delivery
    self.consumer = dataConsumer
  }

  /// Delivers each line as a string, or as `"non-utf8"` when the line does not decode.
  public convenience init(delivery: Delivery = .queue(LineConsumer.privateQueue()), consumer: @escaping (String) -> Void) {
    self.init(delivery: delivery) { data in
      consumer(String(data: data, encoding: .utf8) ?? "non-utf8")
    }
  }

  public static func privateQueue() -> DispatchQueue {
    DispatchQueue(label: "com.facebook.FBControlCore.LineConsumer")
  }

  public func consumeData(_ data: Data) {
    lock.withLock {
      guard var buffer = pending else {
        return
      }
      buffer.append(data)
      while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
        deliver(Data(buffer[buffer.startIndex..<newline]))
        buffer.removeSubrange(buffer.startIndex...newline)
      }
      pending = buffer
    }
  }

  public func consumeEndOfFile() {
    lock.withLock {
      guard let buffer = pending else {
        return
      }
      pending = nil
      if !buffer.isEmpty {
        deliver(buffer)
      }
      let finished = finishedConsumingFuture
      switch delivery {
      case .synchronous:
        finished.resolve(withResult: NSNull())
      case let .queue(queue):
        queue.async {
          finished.resolve(withResult: NSNull())
        }
      }
    }
  }

  public var finishedConsuming: FBFuture<NSNull> {
    finishedConsumingFuture.retyped(FBFuture<NSNull>.self)
  }

  private func deliver(_ line: Data) {
    switch delivery {
    case .synchronous:
      consumer(line)
    case let .queue(queue):
      queue.async {
        self.consumer(line)
      }
    }
  }
}
