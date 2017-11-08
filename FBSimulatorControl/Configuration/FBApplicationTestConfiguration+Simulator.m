/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBApplicationTestConfiguration+Simulator.h"

#import "FBSimulator.h"

FBiOSTargetActionType const FBiOSTargetActionTypeApplicationTest = FBXCTestTypeApplicationTestValue;

@implementation FBApplicationTestConfiguration (Simulator)

- (FBiOSTargetActionType)actionType
{
  return FBiOSTargetActionTypeApplicationTest;
}

- (FBFuture<FBiOSTargetActionType> *)runWithTarget:(id<FBiOSTarget>)target consumer:(id<FBFileConsumer>)consumer reporter:(id<FBEventReporter>)reporter awaitableDelegate:(id<FBiOSTargetActionAwaitableDelegate>)awaitableDelegate
{
  FBSimulator *simulator = (FBSimulator *) target;
  if (![simulator isKindOfClass:FBSimulator.class]) {
    return [[FBXCTestError
      describeFormat:@"%@ is not a Simulator, so cannot run fbxctest", simulator]
      failFuture];
  }
  FBJSONTestReporter *testReporter = [[FBJSONTestReporter alloc]
    initWithTestBundlePath:self.testBundlePath
    testType:self.testType
    logger:target.logger
    fileConsumer:consumer];

  return [[simulator runApplicationTest:self reporter:testReporter] mapReplace:self.actionType];
}

@end
