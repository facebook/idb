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

  public static var ofURL: Parser<NSURL> { get {
    let expected = NSStringFromClass(NSURL.self)
    return Parser<NSURL>.single("A \(expected)") { token in
      guard let url = NSURL(string: token) else {
        throw ParseError.CouldNotInterpret(expected, token)
      }
      return url
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
    return Parser<OutputOptions>.union(parsers)
  }}

  static var parsers: [Parser<OutputOptions>] { get {
    return [
      Parser.ofString("--debug-logging", OutputOptions.DebugLogging),
      Parser.ofString("--json", OutputOptions.JSON),
      Parser.ofString("---pretty", OutputOptions.Pretty),
    ]
  }}
}

extension FBSimulatorManagementOptions : Parsable {
  public static var parser: Parser<FBSimulatorManagementOptions> { get {
    return Parser<FBSimulatorManagementOptions>.union(self.parsers)
  }}

  static var parsers: [Parser<FBSimulatorManagementOptions>] { get {
    return [
      self.deleteAllOnFirstParser,
      self.killAllOnFirstParser,
      self.killSpuriousSimulatorsOnFirstStartParser,
      self.ignoreSpuriousKillFailParser,
      self.killSpuriousCoreSimulatorServicesParser,
      self.useSimDeviceTimeoutResilianceParser
    ]
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

extension Configuration : Parsable {
  public static var parser: Parser<Configuration> { get {
    let outputOptionsParsers = OutputOptions.parsers.map { $0.fmap(Configuration.ofOutputOptions) }
    let managementOptionsParsers = FBSimulatorManagementOptions.parsers.map { $0.fmap(Configuration.ofManagementOptions) }
    let parsers = Array([outputOptionsParsers, managementOptionsParsers, [self.deviceSetPathParser]].flatten())
    return Parser<Configuration>.accumulate(0, parsers)
  }}

  static var deviceSetPathParser: Parser<Configuration> { get {
    return Parser.succeeded("--set", Parser<Any>.ofDirectory).fmap(Configuration.ofDeviceSetPath)
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

extension FBProcessLaunchOptions : Parsable {
  public static var parser: Parser<FBProcessLaunchOptions> { get {
    return Parser<FBProcessLaunchOptions>.union([
      Parser.ofString("--stdout", FBProcessLaunchOptions.WriteStdout),
      Parser.ofString("--stderr", FBProcessLaunchOptions.WriteStderr),
    ])
  }}
}

extension FBCrashLogInfoProcessType : Parsable {
  public static var parser: Parser<FBCrashLogInfoProcessType> { get {
    return Parser<FBCrashLogInfoProcessType>
      .union([
        Parser.ofString("--application", FBCrashLogInfoProcessType.Application),
        Parser.ofString("--system", FBCrashLogInfoProcessType.System),
        Parser.ofString("--custom-agent", FBCrashLogInfoProcessType.CustomAgent)
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
        FBiOSTargetQueryParsers.parser.optional(),
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


extension Action : Parsable {
  public static var parser: Parser<Action> { get {
    return Parser
      .alternative([
        self.approveParser,
        self.bootParser,
        self.clearKeychainParser,
        self.createParser,
        self.deleteParser,
        self.diagnoseParser,
        self.eraseParser,
        self.installParser,
        self.launchAgentParser,
        self.launchAppParser,
        self.launchXCTestParser,
        self.listenParser,
        self.listParser,
        self.listAppsParser,
        self.openParser,
        self.recordParser,
        self.relaunchParser,
        self.shutdownParser,
        self.tapParser,
        self.terminateParser,
        self.uninstallParser,
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

  static var clearKeychainParser: Parser<Action> { get {
    return Parser
      .succeeded(EventName.ClearKeychain.rawValue, Parser<Any>.ofBundleID)
      .fmap { Action.ClearKeychain($0) }
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
      .succeeded(
        EventName.Diagnose.rawValue,
        Parser.ofTwoSequenced(
          DiagnosticFormat.parser.fallback(DiagnosticFormat.CurrentFormat),
          FBSimulatorDiagnosticQueryParser.parser
        )
      )
      .fmap { (format, query) in
        Action.Diagnose(query, format)
      }
  }}

  static var eraseParser: Parser<Action> { get {
    return Parser.ofString(EventName.Erase.rawValue, Action.Erase)
  }}

  static var launchAgentParser: Parser<Action> { get {
    return Parser
      .succeeded(
        EventName.Launch.rawValue,
        FBProcessLaunchConfigurationParsers.agentLaunchParser
      )
      .fmap { Action.LaunchAgent($0) }
  }}

  static var launchAppParser: Parser<Action> { get {
    return Parser
      .succeeded(
        EventName.Launch.rawValue,
        FBProcessLaunchConfigurationParsers.appLaunchParser
      )
      .fmap { Action.LaunchApp($0) }
  }}

  static var launchXCTestParser: Parser<Action> { get {
    return Parser
      .succeeded(
        EventName.LaunchXCTest.rawValue,
        Parser.ofTwoSequenced(
          Parser<Any>.ofDirectory,
          FBProcessLaunchConfigurationParsers.appLaunchParser
        )
      )
      .fmap { (bundle, appLaunch) in
        Action.LaunchXCTest(appLaunch, bundle)
      }
  }}

  static var listenParser: Parser<Action> { get {
    return Parser
      .succeeded(EventName.Listen.rawValue, Server.parser)
      .fmap { Action.Listen($0) }
  }}

  static var listParser: Parser<Action> { get {
    return Parser.ofString(EventName.List.rawValue, Action.List)
  }}

  static var listAppsParser: Parser<Action> { get {
    return Parser.ofString(EventName.ListApps.rawValue, Action.ListApps)
  }}

  static var openParser: Parser<Action> { get {
    return Parser
      .succeeded(
        EventName.Open.rawValue,
        Parser<Any>.ofURL
      )
      .fmap { Action.Open($0) }
  }}

  static var installParser: Parser<Action> { get {
    return Parser
      .succeeded(EventName.Install.rawValue, Parser<Any>.ofApplication)
      .fmap { Action.Install($0) }
  }}

  static var relaunchParser: Parser<Action> { get {
    return Parser
      .succeeded(EventName.Relaunch.rawValue, FBProcessLaunchConfigurationParsers.appLaunchParser)
      .fmap { Action.Relaunch($0) }
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

  static var tapParser: Parser<Action> { get {
    return Parser
      .succeeded(
        EventName.Tap.rawValue,
        Parser.ofTwoSequenced(
          Parser<Any>.ofDouble,
          Parser<Any>.ofDouble
        )
      )
      .fmap { (x,y) in
        Action.Tap(x, y)
      }
  }}

  static var terminateParser: Parser<Action> { get {
    return Parser
      .succeeded(EventName.Terminate.rawValue, Parser<Any>.ofBundleID)
      .fmap { Action.Terminate($0) }
  }}

  static var uninstallParser: Parser<Action> { get {
    return Parser
      .succeeded(EventName.Uninstall.rawValue, Parser<Any>.ofBundleID)
      .fmap { Action.Uninstall($0) }
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

extension DiagnosticFormat : Parsable {
  public static var parser: Parser<DiagnosticFormat> { get {
    return Parser
      .alternative([
        Parser.ofString(DiagnosticFormat.CurrentFormat.rawValue, DiagnosticFormat.CurrentFormat),
        Parser.ofString(DiagnosticFormat.Path.rawValue, DiagnosticFormat.Path),
        Parser.ofString(DiagnosticFormat.Content.rawValue, DiagnosticFormat.Content),
      ])
  }}
}

extension SequenceType where Generator.Element == Keyword {
  public static var parser: Parser<Format> { get {
    return Parser.manyCount(1, Keyword.parser)
  }}
}

public struct FBiOSTargetQueryParsers {
  public static var parser: Parser<FBiOSTargetQuery> { get {
    return Parser.alternative([
      self.allParser,
      self.unionParser
    ])
  }}

  static var allParser: Parser<FBiOSTargetQuery> { get {
    return Parser<FBiOSTargetQuery>
      .ofString("all", FBiOSTargetQuery.allSimulators())
  }}

  static var unionParser: Parser<FBiOSTargetQuery> { get {
    return Parser<FBiOSTargetQuery>.accumulate(1, [
      self.firstParser,
      self.uuidParser,
      self.simulatorStateParser,
      self.osVersionsParser,
      self.deviceParser
    ])
  }}

  static var firstParser: Parser<FBiOSTargetQuery> { get {
    return Parser
      .succeeded("--first", Parser<Any>.ofInt)
      .fmap { FBiOSTargetQuery.ofCount($0) }
  }}

  static var uuidParser: Parser<FBiOSTargetQuery> { get {
    return Parser<FBiOSTargetQuery>
      .ofUDID
      .fmap { FBiOSTargetQuery.udids([$0.UUIDString]) }
  }}

  static var simulatorStateParser: Parser<FBiOSTargetQuery> { get {
    return FBSimulatorState
      .parser
      .fmap { FBiOSTargetQuery.simulatorStates([$0]) }
  }}

  static var osVersionsParser: Parser<FBiOSTargetQuery> { get {
    return FBSimulatorConfigurationParser
      .osVersionParser
      .fmap { FBiOSTargetQuery.osVersions([$0]) }
  }}

  static var deviceParser: Parser<FBiOSTargetQuery> { get {
    return FBSimulatorConfigurationParser
      .deviceParser
      .fmap { FBiOSTargetQuery.devices([$0]) }
  }}
}

/**
 A separate struct for FBSimulatorDiagnosticQuery is needed as Parsable protcol conformance cannot be
 applied to FBSimulatorDiagnosticQuery as it is a non-final.
 */
struct FBSimulatorDiagnosticQueryParser {
  internal static var parser: Parser<FBSimulatorDiagnosticQuery> { get {
    return Parser
      .alternative([
        self.appFilesParser,
        self.namedParser,
        self.crashesParser,
      ])
      .fallback(FBSimulatorDiagnosticQuery.all())
    }}

  static var namedParser: Parser<FBSimulatorDiagnosticQuery> { get {
    return Parser
      .manyCount(1, Parser.succeeded("--name", Parser<Any>.ofAny))
      .fmap { names in
        FBSimulatorDiagnosticQuery.named(names)
      }
  }}

  static var crashesParser: Parser<FBSimulatorDiagnosticQuery> { get {
    return Parser
      .ofTwoSequenced(
        Parser.succeeded("--crashes-since", Parser<Any>.ofDate),
        FBCrashLogInfoProcessType.parser
      )
      .fmap { (date, processType) in
        FBSimulatorDiagnosticQuery.crashesOfType(processType, since: date)
      }
  }}

  static var appFilesParser: Parser<FBSimulatorDiagnosticQuery> { get {
    return Parser
      .ofTwoSequenced(
        Parser<Any>.ofBundleID,
        Parser.manyCount(1, Parser<Any>.ofAny)
      )
      .fmap { (bundleID, fileNames) in
        FBSimulatorDiagnosticQuery.filesInApplicationOfBundleID(bundleID, withFilenames: fileNames)
      }
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
        var configuration = FBSimulatorConfiguration.defaultConfiguration()
        if let device = device {
          configuration = configuration.withDevice(device)
        }
        if let os = os {
          configuration = configuration.withOS(os)
        }
        if let auxDirectory = auxDirectory {
          configuration = configuration.withAuxillaryDirectory(auxDirectory)
        }
        return configuration
      }
  }}

  static var deviceParser: Parser<FBControlCoreConfiguration_Device> { get {
    return Parser.single("A Device Name") { token in
      let nameToDevice = FBControlCoreConfigurationVariants.nameToDevice()
      guard let device = nameToDevice[token] else {
        throw ParseError.Custom("\(token) is not a valid device name")
      }
      return device
    }
  }}

  static var osVersionParser: Parser<FBControlCoreConfiguration_OS> { get {
    return Parser.single("An OS Version") { token in
      let nameToOSVersion = FBControlCoreConfigurationVariants.nameToOSVersion()
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
 A separate struct for FBSimulatorLaunchConfiguration is needed as Parsable protcol conformance cannot be
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
          configuration = configuration.withLocalizationOverride(FBLocalizationOverride.withLocale(locale))
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
      .union(1, [
        Parser.ofString("--connect-bridge", FBSimulatorLaunchOptions.ConnectBridge),
        Parser.ofString("--direct-launch", FBSimulatorLaunchOptions.EnableDirectLaunch),
        Parser.ofString("--use-nsworkspace", FBSimulatorLaunchOptions.UseNSWorkspace),
        Parser.ofString("--debug-window", FBSimulatorLaunchOptions.ShowDebugWindow)
      ])
  }}
}

/**
 A separate struct for FBProcessLaunchConfiguration is needed as Parsable protcol conformance cannot be
 applied to FBProcessLaunchConfiguration as it is a non-final class.
 */
struct FBProcessLaunchConfigurationParsers {
  static var appLaunchParser: Parser<FBApplicationLaunchConfiguration> { get {
    return Parser
      .ofThreeSequenced(
        FBProcessLaunchOptions.parser,
        Parser<Any>.ofBundleID,
        self.argumentParser
      )
      .fmap { (options, bundleID, arguments) in
        return FBApplicationLaunchConfiguration(bundleID: bundleID, bundleName: nil, arguments: arguments, environment : [:], options: options)
      }
  }}

  static var agentLaunchParser: Parser<FBAgentLaunchConfiguration> { get {
    return Parser
      .ofThreeSequenced(
        FBProcessLaunchOptions.parser,
        Parser<Any>.ofBinary,
        self.argumentParser
      )
      .fmap { (options, binary, arguments) in
        return FBAgentLaunchConfiguration(binary: binary, arguments: arguments, environment : [:], options: options)
      }
  }}

  static var argumentParser: Parser<[String]> { get {
    return Parser.manyTill(
      Parser<String>.ofString("--", "--"),
      Parser<String>.ofAny
    )
  }}
}
