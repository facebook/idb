/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorXCTestProcessExecutor.h"

#import <FBControlCore/FBControlCore.h>

#import "FBAgentLaunchStrategy.h"
#import "FBSimulatorAgentOperation.h"
#import "FBSimulator.h"

@interface FBSimulatorXCTestProcessExecutor ()

@property (nonatomic, strong, readonly) FBSimulator *simulator;
@property (nonatomic, strong, readonly) FBXCTestShimConfiguration *shims;

@end

@implementation FBSimulatorXCTestProcessExecutor

#pragma mark Initializers

+ (instancetype)executorWithSimulator:(FBSimulator *)simulator shims:(FBXCTestShimConfiguration *)shims
{
  return [[self alloc] initWithSimulator:simulator shims:shims];
}

- (instancetype)initWithSimulator:(FBSimulator *)simulator shims:(FBXCTestShimConfiguration *)shims
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _simulator = simulator;
  _shims = shims;

  return self;
}

#pragma mark Public

- (FBFuture<FBSimulatorAgentOperation *> *)startProcessWithLaunchPath:(NSString *)launchPath arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment stdOutConsumer:(id<FBDataConsumer>)stdOutConsumer stdErrConsumer:(id<FBDataConsumer>)stdErrConsumer
{
  FBProcessIO *io = [[FBProcessIO alloc]
    initWithStdIn:nil
    stdOut:[FBProcessOutput outputForDataConsumer:stdOutConsumer]
    stdErr:[FBProcessOutput outputForDataConsumer:stdErrConsumer]];

  FBProcessSpawnConfiguration *configuration = [[FBProcessSpawnConfiguration alloc]
   initWithLaunchPath:launchPath
   arguments:arguments
   environment:environment
   io:io
   mode:FBProcessSpawnModePosixSpawn];

  return [[FBAgentLaunchStrategy
    strategyWithSimulator:self.simulator]
    launchAgent:configuration];
}

- (NSString *)xctestPath
{
  return [FBXcodeConfiguration.developerDirectory
    stringByAppendingPathComponent:@"Platforms/iPhoneSimulator.platform/Developer/Library/Xcode/Agents/xctest"];
}

- (NSString *)shimPath
{
  return self.shims.iOSSimulatorTestShimPath;
}

- (NSString *)queryShimPath
{
  return self.shims.iOSSimulatorTestShimPath;
}

- (dispatch_queue_t)workQueue
{
  return self.simulator.workQueue;
}

@end
