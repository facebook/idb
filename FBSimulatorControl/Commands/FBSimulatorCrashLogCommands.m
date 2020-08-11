/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorCrashLogCommands.h"

#import "FBSimulator.h"

@interface FBSimulatorCrashLogCommands ()

@property (nonatomic, weak, readonly) FBSimulator *simulator;
@property (nonatomic, strong, readonly) FBCrashLogNotifier *notifier;
@property (nonatomic, assign, readwrite) BOOL hasPerformedInitialIngestion;

@end

@implementation FBSimulatorCrashLogCommands

#pragma mark Initializers

+ (instancetype)commandsWithTarget:(id<FBiOSTarget>)target
{
  NSParameterAssert([target isKindOfClass:FBSimulator.class]);
  return [[self alloc] initWithSimulator:(FBSimulator *)target notifier:FBCrashLogNotifier.sharedInstance];
}

- (instancetype)initWithSimulator:(FBSimulator *)simulator notifier:(FBCrashLogNotifier *)notifier
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _simulator = simulator;
  _notifier = notifier;
  _hasPerformedInitialIngestion = NO;

  return self;
}

#pragma mark id<FBiOSTarget>

- (FBFuture<FBCrashLogInfo *> *)notifyOfCrash:(NSPredicate *)predicate
{
  return [self.notifier nextCrashLogForPredicate:predicate];
}

- (FBFuture<NSArray<FBCrashLogInfo *> *> *)crashes:(NSPredicate *)predicate useCache:(BOOL)useCache
{
  if (!self.hasPerformedInitialIngestion) {
    [self.notifier.store ingestAllExistingInDirectory];
    self.hasPerformedInitialIngestion = YES;
  }

  return [FBFuture futureWithResult:[self.notifier.store ingestedCrashLogsMatchingPredicate:predicate]];
}

- (FBFuture<NSArray<FBCrashLogInfo *> *> *)pruneCrashes:(NSPredicate *)predicate
{
  // Unfortunately, the Crash Logs that are created for Simulators may not contain the UDID of the Simulator.
  // Crashes will not contain a UDID if they are launching System Apps that are present in the RuntimeRoot, not the Simulator Data Directory.
  // If they are Applications installed by the User, the UDID will appear in the launch path, as the Application is installed relative to the Simulator's Simulator Data Directory.
  // For this reason, we need to be conservative about which Crash Logs to prune, otherwise we may end up deleting the crash logs of another Simulator, or something running on the host.
  // Deleting these behind the back of the API is not something that makes sense.
  // We ensure that *any* crash logs that are to be deleted *must* contain the UDID of the Simulator.
  NSPredicate *simulatorPredicate = [NSCompoundPredicate andPredicateWithSubpredicates:@[
    [FBCrashLogInfo predicateForExecutablePathContains:self.simulator.udid],
    predicate,
  ]];
  return [FBFuture futureWithResult:[self.notifier.store pruneCrashLogsMatchingPredicate:simulatorPredicate]];
}

- (FBFutureContext<id<FBFileContainer>> *)crashLogFiles
{
  return [[FBControlCoreError
    describeFormat:@"%@ not supported on simulators", NSStringFromSelector(_cmd)]
    failFutureContext];
}

@end
