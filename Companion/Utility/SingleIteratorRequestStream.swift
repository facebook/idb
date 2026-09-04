/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

/// Owns the single `AsyncIterator` of a gRPC request stream.
///
/// grpc-swift's `GRPCAsyncRequestStream` is backed by
/// `NIOThrowingAsyncSequenceProducer`, which fatal-errors if more than one
/// iterator is ever created from it. `AsyncSequence.requiredNext` reads via
/// `first(where:)`, and every `first(where:)` makes a *new* iterator — so any
/// handler that reads more than one request frame straight off the stream
/// (`requestStream.requiredNext` twice) crashes the whole companion on the
/// second read. Wrapping the stream once and reading every frame through this
/// type keeps all reads on one iterator.
final class SingleIteratorRequestStream<S: AsyncSequence>: @unchecked Sendable {
  private var iterator: S.AsyncIterator

  init(_ sequence: S) {
    self.iterator = sequence.makeAsyncIterator()
  }

  func next() async throws -> S.Element? {
    try await iterator.next()
  }

  /// The next element, treating end-of-stream as a precondition failure.
  var requiredNext: S.Element {
    get async throws {
      guard let next = try await next() else {
        throw StreamReadError<S.Element>.nextElementNotProduced
      }
      return next
    }
  }
}
