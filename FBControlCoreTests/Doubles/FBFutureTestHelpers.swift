// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

import FBControlCore

/// Helpers to work around Swift limitations with ObjC APIs.
/// `futureWithFutures:` is NS_SWIFT_UNAVAILABLE, so we call it via the ObjC runtime.
enum FBFutureTestHelpers {

  static func combineFutures(_ futures: [Any]) -> FBFuture<NSArray> {
    let sel = NSSelectorFromString("futureWithFutures:")
    let method = FBFuture<NSArray>.method(for: sel)
    typealias CombineFn = @convention(c) (AnyClass, Selector, NSArray) -> FBFuture<NSArray>
    let fn = unsafeBitCast(method, to: CombineFn.self)
    return fn(FBFuture<NSArray>.self, sel, futures as NSArray)
  }
}
