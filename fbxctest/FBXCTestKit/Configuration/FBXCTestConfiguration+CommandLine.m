/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBXCTestConfiguration+CommandLine.h"

#import <XCTestBootstrap/XCTestBootstrap.h>

FBiOSTargetActionType const FBiOSTargetActionTypeFBXCTest = @"fbxctest";

@implementation FBXCTestConfiguration (CommandLine)

+ (nullable instancetype)configurationFromArguments:(NSArray<NSString *> *)arguments processUnderTestEnvironment:(NSDictionary<NSString *, NSString *> *)environment workingDirectory:(NSString *)workingDirectory error:(NSError **)error
{
  return [self configurationFromArguments:arguments processUnderTestEnvironment:environment workingDirectory:workingDirectory timeout:0 error:nil];
}

+ (nullable instancetype)configurationFromArguments:(NSArray<NSString *> *)arguments processUnderTestEnvironment:(NSDictionary<NSString *, NSString *> *)environment workingDirectory:(NSString *)workingDirectory timeout:(NSTimeInterval)timeout error:(NSError **)error
{
  Class configurationClass = [self testConfigurationClassForArguments:arguments error:error];
  if (!configurationClass) {
    return nil;
  }
  FBXCTestDestination *destination = [self destinationWithArguments:arguments error:error];
  if (!destination) {
    return nil;
  }
  FBXCTestShimConfiguration *shims = nil;
  NSString *testBundlePath = nil;
  NSString *runnerAppPath = nil;
  NSString *testFilter = nil;
  BOOL waitForDebugger = NO;

  if (![FBXCTestConfiguration loadWithArguments:arguments shimsOut:&shims testBundlePathOut:&testBundlePath runnerAppPathOut:&runnerAppPath testFilterOut:&testFilter waitForDebuggerOut:&waitForDebugger error:error]) {
    return nil;
  }
  return [[configurationClass alloc] initWithDestination:destination shims:shims environment:environment workingDirectory:workingDirectory testBundlePath:testBundlePath waitForDebugger:waitForDebugger timeout:timeout runnerAppPath:runnerAppPath testFilter:testFilter];
}

+ (Class)testConfigurationClassForArguments:(NSArray<NSString *> *)arguments error:(NSError **)error
{
  NSSet<NSString *> *argumentSet = [NSSet setWithArray:arguments];
  if ([argumentSet containsObject:@"-listTestsOnly"]) {
    return [FBListTestConfiguration class];
  }
  if ([argumentSet containsObject:@"-logicTest"]) {
    return [FBLogicTestConfiguration class];
  }
  if ([argumentSet containsObject:@"-appTest"]) {
    return [FBApplicationTestConfiguration class];
  }
  return [[FBControlCoreError
    describeFormat:@"Could not determine test runner type from %@", [FBCollectionInformation oneLineDescriptionFromArray:arguments]]
    fail:error];
}

+ (BOOL)loadWithArguments:(NSArray<NSString *> *)arguments shimsOut:(FBXCTestShimConfiguration **)shimsOut testBundlePathOut:(NSString **)testBundlePathOut runnerAppPathOut:(NSString **)runnerAppPathOut testFilterOut:(NSString **)testFilterOut waitForDebuggerOut:(BOOL *)waitForDebuggerOut error:(NSError **)error
{
  NSUInteger nextArgument = 0;
  NSString *testFilter = nil;
  BOOL shimsRequired = YES;

  while (nextArgument < arguments.count) {
    NSString *argument = arguments[nextArgument++];
    if ([argument isEqualToString:@"run-tests"]) {
      // Ignore. This is the only action we support.
      continue;
    } else if ([argument isEqualToString:@"-listTestsOnly"]) {
      // Ignore. This is handled by the configuration class.
      continue;
    } else if ([argument isEqualToString:@"-waitForDebugger"]) {
      *waitForDebuggerOut = YES;
      continue;
    }
    if (nextArgument >= arguments.count) {
      return [[FBXCTestError describeFormat:@"The last option is missing a parameter: %@", argument] failBool:error];
    }
    NSString *parameter = arguments[nextArgument++];
    if ([argument isEqualToString:@"-reporter"]) {
      if (![self checkReporter:parameter error:error]) {
        return NO;
      }
    } else if ([argument isEqualToString:@"-sdk"]) {
      // Ignore. This is handled when extracting the destination
    } else if ([argument isEqualToString:@"-destination"]) {
      // Ignore. This is handled when extracting the destination
    } else if ([argument isEqualToString:@"-logicTest"]) {
      if (*testBundlePathOut != nil) {
        return [[FBXCTestError
          describe:@"Only a single -logicTest or -appTest argument expected"]
          failBool:error];
      }
      *testBundlePathOut = parameter;
    } else if ([argument isEqualToString:@"-appTest"]) {
      NSRange colonRange = [parameter rangeOfString:@":"];
      if (colonRange.length == 0) {
        return [[FBXCTestError describeFormat:@"Test specifier should contain a colon: %@", parameter] failBool:error];
      }
      NSString *testBundlePath = [parameter substringToIndex:colonRange.location];
      NSString *testRunnerPath = [parameter substringFromIndex:colonRange.location + 1];
      NSString *testRunnerAppPath = [testRunnerPath stringByDeletingLastPathComponent];

      if (*testBundlePathOut != nil) {
        return [[FBXCTestError
          describe:@"Only a single -logicTest or -appTest argument expected"]
          failBool:error];
      }
      *testBundlePathOut = testBundlePath;
      *runnerAppPathOut = testRunnerAppPath;
      shimsRequired = NO;
    } else if ([argument isEqualToString:@"-only"]) {
      if (testFilter != nil) {
        return [[FBXCTestError describeFormat:@"Multiple -only options specified: %@, %@", testFilter, parameter] failBool:error];
      }
      testFilter = parameter;
    } else {
      return [[FBXCTestError describeFormat:@"Unrecognized option: %@", argument] failBool:error];
    }
  }

  if (shimsRequired) {
    NSError *innerError = nil;
    FBXCTestShimConfiguration *shimConfiguration = [FBXCTestShimConfiguration defaultShimConfigurationWithError:&innerError];
    if (!shimConfiguration) {
      return [FBXCTestError failBoolWithError:innerError errorOut:error];
    }
    *shimsOut = shimConfiguration;
  }
  if (testFilter != nil) {
    NSString *expectedPrefix = [*testBundlePathOut stringByAppendingString:@":"];
    if (![testFilter hasPrefix:expectedPrefix]) {
      return [[FBXCTestError
        describeFormat:@"Test filter '%@' does not apply to the test bundle '%@'", testFilter, *testBundlePathOut]
        failBool:error];
    }
    *testFilterOut = [testFilter substringFromIndex:expectedPrefix.length];
  }

  return YES;
}

+ (BOOL)checkReporter:(NSString *)reporter error:(NSError **)error
{
  if (![reporter isEqualToString:@"json-stream"]) {
    return [[FBXCTestError describeFormat:@"Unsupported reporter: %@", reporter] failBool:error];
  }
  return YES;
}

+ (FBXCTestDestination *)destinationWithArguments:(NSArray<NSString *> *)arguments error:(NSError **)error
{
  NSOrderedSet<NSString *> *argumentSet = [NSOrderedSet orderedSetWithArray:arguments];
  NSMutableOrderedSet<NSString *> *subset = [NSMutableOrderedSet orderedSetWithArray:arguments];
  NSArray<NSString *> *macOSXSDKArguments = @[@"-sdk", @"macosx"];
  NSArray<NSString *> *iPhoneSimulatorSDKArguments = @[@"-sdk", @"iphonesimulator"];

  // Check for a macosx destination, return early and ignore -destination argument.
  [subset intersectOrderedSet:[NSOrderedSet orderedSetWithArray:macOSXSDKArguments]];
  if ([subset.array isEqualToArray:macOSXSDKArguments]) {
    return [FBXCTestDestinationMacOSX new];
  }

  // Check for an iPhoneSimulator Destination.
  subset = [NSMutableOrderedSet orderedSetWithArray:arguments];
  [subset intersectOrderedSet:[NSOrderedSet orderedSetWithArray:iPhoneSimulatorSDKArguments]];
  NSString *destination = [self destinationArgumentFromArguments:argumentSet];
  if (![subset.array isEqualToArray:iPhoneSimulatorSDKArguments] && !destination) {
    return [[FBXCTestError
      describeFormat:@"No valid SDK or Destination provided in %@", [FBCollectionInformation oneLineDescriptionFromArray:arguments]]
      fail:error];
  }
  // No Destination exists so return early.
  if (!destination) {
    return [[FBXCTestDestinationiPhoneSimulator alloc] initWithModel:nil version:nil];
  }
  // Extract the destination.
  FBOSVersionName os = nil;
  FBDeviceModel model = nil;
  if (![self parseSimulatorConfigurationFromDestination:destination osOut:&os modelOut:&model error:error]) {
    return nil;
  }
  return [[FBXCTestDestinationiPhoneSimulator alloc] initWithModel:model version:os];
}

+ (NSString *)destinationArgumentFromArguments:(NSOrderedSet<NSString *> *)arguments
{
  NSUInteger index = [arguments indexOfObject:@"-destination"];
  if (index == NSNotFound) {
    return nil;
  }
  index += 1;
  if (index >= arguments.count) {
    return nil;
  }
  return arguments[index];
}

+ (BOOL)parseSimulatorConfigurationFromDestination:(NSString *)destination osOut:(FBOSVersionName *)osOut modelOut:(FBDeviceModel *)modelOut error:(NSError **)error
{
  NSArray<NSString *> *parts = [destination componentsSeparatedByString:@","];

  for (NSString *part in parts) {
    if ([part length] == 0) {
      continue;
    }
    NSRange equalsRange = [part rangeOfString:@"="];
    if (equalsRange.length == 0) {
      return [[FBXCTestError
        describeFormat:@"Destination specifier should contain '=': %@", part]
        failBool:error];
    }
    NSString *key = [part substringToIndex:equalsRange.location];
    NSString *value = [part substringFromIndex:equalsRange.location + 1];
    if ([key isEqualToString:@"name"]) {
      FBDeviceModel model = value;
      if (modelOut) {
        *modelOut = model;
      }
    } else if ([key isEqualToString:@"OS"]) {
      FBOSVersionName os = value;
      if (osOut) {
        *osOut = os;
      }
    } else {
      return [[FBXCTestError
        describeFormat:@"Unrecognized destination specifier: %@", key]
        failBool:error];
    }
  }
  return YES;
}

@end
