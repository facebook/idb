/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Swift-native async/await counterpart of `FBDapServerCommand`.
public protocol AsyncDapServerCommand: AnyObject {

  func launchDapServer(
    _ dapPath: Any,
    stdIn: FBProcessInput<AnyObject>,
    stdOut: any FBDataConsumer
  ) async throws -> FBSubprocess<AnyObject, FBDataConsumer, NSString>
}
