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
