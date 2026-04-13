// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

import FBControlCore

/// Helpers to work around Swift limitations with ObjC APIs.
enum FBFutureTestHelpers {

  static func combineFutures(_ futures: [Any]) -> FBFuture<NSArray> {
    return FBFuture<AnyObject>.combine(futures as! [FBFuture<AnyObject>])
  }
}
