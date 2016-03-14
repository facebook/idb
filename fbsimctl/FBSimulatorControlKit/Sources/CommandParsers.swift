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

extension Parser {
  public static var ofInt: Parser<Int> { get {
    return Parser<Int>.single("Of Int") { token in
      guard let integer = NSNumberFormatter().numberFromString(token)?.integerValue else {
        throw ParseError.CouldNotInterpret("Int", token)
      }
      return integer
    }
  }}

  public static var ofDouble: Parser<Double> { get {
    return Parser<Double>.single("Of Double") { token in
      guard let double = NSNumberFormatter().numberFromString(token)?.doubleValue else {
        throw ParseError.CouldNotInterpret("Double", token)
      }
      return double
    }
  }}

  public static var ofAny: Parser<String> { get {
    return Parser<String>.single("Anything", f: { $0 } )
  }}

  public static var ofUDID: Parser<NSUUID> { get {
    let expected = NSStringFromClass(NSUUID.self)
    return Parser<NSUUID>.single("A \(expected)") { token in
      guard let uuid = NSUUID(UUIDString: token) else {
        throw ParseError.CouldNotInterpret(expected, token)
      }
      return uuid
    }
  }}

  public static var ofDirectory: Parser<String> { get {
    let expected = "A Directory"
    return Parser<String>.single(expected) { token  in
      let path = (token as NSString).stringByStandardizingPath
      var isDirectory: ObjCBool = false
      if !NSFileManager.defaultManager().fileExistsAtPath(path, isDirectory: &isDirectory) {
        throw ParseError.Custom("'\(path)' should exist, but doesn't")
      }
      if (!isDirectory) {
        throw ParseError.Custom("'\(path)' should be a directory, but isn't")
      }
      return path
    }
  }}

  public static var ofFile: Parser<String> { get {
    let expected = "A File"
    return Parser<String>.single(expected) { token in
      let path = (token as NSString).stringByStandardizingPath
      var isDirectory: ObjCBool = false
      if !NSFileManager.defaultManager().fileExistsAtPath(path, isDirectory: &isDirectory) {
        throw ParseError.Custom("'\(path)' should exist, but doesn't")
      }
      if (isDirectory) {
        throw ParseError.Custom("'\(path)' should be a file, but isn't")
      }
      return path
    }
  }}

  public static var ofApplication: Parser<FBSimulatorApplication> { get {
    let expected = "An Application"
    return Parser<FBSimulatorApplication>.single(expected) { token in
      do {
        return try FBSimulatorApplication(path: token)
      } catch let error as NSError {
        throw ParseError.Custom("Could not get an app \(token) \(error.description)")
      }
    }
  }}

  public static var ofBinary: Parser<FBSimulatorBinary> { get {
    let expected = "A Binary"
    return Parser<FBSimulatorBinary>.single(expected) { token in
      do {
        return try FBSimulatorBinary(path: token)
      } catch let error as NSError {
        throw ParseError.Custom("Could not get an binary \(token) \(error.description)")
      }
    }
  }}

  public static var ofLocale: Parser<NSLocale> { get {
    let expected = "A Locale"
    return Parser<NSLocale>.single(expected) { token in
      return NSLocale(localeIdentifier: token)
    }
  }}

  public static var ofBundleID: Parser<String> { get {
    return Parser<String>
      .alternative([
        Parser.ofApplication.fmap { $0.bundleID },
        Parser<String>.single("A Bundle ID") { token in
          let components = token.componentsSeparatedByCharactersInSet(NSCharacterSet(charactersInString: "."))
          if components.count < 2 {
            throw ParseError.Custom("Bundle ID must contain a '.'")
          }
          return token
        }
      ])
  }}

  public static var ofDate: Parser<NSDate> { get {
    return Parser<NSDate>.ofDouble.fmap { NSDate(timeIntervalSince1970: $0) }
  }}
}

extension OutputOptions : Parsable {
  public static var parser: Parser<OutputOptions> { get {
    return Parser<OutputOptions>
      .unionOptions([
        Parser.ofString("--debug-logging", OutputOptions.DebugLogging),
        Parser.ofString("--json", OutputOptions.JSON),
        Parser.ofString("---pretty", OutputOptions.Pretty)
      ])
  }}
}

extension Configuration : Parsable {
  public static var parser: Parser<Configuration> { get {
    return Parser
      .ofThreeSequenced(
        OutputOptions.parser,
        Parser.succeeded("--set", Parser<Any>.ofDirectory).optional(),
        FBSimulatorManagementOptions.parser
      )
      .fmap { (output, deviceSetPath, managementOptions) in
        return Configuration(output: output, deviceSetPath: deviceSetPath, managementOptions: managementOptions)
      }
  }}
}

extension FBSimulatorState : Parsable {
  public static var parser: Parser<FBSimulatorState> { get {
    return Parser.alternative([
        Parser.ofString("--state=creating", FBSimulatorState.Creating),
        Parser.ofString("--state=shutdown", FBSimulatorState.Shutdown),
        Parser.ofString("--state=booting", FBSimulatorState.Booting),
        Parser.ofString("--state=booted", FBSimulatorState.Booted),
        Parser.ofString("--state=shutting-down", FBSimulatorState.ShuttingDown),
    ])
  }}
}

extension Command : Parsable {
  public static var parser: Parser<Command> { get {
    return Parser
      .alternative([
        self.helpParser,
        self.performParser,
      ])
  }}

  static var performParser: Parser<Command> { get {
    return Parser
      .ofFourSequenced(
        Configuration.parser,
        Query.parser.optional(),
        Format.parser.optional(),
        Parser.manyCount(1, Action.parser)
      )
      .fmap { (configuration, query, format, actions) in
        return Command.Perform(configuration, actions, query, format)
      }
  }}

  static var helpParser: Parser<Command> { get {
    return Parser
      .ofTwoSequenced(
        OutputOptions.parser,
        Parser.ofString("help", NSNull())
      )
      .fmap { (output, _) in
        return Command.Help(output, true, nil)
      }
  }}
}

extension FBSimulatorManagementOptions : Parsable {
  public static var parser: Parser<FBSimulatorManagementOptions> { get {
    return Parser<FBSimulatorManagementOptions>
      .unionOptions([
        self.deleteAllOnFirstParser,
        self.killAllOnFirstParser,
        self.killSpuriousSimulatorsOnFirstStartParser,
        self.ignoreSpuriousKillFailParser,
        self.killSpuriousCoreSimulatorServicesParser,
        self.useSimDeviceTimeoutResilianceParser
      ])
  }}

  static var deleteAllOnFirstParser: Parser<FBSimulatorManagementOptions> { get {
    return Parser.ofString("--delete-all", .DeleteAllOnFirstStart)
  }}

  static var killAllOnFirstParser: Parser<FBSimulatorManagementOptions> { get {
    return Parser.ofString("--kill-all", .KillAllOnFirstStart)
  }}

  static var killSpuriousSimulatorsOnFirstStartParser: Parser<FBSimulatorManagementOptions> { get {
    return Parser.ofString("--kill-spurious", .KillSpuriousSimulatorsOnFirstStart)
  }}

  static var ignoreSpuriousKillFailParser: Parser<FBSimulatorManagementOptions> { get {
    return Parser.ofString("--ignore-spurious-kill-fail", .IgnoreSpuriousKillFail)
  }}

  static var killSpuriousCoreSimulatorServicesParser: Parser<FBSimulatorManagementOptions> { get {
    return Parser.ofString("--kill-spurious-services", .KillSpuriousCoreSimulatorServices)
  }}

  static var useSimDeviceTimeoutResilianceParser: Parser<FBSimulatorManagementOptions> { get {
    return Parser.ofString("--timeout-resiliance", .UseSimDeviceTimeoutResiliance)
  }}
}

extension Server : Parsable {
  public static var parser: Parser<Server> { get {
    return Parser
      .alternative([
        self.socketParser,
        self.httpParser
      ])
      .fallback(Server.StdIO)
  }}

  static var socketParser: Parser<Server> { get {
    return Parser
      .succeeded("--socket", Parser<Int>.ofInt)
      .fmap { portNumber in
        return Server.Socket(UInt16(portNumber))
      }
  }}

  static var httpParser:  Parser<Server> { get {
    return Parser
      .succeeded("--http", Parser<Int>.ofInt)
      .fmap { portNumber in
        return Server.Http(UInt16(portNumber))
      }
  }}
}

extension DiagnosticQuery : Parsable {
  public static var parser: Parser<DiagnosticQuery> { get {
    return Parser
      .alternative([
        self.appFilesParser,
        self.namedParser,
        self.crashesParser,
      ])
      .fallback(DiagnosticQuery.Default)
  }}

  static var namedParser: Parser<DiagnosticQuery> { get {
    return Parser
      .manyCount(1, Parser.succeeded("--name", Parser<Any>.ofAny))
      .fmap { DiagnosticQuery.Named($0) }
  }}

  static var crashesParser: Parser<DiagnosticQuery> { get {
    return Parser
      .succeeded("--crashes-since", Parser<Any>.ofDate)
      .fmap { DiagnosticQuery.Crashes($0) }
  }}

  static var appFilesParser: Parser<DiagnosticQuery> { get {
    return Parser
      .ofTwoSequenced(
        Parser<Any>.ofBundleID,
        Parser.manyCount(1, Parser<Any>.ofAny)
      )
      .fmap { (bundleID, fileNames) in
        DiagnosticQuery.AppFiles(bundleID, fileNames)
      }
  }}
}

extension Action : Parsable {
  public static var parser: Parser<Action> { get {
    return Parser
      .alternative([
        self.approveParser,
        self.bootParser,
        self.createParser,
        self.deleteParser,
        self.diagnoseParser,
        self.installParser,
        self.launchParser,
        self.listenParser,
        self.listParser,
        self.recordParser,
        self.relaunchParser,
        self.shutdownParser,
        self.terminateParser,
        self.uploadParser,
      ])
  }}

  static var approveParser: Parser<Action> { get {
    return Parser
      .succeeded(EventName.Approve.rawValue, Parser.manyCount(1, Parser<Any>.ofBundleID))
      .fmap { Action.Approve($0) }
  }}

  static var bootParser: Parser<Action> { get {
    return Parser
      .succeeded(EventName.Boot.rawValue, FBSimulatorLaunchConfigurationParser.parser.optional())
      .fmap { Action.Boot($0) }
  }}

  static var createParser: Parser<Action> { get {
    return Parser
      .succeeded(EventName.Create.rawValue, FBSimulatorConfigurationParser.parser)
      .fmap { configuration in
        return Action.Create(configuration)
    }
  }}

  static var deleteParser: Parser<Action> { get {
    return Parser.ofString(EventName.Delete.rawValue, Action.Delete)
  }}

  static var diagnoseParser: Parser<Action> { get {
    return Parser
      .succeeded(EventName.Diagnose.rawValue, DiagnosticQuery.parser)
      .fmap { Action.Diagnose($0) }
  }}

  static var launchParser: Parser<Action> { get {
    return Parser
      .succeeded(EventName.Launch.rawValue, self.processLaunchParser)
      .fmap { Action.Launch($0) }
  }}

  static var listenParser: Parser<Action> { get {
    return Parser
      .succeeded(EventName.Listen.rawValue, Server.parser)
      .fmap { Action.Listen($0) }
  }}

  static var listParser: Parser<Action> { get {
    return Parser.ofString(EventName.List.rawValue, Action.List)
  }}

  static var installParser: Parser<Action> { get {
    return Parser
      .succeeded(EventName.Install.rawValue, Parser<Any>.ofApplication)
      .fmap { Action.Install($0) }
  }}

  static var relaunchParser: Parser<Action> { get {
    return Parser
      .succeeded(EventName.Relaunch.rawValue, self.appLaunchParser)
      .fmap { Action.Relaunch($0 as! FBApplicationLaunchConfiguration) }
  }}

  static var recordParser: Parser<Action> { get {
    return Parser
      .succeeded(EventName.Record.rawValue, Parser.alternative([
        Parser.ofString("start", true),
        Parser.ofString("stop", false)
      ]))
      .fmap { Action.Record($0) }
  }}

  static var shutdownParser: Parser<Action> { get {
    return Parser.ofString(EventName.Shutdown.rawValue, Action.Shutdown)
  }}

  static var terminateParser: Parser<Action> { get {
    return Parser
      .succeeded(EventName.Terminate.rawValue, Parser<Any>.ofBundleID)
      .fmap { Action.Terminate($0) }
  }}

  static var uploadParser: Parser<Action> { get {
    return Parser
      .succeeded(
        EventName.Upload.rawValue,
        Parser.manyCount(1, Parser<Any>.ofFile)
      )
      .fmap { paths in
        let diagnostics: [FBDiagnostic] = paths.map { path in
          return FBDiagnosticBuilder().updatePath(path).build()
        }
        return Action.Upload(diagnostics)
      }
  }}

  static var processLaunchParser: Parser<FBProcessLaunchConfiguration> { get {
    return Parser<FBProcessLaunchConfiguration>
      .alternative([
        self.agentLaunchParser,
        self.appLaunchParser,
      ])
  }}

  static var agentLaunchParser: Parser<FBProcessLaunchConfiguration> { get {
    return Parser
      .ofTwoSequenced(
        Parser<Any>.ofBinary,
        self.argumentParser
      )
      .fmap { (binary, arguments) in
        return FBAgentLaunchConfiguration(binary: binary, arguments: arguments, environment : [:])
      }
  }}

  static var appLaunchParser: Parser<FBProcessLaunchConfiguration> { get {
    return Parser
      .ofTwoSequenced(
        Parser<Any>.ofBundleID,
        self.argumentParser
      )
      .fmap { (bundleID, arguments) in
        return FBApplicationLaunchConfiguration(bundleID: bundleID, bundleName: nil, arguments: arguments, environment : [:])
      }
  }}

  static var argumentParser: Parser<[String]> { get {
    return Parser.many(Parser<String>.ofAny)
  }}
}

extension Query : Parsable {
  public static var parser: Parser<Query> { get {
    return Parser.alternative([
      self.allParser,
      self.specificParser
    ])
  }}

  static var allParser: Parser<Query> { get {
    return Parser<Query>
      .ofString("all", Query.And([]))
  }}

  static var specificParser: Parser<Query> { get {
    return Parser<Query>
      .alternativeMany(1, [
        self.simulatorStateParser,
        self.uuidParser,
        self.simulatorConfigurationParser
      ])
      .fmap { Query.flatten($0) }
  }}

  static var uuidParser: Parser<Query> { get {
    return Parser<Query>
      .ofUDID
      .fmap { Query.UDID([$0.UUIDString]) }
  }}

  static var simulatorStateParser: Parser<Query> { get {
    return FBSimulatorState
      .parser
      .fmap { Query.State([$0]) }
  }}

  static var simulatorConfigurationParser: Parser<Query> { get {
    return FBSimulatorConfigurationParser
      .parser
      .fmap { configuration in
        Query.Configured(Set([configuration]))
      }
  }}
}

extension Keyword : Parsable {
  public static var parser: Parser<Keyword> { get {
    return Parser
      .alternative([
        Parser.ofString(Keyword.UDID.rawValue, Keyword.UDID),
        Parser.ofString(Keyword.Name.rawValue, Keyword.Name),
        Parser.ofString(Keyword.DeviceName.rawValue, Keyword.DeviceName),
        Parser.ofString(Keyword.OSVersion.rawValue, Keyword.OSVersion),
        Parser.ofString(Keyword.State.rawValue, Keyword.State),
        Parser.ofString(Keyword.ProcessIdentifier.rawValue, Keyword.ProcessIdentifier)
      ])
  }}
}

extension SequenceType where Generator.Element == Keyword {
  public static var parser: Parser<Format> { get {
    return Parser.manyCount(1, Keyword.parser)
  }}
}

/**
 A separate struct for FBSimulatorConfiguration is needed as Parsable protcol conformance cannot be
 applied to FBSimulatorConfiguration as it is a non-final.
 */
struct FBSimulatorConfigurationParser {
  internal static var parser: Parser<FBSimulatorConfiguration> { get {
    return Parser
      .ofThreeSequenced(
        self.deviceParser.optional(),
        self.osVersionParser.optional(),
        self.auxDirectoryParser.optional()
      )
      .fmap { (device, os, auxDirectory) in
        if device == nil && os == nil && auxDirectory == nil {
          throw ParseError.Custom("Simulator Configuration must contain at least one of: Device Name, OS Version or Aux Directory")
        }
        let configuration = FBSimulatorConfiguration.defaultConfiguration().copy() as! FBSimulatorConfiguration
        if let device = device {
          configuration.device = device
        }
        if let os = os {
          configuration.os = os
        }
        if let auxDirectory = auxDirectory {
          configuration.auxillaryDirectory = auxDirectory
        }
        return configuration
      }
  }}

  static var deviceParser: Parser<FBSimulatorConfiguration_Device> { get {
    return Parser.single("A Device Name") { token in
      let nameToDevice = FBSimulatorConfiguration.nameToDevice() as! [String : FBSimulatorConfiguration_Device]
      guard let device = nameToDevice[token] else {
        throw ParseError.Custom("\(token) is not a valid device name")
      }
      return device
    }
  }}

  static var osVersionParser: Parser<FBSimulatorConfiguration_OS> { get {
    return Parser.single("An OS Version") { token in
      let nameToOSVersion = FBSimulatorConfiguration.nameToOSVersion() as! [String : FBSimulatorConfiguration_OS]
      guard let osVersion = nameToOSVersion[token] else {
        throw ParseError.Custom("\(token) is not a valid device name")
      }
      return osVersion
    }
  }}

  static var auxDirectoryParser: Parser<String> { get {
    return Parser.succeeded("--aux", Parser<Any>.ofDirectory)
  }}
}

/**
 A separate struct for FBSimulatorLaunchConfigurationParser is needed as Parsable protcol conformance cannot be
 applied to FBSimulatorLaunchConfiguration as it is a non-final class.
 */
struct FBSimulatorLaunchConfigurationParser {
  static var parser: Parser<FBSimulatorLaunchConfiguration> { get {
    return Parser
      .ofThreeSequenced(
        self.localeParser.optional(),
        self.scaleParser.optional(),
        self.optionsParser.optional()
      )
      .fmap { (locale, scale, options) in
        if locale == nil && scale == nil && options == nil {
          throw ParseError.Custom("Simulator Launch Configuration must contain at least a locale or scale")
        }
        var configuration = FBSimulatorLaunchConfiguration.defaultConfiguration().copy() as! FBSimulatorLaunchConfiguration
        if let locale = locale {
          configuration = configuration.withLocale(locale)
        }
        if let scale = scale {
          configuration = configuration.withScale(scale)
        }
        if let options = options {
          configuration = configuration.withOptions(options)
        }
        return configuration
    }
  }}

  static var localeParser: Parser<NSLocale> { get {
    return Parser
      .succeeded("--locale", Parser<Any>.ofLocale)
  }}

  static var scaleParser: Parser<FBSimulatorLaunchConfiguration_Scale> { get {
    return Parser.alternative([
      Parser.ofString("--scale=25", FBSimulatorLaunchConfiguration_Scale_25()),
      Parser.ofString("--scale=50", FBSimulatorLaunchConfiguration_Scale_50()),
      Parser.ofString("--scale=75", FBSimulatorLaunchConfiguration_Scale_75()),
      Parser.ofString("--scale=100", FBSimulatorLaunchConfiguration_Scale_100())
    ])
  }}

  static var optionsParser: Parser<FBSimulatorLaunchOptions> { get {
    return Parser<FBSimulatorLaunchOptions>
      .unionOptions(1, [
        Parser.ofString("--direct-launch", FBSimulatorLaunchOptions.EnableDirectLaunch),
        Parser.ofString("--debug-window", FBSimulatorLaunchOptions.ShowDebugWindow)
      ])
  }}
}
