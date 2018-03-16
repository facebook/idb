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
@property (nonatomic, strong, readonly) FBXCTestShimConfiguration *shims;

@end

@implementation FBMacXCTestProcessExecutor

#pragma mark Initializers

+ (instancetype)executorWithMacDevice:(FBMacDevice *)macDevice shims:(FBXCTestShimConfiguration *)shims
{
  return [[self alloc] initWithMacDevice:macDevice shims:shims];
}

- (instancetype)initWithMacDevice:(FBMacDevice *)macDevice shims:(FBXCTestShimConfiguration *)shims
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _macDevice = macDevice;
  _shims = shims;

  return self;
}

#pragma mark FBXCTestProcessExecutor Implementation

- (FBFuture<FBTask *> *)startProcessWithLaunchPath:(NSString *)launchPath arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment stdOutConsumer:(id<FBFileConsumer>)stdOutConsumer stdErrConsumer:(id<FBFileConsumer>)stdErrConsumer
{
  return [[[[[[FBTaskBuilder
    withLaunchPath:launchPath]
    withArguments:arguments]
    withEnvironment:environment]
    withStdOutConsumer:stdOutConsumer]
    withStdErrConsumer:stdErrConsumer]
    start];
}

- (NSString *)xctestPath
{
  return [FBXcodeConfiguration.developerDirectory
    stringByAppendingPathComponent:@"usr/bin/xctest"];
}

- (NSString *)shimPath
{
  return self.shims.macOSTestShimPath;
}

- (NSString *)queryShimPath
{
  return self.shims.macOSQueryShimPath;
}

- (dispatch_queue_t)workQueue
{
  return self.macDevice.workQueue;
}

@end
