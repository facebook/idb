/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBLogicTestProcess.h"

#import <sys/wait.h>

#import <FBControlCore/FBControlCore.h>
#import <FBSimulatorControl/FBSimulatorControl.h>
#import <XCTestBootstrap/XCTestBootstrap.h>

static NSTimeInterval const CrashLogStartDateFuzz = -10;

@interface FBLogicTestProcess ()

@property (nonatomic, copy, readonly) NSString *launchPath;
@property (nonatomic, copy, readonly) NSArray<NSString *> *arguments;
@property (nonatomic, copy, readonly) NSDictionary<NSString *, NSString *> *environment;
@property (nonatomic, assign, readonly) BOOL waitForDebugger;
@property (nonatomic, strong, readonly) id<FBFileConsumer> stdOutReader;
@property (nonatomic, strong, readonly) id<FBFileConsumer> stdErrReader;
@property (nonatomic, assign, readwrite) BOOL xctestProcessIsSubprocess;

@property (nonatomic, copy, readwrite, nullable) NSDate *startDate;

- (instancetype)initWithLaunchPath:(NSString *)launchPath arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment waitForDebugger:(BOOL)waitForDebugger stdOutReader:(id<FBFileConsumer>)stdOutReader stdErrReader:(id<FBFileConsumer>)stdErrReader;
- (BOOL)processDidTerminateNormallyWithProcessIdentifier:(pid_t)processIdentifier didTimeout:(BOOL)didTimeout exitCode:(int)exitCode error:(NSError **)error;
+ (nullable FBCrashLogInfo *)crashLogsForChildProcessOf:(pid_t)processIdentifier since:(NSDate *)sinceDate;
+ (nullable NSString *)sampleStalledProcess:(pid_t)processIdentifier;

@end

@interface FBLogicTestProcess_Task : FBLogicTestProcess

@property (nonatomic, strong, readwrite, nullable) FBTask *task;

@end

@implementation FBLogicTestProcess_Task

- (pid_t)startWithError:(NSError **)error
{
  // Call super, it won't error out
  [super startWithError:nil];

  self.task = [[[[[[[[FBTaskBuilder
    withLaunchPath:self.launchPath]
    withArguments:self.arguments]
    withEnvironment:self.environment]
    withStdOutConsumer:self.stdOutReader]
    withStdErrConsumer:self.stdErrReader]
    withAcceptableTerminationStatusCodes:[NSSet setWithArray:@[@0, @1]]]
    build]
    startAsynchronously];

  if (self.task.error) {
    [[[FBControlCoreError
      describeFormat:@"Logic Test Process Errored %@", self.task.error.localizedDescription]
      causedBy:self.task.error]
      fail:error];
    self.task = nil;
    return -1;
  }
  return self.task.processIdentifier;
}

- (void)terminate
{
  [self.task terminate];
}

- (BOOL)waitForCompletionWithTimeout:(NSTimeInterval)timeout error:(NSError **)error
{
  if (!self.task) {
    return [[FBControlCoreError
      describe:@"No task to await completion of"]
      failBool:error];
  }

  // Perform the underlying wait.
  FBTask *task = self.task;
  NSError *timeoutError = nil;
  BOOL waitSuccessful = [task waitForCompletionWithTimeout:timeout error:&timeoutError];
  int exitCode = task.error.userInfo[@"exitcode"] ? [task.error.userInfo[@"exitcode"] intValue] : 0;

  // Check that we exited normally
  if (![self processDidTerminateNormallyWithProcessIdentifier:task.processIdentifier didTimeout:(waitSuccessful == NO) exitCode:exitCode error:error]) {
    return NO;
  }
  return YES;
}

@end

@interface FBLogicTestProcess_SimulatorAgent : FBLogicTestProcess

@property (nonatomic, strong, readonly) FBSimulator *simulator;

@property (nonatomic, strong, readwrite) FBPipeReader *stdOutPipe;
@property (nonatomic, strong, readwrite) FBPipeReader *stdErrPipe;
@property (nonatomic, strong, readwrite) FBProcessInfo *process;

@property (atomic, assign, readwrite) BOOL hasTerminated;
@property (atomic, assign, readwrite) int exitCode;

@end

@implementation FBLogicTestProcess_SimulatorAgent

- (instancetype)initWithSimulator:(FBSimulator *)simulator launchPath:(NSString *)launchPath arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment waitForDebugger:(BOOL)waitForDebugger stdOutReader:(id<FBFileConsumer>)stdOutReader stdErrReader:(id<FBFileConsumer>)stdErrReader
{
  self = [super initWithLaunchPath:launchPath arguments:arguments environment:environment waitForDebugger:waitForDebugger stdOutReader:stdOutReader stdErrReader:stdErrReader];
  if (!self) {
    return nil;
  }

  _simulator = simulator;

  return self;
}

- (pid_t)startWithError:(NSError **)error
{
  // Call super, it won't error out
  [super startWithError:nil];

  // Create the Pipes
  self.stdOutPipe = [FBPipeReader pipeReaderWithConsumer:self.stdOutReader];
  self.stdErrPipe = [FBPipeReader pipeReaderWithConsumer:self.stdErrReader];
  NSError *innerError = nil;

  // Start Reading the Stdout
  if (![self.stdOutPipe startReadingWithError:&innerError]) {
    [[[FBXCTestError
      describeFormat:@"Failed to read the stdout of Logic Test Process %@", self.launchPath]
      causedBy:innerError]
      fail:error];
    return -1;
  }

  // Start Reading the Stderr
  if (![self.stdErrPipe startReadingWithError:&innerError]) {
    [[[FBXCTestError
      describeFormat:@"Failed to read the stdout of Logic Test Process %@", self.launchPath]
      causedBy:innerError]
      fail:error];
    return -1;
  }

  // Launch The Process
  FBAgentLaunchHandler handler = ^(int stat_loc){
    if (WIFEXITED(stat_loc)) {
      self.exitCode = WEXITSTATUS(stat_loc);
    } else if (WIFSIGNALED(stat_loc)) {
      self.exitCode = WTERMSIG(stat_loc);
    }
    self.hasTerminated = YES;
  };
  self.process = [[FBAgentLaunchStrategy strategyWithSimulator:self.simulator]
    launchAgentWithLaunchPath:self.launchPath
    arguments:self.arguments
    environment:self.environment
    waitForDebugger:self.waitForDebugger
    stdOut:self.stdOutPipe.pipe.fileHandleForWriting
    stdErr:self.stdErrPipe.pipe.fileHandleForWriting
    terminationHandler:handler
    error:&innerError];
  if (!self.process) {
    [[[FBXCTestError
      describeFormat:@"Failed to launch Logic Test Process %@", self.launchPath]
      causedBy:innerError]
      fail:error];
    return -1;
  }

  return self.process.processIdentifier;
}

- (void)terminate
{

}

- (BOOL)waitForCompletionWithTimeout:(NSTimeInterval)timeout error:(NSError **)error
{
  BOOL waitSuccessful = [NSRunLoop.currentRunLoop spinRunLoopWithTimeout:timeout untilTrue:^BOOL{
    return self.hasTerminated;
  }];

  // Check that we exited normally
  if (![self processDidTerminateNormallyWithProcessIdentifier:self.process.processIdentifier didTimeout:(waitSuccessful == NO) exitCode:self.exitCode error:error]) {
    return NO;
  }
  return YES;
}

@end

@implementation FBLogicTestProcess

+ (instancetype)taskProcessWithLaunchPath:(NSString *)launchPath arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment waitForDebugger:(BOOL)waitForDebugger stdOutReader:(id<FBFileConsumer>)stdOutReader stdErrReader:(id<FBFileConsumer>)stdErrReader
{
  return [[FBLogicTestProcess_Task alloc] initWithLaunchPath:launchPath arguments:arguments environment:environment waitForDebugger:waitForDebugger stdOutReader:stdOutReader stdErrReader:stdErrReader];
}

+ (instancetype)simulatorSpawnProcess:(FBSimulator *)simulator launchPath:(NSString *)launchPath arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment waitForDebugger:(BOOL)waitForDebugger stdOutReader:(id<FBFileConsumer>)stdOutReader stdErrReader:(id<FBFileConsumer>)stdErrReader
{
  return [[FBLogicTestProcess_SimulatorAgent alloc] initWithSimulator:simulator launchPath:launchPath arguments:arguments environment:environment waitForDebugger:waitForDebugger stdOutReader:stdOutReader stdErrReader:stdErrReader];
}

- (instancetype)initWithLaunchPath:(NSString *)launchPath arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment waitForDebugger:(BOOL)waitForDebugger stdOutReader:(id<FBFileConsumer>)stdOutReader stdErrReader:(id<FBFileConsumer>)stdErrReader
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _launchPath = launchPath;
  _arguments = arguments;
  _environment = environment;
  _waitForDebugger = waitForDebugger;
  _stdOutReader = stdOutReader;
  _stdErrReader = stdErrReader;

  return self;
}

- (pid_t)startWithError:(NSError **)error
{
  // Construct and launch the task.
  self.startDate = [NSDate.date dateByAddingTimeInterval:CrashLogStartDateFuzz];
  return 0;
}

- (void)terminate
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
}

- (BOOL)waitForCompletionWithTimeout:(NSTimeInterval)timeout error:(NSError **)error
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return NO;
}

- (BOOL)processDidTerminateNormallyWithProcessIdentifier:(pid_t)processIdentifier didTimeout:(BOOL)didTimeout exitCode:(int)exitCode error:(NSError **)error
{
  // If the xctest process has stalled, we should sample it (if possible), then terminate it.
  if (didTimeout) {
    NSString *sample = [FBLogicTestProcess sampleStalledProcess:processIdentifier];
    [self terminate];
    return [[FBXCTestError
      describeFormat:@"The xctest process stalled: %@", sample]
      failBool:error];
  }

  // If exited abnormally, check for a crash log
  if (exitCode != 0 && exitCode != 1) {
    FBCrashLogInfo *crashLogInfo = [FBLogicTestProcess crashLogsForChildProcessOf:processIdentifier since:self.startDate];
    if (crashLogInfo) {
      FBDiagnostic *diagnosticCrash = [crashLogInfo toDiagnostic:FBDiagnosticBuilder.builder];
      return [[FBXCTestError
        describeFormat:@"xctest process crashed\n %@", diagnosticCrash.asString]
        failBool:error];
    }
    return [[FBXCTestError
      describeFormat:@"xctest process exited abnormally with exit code %d", exitCode]
      failBool:error];
  }
  return YES;
}

+ (nullable FBCrashLogInfo *)crashLogsForChildProcessOf:(pid_t)processIdentifier since:(NSDate *)sinceDate
{
  NSSet<NSNumber *> *possiblePPIDs = [NSSet setWithArray:@[
    @(processIdentifier),
    @(NSProcessInfo.processInfo.processIdentifier),
  ]];

  NSPredicate *crashLogInfoPredicate = [NSPredicate predicateWithBlock:^ BOOL (FBCrashLogInfo *crashLogInfo, id _) {
    return [possiblePPIDs containsObject:@(crashLogInfo.parentProcessIdentifier)];
  }];
  return [NSRunLoop.currentRunLoop spinRunLoopWithTimeout:FBControlCoreGlobalConfiguration.fastTimeout untilExists:^ FBCrashLogInfo * {
    return [[[FBCrashLogInfo
      crashInfoAfterDate:sinceDate]
      filteredArrayUsingPredicate:crashLogInfoPredicate]
      firstObject];
  }];
}

+ (nullable NSString *)sampleStalledProcess:(pid_t)processIdentifier
{
  return [[[[FBTaskBuilder
    withLaunchPath:@"/usr/bin/sample" arguments:@[@(processIdentifier).stringValue, @"1"]]
    build]
    startSynchronouslyWithTimeout:5]
    stdOut];
}

@end
