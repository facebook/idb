/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <FBControlCore/FBControlCore.h>
#import <FBDeviceControl/FBAMDefines.h>

/// Wraps +[FBFuture futureWithFutures:] which is NS_SWIFT_UNAVAILABLE.
FBFuture<NSArray *> *_Nonnull FBFutureFromArray(NSArray<FBFuture *> * _Nonnull futures);

/// Returns a zero-initialized AMDCalls struct (needed because Swift can't zero-init
/// structs with _Nonnull function pointer fields).
static inline AMDCalls FBCreateZeroedAMDCalls(void)
{
  AMDCalls calls = {};
  return calls;
}
