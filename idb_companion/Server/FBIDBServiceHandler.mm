/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <string>

#import <idbGRPC/idb.grpc.pb.h>
#import <idbGRPC/idb.pb.h>
#import <grpcpp/grpcpp.h>
#import <FBSimulatorControl/FBSimulatorControl.h>

#import "FBCodeCoverageRequest.h"
#import "FBDataDownloadInput.h"
#import "FBIDBCommandExecutor.h"
#import "FBIDBError.h"
#import "FBIDBPortsConfiguration.h"
#import "FBIDBServiceHandler.h"
#import "FBIDBStorageManager.h"
#import "FBIDBTestOperation.h"
#import "FBIDBXCTestReporter.h"
#import "FBXCTestRunRequest.h"
#import <FBControlCore/FBFuture.h>
#import "FBXCTestDescriptor.h"
#import "FBDsymInstallLinkToBundle.h"

using grpc::Server;
using grpc::ServerBuilder;
using grpc::ServerContext;
using grpc::Status;

#pragma mark Private Functions

static NSString *nsstring_from_c_string(const ::std::string& string)
{
  return [NSString stringWithUTF8String:string.c_str()];
}

static int BufferOutputSize = 16384; //  # 16Kb

static FBCompressionFormat read_compression_format(const idb::Payload_Compression comp)
{
  switch (comp) {
    case idb::Payload_Compression::Payload_Compression_GZIP:
      return FBCompressionFormatGZIP;
    case idb::Payload_Compression::Payload_Compression_ZSTD:
      return FBCompressionFormatZSTD;
    default:
      return FBCompressionFormatGZIP;
  }
}

template <class T>
static FBFuture<NSNull *> * resolve_next_read(grpc::internal::ReaderInterface<T> *reader)
{
  FBMutableFuture<NSNull *> *future = FBMutableFuture.future;
  dispatch_queue_t queue = dispatch_queue_create("com.facebook.idb.grpc.reader_wait", DISPATCH_QUEUE_SERIAL);
  dispatch_async(queue, ^{
    T stop;
    reader->Read(&stop);
    [future resolveWithResult:NSNull.null];
  });
  return future;
}

template <class T>
static id<FBDataConsumer> drain_consumer(grpc::internal::WriterInterface<T> *writer, FBFuture<NSNull *> *done)
{
  return [FBBlockDataConsumer asynchronousDataConsumerWithBlock:^(NSData *data) {
    if (done.hasCompleted) {
      return;
    }
    T response;
    idb::Payload *payload = response.mutable_payload();
    payload->set_data(data.bytes, data.length);
    writer->Write(response);
  }];
}

template <class Write, class Read>
static id<FBDataConsumer> consumer_from_request(grpc::ServerReaderWriter<Write, Read> *stream, Read& request, FBFuture<NSNull *> *done, NSError **error)
{
  Read initial;
  stream->Read(&initial);
  request = initial;
  const std::string requestedFilePath = initial.start().file_path();
  if (requestedFilePath.length() > 0) {
    return [FBFileWriter syncWriterForFilePath:nsstring_from_c_string(requestedFilePath.c_str()) error:error];
  }
  return drain_consumer(stream, done);
}

template <class T>
static Status drain_writer(FBFuture<FBProcess<NSNull *, NSInputStream *, id> *> *taskFuture, grpc::internal::WriterInterface<T> *stream)
{
  NSError *error = nil;
  FBProcess<NSNull *, NSInputStream *, id> *task = [taskFuture block:&error];
  if (!task) {
    return Status(grpc::StatusCode::INTERNAL, error.localizedDescription.UTF8String);
  }
  NSInputStream *inputStream = task.stdOut;
  [inputStream open];
  while (true) {
    uintptr_t buffer[BufferOutputSize];
    NSInteger size = [inputStream read:(uint8_t *)buffer maxLength:BufferOutputSize];
    if (size == 0) {
      break;
    }
    if (size < 0) {
      return Status::OK;
    }
    T response;
    idb::Payload *payload = response.mutable_payload();
    payload->set_data(reinterpret_cast<void *>(buffer), size);
    stream->Write(response);
  }
  [inputStream close];
  NSNumber *exitCode = [task.exitCode block:&error];
  if (exitCode.integerValue != 0) {
    NSString *errorString = [NSString stringWithFormat:@"Draining operation failed with exit code %ld", (long)exitCode.integerValue];
    return Status(grpc::StatusCode::INTERNAL, errorString.UTF8String);
  }
  return Status::OK;
}

template <class T>
static Status respond_file_path(NSURL *source, NSString *destination, grpc::internal::WriterInterface<T> *stream)
{
  if (source) {
    NSError *error = nil;
    if (![NSFileManager.defaultManager moveItemAtPath:source.path toPath:destination error:&error]) {
      return Status(grpc::StatusCode::INTERNAL, error.localizedDescription.UTF8String);
    }
  }
  T response;
  idb::Payload payload = response.payload();
  payload.set_file_path(destination.UTF8String);
  stream->Write(response);
  return Status::OK;
}

template <class T>
static FBProcessInput<NSOutputStream *> *pipe_to_input(const idb::Payload initial, grpc::ServerReader<T> *reader)
{
  const std::string initialData = initial.data();
  FBProcessInput<NSOutputStream *> *input = [FBProcessInput inputFromStream];
  NSOutputStream *stream = input.contents;
  dispatch_queue_t queue = dispatch_queue_create("com.facebook.idb.processinput", DISPATCH_QUEUE_SERIAL);
  dispatch_async(queue, ^{
    T request;
    [stream open];
    [stream write:(const uint8_t *)initialData.c_str() maxLength:initialData.length()];
    while (reader->Read(&request)) {
      const auto tarData = request.payload().data();
      [stream write:(const uint8_t *)tarData.c_str() maxLength:tarData.length()];
    }
    [stream close];
  });
  return input;
}

static FBProcessInput<NSOutputStream *> *pipe_to_input_output(const idb::Payload initial, grpc::ServerReaderWriter<idb::InstallResponse, idb::InstallRequest> *stream)
{
  const std::string initialData = initial.data();
  FBProcessInput<NSOutputStream *> *input = [FBProcessInput inputFromStream];
  NSOutputStream *appStream = input.contents;
  dispatch_queue_t queue = dispatch_queue_create("com.facebook.idb.processinput", DISPATCH_QUEUE_SERIAL);
  dispatch_async(queue, ^{
    idb::InstallRequest request;
    [appStream open];
    [appStream write:(const uint8_t *)initialData.c_str() maxLength:initialData.length()];
    while (stream->Read(&request)) {
      const auto tarData = request.payload().data();
      [appStream write:(const uint8_t *)tarData.c_str() maxLength:tarData.length()];
    }
    [appStream close];
  });
return input;
}

static id<FBDataConsumer, FBDataConsumerLifecycle> pipe_output(const idb::ProcessOutput_Interface interface, dispatch_queue_t queue, grpc::ServerReaderWriter<idb::LaunchResponse, idb::LaunchRequest> *stream)
{
  id<FBDataConsumer, FBDataConsumerLifecycle> consumer = [FBBlockDataConsumer asynchronousDataConsumerOnQueue:queue consumer:^(NSData *data) {
    idb::LaunchResponse response;
    idb::ProcessOutput *output = response.mutable_output();
    output->set_data(data.bytes, data.length);
    output->set_interface(interface);
    stream->Write(response);
  }];
  return consumer;
}

template <class T>
static FBFuture<NSArray<NSURL *> *> *filepaths_from_stream(const idb::Payload initial, grpc::ServerReader<T> *reader)
{
  NSMutableArray<NSURL *> *filePaths = NSMutableArray.array;
  FBMutableFuture<NSArray<NSURL *> *> *future = FBMutableFuture.future;
  dispatch_queue_t queue = dispatch_queue_create("com.facebook.idb.processinput", DISPATCH_QUEUE_SERIAL);
  dispatch_async(queue, ^{
    T request;
    [filePaths addObject:[NSURL fileURLWithPath:nsstring_from_c_string(initial.file_path())]];
    while (reader->Read(&request)) {
      [filePaths addObject:[NSURL fileURLWithPath:nsstring_from_c_string(request.payload().file_path())]];
    }
    [future resolveWithResult:filePaths];
  });
  return future;
}

static FBFutureContext<NSArray<NSURL *> *> *filepaths_from_tar(FBTemporaryDirectory *temporaryDirectory, FBProcessInput<NSOutputStream *> *input, bool extract_from_subdir, FBCompressionFormat compression, id<FBControlCoreLogger> logger)
{
  dispatch_queue_t queue = dispatch_queue_create("com.facebook.idb.processinput", DISPATCH_QUEUE_SERIAL);
  FBFutureContext<NSURL *> *tarContext = [temporaryDirectory withArchiveExtractedFromStream:input compression:compression];
  if (extract_from_subdir) {
    // Extract from subdirectories
    return [temporaryDirectory filesFromSubdirs:tarContext];
  } else {
    // Extract from the top level
    return [tarContext onQueue:queue pend:^FBFuture<NSArray<NSURL *> *> *(NSURL *extractionDir) {
      NSError *error;
      NSArray<NSURL *> *paths = [NSFileManager.defaultManager contentsOfDirectoryAtURL:extractionDir includingPropertiesForKeys:@[NSURLIsDirectoryKey] options:0 error:&error];
      if (!paths) {
        return [FBFuture futureWithError:error];
      }
      return [FBFuture futureWithResult:paths];
    }];
  }
}

template<class T>
static FBFutureContext<NSArray<NSURL *> *> *filepaths_from_reader(FBTemporaryDirectory *temporaryDirectory, grpc::ServerReader<T> *reader, bool extract_from_subdir, id<FBControlCoreLogger> logger)
{
  T request;
  reader->Read(&request);
  idb::Payload firstPayload = request.payload();

  // The first item in the payload stream may be the compression format, if it's not assume the default.
  FBCompressionFormat compression = FBCompressionFormatGZIP;
  if (firstPayload.source_case() == idb::Payload::kCompression) {
    compression = read_compression_format(firstPayload.compression());
    reader->Read(&request);
    firstPayload = request.payload();
  }

  switch (firstPayload.source_case()) {
    case idb::Payload::kData: {
      FBProcessInput<NSOutputStream *> *input = pipe_to_input(firstPayload, reader);
      return filepaths_from_tar(temporaryDirectory, input, extract_from_subdir, compression, logger);
    }
    case idb::Payload::kFilePath: {
      return [FBFutureContext futureContextWithFuture:filepaths_from_stream(firstPayload, reader)];
    }
    default: {
      return [FBFutureContext futureContextWithError:[FBControlCoreError errorForFormat:@"Unrecognised initial payload type %u", firstPayload.source_case()]];
    }
  }
}

static NSDictionary<NSString *, NSString *> *extract_str_dict(const ::google::protobuf::Map<::std::string, ::std::string >& iterator)
{
  NSMutableDictionary<NSString *, NSString *> *environment = NSMutableDictionary.dictionary;
  for (auto item : iterator) {
    environment[nsstring_from_c_string(item.first)] = nsstring_from_c_string(item.second);
  }
  return environment;
}

template <class T>
static NSArray<NSString *> *extract_string_array(T &input)
{
  NSMutableArray<NSString *> *arguments = NSMutableArray.array;
  for (auto value : input) {
    [arguments addObject:nsstring_from_c_string(value)];
  }
  return arguments;
}

static FBCodeCoverageRequest *extract_code_coverage(const idb::XctestRunRequest *request) {
  if (request->has_code_coverage()) {
    const idb::XctestRunRequest::CodeCoverage codeCoverage = request->code_coverage();
    FBCodeCoverageFormat format = FBCodeCoverageExported;
    switch (codeCoverage.format()) {
      case idb::XctestRunRequest_CodeCoverage_Format::XctestRunRequest_CodeCoverage_Format_RAW:
        format = FBCodeCoverageRaw;
        break;
      case idb::XctestRunRequest_CodeCoverage_Format::XctestRunRequest_CodeCoverage_Format_EXPORTED:
      default:
        format = FBCodeCoverageExported;
        break;
    }
    return [[FBCodeCoverageRequest alloc] initWithCollect:codeCoverage.collect() format:format];
  } else {
    // fallback to deprecated request field for backwards compatibility
    return [[FBCodeCoverageRequest alloc] initWithCollect:request->collect_coverage() format:FBCodeCoverageExported];
  }
}

static FBXCTestRunRequest *convert_xctest_request(const idb::XctestRunRequest *request)
{
  NSNumber *testTimeout = @(request->timeout());
  NSArray<NSString *> *arguments = extract_string_array(request->arguments());
  NSDictionary<NSString *, NSString *> *environment = extract_str_dict(request->environment());
  NSMutableSet<NSString *> *testsToRun = nil;
  NSMutableSet<NSString *> *testsToSkip = NSMutableSet.set;
  NSString *testBundleID = nsstring_from_c_string(request->test_bundle_id());
  BOOL reportActivities = request->report_activities();
  BOOL collectLogs = request->collect_logs();
  BOOL waitForDebugger = request->wait_for_debugger();
  BOOL collectResultBundle = request->collect_result_bundle();
  BOOL reportAttachments = request->report_attachments();
  FBCodeCoverageRequest *coverage = extract_code_coverage(request);

  if (request->tests_to_run_size() > 0) {
    testsToRun = NSMutableSet.set;
    for (int i = 0; i < request->tests_to_run_size(); i++) {
      const std::string value = request->tests_to_run(i);
      [testsToRun addObject:nsstring_from_c_string(value)];
    }
  }
  for (int i = 0; i < request->tests_to_skip_size(); i++) {
    const std::string value = request->tests_to_skip(i);
    [testsToSkip addObject:nsstring_from_c_string(value)];
  }


  switch (request->mode().mode_case()) {
    case idb::XctestRunRequest_Mode::kLogic: {
      return [FBXCTestRunRequest logicTestWithTestBundleID:testBundleID environment:environment arguments:arguments testsToRun:testsToRun testsToSkip:testsToSkip testTimeout:testTimeout reportActivities:reportActivities reportAttachments:reportAttachments coverageRequest:coverage collectLogs:collectLogs waitForDebugger:waitForDebugger collectResultBundle:collectResultBundle];
    }
    case idb::XctestRunRequest_Mode::kApplication: {
      const idb::XctestRunRequest::Application application = request->mode().application();
      NSString *appBundleID = nsstring_from_c_string(application.app_bundle_id());
      return [FBXCTestRunRequest applicationTestWithTestBundleID:testBundleID testHostAppBundleID:appBundleID environment:environment arguments:arguments testsToRun:testsToRun testsToSkip:testsToSkip testTimeout:testTimeout reportActivities:reportActivities reportAttachments:reportAttachments coverageRequest:coverage collectLogs:collectLogs waitForDebugger:waitForDebugger collectResultBundle:collectResultBundle];
    }
    case idb::XctestRunRequest_Mode::kUi: {
      const idb::XctestRunRequest::UI ui = request->mode().ui();
      NSString *testTargetAppBundleID = nsstring_from_c_string(ui.app_bundle_id());
      NSString *testHostAppBundleID = nsstring_from_c_string(ui.test_host_app_bundle_id());
      return [FBXCTestRunRequest uiTestWithTestBundleID:testBundleID testHostAppBundleID:testHostAppBundleID testTargetAppBundleID:testTargetAppBundleID environment:environment arguments:arguments testsToRun:testsToRun testsToSkip:testsToSkip testTimeout:testTimeout reportActivities:reportActivities reportAttachments:reportAttachments coverageRequest:coverage collectLogs:collectLogs collectResultBundle:collectResultBundle];
    }
    default:
      return nil;
  }
}

static NSPredicate *nspredicate_from_crash_log_query(const idb::CrashLogQuery *request)
{
  NSMutableArray<NSPredicate *> *subpredicates = [NSMutableArray array];
  if (request->since()) {
    [subpredicates addObject:[FBCrashLogInfo predicateNewerThanDate:[NSDate dateWithTimeIntervalSince1970:request->since()]]];
  }
  if (request->before()) {
    [subpredicates addObject:[FBCrashLogInfo predicateOlderThanDate:[NSDate dateWithTimeIntervalSince1970:request->before()]]];
  }
  NSString *bundle_id = nsstring_from_c_string(request->bundle_id());
  if (bundle_id.length) {
    [subpredicates addObject:[FBCrashLogInfo predicateForIdentifier:bundle_id]];
  }
  NSString *name = nsstring_from_c_string(request->name());
  if (name.length) {
    [subpredicates addObject:[FBCrashLogInfo predicateForName:name]];
  }
  if (subpredicates.count == 0) {
    return [NSPredicate predicateWithValue:YES];
  }
  return [NSCompoundPredicate andPredicateWithSubpredicates:subpredicates];
}

static void fill_crash_log_info(idb::CrashLogInfo *info, const FBCrashLogInfo *crash)
{
  info->set_name(crash.name.UTF8String);
  info->set_process_name(crash.processName.UTF8String);
  info->set_parent_process_name(crash.parentProcessName.UTF8String);
  info->set_process_identifier(crash.processIdentifier);
  info->set_parent_process_identifier(crash.parentProcessIdentifier);
  info->set_timestamp(crash.date.timeIntervalSince1970);
}

static void fill_crash_log_response(idb::CrashLogResponse *response, const NSArray<FBCrashLogInfo *> *crashes)
{
  for (FBCrashLogInfo *crash in crashes) {
    idb::CrashLogInfo *info = response->add_list();
    fill_crash_log_info(info, crash);
  }
}

static FBSimulatorHIDEvent *translate_event(idb::HIDEvent &event, NSError **error)
{
  if (event.has_press()) {
    idb::HIDEvent_HIDDirection direction = event.press().direction();
    idb::HIDEvent_HIDPressAction action = event.press().action();
    if (action.has_key()) {
      int keycode = (int)action.key().keycode();
      if (direction == idb::HIDEvent_HIDDirection_DOWN) {
        return [FBSimulatorHIDEvent keyDown:keycode];
      } else if (direction == idb::HIDEvent_HIDDirection_UP) {
        return [FBSimulatorHIDEvent keyUp:keycode];
      }
    } else if (action.has_button()) {
      // Need to convert between the objc enum that starts at 1 and the grpc enum that starts at 0
      FBSimulatorHIDButton button = (FBSimulatorHIDButton)(action.button().button() + 1);
      if (direction == idb::HIDEvent_HIDDirection_DOWN) {
        return [FBSimulatorHIDEvent buttonDown:button];
      } else if (direction == idb::HIDEvent_HIDDirection_UP) {
        return [FBSimulatorHIDEvent buttonUp:button];
      }
    } else if (action.has_touch()) {
      int x = action.touch().point().x();
      int y = action.touch().point().y();
      if (direction == idb::HIDEvent_HIDDirection_DOWN) {
        return [FBSimulatorHIDEvent touchDownAtX:x y:y];
      } else if (direction == idb::HIDEvent_HIDDirection_UP) {
        return [FBSimulatorHIDEvent touchUpAtX:x y:y];
      }
    }
  } else if (event.has_swipe()) {
    return [FBSimulatorHIDEvent swipe:event.swipe().start().x() yStart:event.swipe().start().y() xEnd:event.swipe().end().x() yEnd:event.swipe().end().y() delta:event.swipe().delta() duration:event.swipe().duration()];
  } else if (event.has_delay()) {
    return [FBSimulatorHIDEvent delay:event.delay().duration()];
  }
  if (error) {
    *error = [FBControlCoreError errorForDescription:@"Can't decode event"];
  }
  return nil;
}

static FBInstrumentsConfiguration *translate_instruments_configuration(idb::InstrumentsRunRequest_Start request, FBIDBStorageManager *storageManager)
{
  return [FBInstrumentsConfiguration
    configurationWithTemplateName:nsstring_from_c_string(request.template_name())
    targetApplication:nsstring_from_c_string(request.app_bundle_id())
    appEnvironment:extract_str_dict(request.environment())
    appArguments:extract_string_array(request.arguments())
    toolArguments:[storageManager interpolateArgumentReplacements:extract_string_array(request.tool_arguments())]
    timings:[FBInstrumentsTimings
      timingsWithTerminateTimeout:request.timings().terminate_timeout() ?: DefaultInstrumentsTerminateTimeout
      launchRetryTimeout:request.timings().launch_retry_timeout() ?: DefaultInstrumentsLaunchRetryTimeout
      launchErrorTimeout:request.timings().launch_error_timeout() ?: DefaultInstrumentsLaunchErrorTimeout
      operationDuration:request.timings().operation_duration() ?: DefaultInstrumentsOperationDuration
      ]
    ];
}

static FBXCTraceRecordConfiguration *translate_xctrace_record_configuration(idb::XctraceRecordRequest_Start request)
{
  return [FBXCTraceRecordConfiguration
    RecordWithTemplateName:nsstring_from_c_string(request.template_name())
    timeLimit:request.time_limit() ?: DefaultXCTraceRecordOperationTimeLimit
    package:nsstring_from_c_string(request.package())
    allProcesses:request.target().all_processes()
    processToAttach:nsstring_from_c_string(request.target().process_to_attach())
    processToLaunch:nsstring_from_c_string(request.target().launch_process().process_to_launch())
    launchArgs:extract_string_array(request.target().launch_process().launch_args())
    targetStdin:nsstring_from_c_string(request.target().launch_process().target_stdin())
    targetStdout:nsstring_from_c_string(request.target().launch_process().target_stdout())
    processEnv:extract_str_dict(request.target().launch_process().process_env())
    shim:nil
  ];
}

static idb::DebugServerResponse translate_debugserver_status(id<FBDebugServer> debugServer)
{
  idb::DebugServerResponse response;
  idb::DebugServerResponse::Status *status = response.mutable_status();
  if (debugServer) {
    for (NSString *command in debugServer.lldbBootstrapCommands) {
      status->add_lldb_bootstrap_commands(command.UTF8String);
    }
  }
  return response;
}

static NSString *file_container(idb::FileContainer container)
{
  switch (container.kind()) {
    case idb::FileContainer_Kind_ROOT:
      return FBFileContainerKindRoot;
    case idb::FileContainer_Kind_MEDIA:
      return FBFileContainerKindMedia;
    case idb::FileContainer_Kind_CRASHES:
      return FBFileContainerKindCrashes;
    case idb::FileContainer_Kind_PROVISIONING_PROFILES:
      return FBFileContainerKindProvisioningProfiles;
    case idb::FileContainer_Kind_MDM_PROFILES:
      return FBFileContainerKindMDMProfiles;
    case idb::FileContainer_Kind_SPRINGBOARD_ICONS:
      return FBFileContainerKindSpringboardIcons;
    case idb::FileContainer_Kind_WALLPAPER:
      return FBFileContainerKindWallpaper;
    case idb::FileContainer_Kind_DISK_IMAGES:
      return FBFileContainerKindDiskImages;
    case idb::FileContainer_Kind_GROUP_CONTAINER:
      return FBFileContainerKindGroup;
    case idb::FileContainer_Kind_APPLICATION_CONTAINER:
      return FBFileContainerKindApplication;
    case idb::FileContainer_Kind_AUXILLARY:
      return FBFileContainerKindAuxillary;
    case idb::FileContainer_Kind_XCTEST:
      return FBFileContainerKindXctest;
    case idb::FileContainer_Kind_DYLIB:
      return FBFileContainerKindDylib;
    case idb::FileContainer_Kind_DSYM:
      return FBFileContainerKindDsym;
    case idb::FileContainer_Kind_FRAMEWORK:
      return FBFileContainerKindFramework;
    case idb::FileContainer_Kind_SYMBOLS:
      return FBFileContainerKindSymbols;
    case idb::FileContainer_Kind_APPLICATION:
    default:
      return nsstring_from_c_string(container.bundle_id());
  }
}

static FBDsymBundleType bundle_type_link_to_dsym(idb::InstallRequest_LinkDsymToBundle_BundleType bundleType)
{
  switch (bundleType) {
    case idb::InstallRequest_LinkDsymToBundle_BundleType_XCTEST:
      return FBDsymBundleTypeXCTest;
    case idb::InstallRequest_LinkDsymToBundle_BundleType_APP:
      return FBDsymBundleTypeApp;
    default:
      return FBDsymBundleTypeApp;
  }
}

static void populate_companion_info(idb::CompanionInfo *info, id<FBEventReporter> reporter, id<FBiOSTarget> target)
{
  info->set_udid(target.udid.UTF8String);
  NSDictionary<NSString *, NSString *> *metadata = reporter.metadata ?: @{};
  NSError *error = nil;
  NSData *data = [NSJSONSerialization dataWithJSONObject:metadata options:0 error:&error];
  if (data) {
    info->set_metadata(data.bytes, data.length);
  }
}

#pragma mark Constructors

FBIDBServiceHandler::FBIDBServiceHandler(FBIDBCommandExecutor *commandExecutor, id<FBiOSTarget> target, id<FBEventReporter> eventReporter)
{
  _commandExecutor = commandExecutor;
  _target = target;
  _eventReporter = eventReporter;
}

FBIDBServiceHandler::FBIDBServiceHandler(const FBIDBServiceHandler &c)
{
  _commandExecutor = c._commandExecutor;
  _target = c._target;
  _eventReporter = c._eventReporter;
}

#pragma mark Handled Methods

FBFuture<FBInstalledArtifact *> *FBIDBServiceHandler::install_future(const idb::InstallRequest_Destination destination, grpc::ServerReaderWriter<idb::InstallResponse, idb::InstallRequest> *stream)
{@autoreleasepool{
  // Read the initial request
  idb::InstallRequest request;
  stream->Read(&request);

  // The name hint may be provided, if it is not then default to some UUID, then advance the stream.
  NSString *name = NSUUID.UUID.UUIDString;
  if (request.value_case() == idb::InstallRequest::ValueCase::kNameHint) {
    name = nsstring_from_c_string(request.name_hint());
    stream->Read(&request);
  }

  // A debuggable flag may be provided, if it is, then obtain that value, then advance that stream.
  BOOL makeDebuggable = NO;
  if (request.value_case() == idb::InstallRequest::ValueCase::kMakeDebuggable) {
    makeDebuggable = (request.make_debuggable() == true);
    stream->Read(&request);
  }

  BOOL overrideModificationTime = NO;
    if (request.value_case() == idb::InstallRequest::ValueCase::kOverrideModificationTime) {
    overrideModificationTime = (request.override_modification_time() == true);
    stream->Read(&request);
  }

  FBDsymInstallLinkToBundle *linkToBundle = nil;
  //(2022-03-02) REMOVE! Keeping only for retrocompatibility
  // A bundle id might be provided, if it is, then obtain the installed app if exists, then advance that stream.
  // It can be used to determine where debug symbols should be linked
  if (request.value_case() == idb::InstallRequest::ValueCase::kBundleId) {
    NSString *bundleID = nsstring_from_c_string(request.bundle_id());
    linkToBundle = [[FBDsymInstallLinkToBundle alloc] initWith:bundleID bundle_type:FBDsymBundleTypeApp];
    stream->Read(&request);
  }

  if (request.value_case() == idb::InstallRequest::ValueCase::kLinkDsymToBundle) {
    idb::InstallRequest_LinkDsymToBundle link_to_bundle = request.link_dsym_to_bundle();
    FBDsymBundleType bundleType = bundle_type_link_to_dsym(link_to_bundle.bundle_type());
    NSString *bundleID = nsstring_from_c_string(link_to_bundle.bundle_id());
    linkToBundle = [[FBDsymInstallLinkToBundle alloc] initWith:bundleID bundle_type:bundleType];
    stream->Read(&request);
  }

  // Now that we've read the header, the next item in the stream must be the payload.
  if (request.value_case() != idb::InstallRequest::ValueCase::kPayload) {
    return [[FBIDBError
      describeFormat:@"Expected the next item in the stream to be a payload"]
      failFuture];
  }

  // The first item in the payload stream may be the compression format, if it's not assume the default.
  FBCompressionFormat compression = FBCompressionFormatGZIP;
  idb::Payload payload = request.payload();
  if (payload.source_case() == idb::Payload::kCompression) {
    compression = read_compression_format(payload.compression());
    stream->Read(&request);
    payload = request.payload();
  }

  switch (payload.source_case()) {
    case idb::Payload::kData: {
      FBProcessInput<NSOutputStream *> *dataStream = pipe_to_input_output(payload, stream);
      switch (destination) {
        case idb::InstallRequest_Destination::InstallRequest_Destination_APP:
          return [_commandExecutor install_app_stream:dataStream compression:compression make_debuggable:makeDebuggable override_modification_time:overrideModificationTime];
        case idb::InstallRequest_Destination::InstallRequest_Destination_XCTEST:
          return [_commandExecutor install_xctest_app_stream:dataStream];
        case idb::InstallRequest_Destination::InstallRequest_Destination_DSYM:
          return [_commandExecutor install_dsym_stream:dataStream compression:compression linkTo:linkToBundle];
        case idb::InstallRequest_Destination::InstallRequest_Destination_DYLIB:
          return [_commandExecutor install_dylib_stream:dataStream name:name];
        case idb::InstallRequest_Destination::InstallRequest_Destination_FRAMEWORK:
          return [_commandExecutor install_framework_stream:dataStream];
        default:
          return nil;
      }
    }
    case idb::Payload::kUrl: {
      NSURL *url = [NSURL URLWithString:[NSString stringWithCString:payload.url().c_str() encoding:NSUTF8StringEncoding]];
      FBDataDownloadInput *download = [FBDataDownloadInput dataDownloadWithURL:url logger:_target.logger];
      switch (destination) {
        case idb::InstallRequest_Destination::InstallRequest_Destination_APP:
          return [_commandExecutor install_app_stream:download.input compression:compression make_debuggable:makeDebuggable override_modification_time:overrideModificationTime];
        case idb::InstallRequest_Destination::InstallRequest_Destination_XCTEST:
          return [_commandExecutor install_xctest_app_stream:download.input];
        case idb::InstallRequest_Destination::InstallRequest_Destination_DSYM:
          return [_commandExecutor install_dsym_stream:download.input compression:compression linkTo:linkToBundle];
        case idb::InstallRequest_Destination::InstallRequest_Destination_DYLIB:
          return [_commandExecutor install_dylib_stream:download.input name:name];
        case idb::InstallRequest_Destination::InstallRequest_Destination_FRAMEWORK:
          return [_commandExecutor install_framework_stream:download.input];
        default:
          return nil;
      }
    }
    case idb::Payload::kFilePath: {
      NSString *filePath = nsstring_from_c_string(payload.file_path());
      switch (destination) {
        case idb::InstallRequest_Destination::InstallRequest_Destination_APP:
          return [_commandExecutor install_app_file_path:filePath make_debuggable:makeDebuggable override_modification_time:overrideModificationTime];
        case idb::InstallRequest_Destination::InstallRequest_Destination_XCTEST:
          return [_commandExecutor install_xctest_app_file_path:filePath];
        case idb::InstallRequest_Destination::InstallRequest_Destination_DSYM:
          return [_commandExecutor install_dsym_file_path:filePath linkTo:linkToBundle];
        case idb::InstallRequest_Destination::InstallRequest_Destination_DYLIB:
          return [_commandExecutor install_dylib_file_path:filePath];
        case idb::InstallRequest_Destination::InstallRequest_Destination_FRAMEWORK:
          return [_commandExecutor install_framework_file_path:filePath];
        default:
          return nil;
      }
    }
    default:
      return nil;
  }
}}

Status FBIDBServiceHandler::list_apps(ServerContext *context, const idb::ListAppsRequest *request, idb::ListAppsResponse *response)
{@autoreleasepool{
  NSError *error = nil;
  NSSet<NSString *> *persistedBundleIDs = _commandExecutor.storageManager.application.persistedBundleIDs;
  BOOL fetchAppProcessState = request->suppress_process_state() == false;
  NSDictionary<FBInstalledApplication *, id> *apps = [[_commandExecutor list_apps:fetchAppProcessState] block:&error];
  if (!apps) {
    return Status(grpc::StatusCode::INTERNAL, error.localizedDescription.UTF8String);
  }
  for (FBInstalledApplication *app in apps.allKeys) {
    idb::InstalledAppInfo *appInfo = response->add_apps();
    appInfo->set_bundle_id(app.bundle.identifier.UTF8String ?: "");
    appInfo->set_name(app.bundle.name.UTF8String ?: "");
    appInfo->set_install_type(app.installTypeString.UTF8String);
    for (NSString *architecture in app.bundle.binary.architectures) {
      appInfo->add_architectures(architecture.UTF8String);
    }
    id processState = apps[app];
    if ([processState isKindOfClass:NSNumber.class]) {
      appInfo->set_process_state(idb::InstalledAppInfo_AppProcessState_RUNNING);
      appInfo->set_process_identifier([processState unsignedIntegerValue]);
    } else {
      appInfo->set_process_state(idb::InstalledAppInfo_AppProcessState_UNKNOWN);
    }
    appInfo->set_debuggable(app.installType == FBApplicationInstallTypeUserDevelopment && [persistedBundleIDs containsObject:app.bundle.identifier]);
  }
  return Status::OK;
}}

Status FBIDBServiceHandler::open_url(ServerContext *context, const idb::OpenUrlRequest *request, idb::OpenUrlRequest *response)
{@autoreleasepool{
  NSError *error = nil;
  [[_commandExecutor open_url:nsstring_from_c_string(request->url())] block:&error];
  if (error) {
    return Status(grpc::StatusCode::INTERNAL, [error.localizedDescription UTF8String]);
  }
  return Status::OK;
}}

Status FBIDBServiceHandler::install(ServerContext *context, grpc::ServerReaderWriter<idb::InstallResponse, idb::InstallRequest> *stream)
{@autoreleasepool{
  idb::InstallRequest request;
  stream->Read(&request);
  idb::InstallRequest_Destination destination = request.destination();

  NSError *error = nil;
  FBInstalledArtifact *artifact = [install_future(destination, stream) block:&error];
  if (!artifact) {
    return Status(grpc::StatusCode::INTERNAL, error.localizedDescription.UTF8String ?: "An internal error occured when installing");
  }
  idb::InstallResponse response;
  response.set_name(artifact.name.UTF8String);
  response.set_uuid(artifact.uuid.UUIDString.UTF8String ?: "");
  stream->Write(response);
  return Status::OK;
}}

Status FBIDBServiceHandler::screenshot(ServerContext *context, const idb::ScreenshotRequest *request, idb::ScreenshotResponse *response)
{@autoreleasepool{
  NSError *error = nil;
  NSData *screenshot = [[_commandExecutor take_screenshot:FBScreenshotFormatPNG] block:&error];
  if (error) {
    return Status(grpc::StatusCode::INTERNAL, error.localizedDescription.UTF8String);
  }
  response->set_image_data(screenshot.bytes, screenshot.length);
  return Status::OK;
}}

Status FBIDBServiceHandler::focus(ServerContext *context, const idb::FocusRequest *request, idb::FocusResponse *response)
{@autoreleasepool{
  NSError *error = nil;
  [[_commandExecutor focus] block:&error];
  if (error) {
    return Status(grpc::StatusCode::INTERNAL, [error.localizedDescription UTF8String]);
  }
  return Status::OK;
}}

Status FBIDBServiceHandler::accessibility_info(ServerContext *context, const idb::AccessibilityInfoRequest *request, idb::AccessibilityInfoResponse *response)
{@autoreleasepool{
  NSError *error = nil;
  NSValue *point = nil;
  if (request->has_point()) {
    point = [NSValue valueWithPoint:CGPointMake(request->point().x(), request->point().y())];
  }
  BOOL nestedFormat = request->format() == idb::AccessibilityInfoRequest_Format::AccessibilityInfoRequest_Format_NESTED;
  id info = [[_commandExecutor accessibility_info_at_point:point nestedFormat:nestedFormat] block:&error];

  if (!info) {
    return Status(grpc::StatusCode::INTERNAL, [error.localizedDescription UTF8String]);
  }

  NSData *data = [NSJSONSerialization dataWithJSONObject:info options:0 error:&error];
  if (!data) {
    return Status(grpc::StatusCode::INTERNAL, [error.localizedDescription UTF8String]);
  }

  NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
  response->set_json([json UTF8String]);
  return Status::OK;
}}

Status FBIDBServiceHandler::uninstall(ServerContext *context, const idb::UninstallRequest *request, idb::UninstallResponse *response)
{@autoreleasepool{
  NSError *error = nil;
  [[_commandExecutor uninstall_application:nsstring_from_c_string(request->bundle_id())] block:&error];
  if (error) {
    return Status(grpc::StatusCode::INTERNAL, [error.localizedDescription UTF8String]);
  }
  return Status::OK;
}}

Status FBIDBServiceHandler::mkdir(grpc::ServerContext *context, const idb::MkdirRequest *request, idb::MkdirResponse *response)
{@autoreleasepool{
  NSError *error = nil;
  [[_commandExecutor create_directory:nsstring_from_c_string(request->path()) containerType:file_container(request->container())] block:&error];
  if (error) {
    return Status(grpc::StatusCode::INTERNAL, error.localizedDescription.UTF8String);
  }
  return Status::OK;
}}

Status FBIDBServiceHandler::mv(grpc::ServerContext *context, const idb::MvRequest *request, idb::MvResponse *response)
{@autoreleasepool{
  NSError *error = nil;
  NSMutableArray<NSString *> *originalPaths = NSMutableArray.array;
  for (int j = 0; j < request->src_paths_size(); j++) {
    [originalPaths addObject:nsstring_from_c_string(request->src_paths(j))];
  }
  [[_commandExecutor move_paths:originalPaths to_path:nsstring_from_c_string(request->dst_path()) containerType:file_container(request->container())] block:&error];
  if (error) {
    return Status(grpc::StatusCode::INTERNAL, error.localizedDescription.UTF8String);
  }
  return Status::OK;
}}

Status FBIDBServiceHandler::rm(grpc::ServerContext *context, const idb::RmRequest *request, idb::RmResponse *response)
{@autoreleasepool{
  NSError *error = nil;
  NSMutableArray<NSString *> *paths = NSMutableArray.array;
  for (int j = 0; j < request->paths_size(); j++) {
    [paths addObject:nsstring_from_c_string(request->paths(j))];
  }
  [[_commandExecutor remove_paths:paths containerType:file_container(request->container())] block:&error];
  if (error) {
    return Status(grpc::StatusCode::INTERNAL, error.localizedDescription.UTF8String);
  }
  return Status::OK;
}}

Status FBIDBServiceHandler::ls(grpc::ServerContext *context, const idb::LsRequest *request, idb::LsResponse *response)
{@autoreleasepool{
  NSError *error = nil;
  if (request->paths_size() > 0) {
    NSArray<NSString *> *inputPaths = extract_string_array(request->paths());
    NSDictionary<NSString *, NSArray<NSString *> *> *pathsToPaths = [[_commandExecutor list_paths:inputPaths containerType:file_container(request->container())] block:&error];
    if (error) {
      return Status(grpc::StatusCode::INTERNAL, error.localizedDescription.UTF8String);
    }

    for (NSString *containerPath in pathsToPaths.allKeys) {
      NSArray<NSString *> *paths = pathsToPaths[containerPath];
      idb::FileListing *listing = response->add_listings();
      idb::FileInfo *parent = listing->mutable_parent();
      parent->set_path(containerPath.UTF8String);
      for (NSString *path in paths) {
        idb::FileInfo *info = listing->add_files();
        info->set_path(path.UTF8String);
      }
    }
  } else {
    // Back-compat with single paths
    NSArray<NSString *> *paths = [[_commandExecutor list_path:nsstring_from_c_string(request->path()) containerType:file_container(request->container())] block:&error];
    if (error) {
      return Status(grpc::StatusCode::INTERNAL, error.localizedDescription.UTF8String);
    }

    for (NSString *path in paths) {
      idb::FileInfo *info = response->add_files();
      info->set_path(path.UTF8String);
    }
  }

  return Status::OK;
}}

Status FBIDBServiceHandler::approve(ServerContext *context, const idb::ApproveRequest *request, idb::ApproveResponse *response)
{@autoreleasepool{
  NSError *error = nil;
  NSDictionary<NSNumber *, FBTargetSettingsService> *mapping = @{
    @((int)idb::ApproveRequest_Permission::ApproveRequest_Permission_MICROPHONE): FBTargetSettingsServiceMicrophone,
    @((int)idb::ApproveRequest_Permission::ApproveRequest_Permission_PHOTOS): FBTargetSettingsServicePhotos,
    @((int)idb::ApproveRequest_Permission::ApproveRequest_Permission_CAMERA): FBTargetSettingsServiceCamera,
    @((int)idb::ApproveRequest_Permission::ApproveRequest_Permission_CONTACTS): FBTargetSettingsServiceContacts,
    @((int)idb::ApproveRequest_Permission::ApproveRequest_Permission_URL): FBTargetSettingsServiceUrl,
    @((int)idb::ApproveRequest_Permission::ApproveRequest_Permission_LOCATION): FBTargetSettingsServiceLocation,
    @((int)idb::ApproveRequest_Permission::ApproveRequest_Permission_NOTIFICATION): FBTargetSettingsServiceNotification,
  };
  NSMutableSet<FBTargetSettingsService> *services = NSMutableSet.set;
  for (int j = 0; j < request->permissions_size(); j++) {
    idb::ApproveRequest_Permission permission = request->permissions(j);
    [services addObject:mapping[@(permission)]];
  }
  if ([services containsObject:FBTargetSettingsServiceUrl]) {
    [services removeObject:FBTargetSettingsServiceUrl];
    [[_commandExecutor approve_deeplink:nsstring_from_c_string(request->scheme())
                        for_application:nsstring_from_c_string(request->bundle_id())] block:&error];
  }
  if ([services count] > 0 && !error) {
    [[_commandExecutor approve:services for_application:nsstring_from_c_string(request->bundle_id())] block:&error];
  }
  if (error) {
    return Status(grpc::StatusCode::INTERNAL, error.localizedDescription.UTF8String);
  }
  return Status::OK;
}}

Status FBIDBServiceHandler::revoke(ServerContext *context, const idb::RevokeRequest *request, idb::RevokeResponse *response)
{@autoreleasepool{
  NSError *error = nil;
  NSDictionary<NSNumber *, FBTargetSettingsService> *mapping = @{
    @((int)idb::RevokeRequest_Permission::RevokeRequest_Permission_MICROPHONE): FBTargetSettingsServiceMicrophone,
    @((int)idb::RevokeRequest_Permission::RevokeRequest_Permission_PHOTOS): FBTargetSettingsServicePhotos,
    @((int)idb::RevokeRequest_Permission::RevokeRequest_Permission_CAMERA): FBTargetSettingsServiceCamera,
    @((int)idb::RevokeRequest_Permission::RevokeRequest_Permission_CONTACTS): FBTargetSettingsServiceContacts,
    @((int)idb::RevokeRequest_Permission::RevokeRequest_Permission_URL): FBTargetSettingsServiceUrl,
    @((int)idb::RevokeRequest_Permission::RevokeRequest_Permission_LOCATION): FBTargetSettingsServiceLocation,
    @((int)idb::RevokeRequest_Permission::RevokeRequest_Permission_NOTIFICATION): FBTargetSettingsServiceNotification,
  };
  NSMutableSet<FBTargetSettingsService> *services = NSMutableSet.set;
  for (int j = 0; j < request->permissions_size(); j++) {
    idb::RevokeRequest_Permission permission = request->permissions(j);
    [services addObject:mapping[@(permission)]];
  }
  if ([services containsObject:FBTargetSettingsServiceUrl]) {
    [services removeObject:FBTargetSettingsServiceUrl];
    [[_commandExecutor revoke_deeplink:nsstring_from_c_string(request->scheme())
                        for_application:nsstring_from_c_string(request->bundle_id())] block:&error];
  }
  if ([services count] > 0 && !error) {
    [[_commandExecutor revoke:services for_application:nsstring_from_c_string(request->bundle_id())] block:&error];
  }
  if (error) {
    return Status(grpc::StatusCode::INTERNAL, error.localizedDescription.UTF8String);
  }
  return Status::OK;
}}

Status FBIDBServiceHandler::clear_keychain(ServerContext *context, const idb::ClearKeychainRequest *request, idb::ClearKeychainResponse *response)
{@autoreleasepool{
  NSError *error = nil;
  [[_commandExecutor clear_keychain] block:&error];
  if (error) {
    return Status(grpc::StatusCode::INTERNAL, [error.localizedDescription UTF8String]);
  }
  return Status::OK;
}}

Status FBIDBServiceHandler::terminate(ServerContext *context, const idb::TerminateRequest *request, idb::TerminateResponse *response)
{@autoreleasepool{
  NSError *error = nil;
  [[_commandExecutor kill_application:nsstring_from_c_string(request->bundle_id())] block:&error];
  if (error) {
    return Status(grpc::StatusCode::INTERNAL, error.localizedDescription.UTF8String);
  }
  return Status::OK;
}}

Status FBIDBServiceHandler::hid(grpc::ServerContext *context, grpc::ServerReader<idb::HIDEvent> *reader, idb::HIDResponse *response)
{@autoreleasepool{
  NSError *error = nil;
  idb::HIDEvent grpcEvent;
  while (reader->Read(&grpcEvent)) {
    FBSimulatorHIDEvent *event = translate_event(grpcEvent, &error);
    if (error) {
      return Status(grpc::StatusCode::INTERNAL, error.localizedDescription.UTF8String);
    }
    [[_commandExecutor hid:event] block:&error];
    if (error) {
      return Status(grpc::StatusCode::INTERNAL, error.localizedDescription.UTF8String);
    }
  }
  return Status::OK;
}}

Status FBIDBServiceHandler::set_location(ServerContext *context, const idb::SetLocationRequest *request, idb::SetLocationResponse *response)
{@autoreleasepool{
  NSError *error = nil;
  [[_commandExecutor set_location:request->location().latitude() longitude:request->location().longitude()] block:&error];
  if (error) {
    return Status(grpc::StatusCode::INTERNAL, [error.localizedDescription UTF8String]);
  }
  return Status::OK;
}}

Status FBIDBServiceHandler::setting(ServerContext* context, const idb::SettingRequest* request, idb::SettingResponse* response)
{@autoreleasepool{
  switch (request->setting_case()) {
    case idb::SettingRequest::SettingCase::kHardwareKeyboard: {
      NSError *error = nil;
      NSNull *result = [[_commandExecutor set_hardware_keyboard_enabled:request->hardwarekeyboard().enabled()] await:&error];
      if (!result) {
        return Status(grpc::StatusCode::INTERNAL, error.localizedDescription.UTF8String);
      }
      return Status::OK;
    }
    case idb::SettingRequest::SettingCase::kStringSetting: {
      idb::SettingRequest::StringSetting stringSetting = request->stringsetting();
      switch (stringSetting.setting()) {
        case idb::Setting::LOCALE: {
          NSError *error = nil;
          NSNull *result = [[_commandExecutor set_locale_with_identifier:nsstring_from_c_string(stringSetting.value().c_str())] await:&error];
          if (!result) {
            return Status(grpc::StatusCode::INTERNAL, error.localizedDescription.UTF8String);
          }
          return Status::OK;
        }
        case idb::Setting::ANY: {
          NSError *error = nil;
          NSString *name = nsstring_from_c_string(stringSetting.name().c_str());
          NSString *value = nsstring_from_c_string(stringSetting.value().c_str());
          NSString *type = nil;
          if (stringSetting.value_type().length() > 0) {
            type = nsstring_from_c_string(stringSetting.value_type().c_str());
          }
          NSString *domain = nil;
          if (stringSetting.domain().length() > 0) {
            domain = nsstring_from_c_string(stringSetting.domain().c_str());
          }
          NSNull *result = [[_commandExecutor set_preference:name value:value type: type domain:domain] await:&error];
          if (!result) {
            return Status(grpc::StatusCode::INTERNAL, error.localizedDescription.UTF8String);
          }
          return Status::OK;
        }
        default:
          return Status(grpc::StatusCode::INTERNAL, "Unknown setting case");
      }
    }
    default:
      return Status(grpc::StatusCode::INTERNAL, "Unknown setting case");
  }
}}

Status FBIDBServiceHandler::get_setting(ServerContext* context, const idb::GetSettingRequest* request, idb::GetSettingResponse* response)
{@autoreleasepool{
  switch (request->setting()) {
    case idb::Setting::LOCALE: {
      NSError *error = nil;
      NSString *localeIdentifier = [[_commandExecutor get_current_locale_identifier] await:&error];
      if (error) {
        return Status(grpc::StatusCode::INTERNAL, error.localizedDescription.UTF8String);
      }
      response->set_value(localeIdentifier.UTF8String);
      return Status::OK;
    }
    case idb::Setting::ANY: {
      NSError *error = nil;
      NSString *name = nsstring_from_c_string(request->name().c_str());
      NSString *domain = nil;
      if (request->domain().length() > 0) {
        domain = nsstring_from_c_string(request->domain().c_str());
      }
      NSString *value = [[_commandExecutor get_preference:name domain:domain] await:&error];
      if (error) {
        return Status(grpc::StatusCode::INTERNAL, error.localizedDescription.UTF8String);
      }
      response->set_value(value.UTF8String);
      return Status::OK;
    }
    default:
      return Status(grpc::StatusCode::INTERNAL, "Unknown setting case");
  }
}}

Status FBIDBServiceHandler::list_settings(ServerContext* context, const idb::ListSettingRequest* request, idb::ListSettingResponse* response)
{@autoreleasepool{
  switch (request->setting()) {
    case idb::Setting::LOCALE: {
      NSArray<NSString *> *localeIdentifiers = _commandExecutor.list_locale_identifiers;
      auto values = response->mutable_values();
      for (NSString *localeIdentifier in localeIdentifiers) {
        values->Add(localeIdentifier.UTF8String);
      }
      return Status::OK;
    }
    default:
      return Status(grpc::StatusCode::INTERNAL, "Unknown setting case");
  }
}}

Status FBIDBServiceHandler::contacts_update(ServerContext *context, const idb::ContactsUpdateRequest *request, idb::ContactsUpdateResponse *response)
{@autoreleasepool{
  NSError *error = nil;
  std::string data = request->payload().data();
  [[_commandExecutor update_contacts:[NSData dataWithBytes:data.c_str() length:data.length()]] block:&error];
  if (error) {
    return Status(grpc::StatusCode::INTERNAL, [error.localizedDescription UTF8String]);
  }
  return Status::OK;
}}

Status FBIDBServiceHandler::launch(grpc::ServerContext *context, grpc::ServerReaderWriter<idb::LaunchResponse, idb::LaunchRequest> *stream)
{@autoreleasepool{
  idb::LaunchRequest request;
  stream->Read(&request);
  idb::LaunchRequest_Start start = request.start();
  NSError *error = nil;
  FBProcessOutput *stdOut = FBProcessOutput.outputForNullDevice;
  FBProcessOutput *stdErr = FBProcessOutput.outputForNullDevice;
  NSMutableArray<FBFuture *> *completions = NSMutableArray.array;
  if (start.wait_for()) {
    dispatch_queue_t writeQueue = dispatch_queue_create("com.facebook.idb.launch.write", DISPATCH_QUEUE_SERIAL);
    id<FBDataConsumer, FBDataConsumerLifecycle> consumer = pipe_output(idb::ProcessOutput_Interface_STDOUT, writeQueue, stream);
    [completions addObject:consumer.finishedConsuming];
    stdOut = [FBProcessOutput outputForDataConsumer:consumer];
    consumer = pipe_output(idb::ProcessOutput_Interface_STDERR, writeQueue, stream);
    [completions addObject:consumer.finishedConsuming];
    stdErr = [FBProcessOutput outputForDataConsumer:consumer];
  }
  FBProcessIO *io = [[FBProcessIO alloc]
    initWithStdIn:nil
    stdOut:stdOut
    stdErr:stdErr];
  FBApplicationLaunchConfiguration *configuration = [[FBApplicationLaunchConfiguration alloc]
    initWithBundleID:nsstring_from_c_string(start.bundle_id())
    bundleName:nil
    arguments:extract_string_array(start.app_args())
    environment:extract_str_dict(start.env())
    waitForDebugger:(start.wait_for_debugger() ? YES : NO)
    io:io
    launchMode:start.foreground_if_running() ? FBApplicationLaunchModeForegroundIfRunning : FBApplicationLaunchModeFailIfRunning];
  id<FBLaunchedApplication> launchedApp = [[_commandExecutor launch_app:configuration] block:&error];
  if (!launchedApp) {
    if (error.code != 0) {
      return Status(grpc::StatusCode::INTERNAL, error.localizedDescription.UTF8String);
    } else {
      return Status(grpc::StatusCode::FAILED_PRECONDITION, error.localizedDescription.UTF8String);
    }
  }
  // Respond with the pid of the launched process
  idb::LaunchResponse response;
  idb::DebuggerInfo *debugger_info = response.mutable_debugger();
  debugger_info->set_pid(launchedApp.processIdentifier);
  stream->Write(response);
  // Return early if not waiting for output
  if (!start.wait_for()) {
    return Status::OK;
  }
  // Otherwise wait for the client to hang up.
  stream->Read(&request);
  [[launchedApp.applicationTerminated cancel] block:nil];
  [[FBFuture futureWithFutures:completions] block:nil];
  return Status::OK;
}}

Status FBIDBServiceHandler::crash_list(ServerContext *context, const idb::CrashLogQuery *request, idb::CrashLogResponse *response)
{@autoreleasepool{
  NSError *error = nil;
  NSPredicate *predicate = nspredicate_from_crash_log_query(request);
  NSArray<FBCrashLogInfo *> *crashes = [[_commandExecutor crash_list:predicate] block:&error];
  if (error) {
     return Status(grpc::StatusCode::INTERNAL, error.localizedDescription.UTF8String);
  }
  fill_crash_log_response(response, crashes);
  return Status::OK;
}}

Status FBIDBServiceHandler::crash_show(ServerContext *context, const idb::CrashShowRequest *request, idb::CrashShowResponse *response)
{@autoreleasepool{
  NSError *error = nil;
  NSString *name = nsstring_from_c_string(request->name());
  if (!name){
      return Status(grpc::StatusCode::INTERNAL, @"Missing crash name".UTF8String);
  }
  NSPredicate *predicate = [FBCrashLogInfo predicateForName:name];
  FBCrashLog *crash = [[_commandExecutor crash_show:predicate] block:&error];
  if (error) {
      return Status(grpc::StatusCode::INTERNAL, error.localizedDescription.UTF8String);
  }
  idb::CrashLogInfo *info = response->mutable_info();
  fill_crash_log_info(info, crash.info);
  response->set_contents(crash.contents.UTF8String);
  return Status::OK;
}}

Status FBIDBServiceHandler::crash_delete(ServerContext *context, const idb::CrashLogQuery *request, idb::CrashLogResponse *response)
{@autoreleasepool{
  NSError *error = nil;
  NSPredicate *predicate = nspredicate_from_crash_log_query(request);
  NSArray<FBCrashLogInfo *> *crashes = [[_commandExecutor crash_delete:predicate] block:&error];
  if (error) {
      return Status(grpc::StatusCode::INTERNAL, error.localizedDescription.UTF8String);
  }
  fill_crash_log_response(response, crashes);
  return Status::OK;
}}

Status FBIDBServiceHandler::xctest_list_bundles(ServerContext *context, const idb::XctestListBundlesRequest *request, idb::XctestListBundlesResponse *response)
{@autoreleasepool{
  NSError *error = nil;
  NSArray<id<FBXCTestDescriptor>> *descriptors = [[_commandExecutor list_test_bundles] block:&error];
  if (!descriptors) {
    return Status(grpc::StatusCode::INTERNAL, error.localizedDescription.UTF8String);
  }
  for (id<FBXCTestDescriptor> descriptor in descriptors) {
    idb::XctestListBundlesResponse_Bundles *bundle = response->add_bundles();
    bundle->set_name(descriptor.name.UTF8String ?: "");
    bundle->set_bundle_id(descriptor.testBundleID.UTF8String ?: "");
    for (NSString *architecture in descriptor.architectures) {
      bundle->add_architectures(architecture.UTF8String);
    }
  }
  return Status::OK;
}}

Status FBIDBServiceHandler::xctest_list_tests(ServerContext *context, const idb::XctestListTestsRequest *request, idb::XctestListTestsResponse *response)
{@autoreleasepool{
  NSError *error = nil;
  NSArray<NSString *> *tests = [[_commandExecutor list_tests_in_bundle:nsstring_from_c_string(request->bundle_name()) with_app:nsstring_from_c_string(request->app_path())] block:&error];
  if (!tests) {
    return Status(grpc::StatusCode::INTERNAL, error.localizedDescription.UTF8String);
  }
  for (NSString *test in tests) {
    response->add_names(test.UTF8String);
  }
  return Status::OK;
}}

Status FBIDBServiceHandler::xctest_run(ServerContext *context, const idb::XctestRunRequest *request, grpc::ServerWriter<idb::XctestRunResponse> *response)
{@autoreleasepool{
  FBXCTestRunRequest *xctestRunRequest = convert_xctest_request(request);
  if (xctestRunRequest == nil) {
    return Status(grpc::StatusCode::INTERNAL, "Failed to convert xctest request");
  }
  // Once the reporter is created, only it will perform writing to the writer.
  NSError *error = nil;
  FBIDBXCTestReporter *reporter = [[FBIDBXCTestReporter alloc] initWithResponseWriter:response queue:_target.workQueue logger:_target.logger reportResultBundle:xctestRunRequest.collectResultBundle];
  FBIDBTestOperation *operation = [[_commandExecutor xctest_run:xctestRunRequest reporter:reporter logger:[FBControlCoreLoggerFactory loggerToConsumer:reporter]] block:&error];
  if (!operation) {
    return Status(grpc::StatusCode::INTERNAL, error.localizedDescription.UTF8String);
  }
  reporter.configuration = operation.reporterConfiguration;

  // Make sure we've reported everything, otherwise we could write in the background (use-after-free)
  [reporter.reportingTerminated block:&error];
  if (error) {
    return Status(grpc::StatusCode::INTERNAL, error.localizedDescription.UTF8String);
  }

  // Wait for the test operation to finish
  [operation.completed block:&error];
  return Status::OK;
}}

Status FBIDBServiceHandler::log(ServerContext *context, const idb::LogRequest *request, grpc::ServerWriter<idb::LogResponse> *response)
{@autoreleasepool{
  // In the background, write out the log data. Prevent future writes if the client write fails.
  // This will happen asynchronously with the server thread.
  FBMutableFuture<NSNull *> *writingDone = FBMutableFuture.future;
  id<FBDataConsumer, FBDataConsumerLifecycle, FBDataConsumerSync> consumer = [FBBlockDataConsumer synchronousDataConsumerWithBlock:^(NSData *data) {
    idb::LogResponse item;
    item.set_output(data.bytes, data.length);
    if (writingDone.hasCompleted) {
      return;
    }
    bool success = response->Write(item);
    if (success) {
      return;
    }
    // The client write failed, the client has gone so don't write again.
    [writingDone resolveWithResult:NSNull.null];
  }];

  // Setup the log operation.
  NSError *error = nil;
  BOOL logFromCompanion = request->source() == idb::LogRequest::Source::LogRequest_Source_COMPANION;
  NSArray<NSString *> *arguments = extract_string_array(request->arguments());
  id<FBLogOperation> operation = [(logFromCompanion ? [_commandExecutor tail_companion_logs:consumer] : [_target tailLog:arguments consumer:consumer]) block:&error];
  if (!operation) {
    return Status(grpc::StatusCode::INTERNAL, error.localizedDescription.UTF8String);
  }

  // Poll on completion (logging happens asynchronously). This occurs when the stream is cancelled, the log operation is done, or the last write failed.
  FBFuture<NSNull *> *completed = [FBFuture race:@[writingDone, operation.completed]];
  while (completed.hasCompleted == NO && context->IsCancelled() == false) {
    // Sleep for 200ms before polling again.
    usleep(1000 * 200);
  }

  // Signal that we're done writing due to the operation completion or the client going away.
  // This will also prevent the polling of the ClientContext.
  [writingDone resolveWithResult:NSNull.null];

  // Teardown the log operation now that we're done with it
  FBFuture<NSNull *> *teardown = [operation.completed cancel];
  [teardown block:nil];

  return Status::OK;
}}

Status FBIDBServiceHandler::record(grpc::ServerContext *context, grpc::ServerReaderWriter<idb::RecordResponse, idb::RecordRequest> *stream)
{@autoreleasepool{
  idb::RecordRequest initial;
  stream->Read(&initial);
  NSError *error = nil;
  const std::string requestedFilePath = initial.start().file_path();
  NSString *filePath = requestedFilePath.length() > 0 ? nsstring_from_c_string(requestedFilePath.c_str()) : [[_target.auxillaryDirectory stringByAppendingPathComponent:@"idb_encode"] stringByAppendingPathExtension:@"mp4"];
  id<FBiOSTargetOperation> operation = [[_target startRecordingToFile:filePath] block:&error];
  if (!operation) {
    return Status(grpc::StatusCode::INTERNAL, error.localizedDescription.UTF8String);
  }
  idb::RecordRequest stop;
  stream->Read(&stop);
  if (![[_target stopRecording] succeeds:&error]) {
    return Status(grpc::StatusCode::INTERNAL, error.localizedDescription.UTF8String);
  }
  if (requestedFilePath.length() > 0) {
    return respond_file_path(nil, filePath, stream);
  } else {
    return drain_writer([FBArchiveOperations createGzipForPath:filePath queue:dispatch_queue_create("com.facebook.idb.record", DISPATCH_QUEUE_SERIAL) logger:_target.logger], stream);
  }
}}

Status FBIDBServiceHandler::video_stream(ServerContext* context, grpc::ServerReaderWriter<idb::VideoStreamResponse, idb::VideoStreamRequest>* stream)
{@autoreleasepool{
  NSError *error = nil;
  idb::VideoStreamRequest request;
  FBMutableFuture<NSNull *> *done = FBMutableFuture.future;
  id<FBDataConsumer> consumer = consumer_from_request(stream, request, done, &error);
  if (!consumer) {
    return Status(grpc::StatusCode::INTERNAL, error.localizedDescription.UTF8String);
  }
  idb::VideoStreamRequest_Start start = request.start();
  NSNumber *framesPerSecond = start.fps() > 0 ? @(start.fps()) : nil;
  FBVideoStreamEncoding encoding = @"";
  switch (start.format()) {
    case idb::VideoStreamRequest_Format_RBGA:
      encoding = FBVideoStreamEncodingBGRA;
      break;
    case idb::VideoStreamRequest_Format_H264:
      encoding = FBVideoStreamEncodingH264;
      break;
    case idb::VideoStreamRequest_Format_MJPEG:
      encoding = FBVideoStreamEncodingMJPEG;
      break;
    case idb::VideoStreamRequest_Format_MINICAP:
      encoding = FBVideoStreamEncodingMinicap;
      break;
    default:
      return Status(grpc::StatusCode::INTERNAL, "Invalid Video format provided");
  }
  NSNumber *compressionQuality = @(start.compression_quality());
  NSNumber *scaleFactor = @(start.scale_factor());
  NSNumber *avgBitrate = start.avg_bitrate() > 0 ? @(start.avg_bitrate()) : nil;
  FBVideoStreamConfiguration *configuration = [[FBVideoStreamConfiguration alloc] initWithEncoding:encoding framesPerSecond:framesPerSecond compressionQuality:compressionQuality scaleFactor:scaleFactor avgBitrate:avgBitrate];
  id<FBVideoStream> videoStream = [[_target createStreamWithConfiguration:configuration] block:&error];
  if (!stream) {
    return Status(grpc::StatusCode::INTERNAL, error.localizedDescription.UTF8String);
  }
  BOOL success = [[videoStream startStreaming:consumer] block:&error] != nil;
  if (success == NO) {
    return Status(grpc::StatusCode::INTERNAL, error.localizedDescription.UTF8String);
  }

  // Wait for the client to hangup or stream to stop
  FBFuture<NSNull *> *clientStopped = resolve_next_read(stream);
  [[FBFuture race:@[clientStopped, videoStream.completed]] block:nil];

  // Signal that we're done so we don't write to a dangling pointer.
  [done resolveWithResult:NSNull.null];
  // Stop the streaming for real. It may have stopped already in which case this returns instantly.
  success = [[videoStream stopStreaming] block:&error] != nil;
  [_target.logger logFormat:@"The video stream is terminated"];
  if (success == NO) {
    return Status(grpc::StatusCode::INTERNAL, error.localizedDescription.UTF8String);
  }
  return Status::OK;
}}

Status FBIDBServiceHandler::push(grpc::ServerContext *context, grpc::ServerReader<idb::PushRequest> *reader, idb::PushResponse *response)
{@autoreleasepool{
  NSError *error = nil;
  idb::PushRequest request;
  reader->Read(&request);
  if (request.value_case() != idb::PushRequest::kInner) {
    return Status(grpc::StatusCode::INTERNAL, "First message must contain the commands information");
  }
  const idb::PushRequest_Inner inner = request.inner();

  [[filepaths_from_reader(_commandExecutor.temporaryDirectory, reader, false, _target.logger) onQueue:_target.asyncQueue pop:^FBFuture<NSNull *> *(NSArray<NSURL *> *files) {
    return [_commandExecutor push_files:files to_path:nsstring_from_c_string(inner.dst_path()) containerType:file_container(inner.container())];
  }] block:&error];
  if (error) {
    return Status(grpc::StatusCode::INTERNAL, error.localizedDescription.UTF8String);
  }
  return Status::OK;
}}

Status FBIDBServiceHandler::pull(ServerContext *context, const ::idb::PullRequest *request, grpc::ServerWriter<::idb::PullResponse> *stream)
{@autoreleasepool{
  NSString *path = nsstring_from_c_string(request->src_path());
  NSError *error = nil;
  if (request->dst_path().length() > 0) {
    NSString *filePath = [[_commandExecutor pull_file_path:path destination_path:nsstring_from_c_string(request->dst_path()) containerType:file_container(request->container())] block:&error];
    if (error) {
      return Status(grpc::StatusCode::INTERNAL, error.localizedDescription.UTF8String);
    }
    return respond_file_path(nil, filePath, stream);
  } else {
    NSURL *url = [_commandExecutor.temporaryDirectory temporaryDirectory];
    NSString *tempPath = [url.path stringByAppendingPathComponent:path.lastPathComponent];
    NSString *filePath = [[_commandExecutor pull_file_path:path destination_path:tempPath containerType:file_container(request->container())] block:&error];
    if (error) {
      return Status(grpc::StatusCode::INTERNAL, error.localizedDescription.UTF8String);
    }
    return drain_writer([FBArchiveOperations
                         createGzippedTarForPath:filePath
                         logger:_target.logger],
                        stream);
  }
}}

Status FBIDBServiceHandler::tail(ServerContext* context, grpc::ServerReaderWriter<idb::TailResponse, idb::TailRequest>* stream)
{@autoreleasepool{
  idb::TailRequest request;
  stream->Read(&request);
  idb::TailRequest_Start start = request.start();
  NSString *path = nsstring_from_c_string(start.path());
  NSString *container = file_container(start.container());

  FBMutableFuture<NSNull *> *finished = FBMutableFuture.future;
  id<FBDataConsumer, FBDataConsumerSync> consumer = [FBBlockDataConsumer synchronousDataConsumerWithBlock:^(NSData *data) {
    if (finished.hasCompleted) {
      return;
    }
    idb::TailResponse response;
    response.set_data(data.bytes, data.length);
    stream->Write(response);
  }];

  NSError *error = nil;
  FBFuture<NSNull *> *tailOperation = [[_commandExecutor tail:path to_consumer:consumer in_container:container] block:&error];
  if (!tailOperation) {
    return Status(grpc::StatusCode::INTERNAL, error.localizedDescription.UTF8String);
  }

  stream->Read(&request);
  [[tailOperation cancel] block:nil];
  [finished resolveWithResult:NSNull.null];

  return Status::OK;
}}

Status FBIDBServiceHandler::describe(ServerContext *context, const idb::TargetDescriptionRequest *request, idb::TargetDescriptionResponse *response)
{@autoreleasepool{
  // Populate the default values
  idb::TargetDescription *description = response->mutable_target_description();
  FBiOSTargetScreenInfo *screenInfo = _target.screenInfo;
  if (screenInfo) {
    idb::ScreenDimensions *dimensions = description->mutable_screen_dimensions();
    dimensions->set_width(screenInfo.widthPixels);
    dimensions->set_height(screenInfo.heightPixels);
    dimensions->set_height_points(screenInfo.heightPixels/screenInfo.scale);
    dimensions->set_width_points(screenInfo.widthPixels/screenInfo.scale);
    dimensions->set_density(screenInfo.scale);
  }
  description->set_udid(_target.udid.UTF8String);
  description->set_name(_target.name.UTF8String);
  description->set_state(FBiOSTargetStateStringFromState(_target.state).UTF8String);
  description->set_target_type(FBiOSTargetTypeStringFromTargetType(_target.targetType).lowercaseString.UTF8String);
  description->set_os_version(_target.osVersion.name.UTF8String);
  description->set_architecture(_target.architecture.UTF8String);

  // Add extended information
  NSDictionary<NSString *, id> *extendedInformation = _target.extendedInformation;
  NSError *error = nil;
  NSData *data = [NSJSONSerialization dataWithJSONObject:extendedInformation options:0 error:&error];
  if (!data) {
    return Status(grpc::StatusCode::INTERNAL, error.localizedDescription.UTF8String);
  }
  description->set_extended(data.bytes, data.length);

  // Also attach the companion metadata
  populate_companion_info(response->mutable_companion(), _eventReporter, _target);

  // Only fetch diagnostic information when requested.
  if (!request->fetch_diagnostics()) {
    return Status::OK;
  }
  NSDictionary<NSString *, id> *diagnosticInformation = [[_commandExecutor diagnostic_information] block:&error];
  if (!diagnosticInformation) {
    return Status(grpc::StatusCode::INTERNAL, error.localizedDescription.UTF8String);
  }
  data = [NSJSONSerialization dataWithJSONObject:diagnosticInformation options:0 error:&error];
  if (!data) {
    return Status(grpc::StatusCode::INTERNAL, error.localizedDescription.UTF8String);
  }
  description->set_diagnostics(data.bytes, data.length);

  return Status::OK;
}}

Status FBIDBServiceHandler::add_media(grpc::ServerContext *context, grpc::ServerReader<idb::AddMediaRequest> *reader, idb::AddMediaResponse *response)
{@autoreleasepool{
  NSError *error = nil;
  [[filepaths_from_reader(_commandExecutor.temporaryDirectory, reader, true, _target.logger)
    onQueue:_target.asyncQueue pop:^(NSArray<NSURL *> *files) {
      return [_commandExecutor add_media:files];
    }]
    block:&error];
  if (error) {
    return Status(grpc::StatusCode::INTERNAL, error.localizedDescription.UTF8String);
  }
  return Status::OK;
}}

Status FBIDBServiceHandler::instruments_run(grpc::ServerContext *context, grpc::ServerReaderWriter<idb::InstrumentsRunResponse, idb::InstrumentsRunRequest> *stream)
{@autoreleasepool{
  __block idb::InstrumentsRunRequest startRunRequest;
  __block pthread_mutex_t mutex;
  pthread_mutex_init(&mutex, NULL);
  __block bool finished_writing = NO;
  dispatch_queue_t queue = dispatch_queue_create("com.facebook.idb.instruments.server", DISPATCH_QUEUE_SERIAL);
  dispatch_sync(queue, ^{
    idb::InstrumentsRunRequest request;
    stream->Read(&request);
    startRunRequest = request;
  });

  FBInstrumentsConfiguration *configuration = translate_instruments_configuration(startRunRequest.start(), _commandExecutor.storageManager);

  NSError *error = nil;
  id<FBDataConsumer> consumer = [FBBlockDataConsumer asynchronousDataConsumerOnQueue:queue consumer:^(NSData *data) {
    idb::InstrumentsRunResponse response;
    response.set_log_output(data.bytes, data.length);
    pthread_mutex_lock(&mutex);
    if (!finished_writing) {
      stream->Write(response);
    }
    pthread_mutex_unlock(&mutex);

  }];
  id<FBControlCoreLogger> logger = [FBControlCoreLoggerFactory compositeLoggerWithLoggers:@[
    [FBControlCoreLoggerFactory loggerToConsumer:consumer],
    _target.logger,
  ]];
  FBInstrumentsOperation *operation = [[_target startInstruments:configuration logger:logger] block:&error];
  if (!operation) {
    pthread_mutex_lock(&mutex);
    finished_writing = YES;
    pthread_mutex_unlock(&mutex);
    return Status(grpc::StatusCode::INTERNAL, error.localizedDescription.UTF8String);
  }
  __block idb::InstrumentsRunRequest stopRunRequest;
  dispatch_sync(queue, ^{
    idb::InstrumentsRunResponse response;
    response.set_state(idb::InstrumentsRunResponse::State::InstrumentsRunResponse_State_RUNNING_INSTRUMENTS);
    stream->Write(response);
    idb::InstrumentsRunRequest request;
    stream->Read(&request);
    stopRunRequest = request;
  });
  if (![operation.stop succeeds:&error]) {
    pthread_mutex_lock(&mutex);
    finished_writing = YES;
    pthread_mutex_unlock(&mutex);
    return Status(grpc::StatusCode::INTERNAL, error.localizedDescription.UTF8String);
  }
  NSArray<NSString *> *postProcessArguments = [_commandExecutor.storageManager interpolateArgumentReplacements:extract_string_array(stopRunRequest.stop().post_process_arguments())];
  dispatch_sync(queue, ^{
    idb::InstrumentsRunResponse response;
    response.set_state(idb::InstrumentsRunResponse::State::InstrumentsRunResponse_State_POST_PROCESSING);
    stream->Write(response);
  });
  NSURL *processed = [[FBInstrumentsOperation postProcess:postProcessArguments traceDir:operation.traceDir queue:queue logger:logger] block:&error];
  pthread_mutex_lock(&mutex);
  finished_writing = YES;
  pthread_mutex_unlock(&mutex);
  if (!processed) {
    return Status(grpc::StatusCode::INTERNAL, error.localizedDescription.UTF8String);
  }
  return drain_writer([FBArchiveOperations createGzippedTarForPath:processed.path logger:_target.logger], stream);
}}

Status FBIDBServiceHandler::debugserver(grpc::ServerContext *context, grpc::ServerReaderWriter<idb::DebugServerResponse, idb::DebugServerRequest> *stream)
{@autoreleasepool{
  idb::DebugServerRequest request;
  stream->Read(&request);

  NSError *error = nil;
  switch (request.control_case()) {
    case idb::DebugServerRequest::ControlCase::kStart: {
      idb::DebugServerRequest::Start start = request.start();
      id<FBDebugServer> debugServer = [[_commandExecutor debugserver_start:nsstring_from_c_string(start.bundle_id())] block:&error];
      if (!debugServer) {
        return Status(grpc::StatusCode::INTERNAL, error.localizedDescription.UTF8String);
      }
      stream->Write(translate_debugserver_status(debugServer));
      return Status::OK;
    }
    case idb::DebugServerRequest::ControlCase::kStatus: {
      id<FBDebugServer> debugServer = [[_commandExecutor debugserver_status] block:&error];
      stream->Write(translate_debugserver_status(debugServer));
      return Status::OK;
    }
    case idb::DebugServerRequest::ControlCase::kStop: {
      id<FBDebugServer> debugServer = [[_commandExecutor debugserver_stop] block:&error];
      if (!debugServer) {
        return Status(grpc::StatusCode::INTERNAL, error.localizedDescription.UTF8String);
      }
      stream->Write(translate_debugserver_status(debugServer));
      return Status::OK;
    }
    default: {
      return Status(grpc::StatusCode::UNIMPLEMENTED, NULL);
    }
  }
}}

Status FBIDBServiceHandler::dap(grpc::ServerContext *context, grpc::ServerReaderWriter<idb::DapResponse, idb::DapRequest> *stream)
{@autoreleasepool{
  idb::DapRequest initial_request;
  stream->Read(&initial_request);
  if (initial_request.control_case() != idb::DapRequest::ControlCase::kStart) {
    return Status(grpc::StatusCode::FAILED_PRECONDITION, "Dap command expected a Start messaged in the beginning of the Stream");
  }
  idb::DapRequest_Start start = initial_request.start();
  NSString *pkg_id = nsstring_from_c_string(start.debugger_pkg_id());
  NSString *lldb_vscode = [@"dap" stringByAppendingPathComponent:[pkg_id stringByAppendingPathComponent: @"usr/bin/lldb-vscode"]];

  id<FBDataConsumer> reader = [FBBlockDataConsumer synchronousDataConsumerWithBlock:^(NSData *data) {
    idb::DapResponse response;
    idb::DapResponse_Pipe *stdout = response.mutable_stdout();
    stdout->set_data(data.bytes, data.length);
    stream->Write(response);
    [_target.logger.debug logFormat:@"Dap server stdout consumer: sent %lu bytes.", data.length];
  }];


  [_target.logger.debug logFormat:@"Starting dap server with path %@", lldb_vscode];
  NSError *error = nil;
  FBProcessInput<id<FBDataConsumer>> *writer = [FBProcessInput inputFromConsumer];
  FBProcess *process = [[_commandExecutor dapServerWithPath:lldb_vscode stdIn:writer stdOut:reader] awaitWithTimeout:600 error:&error];
  if (error){
    NSString *errorMsg = [NSString stringWithFormat:@"Failed to spaw DAP server. Error: %@", error.localizedDescription];
    return Status(grpc::StatusCode::INTERNAL, errorMsg.UTF8String);
  }
  [_target.logger.debug logFormat:@"Dap server spawn with PID: %d", process.processIdentifier];
  idb::DapResponse response;
  response.mutable_started();
  stream->Write(response);

  dispatch_queue_t write_queue = dispatch_queue_create("com.facebook.idb.dap.write", DISPATCH_QUEUE_SERIAL);
  auto writeFuture = [FBFuture onQueue:write_queue resolveWhen:^BOOL {
    idb::DapRequest request;
    stream->Read(&request);
    if (request.control_case() == idb::DapRequest::ControlCase::kStop){
      [_target.logger.debug logFormat:@"Received stop from Dap Request"];
      [_target.logger.debug logFormat:@"Dap server with pid %d. Stderr: %@", process.processIdentifier, process.stdErr];
      return YES;
    }

    idb::DapRequest_Pipe pipe = request.pipe();
    auto raw_data = pipe.data();
    NSData *data = [NSData dataWithBytes:raw_data.c_str() length:raw_data.length()];
    if (data.length == 0) {
      [_target.logger.debug logFormat:@"Dap Request. Receiving empty messages. Transmission finished."];
      return YES;
    }
    [_target.logger.debug logFormat:@"Dap Request. Received %lu bytes from client", data.length];
    [writer.contents consumeData:data];
    return NO;
  }];

  //  Debug session shouln't be longer than 10hours
  [writeFuture awaitWithTimeout:36000 error:&error];
  if (error){
    NSString *errorMsg = [NSString stringWithFormat:@"Error in writting to dap server stdout: %@", error.localizedDescription];
    return Status(grpc::StatusCode::INTERNAL, errorMsg.UTF8String);
  }

  idb::DapResponse_Event *stopped = response.mutable_stopped();
  stopped->set_desc(@"Dap server stopped.".UTF8String);
  stream->Write(response);

  return Status::OK;
}}




Status FBIDBServiceHandler::connect(grpc::ServerContext *context, const idb::ConnectRequest *request, idb::ConnectResponse *response)
{@autoreleasepool{
  // Add Meta to Reporter
  [_eventReporter addMetadata:extract_str_dict(request->metadata())];

  // Get the local state
  BOOL isLocal = [NSFileManager.defaultManager fileExistsAtPath:nsstring_from_c_string(request->local_file_path())];
  idb::CompanionInfo *info = response->mutable_companion();
  info->set_is_local(isLocal);

  // Populate the other values.
  populate_companion_info(info, _eventReporter, _target);

  return Status::OK;
}}

Status FBIDBServiceHandler::xctrace_record(ServerContext *context,grpc::ServerReaderWriter<idb::XctraceRecordResponse, idb::XctraceRecordRequest> *stream)
{@autoreleasepool{
  __block idb::XctraceRecordRequest recordRequest;
  __block pthread_mutex_t mutex;
  pthread_mutex_init(&mutex, NULL);
  __block bool finished_writing = NO;
  dispatch_queue_t queue = dispatch_queue_create("com.facebook.idb.xctrace.record", DISPATCH_QUEUE_SERIAL);
  // @lint-ignore FBOBJCDISCOURAGEDFUNCTION
  dispatch_sync(queue, ^{
    idb::XctraceRecordRequest request;
    stream->Read(&request);
    recordRequest = request;
  });

  FBXCTraceRecordConfiguration *configuration = translate_xctrace_record_configuration(recordRequest.start());

  NSError *error = nil;
  id<FBDataConsumer> consumer = [FBBlockDataConsumer asynchronousDataConsumerOnQueue:queue consumer:^(NSData *data) {
    idb::XctraceRecordResponse response;
    response.set_log(data.bytes, data.length);
    pthread_mutex_lock(&mutex);
    if (!finished_writing) {
      stream->Write(response);
    }
    pthread_mutex_unlock(&mutex);
  }];
  id<FBControlCoreLogger> logger = [FBControlCoreLoggerFactory compositeLoggerWithLoggers:@[
    [FBControlCoreLoggerFactory loggerToConsumer:consumer],
    _target.logger,
  ]];

  FBXCTraceRecordOperation *operation = [[_target startXctraceRecord:configuration logger:logger] block:&error];
  if (!operation) {
    pthread_mutex_lock(&mutex);
    finished_writing = YES;
    pthread_mutex_unlock(&mutex);
    return Status(grpc::StatusCode::INTERNAL, error.localizedDescription.UTF8String);
  }
  // @lint-ignore FBOBJCDISCOURAGEDFUNCTION
  dispatch_sync(queue, ^{
    idb::XctraceRecordResponse response;
    response.set_state(idb::XctraceRecordResponse::State::XctraceRecordResponse_State_RUNNING);
    stream->Write(response);
    idb::XctraceRecordRequest request;
    stream->Read(&request);
    recordRequest = request;
  });
  NSTimeInterval stopTimeout = recordRequest.stop().timeout() ?: DefaultXCTraceRecordStopTimeout;
  if (![[operation stopWithTimeout:stopTimeout] succeeds:&error]) {
    pthread_mutex_lock(&mutex);
    finished_writing = YES;
    pthread_mutex_unlock(&mutex);
    return Status(grpc::StatusCode::INTERNAL, error.localizedDescription.UTF8String);
  }
  NSArray<NSString *> *postProcessArgs = extract_string_array(recordRequest.stop().args());
  // @lint-ignore FBOBJCDISCOURAGEDFUNCTION
  dispatch_sync(queue, ^{
    idb::XctraceRecordResponse response;
    response.set_state(idb::XctraceRecordResponse::State::XctraceRecordResponse_State_PROCESSING);
    stream->Write(response);
  });
  NSURL *processed = [[FBInstrumentsOperation postProcess:postProcessArgs traceDir:operation.traceDir queue:queue logger:logger] block:&error];
  pthread_mutex_lock(&mutex);
  finished_writing = YES;
  pthread_mutex_unlock(&mutex);
  if (!processed) {
    return Status(grpc::StatusCode::INTERNAL, error.localizedDescription.UTF8String);
  }
  return drain_writer([FBArchiveOperations createGzippedTarForPath:processed.path logger:_target.logger], stream);
}}

Status FBIDBServiceHandler::send_notification(grpc::ServerContext *context, const idb::SendNotificationRequest *request, idb::SendNotificationResponse *response)
{@autoreleasepool{
  NSError *error = nil;
  [[_commandExecutor sendPushNotificationForBundleID:nsstring_from_c_string(request->bundle_id()) jsonPayload:nsstring_from_c_string(request->json_payload())] block:&error];
  if (error) {
    return Status(grpc::StatusCode::INTERNAL, [error.localizedDescription UTF8String]);
  }
  return Status::OK;
}}

Status FBIDBServiceHandler::simulate_memory_warning(grpc::ServerContext *context, const idb::SimulateMemoryWarningRequest *request, idb::SimulateMemoryWarningResponse *response)
{@autoreleasepool{
  NSError *error = nil;
  [[_commandExecutor simulateMemoryWarning] block:&error];
  if (error) {
    return Status(grpc::StatusCode::INTERNAL, [error.localizedDescription UTF8String]);
  }
  return Status::OK;
}}
