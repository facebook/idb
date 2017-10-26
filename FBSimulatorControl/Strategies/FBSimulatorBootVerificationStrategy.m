/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorBootVerificationStrategy.h"

#import <FBControlCore/FBControlCore.h>

#import "FBSimulator.h"
#import "FBSimulatorError.h"

@interface FBSimulatorBootVerificationStrategy ()

@property (nonatomic, strong, readonly) FBSimulator *simulator;

@end

@implementation FBSimulatorBootVerificationStrategy

#pragma mark Initializers

+ (instancetype)strategyWithSimulator:(FBSimulator *)simulator
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

- (BOOL)verifySimulatorIsBooted:(NSError **)error
{
  NSArray<NSString *> *requiredServiceNames = self.requiredLaunchdServicesToVerifyBooted;
  __block NSDictionary<id, NSString *> *processIdentifiers = @{};
  BOOL didStartAllRequiredServices = [NSRunLoop.mainRunLoop spinRunLoopWithTimeout:FBControlCoreGlobalConfiguration.slowTimeout untilTrue:^ BOOL {
    NSDictionary<NSString *, id> *services = [[self.simulator listServices] await:nil];
    if (!services) {
      return NO;
    }
    processIdentifiers = [NSDictionary dictionaryWithObjects:requiredServiceNames forKeys:[services objectsForKeys:requiredServiceNames notFoundMarker:NSNull.null]];
    if (processIdentifiers[NSNull.null]) {
      return NO;
    }
      return YES;
  }];
  if (!didStartAllRequiredServices) {
    return [[[FBSimulatorError
      describeFormat:@"Timed out waiting for service %@ to start", processIdentifiers[NSNull.null]]
      inSimulator:self.simulator]
      failBool:error];
  }
  return YES;
}

#pragma mark Private

/*
 A Set of launchd_sim service names that are used to determine whether relevant System daemons are available after booting.

 There is a period of time between when CoreSimulator says that the Simulator is 'Booted'
 and when it is stable enough state to launch Applications/Daemons, these Service Names
 represent the Services that are known to signify readyness.

 @return the required Service Names.
 */
- (NSArray<NSString *> *)requiredLaunchdServicesToVerifyBooted
{
  FBControlCoreProductFamily family = self.simulator.productFamily;
  if (family == FBControlCoreProductFamilyiPhone || family == FBControlCoreProductFamilyiPad) {
    if (FBXcodeConfiguration.isXcode9OrGreater) {
      return @[
        @"com.apple.backboardd",
        @"com.apple.mobile.installd",
        @"com.apple.CoreSimulator.bridge",
        @"com.apple.SpringBoard",
      ];
    }
    if (FBXcodeConfiguration.isXcode8OrGreater ) {
      return @[
        @"com.apple.backboardd",
        @"com.apple.mobile.installd",
        @"com.apple.SimulatorBridge",
        @"com.apple.SpringBoard",
      ];
    }
  }
  if (family == FBControlCoreProductFamilyAppleWatch || family == FBControlCoreProductFamilyAppleTV) {
    if (FBXcodeConfiguration.isXcode8OrGreater) {
      return @[
        @"com.apple.mobileassetd",
        @"com.apple.nsurlsessiond",
      ];
    }
    return @[
      @"com.apple.mobileassetd",
      @"com.apple.networkd",
    ];
  }
  return @[];
}

@end
