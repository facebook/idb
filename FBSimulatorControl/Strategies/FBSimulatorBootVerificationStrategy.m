/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorBootVerificationStrategy.h"

#import <CoreSimulator/SimDevice.h>
#import <CoreSimulator/SimDeviceBootInfo.h>

#import <FBControlCore/FBControlCore.h>

#import "FBSimulator.h"
#import "FBSimulatorError.h"

@interface FBSimulatorBootVerificationStrategy ()

@property (nonatomic, strong, readonly) FBSimulator *simulator;

@end

@interface FBSimulatorBootVerificationStrategy_LaunchCtlServices : FBSimulatorBootVerificationStrategy

@property (nonatomic, copy, readonly) NSArray<NSString *> *requiredServiceNames;

- (instancetype)initWithSimulator:(FBSimulator *)simulator requiredServiceNames:(NSArray<NSString *> *)requiredServiceNames;

+ (NSArray<NSString *> *)requiredLaunchdServicesToVerifyBooted:(FBSimulator *)simulator;

@end

@interface FBSimulatorBootVerificationStrategy_SimDeviceBootInfo : FBSimulatorBootVerificationStrategy

@property (nonatomic, strong, nullable, readwrite) SimDeviceBootInfo *lastBootInfo;
@property (nonatomic, strong, nullable, readwrite) NSDate *lastInfoUpdateDate;

@end

@implementation FBSimulatorBootVerificationStrategy

#pragma mark Initializers

+ (instancetype)strategyWithSimulator:(FBSimulator *)simulator
{
  if ([simulator.device respondsToSelector:@selector(bootStatus)]) {
    return [[FBSimulatorBootVerificationStrategy_SimDeviceBootInfo alloc] initWithSimulator:simulator];
  } else {
    NSArray<NSString *> *requiredServiceNames = [FBSimulatorBootVerificationStrategy_LaunchCtlServices requiredLaunchdServicesToVerifyBooted:simulator];
    return [[FBSimulatorBootVerificationStrategy_LaunchCtlServices alloc] initWithSimulator:simulator requiredServiceNames:requiredServiceNames];
  }
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

static NSTimeInterval BootVerificationWaitInterval = 0.5; // 500ms
static NSTimeInterval BootVerificationStallInterval = 1.5; // 60s

- (FBFuture<NSNull *> *)verifySimulatorIsBooted
{
  FBSimulator *simulator = self.simulator;

  return [[simulator
    resolveState:FBiOSTargetStateBooted]
    onQueue:simulator.workQueue fmap:^FBFuture *(NSNull *_) {
      return [FBFuture onQueue:simulator.workQueue resolveUntil:^{
        return [[self performBootVerification] delay:BootVerificationWaitInterval];
      }];
    }];
}

#pragma mark Private

- (FBFuture<NSNull *> *)performBootVerification
 {
   NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
   return nil;
 }

@end

@implementation FBSimulatorBootVerificationStrategy_SimDeviceBootInfo

- (FBFuture<NSNull *> *)performBootVerification
{
  SimDeviceBootInfo *bootInfo = self.simulator.device.bootStatus;
  if (!bootInfo) {
    return [[FBSimulatorError
      describeFormat:@"No bootInfo for %@", self.simulator]
      failFuture];
  }
  [self updateBootInfo:bootInfo];
  if (bootInfo.isTerminalStatus == NO) {
    return [[FBSimulatorError
      describeFormat:@"Not terminal status, status is %@", bootInfo]
      failFuture];
  }
  return FBFuture.empty;
}

- (void)updateBootInfo:(SimDeviceBootInfo *)bootInfo
{
  // The isEqual Method implementation does *not* take into account -[SimDeviceBootInfo bootElapsedTime].
  // We can check that the differences between the last info and the current one are greater some 'stall threshold.
  // This can be indicative that something has gone wrong in the boot process.
  NSTimeInterval stallInterval = BootVerificationStallInterval;
  id<FBControlCoreLogger> logger = self.simulator.logger;
  if (!self.lastInfoUpdateDate) {
    self.lastInfoUpdateDate = NSDate.date;
  }
  if ([bootInfo isEqual:self.lastBootInfo]) {
    NSTimeInterval updateInterval = [NSDate.date timeIntervalSinceDate:self.lastInfoUpdateDate];
    if (updateInterval < stallInterval) {
      return;
    }
    [logger logFormat:@"Boot Status has not changed from '%@' for %f seconds", [FBSimulatorBootVerificationStrategy_SimDeviceBootInfo describeBootInfo:bootInfo], updateInterval];
  } else {
    [logger.debug logFormat:@"Boot Status Changed: %@", [FBSimulatorBootVerificationStrategy_SimDeviceBootInfo describeBootInfo:bootInfo]];
    self.lastBootInfo = bootInfo;
    self.lastInfoUpdateDate = NSDate.date;
  }
}

+ (NSString *)describeBootInfo:(SimDeviceBootInfo *)bootInfo
{
  NSString *regular = [self regularBootInfo:bootInfo];
  NSString *migration = [self dataMigrationString:bootInfo];
  if (!migration) {
    return regular;
  }
  return [NSString stringWithFormat:@"%@ | %@", regular, migration];
}

+ (NSString *)regularBootInfo:(SimDeviceBootInfo *)bootInfo
{
  return [NSString stringWithFormat:
    @"%@ | Elapsed %f",
    [self bootStatusString:bootInfo.status],
    bootInfo.bootElapsedTime
  ];
}

+ (NSString *)bootStatusString:(SimDeviceBootInfoStatus)status
{
  switch (status) {
    case SimDeviceBootInfoStatusBooting:
      return @"Booting";
    case SimDeviceBootInfoStatusWaitingOnBackboard:
      return @"WaitingOnBackboard";
    case SimDeviceBootInfoStatusWaitingOnDataMigration:
      return @"WaitingOnDataMigration";
    case SimDeviceBootInfoStatusWaitingOnSystemApp:
      return @"WaitingOnSystemApp";
    case SimDeviceBootInfoStatusFinished:
      return @"Finished";
    case SimDeviceBootInfoStatusDataMigrationFailed:
      return @"DataMigrationFailed";
    default:
      return @"Unknown";
  }
}

+ (NSString *)dataMigrationString:(SimDeviceBootInfo *)bootInfo
{
  if (bootInfo.status != SimDeviceBootInfoStatusWaitingOnDataMigration) {
    return nil;
  }
  return [NSString stringWithFormat:
    @"Migration Phase '%@' | Migration Elapsed %f",
    bootInfo.migrationPhaseDescription,
    bootInfo.migrationElapsedTime
  ];
}

@end

@implementation FBSimulatorBootVerificationStrategy_LaunchCtlServices

- (instancetype)initWithSimulator:(FBSimulator *)simulator requiredServiceNames:(NSArray<NSString *> *)requiredServiceNames
{
  self = [super initWithSimulator:simulator];
  if (!self) {
    return nil;
  }

  _requiredServiceNames = requiredServiceNames;

  return self;
}

- (FBFuture<NSNull *> *)performBootVerification
{
  return [[self.simulator
    listServices]
    onQueue:self.simulator.asyncQueue fmap:^ FBFuture<NSNull *> * (NSDictionary<NSString *, id> *services) {
      NSDictionary<id, NSString *> *processIdentifiers = [NSDictionary
        dictionaryWithObjects:self.requiredServiceNames
        forKeys:[services objectsForKeys:self.requiredServiceNames notFoundMarker:NSNull.null]];
      if (processIdentifiers[NSNull.null]) {
        return [[FBSimulatorError
          describeFormat:@"Service %@ has not started", processIdentifiers[NSNull.null]]
          failFuture];
      }
      return FBFuture.empty;
    }];
}

/*
 A Set of launchd_sim service names that are used to determine whether relevant System daemons are available after booting.

 There is a period of time between when CoreSimulator says that the Simulator is 'Booted'
 and when it is stable enough state to launch Applications/Daemons, these Service Names
 represent the Services that are known to signify readyness.

 @return the required Service Names.
 */
+ (NSArray<NSString *> *)requiredLaunchdServicesToVerifyBooted:(FBSimulator *)simulator
{
  FBControlCoreProductFamily family = simulator.productFamily;
  if (family == FBControlCoreProductFamilyiPhone || family == FBControlCoreProductFamilyiPad) {
    if (FBXcodeConfiguration.isXcode9OrGreater) {
      return @[
        @"com.apple.backboardd",
        @"com.apple.mobile.installd",
        @"com.apple.CoreSimulator.bridge",
        @"com.apple.SpringBoard",
      ];
    }
      return @[
        @"com.apple.backboardd",
        @"com.apple.mobile.installd",
        @"com.apple.SimulatorBridge",
        @"com.apple.SpringBoard",
      ];
  }
  if (family == FBControlCoreProductFamilyAppleWatch || family == FBControlCoreProductFamilyAppleTV) {
    return @[
      @"com.apple.mobileassetd",
      @"com.apple.nsurlsessiond",
    ];
  }
  return @[];
}

@end
