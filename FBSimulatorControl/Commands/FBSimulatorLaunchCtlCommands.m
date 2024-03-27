/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorLaunchCtlCommands.h"

#import <CoreSimulator/SimDevice.h>
#import <CoreSimulator/SimRuntime.h>

#import "FBSimulator+Private.h"
#import "FBSimulator.h"
#import "FBSimulatorError.h"

@interface FBSimulatorLaunchCtlCommands ()

@property (nonatomic, strong, readonly) FBSimulator *simulator;
@property (nonatomic, copy, readonly) NSString *launchctlLaunchPath;

- (instancetype)initWithSimulator:(FBSimulator *)simulator launchctlLaunchPath:(NSString *)launchctlLaunchPath;

@end

@implementation FBSimulatorLaunchCtlCommands

#pragma mark Initializers

+ (NSString *)launchCtlLaunchPathForSimulator:(FBSimulator *)simulator error:(NSError **)error
{
  NSString *path = [[simulator.device.runtime.root
    stringByAppendingPathComponent:@"bin"]
    stringByAppendingPathComponent:@"launchctl"];
  FBBinaryDescriptor *binary = [FBBinaryDescriptor binaryWithPath:path error:error];
  if (!binary) {
    return nil;
  }
  return binary.path;
}

+ (instancetype)commandsWithTarget:(FBSimulator *)target
{
  NSError *error = nil;
  NSString *launchctlLaunchPath = [self launchCtlLaunchPathForSimulator:target error:&error];
  NSAssert(launchctlLaunchPath, @"Could not find path for launchctl binary with error %@", error);
  return [[FBSimulatorLaunchCtlCommands alloc] initWithSimulator:target launchctlLaunchPath:launchctlLaunchPath];
}

- (instancetype)initWithSimulator:(FBSimulator *)simulator launchctlLaunchPath:(NSString *)launchctlLaunchPath
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _simulator = simulator;
  _launchctlLaunchPath = launchctlLaunchPath;

  return self;
}

#pragma mark Querying Services

- (FBFuture<NSString *> *)serviceNameForProcessIdentifier:(pid_t)pid
{
  NSError *error = nil;
  NSString *pattern = [NSString stringWithFormat:@"^%@\t", [NSRegularExpression escapedPatternForString:@(pid).stringValue]];
  NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:&error];
  if (error) {
    return [[FBSimulatorError
      describeFormat:@"Couldn't build search pattern for '%@'", @(pid)]
      failFuture];
  }

  return [[self
    firstServiceNameAndProcessIdentifierMatching:regex]
    onQueue:self.simulator.asyncQueue map:^(NSArray<id> *tuple) {
      return [tuple firstObject];
    }];
}


- (FBFuture<NSString *> *)serviceNameForProcess:(FBProcessInfo *)process
{
  return [self serviceNameForProcessIdentifier:process.processIdentifier];
}

- (FBFuture<NSDictionary<NSString *, NSNumber *> *> *)serviceNamesAndProcessIdentifiersMatching:(NSRegularExpression *)regex
{
  return [[self
    runWithArguments:@[@"list"]]
    onQueue:self.simulator.asyncQueue fmap:^(NSString *text) {
      NSArray<NSString *> *lines = [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
      NSMutableDictionary<NSString *, NSNumber *> *mapping = [NSMutableDictionary dictionary];
      for (NSString *line in lines) {
        if (![regex firstMatchInString:line options:0 range:NSMakeRange(0, line.length)]) {
          continue;
        }
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

- (FBFuture<NSArray<id> *> *)firstServiceNameAndProcessIdentifierMatching:(NSRegularExpression *)regex
{
  return [[self
    serviceNamesAndProcessIdentifiersMatching:regex]
    onQueue:self.simulator.asyncQueue fmap:^(NSDictionary<NSString *, NSNumber *> *serviceNameToProcessIdentifier) {
      if (serviceNameToProcessIdentifier.count == 0) {
        return [[FBSimulatorError
          describeFormat:@"No Matching processes for '%@'", regex.pattern ]
          failFuture];
      }
      if (serviceNameToProcessIdentifier.count > 1) {
        return [[FBSimulatorError
          describeFormat:@"Multiple Matching processes for '%@' %@", regex.pattern, [FBCollectionInformation oneLineDescriptionFromDictionary:serviceNameToProcessIdentifier]]
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
  FBProcessSpawnConfiguration *launchConfiguration = [[FBProcessSpawnConfiguration alloc]
    initWithLaunchPath:self.launchctlLaunchPath
    arguments:arguments
    environment:@{}
    io:FBProcessIO.outputToDevNull
    mode:FBProcessSpawnModeDefault];

  // Spawn and get the output
  return [FBProcessSpawnCommandHelpers launchConsumingStdout:launchConfiguration withCommands:self.simulator];
}

@end
