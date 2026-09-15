/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionUtilities
import GRPCCore

extension RPCWriter: @retroactive AsyncStreamWriter {
  public typealias Value = Element

  @inlinable
  public func send(_ value: Value) async throws {
    try await write(value)
  }
}
