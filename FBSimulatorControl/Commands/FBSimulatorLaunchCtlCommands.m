/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorLaunchCtlCommands.h"

#import <CoreSimulator/SimDevice.h>
#import <CoreSimulator/SimRuntime.h>

#import <FBControlCore/FBControlCore.h>

#import "FBAgentLaunchStrategy.h"
#import "FBSimulator+Private.h"
#import "FBSimulator.h"
#import "FBSimulatorProcessFetcher.h"
#import "FBSimulatorError.h"

@interface FBSimulatorLaunchCtlCommands ()

@property (nonatomic, strong, readonly) FBSimulator *simulator;
@property (nonatomic, strong, readonly) FBBinaryDescriptor *launchCtlBinary;

- (instancetype)initWithSimulator:(FBSimulator *)simulator launchCtlBinary:(FBBinaryDescriptor *)launchCtlBinary;

@end

@implementation FBSimulatorLaunchCtlCommands

#pragma mark Initializers

+ (FBBinaryDescriptor *)launchCtlBinaryForSimulator:(FBSimulator *)simulator error:(NSError **)error
{
  NSString *path = [[simulator.device.runtime.root
    stringByAppendingPathComponent:@"bin"]
    stringByAppendingPathComponent:@"launchctl"];
  return [FBBinaryDescriptor binaryWithPath:path error:error];
}

+ (instancetype)commandsWithTarget:(FBSimulator *)target
{
  NSError *error = nil;
  FBBinaryDescriptor *launchCtlBinary = [self launchCtlBinaryForSimulator:target error:&error];
  NSAssert(launchCtlBinary, @"Could not find path for launchctl binary with error %@", error);
  return [[FBSimulatorLaunchCtlCommands alloc] initWithSimulator:target launchCtlBinary:launchCtlBinary];
}

- (instancetype)initWithSimulator:(FBSimulator *)simulator launchCtlBinary:(FBBinaryDescriptor *)launchCtlBinary
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _simulator = simulator;
  _launchCtlBinary = launchCtlBinary;

  return self;
}

#pragma mark Processes

- (NSArray<FBProcessInfo *> *)launchdSimSubprocesses
{
  FBProcessInfo *launchdSim = self.simulator.launchdProcess;
  if (!launchdSim) {
    return @[];
  }
  return [self.simulator.processFetcher.processFetcher subprocessesOf:launchdSim.processIdentifier];
}

#pragma mark Querying Services

- (nullable NSString *)serviceNameForProcess:(FBProcessInfo *)process error:(NSError **)error
{
  return [self serviceNameForSubstring:@(process.processIdentifier).stringValue processIdentifierOut:nil error:error];
}

- (nullable NSString *)serviceNameForBundleID:(NSString *)bundleID processIdentifierOut:(pid_t *)processIdentifierOut error:(NSError **)error
{
  return [self serviceNameForSubstring:bundleID processIdentifierOut:processIdentifierOut error:error];
}

- (BOOL)processIsRunningOnSimulator:(FBProcessInfo *)process error:(NSError **)error
{
  return [self serviceNameForProcess:process error:error] != nil;
}

#pragma mark Public

- (nullable NSDictionary<NSString *, id> *)listServicesWithError:(NSError **)error
{
  NSString *text = [self runWithArguments:@[@"list"] error:error];
  if (!text) {
    return nil;
  }

  NSArray<NSString *> *lines = [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
  if (lines.count < 2) {
    return [[FBSimulatorError
      describeFormat:@"Insufficient number of lines from output '%@'", text]
      fail:error];
  }
  lines = [lines subarrayWithRange:NSMakeRange(1, lines.count -1)];

  NSMutableDictionary<NSString *, id> *services = [NSMutableDictionary dictionary];
  for (NSString *line in lines) {
    if (line.length == 0) {
      continue;
    }
    pid_t processIdentifier = -1;
    NSError *innerError = nil;
    NSString *serviceName = [self.class extractServiceNameFromListLine:line processIdentifierOut:&processIdentifier error:&innerError];
    if (!serviceName) {
      return [FBSimulatorError failWithError:innerError errorOut:error];
    }
    services[serviceName] = processIdentifier > 0 ? @(processIdentifier) : NSNull.null;
  }
  return [services copy];
}

#pragma mark Manipulating Services

- (nullable NSString *)stopServiceWithName:(NSString *)serviceName error:(NSError **)error
{
  NSError *innerError = nil;
  if (![self runWithArguments:@[@"stop", serviceName] error:&innerError]) {
    return [[[FBSimulatorError
      describeFormat:@"Failed to stop service '%@'", serviceName]
      causedBy:innerError]
      fail:error];
  }
  return serviceName;
}

- (nullable NSString *)startServiceWithName:(NSString *)serviceName error:(NSError **)error
{
  NSError *innerError = nil;
  if (![self runWithArguments:@[@"start", serviceName] error:&innerError]) {
    return [[[FBSimulatorError
      describeFormat:@"Failed to start service '%@'", serviceName]
      causedBy:innerError]
      fail:error];
  }
  return serviceName;
}

#pragma mark Private

- (nullable NSString *)serviceNameForSubstring:(NSString *)substring processIdentifierOut:(pid_t *)processIdentifierOut error:(NSError **)error
{
  NSString *text = [self runWithArguments:@[@"list"] error:error];
  if (!text) {
    return nil;
  }
  FBLogSearchPredicate *predicate = [FBLogSearchPredicate substrings:@[substring]];
  FBLogSearch *search = [FBLogSearch withText:text predicate:predicate];
  NSString *line = search.firstMatchingLine;
  if (!line) {
    return [[FBSimulatorError
      describeFormat:@"No Matching processes for %@", substring]
      fail:error];
  }
  return [self.class extractServiceNameFromListLine:line processIdentifierOut:processIdentifierOut error:error];
}

+ (nullable NSString *)extractServiceNameFromListLine:(NSString *)line processIdentifierOut:(pid_t *)processIdentifierOut error:(NSError **)error
{
  NSArray<NSString *> *words = [line componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
  if (words.count != 3) {
    return [[FBSimulatorError
      describeFormat:@"Output does not have exactly three words: %@", [FBCollectionInformation oneLineDescriptionFromArray:words]]
      fail:error];
  }
  NSString *serviceName = [words lastObject];
  NSString *processIdentifierString = [words firstObject];
  if ([processIdentifierString isEqualToString:@"-"]) {
    if (processIdentifierOut) {
      *processIdentifierOut = -1;
    }
    return serviceName;
  }

  NSInteger processIdentifierInteger = [processIdentifierString integerValue];
  if (processIdentifierInteger < 1) {
    return [[FBSimulatorError
      describeFormat:@"Expected a process identifier as first word, but got %@ from %@", processIdentifierString, [FBCollectionInformation oneLineDescriptionFromArray:words]]
      fail:error];
  }
  if (processIdentifierOut) {
    *processIdentifierOut = (pid_t) processIdentifierInteger;
  }

  return serviceName;
}

- (NSString *)runWithArguments:(NSArray<NSString *> *)arguments error:(NSError **)error
{
  // Construct a Launch Configuration for launchctl we'll use the 'list' command.
  FBAgentLaunchConfiguration *launchConfiguration = [FBAgentLaunchConfiguration
    configurationWithBinary:self.launchCtlBinary
    arguments:arguments
    environment:@{}
    output:FBProcessOutputConfiguration.outputToDevNull];

  // Spawn and get the output
  return [[[FBAgentLaunchStrategy
    strategyWithSimulator:self.simulator]
    launchConsumingStdout:launchConfiguration]
    await:error];
}

@end
