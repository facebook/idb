/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorLogs.h"

#import <CoreSimulator/SimDevice.h>
#import <CoreSimulator/SimDeviceSet.h>

#import "FBASLParser.h"
#import "FBConcurrentCollectionOperations.h"
#import "FBCrashLogInfo.h"
#import "FBProcessInfo.h"
#import "FBSimulator.h"
#import "FBSimulatorHistory+Queries.h"
#import "FBTaskExecutor.h"
#import "FBDiagnostic.h"

NSString *const FBSimulatorLogNameSyslog = @"system_log";
NSString *const FBSimulatorLogNameCoreSimulator = @"coresimulator";
NSString *const FBSimulatorLogNameSimulatorBootstrap = @"launchd_bootstrap";
NSString *const FBSimulatorLogNameVideo = @"video";
NSString *const FBSimulatorLogNameScreenshot = @"screenshot";

@interface FBSimulatorLogs ()

@property (nonatomic, weak, readonly) FBSimulator *simulator;
@property (nonatomic, copy, readonly) NSString *storageDirectory;
@property (nonatomic, strong, readonly) NSMutableDictionary *eventLogs;

@end

@implementation FBSimulatorLogs

#pragma mark Initializers

+ (instancetype)withSimulator:(FBSimulator *)simulator
{
  NSString *storageDirectory = [FBSimulatorLogs storageDirectoryForSimulator:simulator];
  return [[self alloc] initWithSimulator:simulator storageDirectory:storageDirectory];
}

- (instancetype)initWithSimulator:(FBSimulator *)simulator storageDirectory:(NSString *)storageDirectory
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _simulator = simulator;
  _storageDirectory = storageDirectory;
  _eventLogs = [NSMutableDictionary dictionary];

  return self;
}

#pragma mark Accessors

- (FBDiagnostic *)base
{
  return [self.logBuilder build];
}

- (FBDiagnostic *)syslog
{
  return [[[[self.logBuilder
    updatePath:self.systemLogPath]
    updateShortName:FBSimulatorLogNameSyslog]
    updateHumanReadableName:@"System Log"]
    build];
}

- (FBDiagnostic *)coreSimulator
{
  return [[[[self.logBuilder
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

  return [[[[self.logBuilder
    updatePath:expectedPath]
    updateShortName:FBSimulatorLogNameSimulatorBootstrap]
    updateHumanReadableName:@"Launchd Bootstrap"]
    build];
}

- (FBDiagnostic *)video
{
  return [[[[self.logBuilder
    updateShortName:FBSimulatorLogNameVideo]
    updateFileType:@"mp4"]
    updateWritableLog:self.eventLogs[FBSimulatorLogNameVideo]]
    build];
}

- (FBDiagnostic *)screenshot
{
  return [[[[self.logBuilder
    updateShortName:FBSimulatorLogNameScreenshot]
    updateFileType:@"png"]
    updateWritableLog:self.eventLogs[FBSimulatorLogNameVideo]]
    build];
}

- (NSArray *)subprocessCrashesAfterDate:(NSDate *)date
{
  return [FBConcurrentCollectionOperations
    map:[self launchdSimSubprocessCrashesPathsAfterDate:date]
    withBlock:^ FBDiagnostic * (FBCrashLogInfo *logInfo) {
      return [logInfo toWritableLog:self.logBuilder];
    }];
}

- (NSArray *)userLaunchedProcessCrashesSinceLastLaunch
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
    predicate:[FBSimulatorLogs predicateForUserLaunchedProcessesInHistory:self.simulator.history]
    map:^ FBDiagnostic * (FBCrashLogInfo *logInfo) {
      return [logInfo toWritableLog:self.logBuilder];
    }];
}

- (NSDictionary *)launchedProcessLogs
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
    logs[launchedProcess] = [aslParser diagnosticForProcessInfo:launchedProcess logBuilder:self.logBuilder];
  }

  return [logs copy];
}

- (NSArray *)allLogs
{
  NSPredicate *predicate = [NSPredicate predicateWithBlock:^ BOOL (FBDiagnostic *log, NSDictionary *_) {
    return log.hasLogContent;
  }];

  NSMutableArray *logs = [NSMutableArray arrayWithArray:@[
    self.syslog,
    self.coreSimulator,
    self.simulatorBootstrap
  ]];
  [logs addObjectsFromArray:[self userLaunchedProcessCrashesSinceLastLaunch]];
  [logs addObjectsFromArray:self.eventLogs.allValues];
  return [logs filteredArrayUsingPredicate:predicate];
}

#pragma mark FBSimulatorEventSink Implementation

- (void)containerApplicationDidLaunch:(FBProcessInfo *)applicationProcess
{

}

- (void)containerApplicationDidTerminate:(FBProcessInfo *)applicationProcess expected:(BOOL)expected
{

}

- (void)framebufferDidStart:(FBSimulatorFramebuffer *)framebuffer
{

}

- (void)framebufferDidTerminate:(FBSimulatorFramebuffer *)framebuffer expected:(BOOL)expected
{

}

- (void)simulatorDidLaunch:(FBProcessInfo *)launchdSimProcess
{

}

- (void)simulatorDidTerminate:(FBProcessInfo *)launchdSimProcess expected:(BOOL)expected
{

}

- (void)agentDidLaunch:(FBAgentLaunchConfiguration *)launchConfig didStart:(FBProcessInfo *)agentProcess stdOut:(NSFileHandle *)stdOut stdErr:(NSFileHandle *)stdErr
{

}

- (void)agentDidTerminate:(FBProcessInfo *)agentProcess expected:(BOOL)expected
{

}

- (void)applicationDidLaunch:(FBApplicationLaunchConfiguration *)launchConfig didStart:(FBProcessInfo *)applicationProcess stdOut:(NSFileHandle *)stdOut stdErr:(NSFileHandle *)stdErr
{

}

- (void)applicationDidTerminate:(FBProcessInfo *)applicationProcess expected:(BOOL)expected
{

}

- (void)logAvailable:(FBDiagnostic *)log
{
  if (!log.shortName) {
    return;
  }
  self.eventLogs[log.shortName] = log;
}

- (void)didChangeState:(FBSimulatorState)state
{

}

- (void)terminationHandleAvailable:(id<FBTerminationHandle>)terminationHandle
{

}

#pragma mark Private

- (FBDiagnosticBuilder *)logBuilder
{
  return [FBDiagnosticBuilder.builder updateStorageDirectory:self.storageDirectory];
}

+ (NSString *)storageDirectoryForSimulator:(FBSimulator *)simulator
{
  return [simulator.auxillaryDirectory stringByAppendingPathComponent:@"logs"];
}

- (NSString *)systemLogPath
{
  return [self.simulator.device.logPath stringByAppendingPathComponent:@"system.log"];
}

- (NSString *)coreSimulatorLogPath
{
  return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs/CoreSimulator/CoreSimulator.log"];
}

- (NSString *)diagnosticReportsPath
{
  return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs/DiagnosticReports"];
}

- (NSString *)aslPath
{
  return [[[NSHomeDirectory()
    stringByAppendingPathComponent:@"Library/Logs/CoreSimulator"]
    stringByAppendingPathComponent:self.simulator.udid]
    stringByAppendingPathComponent:@"asl"];
}

- (NSArray *)crashInfoAfterDate:(NSDate *)date
{
  NSString *basePath = self.diagnosticReportsPath;

  return [FBConcurrentCollectionOperations
    filterMap:[NSFileManager.defaultManager contentsOfDirectoryAtPath:basePath error:nil]
    predicate:[FBSimulatorLogs predicateForFilesWithBasePath:basePath afterDate:date withExtension:@"crash"]
    map:^ FBCrashLogInfo * (NSString *fileName) {
      NSString *path = [basePath stringByAppendingPathComponent:fileName];
      return [FBCrashLogInfo fromCrashLogAtPath:path];
    }];
}

- (NSArray *)launchdSimSubprocessCrashesPathsAfterDate:(NSDate *)date
{
  FBProcessInfo *launchdProcess = self.simulator.launchdSimProcess;
  if (!launchdProcess) {
    return @[];
  }

  NSPredicate *parentProcessPredicate = [NSPredicate predicateWithBlock:^ BOOL (FBCrashLogInfo *logInfo, NSDictionary *_) {
    return [logInfo.parentProcessName isEqualToString:@"launchd_sim"] && logInfo.parentProcessIdentifier == launchdProcess.processIdentifier;
  }];

  return [[self crashInfoAfterDate:date] filteredArrayUsingPredicate:parentProcessPredicate];
}

+ (NSPredicate *)predicateForFilesWithBasePath:(NSString *)basePath afterDate:(NSDate *)date withExtension:(NSString *)extension
{
  NSFileManager *fileManager = NSFileManager.defaultManager;
  NSPredicate *datePredicate = [NSPredicate predicateWithValue:YES];
  if (date) {
    datePredicate = [NSPredicate predicateWithBlock:^ BOOL (NSString *fileName, NSDictionary *_) {
      NSString *path = [basePath stringByAppendingPathComponent:fileName];
      NSDictionary *attributes = [fileManager attributesOfItemAtPath:path error:nil];
      return [attributes.fileModificationDate isGreaterThanOrEqualTo:date];
    }];
  }
  return [NSCompoundPredicate andPredicateWithSubpredicates:@[
    [NSPredicate predicateWithFormat:@"pathExtension == %@", extension],
    datePredicate
  ]];
}

+ (NSPredicate *)predicateForUserLaunchedProcessesInHistory:(FBSimulatorHistory *)history
{
  NSSet *pidSet = [NSSet setWithArray:[history.allUserLaunchedProcesses valueForKey:@"processIdentifier"]];
  return [NSPredicate predicateWithBlock:^ BOOL (FBCrashLogInfo *crashLog, NSDictionary *_) {
    return [pidSet containsObject:@(crashLog.processIdentifier)];
  }];
}

@end
