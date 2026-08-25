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

// Named stand-ins for `SimDevice.runtime` / `SimDevice.deviceType`. Only `-name` is
// read, by the configuration synthesis below.
@interface FBStubSimNamed : NSObject
@property (nonatomic, copy) NSString *name;
@end

@implementation FBStubSimNamed
+ (instancetype)named:(NSString *)name
{
  FBStubSimNamed *stub = [self new];
  stub.name = name;
  return stub;
}

@end

// A device whose runtime and device-type names are always present, used solely to
// synthesize a configuration for the tests.
@interface FBStubConfigurationSimDevice : NSObject
@property (nonatomic, strong) FBStubSimNamed *runtime;
@property (nonatomic, strong) FBStubSimNamed *deviceType;
@end

@implementation FBStubConfigurationSimDevice
- (instancetype)init
{
  self = [super init];
  if (self) {
    _runtime = [FBStubSimNamed named:@"iOS 17.0"];
    _deviceType = [FBStubSimNamed named:@"iPhone 15"];
  }
  return self;
}

@end

@implementation FBSimulatorTestSupport

+ (FBSimulator *)testableSimulator
{
  return [self testableSimulatorWithDevice:[FBStubSimDevice new]];
}

+ (FBSimulator *)testableSimulatorWithDevice:(id)device
{
  id<FBControlCoreLogger> logger = [FBControlCoreLoggerFactory loggerToConsumer:[FBNullDataConsumer new]];
  // Synthesize the configuration from a stub rather than asking for the default one.
  // `+defaultConfiguration` pins a hardcoded device model and then resolves the newest
  // *installed* runtime that supports it, so it returns nil on a host whose runtimes have
  // dropped that model — a host dependency these tests should not have. They never read the
  // configuration back; `-initWithDevice:` only stores it.
  FBSimulatorConfiguration *configuration =
  [FBSimulatorConfiguration inferSimulatorConfigurationFromDeviceSynthesizingMissing:(id)[FBStubConfigurationSimDevice new]];
  // Cast through `id` so the type checker accepts the substitution as
  // `SimDevice *`. The init only stores fields and reads `device.UDID.UUIDString`.
  return [[FBSimulator alloc] initWithDevice:device
                               configuration:configuration
                                         set:nil
                          auxillaryDirectory:NSTemporaryDirectory()
                                      logger:logger];
}

@end
