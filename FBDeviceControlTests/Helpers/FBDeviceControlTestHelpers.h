// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

#import <FBControlCore/FBControlCore.h>
#import <FBDeviceControl/FBAMDefines.h>

NS_ASSUME_NONNULL_BEGIN

/// Wraps +[FBFuture futureWithFutures:] which is NS_SWIFT_UNAVAILABLE.
FBFuture<NSArray *> *FBFutureFromArray(NSArray<FBFuture *> *futures);

/// Returns a zero-initialized AMDCalls struct (needed because Swift can't zero-init
/// structs with _Nonnull function pointer fields).
static inline AMDCalls FBCreateZeroedAMDCalls(void) {
  AMDCalls calls = {};
  return calls;
}

NS_ASSUME_NONNULL_END
