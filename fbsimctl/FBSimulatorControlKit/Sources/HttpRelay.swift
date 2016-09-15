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

private class HttpEventReporter : EventReporter {
  var events: [EventReporterSubject] = []

  private func report(subject: EventReporterSubject) {
    self.events.append(subject)
  }

  var jsonDescription: JSON { get {
    return JSON.JArray(self.events.map { $0.jsonDescription })
  }}

  static func errorResponse(errorMessage: String?) -> HttpResponse {
    let json = JSON.JDictionary([
      "status" : JSON.JString("failure"),
      "message": JSON.JString(errorMessage ?? "Unknown Error")
    ])
    return HttpResponse.internalServerError(json.data)
  }

  func interactionResultResponse(result: CommandResult) -> HttpResponse {
    switch result {
    case .Failure(let string):
      let json = JSON.JDictionary([
        "status" : JSON.JString("failure"),
        "message": JSON.JString(string),
        "events" : self.jsonDescription
      ])
      return HttpResponse.internalServerError(json.data)
    case .Success:
      let json = JSON.JDictionary([
        "status" : JSON.JString("success"),
        "events" : self.jsonDescription
      ])
      return HttpResponse.ok(json.data)
    }
  }
}

extension ActionPerformer {
  func dispatchAction(action: Action, queryOverride: FBiOSTargetQuery? = nil, formatOverride: FBiOSTargetFormat? = nil) -> HttpResponse {
    let reporter = HttpEventReporter()
    var result: CommandResult? = nil
    dispatch_sync(dispatch_get_main_queue()) {
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
  let method: HttpMethod
  let endpoint: EventName
  let actionParser: JSON throws -> Action

  func httpRoute(performer: ActionPerformer) -> HttpRoute {
    let actionParser = self.actionParser
    return HttpRoute(method: self.method.rawValue, path: "/" + self.endpoint.rawValue) { request in
      do {
        let json = try request.jsonBody()
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
  let httpServer: HttpServer
  let performer: ActionPerformer

  init(portNumber: in_port_t, performer: ActionPerformer) {
    self.portNumber = portNumber
    self.performer = performer

    self.httpServer = HttpServer(
      port: portNumber,
      routes: HttpRelay.actionRoutes.map { $0.httpRoute(performer) }
    )
  }

  func start() throws {
    do {
      try self.httpServer.start()
    } catch let error as NSError {
      throw HttpRelay.Error(message: "An Error occurred starting the HTTP Server on Port \(self.portNumber): \(error.description)")
    }
  }

  func stop() {
    self.httpServer.stop()
  }

  private static var clearKeychainRoute: ActionRoute { get {
    return ActionRoute(method: HttpMethod.POST, endpoint: EventName.ClearKeychain) { json in
      let bundleID = try json.getValue("bundle_id").getString()
      return Action.ClearKeychain(bundleID)
    }
  }}

  private static var diagnoseRoute: ActionRoute { get {
    return ActionRoute(method: HttpMethod.POST, endpoint: EventName.Diagnose) { json in
      let query = try FBSimulatorDiagnosticQuery.inflateFromJSON(json.decode())
      return Action.Diagnose(query, DiagnosticFormat.Content)
    }
  }}

  private static var launchRoute: ActionRoute { get {
    return ActionRoute(method: HttpMethod.POST, endpoint: EventName.Launch) { json in
      if let agentLaunch = try? FBAgentLaunchConfiguration.inflateFromJSON(json.decode()) {
        return Action.LaunchAgent(agentLaunch)
      }
      if let appLaunch = try? FBApplicationLaunchConfiguration.inflateFromJSON(json.decode()) {
        return Action.LaunchApp(appLaunch)
      }

      throw JSONError.Parse("Could not parse \(json) either an Agent or App Launch")
    }
  }}

  private static var listRoute: ActionRoute { get {
    return ActionRoute(method: HttpMethod.POST, endpoint: EventName.List) { _ in
      return Action.List
    }
  }}

  private static var openRoute: ActionRoute { get {
    return ActionRoute(method: HttpMethod.POST, endpoint: EventName.Open) { json in
      let urlString = try json.getValue("url").getString()
      guard let url = NSURL(string: urlString) else {
        throw JSONError.Parse("\(urlString) is not a valid URL")
      }
      return Action.Open(url)
    }
  }}

  private static var recordRoute: ActionRoute { get {
    return ActionRoute(method: HttpMethod.POST, endpoint: EventName.Record) { json in
      let start = try json.getValue("start").getBool()
      return Action.Record(start)
    }
  }}

  private static var relaunchRoute: ActionRoute { get {
    return ActionRoute(method: HttpMethod.POST, endpoint: EventName.Relaunch) { json in
      let launchConfiguration = try FBApplicationLaunchConfiguration.inflateFromJSON(json.decode())
      return Action.Relaunch(launchConfiguration)
    }
  }}

  private static var searchRoute: ActionRoute { get {
    return ActionRoute(method: HttpMethod.POST, endpoint: EventName.Search) { json in
      let search = try FBBatchLogSearch.inflateFromJSON(json.decode())
      return Action.Search(search)
    }
  }}

  private static var setLocationRoute: ActionRoute { get {
    return ActionRoute(method: HttpMethod.POST, endpoint: EventName.SetLocation) { json in
      let latitude = try json.getValue("latitude").getNumber().doubleValue
      let longitude = try json.getValue("longitude").getNumber().doubleValue
      return Action.SetLocation(latitude, longitude)
    }
  }}

  private static var tapRoute: ActionRoute { get {
    return ActionRoute(method: HttpMethod.POST, endpoint: EventName.Tap) { json in
      let x = try json.getValue("x").getNumber().doubleValue
      let y = try json.getValue("y").getNumber().doubleValue
      return Action.Tap(x, y)
    }
  }}

  private static var terminateRoute: ActionRoute { get {
    return ActionRoute(method: HttpMethod.POST, endpoint: EventName.Terminate) { json in
      let bundleID = try json.getValue("bundle_id").getString()
      return Action.Terminate(bundleID)
    }
  }}

  private static var uploadRoute: ActionRoute { get {
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

    return ActionRoute(method: HttpMethod.POST, endpoint: EventName.Upload) { json in
      return Action.Upload(try jsonToDiagnostics(json))
    }
  }}

  private static var actionRoutes: [ActionRoute] { get {
    return [
      self.clearKeychainRoute,
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
