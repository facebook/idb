/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionUtilities
@preconcurrency import FBControlCore
import Foundation
import GRPCCore
import IDBGRPCSwift
import SwiftProtobuf
import XCTestBootstrap

final class CompanionServiceProvider: Idb_CompanionService.SimpleServiceProtocol, @unchecked Sendable {

  private let target: any Target
  private let commandExecutor: IDBCommandExecutor
  private let reporter: EventReporter
  private let logger: IDBLogger
  private let telemetry: CompanionTelemetry
  /// Tracks in-flight calls so the companion can shut down when idle.
  private let idleMonitor: IdleMonitor?
  /// Owns the single in-progress REPL screen recording. Held here, at target scope,
  /// because a recording can outlive the `repl` stream that started it (the app
  /// context keeps the app -- and the recording -- alive across reconnects).
  private let replRecordingCoordinator: ReplRecordingCoordinator

  init(
    target: any Target,
    commandExecutor: IDBCommandExecutor,
    reporter: EventReporter,
    logger: IDBLogger,
    idleMonitor: IdleMonitor? = nil
  ) {
    self.target = target
    self.commandExecutor = commandExecutor
    self.reporter = reporter
    self.logger = logger
    self.telemetry = CompanionTelemetry(logger: logger, reporter: reporter)
    self.idleMonitor = idleMonitor
    self.replRecordingCoordinator = ReplRecordingCoordinator(
      auxillaryDirectory: commandExecutor.auxillaryDirectory, logger: target.logger)
  }

  /// Also counts the call as in-flight for `idleMonitor` (a no-op when idle shutdown is disabled),
  /// and maps whatever the handler throws to the status the client sees.
  ///
  /// The generated service runs a streaming handler inside the response producer, after the
  /// interceptor chain has already returned, so an interceptor cannot map its errors; the
  /// mapping has to happen here, around the handler itself.
  private func tracked<R>(_ body: () async throws -> R) async throws -> R {
    do {
      guard let idleMonitor else {
        return try await body()
      }
      return try await idleMonitor.tracking(body)
    } catch {
      throw ErrorMapping.rpcError(from: error)
    }
  }

  private func trackedUnaryCall<Request, Response>(_ method: String, request: Request, summarize: ((Response) -> String)? = nil, body: () async throws -> Response) async throws -> Response {
    try await tracked { try await telemetry.unaryCall(method, request: request, summarize: summarize, body: body) }
  }

  private func trackedClientStreaming<Response>(_ method: String, body: () async throws -> Response) async throws -> Response {
    try await tracked { try await telemetry.clientStreaming(method, body: body) }
  }

  private func trackedServerStreaming<Request>(_ method: String, request: Request, body: () async throws -> Void) async throws {
    try await tracked { try await telemetry.serverStreaming(method, request: request, body: body) }
  }

  private func trackedBidiStreaming(_ method: String, body: () async throws -> Void) async throws {
    try await tracked { try await telemetry.bidiStreaming(method, body: body) }
  }

  private var targetLogger: ControlCoreLogger {
    target.logger
  }

  func connect(request: Idb_ConnectRequest, context: ServerContext) async throws -> Idb_ConnectResponse {
    return try await trackedUnaryCall("connect", request: request) {
      try await TeardownContext.withAutocleanup {
        try await ConnectMethodHandler(reporter: reporter, logger: logger, target: target)
          .handle(request: request, context: context)
      }
    }
  }

  func debugserver(request: RPCAsyncSequence<Idb_DebugServerRequest, any Error>, response: RPCWriter<Idb_DebugServerResponse>, context: ServerContext) async throws {
    let reader = RequestStreamReader(request)
    try await trackedBidiStreaming("debugserver") {
      try await TeardownContext.withAutocleanup {
        try await DebugserverMethodHandler(commandExecutor: commandExecutor)
          .handle(requestStream: reader, responseStream: response, context: context)
      }
    }
  }

  func dap(request: RPCAsyncSequence<Idb_DapRequest, any Error>, response: RPCWriter<Idb_DapResponse>, context: ServerContext) async throws {
    let reader = RequestStreamReader(request)
    try await trackedBidiStreaming("dap") {
      try await TeardownContext.withAutocleanup {
        try await DapMethodHandler(commandExecutor: commandExecutor, targetLogger: targetLogger)
          .handle(requestStream: reader, responseStream: response, context: context)
      }
    }
  }

  func describe(request: Idb_TargetDescriptionRequest, context: ServerContext) async throws -> Idb_TargetDescriptionResponse {
    return try await trackedUnaryCall("describe", request: request) {
      try await TeardownContext.withAutocleanup {
        try await DescribeMethodHandler(reporter: reporter, logger: logger, target: target, commandExecutor: commandExecutor)
          .handle(request: request, context: context)
      }
    }
  }

  func install(request: RPCAsyncSequence<Idb_InstallRequest, any Error>, response: RPCWriter<Idb_InstallResponse>, context: ServerContext) async throws {
    let reader = RequestStreamReader(request)
    try await trackedBidiStreaming("install") {
      try await TeardownContext.withAutocleanup {
        try await InstallMethodHandler(commandExecutor: commandExecutor, targetLogger: targetLogger)
          .handle(requestStream: reader, responseStream: response, context: context)
      }
    }
  }

  func instruments_run(request: RPCAsyncSequence<Idb_InstrumentsRunRequest, any Error>, response: RPCWriter<Idb_InstrumentsRunResponse>, context: ServerContext) async throws {
    let reader = RequestStreamReader(request)
    try await trackedBidiStreaming("instruments_run") {
      try await TeardownContext.withAutocleanup {
        try await InstrumentsRunMethodHandler(target: target, targetLogger: targetLogger, commandExecutor: commandExecutor, logger: logger)
          .handle(requestStream: reader, responseStream: response, context: context)
      }
    }
  }

  func log(request: Idb_LogRequest, response: RPCWriter<Idb_LogResponse>, context: ServerContext) async throws {
    try await trackedServerStreaming("log", request: request) {
      try await TeardownContext.withAutocleanup {
        try await LogMethodHandler(target: target, commandExecutor: commandExecutor)
          .handle(request: request, responseStream: response, context: context)
      }
    }
  }

  func xctrace_record(request: RPCAsyncSequence<Idb_XctraceRecordRequest, any Error>, response: RPCWriter<Idb_XctraceRecordResponse>, context: ServerContext) async throws {
    let reader = RequestStreamReader(request)
    try await trackedBidiStreaming("xctrace_record") {
      try await TeardownContext.withAutocleanup {
        try await XctraceRecordMethodHandler(logger: logger, targetLogger: targetLogger, target: target)
          .handle(requestStream: reader, responseStream: response, context: context)
      }
    }
  }

  func accessibility_info(request: Idb_AccessibilityInfoRequest, context: ServerContext) async throws -> Idb_AccessibilityInfoResponse {
    return try await trackedUnaryCall("accessibility_info", request: request) {
      try await TeardownContext.withAutocleanup {
        try await AccessibilityInfoMethodHandler(commandExecutor: commandExecutor)
          .handle(request: request, context: context)
      }
    }
  }

  func accessibility_action(request: Idb_AccessibilityActionRequest, context: ServerContext) async throws -> Idb_AccessibilityActionResponse {
    return try await trackedUnaryCall("accessibility_action", request: request) {
      try await TeardownContext.withAutocleanup {
        try await AccessibilityActionMethodHandler(commandExecutor: commandExecutor)
          .handle(request: request, context: context)
      }
    }
  }

  func focus(request: Idb_FocusRequest, context: ServerContext) async throws -> Idb_FocusResponse {
    return try await trackedUnaryCall("focus", request: request) {
      try await TeardownContext.withAutocleanup {
        try await FocusMethodHandler(commandExecutor: commandExecutor)
          .handle(request: request, context: context)
      }
    }
  }

  func hid(request: RPCAsyncSequence<Idb_HIDEvent, any Error>, context: ServerContext) async throws -> Idb_HIDResponse {
    let reader = RequestStreamReader(request)
    return try await trackedClientStreaming("hid") {
      try await TeardownContext.withAutocleanup {
        try await HidMethodHandler(commandExecutor: commandExecutor)
          .handle(requestStream: reader, context: context)
      }
    }
  }

  func open_url(request: Idb_OpenUrlRequest, context: ServerContext) async throws -> Idb_OpenUrlRequest {
    return try await trackedUnaryCall("open_url", request: request) {
      try await TeardownContext.withAutocleanup {
        try await OpenUrlMethodHandler(commandExecutor: commandExecutor)
          .handle(request: request, context: context)
      }
    }
  }

  func set_location(request: Idb_SetLocationRequest, context: ServerContext) async throws -> Idb_SetLocationResponse {
    return try await trackedUnaryCall("set_location", request: request) {
      try await TeardownContext.withAutocleanup {
        try await SetLocationMethodHandler(commandExecutor: commandExecutor)
          .handle(request: request, context: context)
      }
    }
  }

  func delivered_notifications(request: Idb_DeliveredNotificationsRequest, context: ServerContext) async throws -> Idb_DeliveredNotificationsResponse {
    return try await trackedUnaryCall("delivered_notifications", request: request) {
      try await TeardownContext.withAutocleanup {
        try await DeliveredNotificationsMethodHandler(commandExecutor: commandExecutor)
          .handle(request: request, context: context)
      }
    }
  }

  func send_notification(request: Idb_SendNotificationRequest, context: ServerContext) async throws -> Idb_SendNotificationResponse {
    return try await trackedUnaryCall("send_notification", request: request) {
      try await TeardownContext.withAutocleanup {
        try await SendNotificationMethodHandler(commandExecutor: commandExecutor)
          .handle(request: request, context: context)
      }
    }
  }

  func simulate_memory_warning(request: Idb_SimulateMemoryWarningRequest, context: ServerContext) async throws -> Idb_SimulateMemoryWarningResponse {
    return try await trackedUnaryCall("simulate_memory_warning", request: request) {
      try await TeardownContext.withAutocleanup {
        try await SimulateMemoryWarningMethodHandler(commandExecutor: commandExecutor)
          .handle(request: request, context: context)
      }
    }
  }

  func approve(request: Idb_ApproveRequest, context: ServerContext) async throws -> Idb_ApproveResponse {
    return try await trackedUnaryCall("approve", request: request) {
      try await TeardownContext.withAutocleanup {
        try await ApproveMethodHandler(commandExecutor: commandExecutor)
          .handle(request: request, context: context)
      }
    }
  }

  func revoke(request: Idb_RevokeRequest, context: ServerContext) async throws -> Idb_RevokeResponse {
    return try await trackedUnaryCall("revoke", request: request) {
      try await TeardownContext.withAutocleanup {
        try await RevokeMethodHandler(commandExecutor: commandExecutor)
          .handle(request: request, context: context)
      }
    }
  }

  func clear_keychain(request: Idb_ClearKeychainRequest, context: ServerContext) async throws -> Idb_ClearKeychainResponse {
    return try await trackedUnaryCall("clear_keychain", request: request) {
      try await TeardownContext.withAutocleanup {
        try await ClearKeychainMethodHandler(commandExecutor: commandExecutor)
          .handle(request: request, context: context)
      }
    }
  }

  func contacts_update(request: Idb_ContactsUpdateRequest, context: ServerContext) async throws -> Idb_ContactsUpdateResponse {
    return try await trackedUnaryCall("contacts_update", request: request) {
      try await TeardownContext.withAutocleanup {
        try await ContactsUpdateMethodHandler(commandExecutor: commandExecutor)
          .handle(request: request, context: context)
      }
    }
  }

  func contacts_clear(request: Idb_ContactsClearRequest, context: ServerContext) async throws -> Idb_ContactsClearResponse {
    return try await trackedUnaryCall("contacts_clear", request: request) {
      try await TeardownContext.withAutocleanup {
        try await commandExecutor.clear_contacts()
        return Idb_ContactsClearResponse()
      }
    }
  }

  func photos_clear(request: Idb_PhotosClearRequest, context: ServerContext) async throws -> Idb_PhotosClearResponse {
    return try await trackedUnaryCall("photos_clear", request: request) {
      try await TeardownContext.withAutocleanup {
        try await commandExecutor.clear_photos()
        return Idb_PhotosClearResponse()
      }
    }
  }

  func setting(request: Idb_SettingRequest, context: ServerContext) async throws -> Idb_SettingResponse {
    return try await trackedUnaryCall("setting", request: request) {
      try await TeardownContext.withAutocleanup {
        try await SettingMethodHandler(commandExecutor: commandExecutor)
          .handle(request: request, context: context)
      }
    }
  }

  func get_setting(request: Idb_GetSettingRequest, context: ServerContext) async throws -> Idb_GetSettingResponse {
    return try await trackedUnaryCall("get_setting", request: request) {
      try await TeardownContext.withAutocleanup {
        try await GetSettingMethodHandler(commandExecutor: commandExecutor)
          .handle(request: request, context: context)
      }
    }
  }

  func list_settings(request: Idb_ListSettingRequest, context: ServerContext) async throws -> Idb_ListSettingResponse {
    return try await trackedUnaryCall("list_settings", request: request) {
      try await TeardownContext.withAutocleanup {
        try await ListSettingsMethodHandler(commandExecutor: commandExecutor)
          .handle(request: request, context: context)
      }
    }
  }

  func launch(request: RPCAsyncSequence<Idb_LaunchRequest, any Error>, response: RPCWriter<Idb_LaunchResponse>, context: ServerContext) async throws {
    let reader = RequestStreamReader(request)
    try await trackedBidiStreaming("launch") {
      try await TeardownContext.withAutocleanup {
        try await LaunchMethodHandler(commandExecutor: commandExecutor)
          .handle(requestStream: reader, responseStream: response, context: context)
      }
    }
  }

  func list_apps(request: Idb_ListAppsRequest, context: ServerContext) async throws -> Idb_ListAppsResponse {
    return try await trackedUnaryCall("list_apps", request: request) {
      try await TeardownContext.withAutocleanup {
        try await ListAppsMethodHandler(commandExecutor: commandExecutor)
          .handle(request: request, context: context)
      }
    }
  }

  func terminate(request: Idb_TerminateRequest, context: ServerContext) async throws -> Idb_TerminateResponse {
    return try await trackedUnaryCall("terminate", request: request) {
      try await TeardownContext.withAutocleanup {
        try await TerminateMethodHandler(commandExecutor: commandExecutor)
          .handle(request: request, context: context)
      }
    }
  }

  func uninstall(request: Idb_UninstallRequest, context: ServerContext) async throws -> Idb_UninstallResponse {
    return try await trackedUnaryCall("uninstall", request: request) {
      try await TeardownContext.withAutocleanup {
        try await UninstallMethodHandler(commandExecutor: commandExecutor)
          .handle(request: request, context: context)
      }
    }
  }

  func add_media(request: RPCAsyncSequence<Idb_AddMediaRequest, any Error>, context: ServerContext) async throws -> Idb_AddMediaResponse {
    let reader = RequestStreamReader(request)
    return try await trackedClientStreaming("add_media") {
      try await TeardownContext.withAutocleanup {
        try await AddMediaMethodHandler(commandExecutor: commandExecutor)
          .handle(requestStream: reader, context: context)
      }
    }
  }

  func record(request: RPCAsyncSequence<Idb_RecordRequest, any Error>, response: RPCWriter<Idb_RecordResponse>, context: ServerContext) async throws {
    let reader = RequestStreamReader(request)
    try await trackedBidiStreaming("record") {
      try await TeardownContext.withAutocleanup {
        try await RecordMethodHandler(target: target, targetLogger: targetLogger)
          .handle(requestStream: reader, responseStream: response, context: context)
      }
    }
  }

  func screenshot(request: Idb_ScreenshotRequest, context: ServerContext) async throws -> Idb_ScreenshotResponse {
    return try await trackedUnaryCall("screenshot", request: request) {
      try await TeardownContext.withAutocleanup {
        try await ScreenshotMethodHandler(commandExecutor: commandExecutor)
          .handle(request: request, context: context)
      }
    }
  }

  func video_stream(request: RPCAsyncSequence<Idb_VideoStreamRequest, any Error>, response: RPCWriter<Idb_VideoStreamResponse>, context: ServerContext) async throws {
    let reader = RequestStreamReader(request)
    try await trackedBidiStreaming("video_stream") {
      try await TeardownContext.withAutocleanup {
        try await VideoStreamMethodHandler(target: target, targetLogger: targetLogger, commandExecutor: commandExecutor)
          .handle(requestStream: reader, responseStream: response, context: context)
      }
    }
  }

  func crash_delete(request: Idb_CrashLogQuery, context: ServerContext) async throws -> Idb_CrashLogResponse {
    return try await trackedUnaryCall("crash_delete", request: request) {
      try await TeardownContext.withAutocleanup {
        try await CrashDeleteMethodHandler(commandExecutor: commandExecutor)
          .handle(request: request, context: context)
      }
    }
  }

  func crash_list(request: Idb_CrashLogQuery, context: ServerContext) async throws -> Idb_CrashLogResponse {
    return try await trackedUnaryCall("crash_list", request: request) {
      try await TeardownContext.withAutocleanup {
        try await CrashListMethodHandler(commandExecutor: commandExecutor)
          .handle(request: request, context: context)
      }
    }
  }

  func crash_show(request: Idb_CrashShowRequest, context: ServerContext) async throws -> Idb_CrashShowResponse {
    return try await trackedUnaryCall("crash_show", request: request) {
      try await TeardownContext.withAutocleanup {
        try await CrashShowMethodHandler(commandExecutor: commandExecutor)
          .handle(request: request, context: context)
      }
    }
  }

  func xctest_list_bundles(request: Idb_XctestListBundlesRequest, context: ServerContext) async throws -> Idb_XctestListBundlesResponse {
    return try await trackedUnaryCall("xctest_list_bundles", request: request) {
      try await TeardownContext.withAutocleanup {
        try await XCTestListBundlesMethodHandler(commandExecutor: commandExecutor)
          .handle(request: request, context: context)
      }
    }
  }

  func xctest_list_tests(request: Idb_XctestListTestsRequest, context: ServerContext) async throws -> Idb_XctestListTestsResponse {
    return try await trackedUnaryCall("xctest_list_tests", request: request) {
      try await TeardownContext.withAutocleanup {
        try await XCTestListTestsMethodHandler(commandExecutor: commandExecutor)
          .handle(request: request, context: context)
      }
    }
  }

  func xctest_run(request: Idb_XctestRunRequest, response: RPCWriter<Idb_XctestRunResponse>, context: ServerContext) async throws {
    try await trackedServerStreaming("xctest_run", request: request) {
      try await TeardownContext.withAutocleanup {
        try await XCTestRunMethodHandler(target: target, commandExecutor: commandExecutor, reporter: reporter, targetLogger: targetLogger, logger: logger)
          .handle(request: request, responseStream: response, context: context)
      }
    }
  }

  func repl(request: RPCAsyncSequence<Idb_ReplRequest, any Error>, response: RPCWriter<Idb_ReplResponse>, context: ServerContext) async throws {
    let reader = RequestStreamReader(request)
    try await trackedBidiStreaming("repl") {
      try await TeardownContext.withAutocleanup {
        try await ReplMethodHandler(commandExecutor: commandExecutor, targetLogger: targetLogger, recordingCoordinator: replRecordingCoordinator)
          .handle(requestStream: reader, responseStream: response, context: context)
      }
    }
  }

  func ls(request: Idb_LsRequest, context: ServerContext) async throws -> Idb_LsResponse {
    return try await trackedUnaryCall("ls", request: request, summarize: LsMethodHandler.summarize) {
      try await TeardownContext.withAutocleanup {
        try await LsMethodHandler(commandExecutor: commandExecutor)
          .handle(request: request, context: context)
      }
    }
  }

  func mkdir(request: Idb_MkdirRequest, context: ServerContext) async throws -> Idb_MkdirResponse {
    return try await trackedUnaryCall("mkdir", request: request) {
      try await TeardownContext.withAutocleanup {
        try await MkdirMethodHandler(commandExecutor: commandExecutor)
          .handle(request: request, context: context)
      }
    }
  }

  func mv(request: Idb_MvRequest, context: ServerContext) async throws -> Idb_MvResponse {
    return try await trackedUnaryCall("mv", request: request) {
      try await TeardownContext.withAutocleanup {
        try await MvMethodHandler(commandExecutor: commandExecutor)
          .handle(request: request, context: context)
      }
    }
  }

  func rm(request: Idb_RmRequest, context: ServerContext) async throws -> Idb_RmResponse {
    return try await trackedUnaryCall("rm", request: request) {
      try await TeardownContext.withAutocleanup {
        try await RmMethodHandler(commandExecutor: commandExecutor)
          .handle(request: request, context: context)
      }
    }
  }

  func pull(request: Idb_PullRequest, response: RPCWriter<Idb_PullResponse>, context: ServerContext) async throws {
    try await trackedServerStreaming("pull", request: request) {
      try await TeardownContext.withAutocleanup {
        try await PullMethodHandler(target: target, commandExecutor: commandExecutor)
          .handle(request: request, responseStream: response, context: context)
      }
    }
  }

  func push(request: RPCAsyncSequence<Idb_PushRequest, any Error>, context: ServerContext) async throws -> Idb_PushResponse {
    let reader = RequestStreamReader(request)
    return try await trackedClientStreaming("push") {
      try await TeardownContext.withAutocleanup {
        try await PushMethodHandler(target: target, commandExecutor: commandExecutor)
          .handle(requestStream: reader, context: context)
      }
    }
  }

  func tail(request: RPCAsyncSequence<Idb_TailRequest, any Error>, response: RPCWriter<Idb_TailResponse>, context: ServerContext) async throws {
    let reader = RequestStreamReader(request)
    try await trackedBidiStreaming("tail") {
      try await TeardownContext.withAutocleanup {
        try await TailMethodHandler(commandExecutor: commandExecutor)
          .handle(requestStream: reader, responseStream: response, context: context)
      }
    }
  }
}
