    /**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

import Foundation
import FBSimulatorControl

enum QueryError : Error, CustomStringConvertible {
  case TooManyMatches([FBiOSTarget], Int)
  case NoMatches
  case WrongTarget(String, String)
  case NoneProvided

  var description: String { get {
    switch self {
    case .TooManyMatches(let matches, let expected):
      return "Matched too many Targets. \(expected) targets matched but had \(matches.count)"
    case .NoMatches:
      return "No Matching Targets"
    case .WrongTarget(let expected, let actual):
      return "Wrong Target. Expected \(expected) but got \(actual)"
    case .NoneProvided:
      return "No Query Provided"
    }
  }}
}

extension HttpRequest {
  func jsonBody() throws -> JSON {
    return try JSON.fromData(self.body)
  }
}

enum ResponseKeys : String {
  case Success = "success"
  case Failure = "failure"
  case Status = "status"
  case Message = "message"
  case Events = "events"
  case Subject = "subject"
}

private class HttpEventReporter : EventReporter {
  var events: [EventReporterSubject] = []
  let interpreter: EventInterpreter = JSONEventInterpreter(pretty: false)
  let writer: Writer = FileHandleWriter.nullWriter

  fileprivate func report(_ subject: EventReporterSubject) {
    self.events.append(subject)
  }

  var jsonDescription: JSON { get {
    return JSON.array(self.events.map { $0.jsonDescription })
  }}

  static func errorResponse(_ errorMessage: String?) -> HttpResponse {
    let json = JSON.dictionary([
      ResponseKeys.Status.rawValue : JSON.string(ResponseKeys.Failure.rawValue),
      ResponseKeys.Message.rawValue : JSON.string(errorMessage ?? "Unknown Error")
    ])
    return HttpResponse.internalServerError(json.data)
  }

  func interactionResultResponse(_ result: CommandResult) -> HttpResponse {
    switch result.outcome {
    case .failure(let string):
      let json = JSON.dictionary([
        ResponseKeys.Status.rawValue : JSON.string(ResponseKeys.Failure.rawValue),
        ResponseKeys.Message.rawValue : JSON.string(string),
        ResponseKeys.Events.rawValue : self.jsonDescription
      ])
      return HttpResponse.internalServerError(json.data)
    case .success(let subject):
      var dictionary = [
        ResponseKeys.Status.rawValue : JSON.string(ResponseKeys.Success.rawValue),
        ResponseKeys.Events.rawValue : self.jsonDescription
      ]
      if let subject = subject {
        dictionary[ResponseKeys.Subject.rawValue] = subject.jsonDescription
      }
      let json = JSON.dictionary(dictionary)
      return HttpResponse.ok(json.data)
    }
  }
}

extension ActionPerformer {
  func dispatchAction(_ action: Action, queryOverride: FBiOSTargetQuery?) -> HttpResponse {
    let reporter = HttpEventReporter()
    var result: CommandResult? = nil
    DispatchQueue.main.sync {
      result = self.perform(reporter: reporter, action: action, queryOverride: queryOverride)
    }

    return reporter.interactionResultResponse(result!)
  }

  func runWithSingleSimulator<A>(_ query: FBiOSTargetQuery, action: (FBSimulator) throws -> A) throws -> A {
    let simulator = try self.runnerContext(HttpEventReporter()).querySingleSimulator(query)
    var result: A? = nil
    var error: Error? = nil
    DispatchQueue.main.sync {
      do {
        result = try action(simulator)
      } catch let caughtError {
        error = caughtError
      }
    }
    if let error = error {
      throw error
    }
    return result!
  }
}

enum HttpMethod : String {
  case GET = "GET"
  case POST = "POST"
}

enum ActionHandler {
  case constant(Action)
  case path(([String]) throws -> Action)
  case parser((JSON) throws -> Action)
  case binary((Data) throws -> Action)
  case file(String, (HttpRequest, URL) throws -> Action)

  func produceAction(_ request: HttpRequest) throws -> (Action, FBiOSTargetQuery?) {
    switch self {
    case .constant(let action):
      return (action, nil)
    case .path(let pathHandler):
      let components = Array(request.pathComponents.dropFirst())
      let action = try pathHandler(components)
      return (action, nil)
    case .parser(let actionParser):
      let json = try request.jsonBody()
      let action = try actionParser(json)
      let query = try? FBiOSTargetQuery.inflate(fromJSON: json.getValue("simulators").decode())
      return (action, query)
    case .binary(let binaryHandler):
      let action = try binaryHandler(request.body)
      return (action, nil)
    case .file(let pathExtension, let handler):
      let guid = UUID().uuidString
      let destination = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("fbsimctl-\(guid)")
        .appendingPathExtension(pathExtension)
      if (FileManager.default.fileExists(atPath: destination.path)) {
        throw ParseError.custom("Could not generate temporary filename, \(destination.path) already exists.")
      }
      try request.body.write(to: destination)
      let action = try handler(request, destination)
      return (action, nil)
    }
  }
}

class ActionHttpResponseHandler : NSObject, HttpResponseHandler {
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

class SimpleResponseHandler : NSObject, HttpResponseHandler {
  let handler:(HttpRequest)throws -> HttpResponse

  init(handler: @escaping (HttpRequest) throws -> HttpResponse) {
    self.handler = handler
    super.init()
  }

  func handle(_ request: HttpRequest) -> HttpResponse {
    return SimpleResponseHandler.perform(request: request, self.handler)
  }

  static func perform(request: HttpRequest, _ handler:(HttpRequest)throws -> HttpResponse) -> HttpResponse {
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
      try FBiOSTargetQuery.parseUDIDToken(queryPath)
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

struct ActionRoute : Route {
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

  var endpoint: String { get {
    return self.eventName.rawValue
  }}

  func responseHandler(performer: ActionPerformer) -> HttpResponseHandler {
     return ActionHttpResponseHandler(performer: performer, handler: self.handler)
  }
}

struct ScreenshotRoute : Route {
  enum Format : String {
    case jpeg = "jpeg"
    case png = "png"
  }
  let format: ScreenshotRoute.Format

  var method: HttpMethod { get {
    return HttpMethod.GET
  }}

  var endpoint: String { get {
    return "screenshot.\(self.format.rawValue)"
  }}

  func responseHandler(performer: ActionPerformer) -> HttpResponseHandler {
    let format = self.format
    return SimpleResponseHandler { request in
      guard let query = try SimpleResponseHandler.extractQueryFromPath(request) else {
        throw QueryError.NoneProvided
      }
      let imageData: Data = try performer.runWithSingleSimulator(query) { simulator in
        let image = try simulator.connect().connectToFramebuffer().image
        switch (format) {
        case .jpeg: return try image.jpegImageData()
        case .png: return try image.pngImageData()
        }
      }
      return HttpResponse(statusCode: 200, body: imageData, contentType: "image/" + self.format.rawValue)
    }
  }
}

class HttpRelay : Relay {
  struct HttpError : Error, CustomStringConvertible {
    let message: String

    var description: String { get {
      return message
    }}
  }

  let portNumber: in_port_t
  let httpServer: HttpServer
  let performer: ActionPerformer

  init(portNumber: in_port_t, performer: ActionPerformer) {
    self.portNumber = portNumber
    self.performer = performer
    self.httpServer = HttpServer(
      port: portNumber,
      routes: HttpRelay.actionRoutes.flatMap { $0.httpRoutes(performer) },
      logger: FBControlCoreGlobalConfiguration.defaultLogger
    )
  }

  func start() throws {
    do {
      try self.httpServer.start()
    } catch let error as NSError {
      throw HttpRelay.HttpError(message: "An Error occurred starting the HTTP Server on Port \(self.portNumber): \(error.description)")
    }
  }

  func stop() {
    self.httpServer.stop()
  }

  fileprivate static var clearKeychainRoute: Route { get {
    return ActionRoute.post(.clearKeychain) { json in
      let bundleID = try json.getValue("bundle_id").getString()
      return Action.clearKeychain(bundleID)
    }
  }}

  fileprivate static var configRoute: Route { get {
    return ActionRoute.getConstant(.config, action: Action.config)
  }}

  fileprivate static var diagnosticQueryRoute: Route { get {
    return ActionRoute.post(.diagnose) { json in
      let query = try FBDiagnosticQuery.inflate(fromJSON: json.decode())
      return Action.diagnose(query, DiagnosticFormat.Content)
    }
  }}

  fileprivate static var diagnosticRoute: Route { get {
    return ActionRoute.get(.diagnose) { components in
      guard let name = components.last else {
        throw ParseError.custom("No diagnostic name provided")
      }
      let query = FBDiagnosticQuery.named([name])
      return Action.diagnose(query, DiagnosticFormat.Content)
    }
  }}

  fileprivate static var hidRoute: Route { get {
    return ActionRoute.post(.HID) { json in
      let event = try FBSimulatorHIDEvent.inflate(fromJSON: json.decode())
      return Action.hid(event)
    }
  }}

  fileprivate static var installRoute: Route { get {
    return ActionRoute.postFile(.install, "ipa") { request, file in
      let shouldCodeSign = request.getBoolQueryParam("codesign", false)
      return Action.install(file.path, shouldCodeSign)
    }
  }}

  fileprivate static var launchRoute: Route { get {
    return ActionRoute.post(.launch) { json in
      if let agentLaunch = try? FBAgentLaunchConfiguration.inflate(fromJSON: json.decode()) {
        return Action.launchAgent(agentLaunch)
      }
      if let appLaunch = try? FBApplicationLaunchConfiguration.inflate(fromJSON: json.decode()) {
        return Action.launchApp(appLaunch)
      }

      throw JSONError.parse("Could not parse \(json) either an Agent or App Launch")
    }
  }}

  fileprivate static var listRoute: Route { get {
    return ActionRoute.getConstant(.list, action: Action.list)
  }}

  fileprivate static var openRoute: Route { get {
    return ActionRoute.post(.open) { json in
      let urlString = try json.getValue("url").getString()
      guard let url = URL(string: urlString) else {
        throw JSONError.parse("\(urlString) is not a valid URL")
      }
      return Action.open(url)
    }
  }}

  fileprivate static var recordRoute: Route { get {
    return ActionRoute.post(.record) { json in
      if try json.getValue("start").getBool() {
        return Action.record(Record.start(nil))
      }
      return Action.record(Record.stop)
    }
  }}

  fileprivate static var relaunchRoute: Route { get {
    return ActionRoute.post(.relaunch) { json in
      let launchConfiguration = try FBApplicationLaunchConfiguration.inflate(fromJSON: json.decode())
      return Action.relaunch(launchConfiguration)
    }
  }}

  fileprivate static var searchRoute: Route { get {
    return ActionRoute.post(.search) { json in
      let search = try FBBatchLogSearch.inflate(fromJSON: json.decode())
      return Action.search(search)
    }
  }}

  fileprivate static var setLocationRoute: Route { get {
    return ActionRoute.post(.setLocation) { json in
      let latitude = try json.getValue("latitude").getNumber().doubleValue
      let longitude = try json.getValue("longitude").getNumber().doubleValue
      return Action.setLocation(latitude, longitude)
    }
  }}

  fileprivate static var tapRoute: Route { get {
    return ActionRoute.post(.tap) { json in
      let x = try json.getValue("x").getNumber().doubleValue
      let y = try json.getValue("y").getNumber().doubleValue
      let event = FBSimulatorHIDEvent.tapAt(x: x, y: y)
      return Action.core(event)
    }
  }}

  fileprivate static var terminateRoute: Route { get {
    return ActionRoute.post(.terminate) { json in
      let bundleID = try json.getValue("bundle_id").getString()
      return Action.terminate(bundleID)
    }
  }}

  fileprivate static var uploadRoute: Route { get {
    let jsonToDiagnostics:(JSON)throws -> [FBDiagnostic] = { json in
      switch json {
      case .array(let array):
        let diagnostics = try array.map { jsonDiagnostic in
          return try FBDiagnostic.inflate(fromJSON: jsonDiagnostic.decode())
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
      return Action.upload(try jsonToDiagnostics(json))
    }
  }}

  fileprivate static var actionRoutes: [Route] { get {
    return [
      self.clearKeychainRoute,
      self.configRoute,
      self.diagnosticQueryRoute,
      self.diagnosticRoute,
      self.hidRoute,
      self.installRoute,
      self.launchRoute,
      self.listRoute,
      self.openRoute,
      self.recordRoute,
      self.relaunchRoute,
      self.searchRoute,
      self.setLocationRoute,
      self.tapRoute,
      self.terminateRoute,
      self.uploadRoute,
      ScreenshotRoute(format: ScreenshotRoute.Format.png),
      ScreenshotRoute(format: ScreenshotRoute.Format.jpeg),
    ]
  }}
}
