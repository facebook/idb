/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

import XCTest
import FBSimulatorControl
@testable import FBSimulatorControlKit


class FBiOSTargetFormatParserTests : XCTestCase {
  func testParsesKeywords() {
    self.assertParsesAll(FBiOSTargetFormatParsers.parser, [
      (["--udid"], FBiOSTargetFormat(fields: [FBiOSTargetFormatUDID])),
      (["--name"], FBiOSTargetFormat(fields: [FBiOSTargetFormatName])),
      (["--device-name"], FBiOSTargetFormat(fields: [FBiOSTargetFormatDeviceName])),
      (["--os"], FBiOSTargetFormat(fields: [FBiOSTargetFormatOSVersion])),
      (["--state"], FBiOSTargetFormat(fields: [FBiOSTargetFormatState])),
      (["--pid"], FBiOSTargetFormat(fields: [FBiOSTargetFormatProcessIdentifier])),
      (["--container_pid"], FBiOSTargetFormat(fields: [FBiOSTargetFormatContainerApplicationProcessIdentifier]))
    ])
  }
}

class FBSimulatorManagementOptionsParserTests : XCTestCase {
  func testParsesSimple() {
    self.assertParsesAll(FBSimulatorManagementOptions.parser, [
      (["--delete-all"], FBSimulatorManagementOptions.DeleteAllOnFirstStart),
      (["--kill-all"], FBSimulatorManagementOptions.KillAllOnFirstStart),
      (["--kill-spurious"], FBSimulatorManagementOptions.KillSpuriousSimulatorsOnFirstStart),
      (["--ignore-spurious-kill-fail"], FBSimulatorManagementOptions.IgnoreSpuriousKillFail),
      (["--kill-spurious-services"], FBSimulatorManagementOptions.KillSpuriousCoreSimulatorServices),
      (["--timeout-resiliance"], FBSimulatorManagementOptions.UseSimDeviceTimeoutResiliance)
    ])
  }

  func testParsesCompound() {
    self.assertParsesAll(FBSimulatorManagementOptions.parser, [
      (["--delete-all", "--kill-all"], FBSimulatorManagementOptions.DeleteAllOnFirstStart.union(.KillAllOnFirstStart)),
      (["--kill-spurious-services"], FBSimulatorManagementOptions.KillSpuriousCoreSimulatorServices),
      (["--ignore-spurious-kill-fail", "--timeout-resiliance"], FBSimulatorManagementOptions.IgnoreSpuriousKillFail.union(.UseSimDeviceTimeoutResiliance)),
      (["--kill-spurious", "--ignore-spurious-kill-fail"], FBSimulatorManagementOptions.KillSpuriousSimulatorsOnFirstStart.union(.IgnoreSpuriousKillFail))
    ])
  }
}


class CreationSpecificationParserTests : XCTestCase {
  func testParses() {
    self.assertParsesAll(CreationSpecification.parser, [
      ([], CreationSpecification.empty),
      (["iOS 9.0"], CreationSpecification.iOS9CreationSpecification),
      (["iPhone 6"], CreationSpecification.iPhone6Configuration),
      (["--aux", "/usr/bin"], CreationSpecification.auxDirectoryConfiguration),
      (["iPhone 6s", "iOS 9.3"], CreationSpecification.compoundConfiguration0),
      (["iPad Air 2", "iOS 10.0"], CreationSpecification.compoundConfiguration1),
    ])
  }
}

class FBSimulatorLaunchConfigurationTests : XCTestCase {
  func testParsesLocale() {
    self.assertParses(
      FBSimulatorLaunchConfigurationParser.parser,
      ["--locale", "fr_FR"],
      FBSimulatorLaunchConfiguration.defaultConfiguration().withLocalizationOverride(FBLocalizationOverride.withLocale(NSLocale(localeIdentifier: "fr_FR")))
    )
  }

  func testParsesScale() {
    self.assertParses(
      FBSimulatorLaunchConfigurationParser.parser,
      ["--scale=50"],
      FBSimulatorLaunchConfiguration.defaultConfiguration().scale50Percent()
    )
  }

  func testParsesConnectBridge() {
    self.assertParses(
      FBSimulatorLaunchConfigurationParser.parser,
      ["--connect-bridge"],
      FBSimulatorLaunchConfiguration
        .defaultConfiguration()
        .withOptions(FBSimulatorLaunchOptions.ConnectBridge)
    )
  }

  func testUseNSWorkspace() {
    self.assertParses(
      FBSimulatorLaunchConfigurationParser.parser,
      ["--use-nsworkspace"],
      FBSimulatorLaunchConfiguration
        .defaultConfiguration()
        .withOptions(FBSimulatorLaunchOptions.UseNSWorkspace)
    )
  }

  func testParsesDirectLaunchToMakeFramebuffer() {
    self.assertParses(
      FBSimulatorLaunchConfigurationParser.parser,
      ["--direct-launch"],
      FBSimulatorLaunchConfiguration.defaultConfiguration()
        .withOptions(FBSimulatorLaunchOptions.EnableDirectLaunch)
        .withFramebuffer(FBFramebufferConfiguration.defaultConfiguration())
    )
  }

  func testParsesAllTheAbove() {
    self.assertParses(
      FBSimulatorLaunchConfigurationParser.parser,
      ["--locale", "en_GB", "--scale=75", "--direct-launch", "--connect-bridge"],
      FBSimulatorLaunchConfiguration.defaultConfiguration()
        .withLocalizationOverride(FBLocalizationOverride.withLocale(NSLocale(localeIdentifier: "en_GB")))
        .scale75Percent()
        .withOptions(FBSimulatorLaunchOptions.EnableDirectLaunch.union(.ConnectBridge))
        .withFramebuffer(FBFramebufferConfiguration.defaultConfiguration())
    )
  }
}

let validConfigurations: [([String], Configuration)] = [
  ([], Configuration.defaultValue),
  (["--debug-logging"], Configuration(outputOptions: OutputOptions.DebugLogging, managementOptions: FBSimulatorManagementOptions(), deviceSetPath: nil)),
  (["--kill-all", "--kill-spurious"], Configuration(outputOptions: OutputOptions(), managementOptions: FBSimulatorManagementOptions.KillAllOnFirstStart.union(.KillSpuriousSimulatorsOnFirstStart), deviceSetPath: nil)),
  (["--set", "/usr/bin"], Configuration(outputOptions: OutputOptions(), managementOptions: FBSimulatorManagementOptions(), deviceSetPath: "/usr/bin")),
  (["--debug-logging", "--set", "/usr/bin", "--delete-all", "--kill-spurious"], Configuration(outputOptions: OutputOptions.DebugLogging, managementOptions: FBSimulatorManagementOptions.DeleteAllOnFirstStart.union(.KillSpuriousSimulatorsOnFirstStart), deviceSetPath: "/usr/bin")),
  (["--delete-all", "--set", "/usr/bin", "--debug-logging", "--kill-spurious"], Configuration(outputOptions: OutputOptions.DebugLogging, managementOptions: FBSimulatorManagementOptions.DeleteAllOnFirstStart.union(.KillSpuriousSimulatorsOnFirstStart), deviceSetPath: "/usr/bin")),
  (["--set", "/usr/bin", "--delete-all", "--kill-spurious"], Configuration(outputOptions: OutputOptions(), managementOptions: FBSimulatorManagementOptions.DeleteAllOnFirstStart.union(.KillSpuriousSimulatorsOnFirstStart), deviceSetPath: "/usr/bin"))
]

let validQueries: [([String], FBiOSTargetQuery)] = [
  (["all"], FBiOSTargetQuery.allTargets()),
  (["iPhone 5"], FBiOSTargetQuery.devices([FBControlCoreConfiguration_Device_iPhone5()])),
  (["iPad 2"], FBiOSTargetQuery.devices([FBControlCoreConfiguration_Device_iPad2()])),
  (["iOS 9.0", "iOS 9.1"], FBiOSTargetQuery.osVersions([FBControlCoreConfiguration_iOS_9_0(), FBControlCoreConfiguration_iOS_9_1()])),
  (["--state=creating"], FBiOSTargetQuery.simulatorStates([.Creating])),
  (["--state=shutdown"], FBiOSTargetQuery.simulatorStates([.Shutdown])),
  (["--state=booted"], FBiOSTargetQuery.simulatorStates([.Booted])),
  (["--state=booting"], FBiOSTargetQuery.simulatorStates([.Booting])),
  (["--state=shutting-down"], FBiOSTargetQuery.simulatorStates([.ShuttingDown])),
  (["--simulators"], FBiOSTargetQuery.targetType(FBiOSTargetType.Simulator)),
  (["--devices"], FBiOSTargetQuery.targetType(FBiOSTargetType.Device)),
  (["--simulators", "--devices", "iPhone 6s"], FBiOSTargetQuery.targetType(FBiOSTargetType.Simulator.union(FBiOSTargetType.Device)).devices([FBControlCoreConfiguration_Device_iPhone6S()])),
  (["--first", "2", "iPhone 6"], FBiOSTargetQuery.devices([FBControlCoreConfiguration_Device_iPhone6()]).ofCount(2)),
  (["B8EEA6C4-841B-47E5-92DE-014E0ECD8139"], FBiOSTargetQuery.udids(["B8EEA6C4-841B-47E5-92DE-014E0ECD8139"])),
  (["0123456789abcdefABCDEFaaaaaaaaaaaaaaaaaa"], FBiOSTargetQuery.udids(["0123456789abcdefABCDEFaaaaaaaaaaaaaaaaaa"])),
  (["iPhone 5", "iPad 2"], FBiOSTargetQuery.devices([FBControlCoreConfiguration_Device_iPhone5(), FBControlCoreConfiguration_Device_iPad2()])),
  (["--state=creating", "--state=booting", "--state=shutdown"], FBiOSTargetQuery.simulatorStates([.Creating, .Booting, .Shutdown])),
  (["B8EEA6C4-841B-47E5-92DE-014E0ECD8139", "124DAC9C-4DFF-4F0C-9828-998CCFFCD4C8", "0123456789abcdefABCDEFaaaaaaaaaaaaaaaaaa"], FBiOSTargetQuery.udids(["B8EEA6C4-841B-47E5-92DE-014E0ECD8139", "124DAC9C-4DFF-4F0C-9828-998CCFFCD4C8", "0123456789abcdefABCDEFaaaaaaaaaaaaaaaaaa"])),
  (["iPhone 6", "124DAC9C-4DFF-4F0C-9828-998CCFFCD4C8"], FBiOSTargetQuery.devices([FBControlCoreConfiguration_Device_iPhone6()]).udids(["124DAC9C-4DFF-4F0C-9828-998CCFFCD4C8"])),
]

let invalidQueries: [[String]] = [
  ["Galaxy S5"],
  ["Nexus Chromebook Pixel G4 Droid S5 S1 S4 4S"],
  ["makingtea"],
  ["B8EEA6C4-47E5-92DE-014E0ECD8139"],
  ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaag"],
  ["Nexus 5", "iPhone 5", "iPad 2"],
  ["jelly", "--state=creating", "--state=booting", "shutdown"],
  ["banana", "B8EEA6C4-841B-47E5-92DE-014E0ECD8139", "D7DA55E9-26FF-44FD-91A1-5B30DB68A4BB"],
]

let validActions: [([String], Action)] = [
  (["approve", "com.foo.bar", "com.bing.bong"], Action.Approve(["com.foo.bar", "com.bing.bong"])),
  (["approve", Fixtures.application.path], Action.Approve([Fixtures.application.bundleID])),
  (["boot", "--locale", "en_US", "--scale=75"], Action.Boot(FBSimulatorLaunchConfiguration.defaultConfiguration().withLocalizationOverride(FBLocalizationOverride.withLocale(NSLocale(localeIdentifier: "en_US"))).scale75Percent())),
  (["boot", "--locale", "fr_FR"], Action.Boot(FBSimulatorLaunchConfiguration.defaultConfiguration().withLocalizationOverride(FBLocalizationOverride.withLocale(NSLocale(localeIdentifier: "fr_FR"))))),
  (["boot", "--scale=50"], Action.Boot(FBSimulatorLaunchConfiguration.defaultConfiguration().scale50Percent())),
  (["boot", "--scale=25", "--connect-bridge", "--use-nsworkspace"], Action.Boot(FBSimulatorLaunchConfiguration.defaultConfiguration().scale25Percent().withOptions(FBSimulatorLaunchOptions.ConnectBridge.union(FBSimulatorLaunchOptions.UseNSWorkspace)))),
  (["boot"], Action.Boot(nil)),
  (["clear_keychain", "com.foo.bar"], Action.ClearKeychain("com.foo.bar")),
  (["clear_keychain"], Action.ClearKeychain(nil)),
  (["config"], Action.Config),
  (["create", "--all-missing-defaults"], Action.Create(CreationSpecification.AllMissingDefaults)),
  (["create", "iOS 9.0"], Action.Create(CreationSpecification.iOS9CreationSpecification)),
  (["create", "iPhone 6s", "iOS 9.3"], Action.Create(CreationSpecification.compoundConfiguration0)),
  (["create", "iPhone 6"], Action.Create(CreationSpecification.iPhone6Configuration)),
  (["delete"], Action.Delete),
  (["diagnose", "--content", "--crashes-since", "200", "--system"], Action.Diagnose(FBSimulatorDiagnosticQuery.crashesOfType(FBCrashLogInfoProcessType.System, since: NSDate(timeIntervalSince1970: 200)), DiagnosticFormat.Content)),
  (["diagnose", "--content", "com.foo.bar", "foo.txt", "bar.txt"], Action.Diagnose(FBSimulatorDiagnosticQuery.filesInApplicationOfBundleID("com.foo.bar", withFilenames: ["foo.txt", "bar.txt"]), DiagnosticFormat.Content)),
  (["diagnose", "--crashes-since", "300", "--custom-agent"], Action.Diagnose(FBSimulatorDiagnosticQuery.crashesOfType(FBCrashLogInfoProcessType.CustomAgent, since: NSDate(timeIntervalSince1970: 300)), DiagnosticFormat.CurrentFormat)),
  (["diagnose", "--name", "log1", "--name", "log2"], Action.Diagnose(FBSimulatorDiagnosticQuery.named(["log1", "log2"]), DiagnosticFormat.CurrentFormat)),
  (["diagnose", "--path", "--crashes-since", "100", "--application"], Action.Diagnose(FBSimulatorDiagnosticQuery.crashesOfType(FBCrashLogInfoProcessType.Application, since: NSDate(timeIntervalSince1970: 100)), DiagnosticFormat.Path)),
  (["diagnose"], Action.Diagnose(FBSimulatorDiagnosticQuery.all(), DiagnosticFormat.CurrentFormat)),
  (["erase"], Action.Erase),
  (["install", Fixtures.application.path], Action.Install(Fixtures.application.path)),
  (["launch", "--stderr", "com.foo.bar", "--foo", "-b", "-a", "-r"], Action.LaunchApp(FBApplicationLaunchConfiguration(bundleID: "com.foo.bar", bundleName: nil, arguments: ["--foo", "-b", "-a", "-r"], environment: [:], options: .WriteStderr))),
  (["launch", "com.foo.bar"], Action.LaunchApp(FBApplicationLaunchConfiguration(bundleID: "com.foo.bar", bundleName: nil, arguments: [], environment: [:], options: FBProcessLaunchOptions()))),
  (["launch", "--stderr", Fixtures.application.path], Action.LaunchApp(FBApplicationLaunchConfiguration(bundleID: Fixtures.application.bundleID, bundleName: nil, arguments: [], environment: [:], options: .WriteStderr))),
  (["launch", Fixtures.application.path], Action.LaunchApp(FBApplicationLaunchConfiguration(bundleID: Fixtures.application.bundleID, bundleName: nil, arguments: [], environment: [:], options: FBProcessLaunchOptions()))),
  (["launch", Fixtures.binary.path, "--foo", "-b", "-a", "-r"], Action.LaunchAgent(FBAgentLaunchConfiguration(binary: Fixtures.binary, arguments: ["--foo", "-b", "-a", "-r"], environment: [:], options: FBProcessLaunchOptions()))),
  (["launch", Fixtures.binary.path], Action.LaunchAgent(FBAgentLaunchConfiguration(binary: Fixtures.binary, arguments: [], environment: [:], options: FBProcessLaunchOptions()))),
  (["launch_xctest", "/usr/bin", "com.foo.bar", "--foo", "-b", "-a", "-r"], Action.LaunchXCTest(FBApplicationLaunchConfiguration(bundleID: "com.foo.bar", bundleName: nil, arguments: ["--foo", "-b", "-a", "-r"], environment: [:], options: FBProcessLaunchOptions()), "/usr/bin", nil)),
  (["launch_xctest", "/usr/bin", "com.foo.bar"], Action.LaunchXCTest(FBApplicationLaunchConfiguration(bundleID: "com.foo.bar", bundleName: nil, arguments: [], environment: [:], options: FBProcessLaunchOptions()), "/usr/bin", nil)),
  (["launch_xctest", "/usr/bin", Fixtures.application.path], Action.LaunchXCTest(FBApplicationLaunchConfiguration(bundleID: Fixtures.application.bundleID, bundleName: nil, arguments: [], environment: [:], options: FBProcessLaunchOptions()), "/usr/bin", nil)),
  (["launch_xctest", "/usr/bin", Fixtures.application.path], Action.LaunchXCTest(FBApplicationLaunchConfiguration(bundleID: Fixtures.application.bundleID, bundleName: nil, arguments: [], environment: [:], options: FBProcessLaunchOptions()), "/usr/bin", nil)),
  (["launch_xctest", "--test-timeout", "900", "/usr/bin", Fixtures.application.path], Action.LaunchXCTest(FBApplicationLaunchConfiguration(bundleID: Fixtures.application.bundleID, bundleName: nil, arguments: [], environment: [:], options: FBProcessLaunchOptions()), "/usr/bin", 900)),
  (["list"], Action.List),
  (["list_apps"], Action.ListApps),
  (["list_device_sets"], Action.ListDeviceSets),
  (["listen", "--http", "43"], Action.Listen(Server.Http(43))),
  (["listen", "--socket", "42"], Action.Listen(Server.Socket(42))),
  (["listen"], Action.Listen(Server.StdIO)),
  (["open", "aoo://bar/baz"], Action.Open(NSURL(string: "aoo://bar/baz")!)),
  (["open", "http://facebook.com"], Action.Open(NSURL(string: "http://facebook.com")!)),
  (["record", "start"], Action.Record(true)),
  (["record", "stop"], Action.Record(false)),
  (["relaunch", "com.foo.bar", "--foo", "-b", "-a", "-r"], Action.Relaunch(FBApplicationLaunchConfiguration(bundleID: "com.foo.bar", bundleName: nil, arguments: ["--foo", "-b", "-a", "-r"], environment: [:], options: FBProcessLaunchOptions()))),
  (["relaunch", "com.foo.bar"], Action.Relaunch(FBApplicationLaunchConfiguration(bundleID: "com.foo.bar", bundleName: nil, arguments: [], environment: [:], options: FBProcessLaunchOptions()))),
  (["shutdown"], Action.Shutdown),
  (["shutdown"], Action.Shutdown),
  (["terminate", "com.foo.bar"], Action.Terminate("com.foo.bar")),
  (["uninstall", "com.foo.bar"], Action.Uninstall("com.foo.bar")),
  (["upload", Fixtures.photoPath, Fixtures.videoPath], Action.Upload([Fixtures.photoDiagnostic, Fixtures.videoDiagnostic])),
  (["watchdog_override", "60", "com.foo.bar", "com.bar.baz"], Action.WatchdogOverride(["com.foo.bar", "com.bar.baz"], 60)),
  (["set_location", "39.9", "116.39"], Action.SetLocation(39.9, 116.39)),
]

let invalidActions: [[String]] = [
  ["aboota"],
  ["approve", "dontadddotstome"],
  ["approve"],
  ["ddshutdown"],
  ["install"],
  ["listaa"],
]

class ConfigurationParserTests : XCTestCase {
  func testParsesValidConfigurations() {
    self.assertParsesAll(Configuration.parser, validConfigurations)
  }
}

class QueryParserTests : XCTestCase {
  func testParsesValidQueries() {
    self.assertParsesAll(FBiOSTargetQueryParsers.parser, validQueries)
  }

  func testParsesInvalidQueries() {
    self.assertFailsToParseAll(FBiOSTargetQueryParsers.parser, invalidQueries)
  }
}

class ActionParserTests : XCTestCase {
  func testParsesValidActions() {
    self.assertParsesAll(Action.parser, validActions)
  }

  func testFailsToParseInvalidActions() {
    self.assertFailsToParseAll(Action.parser, invalidActions)
  }
}

class CommandParserTests : XCTestCase {
  func testParsesValidActions() {
    for (suffix, action) in validActions {
      self.assertWithDefaultAction(action, suffix: suffix)
    }
  }

  func testParsesListBootListenShutdown() {
    let compoundComponents = [
      ["list"], ["boot"], ["listen", "--http", "1000"], ["shutdown"],
    ]
    let actions: [Action] = [Action.List, Action.Boot(nil), Action.Listen(Server.Http(1000)), Action.Shutdown]
    self.assertParsesImplodingCompoundActions(actions, compoundComponents: compoundComponents)
  }

  func testParsesListBootListenShutdownDiagnose() {
    let compoundComponents = [
      ["list"], ["create", "iPhone 6"], ["boot", "--direct-launch"], ["listen", "--http", "8090"], ["shutdown"], ["diagnose"],
    ]
    let launchConfiguration = FBSimulatorLaunchConfiguration.defaultConfiguration()
      .withOptions(FBSimulatorLaunchOptions.EnableDirectLaunch)
      .withFramebuffer(FBFramebufferConfiguration.defaultConfiguration())
    let diagnoseAction = Action.Diagnose(FBSimulatorDiagnosticQuery.all(), DiagnosticFormat.CurrentFormat)
    let actions: [Action] = [Action.List, Action.Create(CreationSpecification.iPhone6Configuration), Action.Boot(launchConfiguration), Action.Listen(Server.Http(8090)), Action.Shutdown, diagnoseAction]
    self.assertParsesImplodingCompoundActions(actions, compoundComponents: compoundComponents)
  }

  func testFailsToParseDanglingTokens() {
    let compoundComponents = [
      ["list"], ["create", "iPhone 5"], ["boot", "--direct-launch"], ["listen", "--http", "8090"], ["YOLO"],
    ]
    self.assertFailsToParseImplodingCompoundActions(compoundComponents)
  }

  func testParsesMultipleConsecutiveLaunches() {
    let compoundComponents = [
      ["launch", "--stdout", "com.foo.bar", "--foo", "--bar"], ["launch", Fixtures.application.path, "--bing", "--bong"],
    ]
    let launchConfig1 = FBApplicationLaunchConfiguration(bundleID: "com.foo.bar", bundleName: nil, arguments: ["--foo", "--bar"], environment: [:], options: .WriteStdout)
    let launchConfig2 = FBApplicationLaunchConfiguration(bundleID: Fixtures.application.bundleID, bundleName: nil, arguments: ["--bing", "--bong"], environment: [:], options: FBProcessLaunchOptions())
    let actions: [Action] = [Action.LaunchApp(launchConfig1), Action.LaunchApp(launchConfig2)]
    self.assertParsesImplodingCompoundActions(actions, compoundComponents: compoundComponents)
  }

  func assertWithDefaultAction(action: Action, suffix: [String]) {
    self.assertWithDefaultActions([action], suffix: suffix)
  }

  func assertWithDefaultActions(actions: [Action], suffix: [String]) {
    return self.unzipAndAssert(actions, suffix: suffix, extras: [
      ([], nil, nil),
      (["all"], FBiOSTargetQuery.allTargets(), nil),
      (["iPad 2"], FBiOSTargetQuery.devices([FBControlCoreConfiguration_Device_iPad2()]), nil),
      (["B8EEA6C4-841B-47E5-92DE-014E0ECD8139"], FBiOSTargetQuery.udids(["B8EEA6C4-841B-47E5-92DE-014E0ECD8139"]), nil),
      (["iPhone 5", "--state=shutdown", "iPhone 6"], FBiOSTargetQuery.devices([FBControlCoreConfiguration_Device_iPhone5(), FBControlCoreConfiguration_Device_iPhone6()]).simulatorStates([.Shutdown]), nil),
      (["iPad 2", "--device-name", "--os"], FBiOSTargetQuery.devices([FBControlCoreConfiguration_Device_iPad2()]), FBiOSTargetFormat(fields: [FBiOSTargetFormatDeviceName, FBiOSTargetFormatOSVersion])),
      (["B8EEA6C4-841B-47E5-92DE-014E0ECD8139"], FBiOSTargetQuery.udids(["B8EEA6C4-841B-47E5-92DE-014E0ECD8139"]), nil),
    ])
  }

  func assertParsesImplodingCompoundActions(actions: [Action], compoundComponents: [[String]]) {
    self.assertWithDefaultActions(actions, suffix: CommandParserTests.implodeCompoundActions(compoundComponents))
  }

  func assertFailsToParseImplodingCompoundActions(compoundComponents: [[String]]) {
    self.assertParseFails(
      Command.parser,
      CommandParserTests.implodeCompoundActions(compoundComponents)
    )
  }

  func unzipAndAssert(actions: [Action], suffix: [String], extras: [([String], FBiOSTargetQuery?, FBiOSTargetFormat?)]) {
    let pairs = extras.map { (tokens, query, format) in
      return (tokens + suffix, Command(configuration: Configuration.defaultValue, actions: actions, query: query, format: format))
    }
    self.assertParsesAll(Command.parser, pairs)
  }

  static func implodeCompoundActions(compoundComponents: [[String]]) -> [String] {
    return Array(compoundComponents.joinWithSeparator(["--"]))
  }
}
