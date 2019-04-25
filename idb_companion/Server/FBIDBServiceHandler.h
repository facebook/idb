/**
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
  FBIDBPortsConfiguration *_portsConfig;
  FBFuture<NSString *> *install_future(const idb::InstallRequest_Destination destination, const idb::Payload payload, grpc::ServerReader<idb::InstallRequest> *reader);
  void description_of_target(idb::TargetDescription *description);
  FBFuture<NSString *> *install_future(const idb::InstallRequest_Destination destination, grpc::ServerReader<idb::InstallRequest> *reader);

public:
  FBIDBServiceHandler(FBIDBCommandExecutor *commandExecutor, id<FBiOSTarget> target, id<FBEventReporter> eventReporter, FBIDBPortsConfiguration *portsConfig);
  FBIDBServiceHandler(const FBIDBServiceHandler &c);
  Status accessibility_info(ServerContext *context, const idb::AccessibilityInfoRequest *request, idb::AccessibilityInfoResponse *response);
  Status add_media(::grpc::ServerContext *context, ::grpc::ServerReader<idb::AddMediaRequest> *reader, idb::AddMediaResponse *response);
  Status approve(ServerContext *context, const idb::ApproveRequest *request, idb::ApproveResponse *response);
  Status clear_keychain(ServerContext *context, const idb::ClearKeychainRequest *request, idb::ClearKeychainResponse *response);
  Status connect(::grpc::ServerContext *context, const idb::ConnectRequest *request, idb::ConnectResponse *response);
  Status contacts_update(ServerContext *context, const idb::ContactsUpdateRequest *request, idb::ContactsUpdateResponse *response);
  Status crash_delete(ServerContext *context, const idb::CrashLogQuery *request, idb::CrashLogResponse *response);
  Status crash_list(ServerContext *context, const idb::CrashLogQuery *request, idb::CrashLogResponse *response);
  Status crash_show(ServerContext *context, const idb::CrashShowRequest *request, idb::CrashShowResponse *response);
  Status pull(::grpc::ServerContext *context, const idb::PullRequest *request, grpc::ServerWriter<::idb::PullResponse> *writer);
  Status debugserver(::grpc::ServerContext* context, ::grpc::ServerReaderWriter<idb::DebugServerResponse, idb::DebugServerRequest>* stream);
  Status describe(ServerContext *context, const idb::TargetDescriptionRequest *request, idb::TargetDescriptionResponse *response);
  Status disconnect(::grpc::ServerContext *context, const idb::DisconnectRequest *request, idb::DisconnectResponse *response);
  Status focus(ServerContext *context, const idb::FocusRequest *request, idb::FocusResponse *response);
  Status hid(::grpc::ServerContext *context, ::grpc::ServerReader<idb::HIDEvent> *reader, idb::HIDResponse *response);
  Status install(ServerContext *context, grpc::ServerReader<idb::InstallRequest> *reader, idb::InstallResponse *response);
  Status instruments_run(::grpc::ServerContext* context, ::grpc::ServerReaderWriter< idb::InstrumentsRunResponse, idb::InstrumentsRunRequest>* stream);
  Status launch(::grpc::ServerContext *context, ::grpc::ServerReaderWriter<idb::LaunchResponse, idb::LaunchRequest> *stream);
  Status list_apps(::grpc::ServerContext *context, const idb::ListAppsRequest *request, idb::ListAppsResponse *response);
  Status list_targets(::grpc::ServerContext *context, const idb::ListTargetsRequest *request, idb::ListTargetsResponse *response);
  Status log(ServerContext *context, const idb::LogRequest *request, grpc::ServerWriter<idb::LogResponse> *response);
  Status ls(::grpc::ServerContext *context, const idb::LsRequest *request, idb::LsResponse *response);
  Status mkdir(::grpc::ServerContext *context, const idb::MkdirRequest *request, idb::MkdirResponse *response);
  Status mv(::grpc::ServerContext *context, const idb::MvRequest *request, idb::MvResponse *response);
  Status open_url(ServerContext *context, const idb::OpenUrlRequest *request, idb::OpenUrlRequest *response);
  Status push(::grpc::ServerContext *context, ::grpc::ServerReader<idb::PushRequest> *reader, idb::PushResponse *response);
  Status record(::grpc::ServerContext* context, ::grpc::ServerReaderWriter<idb::RecordResponse, idb::RecordRequest>* stream);
  Status rm(::grpc::ServerContext *context, const idb::RmRequest *request, idb::RmResponse *response);
  Status screenshot(ServerContext *context, const idb::ScreenshotRequest *request, idb::ScreenshotResponse *response);
  Status set_location(ServerContext *context, const idb::SetLocationRequest *request, idb::SetLocationResponse *response);
  Status terminate(ServerContext *context, const idb::TerminateRequest *request, idb::TerminateResponse *response);
  Status uninstall(ServerContext *context, const idb::UninstallRequest *request, idb::UninstallResponse *response);
  Status xctest_list_bundles(ServerContext *context, const idb::XctestListBundlesRequest *request, idb::XctestListBundlesResponse *response);
  Status xctest_list_tests(ServerContext *context, const idb::XctestListTestsRequest *request, idb::XctestListTestsResponse *response);
  Status xctest_run(ServerContext *context, const idb::XctestRunRequest *request, grpc::ServerWriter<idb::XctestRunResponse> *response);
};
