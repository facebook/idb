/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBTestRunConfiguration.h"

#import <FBSimulatorControl/FBSimulatorControl.h>

#import <XCTestBootstrap/XCTestBootstrap.h>

#import "FBJSONTestReporter.h"
#import "FBXCTestError.h"

@interface FBTestRunConfiguration ()
@property (nonatomic, strong, readwrite) id<FBControlCoreLogger> logger;
@property (nonatomic, strong, readwrite) id<FBXCTestReporter> reporter;
@property (nonatomic, strong, readwrite) FBSimulatorConfiguration *targetDeviceConfiguration;

@property (nonatomic, copy, readwrite) NSString *workingDirectory;
@property (nonatomic, copy, readwrite) NSString *testBundlePath;
@property (nonatomic, copy, readwrite) NSString *runnerAppPath;
@property (nonatomic, copy, readwrite) NSString *simulatorName;
@property (nonatomic, copy, readwrite) NSString *simulatorOS;
@end

@implementation FBTestRunConfiguration

- (BOOL)loadWithArguments:(NSArray<NSString *> *)arguments workingDirectory:(NSString *)workingDirectory error:(NSError **)error
{
  arguments = [arguments subarrayWithRange:NSMakeRange(1, [arguments count] - 1)];
  NSUInteger nextArgument = 0;
  while (nextArgument < arguments.count) {
    NSString *argument = arguments[nextArgument];
    NSString *parameter = nil;
    if ([argument length] >= 1 && [argument characterAtIndex:0] == '-') {
      if (++nextArgument >= arguments.count) {
        return [[FBXCTestError describeFormat:@"The last option is missing a parameter: %@", argument] failBool:error];
      }
      parameter = arguments[nextArgument];
    }
    if ([argument isEqualToString:@"run-tests"]) {
      // Ignore. This is the only action we support.
    } else if ([argument isEqualToString:@"-reporter"]) {
      if (![self checkReporter:parameter error:error]) {
        return NO;
      }
    } else if ([argument isEqualToString:@"-sdk"]) {
      if (![self setSDK:parameter error:error]) {
        return NO;
      }
    } else if ([argument isEqualToString:@"-destination"]) {
      if (![self setDestination:parameter error:error]) {
        return NO;
      }
    } else if ([argument isEqualToString:@"-logicTest"]) {
      [self addTestBundle:parameter runnerAppPath:nil error:error];
    } else if ([argument isEqualToString:@"-appTest"]) {
      NSRange colonRange = [parameter rangeOfString:@":"];
      if (colonRange.length == 0) {
        return [[FBXCTestError describeFormat:@"Test specifier should contain a colon: %@", parameter] failBool:error];
      }
      NSString *testBundlePath = [parameter substringToIndex:colonRange.location];
      NSString *testRunnerPath = [parameter substringFromIndex:colonRange.location + 1];
      NSString *testRunnerAppPath = [testRunnerPath stringByDeletingLastPathComponent];
      [self addTestBundle:testBundlePath runnerAppPath:testRunnerAppPath error:error];
    } else {
      return [[FBXCTestError describeFormat:@"Unrecognized option: %@", argument] failBool:error];
    }
    ++nextArgument;
  }

  //self.logger = [FBControlCoreLogger aslLoggerWritingToStderrr:YES withDebugLogging:YES];
  self.reporter = [[FBJSONTestReporter new] initWithTestBundlePath:_testBundlePath testType:self.testType];
  FBSimulatorConfiguration *simulatorConfiguration = [FBSimulatorConfiguration defaultConfiguration];
  if (_simulatorName) {
    simulatorConfiguration = [simulatorConfiguration withDeviceNamed:_simulatorName];
  }
  if (_simulatorOS) {
    simulatorConfiguration = [simulatorConfiguration withOSNamed:_simulatorOS];
  }
  self.targetDeviceConfiguration = simulatorConfiguration;
  self.workingDirectory = workingDirectory;
  return YES;
}

- (BOOL)checkReporter:(NSString *)reporter error:(NSError **)error
{
  if (![reporter isEqualToString:@"json-stream"]) {
    return [[FBXCTestError describeFormat:@"Unsupported reporter: %@", reporter] failBool:error];
  }
  return YES;
}

- (BOOL)setSDK:(NSString *)sdk error:(NSError **)error
{
  if (![sdk isEqualToString:@"iphonesimulator"]) {
    return [[FBXCTestError describeFormat:@"Unsupported SDK: %@", sdk] failBool:error];
  }
  return YES;
}

- (BOOL)setDestination:(NSString *)destination error:(NSError **)error
{
  NSArray<NSString *> *parts = [destination componentsSeparatedByString:@","];
  for (NSString *part in parts) {
    if ([part length] == 0) {
      continue;
    }
    NSRange equalsRange = [part rangeOfString:@"="];
    if (equalsRange.length == 0) {
      return [[FBXCTestError describeFormat:@"Destination specifier should contain '=': %@", part] failBool:error];
    }
    NSString *key = [part substringToIndex:equalsRange.location];
    NSString *value = [part substringFromIndex:equalsRange.location + 1];
    if ([key isEqualToString:@"name"]) {
      if (![self setSimulatorName:value error:error]) {
        return NO;
      }
    } else if ([key isEqualToString:@"OS"]) {
      if (![self setSimulatorOS:value error:error]) {
        return NO;
      }
    } else {
      return [[FBXCTestError describeFormat:@"Unrecognized destination specifier: %@", key] failBool:error];
    }
  }
  return YES;
}

- (BOOL)setSimulatorName:(NSString *)name error:(NSError **)error
{
  if (_simulatorName) {
    return [[FBXCTestError describeFormat:@"Multiple destination simulator names specified: %@ and %@", _simulatorName, name] failBool:error];
  }
  _simulatorName = name;
  return YES;
}

- (BOOL)setSimulatorOS:(NSString *)os error:(NSError **)error
{
  if (_simulatorOS) {
    return [[FBXCTestError describeFormat:@"Multiple destination simulator OS specified: %@ and %@", _simulatorOS, os] failBool:error];
  }
  _simulatorOS = os;
  return YES;
}

- (BOOL)addTestBundle:(NSString *)testBundlePath runnerAppPath:(NSString *)runnerAppPath error:(NSError **)error
{
  if (_testBundlePath != nil) {
    return [[FBXCTestError describe:@"Only a single -logicTest or -appTest argument expected"] failBool:error];
  }
  _testBundlePath = testBundlePath;
  _runnerAppPath = runnerAppPath;
  return YES;
}

- (NSString *)testType
{
  if (_runnerAppPath) {
    return @"application-test";
  } else {
    return @"logic-test";
  }
}

@end
