/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Swift-native async/await counterpart of `FBProcessSpawnCommands`.
public protocol AsyncProcessSpawnCommands: AnyObject {

  func launchProcess(
    _ configuration: FBProcessSpawnConfiguration
  ) async throws -> FBSubprocess<AnyObject, AnyObject, AnyObject>
}
