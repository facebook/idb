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

  fileprivate func report(_ subject: EventReporterSubject) {
    self.events.append(subject)
  }

  var jsonDescription: JSON { get {
    return JSON.jArray(self.events.map { $0.jsonDescription })
  }}

  static func errorResponse(_ errorMessage: String?) -> HttpResponse {
    let json = JSON.jDictionary([
      ResponseKeys.Status.rawValue : JSON.jString(ResponseKeys.Failure.rawValue),
      ResponseKeys.Message.rawValue : JSON.jString(errorMessage ?? "Unknown Error")
    ])
    return HttpResponse.internalServerError(json.data)
  }

  func interactionResultResponse(_ result: CommandResult) -> HttpResponse {
    switch result {
    case .failure(let string):
      let json = JSON.jDictionary([
        ResponseKeys.Status.rawValue : JSON.jString(ResponseKeys.Failure.rawValue),
        ResponseKeys.Message.rawValue : JSON.jString(string),
        ResponseKeys.Events.rawValue : self.jsonDescription
      ])
      return HttpResponse.internalServerError(json.data)
    case .success(let subject):
      var dictionary = [
        ResponseKeys.Status.rawValue : JSON.jString(ResponseKeys.Success.rawValue),
        ResponseKeys.Events.rawValue : self.jsonDescription
      ]
      if let subject = subject {
        dictionary[ResponseKeys.Subject.rawValue] = subject.jsonDescription
      }
      let json = JSON.jDictionary(dictionary)
      return HttpResponse.ok(json.data)
    }
  }
}

extension ActionPerformer {
  func dispatchAction(_ action: Action, queryOverride: FBiOSTargetQuery? = nil, formatOverride: FBiOSTargetFormat? = nil) -> HttpResponse {
    let reporter = HttpEventReporter()
    var result: CommandResult? = nil
    DispatchQueue.main.sync {
      result = self.perform(reporter, action: action, queryOverride: queryOverride)
    }

    return reporter.interactionResultResponse(result!)
  }
}

enum HttpMethod : String {
  case GET = "GET"
  case POST = "POST"
}

struct ActionRoute {
  enum Handler {
    case constant(Action)
    case parser((JSON) throws -> Action)
  }

  let method: HttpMethod
  let endpoint: EventName
  let handler: Handler

  static func post(_ endpoint: EventName, handler: @escaping (JSON) throws -> Action) -> ActionRoute {
    return ActionRoute(method: HttpMethod.POST, endpoint: endpoint, handler: Handler.parser(handler))
  }

  static func get(_ endpoint: EventName, action: Action) -> ActionRoute {
    return ActionRoute(method: HttpMethod.GET, endpoint: endpoint, handler: Handler.constant(action))
  }

  fileprivate var pathHandler:(HttpRequest)throws -> FBiOSTargetQuery? { get {
    return { request in
      guard let queryPath = request.pathComponents.dropFirst().first , request.pathComponents.count == 3 else {
        return nil
      }
      return FBiOSTargetQuery.udids([
        try FBiOSTargetQuery.parseUDIDToken(queryPath)
      ])
    }
  }}

  fileprivate var bodyHandler:(HttpRequest)throws -> (Action, FBiOSTargetQuery?) { get {
    switch self.handler {
    case .constant(let action):
      return { _ in (action, nil) }
    case .parser(let actionParser):
      return { request in
        let json = try request.jsonBody()
        let action = try actionParser(json)
        let query = try? FBiOSTargetQuery.inflate(fromJSON: json.getValue("simulators").decode())
        return (action, query)
      }
    }
  }}

  fileprivate func requestHandler(_ performer: ActionPerformer) -> (HttpRequest) -> HttpResponse {
    let bodyHandler = self.bodyHandler
    let pathHandler = self.pathHandler

    return { request in
      do {
        let pathQuery = try pathHandler(request)
        let (action, bodyQuery) = try bodyHandler(request)
        return performer.dispatchAction(action, queryOverride: pathQuery ?? bodyQuery)
      } catch let error as JSONError {
        return HttpEventReporter.errorResponse(error.description)
      } catch let error as ParseError {
        return HttpEventReporter.errorResponse(error.description)
      } catch let error as NSError {
        return HttpEventReporter.errorResponse(error.description)
      } catch {
        return HttpEventReporter.errorResponse(nil)
      }
    }
  }

  func httpRoutes(_ performer: ActionPerformer) -> [HttpRoute] {
    return [
      HttpRoute(method: self.method.rawValue, path: "/.*/" + self.endpoint.rawValue, handler: self.requestHandler(performer)),
      HttpRoute(method: self.method.rawValue, path: "/" + self.endpoint.rawValue, handler: self.requestHandler(performer)),
    ]
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
      routes: HttpRelay.actionRoutes.flatMap { $0.httpRoutes(performer) }
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

  fileprivate static var clearKeychainRoute: ActionRoute { get {
    return ActionRoute.post(EventName.ClearKeychain) { json in
      let bundleID = try json.getValue("bundle_id").getString()
      return Action.clearKeychain(bundleID)
    }
  }}

  fileprivate static var configRoute: ActionRoute { get {
    return ActionRoute.get(EventName.Config, action: Action.config)
  }}

  fileprivate static var diagnoseRoute: ActionRoute { get {
    return ActionRoute.post(EventName.Diagnose) { json in
      let query = try FBSimulatorDiagnosticQuery.inflate(fromJSON: json.decode())
      return Action.diagnose(query, DiagnosticFormat.Content)
    }
  }}

  fileprivate static var launchRoute: ActionRoute { get {
    return ActionRoute.post(EventName.Launch) { json in
      if let agentLaunch = try? FBAgentLaunchConfiguration.inflate(fromJSON: json.decode()) {
        return Action.launchAgent(agentLaunch)
      }
      if let appLaunch = try? FBApplicationLaunchConfiguration.inflate(fromJSON: json.decode()) {
        return Action.launchApp(appLaunch)
      }

      throw JSONError.parse("Could not parse \(json) either an Agent or App Launch")
    }
  }}

  fileprivate static var listRoute: ActionRoute { get {
    return ActionRoute.get(EventName.List, action: Action.list)
  }}

  fileprivate static var openRoute: ActionRoute { get {
    return ActionRoute.post(EventName.Open) { json in
      let urlString = try json.getValue("url").getString()
      guard let url = URL(string: urlString) else {
        throw JSONError.parse("\(urlString) is not a valid URL")
      }
      return Action.open(url)
    }
  }}

  fileprivate static var recordRoute: ActionRoute { get {
    return ActionRoute.post(EventName.Record) { json in
      let start = try json.getValue("start").getBool()
      return Action.record(start)
    }
  }}

  fileprivate static var relaunchRoute: ActionRoute { get {
    return ActionRoute.post(EventName.Relaunch) { json in
      let launchConfiguration = try FBApplicationLaunchConfiguration.inflate(fromJSON: json.decode())
      return Action.relaunch(launchConfiguration)
    }
  }}

  fileprivate static var searchRoute: ActionRoute { get {
    return ActionRoute.post(EventName.Search) { json in
      let search = try FBBatchLogSearch.inflate(fromJSON: json.decode())
      return Action.search(search)
    }
  }}

  fileprivate static var setLocationRoute: ActionRoute { get {
    return ActionRoute.post(EventName.SetLocation) { json in
      let latitude = try json.getValue("latitude").getNumber().doubleValue
      let longitude = try json.getValue("longitude").getNumber().doubleValue
      return Action.setLocation(latitude, longitude)
    }
  }}

  fileprivate static var tapRoute: ActionRoute { get {
    return ActionRoute.post(EventName.Tap) { json in
      let x = try json.getValue("x").getNumber().doubleValue
      let y = try json.getValue("y").getNumber().doubleValue
      return Action.tap(x, y)
    }
  }}

  fileprivate static var terminateRoute: ActionRoute { get {
    return ActionRoute.post(EventName.Terminate) { json in
      let bundleID = try json.getValue("bundle_id").getString()
      return Action.terminate(bundleID)
    }
  }}

  fileprivate static var uploadRoute: ActionRoute { get {
    let jsonToDiagnostics:(JSON)throws -> [FBDiagnostic] = { json in
      switch json {
      case .jArray(let array):
        let diagnostics = try array.map { jsonDiagnostic in
          return try FBDiagnostic.inflate(fromJSON: jsonDiagnostic.decode())
        }
        return diagnostics
      case .jDictionary:
        let diagnostic = try FBDiagnostic.inflate(fromJSON: json.decode())
        return [diagnostic]
      default:
        throw JSONError.parse("Unparsable Diagnostic")
      }
    }

    return ActionRoute.post(EventName.Upload) { json in
      return Action.upload(try jsonToDiagnostics(json))
    }
  }}

  fileprivate static var actionRoutes: [ActionRoute] { get {
    return [
      self.clearKeychainRoute,
      self.configRoute,
      self.diagnoseRoute,
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
    ]
  }}
}
