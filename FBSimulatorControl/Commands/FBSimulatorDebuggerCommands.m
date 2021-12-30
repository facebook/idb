/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorDebuggerCommands.h"

#import "FBSimulator.h"

@interface FBSimulatorDebugServer : NSObject <FBDebugServer>

@property (nonatomic, strong, readonly) FBProcess<NSNull *, id<FBControlCoreLogger>, id<FBControlCoreLogger>> *task;

@end

@implementation FBSimulatorDebugServer

@synthesize lldbBootstrapCommands = _lldbBootstrapCommands;
@synthesize completed = _completed;

- (instancetype)initWithDebugServerTask:(FBProcess<NSNull *, id<FBControlCoreLogger>, id<FBControlCoreLogger>> *)task lldbBootstrapCommands:(NSArray<NSString *> *)lldbBootstrapCommands
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _task = task;
  _lldbBootstrapCommands = lldbBootstrapCommands;

  return self;
}

#pragma mark FBiOSTargetOperation

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-property-ivar"

- (FBFuture<NSNull *> *)completed
{
  FBProcess *task = self.task;
  return [[[task
    statLoc]
    mapReplace:NSNull.null]
    onQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0) respondToCancellation:^{
      return [task sendSignal:SIGTERM backingOffToKillWithTimeout:1 logger:nil];
    }];
}

#pragma clang diagnostic pop

@end

@interface FBSimulatorDebuggerCommands ()

@property (nonatomic, weak, readonly) FBSimulator *simulator;
@property (nonatomic, copy, readonly) NSString *debugServerPath;

@end

@implementation FBSimulatorDebuggerCommands

#pragma mark Initializers

+ (NSString *)debugServerPath
{
  return [[FBXcodeConfiguration
    contentsDirectory]
    stringByAppendingPathComponent:@"SharedFrameworks/LLDB.framework/Resources/debugserver"];
}

+ (instancetype)commandsWithTarget:(FBSimulator *)target
{
  return [[self alloc] initWithSimulator:target debugServerPath:[self debugServerPath]];
}

- (instancetype)initWithSimulator:(FBSimulator *)simulator debugServerPath:(NSString *)debugServerPath
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _simulator = simulator;
  _debugServerPath = debugServerPath;

  return self;
}

#pragma mark FBDebuggerCommands

- (FBFuture<id<FBDebugServer>> *)launchDebugServerForHostApplication:(FBBundleDescriptor *)application port:(in_port_t)port
{
  FBApplicationLaunchConfiguration *configuration = [[FBApplicationLaunchConfiguration alloc]
    initWithBundleID:application.identifier
    bundleName:application.name
    arguments:@[]
    environment:@{}
    waitForDebugger:YES
    io:FBProcessIO.outputToDevNull
    launchMode:FBApplicationLaunchModeFailIfRunning];
  return [[[self.simulator
    launchApplication:configuration]
    onQueue:self.simulator.workQueue fmap:^(id<FBLaunchedApplication> process) {
      return [self debugServerTaskForPort:port processIdentifier:process.processIdentifier];
    }]
    onQueue:self.simulator.workQueue map:^(FBProcess<NSNull *, id<FBControlCoreLogger>, id<FBControlCoreLogger>> *task) {
      NSArray<NSString *> *lldbBootstrapCommands = @[
        [NSString stringWithFormat:@"process connect connect://localhost:%d", port]
      ];
      return [[FBSimulatorDebugServer alloc] initWithDebugServerTask:task lldbBootstrapCommands:lldbBootstrapCommands];
    }];
}

#pragma mark Private

- (FBFuture<FBProcess<NSNull *, id<FBControlCoreLogger>, id<FBControlCoreLogger>> *> *)debugServerTaskForPort:(in_port_t)port processIdentifier:(pid_t)processIdentifier
{
  return [[[[[FBProcessBuilder
    withLaunchPath:self.debugServerPath]
    withArguments:@[[NSString stringWithFormat:@"localhost:%d", port], @"--attach", [NSString stringWithFormat:@"%d", processIdentifier]]]
    withStdOutToLogger:self.simulator.logger]
    withStdErrToLogger:self.simulator.logger]
    start];
}

@end
