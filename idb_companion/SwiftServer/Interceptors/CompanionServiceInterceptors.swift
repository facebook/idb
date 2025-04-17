/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionLib
import Foundation
import GRPC
import IDBGRPCSwift

// By design in grpc-swift we should provide interceptor for each method separately.
// This gives us ability to precicely control which interceptors will be used for concrete method from one side,
// but make it too explicit from other side.
final class CompanionServiceInterceptors: Idb_CompanionServiceServerInterceptorFactoryProtocol {

  private let logger: FBIDBLogger
  private let reporter: FBEventReporter

  init(logger: FBIDBLogger, reporter: FBEventReporter) {
    self.logger = logger
    self.reporter = reporter
  }

  private func commonInterceptors<Request, Response>() -> [ServerInterceptor<Request, Response>] {
    [
      MethodInfoSetterInterceptor(),
      LoggingInterceptor(logger: logger, reporter: reporter),
    ]
  }

  func makeconnectInterceptors() -> [ServerInterceptor<Idb_ConnectRequest, Idb_ConnectResponse>] {
    commonInterceptors()
  }

  func makedebugserverInterceptors() -> [ServerInterceptor<Idb_DebugServerRequest, Idb_DebugServerResponse>] {
    commonInterceptors()
  }

  func makedapInterceptors() -> [ServerInterceptor<Idb_DapRequest, Idb_DapResponse>] {
    commonInterceptors()
  }

  func makedescribeInterceptors() -> [ServerInterceptor<Idb_TargetDescriptionRequest, Idb_TargetDescriptionResponse>] {
    commonInterceptors()
  }

  func makeinstallInterceptors() -> [ServerInterceptor<Idb_InstallRequest, Idb_InstallResponse>] {
    commonInterceptors()
  }

  func makeinstruments_runInterceptors() -> [ServerInterceptor<Idb_InstrumentsRunRequest, Idb_InstrumentsRunResponse>] {
    commonInterceptors()
  }

  func makelogInterceptors() -> [ServerInterceptor<Idb_LogRequest, Idb_LogResponse>] {
    commonInterceptors()
  }

  func makexctrace_recordInterceptors() -> [ServerInterceptor<Idb_XctraceRecordRequest, Idb_XctraceRecordResponse>] {
    commonInterceptors()
  }

  func makeaccessibility_infoInterceptors() -> [ServerInterceptor<Idb_AccessibilityInfoRequest, Idb_AccessibilityInfoResponse>] {
    commonInterceptors()
  }

  func makefocusInterceptors() -> [ServerInterceptor<Idb_FocusRequest, Idb_FocusResponse>] {
    commonInterceptors()
  }

  func makehidInterceptors() -> [ServerInterceptor<Idb_HIDEvent, Idb_HIDResponse>] {
    commonInterceptors()
  }

  func makeopen_urlInterceptors() -> [ServerInterceptor<Idb_OpenUrlRequest, Idb_OpenUrlRequest>] {
    commonInterceptors()
  }

  func makeset_locationInterceptors() -> [ServerInterceptor<Idb_SetLocationRequest, Idb_SetLocationResponse>] {
    commonInterceptors()
  }

  func makesend_notificationInterceptors() -> [ServerInterceptor<Idb_SendNotificationRequest, Idb_SendNotificationResponse>] {
    commonInterceptors()
  }

  func makesimulate_memory_warningInterceptors() -> [ServerInterceptor<Idb_SimulateMemoryWarningRequest, Idb_SimulateMemoryWarningResponse>] {
    commonInterceptors()
  }

  func makeapproveInterceptors() -> [ServerInterceptor<Idb_ApproveRequest, Idb_ApproveResponse>] {
    commonInterceptors()
  }

  func makerevokeInterceptors() -> [ServerInterceptor<Idb_RevokeRequest, Idb_RevokeResponse>] {
    commonInterceptors()
  }

  func makeclear_keychainInterceptors() -> [ServerInterceptor<Idb_ClearKeychainRequest, Idb_ClearKeychainResponse>] {
    commonInterceptors()
  }

  func makecontacts_updateInterceptors() -> [ServerInterceptor<Idb_ContactsUpdateRequest, Idb_ContactsUpdateResponse>] {
    commonInterceptors()
  }

  func makesettingInterceptors() -> [ServerInterceptor<Idb_SettingRequest, Idb_SettingResponse>] {
    commonInterceptors()
  }

  func makeget_settingInterceptors() -> [ServerInterceptor<Idb_GetSettingRequest, Idb_GetSettingResponse>] {
    commonInterceptors()
  }

  func makelist_settingsInterceptors() -> [ServerInterceptor<Idb_ListSettingRequest, Idb_ListSettingResponse>] {
    commonInterceptors()
  }

  func makelaunchInterceptors() -> [ServerInterceptor<Idb_LaunchRequest, Idb_LaunchResponse>] {
    commonInterceptors()
  }

  func makelist_appsInterceptors() -> [ServerInterceptor<Idb_ListAppsRequest, Idb_ListAppsResponse>] {
    commonInterceptors()
  }

  func maketerminateInterceptors() -> [ServerInterceptor<Idb_TerminateRequest, Idb_TerminateResponse>] {
    commonInterceptors()
  }

  func makeuninstallInterceptors() -> [ServerInterceptor<Idb_UninstallRequest, Idb_UninstallResponse>] {
    commonInterceptors()
  }

  func makeadd_mediaInterceptors() -> [ServerInterceptor<Idb_AddMediaRequest, Idb_AddMediaResponse>] {
    commonInterceptors()
  }

  func makerecordInterceptors() -> [ServerInterceptor<Idb_RecordRequest, Idb_RecordResponse>] {
    commonInterceptors()
  }

  func makescreenshotInterceptors() -> [ServerInterceptor<Idb_ScreenshotRequest, Idb_ScreenshotResponse>] {
    commonInterceptors()
  }

  func makevideo_streamInterceptors() -> [ServerInterceptor<Idb_VideoStreamRequest, Idb_VideoStreamResponse>] {
    commonInterceptors()
  }

  func makecrash_deleteInterceptors() -> [ServerInterceptor<Idb_CrashLogQuery, Idb_CrashLogResponse>] {
    commonInterceptors()
  }

  func makecrash_listInterceptors() -> [ServerInterceptor<Idb_CrashLogQuery, Idb_CrashLogResponse>] {
    commonInterceptors()
  }

  func makecrash_showInterceptors() -> [ServerInterceptor<Idb_CrashShowRequest, Idb_CrashShowResponse>] {
    commonInterceptors()
  }

  func makexctest_list_bundlesInterceptors() -> [ServerInterceptor<Idb_XctestListBundlesRequest, Idb_XctestListBundlesResponse>] {
    commonInterceptors()
  }

  func makexctest_list_testsInterceptors() -> [ServerInterceptor<Idb_XctestListTestsRequest, Idb_XctestListTestsResponse>] {
    commonInterceptors()
  }

  func makexctest_runInterceptors() -> [ServerInterceptor<Idb_XctestRunRequest, Idb_XctestRunResponse>] {
    commonInterceptors()
  }

  func makelsInterceptors() -> [ServerInterceptor<Idb_LsRequest, Idb_LsResponse>] {
    commonInterceptors()
  }

  func makemkdirInterceptors() -> [ServerInterceptor<Idb_MkdirRequest, Idb_MkdirResponse>] {
    commonInterceptors()
  }

  func makemvInterceptors() -> [ServerInterceptor<Idb_MvRequest, Idb_MvResponse>] {
    commonInterceptors()
  }

  func makermInterceptors() -> [ServerInterceptor<Idb_RmRequest, Idb_RmResponse>] {
    commonInterceptors()
  }

  func makepullInterceptors() -> [ServerInterceptor<Idb_PullRequest, Idb_PullResponse>] {
    commonInterceptors()
  }

  func makepushInterceptors() -> [ServerInterceptor<Idb_PushRequest, Idb_PushResponse>] {
    commonInterceptors()
  }

  func maketailInterceptors() -> [ServerInterceptor<Idb_TailRequest, Idb_TailResponse>] {
    commonInterceptors()
  }
}
