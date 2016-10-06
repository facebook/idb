/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

import Foundation
import FBControlCore
import FBSimulatorControl

extension Parser {
  public static var ofInt: Parser<Int> {
    let desc = PrimitiveDesc(name: "int", desc: "Explaining integers")
    return Parser<Int>.single(desc) { token in
      guard let integer = NumberFormatter().number(from: token)?.intValue else {
        throw ParseError.couldNotInterpret("Int", token)
      }
      return integer
    }
  }

  public static var ofDouble: Parser<Double> {
    let desc = PrimitiveDesc(name: "double", desc: "Explaining doubles")
    return Parser<Double>.single(desc) { token in
      guard let double = NumberFormatter().number(from: token)?.doubleValue else {
        throw ParseError.couldNotInterpret("Double", token)
      }
      return double
    }
  }

  public static var ofAny: Parser<String> {
    let desc = PrimitiveDesc(name: "string", desc: "Explaining strings")
    return Parser<String>.single(desc, f: { $0 } )
  }

  public static var ofUDID: Parser<String> {
    let desc = PrimitiveDesc(name: "udid", desc: "A Device or Simulator UDID")
    return Parser<String>.single(desc) { token in
      return try FBiOSTargetQuery.parseUDIDToken(token)
    }
  }

  public static var ofURL: Parser<URL> {
    let expected = "A URL"
    let desc = PrimitiveDesc(name: "url", desc: expected)
    return Parser<URL>.single(desc) { token in
      guard let url = URL(string: token) else {
        throw ParseError.couldNotInterpret(expected, token)
      }
      return url
    }
  }

  public static var ofDirectory: Parser<String> {
    let desc = PrimitiveDesc(name: "directory", desc: "A Directory")
    return Parser<String>.single(desc) { token  in
      let path = (token as NSString).standardizingPath
      var isDirectory: ObjCBool = false
      if !FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) {
        throw ParseError.custom("'\(path)' should exist, but doesn't")
      }
      if (!isDirectory.boolValue) {
        throw ParseError.custom("'\(path)' should be a directory, but isn't")
      }
      return path
    }
  }

  public static var ofFile: Parser<String> {
    let desc = PrimitiveDesc(name: "file", desc: "A File")
    return Parser<String>.single(desc) { token in
      let path = (token as NSString).standardizingPath
      var isDirectory: ObjCBool = false
      if !FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) {
        throw ParseError.custom("'\(path)' should exist, but doesn't")
      }
      if (isDirectory.boolValue) {
        throw ParseError.custom("'\(path)' should be a file, but isn't")
      }
      return path
    }
  }

  public static var ofApplication: Parser<FBApplicationDescriptor> {
    let desc = PrimitiveDesc(name: "application", desc: "An Application")
    return Parser<FBApplicationDescriptor>.single(desc) { token in
      do {
        return try FBApplicationDescriptor.application(withPath: token)
      } catch let error as NSError {
        throw ParseError.custom("Could not get an app \(token) \(error.description)")
      }
    }
  }

  public static var ofBinary: Parser<FBBinaryDescriptor> {
    let desc = PrimitiveDesc(name: "binary", desc: "A Binary")
    return Parser<FBBinaryDescriptor>.single(desc) { token in
      do {
        return try FBBinaryDescriptor.binary(withPath: token)
      } catch let error as NSError {
        throw ParseError.custom("Could not get a binary \(token) \(error.description)")
      }
    }
  }

  public static var ofLocale: Parser<Locale> {
    let desc = PrimitiveDesc(name: "locale", desc: "A Locale")
    return Parser<Locale>.single(desc) { token in
      return Locale(identifier: token)
    }
  }

  public static var ofBundleID: Parser<String> {
    let desc = PrimitiveDesc(name: "bundle-id", desc: "A Bundle ID")
    return Parser<String>
      .alternative([
        Parser.ofApplication.fmap { $0.bundleID },
        Parser<String>.single(desc) { token in
          let components = token.components(separatedBy: CharacterSet(charactersIn: "."))
          if components.count < 2 {
            throw ParseError.custom("Bundle ID must contain a '.'")
          }
          return token
        }
      ])
  }

  public static var ofDate: Parser<Date> {
    return Parser<Date>
      .ofDouble
      .describe(PrimitiveDesc(name: "date", desc: "A Date"))
      .fmap { Date(timeIntervalSince1970: $0) }
  }

  public static var ofDashSeparator: Parser<NSNull> {
    return Parser<NSNull>.ofString("--", NSNull())
  }
}

extension OutputOptions : Parsable {
  public static var parser: Parser<OutputOptions> {
    return Parser<OutputOptions>.union(parsers)
  }

  static var parsers: [Parser<OutputOptions>] {
    return [
      Parser<OutputOptions>
        .ofFlag("debug-logging", OutputOptions.DebugLogging,
                "Debug Logging Explanation"),
      Parser<OutputOptions>
        .ofFlag("json", OutputOptions.JSON,
                "JSON Explanation"),
      Parser<OutputOptions>
        .ofFlag("pretty", OutputOptions.Pretty,
                "Pretty Explanation"),
    ]
  }
}

extension FBSimulatorManagementOptions : Parsable {
  public static var parser: Parser<FBSimulatorManagementOptions> {
    return Parser<FBSimulatorManagementOptions>.union(self.parsers)
  }

  static var parsers: [Parser<FBSimulatorManagementOptions>] {
    return [
      self.deleteAllOnFirstParser,
      self.killAllOnFirstParser,
      self.killSpuriousSimulatorsOnFirstStartParser,
      self.ignoreSpuriousKillFailParser,
      self.killSpuriousCoreSimulatorServicesParser,
      self.useSimDeviceTimeoutResilianceParser
    ]
  }

  static var deleteAllOnFirstParser: Parser<FBSimulatorManagementOptions> {
    return Parser<FBSimulatorManagementOptions>
      .ofFlag("delete-all", .deleteAllOnFirstStart,
              "Delete All Explanation")
  }

  static var killAllOnFirstParser: Parser<FBSimulatorManagementOptions> {
    return Parser<FBSimulatorManagementOptions>
      .ofFlag("kill-all", .killAllOnFirstStart,
              "Kill All Explanation")
  }

  static var killSpuriousSimulatorsOnFirstStartParser: Parser<FBSimulatorManagementOptions> {
    return Parser<FBSimulatorManagementOptions>
      .ofFlag("kill-spurious", .killSpuriousSimulatorsOnFirstStart,
              "Kill Spurious Explanation")
  }

  static var ignoreSpuriousKillFailParser: Parser<FBSimulatorManagementOptions> {
    return Parser<FBSimulatorManagementOptions>
      .ofFlag("ignore-spurious-kill-fail", .ignoreSpuriousKillFail,
              "Ignore Spurious Kill Fail Explanation")
  }

  static var killSpuriousCoreSimulatorServicesParser: Parser<FBSimulatorManagementOptions> {
    return Parser<FBSimulatorManagementOptions>
      .ofFlag("kill-spurious-services", .killSpuriousCoreSimulatorServices,
              "Kill Spurious Services Explanation")
  }

  static var useSimDeviceTimeoutResilianceParser: Parser<FBSimulatorManagementOptions> {
    return Parser<FBSimulatorManagementOptions>
      .ofFlag("timeout-resiliance", .useSimDeviceTimeoutResiliance,
              "Timeout Resiliance Explanation")
  }
}

extension Configuration : Parsable {
  public static var parser: Parser<Configuration> {
    let outputOptionsParsers = OutputOptions.parsers.map { $0.fmap(Configuration.ofOutputOptions) }
    let managementOptionsParsers = FBSimulatorManagementOptions.parsers.map { $0.fmap(Configuration.ofManagementOptions) }
    let parsers = Array([outputOptionsParsers, managementOptionsParsers, [self.deviceSetPathParser]].joined())
    return Parser<Configuration>.accumulate(0, parsers)
  }

  static var deviceSetPathParser: Parser<Configuration> {
    return Parser<Configuration>
      .ofFlagWithArg("set", Parser<Any>.ofDirectory, "Set Explanation")
      .fmap(Configuration.ofDeviceSetPath)
  }
}

extension IndividualCreationConfiguration : Parsable {
  public static var parser: Parser<IndividualCreationConfiguration> {
    return Parser<IndividualCreationConfiguration>.accumulate(0, [
      self.deviceConfigurationParser,
      self.osVersionConfigurationParser,
      self.auxDirectoryConfigurationParser,
    ])
  }

  static var deviceParser: Parser<FBControlCoreConfiguration_Device> {
    let desc = PrimitiveDesc(name: "device-name", desc: "A Device Name")
    return Parser.single(desc) { token in
      let nameToDevice = FBControlCoreConfigurationVariants.nameToDevice()
      guard let device = nameToDevice[token] else {
        throw ParseError.custom("\(token) is not a valid device name")
      }
      return device
    }
  }

  static var deviceConfigurationParser: Parser<IndividualCreationConfiguration> {
    return self.deviceParser.fmap { device in
      return IndividualCreationConfiguration(
        osVersion: nil,
        deviceType: device,
        auxDirectory: nil
      )
    }
  }

  static var osVersionParser: Parser<FBControlCoreConfiguration_OS> {
    let desc = PrimitiveDesc(name: "os-version", desc: "An OS Version")
    return Parser.single(desc) { token in
      let nameToOSVersion = FBControlCoreConfigurationVariants.nameToOSVersion()
      guard let osVersion = nameToOSVersion[token] else {
        throw ParseError.custom("\(token) is not a valid device name")
      }
      return osVersion
    }
  }

  static var osVersionConfigurationParser: Parser<IndividualCreationConfiguration> {
    return self.osVersionParser.fmap { osVersion in
      return IndividualCreationConfiguration(
        osVersion: osVersion,
        deviceType: nil,
        auxDirectory: nil
      )
    }
  }

  static var auxDirectoryParser: Parser<String> {
    return Parser<String>
      .ofFlagWithArg("aux", Parser<Any>.ofDirectory,
                     "Explanation of AUX Directory")
  }

  static var auxDirectoryConfigurationParser: Parser<IndividualCreationConfiguration> {
    return self.auxDirectoryParser.fmap { auxDirectory in
      return IndividualCreationConfiguration(
        osVersion: nil,
        deviceType: nil,
        auxDirectory: auxDirectory
      )
    }
  }
}

extension CreationSpecification : Parsable {
  public static var parser: Parser<CreationSpecification> {
    return Parser.alternative([
      Parser<CreationSpecification>
        .ofFlag("all-missing-defaults",
                CreationSpecification.allMissingDefaults,
                "All Missing Defaults Explanation"),
      IndividualCreationConfiguration.parser.fmap { CreationSpecification.individual($0) },
    ])
  }
}

extension FBSimulatorState : Parsable {
  public static var parser: Parser<FBSimulatorState> {
    return Parser.alternative([
        stateFlag("creating", FBSimulatorState.creating,
                  "Creating explanation"),
        stateFlag("shutdown", FBSimulatorState.shutdown,
                  "Shutdown explanation"),
        stateFlag("booting", FBSimulatorState.booting,
                  "Booting explanation"),
        stateFlag("booted", FBSimulatorState.booted,
                  "Booted explanation"),
        stateFlag("shutting-down", FBSimulatorState.shuttingDown,
                  "Shutting down explanation")
    ])
  }

  static func stateFlag(_ stateLabel: String,
                        _ state: FBSimulatorState,
                        _ explain: String) -> Parser<FBSimulatorState> {
    return Parser<FBSimulatorState>
      .ofFlag("state=" + stateLabel, state, explain)
  }
}

extension FBProcessLaunchOptions : Parsable {
  public static var parser: Parser<FBProcessLaunchOptions> {
    return Parser<FBProcessLaunchOptions>.union([
      Parser<FBProcessLaunchOptions>.ofFlag(
        "stdout", FBProcessLaunchOptions.writeStdout,
        "STDOUT Explanation."),
      Parser<FBProcessLaunchOptions>.ofFlag(
        "stderr", FBProcessLaunchOptions.writeStderr,
        "STDERR Explanation."),
    ])
  }
}

extension FBiOSTargetType : Parsable {
  public static var parser: Parser<FBiOSTargetType> {
    return Parser<FBiOSTargetType>.alternative([
      Parser<FBiOSTargetType>.ofFlag(
        "simulators", FBiOSTargetType.simulator,
        "Explanation of simulators"),
      Parser<FBiOSTargetType>.ofFlag(
        "devices", FBiOSTargetType.device,
        "Explanation of devices"),
    ])
  }
}

extension FBCrashLogInfoProcessType : Parsable {
  public static var parser: Parser<FBCrashLogInfoProcessType> {
    return Parser<FBCrashLogInfoProcessType>
      .union([
        Parser<FBCrashLogInfoProcessType>
          .ofFlag("application", FBCrashLogInfoProcessType.application,
                  "Explanation of Application"),
        Parser<FBCrashLogInfoProcessType>
          .ofFlag("system", FBCrashLogInfoProcessType.system,
                  "Explanation of System"),
        Parser<FBCrashLogInfoProcessType>
          .ofFlag("custom-agent", FBCrashLogInfoProcessType.customAgent,
                  "Explanation of Custom Agent")
      ])
  }
}

extension CLI : Parsable {
  public static var parser: Parser<CLI> {
    return Parser
      .alternative([
        Command.parser.fmap { CLI.run($0) }.topLevel,
        Help.parser.fmap { CLI.show($0) }.topLevel,
      ])
      .withExpandedDesc
      .sectionize(
        "fbsimctl", "Help",
        "Brief description of the purpose of this app.")
  }
}

extension Help : Parsable {
  public static var parser: Parser<Help> {
    return Parser
      .ofTwoSequenced(
        OutputOptions.parser,
        Parser.ofString("help", NSNull())
      )
      .fmap { (output, _) in
        return Help(outputOptions: output, userInitiated: true, command: nil)
      }
  }
}

extension Command : Parsable {
  public static var parser: Parser<Command> {
    return Parser
      .ofFourSequenced(
        Configuration.parser,
        FBiOSTargetQueryParsers.parser.optional(),
        FBiOSTargetFormatParsers.parser.optional(),
        self.compoundActionParser
      )
      .fmap { (configuration, query, format, actions) in
        return Command(
          configuration: configuration,
          actions: actions,
          query: query,
          format: format
        )
      }
  }

  static var compoundActionParser: Parser<[Action]> {
    return Parser.exhaustive(
      Parser.manySepCount(1, Action.parser, Parser<NSNull>.ofDashSeparator)
    )
  }
}

extension Server : Parsable {
  public static var parser: Parser<Server> {
    return Parser
      .alternative([
        self.socketParser,
        self.httpParser
      ])
      .fallback(Server.stdIO)
  }

  static var socketParser: Parser<Server> {
    return Parser<Server>
      .ofFlagWithArg("socket", Parser<Int>.ofInt,
                     "Explanation of socket")
      .fmap { portNumber in
        return Server.socket(UInt16(portNumber))
      }
  }

  static var httpParser:  Parser<Server> {
    return Parser<Server>
      .ofFlagWithArg("http", Parser<Int>.ofInt,
                     "Explanation of HTTP")
      .fmap { portNumber in
        return Server.http(UInt16(portNumber))
      }
  }
}


extension Action : Parsable {
  public static var parser: Parser<Action> {
    return Parser
      .alternative([
        self.approveParser,
        self.bootParser,
        self.clearKeychainParser,
        self.configParser,
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
        self.listDeviceSetsParser,
        self.openParser,
        self.recordParser,
        self.relaunchParser,
        self.shutdownParser,
        self.tapParser,
        self.terminateParser,
        self.uninstallParser,
        self.uploadParser,
        self.watchdogOverrideParser,
        self.setLocationParser,
      ])
  }

  static var approveParser: Parser<Action> {
    return Parser<[String]>
      .ofCommandWithArg(EventName.Approve.rawValue,
                        Parser.manyCount(1, Parser<String>.ofBundleID))
      .fmap { Action.approve($0) }
  }

  static var bootParser: Parser<Action> {
    return Parser<FBSimulatorLaunchConfiguration?>
      .ofCommandWithArg(EventName.Boot.rawValue,
                        FBSimulatorLaunchConfigurationParser.parser.optional())
      .fmap { Action.boot($0) }
  }

  static var clearKeychainParser: Parser<Action> {
    return Parser<String?>
      .ofCommandWithArg(EventName.ClearKeychain.rawValue,
                        Parser<String>.ofBundleID.optional())
      .fmap { Action.clearKeychain($0) }
  }

  static var configParser: Parser<Action> {
    return Parser.ofString(EventName.Config.rawValue, Action.config)
  }

  static var createParser: Parser<Action> {
    return Parser<CreationSpecification>
      .ofCommandWithArg(EventName.Create.rawValue, CreationSpecification.parser)
      .fmap { Action.create($0) }
  }

  static var deleteParser: Parser<Action> {
    return Parser.ofString(EventName.Delete.rawValue, Action.delete)
  }

  static var diagnoseParser: Parser<Action> {
    return Parser<(DiagnosticFormat, FBSimulatorDiagnosticQuery)>
      .ofCommandWithArg(
        EventName.Diagnose.rawValue,
        Parser.ofTwoSequenced(
          DiagnosticFormat.parser.fallback(DiagnosticFormat.CurrentFormat),
          FBSimulatorDiagnosticQueryParser.parser
        )
      )
      .fmap { (format, query) in
        Action.diagnose(query, format)
      }
  }

  static var eraseParser: Parser<Action> {
    return Parser.ofString(EventName.Erase.rawValue, Action.erase)
  }

  static var launchAgentParser: Parser<Action> {
    return Parser<FBAgentLaunchConfiguration>
      .ofCommandWithArg(
        EventName.Launch.rawValue,
        FBProcessLaunchConfigurationParsers.agentLaunchParser
      )
      .fmap { Action.launchAgent($0) }
  }

  static var launchAppParser: Parser<Action> {
    return Parser<FBApplicationLaunchConfiguration>
      .ofCommandWithArg(
        EventName.Launch.rawValue,
        FBProcessLaunchConfigurationParsers.appLaunchParser
      )
      .fmap { Action.launchApp($0) }
  }

  static var launchXCTestParser: Parser<Action> {
    let optionalTimeoutFlag = Parser<Double>
      .ofFlagWithArg("test-timeout", Parser<Double>.ofDouble,
                     "Explain Test Timeout.")
      .optional()

    let cmdParser = Parser<(Double?, String, FBApplicationLaunchConfiguration)>
      .ofCommandWithArg(
        EventName.LaunchXCTest.rawValue,
        Parser.ofThreeSequenced(
          optionalTimeoutFlag,
          Parser<Any>.ofDirectory,
          FBProcessLaunchConfigurationParsers.appLaunchParser
        )
      )

    return cmdParser
      .fmap { (timeout, bundle, appLaunch) in
        Action.launchXCTest(appLaunch, bundle, timeout)
      }
  }

  static var listenParser: Parser<Action> {
    return Parser<Server>
      .ofCommandWithArg(EventName.Listen.rawValue, Server.parser)
      .fmap { Action.listen($0) }
  }

  static var listParser: Parser<Action> {
    return Parser.ofString(EventName.List.rawValue, Action.list)
  }

  static var listAppsParser: Parser<Action> {
    return Parser.ofString(EventName.ListApps.rawValue, Action.listApps)
  }

  static var listDeviceSetsParser: Parser<Action> {
    return Parser.ofString(EventName.ListDeviceSets.rawValue, Action.listDeviceSets)
  }

  static var openParser: Parser<Action> {
    return Parser<URL>
      .ofCommandWithArg(
        EventName.Open.rawValue,
        Parser<URL>.ofURL
      )
      .fmap { Action.open($0) }
  }

  static var installParser: Parser<Action> {
    return Parser<String>
      .ofCommandWithArg(EventName.Install.rawValue, Parser<String>.ofAny)
      .fmap { Action.install($0) }
  }

  static var relaunchParser: Parser<Action> {
    return Parser<FBApplicationLaunchConfiguration>
      .ofCommandWithArg(EventName.Relaunch.rawValue,
                        FBProcessLaunchConfigurationParsers.appLaunchParser)
      .fmap { Action.relaunch($0) }
  }

  static var recordParser: Parser<Action> {
    let startStopParser: Parser<Bool> = Parser.alternative([
      Parser.ofString("start", true),
      Parser.ofString("stop", false)
    ])

    return Parser<Bool>
      .ofCommandWithArg(EventName.Record.rawValue, startStopParser)
      .fmap { Action.record($0) }
  }

  static var shutdownParser: Parser<Action> {
    return Parser.ofString(EventName.Shutdown.rawValue, Action.shutdown)
  }

  static var tapParser: Parser<Action> {
    let coordParser: Parser<(Double, Double)> = Parser
      .ofTwoSequenced(Parser<Double>.ofDouble,
                      Parser<Double>.ofDouble)

    return Parser
      .ofCommandWithArg(
        EventName.Tap.rawValue,
        coordParser
      )
      .fmap { (x,y) in
        Action.tap(x, y)
      }
  }

  static var setLocationParser: Parser<Action> {
    let latLngParser: Parser<(Double, Double)> = Parser
      .ofTwoSequenced(Parser<Double>.ofDouble,
                      Parser<Double>.ofDouble)

    return Parser
      .ofCommandWithArg(
        EventName.SetLocation.rawValue,
        latLngParser
      )
      .fmap { (latitude, longitude) in
        Action.setLocation(latitude, longitude)
      }
  }

  static var terminateParser: Parser<Action> {
    return Parser<String>
      .ofCommandWithArg(EventName.Terminate.rawValue,
                        Parser<String>.ofBundleID)
      .fmap { Action.terminate($0) }
  }

  static var uninstallParser: Parser<Action> {
    return Parser<String>
      .ofCommandWithArg(EventName.Uninstall.rawValue,
                        Parser<String>.ofBundleID)
      .fmap { Action.uninstall($0) }
  }

  static var uploadParser: Parser<Action> {
    return Parser<[String]>
      .ofCommandWithArg(
        EventName.Upload.rawValue,
        Parser.manyCount(1, Parser<String>.ofFile)
      )
      .fmap { paths in
        let diagnostics: [FBDiagnostic] = paths.map { path in
          return FBDiagnosticBuilder().updatePath(path).build()
        }
        return Action.upload(diagnostics)
      }
  }

  static var watchdogOverrideParser: Parser<Action> {
    return Parser<(Double, [String])>
      .ofCommandWithArg(
        EventName.WatchdogOverride.rawValue,
        Parser.ofTwoSequenced(
          Parser<Double>.ofDouble,
          Parser.manyCount(1, Parser<String>.ofBundleID)
        )
      )
      .fmap { Action.watchdogOverride($1, $0) }
  }
}

extension DiagnosticFormat : Parsable {
  public static var parser: Parser<DiagnosticFormat> {
    return Parser
      .alternative([
        Parser<DiagnosticFormat>
          .ofFlag(DiagnosticFormat.CurrentFormat.rawValue,
                  DiagnosticFormat.CurrentFormat,
                  "Explain Current Format"),
        Parser<DiagnosticFormat>
          .ofFlag(DiagnosticFormat.Path.rawValue,
                  DiagnosticFormat.Path,
                  "Explain Path"),
        Parser<DiagnosticFormat>
          .ofFlag(DiagnosticFormat.Content.rawValue,
                  DiagnosticFormat.Content,
                  "Explain Content"),
      ])
  }
}

public struct FBiOSTargetFormatParsers {
  public static var parser: Parser<FBiOSTargetFormat> {
    let parsers = FBiOSTargetFormat.allFields.map { field in
      return Parser.ofString("--" + field, field)
    }
    return Parser
      .alternativeMany(1, parsers)
      .fmap { FBiOSTargetFormat(fields: $0) }
    }
}

public struct FBiOSTargetQueryParsers {
  public static var parser: Parser<FBiOSTargetQuery> {
    return Parser.alternative([
      self.allParser,
      self.unionParser
    ])
  }

  static var allParser: Parser<FBiOSTargetQuery> {
    return Parser<FBiOSTargetQuery>
      .ofString("all", FBiOSTargetQuery.allTargets())
  }

  static var unionParser: Parser<FBiOSTargetQuery> {
    return Parser<FBiOSTargetQuery>.accumulate(1, [
      self.firstParser,
      self.uuidParser,
      self.simulatorStateParser,
      self.targetTypeParser,
      self.osVersionsParser,
      self.deviceParser
    ])
  }

  static var firstParser: Parser<FBiOSTargetQuery> {
    return Parser<Int>
      .ofFlagWithArg("first", Parser<Int>.ofInt, "Explanatin of First")
      .fmap { FBiOSTargetQuery.ofCount($0) }
  }

  static var uuidParser: Parser<FBiOSTargetQuery> {
    return Parser<FBiOSTargetQuery>
      .ofUDID
      .fmap { FBiOSTargetQuery.udids([$0]) }
  }

  static var simulatorStateParser: Parser<FBiOSTargetQuery> {
    return FBSimulatorState
      .parser
      .fmap { FBiOSTargetQuery.simulatorStates([$0]) }
  }

  static var targetTypeParser: Parser<FBiOSTargetQuery> {
    return FBiOSTargetType
      .parser
      .fmap { FBiOSTargetQuery.targetType($0) }
  }

  static var osVersionsParser: Parser<FBiOSTargetQuery> {
    return IndividualCreationConfiguration
      .osVersionParser
      .fmap { FBiOSTargetQuery.osVersions([$0]) }
  }

  static var deviceParser: Parser<FBiOSTargetQuery> {
    return IndividualCreationConfiguration
      .deviceParser
      .fmap { FBiOSTargetQuery.devices([$0]) }
  }
}

/**
 A separate struct for FBSimulatorDiagnosticQuery is needed as Parsable protcol conformance cannot be
 applied to FBSimulatorDiagnosticQuery as it is a non-final.
 */
struct FBSimulatorDiagnosticQueryParser {
  internal static var parser: Parser<FBSimulatorDiagnosticQuery> {
    return Parser
      .alternative([
        self.appFilesParser,
        self.namedParser,
        self.crashesParser,
      ])
      .fallback(FBSimulatorDiagnosticQuery.all())
    }

  static var namedParser: Parser<FBSimulatorDiagnosticQuery> {
    let nameParser = Parser<String>
      .ofFlagWithArg("name", Parser<String>.ofAny, "Explaining name.")

    return Parser
      .manyCount(1, nameParser)
      .fmap { names in
        FBSimulatorDiagnosticQuery.named(names)
      }
  }

  static var crashesParser: Parser<FBSimulatorDiagnosticQuery> {
    let crashDateParser = Parser<Date>
      .ofFlagWithArg("crashes-since", Parser<Date>.ofDate,
                     "Explain crashes since")

    return Parser
      .ofTwoSequenced(
        crashDateParser,
        FBCrashLogInfoProcessType.parser
      )
      .fmap { (date, processType) in
        FBSimulatorDiagnosticQuery.crashes(of: processType, since: date)
      }
  }

  static var appFilesParser: Parser<FBSimulatorDiagnosticQuery> {
    return Parser
      .ofTwoSequenced(
        Parser<Any>.ofBundleID,
        Parser.manyCount(1, Parser<Any>.ofAny)
      )
      .fmap { (bundleID, fileNames) in
        FBSimulatorDiagnosticQuery.files(inApplicationOfBundleID: bundleID, withFilenames: fileNames)
      }
  }
}

/**
 A separate struct for FBSimulatorLaunchConfiguration is needed as Parsable protcol conformance cannot be
 applied to FBSimulatorLaunchConfiguration as it is a non-final class.
 */
struct FBSimulatorLaunchConfigurationParser {
  static var parser: Parser<FBSimulatorLaunchConfiguration> {
    return Parser<FBSimulatorLaunchConfiguration>
      .accumulate(1, [
        self.optionsParser.fmap { FBSimulatorLaunchConfiguration.withOptions($0) },
        self.scaleParser.fmap { FBSimulatorLaunchConfiguration.withScale($0) },
        self.localeParser.fmap { FBSimulatorLaunchConfiguration.withLocalizationOverride(FBLocalizationOverride.withLocale($0)) }
      ])
      .fmap { configuration in
        if configuration.options.contains(FBSimulatorLaunchOptions.enableDirectLaunch) && configuration.framebuffer == nil {
          return configuration.withFramebuffer(FBFramebufferConfiguration.default())
        }
        return configuration
      }
  }

  static var localeParser: Parser<Locale> {
    return Parser<Locale>
      .ofFlagWithArg("locale", Parser<Locale>.ofLocale,
                     "Explanation of Locale.")
  }

  static var scaleParser: Parser<FBSimulatorScale> {
    return Parser.alternative([
      Parser<FBSimulatorScale>
        .ofFlag("scale=25", FBSimulatorScale_25(),
                "Explanation of Scale 25"),
      Parser<FBSimulatorScale>
        .ofFlag("scale=50", FBSimulatorScale_50(),
                "Explanation of Scale 50"),
      Parser<FBSimulatorScale>
        .ofFlag("scale=75", FBSimulatorScale_75(),
                "Explanation of Scale 75"),
      Parser<FBSimulatorScale>
        .ofFlag("scale=100", FBSimulatorScale_100(),
                "Explanation of Scale 100")
    ])
  }

  static var optionsParser: Parser<FBSimulatorLaunchOptions> {
    return Parser<FBSimulatorLaunchOptions>.alternative([
      Parser<FBSimulatorLaunchOptions>
        .ofFlag("connect-bridge", FBSimulatorLaunchOptions.connectBridge,
                "Explanation of Connect Bridge"),
      Parser<FBSimulatorLaunchOptions>
        .ofFlag("direct-launch", FBSimulatorLaunchOptions.enableDirectLaunch,
                "Explanation of Direct Launch"),
      Parser<FBSimulatorLaunchOptions>
        .ofFlag("use-nsworkspace", FBSimulatorLaunchOptions.useNSWorkspace,
                "Explanation of Use NSWorkspace"),
    ])
  }
}

/**
 A separate struct for FBProcessLaunchConfiguration is needed as Parsable protcol conformance cannot be
 applied to FBProcessLaunchConfiguration as it is a non-final class.
 */
struct FBProcessLaunchConfigurationParsers {
  static var appLaunchParser: Parser<FBApplicationLaunchConfiguration> {
    return Parser
      .ofThreeSequenced(
        FBProcessLaunchOptions.parser,
        Parser<Any>.ofBundleID,
        self.argumentParser
      )
      .fmap { (options, bundleID, arguments) in
        return FBApplicationLaunchConfiguration(bundleID: bundleID, bundleName: nil, arguments: arguments, environment : [:], options: options)
      }
  }

  static var agentLaunchParser: Parser<FBAgentLaunchConfiguration> {
    return Parser
      .ofThreeSequenced(
        FBProcessLaunchOptions.parser,
        Parser<Any>.ofBinary,
        self.argumentParser
      )
      .fmap { (options, binary, arguments) in
        return FBAgentLaunchConfiguration(binary: binary, arguments: arguments, environment : [:], options: options)
      }
  }

  static var argumentParser: Parser<[String]> {
    return Parser
      .manyTill(
        Parser<NSNull>.ofDashSeparator,
        Parser<String>.ofAny
      )
  }
}
