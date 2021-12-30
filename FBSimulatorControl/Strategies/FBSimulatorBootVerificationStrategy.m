/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
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
@property (nonatomic, strong, nullable, readwrite) SimDeviceBootInfo *lastBootInfo;
@property (nonatomic, strong, nullable, readwrite) NSDate *lastInfoUpdateDate;

@end

@implementation FBSimulatorBootVerificationStrategy

#pragma mark Initializers

+ (FBFuture<NSNull *> *)verifySimulatorIsBooted:(FBSimulator *)simulator
{
  return [[[FBSimulatorBootVerificationStrategy alloc] initWithSimulator:simulator] verifySimulatorIsBooted];
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
    [logger logFormat:@"Boot Status has not changed from '%@' for %f seconds", [FBSimulatorBootVerificationStrategy describeBootInfo:bootInfo], updateInterval];
  } else {
    [logger.debug logFormat:@"Boot Status Changed: %@", [FBSimulatorBootVerificationStrategy describeBootInfo:bootInfo]];
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
