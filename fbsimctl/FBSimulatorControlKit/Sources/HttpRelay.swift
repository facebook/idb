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
  func dispatchAction(action: Action) -> HttpResponse {
    let reporter = HttpEventReporter()
    var result = CommandResult.Success
    dispatch_sync(dispatch_get_main_queue()) {
      result = self.perform(action, reporter: reporter)
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
        let action = try HttpRoute.actionFromRequest(request, actionParser: actionParser)
        return performer.dispatchAction(action)
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

  static func actionFromRequest(request: HttpRequest, actionParser: JSON throws -> Action) throws -> Action {
    let body = request.body
    let data = NSData(bytes: body, length: body.count)
    let json = try JSON.fromData(data)
    return try actionParser(json)
  }
}

class HttpRelay : Relay {
  let portNumber: in_port_t
  let httpServer: Swifter.HttpServer
  let performer: ActionPerformer
  let reporter: RelayReporter

  init(portNumber: in_port_t, performer: ActionPerformer, reporter: RelayReporter) {
    self.portNumber = portNumber
    self.performer = performer
    self.httpServer = Swifter.HttpServer()
    self.reporter = reporter
    self.registerRoutes()
  }

  func start() {
    do {
      try self.httpServer.start(self.portNumber)
      self.reporter.started()
      SignalHandler.runUntilSignalled(self.reporter.reporter)
      self.reporter.ended(nil)
    } catch {
      self.reporter.ended("An Error occurred starting the HTTP Server on Port \(self.portNumber)")
    }
  }

  func stop() {
    self.httpServer.stop()
  }

  private var relaunchRoute: HttpRoute { get {
    return HttpRoute(method: HttpMethod.POST, endpoint: "relaunch") { json in
      let launchConfiguration = try FBApplicationLaunchConfiguration.inflateFromJSON(json.decode())
      return Action.Relaunch(launchConfiguration)
    }
  }}

  private var terminateRoute: HttpRoute { get {
    return HttpRoute(method: HttpMethod.POST, endpoint: "terminate") { json in
      let bundleID = try json.getValue("bundle_id").getString()
      return Action.Terminate(bundleID)
    }
  }}

  private var recordRoute: HttpRoute { get {
    return HttpRoute(method: HttpMethod.POST, endpoint: "record") { json in
      let start = try json.getValue("start").getBool()
      return Action.Record(start)
    }
  }}

  private var diagnoseRoute: HttpRoute { get {
    return HttpRoute(method: HttpMethod.POST, endpoint: "diagnose") { json in
      let query = try FBSimulatorDiagnosticQuery.inflateFromJSON(json.decode())
      return Action.Diagnose(query, DiagnosticFormat.Content)
    }
  }}

  private var searchRoute: HttpRoute { get {
    return HttpRoute(method: HttpMethod.POST, endpoint: "search") { json in
      let search = try FBBatchLogSearch.inflateFromJSON(json.decode())
      return Action.Search(search)
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
      self.relaunchRoute,
      self.terminateRoute,
      self.recordRoute,
      self.diagnoseRoute,
      self.searchRoute,
      self.uploadRoute
    ]
  }}

  private func registerRoutes() {
    for route in self.routes {
      route.mount(self.httpServer, performer: self.performer)
    }
  }
}
