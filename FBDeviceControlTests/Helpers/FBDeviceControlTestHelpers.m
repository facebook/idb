// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

#import "FBDeviceControlTestHelpers.h"

FBFuture<NSArray *> *FBFutureFromArray(NSArray<FBFuture *> *futures) {
  return [FBFuture futureWithFutures:futures];
}
