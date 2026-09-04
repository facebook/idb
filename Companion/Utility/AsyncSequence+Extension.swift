/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import GRPC

enum StreamReadError<Element>: Error, GRPCStatusTransformable {
  case nextElementNotProduced

  func makeGRPCStatus() -> GRPCStatus {
    switch self {
    case .nextElementNotProduced:
      return GRPCStatus(code: .failedPrecondition, message: "Expected next element of type \(Element.self)")
    }
  }
}

extension AsyncSequence {

  /// The next element, throwing `failedPrecondition` instead of returning nil when the stream has ended.
  var requiredNext: Element {
    get async throws {
      guard let next = try await first(where: { _ in true }) else {
        throw StreamReadError<Element>.nextElementNotProduced
      }
      return next
    }
  }
}
