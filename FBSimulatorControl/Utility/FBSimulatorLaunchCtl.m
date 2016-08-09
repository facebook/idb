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

- (nullable NSString *)serviceNameForProcess:(FBProcessInfo *)process error:(NSError **)error
{
  NSString *text = [self runWithArguments:@[@"list"] error:error];
  if (!text) {
    return nil;
  }
  FBLogSearchPredicate *predicate = [FBLogSearchPredicate substrings:@[@(process.processIdentifier).stringValue]];
  FBLogSearch *search = [FBLogSearch withText:text predicate:predicate];
  NSString *line = search.firstMatchingLine;
  if (!line) {
    return [[FBSimulatorError
      describeFormat:@"No Matching processes for %@", process.shortDescription]
      fail:error];
  }
  NSArray<NSString *> *words = [line componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
  if (words.count != 3) {
    return [[FBSimulatorError
      describeFormat:@"Output does not have exactly three words: %@", [FBCollectionInformation oneLineDescriptionFromArray:words]]
      fail:error];
  }
  return [words lastObject];
}

- (nullable NSString *)stopServiceWithName:(NSString *)serviceName error:(NSError **)error
{
  NSError *innerError = nil;
  if (![self runWithArguments:@[@"stop", serviceName] error:&innerError]) {
    return [[[FBSimulatorError
      describeFormat:@"Failed to stop service %@", serviceName]
      causedBy:innerError]
      fail:error];
  }
  return serviceName;
}

- (BOOL)processIsRunningOnSimulator:(FBProcessInfo *)process error:(NSError **)error
{
  return [self serviceNameForProcess:process error:error] != nil;
}

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
