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

#import "FBSimulator.h"
#import "FBProcessLaunchConfiguration+Simulator.h"

FBDiagnosticName const FBDiagnosticNameCoreSimulator = @"coresimulator";
FBDiagnosticName const FBDiagnosticNameSimulatorBootstrap = @"launchd_bootstrap";

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

- (NSArray<FBDiagnostic *> *)subprocessCrashesAfterDate:(NSDate *)date withProcessType:(FBCrashLogInfoProcessType)processType
{
  NSPredicate *predicate = [FBSimulatorDiagnostics predicateForProcessType:processType];
  return [self subprocessCrashesAfterDate:date withPredicate:predicate];
}

- (NSArray<FBDiagnostic *> *)subprocessCrashesAfterDate:(NSDate *)date processsIdentifier:(pid_t)processIdentifier processType:(FBCrashLogInfoProcessType)processType
{
  NSPredicate *predicate = [NSCompoundPredicate andPredicateWithSubpredicates:@[
    [FBSimulatorDiagnostics predicateForProcessType:processType],
    [FBSimulatorDiagnostics predicateForProcessIdentifier:processIdentifier],
  ]];
  return [self subprocessCrashesAfterDate:date withPredicate:predicate];
}

- (NSArray<FBDiagnostic *> *)subprocessCrashesAfterDate:(NSDate *)date withPredicate:(NSPredicate *)predicate
{
  return [FBConcurrentCollectionOperations
    filterMap:[self launchdSimSubprocessCrashesPathsAfterDate:date]
    predicate:predicate
    map:^ FBDiagnostic * (FBCrashLogInfo *logInfo) {
      return [logInfo toDiagnostic:self.baseLogBuilder];
    }];
}

#pragma mark Standard Diagnostics

- (FBDiagnostic *)syslog
{
  return [[[[self.baseLogBuilder
    updatePath:self.systemLogPath]
    updateShortName:FBDiagnosticNameSyslog]
    updateHumanReadableName:@"System Log"]
    build];
}

- (FBDiagnostic *)coreSimulator
{
  return [[[[self.baseLogBuilder
    updatePath:self.coreSimulatorLogPath]
    updateShortName:FBDiagnosticNameCoreSimulator]
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
    updateShortName:FBDiagnosticNameSimulatorBootstrap]
    updateHumanReadableName:@"Launchd Bootstrap"]
    build];
}

- (FBDiagnostic *)video
{
  return [[[self.baseLogBuilder
    updateDiagnostic:[super video]]
    updateDiagnostic:self.eventLogs[FBDiagnosticNameVideo]]
    build];
}

- (FBDiagnostic *)screenshot
{
  return [[[[[self.baseLogBuilder
    updateShortName:FBDiagnosticNameScreenshot]
    updateFileType:@"png"]
    updatePathFromDefaultLocation]
    updateDiagnostic:self.eventLogs[FBDiagnosticNameScreenshot]]
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

- (NSArray<FBDiagnostic *> *)diagnosticsForApplicationWithBundleID:(nullable NSString *)bundleID withFilenames:(NSArray<NSString *> *)filenames withFilenameGlobs:(nonnull NSArray<NSString *> *)filenameGlobs fallbackToGlobalSearch:(BOOL)globalFallback
{
  NSString *directory = nil;
  if (bundleID) {
    directory = [[self.simulator dataContainerOfApplicationWithBundleID:bundleID] await:nil];
  }
  if (!directory && globalFallback) {
    directory = self.simulator.dataDirectory;
  }
  if (!directory) {
    return @[];
  }
  NSArray<NSString *> *pathsByFilenames = [FBFileFinder mostRecentFindFiles:filenames inDirectory:directory];
  NSArray<NSString *> *pathsByFilenameGlobs = [FBFileFinder recursiveFindByFilenameGlobs:filenameGlobs inDirectory:directory];
  NSArray<NSString *> *paths = [pathsByFilenames arrayByAddingObjectsFromArray:pathsByFilenameGlobs];
  return [FBSimulatorDiagnostics diagnosticsForPaths:paths];
}

- (NSArray<FBDiagnostic *> *)allDiagnostics
{
  NSMutableArray<FBDiagnostic *> *logs = [[super allDiagnostics] mutableCopy];
  [logs addObjectsFromArray:@[
    self.syslog,
    self.coreSimulator,
    self.simulatorBootstrap,
    self.video,
    self.screenshot
  ]];
  [logs addObjectsFromArray:self.eventLogs.allValues];
  [logs addObjectsFromArray:self.stdOutErrDiagnostics];
  [logs addObjectsFromArray:[super allDiagnostics]];
  return [logs filteredArrayUsingPredicate:FBSimulatorDiagnostics.predicateForHasContent];
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

- (void)agentDidLaunch:(FBSimulatorAgentOperation *)operation
{

}

- (void)agentDidTerminate:(FBSimulatorAgentOperation *)operation statLoc:(int)statLoc
{

}

- (void)applicationDidLaunch:(FBSimulatorApplicationOperation *)operation
{

}

- (void)applicationDidTerminate:(FBSimulatorApplicationOperation *)operation expected:(BOOL)expected
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

+ (NSPredicate *)predicateForProcessType:(FBCrashLogInfoProcessType)processType
{
  return [NSPredicate predicateWithBlock:^ BOOL (FBCrashLogInfo *crashLog, NSDictionary *_) {
    FBCrashLogInfoProcessType current = crashLog.processType;
    return (processType & current) == current;
  }];
}

+ (NSPredicate *)predicateForProcessIdentifier:(pid_t)processIdentifier
{
  return [NSPredicate predicateWithBlock:^ BOOL (FBCrashLogInfo *crashLog, NSDictionary *_) {
    return processIdentifier == crashLog.processIdentifier;
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
