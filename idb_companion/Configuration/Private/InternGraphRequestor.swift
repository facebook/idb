// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

import Foundation

protocol InternGraphRequestor {
  associatedtype Request: Hashable & Sendable

  func read<FetchResult: Decodable>(request: Request, decoder: JSONDecoder) async throws -> FetchResult
}
