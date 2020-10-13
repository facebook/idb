/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
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

- (FBFuture<NSString *> *)serviceNameForProcess:(FBProcessInfo *)process
{
  return [[self
    serviceNameAndProcessIdentifierForSubstring:@(process.processIdentifier).stringValue]
    onQueue:self.simulator.asyncQueue map:^(NSArray<id> *tuple) {
      return [tuple firstObject];
    }];
}

- (FBFuture<NSDictionary<NSString *, NSNumber *> *> *)serviceNamesAndProcessIdentifiersForSubstring:(NSString *)substring
{
  return [[self
    runWithArguments:@[@"list"]]
    onQueue:self.simulator.asyncQueue fmap:^(NSString *text) {
      FBLogSearchPredicate *predicate = [FBLogSearchPredicate substrings:@[substring]];
      FBLogSearch *search = [FBLogSearch withText:text predicate:predicate];
      NSMutableDictionary<NSString *, NSNumber *> *mapping = [NSMutableDictionary dictionary];
      for (NSString *line in search.matchingLines) {
        NSError *error = nil;
        pid_t processIdentifier = 0;
        NSString *serviceName = [FBSimulatorLaunchCtlCommands extractServiceNameFromListLine:line processIdentifierOut:&processIdentifier error:&error];
        if (!serviceName) {
          return [FBControlCoreError failFutureWithError:error];
        }
        mapping[serviceName] = @(processIdentifier);
      }
      return [FBFuture futureWithResult:mapping];
    }];
}

- (FBFuture<NSArray<id> *> *)serviceNameAndProcessIdentifierForSubstring:(NSString *)substring
{
  return [[self
    serviceNamesAndProcessIdentifiersForSubstring:substring]
    onQueue:self.simulator.asyncQueue fmap:^(NSDictionary<NSString *, NSNumber *> *serviceNameToProcessIdentifier) {
      if (serviceNameToProcessIdentifier.count == 0) {
        return [[FBSimulatorError
          describeFormat:@"No Matching processes for %@", substring]
          failFuture];
      }
      if (serviceNameToProcessIdentifier.count > 1) {
        return [[FBSimulatorError
          describeFormat:@"Multiple Matching processes for '%@' %@", substring, [FBCollectionInformation oneLineDescriptionFromDictionary:serviceNameToProcessIdentifier]]
          failFuture];
      }
      NSString *serviceName = serviceNameToProcessIdentifier.allKeys.firstObject;
      NSNumber *processIdentifier = serviceNameToProcessIdentifier.allValues.firstObject;
      return [FBFuture futureWithResult:@[serviceName, processIdentifier]];
    }];
}

- (FBFuture<NSNumber *> *)processIsRunningOnSimulator:(FBProcessInfo *)process
{
  return [[self
    serviceNameForProcess:process]
    onQueue:self.simulator.workQueue map:^NSNumber *(NSString *result) {
      return @YES;
    }];
}

- (FBFuture<NSDictionary<NSString *, id> *> *)listServices
{
  return [[self
    runWithArguments:@[@"list"]]
    onQueue:self.simulator.asyncQueue fmap:^(NSString *text) {
      NSArray<NSString *> *lines = [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
      if (lines.count < 2) {
        return [[FBSimulatorError
          describeFormat:@"Insufficient number of lines from output '%@'", text]
          failFuture];
      }
      lines = [lines subarrayWithRange:NSMakeRange(1, lines.count -1)];

      NSMutableDictionary<NSString *, id> *services = [NSMutableDictionary dictionary];
      for (NSString *line in lines) {
        if (line.length == 0) {
          continue;
        }
        pid_t processIdentifier = -1;
        NSError *error = nil;
        NSString *serviceName = [FBSimulatorLaunchCtlCommands extractServiceNameFromListLine:line processIdentifierOut:&processIdentifier error:&error];
        if (!serviceName) {
          return [FBSimulatorError failFutureWithError:error];
        }
        services[serviceName] = processIdentifier > 0 ? @(processIdentifier) : NSNull.null;
      }
      return [FBFuture futureWithResult:[services copy]];
    }];
}

#pragma mark Manipulating Services

- (FBFuture<NSString *> *)stopServiceWithName:(NSString *)serviceName
{
  return [[self
    runWithArguments:@[@"stop", serviceName]]
    rephraseFailure:@"Failed to stop service '%@'", serviceName];
}

- (FBFuture<NSString *> *)startServiceWithName:(NSString *)serviceName
{
  return [[self
    runWithArguments:@[@"start", serviceName]]
    rephraseFailure:@"Failed to start service '%@'", serviceName];
}

#pragma mark Helpers

+ (nullable NSString *)extractApplicationBundleIdentifierFromServiceName:(NSString *)serviceName
{
  NSRegularExpression *regex = self.regularExpressionForServiceNameToBundleID;
  NSTextCheckingResult *result = [regex firstMatchInString:serviceName options:0 range:NSMakeRange(0, serviceName.length)];
  if (!result) {
    return nil;
  }
  NSRange range = [result rangeAtIndex:1];
  return [serviceName substringWithRange:range];
}

#pragma mark Private

+ (NSRegularExpression *)regularExpressionForServiceNameToBundleID
{
  static dispatch_once_t onceToken;
  static NSRegularExpression *regex;
  dispatch_once(&onceToken, ^{
    NSError *error = nil;
    regex = [NSRegularExpression regularExpressionWithPattern:@"UIKitApplication:([^\\[]*).*" options:NSRegularExpressionDotMatchesLineSeparators error:&error];
    NSCAssert(regex, @"Should be able to compile regex %@", error);
  });
  return regex;
}

+ (NSString *)extractServiceNameFromListLine:(NSString *)line processIdentifierOut:(pid_t *)processIdentifierOut error:(NSError **)error
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

- (FBFuture<NSString *> *)runWithArguments:(NSArray<NSString *> *)arguments
{
  // Construct a Launch Configuration for launchctl we'll use the 'list' command.
  FBAgentLaunchConfiguration *launchConfiguration = [FBAgentLaunchConfiguration
    configurationWithBinary:self.launchCtlBinary
    arguments:arguments
    environment:@{}
    output:FBProcessOutputConfiguration.outputToDevNull
    mode:FBAgentLaunchModeDefault];

  // Spawn and get the output
  return [[FBAgentLaunchStrategy strategyWithSimulator:self.simulator] launchConsumingStdout:launchConfiguration];
}

@end
