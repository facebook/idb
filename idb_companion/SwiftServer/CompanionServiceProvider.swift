/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import IDBGRPCSwift
import GRPC


final class CompanionServiceProvider: Idb_CompanionServiceAsyncProvider {
  func connect(request: Idb_ConnectRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_ConnectResponse {
    throw GRPCStatus(code: .unimplemented)
  }

  func debugserver(requestStream: GRPCAsyncRequestStream<Idb_DebugServerRequest>, responseStream: GRPCAsyncResponseStreamWriter<Idb_DebugServerResponse>, context: GRPCAsyncServerCallContext) async throws {
    throw GRPCStatus(code: .unimplemented)
  }

  func dap(requestStream: GRPCAsyncRequestStream<Idb_DapRequest>, responseStream: GRPCAsyncResponseStreamWriter<Idb_DapResponse>, context: GRPCAsyncServerCallContext) async throws {
    throw GRPCStatus(code: .unimplemented)
  }

  func describe(request: Idb_TargetDescriptionRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_TargetDescriptionResponse {
    throw GRPCStatus(code: .unimplemented)
  }

  func install(requestStream: GRPCAsyncRequestStream<Idb_InstallRequest>, responseStream: GRPCAsyncResponseStreamWriter<Idb_InstallResponse>, context: GRPCAsyncServerCallContext) async throws {
    throw GRPCStatus(code: .unimplemented)
  }

  func instruments_run(requestStream: GRPCAsyncRequestStream<Idb_InstrumentsRunRequest>, responseStream: GRPCAsyncResponseStreamWriter<Idb_InstrumentsRunResponse>, context: GRPCAsyncServerCallContext) async throws {
    throw GRPCStatus(code: .unimplemented)
  }

  func log(request: Idb_LogRequest, responseStream: GRPCAsyncResponseStreamWriter<Idb_LogResponse>, context: GRPCAsyncServerCallContext) async throws {
    throw GRPCStatus(code: .unimplemented)
  }

  func xctrace_record(requestStream: GRPCAsyncRequestStream<Idb_XctraceRecordRequest>, responseStream: GRPCAsyncResponseStreamWriter<Idb_XctraceRecordResponse>, context: GRPCAsyncServerCallContext) async throws {
    throw GRPCStatus(code: .unimplemented)
  }

  func accessibility_info(request: Idb_AccessibilityInfoRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_AccessibilityInfoResponse {
    throw GRPCStatus(code: .unimplemented)
  }

  func focus(request: Idb_FocusRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_FocusResponse {
    throw GRPCStatus(code: .unimplemented)
  }

  func hid(requestStream: GRPCAsyncRequestStream<Idb_HIDEvent>, context: GRPCAsyncServerCallContext) async throws -> Idb_HIDResponse {
    throw GRPCStatus(code: .unimplemented)
  }

  func open_url(request: Idb_OpenUrlRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_OpenUrlRequest {
    throw GRPCStatus(code: .unimplemented)
  }

  func set_location(request: Idb_SetLocationRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_SetLocationResponse {
    throw GRPCStatus(code: .unimplemented)
  }

  func send_notification(request: Idb_SendNotificationRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_SendNotificationResponse {
    throw GRPCStatus(code: .unimplemented)
  }

  func simulate_memory_warning(request: Idb_SimulateMemoryWarningRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_SimulateMemoryWarningResponse {
    throw GRPCStatus(code: .unimplemented)
  }

  func approve(request: Idb_ApproveRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_ApproveResponse {
    throw GRPCStatus(code: .unimplemented)
  }

  func clear_keychain(request: Idb_ClearKeychainRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_ClearKeychainResponse {
    throw GRPCStatus(code: .unimplemented)
  }

  func contacts_update(request: Idb_ContactsUpdateRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_ContactsUpdateResponse {
    throw GRPCStatus(code: .unimplemented)
  }

  func setting(request: Idb_SettingRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_SettingResponse {
    throw GRPCStatus(code: .unimplemented)
  }

  func get_setting(request: Idb_GetSettingRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_GetSettingResponse {
    throw GRPCStatus(code: .unimplemented)
  }

  func list_settings(request: Idb_ListSettingRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_ListSettingResponse {
    throw GRPCStatus(code: .unimplemented)
  }

  func launch(requestStream: GRPCAsyncRequestStream<Idb_LaunchRequest>, responseStream: GRPCAsyncResponseStreamWriter<Idb_LaunchResponse>, context: GRPCAsyncServerCallContext) async throws {
    throw GRPCStatus(code: .unimplemented)
  }

  func list_apps(request: Idb_ListAppsRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_ListAppsResponse {
    throw GRPCStatus(code: .unimplemented)
  }

  func terminate(request: Idb_TerminateRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_TerminateResponse {
    throw GRPCStatus(code: .unimplemented)
  }

  func uninstall(request: Idb_UninstallRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_UninstallResponse {
    throw GRPCStatus(code: .unimplemented)
  }

  func add_media(requestStream: GRPCAsyncRequestStream<Idb_AddMediaRequest>, context: GRPCAsyncServerCallContext) async throws -> Idb_AddMediaResponse {
    throw GRPCStatus(code: .unimplemented)
  }

  func record(requestStream: GRPCAsyncRequestStream<Idb_RecordRequest>, responseStream: GRPCAsyncResponseStreamWriter<Idb_RecordResponse>, context: GRPCAsyncServerCallContext) async throws {
    throw GRPCStatus(code: .unimplemented)
  }

  func screenshot(request: Idb_ScreenshotRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_ScreenshotResponse {
    throw GRPCStatus(code: .unimplemented)
  }

  func video_stream(requestStream: GRPCAsyncRequestStream<Idb_VideoStreamRequest>, responseStream: GRPCAsyncResponseStreamWriter<Idb_VideoStreamResponse>, context: GRPCAsyncServerCallContext) async throws {
    throw GRPCStatus(code: .unimplemented)
  }

  func crash_delete(request: Idb_CrashLogQuery, context: GRPCAsyncServerCallContext) async throws -> Idb_CrashLogResponse {
    throw GRPCStatus(code: .unimplemented)
  }

  func crash_list(request: Idb_CrashLogQuery, context: GRPCAsyncServerCallContext) async throws -> Idb_CrashLogResponse {
    throw GRPCStatus(code: .unimplemented)
  }

  func crash_show(request: Idb_CrashShowRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_CrashShowResponse {
    throw GRPCStatus(code: .unimplemented)
  }

  func xctest_list_bundles(request: Idb_XctestListBundlesRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_XctestListBundlesResponse {
    throw GRPCStatus(code: .unimplemented)
  }

  func xctest_list_tests(request: Idb_XctestListTestsRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_XctestListTestsResponse {
    throw GRPCStatus(code: .unimplemented)
  }

  func xctest_run(request: Idb_XctestRunRequest, responseStream: GRPCAsyncResponseStreamWriter<Idb_XctestRunResponse>, context: GRPCAsyncServerCallContext) async throws {
    throw GRPCStatus(code: .unimplemented)
  }

  func ls(request: Idb_LsRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_LsResponse {
    throw GRPCStatus(code: .unimplemented)
  }

  func mkdir(request: Idb_MkdirRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_MkdirResponse {
    throw GRPCStatus(code: .unimplemented)
  }

  func mv(request: Idb_MvRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_MvResponse {
    throw GRPCStatus(code: .unimplemented)
  }

  func rm(request: Idb_RmRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_RmResponse {
    throw GRPCStatus(code: .unimplemented)
  }

  func pull(request: Idb_PullRequest, responseStream: GRPCAsyncResponseStreamWriter<Idb_PullResponse>, context: GRPCAsyncServerCallContext) async throws {
    throw GRPCStatus(code: .unimplemented)
  }

  func push(requestStream: GRPCAsyncRequestStream<Idb_PushRequest>, context: GRPCAsyncServerCallContext) async throws -> Idb_PushResponse {
    throw GRPCStatus(code: .unimplemented)
  }

  func tail(requestStream: GRPCAsyncRequestStream<Idb_TailRequest>, responseStream: GRPCAsyncResponseStreamWriter<Idb_TailResponse>, context: GRPCAsyncServerCallContext) async throws {
    throw GRPCStatus(code: .unimplemented)
  }

}
