/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBMacXCTestProcessExecutor.h"

#import <FBControlCore/FBControlCore.h>

#import "FBXCTestConfiguration.h"
#import "FBXCTestShimConfiguration.h"
#import "FBXCTestProcess.h"

@interface FBMacXCTestProcessExecutor ()

@property (nonatomic, strong, readonly) FBXCTestConfiguration *configuration;

@end

@implementation FBMacXCTestProcessExecutor

@synthesize workQueue = _workQueue;

+ (instancetype)executorWithConfiguration:(FBXCTestConfiguration *)configuration workQueue:(dispatch_queue_t)workQueue
{
  return [[self alloc] initWithConfiguration:configuration workQueue:workQueue];
}

- (instancetype)initWithConfiguration:(FBXCTestConfiguration *)configuration workQueue:(dispatch_queue_t)workQueue
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _configuration = configuration;
  _workQueue = workQueue;

  return self;
}

- (FBFuture<id<FBLaunchedProcess>> *)startProcess:(FBXCTestProcess *)process
{
  FBTask *task = [[[[[[FBTaskBuilder
    withLaunchPath:process.launchPath]
    withArguments:process.arguments]
    withEnvironment:process.environment]
    withStdOutConsumer:process.stdOutReader]
    withStdErrConsumer:process.stdErrReader]
    run];

  return [FBFuture futureWithResult:task];
}

- (NSString *)shimPath
{
  return self.configuration.shims.macOSTestShimPath;
}

- (NSString *)queryShimPath
{
  return self.configuration.shims.macOSQueryShimPath;
}

@end
