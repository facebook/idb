/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBSimulatorControl
import Foundation

enum QueryError: Error, CustomStringConvertible {
  case TooManyMatches([FBiOSTarget], Int)
  case NoMatches
  case WrongTarget(String, String)
  case NoneProvided

  var description: String {
    switch self {
    case let .TooManyMatches(matches, expected):
      return "Matched too many Targets. \(expected) targets matched but had \(matches.count)"
    case .NoMatches:
      return "No Matching Targets"
    case let .WrongTarget(expected, actual):
      return "Wrong Target. Expected \(expected) but got \(actual)"
    case .NoneProvided:
      return "No Query Provided"
    }
  }
}

extension HttpRequest {
  func jsonBody() throws -> JSON {
    return try JSON.fromData(body)
  }
}

enum ResponseKeys: String {
  case Success = "success"
  case Failure = "failure"
  case Status = "status"
  case Message = "message"
  case Events = "events"
  case Subject = "subject"
}

@objc private class HttpEventReporter: NSObject, EventReporter {
  var metadata: [String : String] = [:]

  var events: [FBEventReporterSubjectProtocol] = []
  let interpreter: EventInterpreter = FBEventInterpreter.jsonEventInterpreter(false)
  let consumer: Writer = FBFileWriter.nullWriter

  func report(_ subject: FBEventReporterSubjectProtocol) {
    events.append(subject)
  }

  var jsonDescription: JSON {
    let events: AnyObject = self.events.map { $0.jsonSerializableRepresentation } as AnyObject
    return try! JSON.encode(events)
  }

  static func errorResponse(_ errorMessage: String?) -> HttpResponse {
    let json = JSON.dictionary([
      ResponseKeys.Status.rawValue: JSON.string(ResponseKeys.Failure.rawValue),
      ResponseKeys.Message.rawValue: JSON.string(errorMessage ?? "Unknown Error"),
    ])
    return HttpResponse.internalServerError(json.data)
  }

  func interactionResultResponse(_ result: CommandResult) -> HttpResponse {
    switch result.outcome {
    case let .failure(string):
      let json = JSON.dictionary([
        ResponseKeys.Status.rawValue: JSON.string(ResponseKeys.Failure.rawValue),
        ResponseKeys.Message.rawValue: JSON.string(string),
        ResponseKeys.Events.rawValue: self.jsonDescription,
      ])
      return HttpResponse.internalServerError(json.data)
    case let .success(subject):
      var dictionary = [
        ResponseKeys.Status.rawValue: JSON.string(ResponseKeys.Success.rawValue),
        ResponseKeys.Events.rawValue: self.jsonDescription,
      ]
      if let subject = subject {
        dictionary[ResponseKeys.Subject.rawValue] = subject.jsonDescription
      }
      let json = JSON.dictionary(dictionary)
      return HttpResponse.ok(json.data)
    }
  }

  func addMetadata(_: [String: String]) {}
}

extension ActionPerformer {
  func dispatchAction(_ action: Action, queryOverride: FBiOSTargetQuery?) -> HttpResponse {
    let reporter = HttpEventReporter()
    let future = self.future(reporter: reporter, action: action, queryOverride: queryOverride)
    do {
      let result = try future.await(withTimeout: FBControlCoreGlobalConfiguration.slowTimeout)
      return reporter.interactionResultResponse(result.value)
    } catch {
      return reporter.interactionResultResponse(.failure("Timed Out Performing Action \(action)"))
    }
  }

  func futureWithSingleTarget<A>(_ query: FBiOSTargetQuery, action: (FBiOSTarget) -> FBFuture<A>) throws -> FBFuture<A> {
    let target = try runnerContext(HttpEventReporter()).querySingleTarget(query)
    let future = target.workQueue.sync {
      action(target)
    }
    return future
  }
}

enum HttpMethod: String {
  case GET
  case POST
}

enum ActionHandler {
  case constant(Action)
  case path(([String]) throws -> Action)
  case parser((JSON) throws -> Action)
  case binary((Data) throws -> Action)
  case file(String, (HttpRequest, URL) throws -> Action)

  func produceAction(_ request: HttpRequest) throws -> (Action, FBiOSTargetQuery?) {
    switch self {
    case let .constant(action):
      return (action, nil)
    case let .path(pathHandler):
      let components = Array(request.pathComponents.dropFirst())
      let action = try pathHandler(components)
      return (action, nil)
    case let .parser(actionParser):
      let json = try request.jsonBody()
      let action = try actionParser(json)
      let query = try? FBiOSTargetQuery.inflate(fromJSON: json.getValue("simulators").decode())
      return (action, query)
    case let .binary(binaryHandler):
      let action = try binaryHandler(request.body)
      return (action, nil)
    case let .file(pathExtension, handler):
      let guid = UUID().uuidString
      let destination = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("fbsimctl-\(guid)")
        .appendingPathExtension(pathExtension)
      if FileManager.default.fileExists(atPath: destination.path) {
        throw ParseError.custom("Could not generate temporary filename, \(destination.path) already exists.")
      }
      try request.body.write(to: destination)
      let action = try handler(request, destination)
      return (action, nil)
    }
  }
}

class ActionHttpResponseHandler: NSObject, HttpResponseHandler {
  let performer: ActionPerformer
  let handler: ActionHandler

  init(performer: ActionPerformer, handler: ActionHandler) {
    self.performer = performer
    self.handler = handler
    super.init()
  }

  func handle(_ request: HttpRequest) -> HttpResponse {
    return SimpleResponseHandler.perform(request: request) { request in
      let pathQuery = try SimpleResponseHandler.extractQueryFromPath(request)
      let (action, actionQuery) = try self.handler.produceAction(request)
      let response = performer.dispatchAction(action, queryOverride: pathQuery ?? actionQuery)
      return response
    }
  }
}

class SimpleResponseHandler: NSObject, HttpResponseHandler {
  let handler: (HttpRequest) throws -> HttpResponse

  init(handler: @escaping (HttpRequest) throws -> HttpResponse) {
    self.handler = handler
    super.init()
  }

  func handle(_ request: HttpRequest) -> HttpResponse {
    return SimpleResponseHandler.perform(request: request, handler)
  }

  static func perform(request: HttpRequest, _ handler: (HttpRequest) throws -> HttpResponse) -> HttpResponse {
    do {
      return try handler(request)
    } catch let error as CustomStringConvertible {
      return HttpEventReporter.errorResponse(error.description)
    } catch let error as NSError {
      return HttpEventReporter.errorResponse(error.localizedDescription)
    } catch {
      return HttpEventReporter.errorResponse(nil)
    }
  }

  static func extractQueryFromPath(_ request: HttpRequest) throws -> FBiOSTargetQuery? {
    guard let queryPath = request.pathComponents.dropFirst().first, request.pathComponents.count >= 3 else {
      return nil
    }
    return FBiOSTargetQuery.udids([
      try FBiOSTargetQuery.parseUDIDToken(queryPath),
    ])
  }
}

protocol Route {
  var method: HttpMethod { get }
  var endpoint: String { get }
  func responseHandler(performer: ActionPerformer) -> HttpResponseHandler
}

extension Route {
  func httpRoutes(_ performer: ActionPerformer) -> [HttpRoute] {
    let handler = responseHandler(performer: performer)

    return [
      HttpRoute(method: self.method.rawValue, path: "/.*/" + self.endpoint, handler: handler),
      HttpRoute(method: self.method.rawValue, path: "/" + self.endpoint, handler: handler),
    ]
  }
}

struct ActionRoute: Route {
  let method: HttpMethod
  let eventName: EventName
  let handler: ActionHandler

  static func post(_ eventName: EventName, handler: @escaping (JSON) throws -> Action) -> Route {
    return ActionRoute(method: HttpMethod.POST, eventName: eventName, handler: ActionHandler.parser(handler))
  }

  static func postFile(_ eventName: EventName, _ pathExtension: String, handler: @escaping (HttpRequest, URL) throws -> Action) -> Route {
    return ActionRoute(method: HttpMethod.POST, eventName: eventName, handler: ActionHandler.file(pathExtension, handler))
  }

  static func getConstant(_ eventName: EventName, action: Action) -> Route {
    return ActionRoute(method: HttpMethod.GET, eventName: eventName, handler: ActionHandler.constant(action))
  }

  static func get(_ eventName: EventName, handler: @escaping ([String]) throws -> Action) -> Route {
    return ActionRoute(method: HttpMethod.GET, eventName: eventName, handler: ActionHandler.path(handler))
  }

  var endpoint: String {
    return eventName.rawValue
  }

  func responseHandler(performer: ActionPerformer) -> HttpResponseHandler {
    return ActionHttpResponseHandler(performer: performer, handler: handler)
  }
}

struct ScreenshotRoute: Route {
  let format: FBScreenshotFormat

  var method: HttpMethod {
    return HttpMethod.GET
  }

  var endpoint: String {
    return "screenshot.\(format.rawValue)"
  }

  func responseHandler(performer: ActionPerformer) -> HttpResponseHandler {
    let format = self.format
    return SimpleResponseHandler { request in
      guard let query = try SimpleResponseHandler.extractQueryFromPath(request) else {
        throw QueryError.NoneProvided
      }
      let imageFuture: FBFuture<NSData> = try performer.futureWithSingleTarget(query) { target in
        target.takeScreenshot(format)
      }
      let imageData = try imageFuture.await()
      return HttpResponse(statusCode: 200, body: imageData as Data, contentType: "image/" + self.format.rawValue)
    }
  }
}

class HttpRelay: Relay {
  struct HttpError: Error, CustomStringConvertible {
    let message: String

    var description: String {
      return message
    }
  }

  let portNumber: in_port_t
  let httpServer: HttpServer
  let performer: ActionPerformer

  init(portNumber: in_port_t, performer: ActionPerformer) {
    self.portNumber = portNumber
    self.performer = performer
    httpServer = HttpServer(
      port: portNumber,
      routes: HttpRelay.actionRoutes.flatMap { $0.httpRoutes(performer) },
      logger: FBControlCoreGlobalConfiguration.defaultLogger
    )
  }

  func start() throws {
    do {
      try httpServer.start()
    } catch let error as NSError {
      throw HttpRelay.HttpError(message: "An Error occurred starting the HTTP Server on Port \(self.portNumber): \(error.description)")
    }
  }

  func stop() {
    httpServer.stop()
  }

  fileprivate static var approveRoute: Route {
    return ActionRoute.post(.approve) { json in
      let approval = try FBSettingsApproval.inflate(fromJSON: json.decode())
      return Action.coreFuture(approval)
    }
  }

  fileprivate static var clearKeychainRoute: Route {
    return ActionRoute.post(.clearKeychain) { json in
      let bundleID = try json.getValue("bundle_id").getString()
      return Action.clearKeychain(bundleID)
    }
  }

  fileprivate static var configRoute: Route {
    return ActionRoute.getConstant(.config, action: Action.config)
  }

  fileprivate static var diagnosticQueryRoute: Route {
    return ActionRoute.post(.diagnose) { json in
      var query = try FBDiagnosticQuery.inflate(fromJSON: json.decode())
      query = query.withFormat(DiagnosticFormat.content)
      return Action.diagnose(query)
    }
  }

  fileprivate static var diagnosticRoute: Route {
    return ActionRoute.get(.diagnose) { components in
      guard let name = components.last else {
        throw ParseError.custom("No diagnostic name provided")
      }
      var query = FBDiagnosticQuery.named([name])
      query = query.withFormat(DiagnosticFormat.content)
      return Action.diagnose(query)
    }
  }

  fileprivate static var hidRoute: Route {
    return ActionRoute.post(.hid) { json in
      let event = try FBSimulatorHIDEvent.inflate(fromJSON: json.decode())
      return Action.hid(event)
    }
  }

  fileprivate static var installRoute: Route {
    return ActionRoute.postFile(.install, "ipa") { request, file in
      let shouldCodeSign = request.getBoolQueryParam("codesign", false)
      return Action.install(file.path, shouldCodeSign)
    }
  }

  fileprivate static var launchRoute: Route {
    return ActionRoute.post(.launch) { json in
      if let agentLaunch = try? FBAgentLaunchConfiguration.inflate(fromJSON: json.decode()) {
        return Action.launchAgent(agentLaunch)
      }
      if let appLaunch = try? FBApplicationLaunchConfiguration.inflate(fromJSON: json.decode()) {
        return Action.launchApp(appLaunch)
      }

      throw JSONError.parse("Could not parse \(json) either an Agent or App Launch")
    }
  }

  fileprivate static var listRoute: Route {
    return ActionRoute.getConstant(.list, action: Action.list)
  }

  fileprivate static var listAppsRoute: Route {
    return ActionRoute.getConstant(.listApps, action: Action.listApps)
  }

  fileprivate static var openRoute: Route {
    return ActionRoute.post(.open) { json in
      let urlString = try json.getValue("url").getString()
      guard let url = URL(string: urlString) else {
        throw JSONError.parse("\(urlString) is not a valid URL")
      }
      return Action.open(url)
    }
  }

  fileprivate static var recordRoute: Route {
    return ActionRoute.post(.record) { json in
      if try json.getValue("start").getBool() {
        return Action.record(Record.start(nil))
      }
      return Action.record(Record.stop)
    }
  }

  fileprivate static var relaunchRoute: Route {
    return ActionRoute.post(.relaunch) { json in
      let launchConfiguration = try FBApplicationLaunchConfiguration.inflate(fromJSON: json.decode())
      return Action.relaunch(launchConfiguration)
    }
  }

  fileprivate static var searchRoute: Route {
    return ActionRoute.post(.search) { json in
      let search = try FBBatchLogSearch.inflate(fromJSON: json.decode())
      return Action.search(search)
    }
  }

  fileprivate static var setLocationRoute: Route {
    return ActionRoute.post(.setLocation) { json in
      let latitude = try json.getValue("latitude").getNumber().doubleValue
      let longitude = try json.getValue("longitude").getNumber().doubleValue
      return Action.setLocation(latitude, longitude)
    }
  }

  fileprivate static var tapRoute: Route {
    return ActionRoute.post(.tap) { json in
      let x = try json.getValue("x").getNumber().doubleValue
      let y = try json.getValue("y").getNumber().doubleValue
      let event = FBSimulatorHIDEvent.tapAt(x: x, y: y)
      return Action.hid(event)
    }
  }

  fileprivate static var terminateRoute: Route {
    return ActionRoute.post(.terminate) { json in
      let bundleID = try json.getValue("bundle_id").getString()
      return Action.terminate(bundleID)
    }
  }

  fileprivate static var uninstallRoute: Route {
    return ActionRoute.post(.uninstall) { json in
      let bundleID = try json.getValue("bundle_id").getString()
      return Action.uninstall(bundleID)
    }
  }

  fileprivate static var uploadRoute: Route {
    let jsonToDiagnostics: (JSON) throws -> [FBDiagnostic] = { json in
      switch json {
      case let .array(array):
        let diagnostics = try array.map { jsonDiagnostic in
          try FBDiagnostic.inflate(fromJSON: jsonDiagnostic.decode())
        }
        return diagnostics
      case .dictionary:
        let diagnostic = try FBDiagnostic.inflate(fromJSON: json.decode())
        return [diagnostic]
      default:
        throw JSONError.parse("Unparsable Diagnostic")
      }
    }

    return ActionRoute.post(.upload) { json in
      Action.upload(try jsonToDiagnostics(json))
    }
  }

  fileprivate static var actionRoutes: [Route] {
    return [
      self.approveRoute,
      self.clearKeychainRoute,
      self.configRoute,
      self.diagnosticQueryRoute,
      self.diagnosticRoute,
      self.hidRoute,
      self.installRoute,
      self.launchRoute,
      self.listRoute,
      self.listAppsRoute,
      self.openRoute,
      self.recordRoute,
      self.relaunchRoute,
      self.searchRoute,
      self.setLocationRoute,
      self.tapRoute,
      self.terminateRoute,
      self.uninstallRoute,
      self.uploadRoute,
      ScreenshotRoute(format: FBScreenshotFormat.PNG),
      ScreenshotRoute(format: FBScreenshotFormat.JPEG),
    ]
  }
}
