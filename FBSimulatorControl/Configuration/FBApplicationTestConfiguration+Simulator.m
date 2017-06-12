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

+ (FBiOSTargetActionType)actionType
{
  return FBiOSTargetActionTypeApplicationTest;
}

- (BOOL)runWithTarget:(id<FBiOSTarget>)target delegate:(id<FBiOSTargetActionDelegate>)delegate error:(NSError **)error
{
  FBSimulator *simulator = (FBSimulator *) target;
  if (![simulator isKindOfClass:FBSimulator.class]) {
    return [[FBXCTestError
      describeFormat:@"%@ is not a Simulator, so cannot run fbxctest", simulator]
      failBool:error];
  }
  id<FBFileConsumer> consumer = [delegate obtainConsumerForAction:self target:target];
  FBJSONTestReporter *reporter = [[FBJSONTestReporter alloc]
    initWithTestBundlePath:self.testBundlePath
    testType:self.testType
    logger:target.logger
    fileConsumer:consumer];

  return [simulator runApplicationTest:self reporter:reporter error:error];
}

@end
