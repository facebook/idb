/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionLib
@preconcurrency import FBControlCore
import Foundation
import GRPC
import IDBCompanionUtilities
import IDBGRPCSwift
import NIOHPACK
import SwiftProtobuf
import XCTestBootstrap

final class CompanionServiceProvider: Idb_CompanionServiceAsyncProvider {

  private let target: FBiOSTarget
  private let commandExecutor: FBIDBCommandExecutor
  private let reporter: FBEventReporter
  private let logger: FBIDBLogger
  private let interceptorFactory: Idb_CompanionServiceServerInterceptorFactoryProtocol
  private let telemetry: CompanionTelemetry

  init(
    target: FBiOSTarget,
    commandExecutor: FBIDBCommandExecutor,
    reporter: FBEventReporter,
    logger: FBIDBLogger,
    interceptors: Idb_CompanionServiceServerInterceptorFactoryProtocol
  ) {
    self.target = target
    self.commandExecutor = commandExecutor
    self.reporter = reporter
    self.logger = logger
    self.interceptorFactory = interceptors
    self.telemetry = CompanionTelemetry(logger: logger, reporter: reporter)
  }

  var interceptors: Idb_CompanionServiceServerInterceptorFactoryProtocol? { interceptorFactory }

  private var targetLogger: FBControlCoreLogger {
    get throws {
      guard let logger = target.logger else {
        throw GRPCStatus(code: .internalError, message: "Target logger not configured")
      }
      return logger
    }
  }

  func connect(request: Idb_ConnectRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_ConnectResponse {
    return try await telemetry.unaryCall("connect", request: request) {
      try await FBTeardownContext.withAutocleanup {
        try await ConnectMethodHandler(reporter: reporter, logger: logger, target: target)
          .handle(request: request, context: context)
      }
    }
  }

  func debugserver(requestStream: GRPCAsyncRequestStream<Idb_DebugServerRequest>, responseStream: GRPCAsyncResponseStreamWriter<Idb_DebugServerResponse>, context: GRPCAsyncServerCallContext) async throws {
    try await telemetry.bidiStreaming("debugserver") {
      try await FBTeardownContext.withAutocleanup {
        try await DebugserverMethodHandler(commandExecutor: commandExecutor)
          .handle(requestStream: requestStream, responseStream: responseStream, context: context)
      }
    }
  }

  func dap(requestStream: GRPCAsyncRequestStream<Idb_DapRequest>, responseStream: GRPCAsyncResponseStreamWriter<Idb_DapResponse>, context: GRPCAsyncServerCallContext) async throws {
    try await telemetry.bidiStreaming("dap") {
      try await FBTeardownContext.withAutocleanup {
        try await DapMethodHandler(commandExecutor: commandExecutor, targetLogger: targetLogger)
          .handle(requestStream: requestStream, responseStream: responseStream, context: context)
      }
    }
  }

  func describe(request: Idb_TargetDescriptionRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_TargetDescriptionResponse {
    return try await telemetry.unaryCall("describe", request: request) {
      try await FBTeardownContext.withAutocleanup {
        try await DescribeMethodHandler(reporter: reporter, logger: logger, target: target, commandExecutor: commandExecutor)
          .handle(request: request, context: context)
      }
    }
  }

  func install(requestStream: GRPCAsyncRequestStream<Idb_InstallRequest>, responseStream: GRPCAsyncResponseStreamWriter<Idb_InstallResponse>, context: GRPCAsyncServerCallContext) async throws {
    try await telemetry.bidiStreaming("install") {
      try await FBTeardownContext.withAutocleanup {
        try await InstallMethodHandler(commandExecutor: commandExecutor, targetLogger: targetLogger)
          .handle(requestStream: requestStream, responseStream: responseStream, context: context)
      }
    }
  }

  func instruments_run(requestStream: GRPCAsyncRequestStream<Idb_InstrumentsRunRequest>, responseStream: GRPCAsyncResponseStreamWriter<Idb_InstrumentsRunResponse>, context: GRPCAsyncServerCallContext) async throws {
    try await telemetry.bidiStreaming("instruments_run") {
      try await FBTeardownContext.withAutocleanup {
        try await InstrumentsRunMethodHandler(target: target, targetLogger: targetLogger, commandExecutor: commandExecutor, logger: logger)
          .handle(requestStream: requestStream, responseStream: responseStream, context: context)
      }
    }
  }

  func log(request: Idb_LogRequest, responseStream: GRPCAsyncResponseStreamWriter<Idb_LogResponse>, context: GRPCAsyncServerCallContext) async throws {
    try await telemetry.serverStreaming("log", request: request) {
      try await FBTeardownContext.withAutocleanup {
        try await LogMethodHandler(target: target, commandExecutor: commandExecutor)
          .handle(request: request, responseStream: responseStream, context: context)
      }
    }
  }

  func xctrace_record(requestStream: GRPCAsyncRequestStream<Idb_XctraceRecordRequest>, responseStream: GRPCAsyncResponseStreamWriter<Idb_XctraceRecordResponse>, context: GRPCAsyncServerCallContext) async throws {
    try await telemetry.bidiStreaming("xctrace_record") {
      try await FBTeardownContext.withAutocleanup {
        try await XctraceRecordMethodHandler(logger: logger, targetLogger: targetLogger, target: target)
          .handle(requestStream: requestStream, responseStream: responseStream, context: context)
      }
    }
  }

  func accessibility_info(request: Idb_AccessibilityInfoRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_AccessibilityInfoResponse {
    return try await telemetry.unaryCall("accessibility_info", request: request) {
      try await FBTeardownContext.withAutocleanup {
        try await AccessibilityInfoMethodHandler(commandExecutor: commandExecutor)
          .handle(request: request, context: context)
      }
    }
  }

  func focus(request: Idb_FocusRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_FocusResponse {
    return try await telemetry.unaryCall("focus", request: request) {
      try await FBTeardownContext.withAutocleanup {
        try await FocusMethodHandler(commandExecutor: commandExecutor)
          .handle(request: request, context: context)
      }
    }
  }

  func hid(requestStream: GRPCAsyncRequestStream<Idb_HIDEvent>, context: GRPCAsyncServerCallContext) async throws -> Idb_HIDResponse {
    return try await telemetry.clientStreaming("hid") {
      try await FBTeardownContext.withAutocleanup {
        try await HidMethodHandler(commandExecutor: commandExecutor)
          .handle(requestStream: requestStream, context: context)
      }
    }
  }

  func open_url(request: Idb_OpenUrlRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_OpenUrlRequest {
    return try await telemetry.unaryCall("open_url", request: request) {
      try await FBTeardownContext.withAutocleanup {
        try await OpenUrlMethodHandler(commandExecutor: commandExecutor)
          .handle(request: request, context: context)
      }
    }
  }

  func set_location(request: Idb_SetLocationRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_SetLocationResponse {
    return try await telemetry.unaryCall("set_location", request: request) {
      try await FBTeardownContext.withAutocleanup {
        try await SetLocationMethodHandler(commandExecutor: commandExecutor)
          .handle(request: request, context: context)
      }
    }
  }

  func send_notification(request: Idb_SendNotificationRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_SendNotificationResponse {
    return try await telemetry.unaryCall("send_notification", request: request) {
      try await FBTeardownContext.withAutocleanup {
        try await SendNotificationMethodHandler(commandExecutor: commandExecutor)
          .handle(request: request, context: context)
      }
    }
  }

  func simulate_memory_warning(request: Idb_SimulateMemoryWarningRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_SimulateMemoryWarningResponse {
    return try await telemetry.unaryCall("simulate_memory_warning", request: request) {
      try await FBTeardownContext.withAutocleanup {
        try await SimulateMemoryWarningMethodHandler(commandExecutor: commandExecutor)
          .handle(request: request, context: context)
      }
    }
  }

  func approve(request: Idb_ApproveRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_ApproveResponse {
    return try await telemetry.unaryCall("approve", request: request) {
      try await FBTeardownContext.withAutocleanup {
        try await ApproveMethodHandler(commandExecutor: commandExecutor)
          .handle(request: request, context: context)
      }
    }
  }

  func revoke(request: Idb_RevokeRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_RevokeResponse {
    return try await telemetry.unaryCall("revoke", request: request) {
      try await FBTeardownContext.withAutocleanup {
        try await RevokeMethodHandler(commandExecutor: commandExecutor)
          .handle(request: request, context: context)
      }
    }
  }

  func clear_keychain(request: Idb_ClearKeychainRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_ClearKeychainResponse {
    return try await telemetry.unaryCall("clear_keychain", request: request) {
      try await FBTeardownContext.withAutocleanup {
        try await ClearKeychainMethodHandler(commandExecutor: commandExecutor)
          .handle(request: request, context: context)
      }
    }
  }

  func contacts_update(request: Idb_ContactsUpdateRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_ContactsUpdateResponse {
    return try await telemetry.unaryCall("contacts_update", request: request) {
      try await FBTeardownContext.withAutocleanup {
        try await ContactsUpdateMethodHandler(commandExecutor: commandExecutor)
          .handle(request: request, context: context)
      }
    }
  }

  func contacts_clear(request: Idb_ContactsClearRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_ContactsClearResponse {
    return try await telemetry.unaryCall("contacts_clear", request: request) {
      try await FBTeardownContext.withAutocleanup {
        try await commandExecutor.clear_contacts()
        return Idb_ContactsClearResponse()
      }
    }
  }

  func photos_clear(request: Idb_PhotosClearRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_PhotosClearResponse {
    return try await telemetry.unaryCall("photos_clear", request: request) {
      try await FBTeardownContext.withAutocleanup {
        try await commandExecutor.clear_photos()
        return Idb_PhotosClearResponse()
      }
    }
  }

  func setting(request: Idb_SettingRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_SettingResponse {
    return try await telemetry.unaryCall("setting", request: request) {
      try await FBTeardownContext.withAutocleanup {
        try await SettingMethodHandler(commandExecutor: commandExecutor)
          .handle(request: request, context: context)
      }
    }
  }

  func get_setting(request: Idb_GetSettingRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_GetSettingResponse {
    return try await telemetry.unaryCall("get_setting", request: request) {
      try await FBTeardownContext.withAutocleanup {
        try await GetSettingMethodHandler(commandExecutor: commandExecutor)
          .handle(request: request, context: context)
      }
    }
  }

  func list_settings(request: Idb_ListSettingRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_ListSettingResponse {
    return try await telemetry.unaryCall("list_settings", request: request) {
      try await FBTeardownContext.withAutocleanup {
        try await ListSettingsMethodHandler(commandExecutor: commandExecutor)
          .handle(request: request, context: context)
      }
    }
  }

  func launch(requestStream: GRPCAsyncRequestStream<Idb_LaunchRequest>, responseStream: GRPCAsyncResponseStreamWriter<Idb_LaunchResponse>, context: GRPCAsyncServerCallContext) async throws {
    try await telemetry.bidiStreaming("launch") {
      try await FBTeardownContext.withAutocleanup {
        try await LaunchMethodHandler(commandExecutor: commandExecutor)
          .handle(requestStream: requestStream, responseStream: responseStream, context: context)
      }
    }
  }

  func list_apps(request: Idb_ListAppsRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_ListAppsResponse {
    return try await telemetry.unaryCall("list_apps", request: request) {
      try await FBTeardownContext.withAutocleanup {
        try await ListAppsMethodHandler(commandExecutor: commandExecutor)
          .handle(request: request, context: context)
      }
    }
  }

  func terminate(request: Idb_TerminateRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_TerminateResponse {
    return try await telemetry.unaryCall("terminate", request: request) {
      try await FBTeardownContext.withAutocleanup {
        try await TerminateMethodHandler(commandExecutor: commandExecutor)
          .handle(request: request, context: context)
      }
    }
  }

  func uninstall(request: Idb_UninstallRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_UninstallResponse {
    return try await telemetry.unaryCall("uninstall", request: request) {
      try await FBTeardownContext.withAutocleanup {
        try await UninstallMethodHandler(commandExecutor: commandExecutor)
          .handle(request: request, context: context)
      }
    }
  }

  func add_media(requestStream: GRPCAsyncRequestStream<Idb_AddMediaRequest>, context: GRPCAsyncServerCallContext) async throws -> Idb_AddMediaResponse {
    return try await telemetry.clientStreaming("add_media") {
      try await FBTeardownContext.withAutocleanup {
        try await AddMediaMethodHandler(commandExecutor: commandExecutor)
          .handle(requestStream: requestStream, context: context)
      }
    }
  }

  func record(requestStream: GRPCAsyncRequestStream<Idb_RecordRequest>, responseStream: GRPCAsyncResponseStreamWriter<Idb_RecordResponse>, context: GRPCAsyncServerCallContext) async throws {
    try await telemetry.bidiStreaming("record") {
      try await FBTeardownContext.withAutocleanup {
        try await RecordMethodHandler(target: target, targetLogger: targetLogger)
          .handle(requestStream: requestStream, responseStream: responseStream, context: context)
      }
    }
  }

  func screenshot(request: Idb_ScreenshotRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_ScreenshotResponse {
    return try await telemetry.unaryCall("screenshot", request: request) {
      try await FBTeardownContext.withAutocleanup {
        try await ScreenshotMethodHandler(commandExecutor: commandExecutor)
          .handle(request: request, context: context)
      }
    }
  }

  func video_stream(requestStream: GRPCAsyncRequestStream<Idb_VideoStreamRequest>, responseStream: GRPCAsyncResponseStreamWriter<Idb_VideoStreamResponse>, context: GRPCAsyncServerCallContext) async throws {
    try await telemetry.bidiStreaming("video_stream") {
      try await FBTeardownContext.withAutocleanup {
        try await VideoStreamMethodHandler(target: target, targetLogger: targetLogger, commandExecutor: commandExecutor)
          .handle(requestStream: requestStream, responseStream: responseStream, context: context)
      }
    }
  }

  func crash_delete(request: Idb_CrashLogQuery, context: GRPCAsyncServerCallContext) async throws -> Idb_CrashLogResponse {
    return try await telemetry.unaryCall("crash_delete", request: request) {
      try await FBTeardownContext.withAutocleanup {
        try await CrashDeleteMethodHandler(commandExecutor: commandExecutor)
          .handle(request: request, context: context)
      }
    }
  }

  func crash_list(request: Idb_CrashLogQuery, context: GRPCAsyncServerCallContext) async throws -> Idb_CrashLogResponse {
    return try await telemetry.unaryCall("crash_list", request: request) {
      try await FBTeardownContext.withAutocleanup {
        try await CrashListMethodHandler(commandExecutor: commandExecutor)
          .handle(request: request, context: context)
      }
    }
  }

  func crash_show(request: Idb_CrashShowRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_CrashShowResponse {
    return try await telemetry.unaryCall("crash_show", request: request) {
      try await FBTeardownContext.withAutocleanup {
        try await CrashShowMethodHandler(commandExecutor: commandExecutor)
          .handle(request: request, context: context)
      }
    }
  }

  func xctest_list_bundles(request: Idb_XctestListBundlesRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_XctestListBundlesResponse {
    return try await telemetry.unaryCall("xctest_list_bundles", request: request) {
      try await FBTeardownContext.withAutocleanup {
        try await XCTestListBundlesMethodHandler(commandExecutor: commandExecutor)
          .handle(request: request, context: context)
      }
    }
  }

  func xctest_list_tests(request: Idb_XctestListTestsRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_XctestListTestsResponse {
    return try await telemetry.unaryCall("xctest_list_tests", request: request) {
      try await FBTeardownContext.withAutocleanup {
        try await XCTestListTestsMethodHandler(commandExecutor: commandExecutor)
          .handle(request: request, context: context)
      }
    }
  }

  func xctest_run(request: Idb_XctestRunRequest, responseStream: GRPCAsyncResponseStreamWriter<Idb_XctestRunResponse>, context: GRPCAsyncServerCallContext) async throws {
    try await telemetry.serverStreaming("xctest_run", request: request) {
      try await FBTeardownContext.withAutocleanup {
        try await XCTestRunMethodHandler(target: target, commandExecutor: commandExecutor, reporter: reporter, targetLogger: targetLogger, logger: logger)
          .handle(request: request, responseStream: responseStream, context: context)
      }
    }
  }

  func ls(request: Idb_LsRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_LsResponse {
    return try await telemetry.unaryCall("ls", request: request) {
      try await FBTeardownContext.withAutocleanup {
        try await LsMethodHandler(commandExecutor: commandExecutor)
          .handle(request: request, context: context)
      }
    }
  }

  func mkdir(request: Idb_MkdirRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_MkdirResponse {
    return try await telemetry.unaryCall("mkdir", request: request) {
      try await FBTeardownContext.withAutocleanup {
        try await MkdirMethodHandler(commandExecutor: commandExecutor)
          .handle(request: request, context: context)
      }
    }
  }

  func mv(request: Idb_MvRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_MvResponse {
    return try await telemetry.unaryCall("mv", request: request) {
      try await FBTeardownContext.withAutocleanup {
        try await MvMethodHandler(commandExecutor: commandExecutor)
          .handle(request: request, context: context)
      }
    }
  }

  func rm(request: Idb_RmRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_RmResponse {
    return try await telemetry.unaryCall("rm", request: request) {
      try await FBTeardownContext.withAutocleanup {
        try await RmMethodHandler(commandExecutor: commandExecutor)
          .handle(request: request, context: context)
      }
    }
  }

  func pull(request: Idb_PullRequest, responseStream: GRPCAsyncResponseStreamWriter<Idb_PullResponse>, context: GRPCAsyncServerCallContext) async throws {
    try await telemetry.serverStreaming("pull", request: request) {
      try await FBTeardownContext.withAutocleanup {
        try await PullMethodHandler(target: target, commandExecutor: commandExecutor)
          .handle(request: request, responseStream: responseStream, context: context)
      }
    }
  }

  func push(requestStream: GRPCAsyncRequestStream<Idb_PushRequest>, context: GRPCAsyncServerCallContext) async throws -> Idb_PushResponse {
    return try await telemetry.clientStreaming("push") {
      try await FBTeardownContext.withAutocleanup {
        try await PushMethodHandler(target: target, commandExecutor: commandExecutor)
          .handle(requestStream: requestStream, context: context)
      }
    }
  }

  func tail(requestStream: GRPCAsyncRequestStream<Idb_TailRequest>, responseStream: GRPCAsyncResponseStreamWriter<Idb_TailResponse>, context: GRPCAsyncServerCallContext) async throws {
    try await telemetry.bidiStreaming("tail") {
      try await FBTeardownContext.withAutocleanup {
        try await TailMethodHandler(commandExecutor: commandExecutor)
          .handle(requestStream: requestStream, responseStream: responseStream, context: context)
      }
    }
  }
}
