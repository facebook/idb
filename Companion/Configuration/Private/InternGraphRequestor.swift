/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

protocol InternGraphRequestor {
  associatedtype Request: Hashable & Sendable

  func read<FetchResult: Decodable>(request: Request, decoder: JSONDecoder) async throws -> FetchResult
}
