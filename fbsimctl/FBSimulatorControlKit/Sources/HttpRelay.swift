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
import Swifter

private class HttpEventReporter : EventReporter, JSONDescribeable {
  var events: [EventReporterSubject] = []

  private func report(subject: EventReporterSubject) {
    self.events.append(subject)
  }

  var jsonDescription: JSON {
    get {
      return JSON.JArray(self.events.map { $0.jsonDescription })
    }
  }

  static func errorResponse(errorMessage: String?) -> HttpResponse {
    let json = JSON.JDictionary([
      "status" : JSON.JString("failure"),
      "message": JSON.JString(errorMessage ?? "Unknown Error")
    ])
    return HttpResponse.BadRequest(.Json(json.decode()))
  }

  func interactionResultResponse(result: CommandResult) -> HttpResponse {
    switch result {
    case .Failure(let string):
      let json = JSON.JDictionary([
        "status" : JSON.JString("failure"),
        "message": JSON.JString(string),
        "events" : self.jsonDescription
      ])
      return HttpResponse.BadRequest(.Json(json.decode()))
    case .Success:
      let json = JSON.JDictionary([
        "status" : JSON.JString("success"),
        "events" : self.jsonDescription
      ])
      return HttpResponse.OK(.Json(json.decode()))
    }
  }
}

extension ActionPerformer {
  func dispatchAction(action: Action, queryOverride: FBiOSTargetQuery? = nil, formatOverride: Format? = nil) -> HttpResponse {
    let reporter = HttpEventReporter()
    var result = CommandResult.Success
    dispatch_sync(dispatch_get_main_queue()) {
      result = self.perform(reporter, action: action, queryOverride: queryOverride)
    }

    return reporter.interactionResultResponse(result)
  }
}

enum HttpMethod {
  case GET
  case POST
}

struct HttpRoute {
  let method: HttpMethod
  let endpoint: String
  let actionParser: JSON throws -> Action

  func mount(server: Swifter.HttpServer, performer: ActionPerformer) {
    let actionParser = self.actionParser
    let handler: Swifter.HttpRequest -> Swifter.HttpResponse = { request in
      do {
        let json = try HttpRoute.jsonBodyFromRequest(request)
        let action = try actionParser(json)
        let query = try? FBiOSTargetQuery.inflateFromJSON(json.getValue("simulators").decode())
        return performer.dispatchAction(action, queryOverride: query)
      } catch let error as JSONError {
        return HttpEventReporter.errorResponse(error.description)
      } catch let error as NSError {
        return HttpEventReporter.errorResponse(error.description)
      } catch {
        return HttpEventReporter.errorResponse(nil)
      }
    }

    switch self.method {
    case .GET:
      server.GET["/" + self.endpoint] = handler
    case .POST:
      server.POST["/" + self.endpoint] = handler
    }
  }

  static func jsonBodyFromRequest(request: HttpRequest) throws -> JSON {
    let body = request.body
    let data = NSData(bytes: body, length: body.count)
    return try JSON.fromData(data)
  }
}

class HttpRelay : Relay {
  struct Error : ErrorType, CustomStringConvertible {
    let message: String

    var description: String { get {
      return message
    }}
  }

  let portNumber: in_port_t
  let httpServer: Swifter.HttpServer
  let performer: ActionPerformer

  init(portNumber: in_port_t, performer: ActionPerformer) {
    self.portNumber = portNumber
    self.performer = performer
    self.httpServer = Swifter.HttpServer()
  }

  func start() throws {
    do {
      self.registerRoutes()
      try self.httpServer.start(self.portNumber)
    } catch {
      throw HttpRelay.Error(message: "An Error occurred starting the HTTP Server on Port \(self.portNumber)")
    }
  }

  func stop() {
    self.httpServer.stop()
  }

  private var clearKeychainRoute: HttpRoute { get {
    return HttpRoute(method: HttpMethod.POST, endpoint: "clear_keychain") { json in
      let bundleID = try json.getValue("bundle_id").getString()
      return Action.ClearKeychain(bundleID)
    }
  }}

  private var diagnoseRoute: HttpRoute { get {
    return HttpRoute(method: HttpMethod.POST, endpoint: "diagnose") { json in
      let query = try FBSimulatorDiagnosticQuery.inflateFromJSON(json.decode())
      return Action.Diagnose(query, DiagnosticFormat.Content)
    }
  }}

  private var openRoute: HttpRoute { get {
    return HttpRoute(method: HttpMethod.POST, endpoint: "open") { json in
      let urlString = try json.getValue("url").getString()
      guard let url = NSURL(string: urlString) else {
        throw JSONError.Parse("\(urlString) is not a valid URL")
      }
      return Action.Open(url)
    }
  }}

  private var recordRoute: HttpRoute { get {
    return HttpRoute(method: HttpMethod.POST, endpoint: "record") { json in
      let start = try json.getValue("start").getBool()
      return Action.Record(start)
    }
  }}

  private var launchRoute: HttpRoute { get {
    return HttpRoute(method: HttpMethod.POST, endpoint: "launch") { json in
      if let agentLaunch = try? FBAgentLaunchConfiguration.inflateFromJSON(json.decode()) {
        return Action.LaunchAgent(agentLaunch)
      }
      if let appLaunch = try? FBApplicationLaunchConfiguration.inflateFromJSON(json.decode()) {
        return Action.LaunchApp(appLaunch)
      }

      throw JSONError.Parse("Could not parse \(json) either an Agent or App Launch")
    }
  }}

  private var relaunchRoute: HttpRoute { get {
    return HttpRoute(method: HttpMethod.POST, endpoint: "relaunch") { json in
      let launchConfiguration = try FBApplicationLaunchConfiguration.inflateFromJSON(json.decode())
      return Action.Relaunch(launchConfiguration)
    }
  }}

  private var searchRoute: HttpRoute { get {
    return HttpRoute(method: HttpMethod.POST, endpoint: "search") { json in
      let search = try FBBatchLogSearch.inflateFromJSON(json.decode())
      return Action.Search(search)
    }
  }}

  private var tapRoute: HttpRoute { get {
    return HttpRoute(method: HttpMethod.POST, endpoint: EventName.Tap.rawValue) { json in
      let x = try json.getValue("x").getNumber().doubleValue
      let y = try json.getValue("y").getNumber().doubleValue
      return Action.Tap(x, y)
    }
  }}

  private var terminateRoute: HttpRoute { get {
    return HttpRoute(method: HttpMethod.POST, endpoint: "terminate") { json in
      let bundleID = try json.getValue("bundle_id").getString()
      return Action.Terminate(bundleID)
    }
  }}

  private var uploadRoute: HttpRoute { get {
    let jsonToDiagnostics: JSON throws -> [FBDiagnostic] = { json in
      switch json {
      case .JArray(let array):
        let diagnostics = try array.map { jsonDiagnostic in
          return try FBDiagnostic.inflateFromJSON(jsonDiagnostic.decode())
        }
        return diagnostics
      case .JDictionary:
        let diagnostic = try FBDiagnostic.inflateFromJSON(json.decode())
        return [diagnostic]
      default:
        throw JSONError.Parse("Unparsable Diagnostic")
      }
    }

    return HttpRoute(method: HttpMethod.POST, endpoint: "upload") { json in
      return Action.Upload(try jsonToDiagnostics(json))
    }
  }}

  private var routes: [HttpRoute] { get {
    return [
      self.clearKeychainRoute,
      self.diagnoseRoute,
      self.launchRoute,
      self.openRoute,
      self.recordRoute,
      self.relaunchRoute,
      self.searchRoute,
      self.tapRoute,
      self.terminateRoute,
      self.uploadRoute
    ]
  }}

  private func registerRoutes() {
    for route in self.routes {
      route.mount(self.httpServer, performer: self.performer)
    }
  }
}
