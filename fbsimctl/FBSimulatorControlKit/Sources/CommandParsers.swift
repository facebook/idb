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
import FBDeviceControl

extension Parser {
  public static var ofInt: Parser<Int> {
    let desc = PrimitiveDesc(name: "int",
                             desc: "Signed integer.")
    return Parser<Int>.single(desc) { token in
      guard let integer = NumberFormatter().number(from: token)?.intValue else {
        throw ParseError.couldNotInterpret("Int", token)
      }
      return integer
    }
  }

  public static var ofDouble: Parser<Double> {
    let desc = PrimitiveDesc(name: "double",
                             desc: "Double-precision floating point number.")
    return Parser<Double>.single(desc) { token in
      guard let double = NumberFormatter().number(from: token)?.doubleValue else {
        throw ParseError.couldNotInterpret("Double", token)
      }
      return double
    }
  }

  public static var ofAny: Parser<String> {
    let desc = PrimitiveDesc(name: "string", desc: "String without spaces.")
    return Parser<String>.single(desc, f: { $0 } )
  }

  public static var ofUDID: Parser<String> {
    let desc = PrimitiveDesc(name: "udid", desc: "Device or simulator Unique Device Identifier.")
    return Parser<String>.single(desc) { token in
      return try FBiOSTargetQuery.parseUDIDToken(token)
    }
  }

  public static var ofURL: Parser<URL> {
    let expected = "URL."
    let desc = PrimitiveDesc(name: "url", desc: expected)
    return Parser<URL>.single(desc) { token in
      guard let url = URL(string: token) else {
        throw ParseError.couldNotInterpret(expected, token)
      }
      return url
    }
  }

  public static var ofDirectory: Parser<String> {
    let desc = PrimitiveDesc(name: "directory", desc: "Path to a directory.")
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
    let desc = PrimitiveDesc(name: "file", desc: "Path to a file.")
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
    let desc = PrimitiveDesc(name: "application", desc: "Path to an application.")
    return Parser<FBApplicationDescriptor>.single(desc) { token in
      do {
        return try FBApplicationDescriptor.userApplication(withPath: token)
      } catch let error as NSError {
        throw ParseError.custom("Could not get an app \(token) \(error.description)")
      }
    }
  }

  public static var ofBinary: Parser<FBBinaryDescriptor> {
    let desc = PrimitiveDesc(name: "binary", desc: "Path to a binary.")
    return Parser<FBBinaryDescriptor>.single(desc) { token in
      do {
        return try FBBinaryDescriptor.binary(withPath: token)
      } catch let error as NSError {
        throw ParseError.custom("Could not get a binary \(token) \(error.description)")
      }
    }
  }

  public static var ofLocale: Parser<Locale> {
    let desc = PrimitiveDesc(name: "locale", desc: "Locale identifier.")
    return Parser<Locale>.single(desc) { token in
      return Locale(identifier: token)
    }
  }

  public static var ofBundleID: Parser<String> {
    let desc = PrimitiveDesc(name: "bundle-id", desc: "Bundle ID.")
    return Parser<String>.single(desc) { token in
      let components = token.components(separatedBy: CharacterSet(charactersIn: "."))
      if components.count < 2 {
        throw ParseError.custom("Bundle ID must contain a '.'")
      }
      return token
    }
  }

  public static var ofBundleIDOrApplicationDescriptor: Parser<(String, FBApplicationDescriptor?)> {
    return Parser<(String, FBApplicationDescriptor?)>
      .alternative([
        Parser.ofApplication.fmap { (app) -> (String, FBApplicationDescriptor?) in (app.bundleID, app) },
        Parser.ofBundleID.fmap{ (bundleId) -> (String, FBApplicationDescriptor?) in (bundleId, nil) },
      ])
  }

  public static var ofBundleIDOrApplicationDescriptorBundleID: Parser<String> {
    return Parser.ofBundleIDOrApplicationDescriptor.fmap{ $0.0 }
  }

  public static var ofDate: Parser<Date> {
    return Parser<Date>
      .ofDouble
      .describe(PrimitiveDesc(name: "date", desc: "Time since UNIX epoch (seconds)"))
      .fmap { Date(timeIntervalSince1970: $0) }
  }

  public static var ofDashSeparator: Parser<NSNull> {
    return Parser<NSNull>.ofString("--", NSNull())
  }
}

extension OutputOptions : Parsable {
  public static var parser: Parser<OutputOptions> {
    return Parser<OutputOptions>.union([singleParser])
  }

  static var singleParser: Parser<OutputOptions> {
    return Parser.alternative([
      Parser<OutputOptions>
        .ofFlag("debug-logging", OutputOptions.DebugLogging, ""),
      Parser<OutputOptions>
        .ofFlag("json", OutputOptions.JSON, ""),
      Parser<OutputOptions>
        .ofFlag("pretty", OutputOptions.Pretty, ""),
    ])
      .sectionize("output", "Output Options", "")
  }
}

extension FBSimulatorManagementOptions : Parsable {
  public static var parser: Parser<FBSimulatorManagementOptions> {
    return Parser<FBSimulatorManagementOptions>.union([singleParser])
  }

  static var singleParser: Parser<FBSimulatorManagementOptions> {
    return Parser.alternative([
      self.deleteAllOnFirstParser,
      self.killAllOnFirstParser,
      self.killSpuriousSimulatorsOnFirstStartParser,
      self.ignoreSpuriousKillFailParser,
      self.killSpuriousCoreSimulatorServicesParser,
    ])
      .sectionize("management", "Simulator Management", "")
  }

  static var deleteAllOnFirstParser: Parser<FBSimulatorManagementOptions> {
    return Parser<FBSimulatorManagementOptions>
      .ofFlag("delete-all", .deleteAllOnFirstStart, "")
  }

  static var killAllOnFirstParser: Parser<FBSimulatorManagementOptions> {
    return Parser<FBSimulatorManagementOptions>
      .ofFlag("kill-all", .killAllOnFirstStart, "")
  }

  static var killSpuriousSimulatorsOnFirstStartParser: Parser<FBSimulatorManagementOptions> {
    return Parser<FBSimulatorManagementOptions>
      .ofFlag("kill-spurious", .killSpuriousSimulatorsOnFirstStart, "")
  }

  static var ignoreSpuriousKillFailParser: Parser<FBSimulatorManagementOptions> {
    return Parser<FBSimulatorManagementOptions>
      .ofFlag("ignore-spurious-kill-fail", .ignoreSpuriousKillFail, "")
  }

  static var killSpuriousCoreSimulatorServicesParser: Parser<FBSimulatorManagementOptions> {
    return Parser<FBSimulatorManagementOptions>
      .ofFlag("kill-spurious-services", .killSpuriousCoreSimulatorServices, "")
  }
}

extension Configuration : Parsable {
  public static var parser: Parser<Configuration> {
    let outputOptionsParsers = OutputOptions.singleParser.fmap(Configuration.ofOutputOptions)
    let managementOptionsParsers = FBSimulatorManagementOptions.singleParser.fmap(Configuration.ofManagementOptions)
    return Parser<Configuration>.accumulate(0, [
      outputOptionsParsers,
      managementOptionsParsers,
      self.deviceSetPathParser
    ])
  }

  static var deviceSetPathParser: Parser<Configuration> {
    return Parser<Configuration>
      .ofFlagWithArg("set", Parser<Any>.ofDirectory, "")
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
    let desc = PrimitiveDesc(name: "device-name", desc: "Device Name.")
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
    let desc = PrimitiveDesc(name: "os-version", desc: "OS Version.")
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
      .ofFlagWithArg("aux", Parser<Any>.ofDirectory, "")
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
                ""),
      IndividualCreationConfiguration.parser.fmap { CreationSpecification.individual($0) },
    ])
  }
}

extension FBSimulatorState : Parsable {
  public static var parser: Parser<FBSimulatorState> {
    return Parser.alternative([
        stateFlag("creating", FBSimulatorState.creating, ""),
        stateFlag("shutdown", FBSimulatorState.shutdown, ""),
        stateFlag("booting", FBSimulatorState.booting, ""),
        stateFlag("booted", FBSimulatorState.booted, ""),
        stateFlag("shutting-down", FBSimulatorState.shuttingDown, "")
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
        "stdout", FBProcessLaunchOptions.writeStdout, ""),
      Parser<FBProcessLaunchOptions>.ofFlag(
        "stderr", FBProcessLaunchOptions.writeStderr, ""),
    ])
  }
}

extension FBiOSTargetType : Parsable {
  public static var parser: Parser<FBiOSTargetType> {
    return Parser<FBiOSTargetType>.alternative([
      Parser<FBiOSTargetType>.ofFlag(
        "simulators", FBiOSTargetType.simulator, ""),
      Parser<FBiOSTargetType>.ofFlag(
        "devices", FBiOSTargetType.device, ""),
    ])
  }
}

extension FBCrashLogInfoProcessType : Parsable {
  public static var parser: Parser<FBCrashLogInfoProcessType> {
    return Parser<FBCrashLogInfoProcessType>
      .union([
        Parser<FBCrashLogInfoProcessType>
          .ofFlag("application", FBCrashLogInfoProcessType.application, ""),
        Parser<FBCrashLogInfoProcessType>
          .ofFlag("system", FBCrashLogInfoProcessType.system, ""),
        Parser<FBCrashLogInfoProcessType>
          .ofFlag("custom-agent", FBCrashLogInfoProcessType.customAgent, "")
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
        "fbsimclt is a Mac OS X library for managing and manipulating iOS Simulators")
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
        self.httpParser,
        self.stdinParser,
      ])
      .fallback(Server.empty)
  }

  static var stdinParser: Parser<Server> {
    return Parser<Server>
      .ofFlag("stdin", Server.stdin, "Listen for commands on stdin")
  }

  static var httpParser:  Parser<Server> {
    return Parser<Server>
      .ofFlagWithArg("http", portParser, "")
      .fmap(Server.http)
  }

  private static var portParser: Parser<UInt16> {
    return Parser<Int>.ofInt
      .fmap { UInt16($0) }
      .describe(PrimitiveDesc(name: "port",
                              desc: "Port number (16-bit unsigned integer)."))
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
        self.listAppsParser,
        self.listDeviceSetsParser,
        self.listenParser,
        self.listParser,
        self.openParser,
        self.recordParser,
        self.relaunchParser,
        self.serviceInfoParser,
        self.setLocationParser,
        self.shutdownParser,
        self.tapParser,
        self.terminateParser,
        self.uninstallParser,
        self.uploadParser,
        self.watchdogOverrideParser,
      ])
      .withExpandedDesc
      .sectionize("action", "Action", "")
  }

  static var approveParser: Parser<Action> {
    return Parser<[String]>
      .ofCommandWithArg(EventName.Approve.rawValue,
                        Parser.manyCount(1, Parser<String>.ofBundleIDOrApplicationDescriptorBundleID))
      .fmap { Action.approve($0) }
      .sectionize("approve", "Action: Approve", "")
  }

  static var bootParser: Parser<Action> {
    return Parser<FBSimulatorBootConfiguration?>
      .ofCommandWithArg(EventName.Boot.rawValue,
                        FBSimulatorBootConfigurationParser.parser.optional())
      .fmap { Action.boot($0) }
      .sectionize("boot", "Action: Boot", "")
  }

  static var clearKeychainParser: Parser<Action> {
    return Parser<String?>
      .ofCommandWithArg(EventName.ClearKeychain.rawValue,
                        Parser<String>.ofBundleIDOrApplicationDescriptorBundleID.optional())
      .fmap { Action.clearKeychain($0) }
      .sectionize("clear_keychain", "Action: Clear Keychain", "")
  }

  static var configParser: Parser<Action> {
    return Parser.ofString(EventName.Config.rawValue, Action.config)
  }

  static var createParser: Parser<Action> {
    return Parser<CreationSpecification>
      .ofCommandWithArg(EventName.Create.rawValue, CreationSpecification.parser)
      .fmap { Action.create($0) }
      .sectionize("create", "Action: Create", "")
  }

  static var deleteParser: Parser<Action> {
    return Parser.ofString(EventName.Delete.rawValue, Action.delete)
  }

  static var diagnoseParser: Parser<Action> {
    return Parser<(DiagnosticFormat, FBDiagnosticQuery)>
      .ofCommandWithArg(
        EventName.Diagnose.rawValue,
        Parser.ofTwoSequenced(
          DiagnosticFormat.parser.fallback(DiagnosticFormat.CurrentFormat),
          FBDiagnosticQueryParser.parser
        )
      )
      .fmap { (format, query) in
        Action.diagnose(query, format)
      }
      .sectionize("diagnose", "Action: Diagnose", "")
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
      .sectionize("launch(agent)", "Action: Launch (Agent)", "")
  }

  static var launchAppParser: Parser<Action> {
    return Parser<FBApplicationLaunchConfiguration>
      .ofCommandWithArg(
        EventName.Launch.rawValue,
        FBProcessLaunchConfigurationParsers.appLaunchParser
      )
      .fmap { Action.launchApp($0) }
      .sectionize("launch(app)", "Action: Launch (App)", "")
  }

  static var launchXCTestParser: Parser<Action> {
        let optionalTimeoutFlag = Parser<Double>
      .ofFlagWithArg("test-timeout", Parser<Double>.ofDouble, "")
      .optional()

    let parser = Parser.ofThreeSequenced(
      optionalTimeoutFlag,
      Parser<Any>.ofDirectory,
      FBProcessLaunchConfigurationParsers.appLaunchAndApplicationDescriptorParser
    )

    let configurationParser = parser
      .fmap{ (timeout, bundle, appLaunch) -> FBTestLaunchConfiguration in
        var conf =
          FBTestLaunchConfiguration(testBundlePath: bundle)
            .withApplicationLaunchConfiguration(appLaunch.0)

        if let testHostPath = appLaunch.1?.path {
          conf = conf.withTestHostPath(testHostPath)
        }

        if (timeout != nil) {
          conf = conf.withTimeout(timeout!)
        }
        return conf
    }

    return Parser
      .ofCommandWithArg(
        EventName.LaunchXCTest.rawValue,
        configurationParser)
      .fmap { Action.launchXCTest($0) }
      .sectionize("launch_xctest", "Action: Launch XCTest", "")
  }

  static var listenParser: Parser<Action> {
    return Parser<Server>
      .ofCommandWithArg(EventName.Listen.rawValue, Server.parser)
      .fmap { Action.listen($0) }
      .sectionize("listen", "Action: Listen", "")
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
      .sectionize("relaunch", "Action: Relaunch", "")
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

  static var serviceInfoParser: Parser<Action> {
    return Parser
      .ofCommandWithArg(
        EventName.ServiceInfo.rawValue,
        Parser<String>.ofBundleIDOrApplicationDescriptorBundleID
      )
      .fmap(Action.serviceInfo)
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
                        Parser<String>.ofBundleIDOrApplicationDescriptorBundleID)
      .fmap { Action.terminate($0) }
  }

  static var uninstallParser: Parser<Action> {
    return Parser<String>
      .ofCommandWithArg(EventName.Uninstall.rawValue,
                        Parser<String>.ofBundleIDOrApplicationDescriptorBundleID)
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
          Parser.manyCount(1, Parser<String>.ofBundleIDOrApplicationDescriptorBundleID)
        )
      )
      .fmap { Action.watchdogOverride($1, $0) }
      .sectionize("watchdog_override", "Action: Watchdog Override", "")
  }
}

extension DiagnosticFormat : Parsable {
  public static var parser: Parser<DiagnosticFormat> {
    return Parser
      .alternative([
        Parser<DiagnosticFormat>
          .ofFlag(DiagnosticFormat.CurrentFormat.rawValue,
                  DiagnosticFormat.CurrentFormat, ""),
        Parser<DiagnosticFormat>
          .ofFlag(DiagnosticFormat.Path.rawValue,
                  DiagnosticFormat.Path, ""),
        Parser<DiagnosticFormat>
          .ofFlag(DiagnosticFormat.Content.rawValue,
                  DiagnosticFormat.Content, ""),
      ])
  }
}

public struct FBiOSTargetFormatParsers {
  public static var parser: Parser<FBiOSTargetFormat> {
    let parsers = FBiOSTargetFormat.allFields.map { field in
      return Parser.ofString("--" + field, field)
    }

    let altParser = Parser
      .alternative(parsers)
      .sectionize("target-format", "Target Format", "")

    return Parser
      .manyCount(1, altParser)
      .fmap { FBiOSTargetFormat(fields: $0) }
    }
}

public struct FBiOSTargetQueryParsers {
  public static var parser: Parser<FBiOSTargetQuery> {
    return Parser.alternative([
      self.allParser,
      self.unionParser
    ])
      .sectionize("targets", "Targets",
                  "")
  }

  static var allParser: Parser<FBiOSTargetQuery> {
    return Parser<FBiOSTargetQuery>
      .ofString("all", FBiOSTargetQuery.allTargets())
  }

  static var unionParser: Parser<FBiOSTargetQuery> {
    return Parser<FBiOSTargetQuery>.accumulate(1, [singleQueryParser])
  }

  static var singleQueryParser: Parser<FBiOSTargetQuery> {
    return Parser.alternative([
      self.firstParser,
      self.uuidParser,
      self.simulatorStateParser,
      self.targetTypeParser,
      self.osVersionsParser,
      self.deviceParser
    ])
      .sectionize("targets/query", "Target: Queries", "")
  }

  static var firstParser: Parser<FBiOSTargetQuery> {
    return Parser<Int>
      .ofFlagWithArg("first", Parser<Int>.ofInt, "")
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
 A separate struct for FBDiagnosticQuery is needed as Parsable protcol conformance cannot be
 applied to FBDiagnosticQuery as it is a non-final.
 */
struct FBDiagnosticQueryParser {
  internal static var parser: Parser<FBDiagnosticQuery> {
    return Parser
      .alternative([
        self.appFilesParser,
        self.namedParser,
        self.crashesParser,
      ])
      .fallback(FBDiagnosticQuery.all())
      .withExpandedDesc
      .sectionize("diagnose/query", "Diagnose: Query", "")
    }

  static var namedParser: Parser<FBDiagnosticQuery> {
    let nameParser = Parser<String>
      .ofFlagWithArg("name", Parser<String>.ofAny, "")

    return Parser
      .manyCount(1, nameParser)
      .fmap { names in
        FBDiagnosticQuery.named(names)
      }
  }

  static var crashesParser: Parser<FBDiagnosticQuery> {
    let crashDateParser = Parser<Date>
      .ofFlagWithArg("crashes-since", Parser<Date>.ofDate, "")

    return Parser
      .ofTwoSequenced(
        crashDateParser,
        FBCrashLogInfoProcessType.parser
      )
      .fmap { (date, processType) in
        FBDiagnosticQuery.crashes(of: processType, since: date)
      }
  }

  static var appFilesParser: Parser<FBDiagnosticQuery> {
    return Parser
      .ofTwoSequenced(
        Parser<Any>.ofBundleIDOrApplicationDescriptorBundleID,
        Parser.manyCount(1, Parser<Any>.ofAny)
      )
      .fmap { (bundleID, fileNames) in
        FBDiagnosticQuery.files(inApplicationOfBundleID: bundleID, withFilenames: fileNames)
      }
  }
}

/**
 A separate struct for FBSimulatorBootConfiguration is needed as Parsable protcol conformance cannot be
 applied to FBSimulatorBootConfiguration as it is a non-final class.
 */
struct FBSimulatorBootConfigurationParser {
  static var parser: Parser<FBSimulatorBootConfiguration> {
    return Parser<FBSimulatorBootConfiguration>
      .accumulate(1, [
        self.optionsParser.fmap { FBSimulatorBootConfiguration.withOptions($0) },
        self.scaleParser.fmap { FBSimulatorBootConfiguration.withScale($0) },
        self.localeParser.fmap { FBSimulatorBootConfiguration.withLocalizationOverride(FBLocalizationOverride.withLocale($0)) }
      ])
      .fmap { configuration in
        if configuration.options.contains(FBSimulatorBootOptions.enableDirectLaunch) && configuration.framebuffer == nil {
          return configuration.withFramebuffer(FBFramebufferConfiguration.default())
        }
        return configuration
      }
  }

  static var localeParser: Parser<Locale> {
    return Parser<Locale>
      .ofFlagWithArg("locale", Parser<Locale>.ofLocale, "")
  }

  static var scaleParser: Parser<FBSimulatorScale> {
    return Parser.alternative([
      Parser<FBSimulatorScale>
        .ofFlag("scale=25", FBSimulatorScale_25(), ""),
      Parser<FBSimulatorScale>
        .ofFlag("scale=50", FBSimulatorScale_50(), ""),
      Parser<FBSimulatorScale>
        .ofFlag("scale=75", FBSimulatorScale_75(), ""),
      Parser<FBSimulatorScale>
        .ofFlag("scale=100", FBSimulatorScale_100(), "")
    ])
  }

  static var optionsParser: Parser<FBSimulatorBootOptions> {
    return Parser<FBSimulatorBootOptions>.alternative([
      Parser<FBSimulatorBootOptions>
        .ofFlag("connect-bridge", FBSimulatorBootOptions.connectBridge, ""),
      Parser<FBSimulatorBootOptions>
        .ofFlag("direct-launch", FBSimulatorBootOptions.enableDirectLaunch,
                ""),
      Parser<FBSimulatorBootOptions>
        .ofFlag("use-nsworkspace", FBSimulatorBootOptions.useNSWorkspace, ""),
    ])
  }
}

/**
 A separate struct for FBProcessLaunchConfiguration is needed as Parsable protcol conformance cannot be
 applied to FBProcessLaunchConfiguration as it is a non-final class.
 */
struct FBProcessLaunchConfigurationParsers {
  static var appLaunchAndApplicationDescriptorParser: Parser<(FBApplicationLaunchConfiguration, FBApplicationDescriptor?)> {
    return Parser
      .ofThreeSequenced(
        FBProcessLaunchOptions.parser,
        Parser<Any>.ofBundleIDOrApplicationDescriptor,
        self.argumentParser
      )
      .fmap { (options, bundleIDOrApplicationDescriptor, arguments) in
        let (bundleId, appDescriptor) = bundleIDOrApplicationDescriptor
        return (
          FBApplicationLaunchConfiguration(bundleID: bundleId, bundleName: nil, arguments: arguments, environment : [:], options: options),
          appDescriptor
        )
      }
  }

  static var appLaunchParser: Parser<FBApplicationLaunchConfiguration> {
    return appLaunchAndApplicationDescriptorParser.fmap{ $0.0 }
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
