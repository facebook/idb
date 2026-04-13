/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore

/// Helpers to work around Swift limitations with ObjC APIs.
enum FBFutureTestHelpers {

  static func combineFutures(_ futures: [Any]) -> FBFuture<NSArray> {
    return FBFuture<AnyObject>.combine(futures as! [FBFuture<AnyObject>])
  }
}
