/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBProcessLaunchConfiguration+Helpers.h"

#import "FBProcessLaunchConfiguration+Private.h"
#import "FBSimulator.h"
#import "FBSimulatorApplication.h"
#import "FBSimulatorError.h"

@implementation FBProcessLaunchConfiguration (Helpers)

- (instancetype)withEnvironmentAdditions:(NSDictionary<NSString *, NSString *> *)environmentAdditions
{
  NSMutableDictionary *environment = [[self environment] mutableCopy];
  [environment addEntriesFromDictionary:environmentAdditions];

  FBProcessLaunchConfiguration *configuration = [self copy];
  configuration.environment = [environment copy];
  return configuration;
}

- (instancetype)withAdditionalArguments:(NSArray<NSString *> *)arguments
{
  FBProcessLaunchConfiguration *configuration = [self copy];
  configuration.arguments = [self.arguments arrayByAddingObjectsFromArray:arguments];
  return configuration;
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
  return [self injectingLibrary:[[NSBundle bundleForClass:self.class] pathForResource:@"libShimulator" ofType:@"dylib"]];
}

- (NSDictionary *)simDeviceLaunchOptionsWithStdOut:(NSFileHandle *)stdOut stdErr:(NSFileHandle *)stdErr
{
  NSMutableDictionary *options = [@{
    @"arguments" : self.arguments,
    // iOS 7 Launch fails if the environment is empty, put some nothing in the environment for it.
    @"environment" : self.environment.count ? self.environment:  @{@"__SOME_MAGIC__" : @"__IS_ALIVE__"}
  } mutableCopy];

  if (stdOut){
    options[@"stdout"] = @([stdOut fileDescriptor]);
  }
  if (stdErr) {
    options[@"stderr"] = @([stdErr fileDescriptor]);
  }
  return [options copy];
}

- (NSString *)identifiableName
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

@end

@implementation FBAgentLaunchConfiguration (Helpers)

- (NSDictionary *)simDeviceLaunchOptionsWithStdOut:(NSFileHandle *)stdOut stdErr:(NSFileHandle *)stdErr
{
  // If arguments are passed to launched processes, then then the first argument needs to be the executable path.
  // Providing no arguments will do this automatically, but when custom arguments are, the first argument must be manually set.
  NSDictionary *options = [super simDeviceLaunchOptionsWithStdOut:stdOut stdErr:stdErr];
  NSArray *arguments = options[@"arguments"];
  if (arguments.count == 0 || [arguments.firstObject isEqualToString:self.agentBinary.path]) {
    return options;
  }

  NSMutableArray *modifiedArguments = [arguments mutableCopy];
  [modifiedArguments insertObject:self.agentBinary.path atIndex:0];
  NSMutableDictionary *modifiedOptions = [options mutableCopy];
  modifiedOptions[@"arguments"] = [modifiedArguments copy];
  return [modifiedOptions copy];
}

- (NSString *)identifiableName
{
  return self.agentBinary.name;
}

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

@end
