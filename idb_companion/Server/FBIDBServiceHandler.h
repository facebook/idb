/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <idbGRPC/idb.grpc.pb.h>

@class FBIDBCommandExecutor;
@class FBIDBPortsConfiguration;

using idb::CompanionService;
using grpc::Status;
using grpc::ServerContext;

#pragma once

class FBIDBServiceHandler final : public CompanionService::Service {
private:
  FBIDBCommandExecutor *_commandExecutor;
  id<FBiOSTarget> _target;
  id<FBEventReporter> _eventReporter;
  FBFuture<FBInstalledArtifact *> *install_future(const idb::InstallRequest_Destination destination, grpc::ServerReaderWriter<idb::InstallResponse, idb::InstallRequest> *stream);

public:
  FBIDBPortsConfiguration *portsConfig;
  // Constructors
  FBIDBServiceHandler(FBIDBCommandExecutor *commandExecutor, id<FBiOSTarget> target, id<FBEventReporter> eventReporter);
  FBIDBServiceHandler(const FBIDBServiceHandler &c);

  // Handled Methods
  Status accessibility_info(ServerContext *context, const idb::AccessibilityInfoRequest *request, idb::AccessibilityInfoResponse *response);
  Status add_media(ServerContext *context,grpc::ServerReader<idb::AddMediaRequest> *reader, idb::AddMediaResponse *response);
  Status approve(ServerContext *context, const idb::ApproveRequest *request, idb::ApproveResponse *response);
  Status clear_keychain(ServerContext *context, const idb::ClearKeychainRequest *request, idb::ClearKeychainResponse *response);
  Status connect(ServerContext *context, const idb::ConnectRequest *request, idb::ConnectResponse *response);
  Status contacts_update(ServerContext *context, const idb::ContactsUpdateRequest *request, idb::ContactsUpdateResponse *response);
  Status crash_delete(ServerContext *context, const idb::CrashLogQuery *request, idb::CrashLogResponse *response);
  Status crash_list(ServerContext *context, const idb::CrashLogQuery *request, idb::CrashLogResponse *response);
  Status crash_show(ServerContext *context, const idb::CrashShowRequest *request, idb::CrashShowResponse *response);
  Status debugserver(ServerContext *context,grpc::ServerReaderWriter<idb::DebugServerResponse, idb::DebugServerRequest> *stream);
  Status describe(ServerContext *context, const idb::TargetDescriptionRequest *request, idb::TargetDescriptionResponse *response);
  Status focus(ServerContext *context, const idb::FocusRequest *request, idb::FocusResponse *response);
  Status hid(ServerContext *context,grpc::ServerReader<idb::HIDEvent> *reader, idb::HIDResponse *response);
  Status install(ServerContext *context,grpc::ServerReaderWriter<idb::InstallResponse, idb::InstallRequest> *stream);
  Status instruments_run(ServerContext *context,grpc::ServerReaderWriter<idb::InstrumentsRunResponse, idb::InstrumentsRunRequest> *stream);
  Status launch(ServerContext *context,grpc::ServerReaderWriter<idb::LaunchResponse, idb::LaunchRequest> *stream);
  Status list_apps(ServerContext *context, const idb::ListAppsRequest *request, idb::ListAppsResponse *response);
  Status log(ServerContext *context, const idb::LogRequest *request, grpc::ServerWriter<idb::LogResponse> *response);
  Status ls(ServerContext *context, const idb::LsRequest *request, idb::LsResponse *response);
  Status mkdir(ServerContext *context, const idb::MkdirRequest *request, idb::MkdirResponse *response);
  Status mv(ServerContext *context, const idb::MvRequest *request, idb::MvResponse *response);
  Status open_url(ServerContext *context, const idb::OpenUrlRequest *request, idb::OpenUrlRequest *response);
  Status pull(ServerContext *context, const idb::PullRequest *request, grpc::ServerWriter<::idb::PullResponse> *writer);
  Status push(ServerContext *context,grpc::ServerReader<idb::PushRequest> *reader, idb::PushResponse *response);
  Status record(ServerContext *context,grpc::ServerReaderWriter<idb::RecordResponse, idb::RecordRequest> *stream);
  Status rm(ServerContext *context, const idb::RmRequest *request, idb::RmResponse *response);
  Status screenshot(ServerContext *context, const idb::ScreenshotRequest *request, idb::ScreenshotResponse *response);
  Status set_location(ServerContext *context, const idb::SetLocationRequest *request, idb::SetLocationResponse *response);
  Status setting(ServerContext* context, const idb::SettingRequest* request, idb::SettingResponse* response);
  Status terminate(ServerContext *context, const idb::TerminateRequest *request, idb::TerminateResponse *response);
  Status uninstall(ServerContext *context, const idb::UninstallRequest *request, idb::UninstallResponse *response);
  Status video_stream(ServerContext* context, grpc::ServerReaderWriter<idb::VideoStreamResponse, idb::VideoStreamRequest>* stream);
  Status xctest_list_bundles(ServerContext *context, const idb::XctestListBundlesRequest *request, idb::XctestListBundlesResponse *response);
  Status xctest_list_tests(ServerContext *context, const idb::XctestListTestsRequest *request, idb::XctestListTestsResponse *response);
  Status xctest_run(ServerContext *context, const idb::XctestRunRequest *request, grpc::ServerWriter<idb::XctestRunResponse> *response);
};
