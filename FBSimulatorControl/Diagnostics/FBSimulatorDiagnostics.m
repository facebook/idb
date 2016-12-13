/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorDiagnostics.h"

#import <CoreSimulator/SimDevice.h>
#import <CoreSimulator/SimDeviceSet.h>

#import <FBControlCore/FBControlCore.h>

#import "FBSimulator+Helpers.h"
#import "FBSimulator.h"
#import "FBSimulatorHistory+Queries.h"

NSString *const FBSimulatorLogNameSyslog = @"system_log";
NSString *const FBSimulatorLogNameCoreSimulator = @"coresimulator";
NSString *const FBSimulatorLogNameSimulatorBootstrap = @"launchd_bootstrap";
NSString *const FBSimulatorLogNameScreenshot = @"screenshot";

@interface FBDiagnosticQuery (Simulators)

- (NSArray<FBDiagnostic *> *)performSimulator:(FBSimulatorDiagnostics *)diagnostic;

@end

@interface FBSimulatorDiagnostics ()

@property (nonatomic, weak, readonly) FBSimulator *simulator;
@property (nonatomic, strong, readonly) NSMutableDictionary *eventLogs;

@end

@implementation FBSimulatorDiagnostics

#pragma mark Initializers

+ (instancetype)withSimulator:(FBSimulator *)simulator
{
  NSString *storageDirectory = [FBSimulatorDiagnostics storageDirectoryForSimulator:simulator];
  return [[self alloc] initWithSimulator:simulator storageDirectory:storageDirectory];
}

- (instancetype)initWithSimulator:(FBSimulator *)simulator storageDirectory:(NSString *)storageDirectory
{
  self = [super initWithStorageDirectory:storageDirectory];
  if (!self) {
    return nil;
  }

  _simulator = simulator;
  _eventLogs = [NSMutableDictionary dictionary];

  return self;
}

#pragma mark Paths

- (NSString *)coreSimulatorLogsDirectory
{
  return [[NSHomeDirectory()
    stringByAppendingPathComponent:@"Library/Logs/CoreSimulator"]
    stringByAppendingPathComponent:self.simulator.udid];
}

#pragma mark Crash Log Diagnostics

- (NSArray<FBDiagnostic *> *)subprocessCrashesAfterDate:(NSDate *)date withProcessType:(FBCrashLogInfoProcessType)processType;
{
  return [FBConcurrentCollectionOperations
    filterMap:[self launchdSimSubprocessCrashesPathsAfterDate:date]
    predicate:[FBSimulatorDiagnostics predicateForProcessType:processType]
    map:^ FBDiagnostic * (FBCrashLogInfo *logInfo) {
      return [logInfo toDiagnostic:self.baseLogBuilder];
    }];
}

- (NSArray<FBDiagnostic *> *)userLaunchedProcessCrashesSinceLastLaunch
{
  NSPredicate *predicate = [FBSimulatorDiagnostics predicateForUserLaunchedProcessesInHistory:self.simulator.history];
  return [self userLaunchedProcessCrashesSinceLastLaunchWithPredicate:predicate];
}

- (NSArray<FBDiagnostic *> *)userLaunchedProcessCrashesSinceLastLaunchWithProcessIdentifier:(pid_t)processIdentifier
{
  NSPredicate *predicate = [FBCrashLogInfo predicateForCrashLogsWithProcessID:processIdentifier];
  return [self userLaunchedProcessCrashesSinceLastLaunchWithPredicate:predicate];
}

#pragma mark Standard Diagnostics

- (FBDiagnostic *)syslog
{
  return [[[[self.baseLogBuilder
    updatePath:self.systemLogPath]
    updateShortName:FBSimulatorLogNameSyslog]
    updateHumanReadableName:@"System Log"]
    build];
}

- (FBDiagnostic *)coreSimulator
{
  return [[[[self.baseLogBuilder
    updatePath:self.coreSimulatorLogPath]
    updateShortName:FBSimulatorLogNameCoreSimulator]
    updateHumanReadableName:@"Core Simulator Log"]
    build];
}

- (FBDiagnostic *)simulatorBootstrap
{
  NSString *expectedPath = [[self.simulator.device.deviceSet.setPath
    stringByAppendingPathComponent:self.simulator.udid]
    stringByAppendingPathComponent:@"/data/var/run/launchd_bootstrap.plist"];

  return [[[[self.baseLogBuilder
    updatePath:expectedPath]
    updateShortName:FBSimulatorLogNameSimulatorBootstrap]
    updateHumanReadableName:@"Launchd Bootstrap"]
    build];
}

- (FBDiagnostic *)video
{
  return [[[self.baseLogBuilder
    updateDiagnostic:[super video]]
    updateDiagnostic:self.eventLogs[FBiOSTargetLogNameVideo]]
    build];
}

- (FBDiagnostic *)screenshot
{
  return [[[[[self.baseLogBuilder
    updateShortName:FBSimulatorLogNameScreenshot]
    updateFileType:@"png"]
    updatePathFromDefaultLocation]
    updateDiagnostic:self.eventLogs[FBSimulatorLogNameScreenshot]]
    build];
}

- (FBDiagnostic *)stdOut:(FBProcessLaunchConfiguration *)configuration
{
  NSString *name = [NSString stringWithFormat:@"%@_out", configuration.identifiableName];
  return [[[[[self.baseLogBuilder
    updateStorageDirectory:[self stdOutErrContainersPath]]
    updateShortName:name]
    updateFileType:@"txt"]
    updatePathFromDefaultLocation]
    build];
}

- (FBDiagnostic *)stdErr:(FBProcessLaunchConfiguration *)configuration
{
  NSString *name = [NSString stringWithFormat:@"%@_err", configuration.identifiableName];
  return [[[[[self.baseLogBuilder
    updateStorageDirectory:[self stdOutErrContainersPath]]
    updateShortName:name]
    updateFileType:@"txt"]
    updatePathFromDefaultLocation]
    build];
}

- (NSArray<FBDiagnostic *> *)stdOutErrDiagnostics
{
  return [FBSimulatorDiagnostics diagnosticsForSubpathsOf:self.stdOutErrContainersPath];
}

- (NSDictionary<FBProcessInfo *, FBDiagnostic *> *)launchedProcessLogs
{
  NSString *aslPath = self.aslPath;
  if (!aslPath) {
    return @{};
  }

  FBASLParser *aslParser = [FBASLParser parserForPath:aslPath];
  if (!aslParser) {
    return @{};
  }

  NSArray *launchedProcesses = self.simulator.history.allUserLaunchedProcesses;
  NSMutableDictionary *logs = [NSMutableDictionary dictionary];
  for (FBProcessInfo *launchedProcess in launchedProcesses) {
    logs[launchedProcess] = [aslParser diagnosticForProcessInfo:launchedProcess logBuilder:self.baseLogBuilder];
  }

  return [logs copy];
}

- (NSArray<FBDiagnostic *> *)diagnosticsForApplicationWithBundleID:(nullable NSString *)bundleID withFilenames:(NSArray<NSString *> *)filenames fallbackToGlobalSearch:(BOOL)globalFallback
{
  NSString *directory = nil;
  if (bundleID) {
    directory = [self.simulator homeDirectoryOfApplicationWithBundleID:bundleID error:nil];
  }
  if (!directory && globalFallback) {
    directory = self.simulator.dataDirectory;
  }
  if (!directory) {
    return @[];
  }
  NSArray *paths = [FBFileFinder mostRecentFindFiles:filenames inDirectory:directory];
  return [FBSimulatorDiagnostics diagnosticsForPaths:paths];
}

- (NSArray<FBDiagnostic *> *)allDiagnostics
{
  NSMutableArray *logs = [NSMutableArray arrayWithArray:@[
    self.syslog,
    self.coreSimulator,
    self.simulatorBootstrap,
    self.video,
    self.screenshot
  ]];
  [logs addObjectsFromArray:[self userLaunchedProcessCrashesSinceLastLaunch]];
  [logs addObjectsFromArray:self.eventLogs.allValues];
  [logs addObjectsFromArray:self.stdOutErrDiagnostics];
  return [logs filteredArrayUsingPredicate:FBSimulatorDiagnostics.predicateForHasContent];
}

- (NSArray<FBDiagnostic *> *)perform:(FBDiagnosticQuery *)query
{
  return [[super perform:query] arrayByAddingObjectsFromArray:[query performSimulator:self]];
}

#pragma mark FBSimulatorEventSink Implementation

- (void)containerApplicationDidLaunch:(FBProcessInfo *)applicationProcess
{

}

- (void)containerApplicationDidTerminate:(FBProcessInfo *)applicationProcess expected:(BOOL)expected
{

}

- (void)connectionDidConnect:(FBSimulatorConnection *)connection
{

}

- (void)connectionDidDisconnect:(FBSimulatorConnection *)connection expected:(BOOL)expected
{

}

- (void)simulatorDidLaunch:(FBProcessInfo *)launchdProcess
{

}

- (void)simulatorDidTerminate:(FBProcessInfo *)launchdProcess expected:(BOOL)expected
{

}

- (void)agentDidLaunch:(FBAgentLaunchConfiguration *)launchConfig didStart:(FBProcessInfo *)agentProcess stdOut:(NSFileHandle *)stdOut stdErr:(NSFileHandle *)stdErr
{

}

- (void)agentDidTerminate:(FBProcessInfo *)agentProcess expected:(BOOL)expected
{

}

- (void)applicationDidLaunch:(FBApplicationLaunchConfiguration *)launchConfig didStart:(FBProcessInfo *)applicationProcess
{

}

- (void)applicationDidTerminate:(FBProcessInfo *)applicationProcess expected:(BOOL)expected
{

}

- (void)testmanagerDidConnect:(FBTestManager *)testManager
{
}

- (void)testmanagerDidDisconnect:(FBTestManager *)testManager
{
}

- (void)diagnosticAvailable:(FBDiagnostic *)diagnostic
{
  if (!diagnostic.shortName) {
    return;
  }
  self.eventLogs[diagnostic.shortName] = diagnostic;
}

- (void)didChangeState:(FBSimulatorState)state
{

}

- (void)terminationHandleAvailable:(id<FBTerminationHandle>)terminationHandle
{

}

#pragma mark Paths

+ (NSString *)storageDirectoryForSimulator:(FBSimulator *)simulator
{
  return [simulator.auxillaryDirectory stringByAppendingPathComponent:@"diagnostics"];
}

- (NSString *)systemLogPath
{
  return [self.simulator.device.logPath stringByAppendingPathComponent:@"system.log"];
}

- (NSString *)coreSimulatorLogPath
{
  return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs/CoreSimulator/CoreSimulator.log"];
}

- (NSString *)applicationContainersPath
{
  return [self.simulator.dataDirectory stringByAppendingPathComponent:@"Containers/Data/Application"];
}

- (NSString *)stdOutErrContainersPath
{
  return [self.storageDirectory stringByAppendingPathComponent:@"out_err"];
}

- (NSString *)aslPath
{
  return [self.coreSimulatorLogsDirectory stringByAppendingPathComponent:@"asl"];
}

#pragma mark Crash Logs

- (NSArray<FBCrashLogInfo *> *)launchdSimSubprocessCrashesPathsAfterDate:(NSDate *)date
{
  FBProcessInfo *launchdProcess = self.simulator.launchdProcess;
  if (!launchdProcess) {
    return @[];
  }

  NSPredicate *parentProcessPredicate = [NSPredicate predicateWithBlock:^ BOOL (FBCrashLogInfo *logInfo, NSDictionary *_) {
    return [logInfo.parentProcessName isEqualToString:@"launchd_sim"] && logInfo.parentProcessIdentifier == launchdProcess.processIdentifier;
  }];

  return [[FBCrashLogInfo crashInfoAfterDate:date] filteredArrayUsingPredicate:parentProcessPredicate];
}

- (NSArray<FBDiagnostic *> *)userLaunchedProcessCrashesSinceLastLaunchWithPredicate:(NSPredicate *)predicate
{
  // Going from state transition to 'Booted' can be after the crash report is written for an
  // Process that instacrashes around the same time the simulator is booted.
  // Instead, use the 'Booting' state, which will be before any Process could have been launched.
  NSDate *lastLaunchDate = [[[self.simulator.history
    lastChangeOfState:FBSimulatorStateBooted]
    lastChangeOfState:FBSimulatorStateBooting]
    timestamp];

  // If we don't have the last launch date, we can't reliably predict which processes are interesting.
  if (!lastLaunchDate) {
    return @[];
  }

  return [FBConcurrentCollectionOperations
    filterMap:[self launchdSimSubprocessCrashesPathsAfterDate:lastLaunchDate]
    predicate:predicate
    map:^ FBDiagnostic * (FBCrashLogInfo *logInfo) {
      return [logInfo toDiagnostic:self.baseLogBuilder];
    }];
}

+ (NSPredicate *)predicateForUserLaunchedProcessesInHistory:(FBSimulatorHistory *)history
{
  NSSet *pidSet = [NSSet setWithArray:[history.allUserLaunchedProcesses valueForKey:@"processIdentifier"]];
  return [NSPredicate predicateWithBlock:^ BOOL (FBCrashLogInfo *crashLog, NSDictionary *_) {
    return [pidSet containsObject:@(crashLog.processIdentifier)];
  }];
}

+ (NSPredicate *)predicateForProcessType:(FBCrashLogInfoProcessType)processType
{
  return [NSPredicate predicateWithBlock:^ BOOL (FBCrashLogInfo *crashLog, NSDictionary *_) {
    FBCrashLogInfoProcessType current = crashLog.processType;
    return (processType & current) == current;
  }];
}

#pragma mark Diagnostics

+ (NSArray<FBDiagnostic *> *)diagnosticsForSubpathsOf:(NSString *)container
{
  return [[self diagnosticsForPaths:[FBFileFinder contentsOfDirectoryWithBasePath:container]]
    filteredArrayUsingPredicate:self.predicateForHasContent];
}

+ (NSArray<FBDiagnostic *> *)diagnosticsForPaths:(NSArray<NSString *> *)paths
{
  NSMutableArray *array = [NSMutableArray array];
  for (NSString *path in paths) {
    [array addObject:[[[FBDiagnosticBuilder builder] updatePath:path] build]];
  }
  return [array filteredArrayUsingPredicate:self.predicateForHasContent];
}

@end

@implementation FBDiagnosticQuery_ApplicationLogs (Simulators)

- (NSArray<FBDiagnostic *> *)performSimulator:(FBSimulatorDiagnostics *)diagnostics
{
  return [diagnostics diagnosticsForApplicationWithBundleID:self.bundleID withFilenames:self.filenames fallbackToGlobalSearch:YES];
}

@end

@implementation FBDiagnosticQuery_Crashes (Simulators)

- (NSArray<FBDiagnostic *> *)performSimulator:(FBSimulatorDiagnostics *)diagnostics
{
  return [diagnostics subprocessCrashesAfterDate:self.date withProcessType:self.processType];
}

@end

@implementation FBDiagnosticQuery (Simulators)

- (NSArray<FBDiagnostic *> *)performSimulator:(FBSimulatorDiagnostics *)diagnostics
{
  return @[];
}

@end
