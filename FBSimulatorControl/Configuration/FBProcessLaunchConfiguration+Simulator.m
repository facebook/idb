/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBProcessLaunchConfiguration+Simulator.h"

#import "FBSimulator.h"
#import "FBSimulatorError.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"

@implementation FBProcessLaunchConfiguration (Simulator)

- (instancetype)withEnvironmentAdditions:(NSDictionary<NSString *, NSString *> *)environmentAdditions
{
  NSMutableDictionary *environment = [[self environment] mutableCopy];
  [environment addEntriesFromDictionary:environmentAdditions];

  return [self withEnvironment:[environment copy]];
}

- (instancetype)withAdditionalArguments:(NSArray<NSString *> *)arguments
{
  return [self withAdditionalArguments:[self.arguments arrayByAddingObjectsFromArray:arguments]];
}

- (instancetype)withDiagnosticEnvironment
{
  // It looks like DYLD_PRINT is not currently working as per TN2239.
  return [self withEnvironmentAdditions:@{
    @"OBJC_PRINT_LOAD_METHODS" : @"YES",
    @"OBJC_PRINT_IMAGES" : @"YES",
    @"OBJC_PRINT_IMAGE_TIMES" : @"YES",
    @"DYLD_PRINT_STATISTICS" : @"1",
    @"DYLD_PRINT_ENV" : @"1",
    @"DYLD_PRINT_LIBRARIES" : @"1"
  }];
}

- (instancetype)injectingLibrary:(NSString *)filePath
{
  NSParameterAssert(filePath);

  return [self withEnvironmentAdditions:@{
    @"DYLD_INSERT_LIBRARIES" : filePath
  }];
}

- (instancetype)injectingShimulator
{
  return [self injectingLibrary:[[NSBundle bundleForClass:FBSimulator.class] pathForResource:@"libShimulator" ofType:@"dylib"]];
}

- (NSString *)identifiableName
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

+ (NSMutableDictionary<NSString *, id> *)launchOptionsWithArguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment waitForDebugger:(BOOL)waitForDebugger
{
  NSMutableDictionary<NSString *, id> *options = [NSMutableDictionary dictionary];
  options[@"arguments"] = arguments;
  options[@"environment"] = environment ? environment: @{@"__SOME_MAGIC__" : @"__IS_ALIVE__"};
  if (waitForDebugger) {
    options[@"wait_for_debugger"] = @1;
  }
  return options;
}

#pragma clang diagnostic pop

@end

@implementation FBApplicationLaunchConfiguration (Helpers)

- (instancetype)overridingLocalization:(FBLocalizationOverride *)localizationOverride
{
  return [self withAdditionalArguments:localizationOverride.arguments];
}

- (NSString *)identifiableName
{
  return self.bundleID;
}

- (NSDictionary<NSString *, id> *)simDeviceLaunchOptionsWithStdOutPath:(nullable NSString *)stdOutPath stdErrPath:(nullable NSString *)stdErrPath waitForDebugger:(BOOL)waitForDebugger
{
  NSMutableDictionary<NSString *, id> *options = [FBProcessLaunchConfiguration launchOptionsWithArguments:self.arguments environment:self.environment waitForDebugger:waitForDebugger];
  if (stdOutPath){
    options[@"stdout"] = stdOutPath;
  }
  if (stdErrPath) {
    options[@"stderr"] = stdErrPath;
  }
  return [options copy];
}

@end
