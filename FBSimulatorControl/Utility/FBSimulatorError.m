/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorError.h"

#import <FBControlCore/FBControlCore.h>

#import "FBSimulator+Helpers.h"
#import "FBSimulator.h"

NSString *const FBSimulatorControlErrorDomain = @"com.facebook.FBSimulatorControl";

@interface FBSimulatorError ()

@property (nonatomic, copy, readwrite) NSString *describedAs;
@property (nonatomic, copy, readwrite) NSError *cause;
@property (nonatomic, strong, readwrite) id<FBControlCoreLogger> logger;
@property (nonatomic, strong, readwrite) NSMutableDictionary *additionalInfo;
@property (nonatomic, assign, readwrite) BOOL describeRecursively;

@end

@implementation FBSimulatorError

- (instancetype)init
{
  self = [super init];
  if (!self) {
    return nil;
  }

  [self inDomain:FBSimulatorControlErrorDomain];

  return self;
}

- (instancetype)inSimulator:(FBSimulator *)simulator
{
  return [[self
    extraInfo:@"launchd_is_running" value:@(simulator.launchdSimProcess != nil)]
    extraInfo:@"launchd_subprocesses" value:[FBCollectionInformation oneLineDescriptionFromArray:simulator.launchdSimSubprocesses atKeyPath:@"shortDescription"]];
}

@end
