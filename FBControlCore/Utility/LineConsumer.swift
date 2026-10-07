/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// A consumer that splits what it receives on newlines and delivers each line, without its newline.
///
/// A trailing chunk with no newline is never delivered, and `finishedConsuming` resolves on end-of-file
/// without waiting for lines still queued for delivery.
// SAFETY: `pending` is only touched under `lock`; `FBMutableFuture` is internally synchronized.
public final class LineConsumer: NSObject, DataConsumer, DataConsumerLifecycle, @unchecked Sendable {
  public enum Delivery: Sendable {
    /// Lines are delivered on the thread that consumed the data.
    case synchronous
    /// Lines are delivered in order on `queue`.
    case queue(DispatchQueue)
  }

  private let delivery: Delivery
  private let consumer: (Data) -> Void
  private let lock = NSLock()
  private var pending = Data()
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
      guard !finishedConsumingFuture.hasCompleted else {
        return
      }
      pending.append(data)
      while let newline = pending.firstIndex(of: UInt8(ascii: "\n")) {
        let line = Data(pending[pending.startIndex..<newline])
        pending.removeSubrange(pending.startIndex...newline)
        deliver(line)
      }
    }
  }

  public func consumeEndOfFile() {
    lock.withLock {
      guard !finishedConsumingFuture.hasCompleted else {
        return
      }
      finishedConsumingFuture.resolve(withResult: NSNull())
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
