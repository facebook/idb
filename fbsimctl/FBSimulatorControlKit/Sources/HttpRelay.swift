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

  private func registerRoutes() {
    registerRoutes([
      ("relaunch", { json in
        let bundleID = try json.getValue("bundle_id").getString()
        let bundleName = try json.getValue("bundle_name").getString()
        let arguments = try json.getValue("arguments").getArrayOfStrings()
        let environment = try json.getValue("environment").getDictionaryOfStrings()
        let launchConfiguration = FBApplicationLaunchConfiguration(
          bundleID: bundleID, bundleName: bundleName, arguments: arguments, environment: environment
        )
        return Action.Relaunch(launchConfiguration)
      }),
      ("terminate", { json in
        let bundleID = try json.getValue("bundle_id").getString()
        return Action.Terminate(bundleID)
      }),
      ("record", { json in
        let start = try json.getValue("start").getBool()
        return Action.Record(start)
      }),
    ])
  }

  private func registerRoutes(routes: [(String, JSON throws -> Action)]) {
    for (endpoint, parser) in routes {
      self.registerActionMapping(endpoint, parser: parser)
    }
  }

  private func registerActionMapping(endpoint: String, parser: JSON throws -> Action) {
    self.httpServer.POST["/" + endpoint] = { [unowned self] request in
      do {
        let action = try HttpRelay.actionFromRequest(request, parser: parser)
        return self.dispatchAction(action)
      } catch let error as JSONError {
        return self.errorResponse(error.description)
      } catch {
        return self.errorResponse(nil)
      }
    }
  }

  private static func actionFromRequest(request: HttpRequest, parser: JSON throws -> Action) throws -> Action {
    let body = request.body
    let data = NSData(bytes: body, length: body.count)
    let json = try JSON.fromData(data)
    return try parser(json)
  }

  private func dispatchAction(action: Action) -> HttpResponse {
    let reporter = HttpEventReporter()
    var result = CommandResult.Success
    dispatch_sync(dispatch_get_main_queue()) {
      result = self.performer.perform(action, reporter: reporter)
    }

    return self.interactionResultResponse(reporter, result: result)
  }

  private func errorResponse(errorMessage: String?) -> HttpResponse {
    let json = JSON.JDictionary([
      "status" : JSON.JString("failure"),
      "message": JSON.JString(errorMessage ?? "Unknown Error")
    ])
    return HttpResponse.BadRequest(.Json(json.decode()))
  }

  private func interactionResultResponse(eventReporter: HttpEventReporter, result: CommandResult) -> HttpResponse {
    switch result {
    case .Failure(let string):
      let json = JSON.JDictionary([
        "status" : JSON.JString("failure"),
        "message": JSON.JString(string),
        "events" : eventReporter.jsonDescription
      ])
      return HttpResponse.BadRequest(.Json(json.decode()))
    case .Success:
      let json = JSON.JDictionary([
        "status" : JSON.JString("success"),
        "events" : eventReporter.jsonDescription
      ])
      return HttpResponse.OK(.Json(json.decode()))
    }
  }
}

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
}
