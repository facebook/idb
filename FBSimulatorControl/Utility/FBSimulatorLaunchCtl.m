/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorLaunchCtl.h"

#import <CoreSimulator/SimDevice.h>
#import <CoreSimulator/SimRuntime.h>

#import <FBControlCore/FBControlCore.h>

#import "FBAgentLaunchStrategy.h"
#import "FBSimulator+Helpers.h"
#import "FBSimulator.h"
#import "FBSimulatorError.h"

@interface FBSimulator (FBSimulatorLaunchCtl)

@property (nonatomic, copy, readonly) FBBinaryDescriptor *launchCtlBinary;

@end

@implementation FBSimulator (FBSimulatorLaunchCtl)

- (FBBinaryDescriptor *)launchCtlBinary
{
  NSString *path = [[self.device.runtime.root
    stringByAppendingPathComponent:@"bin"]
    stringByAppendingPathComponent:@"launchctl"];
  NSError *error = nil;
  FBBinaryDescriptor *binary = [FBBinaryDescriptor binaryWithPath:path error:&error];
  NSAssert(binary, @"Could not locate launchctl at expected location '%@', error %@", path, error);
  return binary;
}

@end

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
    NSString *serviceName = [FBSimulatorLaunchCtl extractServiceNameFromListLine:line processIdentifierOut:&processIdentifier error:&innerError];
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
  return [FBSimulatorLaunchCtl extractServiceNameFromListLine:line processIdentifierOut:processIdentifierOut error:error];
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
    configurationWithBinary:self.simulator.launchCtlBinary
    arguments:arguments
    environment:@{}
    output:FBProcessOutputConfiguration.outputToDevNull];

  // Spawn and get the output
  return [[FBAgentLaunchStrategy
    strategyWithSimulator:self.simulator]
    launchConsumingStdout:launchConfiguration error:error];
}

@end
