/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// A single JSON-RPC 2.0 response sent back over a companion connection. Exactly
/// one of `result` / `error` is set. `result` is method-specific; for a `cli`
/// request it is an object `{ "stdout": String, "exitCode": Int }`.
public struct JSONRPCResponse: Codable, Equatable, Sendable {
  public let jsonrpc: String
  public let id: JSONValue?
  public let result: JSONValue?
  public let error: JSONValue?

  public init(id: JSONValue?, result: JSONValue? = nil, error: JSONValue? = nil) {
    self.jsonrpc = "2.0"
    self.id = id
    self.result = result
    self.error = error
  }
}
