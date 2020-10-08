/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <string>

#import <idbGRPC/idb.grpc.pb.h>
#import <idbGRPC/idb.pb.h>
#import <grpcpp/grpcpp.h>
#import <FBSimulatorControl/FBSimulatorControl.h>

#import "FBDataDownloadInput.h"
#import "FBIDBCommandExecutor.h"
#import "FBIDBPortsConfiguration.h"
#import "FBIDBServiceHandler.h"
#import "FBIDBStorageManager.h"
#import "FBIDBTestOperation.h"
#import "FBIDBXCTestReporter.h"
#import "FBStorageUtils.h"
#import "FBTemporaryDirectory.h"

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
static Status drain_writer(FBFuture<FBTask<NSNull *, NSInputStream *, id> *> *taskFuture, grpc::internal::WriterInterface<T> *stream)
{
  NSError *error = nil;
  FBTask<NSNull *, NSInputStream *, id> *task = [taskFuture block:&error];
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
    payload->set_data(buffer, size);
    stream->Write(response);
  }
  [inputStream close];
  NSNumber *exitCode = [task.completed block:&error];
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

static id<FBDataConsumerLifecycle> pipe_output(const idb::LaunchResponse::Interface interface, dispatch_queue_t queue, grpc::ServerReaderWriter<idb::LaunchResponse, idb::LaunchRequest> *stream)
{
  id<FBDataConsumerLifecycle> consumer = [FBBlockDataConsumer asynchronousDataConsumerOnQueue:queue consumer:^(NSData *data) {
    idb::LaunchResponse response;
    response.set_interface(interface);
    idb::LaunchResponse_Pipe *pipe = response.mutable_pipe();
    pipe->set_data(data.bytes, data.length);
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

static FBFutureContext<NSArray<NSURL *> *> *filepaths_from_tar(FBTemporaryDirectory *temporaryDirectory, FBProcessInput<NSOutputStream *> *input, bool extract_from_subdir, id<FBControlCoreLogger> logger)
{
  dispatch_queue_t queue = dispatch_queue_create("com.facebook.idb.processinput", DISPATCH_QUEUE_SERIAL);
  FBFutureContext<NSURL *> *tarContext = [temporaryDirectory withArchiveExtractedFromStream:input];
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
  switch (firstPayload.source_case()) {
    case idb::Payload::kData: {
      FBProcessInput<NSOutputStream *> *input = pipe_to_input(firstPayload, reader);
      return filepaths_from_tar(temporaryDirectory, input, extract_from_subdir, logger);
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

static FBXCTestRunRequest *convert_xctest_request(const idb::XctestRunRequest *request)
{
  NSNumber *testTimeout = @(request->timeout());
  NSArray<NSString *> *arguments = extract_string_array(request->arguments());
  NSDictionary<NSString *, NSString *> *environment = extract_str_dict(request->environment());
  NSMutableSet<NSString *> *testsToRun = nil;
  NSMutableSet<NSString *> *testsToSkip = NSMutableSet.set;
  NSString *testBundleID = nsstring_from_c_string(request->test_bundle_id());
  BOOL reportActivities = request->report_activities();
  BOOL collectCoverage = request->collect_coverage();

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
      return [FBXCTestRunRequest logicTestWithTestBundleID:testBundleID environment:environment arguments:arguments testsToRun:testsToRun testsToSkip:testsToSkip testTimeout:testTimeout reportActivities:reportActivities collectCoverage:collectCoverage];
    }
    case idb::XctestRunRequest_Mode::kApplication: {
      const idb::XctestRunRequest::Application application = request->mode().application();
      NSString *appBundleID = nsstring_from_c_string(application.app_bundle_id());
      return [FBXCTestRunRequest applicationTestWithTestBundleID:testBundleID appBundleID:appBundleID environment:environment arguments:arguments testsToRun:testsToRun testsToSkip:testsToSkip testTimeout:testTimeout reportActivities:reportActivities collectCoverage:collectCoverage];
    }
    case idb::XctestRunRequest_Mode::kUi: {
      const idb::XctestRunRequest::UI ui = request->mode().ui();
      NSString *appBundleID = nsstring_from_c_string(ui.app_bundle_id());
      NSString *testHostAppBundleID = nsstring_from_c_string(ui.test_host_app_bundle_id());
      return [FBXCTestRunRequest uiTestWithTestBundleID:testBundleID appBundleID:appBundleID testHostAppBundleID:testHostAppBundleID environment:environment arguments:arguments testsToRun:testsToRun testsToSkip:testsToSkip testTimeout:testTimeout reportActivities:reportActivities collectCoverage:collectCoverage];
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

static idb::TargetDescription description_of_target(id<FBiOSTarget> target)
{
  idb::TargetDescription description;
  description.set_udid(target.udid.UTF8String);
  description.set_name(target.name.UTF8String);
  idb::ScreenDimensions *screenDimensions = description.mutable_screen_dimensions();
  screenDimensions->set_width(target.screenInfo.widthPixels);
  screenDimensions->set_height(target.screenInfo.heightPixels);
  screenDimensions->set_density(target.screenInfo.scale);
  screenDimensions->set_width_points(target.screenInfo.widthPixels / target.screenInfo.scale);
  screenDimensions->set_height_points(target.screenInfo.heightPixels / target.screenInfo.scale);
  description.set_state(FBiOSTargetStateStringFromState(target.state).UTF8String);
  description.set_target_type(FBiOSTargetTypeStringsFromTargetType(target.targetType)[0].UTF8String);
  description.set_target_type(target.osVersion.name.UTF8String);
  description.set_target_type(target.architecture.UTF8String);
  return description;
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
    case idb::FileContainer_Kind_APPLICATION:
    default:
      return nsstring_from_c_string(container.bundle_id());
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
  idb::InstallRequest request;
  stream->Read(&request);
  idb::Payload payload;
  NSString *name = NSUUID.UUID.UUIDString;
  if (request.name_hint().length()) {
    name = nsstring_from_c_string(request.name_hint());
    stream->Read(&request);
  }
  payload = request.payload();

  switch (payload.source_case()) {
    case idb::Payload::kData: {
      FBProcessInput<NSOutputStream *> *dataStream = pipe_to_input_output(payload, stream);
      switch (destination) {
        case idb::InstallRequest_Destination::InstallRequest_Destination_APP:
          return [_commandExecutor install_app_stream:dataStream];
        case idb::InstallRequest_Destination::InstallRequest_Destination_XCTEST:
          return [_commandExecutor install_xctest_app_stream:dataStream];
        case idb::InstallRequest_Destination::InstallRequest_Destination_DSYM:
          return [_commandExecutor install_dsym_stream:dataStream];
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
          return [_commandExecutor install_app_stream:download.input];
        case idb::InstallRequest_Destination::InstallRequest_Destination_XCTEST:
          return [_commandExecutor install_xctest_app_stream:download.input];
        case idb::InstallRequest_Destination::InstallRequest_Destination_DSYM:
          return [_commandExecutor install_dsym_stream:download.input];
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
          return [_commandExecutor install_app_file_path:filePath];
        case idb::InstallRequest_Destination::InstallRequest_Destination_XCTEST:
          return [_commandExecutor install_xctest_app_file_path:filePath];
        case idb::InstallRequest_Destination::InstallRequest_Destination_DSYM:
          return [_commandExecutor install_dsym_file_path:filePath];
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
  NSDictionary<FBInstalledApplication *, id> *apps = [[_commandExecutor list_apps] block:&error];
  for (FBInstalledApplication *app in apps.allKeys) {
    idb::InstalledAppInfo *appInfo = response->add_apps();
    appInfo->set_bundle_id(app.bundle.identifier.UTF8String ?: "");
    appInfo->set_name(app.bundle.name.UTF8String ?: "");
    appInfo->set_install_type([FBInstalledApplication stringFromApplicationInstallType:app.installType].UTF8String);
    for (NSString *architecture in app.bundle.binary.architectures) {
      appInfo->add_architectures(architecture.UTF8String);
    }
    id processState = apps[app];
    if ([processState isKindOfClass:NSNumber.class]) {
      appInfo->set_process_state(idb::InstalledAppInfo_AppProcessState_RUNNING);
    } else {
      appInfo->set_process_state(idb::InstalledAppInfo_AppProcessState_UNKNOWN);
    }
    appInfo->set_debuggable(app.installType == FBApplicationInstallTypeUserDevelopment && [persistedBundleIDs containsObject:app.bundle.identifier]);
  }
  if (error) {
    return Status(grpc::StatusCode::INTERNAL, error.localizedDescription.UTF8String);
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
  NSArray<NSDictionary<NSString *, id> *> *info = [[_commandExecutor accessibility_info_at_point:point nestedFormat:nestedFormat] block:&error];

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
  NSDictionary<NSNumber *, FBSettingsApprovalService> *mapping = @{
    @((int)idb::ApproveRequest_Permission::ApproveRequest_Permission_PHOTOS): FBSettingsApprovalServicePhotos,
    @((int)idb::ApproveRequest_Permission::ApproveRequest_Permission_CAMERA): FBSettingsApprovalServiceCamera,
    @((int)idb::ApproveRequest_Permission::ApproveRequest_Permission_CONTACTS): FBSettingsApprovalServiceContacts,
    @((int)idb::ApproveRequest_Permission::ApproveRequest_Permission_URL): FBSettingsApprovalServiceUrl,
    @((int)idb::ApproveRequest_Permission::ApproveRequest_Permission_LOCATION): FBSettingsApprovalServiceLocation,
    @((int)idb::ApproveRequest_Permission::ApproveRequest_Permission_NOTIFICATION): FBSettingsApprovalServiceNotification,
  };
  NSMutableSet<FBSettingsApprovalService> *services = NSMutableSet.set;
  for (int j = 0; j < request->permissions_size(); j++) {
    idb::ApproveRequest_Permission permission = request->permissions(j);
    [services addObject:mapping[@(permission)]];
  }
  if ([services containsObject:FBSettingsApprovalServiceUrl]) {
    [services removeObject:FBSettingsApprovalServiceUrl];
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
      [[_commandExecutor set_hardware_keyboard_enabled:request->hardwarekeyboard().enabled()] await:&error];
      if (error) {
        return Status(grpc::StatusCode::INTERNAL, error.localizedDescription.UTF8String);
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
  FBProcessOutputConfiguration *output = FBProcessOutputConfiguration.outputToDevNull;
  NSMutableArray<FBFuture *> *completions = NSMutableArray.array;
  if (start.wait_for()) {
    dispatch_queue_t writeQueue = dispatch_queue_create("com.facebook.idb.launch.write", DISPATCH_QUEUE_SERIAL);
    id<FBDataConsumerLifecycle> consumer = pipe_output(idb::LaunchResponse::Interface::LaunchResponse_Interface_STDOUT, writeQueue, stream);
    [completions addObject:consumer.finishedConsuming];
    output = [output withStdOut:consumer error:&error];
    if (!output) {
      return Status(grpc::StatusCode::INTERNAL, error.localizedDescription.UTF8String);
    }
    consumer = pipe_output(idb::LaunchResponse::Interface::LaunchResponse_Interface_STDERR, writeQueue, stream);
    [completions addObject:consumer.finishedConsuming];
    output = [output withStdErr:consumer error:&error];
    if (!output) {
      return Status(grpc::StatusCode::INTERNAL, error.localizedDescription.UTF8String);
    }
  }
  FBApplicationLaunchConfiguration *configuration = [FBApplicationLaunchConfiguration
    configurationWithBundleID:nsstring_from_c_string(start.bundle_id())
    bundleName:nil
    arguments:extract_string_array(start.app_args())
    environment:extract_str_dict(start.env())
    output:output
    launchMode:start.foreground_if_running() ? FBApplicationLaunchModeForegroundIfRunning : FBApplicationLaunchModeFailIfRunning];
  id<FBLaunchedProcess> process = [[_commandExecutor launch_app:configuration] block:&error];
  if (!process) {
    if (error.code != 0) {
      return Status(grpc::StatusCode::INTERNAL, error.localizedDescription.UTF8String);
    } else {
      return Status(grpc::StatusCode::FAILED_PRECONDITION, error.localizedDescription.UTF8String);
    }
  }
  if (!start.wait_for()) {
    idb::LaunchResponse response;
    stream->Write(response);
    return Status::OK;
  }
  stream->Read(&request);
  [[process.exitCode cancel] block:nil];
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
  NSSet<id<FBXCTestDescriptor>> *descriptors = [[_commandExecutor list_test_bundles] block:&error];
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
  FBIDBXCTestReporter *reporter = [[FBIDBXCTestReporter alloc] initWithResponseWriter:response reportAttachments:request->report_attachments() queue:_target.workQueue logger:_target.logger];
  FBIDBTestOperation *operation = [[_commandExecutor xctest_run:xctestRunRequest reporter:reporter logger:[FBControlCoreLogger loggerToConsumer:reporter]] block:&error];
  reporter.resultBundlePath = operation.resultBundlePath;
  reporter.coveragePath = operation.coveragePath;
  reporter.binaryPath = operation.binaryPath;
  if (!operation) {
    return Status(grpc::StatusCode::INTERNAL, error.localizedDescription.UTF8String);
  }
  // First wait for the test operation to finish
  [operation.completed block:&error];
  // Then make sure we've reported everything, otherwise we could write in the background (use-after-free)
  [reporter.reportingTerminated block:&error];
  return Status::OK;
}}

Status FBIDBServiceHandler::log(ServerContext *context, const idb::LogRequest *request, grpc::ServerWriter<idb::LogResponse> *response)
{@autoreleasepool{
  NSArray<NSString *> *arguments = extract_string_array(request->arguments());
  FBMutableFuture<NSNull *> *clientClosed = FBMutableFuture.future;
  id<FBDataConsumer, FBDataConsumerLifecycle> consumer = [FBBlockDataConsumer synchronousDataConsumerWithBlock:^(NSData *data) {
    if (clientClosed.hasCompleted) {
      return;
    }
    idb::LogResponse item;
    item.set_output(data.bytes, data.length);
    if (!response->Write(item)) {
      [clientClosed resolveWithResult:NSNull.null];
    }
  }];
  NSError *error = nil;
  BOOL logFromCompanion = request->source() == idb::LogRequest::Source::LogRequest_Source_COMPANION;
  id<FBLogOperation> operation = [(logFromCompanion ? [_commandExecutor tail_companion_logs:consumer] : [_target tailLog:arguments consumer:consumer]) block:&error];
  if (!operation) {
    return Status(grpc::StatusCode::INTERNAL, error.localizedDescription.UTF8String);
  }
  FBFuture<NSNull *> *completed = [FBFuture race:@[clientClosed, operation.completed]];
  [completed block:nil];
  return Status::OK;
}}

Status FBIDBServiceHandler::record(grpc::ServerContext *context, grpc::ServerReaderWriter<idb::RecordResponse, idb::RecordRequest> *stream)
{@autoreleasepool{
  idb::RecordRequest initial;
  stream->Read(&initial);
  NSError *error = nil;
  const std::string requestedFilePath = initial.start().file_path();
  NSString *filePath = requestedFilePath.length() > 0 ? nsstring_from_c_string(requestedFilePath.c_str()) : [[_target.auxillaryDirectory stringByAppendingPathComponent:@"idb_encode"] stringByAppendingPathExtension:@"mp4"];
  id<FBiOSTargetContinuation> operation = [[_target startRecordingToFile:filePath] block:&error];
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
  FBBitmapStreamEncoding encoding = start.format() == idb::VideoStreamRequest_Format_RBGA ? FBBitmapStreamEncodingBGRA : FBBitmapStreamEncodingH264;
  FBBitmapStreamConfiguration *configuration = [FBBitmapStreamConfiguration configurationWithEncoding:encoding framesPerSecond:framesPerSecond];
  id<FBBitmapStream> bitmapStream = [[_target createStreamWithConfiguration:configuration] block:&error];
  if (!stream) {
    return Status(grpc::StatusCode::INTERNAL, error.localizedDescription.UTF8String);
  }
  BOOL success = [[bitmapStream startStreaming:consumer] block:&error] != nil;
  if (success == NO) {
    return Status(grpc::StatusCode::INTERNAL, error.localizedDescription.UTF8String);
  }

  // Wait for the client to hangup or stream to stop
  FBFuture<NSNull *> *clientStopped = resolve_next_read(stream);
  [[FBFuture race:@[clientStopped, bitmapStream.completed]] block:nil];

  // Stop the streaming for real. It may have stopped already in which case this returns instantly.
  success = [[bitmapStream stopStreaming] block:&error] != nil;
  // Signal that we're done so we don't write to a dangling pointer.
  [done resolveWithResult:NSNull.null];
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
    NSString *filePath = [[_commandExecutor pull_file_path:path destination_path:nsstring_from_c_string(request->dst_path()) containerType:file_container(request->container()) ] block:&error];
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
                         queue:dispatch_queue_create("com.facebook.idb.pull", DISPATCH_QUEUE_SERIAL)
                         logger:_target.logger],
                        stream);
  }
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
  description->set_state(FBiOSTargetStateStringFromState(_target.state).lowercaseString.UTF8String);
  description->set_target_type(FBiOSTargetTypeStringsFromTargetType(_target.targetType).firstObject.lowercaseString.UTF8String);
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
  id<FBControlCoreLogger> logger = [FBControlCoreLogger compositeLoggerWithLoggers:@[
    [FBControlCoreLogger loggerToConsumer:consumer],
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
  return drain_writer([FBArchiveOperations createGzippedTarForPath:processed.path queue:queue logger:_target.logger], stream);
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
      id<FBDebugServer> debugServer = [[_commandExecutor debugserver_status] block:&error];
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
