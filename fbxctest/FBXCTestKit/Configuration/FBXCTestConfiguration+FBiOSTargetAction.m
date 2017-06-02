/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBXCTestConfiguration+FBiOSTargetAction.h"

#import <FBSimulatorControl/FBSimulatorControl.h>
#import <XCTestBootstrap/XCTestBootstrap.h>

#import "FBXCTestContext.h"
#import "FBXCTestBaseRunner.h"

@implementation FBXCTestConfiguration (FBiOSTargetAction)


+ (FBiOSTargetActionType)actionType
{
  return FBiOSTargetActionTypeFBXCTest;
}

- (BOOL)runWithTarget:(id<FBiOSTarget>)target delegate:(id<FBiOSTargetActionDelegate>)delegate error:(NSError **)error
{
  FBSimulator *simulator = (FBSimulator *) target;
  if (![simulator isKindOfClass:FBSimulator.class]) {
    return [[FBXCTestError
      describeFormat:@"%@ is not a Simulator, so cannot run fbxctest", simulator]
      failBool:error];
  }

  FBXCTestContext *context = [FBXCTestContext contextWithSimulator:simulator reporter:nil logger:nil];
  FBXCTestBaseRunner *runner = [FBXCTestBaseRunner testRunnerWithConfiguration:self context:context];
  return [runner executeWithError:error];
}

@end
