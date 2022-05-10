/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import IDBGRPCSwift
import GRPC
import SwiftProtobuf
import NIOHPACK
import XCTestBootstrap

final class CompanionServiceProvider: Idb_CompanionServiceAsyncProvider {

  private let target: FBiOSTarget
  private let commandExecutor: FBIDBCommandExecutor
  private let reporter: FBEventReporter
  private let logger: FBIDBLogger
  private let internalCppClient: Idb_CompanionServiceAsyncClientProtocol
  private let interceptorFactory: Idb_CompanionServiceServerInterceptorFactoryProtocol

  init(target: FBiOSTarget,
       commandExecutor: FBIDBCommandExecutor,
       reporter: FBEventReporter,
       logger: FBIDBLogger,
       internalCppClient: Idb_CompanionServiceAsyncClientProtocol,
       interceptors: Idb_CompanionServiceServerInterceptorFactoryProtocol) {
    self.target = target
    self.commandExecutor = commandExecutor
    self.reporter = reporter
    self.logger = logger
    self.internalCppClient = internalCppClient
    self.interceptorFactory = interceptors
  }

  var interceptors: Idb_CompanionServiceServerInterceptorFactoryProtocol? { interceptorFactory }

  private func shouldHandleNatively(context: GRPCAsyncServerCallContext) -> Bool {
    return context.userInfo[CallSwiftMethodNatively.self] ?? false
  }

  private var targetLogger: FBControlCoreLogger {
    get throws {
      guard let logger = target.logger else {
        throw GRPCStatus(code: .internalError, message: "Target logger not configured")
      }
      return logger
    }
  }

  func connect(request: Idb_ConnectRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_ConnectResponse {
    guard shouldHandleNatively(context: context) else {
      return try await proxy(request: request, context: context)
    }
    return try await ConnectMethodHandler(reporter: reporter, logger: logger, target: target)
      .handle(request: request, context: context)
  }

  func debugserver(requestStream: GRPCAsyncRequestStream<Idb_DebugServerRequest>, responseStream: GRPCAsyncResponseStreamWriter<Idb_DebugServerResponse>, context: GRPCAsyncServerCallContext) async throws {
    try await proxy(requestStream: requestStream, responseStream: responseStream, context: context)
  }

  func dap(requestStream: GRPCAsyncRequestStream<Idb_DapRequest>, responseStream: GRPCAsyncResponseStreamWriter<Idb_DapResponse>, context: GRPCAsyncServerCallContext) async throws {
    try await proxy(requestStream: requestStream, responseStream: responseStream, context: context)
  }

  func describe(request: Idb_TargetDescriptionRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_TargetDescriptionResponse {
    guard shouldHandleNatively(context: context) else {
        return try await proxy(request: request, context: context)
    }
    return try await DescribeMethodHandler(reporter: reporter, logger: logger, target: target, commandExecutor: commandExecutor)
      .handle(request: request, context: context)
  }

  func install(requestStream: GRPCAsyncRequestStream<Idb_InstallRequest>, responseStream: GRPCAsyncResponseStreamWriter<Idb_InstallResponse>, context: GRPCAsyncServerCallContext) async throws {
    guard shouldHandleNatively(context: context) else {
      return try await proxy(requestStream: requestStream, responseStream: responseStream, context: context)
    }
    try await InstallMethodHandler(commandExecutor: commandExecutor, targetLogger: targetLogger)
      .handle(requestStream: requestStream, responseStream: responseStream, context: context)
  }

  func instruments_run(requestStream: GRPCAsyncRequestStream<Idb_InstrumentsRunRequest>, responseStream: GRPCAsyncResponseStreamWriter<Idb_InstrumentsRunResponse>, context: GRPCAsyncServerCallContext) async throws {
    try await proxy(requestStream: requestStream, responseStream: responseStream, context: context)
  }

  func log(request: Idb_LogRequest, responseStream: GRPCAsyncResponseStreamWriter<Idb_LogResponse>, context: GRPCAsyncServerCallContext) async throws {
    guard shouldHandleNatively(context: context) else {
      return try await proxy(request: request, responseStream: responseStream, context: context)
    }

    return try await LogMethodHandler(target: target, commandExecutor: commandExecutor)
      .handle(request: request, responseStream: responseStream, context: context)
  }

  func xctrace_record(requestStream: GRPCAsyncRequestStream<Idb_XctraceRecordRequest>, responseStream: GRPCAsyncResponseStreamWriter<Idb_XctraceRecordResponse>, context: GRPCAsyncServerCallContext) async throws {
    try await proxy(requestStream: requestStream, responseStream: responseStream, context: context)
  }

  func accessibility_info(request: Idb_AccessibilityInfoRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_AccessibilityInfoResponse {
    guard shouldHandleNatively(context: context) else {
      return try await proxy(request: request, context: context)
    }
    return try await AccessibilityInfoMethodHandler(commandExecutor: commandExecutor)
      .handle(request: request, context: context)
  }

  func focus(request: Idb_FocusRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_FocusResponse {
    guard shouldHandleNatively(context: context) else {
      return try await proxy(request: request, context: context)
    }
    return try await FBTeardownContext.withAutocleanup {
      try await FocusMethodHandler(commandExecutor: commandExecutor)
        .handle(request: request, context: context)
    }
  }

  func hid(requestStream: GRPCAsyncRequestStream<Idb_HIDEvent>, context: GRPCAsyncServerCallContext) async throws -> Idb_HIDResponse {
    guard shouldHandleNatively(context: context) else {
      return try await proxy(requestStream: requestStream, context: context)
    }

    return try await HidMethodHandler(commandExecutor: commandExecutor)
      .handle(requestStream: requestStream, context: context)
  }

  func open_url(request: Idb_OpenUrlRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_OpenUrlRequest {
    guard shouldHandleNatively(context: context) else {
      return try await proxy(request: request, context: context)
    }

    return try await OpenUrlMethodHandler(commandExecutor: commandExecutor)
      .handle(request: request, context: context)
  }

  func set_location(request: Idb_SetLocationRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_SetLocationResponse {
    return try await proxy(request: request, context: context)
  }

  func send_notification(request: Idb_SendNotificationRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_SendNotificationResponse {
    guard shouldHandleNatively(context: context) else {
      return try await proxy(request: request, context: context)
    }
    return try await FBTeardownContext.withAutocleanup {
      try await SendNotificationMethodHandler(commandExecutor: commandExecutor)
        .handle(request: request, context: context)
    }
  }

  func simulate_memory_warning(request: Idb_SimulateMemoryWarningRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_SimulateMemoryWarningResponse {
    guard shouldHandleNatively(context: context) else {
      return try await proxy(request: request, context: context)
    }
    return try await FBTeardownContext.withAutocleanup {
      try await SimulateMemoryWarningMethodHandler(commandExecutor: commandExecutor)
        .handle(request: request, context: context)
    }
  }

  func approve(request: Idb_ApproveRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_ApproveResponse {
    guard shouldHandleNatively(context: context) else {
      return try await proxy(request: request, context: context)
    }

    return try await ApproveMethodHandler(commandExecutor: commandExecutor)
      .handle(request: request, context: context)
  }

  func clear_keychain(request: Idb_ClearKeychainRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_ClearKeychainResponse {
    guard shouldHandleNatively(context: context) else {
      return try await proxy(request: request, context: context)
    }

    return try await ClearKeychainMethodHandler(commandExecutor: commandExecutor)
      .handle(request: request, context: context)
  }

  func contacts_update(request: Idb_ContactsUpdateRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_ContactsUpdateResponse {
    return try await proxy(request: request, context: context)
  }

  func setting(request: Idb_SettingRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_SettingResponse {
    guard shouldHandleNatively(context: context) else {
      return try await proxy(request: request, context: context)
    }
    return try await SettingMethodHandler(commandExecutor: commandExecutor)
      .handle(request: request, context: context)
  }

  func get_setting(request: Idb_GetSettingRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_GetSettingResponse {
    return try await proxy(request: request, context: context)
  }

  func list_settings(request: Idb_ListSettingRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_ListSettingResponse {
    guard shouldHandleNatively(context: context) else {
      return try await proxy(request: request, context: context)
    }
    return try await ListSettingsMethodHandler(commandExecutor: commandExecutor)
      .handle(request: request, context: context)
  }

  func launch(requestStream: GRPCAsyncRequestStream<Idb_LaunchRequest>, responseStream: GRPCAsyncResponseStreamWriter<Idb_LaunchResponse>, context: GRPCAsyncServerCallContext) async throws {
    guard shouldHandleNatively(context: context) else {
      try await proxy(requestStream: requestStream, responseStream: responseStream, context: context)
      return
    }
    try await LaunchMethodHandler(commandExecutor: commandExecutor)
      .handle(requestStream: requestStream, responseStream: responseStream, context: context)
  }

  func list_apps(request: Idb_ListAppsRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_ListAppsResponse {
    guard shouldHandleNatively(context: context) else {
      return try await proxy(request: request, context: context)
    }
    return try await ListAppsMethodHandler(commandExecutor: commandExecutor)
      .handle(request: request, context: context)
  }

  func terminate(request: Idb_TerminateRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_TerminateResponse {
    guard shouldHandleNatively(context: context) else {
      return try await proxy(request: request, context: context)
    }

    return try await TerminateMethodHandler(commandExecutor: commandExecutor)
      .handle(request: request, context: context)
  }

  func uninstall(request: Idb_UninstallRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_UninstallResponse {
    guard shouldHandleNatively(context: context) else {
      return try await proxy(request: request, context: context)
    }
    return try await FBTeardownContext.withAutocleanup {
      try await UninstallMethodHandler(commandExecutor: commandExecutor)
        .handle(request: request, context: context)
    }
  }

  func add_media(requestStream: GRPCAsyncRequestStream<Idb_AddMediaRequest>, context: GRPCAsyncServerCallContext) async throws -> Idb_AddMediaResponse {
    return try await proxy(requestStream: requestStream, context: context)
  }

  func record(requestStream: GRPCAsyncRequestStream<Idb_RecordRequest>, responseStream: GRPCAsyncResponseStreamWriter<Idb_RecordResponse>, context: GRPCAsyncServerCallContext) async throws {
    guard shouldHandleNatively(context: context) else {
      return try await proxy(requestStream: requestStream, responseStream: responseStream, context: context)
    }
    return try await RecordMethodHandler(target: target, targetLogger: targetLogger)
      .handle(requestStream: requestStream, responseStream: responseStream, context: context)
  }

  func screenshot(request: Idb_ScreenshotRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_ScreenshotResponse {
    guard shouldHandleNatively(context: context) else {
      return try await proxy(request: request, context: context)
    }

    return try await ScreenshotMethodHandler(commandExecutor: commandExecutor)
      .handle(request: request, context: context)
  }

  func video_stream(requestStream: GRPCAsyncRequestStream<Idb_VideoStreamRequest>, responseStream: GRPCAsyncResponseStreamWriter<Idb_VideoStreamResponse>, context: GRPCAsyncServerCallContext) async throws {
    return try await proxy(requestStream: requestStream, responseStream: responseStream, context: context)
  }

  func crash_delete(request: Idb_CrashLogQuery, context: GRPCAsyncServerCallContext) async throws -> Idb_CrashLogResponse {
    return try await proxy(request: request, context: context)
  }

  func crash_list(request: Idb_CrashLogQuery, context: GRPCAsyncServerCallContext) async throws -> Idb_CrashLogResponse {
    return try await proxy(request: request, context: context)
  }

  func crash_show(request: Idb_CrashShowRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_CrashShowResponse {
    return try await proxy(request: request, context: context)
  }

  func xctest_list_bundles(request: Idb_XctestListBundlesRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_XctestListBundlesResponse {
    return try await proxy(request: request, context: context)
  }

  func xctest_list_tests(request: Idb_XctestListTestsRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_XctestListTestsResponse {
    return try await proxy(request: request, context: context)
  }

  func xctest_run(request: Idb_XctestRunRequest, responseStream: GRPCAsyncResponseStreamWriter<Idb_XctestRunResponse>, context: GRPCAsyncServerCallContext) async throws {
    guard shouldHandleNatively(context: context) else {
      try await proxy(request: request, responseStream: responseStream, context: context)
      return
    }

    try await XCTestRunMethodHandler(target: target, commandExecutor: commandExecutor, reporter: reporter, targetLogger: targetLogger, logger: logger)
      .handle(request: request, responseStream: responseStream, context: context)
  }

  func ls(request: Idb_LsRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_LsResponse {
    guard shouldHandleNatively(context: context) else {
      return try await proxy(request: request, context: context)
    }
    return try await LsMethodHandler(commandExecutor: commandExecutor)
      .handle(request: request, context: context)
  }

  func mkdir(request: Idb_MkdirRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_MkdirResponse {
    guard shouldHandleNatively(context: context) else {
      return try await proxy(request: request, context: context)
    }
    return try await MkdirMethodHandler(commandExecutor: commandExecutor)
      .handle(request: request, context: context)
  }

  func mv(request: Idb_MvRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_MvResponse {
    guard shouldHandleNatively(context: context) else {
      return try await proxy(request: request, context: context)
    }

    return try await MvMethodHandler(commandExecutor: commandExecutor)
      .handle(request: request, context: context)
  }

  func rm(request: Idb_RmRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_RmResponse {
    guard shouldHandleNatively(context: context) else {
      return try await proxy(request: request, context: context)
    }

    return try await RmMethodHandler(commandExecutor: commandExecutor)
      .handle(request: request, context: context)
  }

  func pull(request: Idb_PullRequest, responseStream: GRPCAsyncResponseStreamWriter<Idb_PullResponse>, context: GRPCAsyncServerCallContext) async throws {
    guard shouldHandleNatively(context: context) else {
      return try await proxy(request: request, responseStream: responseStream, context: context)
    }
    return try await PullMethodHandler(target: target, commandExecutor: commandExecutor)
      .handle(request: request, responseStream: responseStream, context: context)
  }

  func push(requestStream: GRPCAsyncRequestStream<Idb_PushRequest>, context: GRPCAsyncServerCallContext) async throws -> Idb_PushResponse {
    guard shouldHandleNatively(context: context) else {
      return try await proxy(requestStream: requestStream, context: context)
    }
    return try await FBTeardownContext.withAutocleanup {
      try await PushMethodHandler(target: target, commandExecutor: commandExecutor)
        .handle(requestStream: requestStream, context: context)
    }
  }

  func tail(requestStream: GRPCAsyncRequestStream<Idb_TailRequest>, responseStream: GRPCAsyncResponseStreamWriter<Idb_TailResponse>, context: GRPCAsyncServerCallContext) async throws {
    guard shouldHandleNatively(context: context) else {
      return try await proxy(requestStream: requestStream, responseStream: responseStream, context: context)
    }
    return try await FBTeardownContext.withAutocleanup {
      try await TailMethodHandler(commandExecutor: commandExecutor)
        .handle(requestStream: requestStream, responseStream: responseStream, context: context)
    }
  }
}

extension CompanionServiceProvider {

  private func proxy<Request: Message, Response: Message>(request: Request, context: GRPCAsyncServerCallContext) async throws -> Response {
    let methodPath = try extractMethodPathAndLogProxyMessage(context: context)
    return try await internalCppClient.performAsyncUnaryCall(path: methodPath, request: request)
  }

  private func proxy<Request: Message, Response: Message>(request: Request, responseStream: GRPCAsyncResponseStreamWriter<Response>, context: GRPCAsyncServerCallContext) async throws {
    let methodPath = try extractMethodPathAndLogProxyMessage(context: context)
    let resultStream = internalCppClient.performAsyncServerStreamingCall(path: methodPath, request: request, responseType: Response.self)

    for try await response in resultStream {
      try await responseStream.send(response)
    }
  }

  private func proxy<Request: Message, Response: Message>(requestStream: GRPCAsyncRequestStream<Request>, context: GRPCAsyncServerCallContext) async throws -> Response {
    let methodPath = try extractMethodPathAndLogProxyMessage(context: context)
    return try await internalCppClient.performAsyncClientStreamingCall(path: methodPath, requests: requestStream)
  }

  private func proxy<Request: Message, Response: Message>(requestStream: GRPCAsyncRequestStream<Request>, responseStream: GRPCAsyncResponseStreamWriter<Response>, context: GRPCAsyncServerCallContext) async throws {
    let methodPath = try extractMethodPathAndLogProxyMessage(context: context)
    let resultStream = internalCppClient.performAsyncBidirectionalStreamingCall(path: methodPath, requests: requestStream, responseType: Response.self)

    for try await response in resultStream {
      try await responseStream.send(response)
    }
  }

  private func extractMethodPathAndLogProxyMessage(context: GRPCAsyncServerCallContext) throws -> String {
    guard let methodPath = context.userInfo[MethodPathKey.self] else {
      throw GRPCStatus(code: .internalError, message: "Method path not provided. Check idb_companion's grpc interceptor configuration")
    }
    logger.log("Proxying \(methodPath) to cpp server")
    return methodPath
  }
}
