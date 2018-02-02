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

#import "FBMacDevice.h"
#import "FBXCTestConfiguration.h"
#import "FBXCTestProcess.h"
#import "FBXCTestShimConfiguration.h"

@interface FBMacXCTestProcessExecutor ()

@property (nonatomic, strong, readonly) FBMacDevice *macDevice;
@property (nonatomic, strong, readonly) FBXCTestConfiguration *configuration;

@end

@implementation FBMacXCTestProcessExecutor

#pragma mark Initializers

+ (instancetype)executorWithMacDevice:(FBMacDevice *)macDevice configuration:(FBXCTestConfiguration *)configuration
{
  return [[self alloc] initWithMacDevice:macDevice configuration:configuration];
}

- (instancetype)initWithMacDevice:(FBMacDevice *)macDevice configuration:(FBXCTestConfiguration *)configuration
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _macDevice = macDevice;
  _configuration = configuration;

  return self;
}

#pragma mark FBXCTestProcessExecutor Implementation

- (FBFuture<FBTask *> *)startProcess:(FBXCTestProcess *)process
{
  return [[[[[[FBTaskBuilder
    withLaunchPath:process.launchPath]
    withArguments:process.arguments]
    withEnvironment:process.environment]
    withStdOutConsumer:process.stdOutConsumer]
    withStdErrConsumer:process.stdErrConsumer]
    start];
}

- (NSString *)xctestPath
{
  return [FBXcodeConfiguration.developerDirectory
    stringByAppendingPathComponent:@"usr/bin/xctest"];
}

- (NSString *)shimPath
{
  return self.configuration.shims.macOSTestShimPath;
}

- (NSString *)queryShimPath
{
  return self.configuration.shims.macOSQueryShimPath;
}

- (dispatch_queue_t)workQueue
{
  return self.macDevice.workQueue;
}

@end
