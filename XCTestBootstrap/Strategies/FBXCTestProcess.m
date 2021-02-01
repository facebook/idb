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

@interface FBXCTestProcess ()

@property (nonatomic, strong, readonly) id<FBLaunchedProcess> wrappedProcess;

@end

@implementation FBXCTestProcess

#pragma mark Initializers

- (instancetype)initWithWrappedProcess:(id<FBLaunchedProcess>)wrappedProcess completedNormally:(FBFuture<NSNumber *> *)completedNormally
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _wrappedProcess = wrappedProcess;
  _completedNormally = completedNormally;

  return self;
}

- (NSString *)description
{
  return [NSString stringWithFormat:@"xctest Process %@ | State %@", self.wrappedProcess, self.completedNormally];
}

- (pid_t)processIdentifier
{
  return self.wrappedProcess.processIdentifier;
}

- (FBFuture<NSNumber *> *)exitCode
{
  return self.wrappedProcess.exitCode;
}

- (FBFuture<NSNumber *> *)statLoc
{
  return self.wrappedProcess.statLoc;
}

- (FBFuture<NSNumber *> *)signal
{
  return self.wrappedProcess.signal;
}

#pragma mark Public

+ (FBFuture<FBXCTestProcess *> *)startWithLaunchPath:(NSString *)launchPath arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment waitForDebugger:(BOOL)waitForDebugger stdOutConsumer:(id<FBDataConsumer>)stdOutConsumer stdErrConsumer:(id<FBDataConsumer>)stdErrConsumer executor:(id<FBXCTestProcessExecutor>)executor timeout:(NSTimeInterval)timeout logger:(id<FBControlCoreLogger>)logger
{
  FBCrashLogNotifier *notifier = [FBCrashLogNotifier.sharedInstance startListening:YES];
  NSDate *startDate = NSDate.date;

  return [[executor
    startProcessWithLaunchPath:launchPath arguments:arguments environment:environment stdOutConsumer:stdOutConsumer stdErrConsumer:stdErrConsumer]
    onQueue:executor.workQueue map:^ FBXCTestProcess * (id<FBLaunchedProcess> process) {
      // Since launching the process may make some time, we still want to respect the timeout.
      // For this reason we have to take this delta into account.
      // In addition, the timing out of the process is also more agressive, since we have to take into account the time to take a stack sample
      NSTimeInterval realTimeout = MAX(timeout - [NSDate.date timeIntervalSinceDate:startDate] - SampleTimeoutSubtraction, 0);

      // Additionally, we make the start date of the process appear slightly older than we might think, this is in order that we can catch crash logs that may match this process.
      NSDate *fuzzedStartDate = [startDate dateByAddingTimeInterval:CrashLogStartDateFuzz];

      FBFuture<NSNumber *> *completedNormally = [FBXCTestProcess onQueue:executor.workQueue decorateLaunchedWithErrorHandlingProcess:process startDate:fuzzedStartDate timeout:realTimeout notifier:notifier logger:logger];
      return [[FBXCTestProcess alloc] initWithWrappedProcess:process completedNormally:completedNormally];
    }];
}

+ (FBFuture<NSNumber *> *)ensureProcess:(id<FBLaunchedProcess>)process completesWithin:(NSTimeInterval)timeout queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  return [self ensureProcessExitCode:process.exitCode processIdentifier:process.processIdentifier completesWithin:timeout queue:queue logger:logger];
}

#pragma mark Private

+ (FBFuture<NSNumber *> *)ensureProcessExitCode:(FBFuture<NSNumber *> *)exitCode processIdentifier:(pid_t)processIdentifier completesWithin:(NSTimeInterval)timeout queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  FBFuture<NSNumber *> *timeoutFuture = [FBXCTestProcess onQueue:queue timeoutFuture:timeout processIdentifier:processIdentifier];
  return [FBFuture race:@[exitCode, timeoutFuture]];
}

+ (FBFuture<NSNumber *> *)onQueue:(dispatch_queue_t)queue decorateLaunchedWithErrorHandlingProcess:(id<FBLaunchedProcess>)process startDate:(NSDate *)startDate timeout:(NSTimeInterval)timeout notifier:(FBCrashLogNotifier *)notifier logger:(id<FBControlCoreLogger>)logger
{
  FBFuture<NSNumber *> *checkedExitCode = [[process
    exitCode]  // This will resolve a future with an exit code, so an error condition indicates a crash as checked below.
    onQueue:queue chain:^ FBFuture<NSNumber *> * (FBFuture<NSNumber *> *exitCodeFuture) {
      if (exitCodeFuture.state == FBFutureStateDone) {
        int exitCode = exitCodeFuture.result.intValue;
        // Expected results, return now
        if (exitCode == 0 || exitCode == 1) {
          return [FBFuture futureWithResult:@(exitCode)];
        }
        return [[FBControlCoreError
          describeFormat:@"xctest process %@ exited with unexpected code %d", process, exitCode]
          failFuture];
      }
      return [FBXCTestProcess onQueue:queue performCrashLogQuery:process.processIdentifier startDate:startDate notifier:notifier crashLogWaitTime:CrashLogWaitTime logger:logger];
    }];
  return [self ensureProcessExitCode:checkedExitCode processIdentifier:process.processIdentifier completesWithin:timeout queue:queue logger:logger];
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

+ (FBFuture<NSNumber *> *)onQueue:(dispatch_queue_t)queue performCrashLogQuery:(pid_t)processIdentifier startDate:(NSDate *)startDate notifier:(FBCrashLogNotifier *)notifier crashLogWaitTime:(NSTimeInterval)crashLogWaitTime logger:(id<FBControlCoreLogger>)logger
{
  [logger logFormat:@"xctest process (%d) died prematurely, checking for crash log for %f seconds", processIdentifier, crashLogWaitTime];
  return [[[FBXCTestProcess
    onQueue:queue crashLogsForTerminationOfProcess:processIdentifier since:startDate notifier:notifier crashLogWaitTime:crashLogWaitTime]
    rephraseFailure:@"xctest process (%d) exited abnormally with no crash log, to check for yourself look in ~/Library/Logs/DiagnosticReports", processIdentifier]
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
