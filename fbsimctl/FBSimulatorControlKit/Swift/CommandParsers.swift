/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import FBDeviceControl
import FBSimulatorControl
import Foundation

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
    return Parser<String>.single(desc, f: { $0 })
  }

  public static var ofUDID: Parser<String> {
    let desc = PrimitiveDesc(name: "udid", desc: "Device or simulator Unique Device Identifier.")
    return Parser<String>.single(desc) { token in
      try FBiOSTargetQuery.parseUDIDToken(token)
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

  public static var ofExistingDirectory: Parser<String> {
    let desc = PrimitiveDesc(name: "directory", desc: "Path to an existing directory.")
    return Parser<String>.single(desc) { token in
      let path = (token as NSString).standardizingPath
      var isDirectory: ObjCBool = false
      if !FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) {
        throw ParseError.custom("'\(path)' should exist, but doesn't")
      }
      if !isDirectory.boolValue {
        throw ParseError.custom("'\(path)' should be a directory, but isn't")
      }
      return path
    }
  }

  public static var ofExistingFile: Parser<String> {
    let desc = PrimitiveDesc(name: "file", desc: "Path to an existing file.")
    return Parser<String>.single(desc) { token in
      let path = (token as NSString).standardizingPath
      var isDirectory: ObjCBool = false
      if !FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) {
        throw ParseError.custom("'\(path)' should exist, but doesn't")
      }
      if isDirectory.boolValue {
        throw ParseError.custom("'\(path)' should be a file, but isn't")
      }
      return path
    }
  }

  public static var ofFile: Parser<String> {
    let desc = PrimitiveDesc(name: "file", desc: "Path to a file.")
    return Parser<String>.single(desc) { token in
      do {
        _ = try Parser.ofDashSeparator.parse([token])
      } catch is ParseError {
        return token
      }
      throw ParseError.custom("Not a File Path")
    }
  }

  public static var ofApplication: Parser<FBBundleDescriptor> {
    let desc = PrimitiveDesc(name: "application", desc: "Path to an application.")
    return Parser<FBBundleDescriptor>.single(desc) { token in
      do {
        return try FBBundleDescriptor.bundle(fromPath: token)
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
      Locale(identifier: token)
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

  public static var ofBundleIDOrApplicationDescriptor: Parser<(String, FBBundleDescriptor?)> {
    return Parser<(String, FBBundleDescriptor?)>
      .alternative([
        Parser.ofApplication.fmap { (app) -> (String, FBBundleDescriptor?) in (app.identifier, app) },
        Parser.ofBundleID.fmap { (bundleId) -> (String, FBBundleDescriptor?) in (bundleId, nil) },
      ])
  }

  public static var ofBundleIDOrApplicationDescriptorBundleID: Parser<String> {
    return Parser.ofBundleIDOrApplicationDescriptor.fmap { $0.0 }
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

extension OutputOptions: Parsable {
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

extension FBSimulatorManagementOptions: Parsable {
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

extension Configuration: Parsable {
  public static var parser: Parser<Configuration> {
    let outputOptionsParsers = OutputOptions.singleParser.fmap(Configuration.ofOutputOptions)
    let managementOptionsParsers = FBSimulatorManagementOptions.singleParser.fmap(Configuration.ofManagementOptions)
    return Parser<Configuration>.accumulate(0, [
      outputOptionsParsers,
      managementOptionsParsers,
      self.deviceSetPathParser,
    ])
  }

  static var deviceSetPathParser: Parser<Configuration> {
    return Parser<Configuration>
      .ofFlagWithArg("set", Parser<Any>.ofExistingDirectory, "")
      .fmap(Configuration.ofDeviceSetPath)
  }
}

extension IndividualCreationConfiguration: Parsable {
  public static var parser: Parser<IndividualCreationConfiguration> {
    return Parser<IndividualCreationConfiguration>.accumulate(0, [
      self.deviceConfigurationParser,
      self.osVersionConfigurationParser,
      self.auxDirectoryConfigurationParser,
    ])
  }

  static var deviceParser: Parser<FBDeviceModel> {
    let desc = PrimitiveDesc(name: "device-name", desc: "Device Name.")

    return Parser.single(desc) { token in
      let nameToDevice = FBiOSTargetConfiguration.nameToDevice
      let deviceName = FBDeviceModel(rawValue: token)
      guard let _ = nameToDevice[deviceName] else {
        throw ParseError.custom("\(token) is not a valid device name")
      }
      return deviceName
    }
  }

  static var deviceConfigurationParser: Parser<IndividualCreationConfiguration> {
    return deviceParser.fmap { device in
      IndividualCreationConfiguration(
        os: nil,
        model: device,
        auxDirectory: nil
      )
    }
  }

  static var osVersionParser: Parser<FBOSVersionName> {
    let desc = PrimitiveDesc(name: "os-version", desc: "OS Version.")
    return Parser.single(desc) { token in
      let nameToOSVersion = FBiOSTargetConfiguration.nameToOSVersion
      let osVersionName = FBOSVersionName(rawValue: token)
      guard let _ = nameToOSVersion[osVersionName] else {
        throw ParseError.custom("\(token) is not a valid device name")
      }
      return osVersionName
    }
  }

  static var osVersionConfigurationParser: Parser<IndividualCreationConfiguration> {
    return osVersionParser.fmap { osVersion in
      IndividualCreationConfiguration(
        os: osVersion,
        model: nil,
        auxDirectory: nil
      )
    }
  }

  static var auxDirectoryParser: Parser<String> {
    return Parser<String>
      .ofFlagWithArg("aux", Parser<Any>.ofExistingDirectory, "")
  }

  static var auxDirectoryConfigurationParser: Parser<IndividualCreationConfiguration> {
    return auxDirectoryParser.fmap { auxDirectory in
      IndividualCreationConfiguration(
        os: nil,
        model: nil,
        auxDirectory: auxDirectory
      )
    }
  }
}

extension CreationSpecification: Parsable {
  public static var parser: Parser<CreationSpecification> {
    return Parser.alternative([
      Parser<CreationSpecification>
        .ofFlag("all-missing-defaults",
                CreationSpecification.allMissingDefaults,
                ""),
      IndividualCreationConfiguration.parser.fmap(CreationSpecification.individual),
    ])
  }
}

extension FBiOSTargetState: Parsable {
  public static var parser: Parser<FBiOSTargetState> {
    let names = [
      ("creating", FBiOSTargetState.creating),
      ("shutdown", FBiOSTargetState.shutdown),
      ("booting", FBiOSTargetState.booting),
      ("booted", FBiOSTargetState.booted),
      ("shutting-down", FBiOSTargetState.shuttingDown),
    ]
    let stateParsers = names.map { name, state in
      Parser.ofString(name, state)
    }
    return Parser<FBiOSTargetState>.ofFlagWithArg(
      "state",
      Parser.alternative(stateParsers),
      "A Simulator State"
    )
  }
}

extension FBiOSTargetType: Parsable {
  public static var parser: Parser<FBiOSTargetType> {
    return Parser<FBiOSTargetType>.alternative([
      Parser<FBiOSTargetType>.ofFlag(
        "simulators", FBiOSTargetType.simulator, ""
      ),
      Parser<FBiOSTargetType>.ofFlag(
        "devices", FBiOSTargetType.device, ""
      ),
    ])
  }
}

extension FBCrashLogInfoProcessType: Parsable {
  public static var parser: Parser<FBCrashLogInfoProcessType> {
    return Parser<FBCrashLogInfoProcessType>
      .union([
        Parser<FBCrashLogInfoProcessType>
          .ofFlag("application", FBCrashLogInfoProcessType.application, ""),
        Parser<FBCrashLogInfoProcessType>
          .ofFlag("system", FBCrashLogInfoProcessType.system, ""),
        Parser<FBCrashLogInfoProcessType>
          .ofFlag("custom-agent", FBCrashLogInfoProcessType.customAgent, ""),
      ])
  }
}

extension CLI: Parsable {
  public static var parser: Parser<CLI> {
    return Parser
      .alternative([
        self.printParser.topLevel,
        Command.parser.fmap(CLI.run).topLevel,
        Help.parser.fmap(CLI.show).topLevel,
      ])
      .withExpandedDesc
      .sectionize(
        "fbsimctl", "Help",
        "fbsimctl is a macOS library for managing and manipulating iOS Simulators"
      )
  }

  private static var printParser: Parser<CLI> {
    return Parser
      .ofString("print", NSNull())
      .sequence(Action.parser)
      .fmap(CLI.print)
  }
}

extension Help: Parsable {
  public static var parser: Parser<Help> {
    return Parser
      .ofTwoSequenced(
        OutputOptions.parser,
        Parser.ofString("help", NSNull())
      )
      .fmap { output, _ in
        Help(outputOptions: output, error: nil, command: nil)
      }
  }
}

extension Command: Parsable {
  public static var parser: Parser<Command> {
    return Parser
      .ofFourSequenced(
        Configuration.parser,
        FBiOSTargetQueryParsers.parser.optional(),
        FBiOSTargetFormatParsers.parser.optional(),
        compoundActionParser
      )
      .fmap { configuration, query, format, actions in
        Command(
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

extension ListenInterface: Parsable {
  public static var parser: Parser<ListenInterface> {
    return Parser<ListenInterface>
      .accumulate(0, [
        self.stdinParser,
        self.httpParser,
        self.actionSocketParser,
      ])
  }

  static var stdinParser: Parser<ListenInterface> {
    return Parser<ListenInterface>
      .ofFlag("stdin", ListenInterface(stdin: true, http: nil, hid: nil, continuation: nil), "Listen for commands on stdin")
  }

  static var httpParser: Parser<ListenInterface> {
    return Parser<ListenInterface>
      .ofFlagWithArg("http", portParser, "The HTTP Port to listen on")
      .fmap { ListenInterface(stdin: false, http: $0, hid: nil, continuation: nil) }
  }

  static var actionSocketParser: Parser<ListenInterface> {
    return Parser<ListenInterface>
      .ofFlagWithArg("socket", portParser, "The Action Socket Port to listen on")
      .fmap { ListenInterface(stdin: false, http: nil, hid: $0, continuation: nil) }
  }

  private static var portParser: Parser<UInt16> {
    return Parser<Int>.ofInt
      .fmap { UInt16($0) }
      .describe(PrimitiveDesc(
        name: "port",
        desc: "Port number (16-bit unsigned integer)."
      ))
  }
}

extension Record: Parsable {
  public static var parser: Parser<Record> {
    return Parser.alternative([
      self.startParser,
      self.stopParser,
    ])
  }

  private static var startParser: Parser<Record> {
    return Parser
      .ofCommandWithArg("start", Parser<String>.ofFile.optional())
      .fmap { Record.start($0) }
  }

  private static var stopParser: Parser<Record> {
    return Parser.ofString("stop", Record.stop)
  }
}

extension FileOutput: Parsable {
  public static var parser: Parser<FileOutput> {
    return Parser.alternative([
      Parser.ofString("-", FileOutput.standardOut),
      Parser<FileOutput>.ofFile.fmap(FileOutput.path),
    ])
  }
}

extension Action: Parsable {
  public static var parser: Parser<Action> {
    return Parser
      .alternative([
        self.accessibilityParser,
        self.approveParser,
        self.bootParser,
        self.clearKeychainParser,
        self.cloneParser,
        self.configParser,
        self.contactsUpdate,
        self.createParser,
        self.deleteParser,
        self.diagnoseParser,
        self.eraseParser,
        self.focusParser,
        self.installParser,
        self.keyboardOverrideParser,
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
        self.streamParser,
        self.tapParser,
        self.tailParser,
        self.terminateParser,
        self.uninstallParser,
        self.uploadParser,
        self.watchdogOverrideParser,
      ])
      .withExpandedDesc
      .sectionize("action", "Action", "")
  }

  static var accessibilityParser: Parser<Action> {
    return Parser
      .ofString(
        EventName.accessibilityFetch.rawValue,
        Action.accessibility
      )
  }

  static var approveParser: Parser<Action> {
    return Parser<[String]>
      .ofCommandWithArg(
        EventName.approve.rawValue,
        Parser.manyCount(1, Parser<String>.ofBundleIDOrApplicationDescriptorBundleID)
      )
      .fmap(Action.approve)
      .sectionize("approve", "Action: Approve", "")
  }

  static var bootParser: Parser<Action> {
    return Parser<FBSimulatorBootConfiguration>
      .ofCommandWithArg(
        EventName.boot.rawValue,
        FBSimulatorBootConfigurationParser.parser.fallback(FBSimulatorBootConfiguration.default)
      )
      .fmap(Action.boot)
      .sectionize("boot", "Action: Boot", "")
  }

  static var clearKeychainParser: Parser<Action> {
    return Parser<String?>
      .ofCommandWithArg(
        EventName.clearKeychain.rawValue,
        Parser<String>.ofBundleIDOrApplicationDescriptorBundleID.optional()
      )
      .fmap(Action.clearKeychain)
      .sectionize("clear_keychain", "Action: Clear Keychain", "")
  }

  static var cloneParser: Parser<Action> {
    return Parser.ofString(EventName.clone.rawValue, Action.clone)
  }

  static var configParser: Parser<Action> {
    return Parser.ofString(EventName.config.rawValue, Action.config)
  }

  static var contactsUpdate: Parser<Action> {
    return Parser
      .ofCommandWithArg(
        EventName.contactsUpdate.rawValue,
        Parser<Any>.ofExistingDirectory.fmap(Action.contactsUpdate)
      )
  }

  static var createParser: Parser<Action> {
    return Parser<CreationSpecification>
      .ofCommandWithArg(
        EventName.create.rawValue,
        CreationSpecification.parser
      )
      .fmap(Action.create)
      .sectionize("create", "Action: Create", "")
  }

  static var deleteParser: Parser<Action> {
    return Parser.ofString(EventName.delete.rawValue, Action.delete)
  }

  static var diagnoseParser: Parser<Action> {
    return Parser<(DiagnosticFormat, FBDiagnosticQuery)>
      .ofCommandWithArg(
        EventName.diagnose.rawValue,
        Parser.ofTwoSequenced(
          DiagnosticFormat.parser.fallback(DiagnosticFormat.current),
          FBDiagnosticQueryParser.parser
        )
      )
      .fmap { format, query in
        query.withFormat(format)
      }
      .fmap(Action.diagnose)
      .sectionize("diagnose", "Action: Diagnose", "")
  }

  static var eraseParser: Parser<Action> {
    return Parser.ofString(EventName.erase.rawValue, Action.erase)
  }

  static var focusParser: Parser<Action> {
    return Parser.ofString(EventName.focus.rawValue, Action.focus)
  }

  static var launchAgentParser: Parser<Action> {
    return Parser<FBAgentLaunchConfiguration>
      .ofCommandWithArg(
        EventName.launch.rawValue,
        FBProcessLaunchConfigurationParsers.agentLaunchParser
      )
      .fmap(Action.launchAgent)
      .sectionize("launch(agent)", "Action: Launch (Agent)", "")
  }

  static var launchAppParser: Parser<Action> {
    return Parser<FBApplicationLaunchConfiguration>
      .ofCommandWithArg(
        EventName.launch.rawValue,
        FBProcessLaunchConfigurationParsers.appLaunchParser
      )
      .fmap(Action.launchApp)
      .sectionize("launch(app)", "Action: Launch (App)", "")
  }

  static var launchXCTestParser: Parser<Action> {
    let optionalTimeoutFlag = Parser<Double>
      .ofFlagWithArg("test-timeout", Parser<Double>.ofDouble, "")
      .optional()

    let parser = Parser.ofThreeSequenced(
      optionalTimeoutFlag,
      Parser<Any>.ofExistingDirectory,
      FBProcessLaunchConfigurationParsers.appLaunchAndApplicationDescriptorParser
    )

    let configurationParser = parser
      .fmap { (timeout, bundle, appLaunch) -> FBTestLaunchConfiguration in
        var conf =
          FBTestLaunchConfiguration(testBundlePath: bundle)
          .withApplicationLaunchConfiguration(appLaunch.0)

        if let testHostPath = appLaunch.1?.path {
          conf = conf.withTestHostPath(testHostPath)
        }

        if timeout != nil {
          conf = conf.withTimeout(timeout!)
        }
        return conf
      }

    return Parser
      .ofCommandWithArg(
        EventName.launchXCTest.rawValue,
        configurationParser
      )
      .fmap(Action.launchXCTest)
      .sectionize("launch_xctest", "Action: Launch XCTest", "")
  }

  static var listenParser: Parser<Action> {
    return Parser<ListenInterface>
      .ofCommandWithArg(
        EventName.listen.rawValue,
        ListenInterface.parser
      )
      .fmap(Action.listen)
      .sectionize("listen", "Action: Listen", "")
  }

  static var listParser: Parser<Action> {
    return Parser.ofString(EventName.list.rawValue, Action.list)
  }

  static var listAppsParser: Parser<Action> {
    return Parser.ofString(EventName.listApps.rawValue, Action.listApps)
  }

  static var listDeviceSetsParser: Parser<Action> {
    return Parser.ofString(EventName.listDeviceSets.rawValue, Action.listDeviceSets)
  }

  static var openParser: Parser<Action> {
    return Parser<URL>
      .ofCommandWithArg(
        EventName.open.rawValue,
        Parser<URL>.ofURL
      )
      .fmap(Action.open)
  }

  static var installParser: Parser<Action> {
    return Parser
      .ofTwoSequenced(
        Parser<String>.ofCommandWithArg(EventName.install.rawValue, Parser<String>.ofAny),
        Parser<Bool>.ofFlag("codesign",
                            "Before installing, sign the bundle and all its frameworks with a certificate from the keychain")
      )
      .fmap { path, shouldCodesign in
        Action.install(path, shouldCodesign)
      }
  }

  static var keyboardOverrideParser: Parser<Action> {
    return Parser.ofString(EventName.keyboardOverride.rawValue, Action.keyboardOverride)
  }

  static var relaunchParser: Parser<Action> {
    return Parser<FBApplicationLaunchConfiguration>
      .ofCommandWithArg(
        EventName.relaunch.rawValue,
        FBProcessLaunchConfigurationParsers.appLaunchParser
      )
      .fmap(Action.relaunch)
      .sectionize("relaunch", "Action: Relaunch", "")
  }

  static var recordParser: Parser<Action> {
    return Parser<Record>
      .ofCommandWithArg(EventName.record.rawValue, Record.parser)
      .fmap(Action.record)
  }

  static var shutdownParser: Parser<Action> {
    return Parser.ofString(EventName.shutdown.rawValue, Action.shutdown)
  }

  static var tapParser: Parser<Action> {
    let coordParser: Parser<(Double, Double)> = Parser.ofTwoSequenced(
      Parser<Double>.ofDouble,
      Parser<Double>.ofDouble
    )

    return Parser
      .ofCommandWithArg(
        EventName.tap.rawValue,
        coordParser
      )
      .fmap(FBSimulatorHIDEvent.tapAt)
      .fmap(Action.hid)
  }

  static var serviceInfoParser: Parser<Action> {
    return Parser
      .ofCommandWithArg(
        EventName.serviceInfo.rawValue,
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
        EventName.setLocation.rawValue,
        latLngParser
      )
      .fmap { latitude, longitude in
        Action.setLocation(latitude, longitude)
      }
  }

  static var streamParser: Parser<Action> {
    return Parser
      .ofTwoSequenced(
        Parser.ofCommandWithArg(EventName.stream.rawValue, FBBitmapStreamConfigurationParser.parser),
        FileOutput.parser
      )
      .fmap(Action.stream)
  }

  static var tailParser: Parser<Action> {
    return Parser
      .ofCommandWithArg(
        EventName.logTail.rawValue,
        FBProcessLaunchConfigurationParsers.argumentParser
      )
      .fmap(FBLogTailConfiguration.init)
      .fmap(Action.logTail)
  }

  static var terminateParser: Parser<Action> {
    return Parser<String>
      .ofCommandWithArg(
        EventName.terminate.rawValue,
        Parser<String>.ofBundleIDOrApplicationDescriptorBundleID
      )
      .fmap(Action.terminate)
  }

  static var uninstallParser: Parser<Action> {
    return Parser<String>
      .ofCommandWithArg(
        EventName.uninstall.rawValue,
        Parser<String>.ofBundleIDOrApplicationDescriptorBundleID
      )
      .fmap(Action.uninstall)
  }

  static var uploadParser: Parser<Action> {
    return Parser<[String]>
      .ofCommandWithArg(
        EventName.upload.rawValue,
        Parser.manyCount(1, Parser<String>.ofExistingFile)
      )
      .fmap { paths in
        let diagnostics: [FBDiagnostic] = paths.map { path in
          FBDiagnosticBuilder().updatePath(path).build()
        }
        return Action.upload(diagnostics)
      }
  }

  static var watchdogOverrideParser: Parser<Action> {
    return Parser<(Double, [String])>
      .ofCommandWithArg(
        EventName.watchdogOverride.rawValue,
        Parser.ofTwoSequenced(
          Parser<Double>.ofDouble,
          Parser.manyCount(1, Parser<String>.ofBundleIDOrApplicationDescriptorBundleID)
        )
      )
      .fmap { Action.watchdogOverride($1, $0) }
      .sectionize("watchdog_override", "Action: Watchdog Override", "")
  }
}

extension DiagnosticFormat: Parsable {
  public static var parser: Parser<DiagnosticFormat> {
    return Parser
      .alternative([
        Parser<DiagnosticFormat>
          .ofFlag(DiagnosticFormat.current.rawValue,
                  DiagnosticFormat.current, ""),
        Parser<DiagnosticFormat>
          .ofFlag(DiagnosticFormat.path.rawValue,
                  DiagnosticFormat.path, ""),
        Parser<DiagnosticFormat>
          .ofFlag(DiagnosticFormat.content.rawValue,
                  DiagnosticFormat.content, ""),
      ])
  }
}

public struct FBiOSTargetFormatParsers {
  public static var parser: Parser<FBiOSTargetFormat> {
    let description = PrimitiveDesc(name: "Target Format", desc: "An iOS Target Format")
    return Parser<FBiOSTargetFormat>.ofFlagWithArg(
      "format",
      Parser.single(description, f: FBiOSTargetFormat.init),
      "An iOS Target Format"
    )
  }
}

public struct FBiOSTargetQueryParsers {
  public static var parser: Parser<FBiOSTargetQuery> {
    return Parser.alternative([
      self.allParser,
      self.unionParser,
    ])
      .sectionize("targets", "Targets", "")
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
      self.nameParser,
      self.simulatorStateParser,
      self.architectureParser,
      self.targetTypeParser,
      self.osVersionsParser,
      self.deviceParser,
    ])
      .sectionize("targets/query", "Target: Queries", "")
  }

  static var firstParser: Parser<FBiOSTargetQuery> {
    return Parser<Int>
      .ofFlagWithArg("first", Parser<Int>.ofInt, "")
      .fmap(FBiOSTargetQuery.ofCount)
  }

  static var uuidParser: Parser<FBiOSTargetQuery> {
    return Parser<FBiOSTargetQuery>
      .ofUDID
      .fmap(FBiOSTargetQuery.udid)
  }

  static var nameParser: Parser<FBiOSTargetQuery> {
    let parser: (String) -> FBiOSTargetQuery = FBiOSTargetQuery.named
    let description = PrimitiveDesc(name: "name", desc: "An iOS Target Name")
    return Parser<FBiOSTargetQuery>.ofFlagWithArg(
      "name",
      Parser.single(description, f: parser),
      "An iOS Target Name"
    )
  }

  static var architectureParser: Parser<FBiOSTargetQuery> {
    return Parser<FBArchitecture>
      .alternative(FBArchitecture.allFields.map(architectureSubparser))
      .fmap(FBiOSTargetQuery.architecture)
  }

  static func architectureSubparser(_ architecture: FBArchitecture) -> Parser<FBArchitecture> {
    return Parser<FBArchitecture>
      .ofFlag("arch=\(architecture.rawValue)", architecture, "")
  }

  static var simulatorStateParser: Parser<FBiOSTargetQuery> {
    return FBiOSTargetState
      .parser
      .fmap(FBiOSTargetQuery.state)
  }

  static var targetTypeParser: Parser<FBiOSTargetQuery> {
    return FBiOSTargetType
      .parser
      .fmap(FBiOSTargetQuery.targetType)
  }

  static var osVersionsParser: Parser<FBiOSTargetQuery> {
    return IndividualCreationConfiguration
      .osVersionParser
      .fmap(FBiOSTargetQuery.osVersion)
  }

  static var deviceParser: Parser<FBiOSTargetQuery> {
    return IndividualCreationConfiguration
      .deviceParser
      .fmap(FBiOSTargetQuery.device)
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
      .fmap { date, processType in
        FBDiagnosticQuery.crashes(of: processType, since: date)
      }
  }
}

extension FBSimulatorBootConfiguration {
  static func fromOptions(_ options: FBSimulatorBootOptions) -> FBSimulatorBootConfiguration {
    return FBSimulatorBootConfiguration.default.withOptions(options)
  }

  static func fromScale(_ scale: FBScale) -> FBSimulatorBootConfiguration {
    return FBSimulatorBootConfiguration.default.withScale(scale)
  }

  static func fromLocale(_ locale: Locale) -> FBSimulatorBootConfiguration {
    return FBSimulatorBootConfiguration.default.withLocalizationOverride(FBLocalizationOverride.withLocale(locale))
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
        self.optionsParser.fmap(FBSimulatorBootConfiguration.fromOptions),
        self.scaleParser.fmap(FBSimulatorBootConfiguration.fromScale),
        self.localeParser.fmap(FBSimulatorBootConfiguration.fromLocale),
      ])
  }

  static var localeParser: Parser<Locale> {
    return Parser<Locale>
      .ofFlagWithArg("locale", Parser<Locale>.ofLocale, "")
  }

  static var scaleParser: Parser<FBScale> {
    let subparsers: [Parser<FBScale>] = [
      Parser<FBScale>
        .ofFlag("scale=25", .scale25, ""),
      Parser<FBScale>
        .ofFlag("scale=50", .scale50, ""),
      Parser<FBScale>
        .ofFlag("scale=75", .scale75, ""),
      Parser<FBScale>
        .ofFlag("scale=100", .scale100, ""),
    ]

    return Parser.alternative(subparsers)
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
  static var appLaunchAndApplicationDescriptorParser: Parser<(FBApplicationLaunchConfiguration, FBBundleDescriptor?)> {
    return Parser
      .ofFourSequenced(
        FBProcessOutputConfigurationParser.parser,
        waitForDebuggerParser,
        Parser<Any>.ofBundleIDOrApplicationDescriptor,
        argumentParser
      )
      .fmap { output, waitForDebugger, bundleIDOrApplicationDescriptor, arguments in
        let (bundleId, appDescriptor) = bundleIDOrApplicationDescriptor
        var appLaunchConfig = FBApplicationLaunchConfiguration(
          bundleID: bundleId,
          bundleName: nil,
          arguments: arguments,
          environment: [:],
          output: output,
          launchMode: FBApplicationLaunchMode.failIfRunning
        )
        if waitForDebugger {
          appLaunchConfig = appLaunchConfig.withWaitForDebugger(nil)
        }
        return (appLaunchConfig, appDescriptor)
      }
  }

  static var appLaunchParser: Parser<FBApplicationLaunchConfiguration> {
    return appLaunchAndApplicationDescriptorParser.fmap { $0.0 }
  }

  static var agentLaunchParser: Parser<FBAgentLaunchConfiguration> {
    return Parser
      .ofThreeSequenced(
        FBProcessOutputConfigurationParser.parser,
        Parser<Any>.ofBinary,
        argumentParser
      )
      .fmap { output, binary, arguments in
        FBAgentLaunchConfiguration(binary: binary, arguments: arguments, environment: [:], output: output)
      }
  }

  static var argumentParser: Parser<[String]> {
    return Parser
      .manyTill(
        Parser<NSNull>.ofDashSeparator,
        Parser<String>.ofAny
      )
  }

  static var waitForDebuggerParser: Parser<Bool> {
    return Parser<Bool>
      .alternative([
        Parser<Bool>.ofString("--wait-for-debugger", true),
        Parser<Bool>.ofString("-w", true),
      ])
      .fallback(false)
  }
}

/**
 A separate struct for FBProcessOutputConfiguration is needed as Parsable protcol conformance cannot be
 applied to FBProcessOutputConfiguration as it is a non-final class.
 */
struct FBProcessOutputConfigurationParser {
  public static var parser: Parser<FBProcessOutputConfiguration> {
    return Parser<FBProcessOutputConfiguration>.accumulate(0, [
      Parser<FBProcessOutputConfiguration>.ofFlag(
        "stdout",
        try! FBProcessOutputConfiguration(stdOut: FBProcessOutputToFileDefaultLocation, stdErr: NSNull()),
        ""
      ),
      Parser<FBProcessOutputConfiguration>.ofFlag(
        "stderr",
        try! FBProcessOutputConfiguration(stdOut: NSNull(), stdErr: FBProcessOutputToFileDefaultLocation),
        ""
      ),
    ])
  }
}

struct FBBitmapStreamConfigurationParser {
  public static var parser: Parser<FBBitmapStreamConfiguration> {
    let typeParser = Parser<FBBitmapStreamEncoding>
      .alternative([
        Parser<FBBitmapStreamEncoding>
          .ofFlag("h264", .H264, "Output in h264 format."),
        Parser<FBBitmapStreamEncoding>
          .ofFlag("bgra", .BGRA, "Output in BGRA format."),
      ])
      .fallback(.BGRA)
    let fpsParser = Parser<NSNumber>
      .ofFlagWithArg("fps", Parser<Int>.ofInt, "Frames Per Second of Output")
      .fmap { NSNumber(integerLiteral: $0) }
      .optional()
    return Parser
      .ofTwoSequenced(
        typeParser,
        fpsParser
      )
      .fmap(FBBitmapStreamConfiguration.init)
  }
}
