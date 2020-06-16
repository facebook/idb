/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBIDBXCTestReporter.h"

@interface FBIDBXCTestReporter ()

@property (nonatomic, assign, readwrite) grpc::ServerWriter<idb::XctestRunResponse> *writer;
@property (nonatomic, assign, readonly) BOOL reportAttachments;
@property (nonatomic, strong, readonly) dispatch_queue_t queue;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;
@property (nonatomic, strong, readonly) FBMutableFuture<NSNumber *> *reportingTerminatedMutable;
@property (nonatomic, strong, readonly) FBMutableFuture<NSNull *> *appUnderTestExitedMutable;

@property (nonatomic, nullable, copy, readwrite) NSString *currentBundleName;
@property (nonatomic, nullable, copy, readwrite) NSString *currentTestClass;
@property (nonatomic, nullable, copy, readwrite) NSString *currentTestMethod;

@property (nonatomic, strong, readonly) NSMutableArray<FBActivityRecord *> *currentActivityRecords;
@property (nonatomic, assign, readwrite) idb::XctestRunResponse_TestRunInfo_TestRunFailureInfo failureInfo;

@end

@implementation FBIDBXCTestReporter

#pragma mark Initializer

- (instancetype)initWithResponseWriter:(grpc::ServerWriter<idb::XctestRunResponse> *)writer reportAttachments:(BOOL)reportAttachments queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _writer = writer;
  _reportAttachments = reportAttachments;
  _queue = queue;
  _logger = logger;
  _currentActivityRecords = NSMutableArray.array;
  _reportingTerminatedMutable = FBMutableFuture.future;
  _appUnderTestExitedMutable = FBMutableFuture.future;

  return self;
}

#pragma mark Properties

- (FBFuture<NSNumber *> *)reportingTerminated
{
  return self.reportingTerminatedMutable;
}

#pragma mark FBXCTestReporter

- (void)testCaseDidStartForTestClass:(NSString *)testClass method:(NSString *)method
{
  self.currentTestClass = testClass;
  self.currentTestMethod = method;
}

- (void)testPlanDidFailWithMessage:(NSString *)message
{
  const idb::XctestRunResponse response = [self responseForCrashMessage:message];
  [self writeResponse:response];
}

- (void)testCaseDidFailForTestClass:(NSString *)testClass method:(NSString *)method withMessage:(NSString *)message file:(NSString *)file line:(NSUInteger)line
{
  // testCaseDidFinishForTestClass will be called immediately after this call, this makes sure we attach the failure info to it.
  if (([testClass isEqualToString:self.currentTestClass] && [method isEqualToString:self.currentTestMethod]) == NO) {
    [self.logger logFormat:@"Got failure info for %@/%@ but the current known executing test is %@/%@. Ignoring it", testClass, method, self.currentTestClass, self.currentTestMethod];
    return;
  }
  self.failureInfo = [self failureInfoWithMessage:message file:file line:line];
}

- (void)testCaseDidFinishForTestClass:(NSString *)testClass method:(NSString *)method withStatus:(FBTestReportStatus)status duration:(NSTimeInterval)duration
{
  [self testCaseDidFinishForTestClass:testClass method:method withStatus:status duration:duration logs:nil];
}

- (void)testCaseDidFinishForTestClass:(NSString *)testClass method:(NSString *)method withStatus:(FBTestReportStatus)status duration:(NSTimeInterval)duration logs:(NSArray<NSString *> *)logs
{
  const idb::XctestRunResponse_TestRunInfo info = [self runInfoForTestClass:testClass method:method withStatus:status duration:duration logs:logs];
  [self writeTestRunInfo:info];
}


- (void)testCase:(NSString *)testClass method:(NSString *)method didFinishActivity:(FBActivityRecord *)activity
{
  [self.currentActivityRecords addObject:activity];
}

- (void)testSuite:(NSString *)testSuite didStartAt:(NSString *)startTime
{
  @synchronized (self) {
    self.currentBundleName = testSuite;
  }
}

- (void)didCrashDuringTest:(NSError *)error
{
  const idb::XctestRunResponse response = [self responseForCrashMessage:error.description];
  [self writeResponse:response];
}

- (void)testHadOutput:(NSString *)output
{
  const idb::XctestRunResponse response = [self responseForLogOutput:@[output]];
  [self writeResponse:response];
}

- (void)handleExternalEvent:(NSString *)event
{
  const idb::XctestRunResponse response = [self responseForLogOutput:@[event]];
  [self writeResponse:response];
}

- (void)didFinishExecutingTestPlan
{
  const idb::XctestRunResponse response = [self responseForNormalTestTermination];
  [self writeResponse:response];
}

- (void)appUnderTestExited {
  [self.appUnderTestExitedMutable resolveWithResult:NSNull.null];
}

#pragma mark FBXCTestReporter (Unused)

- (BOOL)printReportWithError:(NSError **)error
{
  return NO;
}

- (void)processWaitingForDebuggerWithProcessIdentifier:(pid_t)pid
{
}

- (void)debuggerAttached
{
}

- (void)didBeginExecutingTestPlan
{
}

- (void)finishedWithSummary:(FBTestManagerResultSummary *)summary
{
  // didFinishExecutingTestPlan should be used to signify completion instead
}

#pragma mark FBDataConsumer

- (void)consumeData:(NSData *)data
{
  idb::XctestRunResponse response = [self responseForLogData:data];
  [self writeResponse:response];
}

- (void)consumeEndOfFile
{

}

#pragma mark Private

- (const idb::XctestRunResponse_TestRunInfo)runInfoForTestClass:(NSString *)testClass method:(NSString *)method withStatus:(FBTestReportStatus)status duration:(NSTimeInterval)duration logs:(NSArray<NSString *> *)logs
{
  idb::XctestRunResponse_TestRunInfo info;
  info.set_bundle_name(self.currentBundleName.UTF8String ?: "");
  info.set_class_name(testClass.UTF8String ?: "");
  info.set_method_name(method.UTF8String ?: "");
  info.set_duration(duration);
  info.mutable_failure_info()->CopyFrom(self.failureInfo);
  switch (status) {
    case FBTestReportStatusPassed:
      info.set_status(idb::XctestRunResponse_TestRunInfo_Status_PASSED);
      break;
    case FBTestReportStatusFailed:
      info.set_status(idb::XctestRunResponse_TestRunInfo_Status_FAILED);
      break;
    default:
      break;
  }
  for (NSString *log in logs) {
    info.add_logs(log.UTF8String ?: "");
  }
  NSSortDescriptor *sortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"start" ascending:YES];
  [self.currentActivityRecords sortUsingDescriptors:@[sortDescriptor]];
  NSMutableArray<FBActivityRecord *> *stackedActivities = [NSMutableArray array];
  while (self.currentActivityRecords.count) {
    FBActivityRecord *activity = self.currentActivityRecords[0];
    [self.currentActivityRecords removeObjectAtIndex:0];
    [self populateSubactivities:activity remaining:self.currentActivityRecords];
    [stackedActivities addObject:activity];
  }
  for (FBActivityRecord *activity in stackedActivities) {
    [self translateActivity:activity activityOut:info.add_activitylogs()];
  }
  [self resetCurrentTestState];
  return info;
}

- (void)populateSubactivities:(FBActivityRecord *)root remaining:(NSMutableArray<FBActivityRecord *> *)remaining {
  while (remaining.count && root.start.timeIntervalSince1970 <= remaining[0].start.timeIntervalSince1970 && root.finish.timeIntervalSince1970 >= remaining[0].finish.timeIntervalSince1970) {
    FBActivityRecord *sub = remaining[0];
    [remaining removeObjectAtIndex:0];
    [self populateSubactivities:sub remaining:remaining];
    [root.subactivities addObject:sub];
  }
}

- (void)translateActivity:(FBActivityRecord *)activity activityOut:(idb::XctestRunResponse_TestRunInfo_TestActivity *)activityOut
{
  activityOut->set_title(activity.title.UTF8String ?: "");
  activityOut->set_duration(activity.duration);
  activityOut->set_uuid(activity.uuid.UUIDString.UTF8String ?: "");
  activityOut->set_activity_type(activity.activityType.UTF8String ?: "");
  activityOut->set_start(activity.start.timeIntervalSince1970);
  activityOut->set_finish(activity.finish.timeIntervalSince1970);
  activityOut->set_name(activity.name.UTF8String ?: "");
  if (self.reportAttachments) {
    for (FBAttachment *attachment in activity.attachments) {
      idb::XctestRunResponse_TestRunInfo_TestAttachment *attachmentOut = activityOut->add_attachments();
      attachmentOut->set_payload(attachment.payload.bytes, attachment.payload.length);
      attachmentOut->set_name(attachment.name.UTF8String ?: "");
      attachmentOut->set_timestamp(attachment.timestamp.timeIntervalSince1970);
      attachmentOut->set_uniform_type_identifier(attachment.uniformTypeIdentifier.UTF8String ?: "");
    }
  }
  for (FBActivityRecord *subActitvity in activity.subactivities) {
    idb::XctestRunResponse_TestRunInfo_TestActivity *subactivityOut = activityOut->add_sub_activities();
    [self translateActivity:subActitvity activityOut:subactivityOut];
  }
}

- (const idb::XctestRunResponse_TestRunInfo_TestRunFailureInfo)failureInfoWithMessage:(NSString *)message file:(NSString *)file line:(NSUInteger)line
{
  idb::XctestRunResponse_TestRunInfo_TestRunFailureInfo failureInfo;
  failureInfo.set_failure_message(message.UTF8String ?: "");
  failureInfo.set_file(file.UTF8String ?: "");
  failureInfo.set_line(line);
  return failureInfo;
}

- (const idb::XctestRunResponse)responseForLogOutput:(NSArray<NSString *> *)logOutput
{
  idb::XctestRunResponse response;
  response.set_status(idb::XctestRunResponse_Status_RUNNING);
  for (NSString *log in logOutput) {
      NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"Assertion failed: (.*), function (.*), file (.*), line (\\d+)." options:NSRegularExpressionCaseInsensitive error:nil];
      NSTextCheckingResult *result = [regex firstMatchInString:log options:0 range:NSMakeRange(0, [log length])];
      if (result) {
          self.failureInfo = [self failureInfoWithMessage:[log substringWithRange:[result rangeAtIndex:1]] file:[log substringWithRange:[result rangeAtIndex:3]] line:[[log substringWithRange:[result rangeAtIndex:4]] integerValue]];
      }
    response.add_log_output(log.UTF8String ?: "");
  }
  return response;
}

- (const idb::XctestRunResponse)responseForLogData:(NSData *)data
{
  idb::XctestRunResponse response;
  response.set_status(idb::XctestRunResponse_Status_RUNNING);
  response.add_log_output((char *) data.bytes, data.length);
  return response;
}

- (const idb::XctestRunResponse)responseForCrashMessage:(NSString *)message
{
  idb::XctestRunResponse response;
  response.set_status(idb::XctestRunResponse_Status_TERMINATED_ABNORMALLY);
  idb::XctestRunResponse_TestRunInfo *info = response.add_results();
  info->set_bundle_name(self.currentBundleName.UTF8String ?: "");
  info->set_class_name(self.currentTestClass.UTF8String ?: "");
  info->set_method_name(self.currentTestMethod.UTF8String ?: "");
  info->mutable_failure_info()->CopyFrom(self.failureInfo);
  info->set_status(idb::XctestRunResponse_TestRunInfo_Status_CRASHED);
  [self resetCurrentTestState];
  return response;
}

- (const idb::XctestRunResponse)responseForNormalTestTermination
{
  idb::XctestRunResponse response;
  response.set_status(idb::XctestRunResponse_Status_TERMINATED_NORMALLY);
  return response;
}

- (void)resetCurrentTestState
{
  [self.currentActivityRecords removeAllObjects];
  self.failureInfo = idb::XctestRunResponse_TestRunInfo_TestRunFailureInfo();
  self.currentTestMethod = nil;
  self.currentTestClass = nil;
}

- (void)writeTestRunInfo:(const idb::XctestRunResponse_TestRunInfo &)info
{
  idb::XctestRunResponse response;
  response.set_status(idb::XctestRunResponse_Status_RUNNING);
  response.add_results()->CopyFrom(info);
  [self writeResponse:response];
}

- (void)writeResponse:(const idb::XctestRunResponse &)response
{
  // If there's a result bundle and this is the last message, then append the result bundle.
  switch (response.status()) {
    case idb::XctestRunResponse_Status_TERMINATED_NORMALLY:
    case idb::XctestRunResponse_Status_TERMINATED_ABNORMALLY:
      [self insertFinalDataThenWriteResponse:response];
      return;
    default:
      break;
  }

  [self writeResponseFinal:response];
}

- (void)insertFinalDataThenWriteResponse:(const idb::XctestRunResponse &)response
{
  // Passing a reference to the response on the stack will lead to garbage memory unless we make a copy for the block.
  // https://github.com/facebook/infer/blob/master/infer/lib/linter_rules/linters.al#L212
  __block idb::XctestRunResponse responseCaptured = response;
  NSMutableArray<FBFuture<NSNull *> *> *futures = [NSMutableArray array];
  if (self.resultBundlePath) {
    [futures addObject:[[self getResultsBundle] onQueue:self.queue chain:^FBFuture<NSNull *> *(FBFuture<NSData *> *future) {
      NSData *data = future.result;
      if (data) {
        idb::Payload *payload = responseCaptured.mutable_result_bundle();
        payload->set_data(data.bytes, data.length);
      } else {
        [self.logger.info logFormat:@"Failed to create result bundle %@", future];
      }
      return [FBFuture futureWithResult:NSNull.null];
    }]];
  }
  if (self.coveragePath) {
    [futures addObject:[[self getCoverageData] onQueue:self.queue chain:^FBFuture<NSNull *>*(FBFuture<NSString *> *future) {
      NSString *coverageData = future.result;
      if (coverageData) {
        responseCaptured.set_coverage_json(coverageData.UTF8String ?: "");
      } else {
        [self.logger.info logFormat:@"Failed to get coverage data %@", future];
      }
      return [FBFuture futureWithResult:NSNull.null];
    }]];
  }
  if (futures.count == 0) {
    [self writeResponseFinal:responseCaptured];
    return;
  }
  [[FBFuture futureWithFutures:futures] onQueue:self.queue map:^NSNull *(id _) {
    [self writeResponseFinal:responseCaptured];
    return NSNull.null;
  }];
}

- (void)writeResponseFinal:(const idb::XctestRunResponse &)response
{
  @synchronized (self)
  {
    // Break out if the terminating condition happens twice.
    if (self.reportingTerminated.hasCompleted || self.writer == nil) {
      [self.logger.error log:@"writeResponse called, but the last response has already be written!!"];
      return;
    }

    self.writer->Write(response);

    // Update the terminal future to signify that reporting is done.
    switch (response.status()) {
      case idb::XctestRunResponse_Status_TERMINATED_NORMALLY:
      case idb::XctestRunResponse_Status_TERMINATED_ABNORMALLY:
        [self.logger logFormat:@"Test Reporting has finished with status %d", response.status()];
        [self.reportingTerminatedMutable resolveWithResult:@(response.status())];
        self.writer = nil;
        break;
      default:
        break;
    }
  }
}

- (FBFuture<NSString *> *)getCoverageData
{
  NSString *profdataPath = [[self.coveragePath stringByDeletingPathExtension] stringByAppendingPathExtension:@"profdata"];
  return [self.appUnderTestExitedMutable onQueue:self.queue fmap:^FBFuture<NSString *> *(NSNull* _) {
    return [[[[FBTaskBuilder
      withLaunchPath:@"/usr/bin/xcrun" arguments:@[@"llvm-profdata", @"merge", @"-o", profdataPath, self.coveragePath]]
      runUntilCompletion]
      onQueue:self.queue fmap:^FBFuture<FBTask<NSNull *, NSString *, NSData *> *> *(id result) {
        return [[[FBTaskBuilder
          withLaunchPath:@"/usr/bin/xcrun" arguments:@[@"llvm-cov", @"export", @"-instr-profile", profdataPath, self.binaryPath]]
          withStdOutInMemoryAsString]
          runUntilCompletion];
      }] onQueue:self.queue map:^NSString *(FBTask<NSNull *, NSString *, NSData *> *task) {
          return task.stdOut;
      }];
  }];
}

- (FBFuture<NSData *> *)getResultsBundle
{
  return [FBArchiveOperations createGzippedTarDataForPath:self.resultBundlePath queue:self.queue logger:self.logger];
}


@end
