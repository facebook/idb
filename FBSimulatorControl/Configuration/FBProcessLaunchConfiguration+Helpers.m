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

@implementation FBProcessLaunchConfiguration (Helpers)

- (instancetype)withDiagnosticEnvironment
{
  FBProcessLaunchConfiguration *configuration = [self copy];

  // It looks like DYLD_PRINT is not currently working as per TN2239.
  NSDictionary *diagnosticEnvironment = @{
    @"OBJC_PRINT_LOAD_METHODS" : @"YES",
    @"OBJC_PRINT_IMAGES" : @"YES",
    @"OBJC_PRINT_IMAGE_TIMES" : @"YES",
    @"DYLD_PRINT_STATISTICS" : @"1",
    @"DYLD_PRINT_ENV" : @"1",
    @"DYLD_PRINT_LIBRARIES" : @"1"
  };
  NSMutableDictionary *environment = [[self environment] mutableCopy];
  [environment addEntriesFromDictionary:diagnosticEnvironment];
  configuration.environment = [environment copy];
  return configuration;
}

@end

@implementation FBAgentLaunchConfiguration (Helpers)

+ (instancetype)defaultWebDriverAgentConfigurationForSimulator:(FBSimulator *)simulator
{
  NSParameterAssert(simulator);

  NSBundle *bundle = [NSBundle bundleForClass:[self class]];
  NSString *webDriverPath = [bundle pathForResource:@"WebDriverAgent" ofType:@""];
  NSAssert(webDriverPath, @"WebDriverAgent should exist in bundle %@", bundle);

  NSDictionary *containingEnvironment = NSProcessInfo.processInfo.environment;
  NSMutableDictionary *agentEnvironment = [NSMutableDictionary dictionary];

  if ([containingEnvironment[@"RUN_FRESH_WEB_DRIVER_AGENT"] boolValue]) {
    webDriverPath = [[@(__FILE__) stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"WebDriverAgent"];
  }
  if (containingEnvironment[@"BUCKET_ID"]) {
    agentEnvironment[@"PORT_OFFSET"] = containingEnvironment[@"BUCKET_ID"];
  }

  NSString *stdErrPath = [simulator.dataDirectory stringByAppendingPathComponent:@"WebDriverAgent.log"];

  FBSimulatorBinary *binary = [FBSimulatorBinary binaryWithPath:webDriverPath error:nil];
  return [self configurationWithBinary:binary arguments:@[] environment:[agentEnvironment copy] stdOutPath:nil stdErrPath:stdErrPath];
}

@end
