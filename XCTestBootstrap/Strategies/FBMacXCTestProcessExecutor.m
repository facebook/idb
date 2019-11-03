/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
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

- (FBFuture<id<FBLaunchedProcess>> *)startProcessWithLaunchPath:(NSString *)launchPath arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment stdOutConsumer:(id<FBDataConsumer>)stdOutConsumer stdErrConsumer:(id<FBDataConsumer>)stdErrConsumer
{
  return (FBFuture<id<FBLaunchedProcess>> *) [[[[[[FBTaskBuilder
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
