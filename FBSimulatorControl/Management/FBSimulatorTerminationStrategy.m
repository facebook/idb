/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorTerminationStrategy.h"

#import <CoreSimulator/SimDevice.h>
#import <CoreSimulator/SimDeviceSet.h>
#import <CoreSimulator/SimDeviceType.h>
#import <CoreSimulator/SimRuntime.h>

#import "FBCoreSimulatorNotifier.h"
#import "FBProcessInfo.h"
#import "FBProcessQuery+Simulators.h"
#import "FBProcessQuery.h"
#import "FBSimulator+Private.h"
#import "FBSimulatorApplication.h"
#import "FBSimulatorConfiguration+CoreSimulator.h"
#import "FBSimulatorConfiguration.h"
#import "FBSimulatorControl.h"
#import "FBSimulatorControlConfiguration.h"
#import "FBSimulatorError.h"
#import "FBSimulatorInteraction.h"
#import "FBSimulatorLogger.h"
#import "FBSimulatorPredicates.h"
#import "FBTaskExecutor+Convenience.h"
#import "FBTaskExecutor.h"
#import "NSRunLoop+SimulatorControlAdditions.h"

@interface FBSimulatorTerminationStrategy ()

@property (nonatomic, copy, readonly) FBSimulatorControlConfiguration *configuration;
@property (nonatomic, copy, readonly) NSArray *allSimulators;

@property (nonatomic, strong, readonly) FBProcessQuery *processQuery;

- (BOOL)killSimulatorProcess:(id<FBProcessInfo>)process error:(NSError **)error;
- (BOOL)killProcesses:(NSArray *)processes error:(NSError **)error;
- (BOOL)killProcess:(id<FBProcessInfo>)process error:(NSError **)error;

@end

@interface FBSimulatorTerminationStrategy_Kill : FBSimulatorTerminationStrategy

@end

@implementation FBSimulatorTerminationStrategy_Kill

- (BOOL)killSimulatorProcess:(id<FBProcessInfo>)process error:(NSError **)error
{
  return [self killProcess:process error:error];
}

@end

@interface FBSimulatorTerminationStrategy_WorkspaceQuit : FBSimulatorTerminationStrategy

@end

@implementation FBSimulatorTerminationStrategy_WorkspaceQuit

- (BOOL)killSimulatorProcess:(id<FBProcessInfo>)process error:(NSError **)error
{
  NSRunningApplication *application = [self.processQuery runningApplicationForProcess:process];
  if ([application isKindOfClass:NSNull.class]) {
    return [[FBSimulatorError describeFormat:@"Could not obtain application handle for %@", process] failBool:error];
  }
  if (![application terminate]) {
    return [[FBSimulatorError describeFormat:@"Could not termination Application %@", application] failBool:error];
  }
  return YES;
}

@end

@implementation FBSimulatorTerminationStrategy

#pragma mark Initialization

+ (instancetype)withConfiguration:(FBSimulatorControlConfiguration *)configuration allSimulators:(NSArray *)allSimulators;
{
  BOOL useKill = (configuration.options & FBSimulatorManagementOptionsUseProcessKilling) == FBSimulatorManagementOptionsUseProcessKilling;
  return useKill
    ? [[FBSimulatorTerminationStrategy_Kill alloc] initWithConfiguration:configuration allSimulators:allSimulators]
    : [[FBSimulatorTerminationStrategy_WorkspaceQuit alloc] initWithConfiguration:configuration allSimulators:allSimulators];
}

- (instancetype)initWithConfiguration:(FBSimulatorControlConfiguration *)configuration allSimulators:(NSArray *)allSimulators
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _configuration = configuration;
  _allSimulators = allSimulators;
  _processQuery = [FBProcessQuery new];

  return self;
}

#pragma mark Public Methods

- (NSArray *)killAllWithError:(NSError **)error
{
  return [self killSimulators:self.allSimulators withError:error];
}

- (NSArray *)killSimulators:(NSArray *)simulators withError:(NSError **)error
{
  // It looks like there is a bug with El Capitan, where terminating mutliple Applications quickly
  // can result in the dock getting into an inconsistent state displaying icons for terminated Applications.
  // This happens regardless of how the Application was terminated.
  // The process backing the terminated Application is definitely gone, but the Icon isn't.
  // The Application appears in the Force Quit menu, but cannot ever be quit by conventional means.
  // Attempting to shutdown the Mac will result in hanging (probably because it can't terminate the App).
  //
  // The only remedy is to quit 'launchservicesd' followed by 'Dock.app'.
  // This will clear up the stale state that must exist in the Dock/launchservicesd.
  // Waiting after killing of processes by a short period of time is sufficient to mitigate this issue.
  // Since `safeShutdown:withError:` will spin the run loop until CoreSimulator confirms that the device is shutdown,
  // this will give a sufficient amount of time between killing Applications.

  for (FBSimulator *simulator in simulators) {
    id<FBProcessInfo> simulatorProcess = simulator.launchInfo.simulatorProcess ?: [self.processQuery simulatorApplicationProcessForSimDevice:simulator.device];
    if (!simulatorProcess) {
      continue;
    }
    NSError *innerError = nil;
    if (![self killSimulatorProcess:simulatorProcess error:&innerError]) {
      return [[[[FBSimulatorError describeFormat:@"Could not kill simulator process %@", simulatorProcess] inSimulator:simulator] causedBy:innerError] fail:error];
    }
    if (![self safeShutdown:simulator withError:&innerError]) {
      return [[[[FBSimulatorError describe:@"Could not shut down simulator after termination"] inSimulator:simulator] causedBy:innerError] fail:error];
    }
  }
  return simulators;
}

- (BOOL)killSpuriousSimulatorsWithError:(NSError **)error
{
  NSPredicate *predicate = [NSCompoundPredicate notPredicateWithSubpredicate:
    [NSCompoundPredicate andPredicateWithSubpredicates:@[
      [FBProcessQuery simulatorsProcessesLaunchedUnderConfiguration:self.configuration],
      [FBProcessQuery simulatorProcessesLaunchedBySimulatorControl]
    ]
  ]];

  NSError *innerError = nil;
  if (![self killSimulatorProcessesMatchingPredicate:predicate error:&innerError]) {
    return [[[FBSimulatorError describe:@"Could not kill non-current spurious simulators"] causedBy:innerError] failBool:error];
  }
  return YES;
}

- (BOOL)killSpuriousCoreSimulatorServicesWithError:(NSError **)error
{
  NSPredicate *predicate = [NSCompoundPredicate notPredicateWithSubpredicate:
    [FBProcessQuery coreSimulatorProcessesForCurrentXcode]
  ];
  NSArray *processes = [[self.processQuery coreSimulatorServiceProcesses] filteredArrayUsingPredicate:predicate];

  return [self killProcesses:processes error:error];
}

#pragma mark Private

- (BOOL)killProcess:(id<FBProcessInfo>)process error:(NSError **)error
{
  if (kill(process.processIdentifier, SIGTERM) < 0) {
    return [[FBSimulatorError describeFormat:@"Failed to kill process %@", process] failBool:error];
  }
  return YES;
}


- (BOOL)killProcesses:(NSArray *)processes error:(NSError **)error
{
  for (id<FBProcessInfo> process in processes) {
    NSParameterAssert(process.processIdentifier > 1);
    if (![self killProcess:process error:error]) {
      return NO;
    }
  }
  return YES;
}

- (BOOL)killSimulatorProcess:(id<FBProcessInfo>)process error:(NSError **)error
{
  NSAssert(NO, @"%@ is abstract", NSStringFromSelector(_cmd));
  return NO;
}

- (BOOL)killSimulatorProcessesMatchingPredicate:(NSPredicate *)predicate error:(NSError **)error
{
  NSArray *processes = [self.processQuery.simulatorProcesses filteredArrayUsingPredicate:predicate];
  for (id<FBProcessInfo> process in processes) {
    NSParameterAssert(process.processIdentifier > 1);
    if (![self killProcess:process error:error]) {
      return NO;
    }
    // See comment in `killSimulators:withError:`
    sleep(1);
  }
  return YES;
}

- (BOOL)safeShutdown:(FBSimulator *)simulator withError:(NSError **)error
{
  // Calling shutdown when already shutdown should be avoided (if detected).
  if (simulator.state == FBSimulatorStateShutdown) {
    return YES;
  }

  // Code 159 (Xcode 7) or 146 (Xcode 6) is 'Unable to shutdown device in current state: Shutdown'
  // We can safely ignore this and then confirm that the simulator is shutdown
  NSError *innerError = nil;
  if (![simulator.device shutdownWithError:&innerError] && innerError.code != 159 && innerError.code != 146) {
    return [FBSimulatorError failBoolWithError:innerError description:@"Simulator could not be shutdown" errorOut:error];
  }

  // We rely on the catch-all-non-manged kill command to do the dirty work.
  // This will confirm that all these simulators are shutdown.
  return [simulator waitOnState:FBSimulatorStateShutdown withError:error];
}

@end
