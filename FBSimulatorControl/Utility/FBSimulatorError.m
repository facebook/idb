/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorError.h"

#import <FBControlCore/FBControlCore.h>

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
    extraInfo:@"launchd_is_running" value:@(simulator.launchdProcess != nil)]
    extraInfo:@"launchd_subprocesses" value:[FBCollectionInformation oneLineDescriptionFromArray:simulator.launchdSimSubprocesses atKeyPath:@"shortDescription"]];
}

@end
