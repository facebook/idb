/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorKeychainCommands.h"

#import "FBSimulator.h"
#import "FBSimulator+Helpers.h"
#import "FBSimulatorError.h"
#import "FBSimulatorLaunchCtl.h"

static NSString *const SecuritydServiceName = @"com.apple.securityd";

@interface FBSimulatorKeychainCommands ()

@property (nonatomic, weak, readonly) FBSimulator *simulator;

@end

@implementation FBSimulatorKeychainCommands

+ (instancetype)commandsWithSimulator:(FBSimulator *)simulator
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

#pragma mark Public

- (BOOL)clearKeychainWithError:(NSError **)error
{
  NSError *innerError = nil;
  if (self.simulator.state == FBSimulatorStateBooted) {
    if (![self.simulator.launchctl stopServiceWithName:SecuritydServiceName error:&innerError]) {
      return [FBSimulatorError failBoolWithError:innerError errorOut:error];
    }
  }
  if (![self removeKeychainDirectory:&innerError]) {
    return [FBSimulatorError failBoolWithError:innerError errorOut:error];
  }
  if (self.simulator.state == FBSimulatorStateBooted) {
    if (![self.simulator.launchctl startServiceWithName:SecuritydServiceName error:&innerError]) {
      return [FBSimulatorError failBoolWithError:innerError errorOut:error];
    }
  }
  return YES;
}

#pragma mark Private

- (BOOL)removeKeychainDirectory:(NSError **)error
{
  NSString *keychainDirectory = [[self.simulator.dataDirectory
    stringByAppendingPathComponent:@"Library"]
    stringByAppendingPathComponent:@"Keychains"];
  if (![NSFileManager.defaultManager fileExistsAtPath:keychainDirectory]) {
    [self.simulator.logger.info logFormat:@"The keychain directory does not exist at '%@'", keychainDirectory];
    return YES;
  }
  NSError *innerError = nil;
  if (![NSFileManager.defaultManager removeItemAtPath:keychainDirectory error:&innerError]) {
    return [[[FBSimulatorError
      describeFormat:@"Failed to delete keychain directory at path %@", keychainDirectory]
      causedBy:innerError]
      failBool:error];
  }
  return YES;
}

@end
