/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

private class FBiOSTargetOperationWrapper: NSObject, FBiOSTargetOperation {

  let completed: FBFuture<NSNull>

  init(completed: FBFuture<NSNull>) {
    self.completed = completed
    super.init()
  }
}

/// C function replacement: called from the @_cdecl function below.
@_cdecl("FBiOSTargetOperationFromFuture")
func FBiOSTargetOperationFromFuture(_ completed: FBFuture<NSNull>) -> FBiOSTargetOperation {
  return FBiOSTargetOperationWrapper(completed: completed)
}
