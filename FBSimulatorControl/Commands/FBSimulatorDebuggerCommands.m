/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorDebuggerCommands.h"

#import "FBSimulator.h"

@interface FBSimulatorDebugServer : NSObject <FBDebugServer>

@property (nonatomic, strong, readonly) FBTask<NSNull *, id<FBControlCoreLogger>, id<FBControlCoreLogger>> *task;

@end

@implementation FBSimulatorDebugServer

@synthesize lldbBootstrapCommands = _lldbBootstrapCommands;
@synthesize completed = _completed;

- (instancetype)initWithDebugServerTask:(FBTask<NSNull *, id<FBControlCoreLogger>, id<FBControlCoreLogger>> *)task lldbBootstrapCommands:(NSArray<NSString *> *)lldbBootstrapCommands
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _task = task;
  _lldbBootstrapCommands = lldbBootstrapCommands;

  return self;
}

#pragma mark FBiOSTargetContinuation

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-property-ivar"
- (FBFuture<NSNull *> *)completed
{
  return [self.task.completed mapReplace:NSNull.null];
}
#pragma clang diagnostic pop

- (FBiOSTargetFutureType)futureType
{
  return @"debug";
}

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
  FBApplicationLaunchConfiguration *configuration = [FBApplicationLaunchConfiguration
    configurationWithApplication:application arguments:@[]
    environment:@{}
    waitForDebugger:YES
    output:FBProcessOutputConfiguration.outputToDevNull];
  return [[[self.simulator
    launchApplication:configuration]
    onQueue:self.simulator.workQueue fmap:^(id<FBLaunchedProcess> process) {
      return [self debugServerTaskForPort:port processIdentifier:process.processIdentifier];
    }]
    onQueue:self.simulator.workQueue map:^(FBTask<NSNull *, id<FBControlCoreLogger>, id<FBControlCoreLogger>> *task) {
      NSArray<NSString *> *lldbBootstrapCommands = @[
        [NSString stringWithFormat:@"process connect connect://localhost:%d", port]
      ];
      return [[FBSimulatorDebugServer alloc] initWithDebugServerTask:task lldbBootstrapCommands:lldbBootstrapCommands];
    }];
}

#pragma mark Private

- (FBFuture<FBTask<NSNull *, id<FBControlCoreLogger>, id<FBControlCoreLogger>> *> *)debugServerTaskForPort:(in_port_t)port processIdentifier:(pid_t)processIdentifier
{
  return [[[[[FBTaskBuilder
    withLaunchPath:self.debugServerPath]
    withArguments:@[[NSString stringWithFormat:@"localhost:%d", port], @"--attach", [NSString stringWithFormat:@"%d", processIdentifier]]]
    withStdOutToLogger:self.simulator.logger]
    withStdErrToLogger:self.simulator.logger]
    start];
}

@end
