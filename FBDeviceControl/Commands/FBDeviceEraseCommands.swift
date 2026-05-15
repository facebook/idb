/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

// MARK: - FBDevice+AsyncEraseCommands

extension FBDevice: AsyncEraseCommands {

  public func erase() async throws {
    try await bridgeFBFutureVoid(eraseCommands().erase())
  }
}
