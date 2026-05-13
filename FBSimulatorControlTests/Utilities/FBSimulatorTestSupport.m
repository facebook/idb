/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorTestSupport.h"

#import <FBControlCore/FBControlCore.h>
#import <FBControlCore/FBControlCoreLogger.h>
#import <FBControlCore/FBDataConsumer.h>
#import <FBSimulatorControl/FBSimulator.h>
#import <FBSimulatorControl/FBSimulatorControl-Swift.h>

// Bare-minimum stand-in for SimDevice. The FBSimulator designated initializer
// only reads `-UDID.UUIDString` (to name the logger); nothing on the unit-test
// path reaches the device through its other properties because tests register
// a wrapping command class that intercepts before any device access.
@interface FBStubSimDevice : NSObject
@property (nonatomic, strong) NSUUID *UDID;
@end

@implementation FBStubSimDevice
- (instancetype)init
{
  self = [super init];
  if (self) {
    _UDID = [NSUUID UUID];
  }
  return self;
}

@end

// Minimal reporter stand-in. The designated init only stores the reporter; the
// unit-test path never reads it.
@interface FBStubEventReporter : NSObject
@end

@implementation FBStubEventReporter
@end

@implementation FBSimulatorTestSupport

+ (FBSimulator *)testableSimulator
{
  id stubDevice = [FBStubSimDevice new];
  id<FBControlCoreLogger> logger = [FBControlCoreLoggerFactory loggerToConsumer:[FBNullDataConsumer new]];
  id stubReporter = [FBStubEventReporter new];
  // Cast the stub through `id` so the type checker accepts it as `SimDevice *`.
  // The init only stores fields and reads `device.UDID.UUIDString`.
  return [[FBSimulator alloc] initWithDevice:stubDevice
                               configuration:FBSimulatorConfiguration.defaultConfiguration
                                         set:nil
                          auxillaryDirectory:NSTemporaryDirectory()
                                      logger:logger
                                    reporter:stubReporter];
}

@end
