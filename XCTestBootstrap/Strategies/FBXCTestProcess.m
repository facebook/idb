/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBXCTestProcess.h"

#import <sys/wait.h>

#import <FBControlCore/FBControlCore.h>

#import "XCTestBootstrapError.h"
#import "FBXCTestProcessExecutor.h"

static NSTimeInterval const CrashLogStartDateFuzz = -20;
static NSTimeInterval const CrashLogWaitTime = 180; // In case resources are pegged, just wait
static NSUInteger const SampleDuration = 1;
static NSTimeInterval const SampleTimeoutSubtraction = SampleDuration + 1;

@interface FBXCTestProcess() <FBLaunchedProcess>

@property (nonatomic, strong, readonly) FBCrashLogNotifier *notifier;

@end

@implementation FBXCTestProcess

@synthesize processIdentifier = _processIdentifier;
@synthesize exitCode = _exitCode;

#pragma mark Initializers

- (instancetype)initWithProcessIdentifier:(pid_t)processIdentifier exitCode:(FBFuture<NSNumber *> *)exitCode
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _processIdentifier = processIdentifier;
  _exitCode = exitCode;

  return self;
}

- (NSString *)description
{
  return [NSString stringWithFormat:@"xctest Process %d | State %@", self.processIdentifier, self.exitCode];
}

#pragma mark NSObject

#pragma mark Public

+ (FBFuture<id<FBLaunchedProcess>> *)startWithLaunchPath:(NSString *)launchPath arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment waitForDebugger:(BOOL)waitForDebugger stdOutConsumer:(id<FBDataConsumer>)stdOutConsumer stdErrConsumer:(id<FBDataConsumer>)stdErrConsumer executor:(id<FBXCTestProcessExecutor>)executor timeout:(NSTimeInterval)timeout logger:(id<FBControlCoreLogger>)logger
{
  FBCrashLogNotifier *notifier = [FBCrashLogNotifier.sharedInstance startListening:YES];
  NSDate *startDate = NSDate.date;

  return [[executor
    startProcessWithLaunchPath:launchPath arguments:arguments environment:environment stdOutConsumer:stdOutConsumer stdErrConsumer:stdErrConsumer]
    onQueue:executor.workQueue map:^(id<FBLaunchedProcess> processInfo) {
      // Since launching the process may make some time, we still want to respect the timeout.
      // For this reason we have to take this delta into account.
      // In addition, the timing out of the process is also more agressive, since we have to take into account the time to take a stack sample
      NSTimeInterval realTimeout = MAX(timeout - [NSDate.date timeIntervalSinceDate:startDate] - SampleTimeoutSubtraction, 0);

      // Additionally, we make the start date of the process appear slightly older than we might think, this is in order that we can catch crash logs that may match this process.
      NSDate *fuzzedStartDate = [startDate dateByAddingTimeInterval:CrashLogStartDateFuzz];

      FBFuture<NSNumber *> *exitCode = [FBXCTestProcess onQueue:executor.workQueue decorateLaunchedWithErrorHandlingProcess:processInfo startDate:fuzzedStartDate timeout:realTimeout notifier:notifier logger:logger];
      return [[FBXCTestProcess alloc] initWithProcessIdentifier:processInfo.processIdentifier exitCode:exitCode];
    }];
}

#pragma mark Private

+ (FBFuture<NSNumber *> *)onQueue:(dispatch_queue_t)queue decorateLaunchedWithErrorHandlingProcess:(id<FBLaunchedProcess>)processInfo startDate:(NSDate *)startDate timeout:(NSTimeInterval)timeout notifier:(FBCrashLogNotifier *)notifier logger:(id<FBControlCoreLogger>)logger
{
  FBFuture<NSNumber *> *completionFuture = [processInfo.exitCode
    onQueue:queue fmap:^(NSNumber *exitCode) {
      return [FBXCTestProcess onQueue:queue confirmNormalExitFor:processInfo.processIdentifier exitCode:exitCode.intValue startDate:startDate notifier:notifier crashLogWaitTime:CrashLogWaitTime logger:logger];
    }];
  FBFuture<NSNumber *> *timeoutFuture = [FBXCTestProcess onQueue:queue timeoutFuture:timeout processIdentifier:processInfo.processIdentifier];
  return [FBFuture race:@[completionFuture, timeoutFuture]];
}

+ (FBFuture<NSNumber *> *)onQueue:(dispatch_queue_t)queue timeoutFuture:(NSTimeInterval)timeout processIdentifier:(pid_t)processIdentifier
{
  return [[FBFuture
    futureWithDelay:timeout future:FBFuture.empty]
    onQueue:queue fmap:^(id _) {
      return [FBXCTestProcess onQueue:queue timeoutErrorWithTimeout:timeout processIdentifier:processIdentifier];
    }];
}

+ (FBFuture<id> *)onQueue:(dispatch_queue_t)queue timeoutErrorWithTimeout:(NSTimeInterval)timeout processIdentifier:(pid_t)processIdentifier
{
  return [[[FBTaskBuilder
    withLaunchPath:@"/usr/bin/sample" arguments:@[@(processIdentifier).stringValue, @(SampleDuration).stringValue]]
    runUntilCompletion]
    onQueue:queue fmap:^(FBTask *task) {
      return [[FBXCTestError
        describeFormat:@"Waited %f seconds for process %d to terminate, but the xctest process stalled: %@", timeout, processIdentifier, task.stdOut]
        failFuture];
    }];
}

+ (FBFuture<NSNumber *> *)onQueue:(dispatch_queue_t)queue confirmNormalExitFor:(pid_t)processIdentifier exitCode:(int)exitCode startDate:(NSDate *)startDate notifier:(FBCrashLogNotifier *)notifier crashLogWaitTime:(NSTimeInterval)crashLogWaitTime logger:(id<FBControlCoreLogger>)logger
{
  // If exited abnormally, check for a crash log
  if (exitCode == 0 || exitCode == 1) {
    return [FBFuture futureWithResult:@(exitCode)];
  }
  [logger logFormat:@"xctest process (%d) exited with code %d, checking for crash log for %f seconds", processIdentifier, exitCode, crashLogWaitTime];
  return [[[FBXCTestProcess
    onQueue:queue crashLogsForTerminationOfProcess:processIdentifier since:startDate notifier:notifier crashLogWaitTime:crashLogWaitTime]
    rephraseFailure:@"xctest process (%d) exited abnormally (exit code %d) with no crash log, to check for yourself look in ~/Library/Logs/DiagnosticReports", processIdentifier, exitCode]
    onQueue:queue fmap:^(FBCrashLogInfo *crashInfo) {
      NSString *crashString = [NSString stringWithContentsOfFile:crashInfo.crashPath encoding:NSUTF8StringEncoding error:nil];
      return [[FBXCTestError
        describeFormat:@"xctest process crashed\n %@", crashString]
        failFuture];
    }];
}

+ (FBFuture<FBCrashLogInfo *> *)onQueue:(dispatch_queue_t)queue crashLogsForTerminationOfProcess:(pid_t)processIdentifier since:(NSDate *)sinceDate notifier:(FBCrashLogNotifier *)notifier crashLogWaitTime:(NSTimeInterval)crashLogWaitTime
{
  NSPredicate *predicate = [NSCompoundPredicate andPredicateWithSubpredicates:@[
    [FBCrashLogInfo predicateForCrashLogsWithProcessID:processIdentifier],
    [FBCrashLogInfo predicateNewerThanDate:sinceDate],
  ]];

  return [[notifier
    nextCrashLogForPredicate:predicate]
    timeout:crashLogWaitTime waitingFor:@"Crash logs for terminated process %d to appear", processIdentifier];
}

@end
