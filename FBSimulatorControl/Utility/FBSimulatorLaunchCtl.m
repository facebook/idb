/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorLaunchCtl.h"

#import "FBProcessInfo.h"
#import "FBSimulatorControlGlobalConfiguration.h"
#import "FBProcessLaunchConfiguration+Helpers.h"
#import "FBProcessLaunchConfiguration.h"
#import "FBSimDeviceWrapper.h"
#import "FBSimulator.h"
#import "FBSimulator+Helpers.h"
#import "FBSimulatorApplication.h"
#import "FBSimulatorError.h"
#import "NSRunLoop+SimulatorControlAdditions.h"

@interface FBSimulatorLaunchCtl ()

@property (nonatomic, strong, readonly) FBSimulator *simulator;

@end

@implementation FBSimulatorLaunchCtl

#pragma mark Initializers

+ (instancetype)withSimulator:(FBSimulator *)simulator
{
  return [[self alloc] initWithSimulator:simulator];
}

- (instancetype)initWithSimulator:(FBSimulator *)simulator
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _simulator = simulator;

  return self;
}

#pragma mark Public

- (BOOL)processIsRunningOnSimulator:(FBProcessInfo *)process error:(NSError **)error
{
  // Construct a Launch Configuration for launchctl.
  // launchctl requires that it's 1st argument is the name 'launchctl'.
  FBAgentLaunchConfiguration *launchConfiguration = [FBAgentLaunchConfiguration
    configurationWithBinary:FBSimulatorBinary.launchCtl
    arguments:@[@"launchctl", @"list"]
    environment:@{}];

  // Construct a pipe to stdout and read asynchronously from it.
  // Synchronize on the mutable string.
  NSPipe *stdOutPipe = [NSPipe pipe];
  NSDictionary *options = [launchConfiguration simDeviceLaunchOptionsWithStdOut:stdOutPipe.fileHandleForWriting stdErr:nil];
  NSMutableString *haystack = [NSMutableString string];
  stdOutPipe.fileHandleForReading.readabilityHandler = ^(NSFileHandle *handle) {
    NSString *string = [[NSString alloc] initWithData:handle.availableData encoding:NSUTF8StringEncoding];
    @synchronized(haystack)
    {
      [haystack appendString:string];
    }
  };

  // Spawn the Process.
  NSError *innerError = nil;
  pid_t processIdentifier = [self.simulator.simDeviceWrapper
    spawnShortRunningWithPath:launchConfiguration.agentBinary.path
    options:options
    timeout:FBSimulatorControlGlobalConfiguration.fastTimeout
    error:&innerError];
  if (processIdentifier <= 0) {
    return [[[FBSimulatorError
      describeFormat:@"Could not get launchctl info for process %@ as the spawn of launchctl failed", process.shortDescription]
      causedBy:innerError]
      failBool:error];
  }

  // Wait for the data to exist.
  NSString *needle = [NSString stringWithFormat:@"%d", process.processIdentifier];
  return [NSRunLoop.currentRunLoop spinRunLoopWithTimeout:FBSimulatorControlGlobalConfiguration.fastTimeout untilTrue:^BOOL{
    @synchronized(haystack)
    {
      return [haystack containsString:needle];
    }
  }];
}

@end
