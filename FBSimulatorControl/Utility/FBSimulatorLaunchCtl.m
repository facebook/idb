/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorLaunchCtl.h"

#import <FBControlCore/FBControlCore.h>

#import "FBProcessLaunchConfiguration+Helpers.h"
#import "FBProcessLaunchConfiguration.h"
#import "FBSimDeviceWrapper.h"
#import "FBSimulator+Helpers.h"
#import "FBSimulator.h"
#import "FBSimulatorError.h"

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
  NSString *needle = [NSString stringWithFormat:@"%d", process.processIdentifier];
  NSString *haystack = [self runWithArguments:@[@"list"] error:error];
  return [haystack containsString:needle];
}

#pragma mark Private

- (NSString *)runWithArguments:(NSArray<NSString *> *)arguments error:(NSError **)error
{
  // Construct a Launch Configuration for launchctl we'll use the 'list' command.
  FBAgentLaunchConfiguration *launchConfiguration = [FBAgentLaunchConfiguration
    configurationWithBinary:FBBinaryDescriptor.launchCtl
    arguments:arguments
    environment:@{}
    options:0];

  // Construct a pipe to stdout and read asynchronously from it.
  // Synchronize on the mutable string.
  NSPipe *stdOutPipe = [NSPipe pipe];
  NSDictionary *options = [launchConfiguration simDeviceLaunchOptionsWithStdOut:stdOutPipe.fileHandleForWriting stdErr:nil];

  NSError *innerError = nil;
  pid_t processIdentifier = [self.simulator.simDeviceWrapper
    spawnShortRunningWithPath:launchConfiguration.agentBinary.path
    options:options
    timeout:FBControlCoreGlobalConfiguration.fastTimeout
    error:&innerError];
  if (processIdentifier <= 0) {
    return [[[FBSimulatorError
      describeFormat:@"Running launchctl %@ failed", [FBCollectionInformation oneLineDescriptionFromArray:arguments]]
      causedBy:innerError]
      fail:error];
  }
  [stdOutPipe.fileHandleForWriting closeFile];
  NSData *data = [stdOutPipe.fileHandleForReading readDataToEndOfFile];
  NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
  return [output copy];
}

@end
