/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimDeviceWrapper.h"

#import <CoreSimulator/SimDevice.h>

#import <FBControlCore/FBControlCore.h>

#import <libkern/OSAtomic.h>

#import "FBSimulator+Helpers.h"
#import "FBSimulator.h"
#import "FBSimulatorControlConfiguration.h"
#import "FBSimulatorError.h"
#import "FBSimulatorProcessFetcher.h"

@interface FBSimDeviceWrapper ()

@property (nonatomic, strong, readonly) FBSimulator *simulator;

@end

@implementation FBSimDeviceWrapper

#pragma mark Initializers

+ (instancetype)withSimulator:(FBSimulator *)simulator
{
  return [[FBSimDeviceWrapper alloc] initWithSimulator:simulator];
}

- (instancetype)initWithSimulator:(FBSimulator *)simulator
{
  if (!(self = [self init])) {
    return nil;
  }

  _simulator = simulator;

  return self;
}

#pragma mark Public

- (BOOL)installApplication:(NSURL *)appURL withOptions:(NSDictionary *)options error:(NSError **)error
{
  // Calling -[SimDevice installApplication:withOptions:error:] will result in the Application unexpectedly terminating.
  return [self.simulator.device installApplication:appURL withOptions:options error:error];
}

- (BOOL)uninstallApplication:(NSString *)bundleID withOptions:(NSDictionary *)options error:(NSError **)error
{
  // The options don't appear to do much, simctl itself doesn't use them.
  return [self.simulator.device uninstallApplication:bundleID withOptions:nil error:error];
}

@end
