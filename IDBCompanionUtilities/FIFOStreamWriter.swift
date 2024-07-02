/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

public protocol AsyncStreamWriter {
  associatedtype Value: Sendable

  func send(_ value: Value) async throws
}

/// Wraps any async stream writer and bridges it to synchronous world
/// preserving FIFO order of elements.
public final class FIFOStreamWriter<StreamWriter: AsyncStreamWriter>: @unchecked Sendable {

  private let stream: StreamWriter

  private let semaphore = DispatchSemaphore(value: 0)

  public init(stream: StreamWriter) {
    self.stream = stream
  }

  // We need to please swift concurrency checker, because
  // interop between semaphores and swift concurrency is not compile-time safe
  private class ErrorWrapper: @unchecked Sendable {
    var error: Error?
  }

  /// This method should be called from GCD
  /// Never ever call that from swift concurrency cooperative pool thread, because it is unsafe
  /// and you will violate swift concurrency contract. Doing that may cause deadlock of whole concurrency runtime.
  public func send(_ value: StreamWriter.Value) throws {
    // Implementation is indentionally naive. "Clever" implementation is much harder to understand
    // and gives 0.01 better results on 1000 of elements. We can live pretty happily with
    // that relatively "slow" impl.
    // There is one downside in current implementation - it is blocking and we consume the thread.
    // So we assume that `stream.send` will not live for a long time.

    let errWrapper = ErrorWrapper()
    Task {
      do {
        try await stream.send(value)
      } catch {
        errWrapper.error = error
      }
      semaphore.signal()
    }
    semaphore.wait()

    if let err = errWrapper.error {
      throw err
    }
  }
}
