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

  /// We have quite a lot of grpc request streams where we read request N constant number of times and do not need foreach loop. But pure next produces optinal by design.
  /// This small tweak just saves us from lots of boilerplate of unwrapping the optionals everywhere
  var requiredNext: Element {
    get async throws {
      guard let next = try await first(where: { _ in true }) else {
        throw StreamReadError<Element>.nextElementNotProduced
      }
      return next
    }
  }
}
