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
      (["--delete-all"], FBSimulatorManagementOptions.deleteAllOnFirstStart),
      (["--kill-all"], FBSimulatorManagementOptions.killAllOnFirstStart),
      (["--kill-spurious"], FBSimulatorManagementOptions.killSpuriousSimulatorsOnFirstStart),
      (["--ignore-spurious-kill-fail"], FBSimulatorManagementOptions.ignoreSpuriousKillFail),
      (["--kill-spurious-services"], FBSimulatorManagementOptions.killSpuriousCoreSimulatorServices),
    ])
  }

  func testParsesCompound() {
    self.assertParsesAll(FBSimulatorManagementOptions.parser, [
      (["--delete-all", "--kill-all"], FBSimulatorManagementOptions.deleteAllOnFirstStart.union(.killAllOnFirstStart)),
      (["--ignore-spurious-kill-fail", "--kill-spurious-services"], FBSimulatorManagementOptions.ignoreSpuriousKillFail.union(.killSpuriousCoreSimulatorServices)),
      (["--kill-spurious", "--ignore-spurious-kill-fail"], FBSimulatorManagementOptions.killSpuriousSimulatorsOnFirstStart.union(.ignoreSpuriousKillFail))
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

class FBSimulatorBootConfigurationTests : XCTestCase {
  func testParsesLocale() {
    self.assertParses(
      FBSimulatorBootConfigurationParser.parser,
      ["--locale", "fr_FR"],
      FBSimulatorBootConfiguration.default().withLocalizationOverride(FBLocalizationOverride.withLocale(Locale(identifier: "fr_FR")))
    )
  }

  func testParsesScale() {
    self.assertParses(
      FBSimulatorBootConfigurationParser.parser,
      ["--scale=50"],
      FBSimulatorBootConfiguration.default().scale50Percent()
    )
  }

  func testParsesConnectBridge() {
    self.assertParses(
      FBSimulatorBootConfigurationParser.parser,
      ["--connect-bridge"],
      FBSimulatorBootConfiguration
        .default()
        .withOptions([.connectBridge, .awaitServices])
    )
  }

  func testUseNSWorkspace() {
    self.assertParses(
      FBSimulatorBootConfigurationParser.parser,
      ["--use-nsworkspace"],
      FBSimulatorBootConfiguration
        .default()
        .withOptions([.useNSWorkspace, .awaitServices])
    )
  }

  func testParsesDirectLaunchToMakeFramebuffer() {
    self.assertParses(
      FBSimulatorBootConfigurationParser.parser,
      ["--direct-launch"],
      FBSimulatorBootConfiguration.default()
        .withOptions([.enableDirectLaunch, .awaitServices])
        .withFramebuffer(FBFramebufferConfiguration.default())
    )
  }

  func testParsesAllTheAbove() {
    self.assertParses(
      FBSimulatorBootConfigurationParser.parser,
      ["--locale", "en_GB", "--scale=75", "--direct-launch", "--connect-bridge"],
      FBSimulatorBootConfiguration.default()
        .withLocalizationOverride(FBLocalizationOverride.withLocale(Locale(identifier: "en_GB")))
        .scale75Percent()
        .withOptions([.enableDirectLaunch, .connectBridge, .awaitServices])
        .withFramebuffer(FBFramebufferConfiguration.default())
    )
  }
}

let validConfigurations: [([String], Configuration)] = [
  ([], Configuration.defaultValue),
  (["--debug-logging"], Configuration(outputOptions: OutputOptions.DebugLogging, managementOptions: FBSimulatorManagementOptions(), deviceSetPath: nil)),
  (["--kill-all", "--kill-spurious"], Configuration(outputOptions: OutputOptions(), managementOptions: FBSimulatorManagementOptions.killAllOnFirstStart.union(.killSpuriousSimulatorsOnFirstStart), deviceSetPath: nil)),
  (["--set", "/usr/bin"], Configuration(outputOptions: OutputOptions(), managementOptions: FBSimulatorManagementOptions(), deviceSetPath: "/usr/bin")),
  (["--debug-logging", "--set", "/usr/bin", "--delete-all", "--kill-spurious"], Configuration(outputOptions: OutputOptions.DebugLogging, managementOptions: FBSimulatorManagementOptions.deleteAllOnFirstStart.union(.killSpuriousSimulatorsOnFirstStart), deviceSetPath: "/usr/bin")),
  (["--delete-all", "--set", "/usr/bin", "--debug-logging", "--kill-spurious"], Configuration(outputOptions: OutputOptions.DebugLogging, managementOptions: FBSimulatorManagementOptions.deleteAllOnFirstStart.union(.killSpuriousSimulatorsOnFirstStart), deviceSetPath: "/usr/bin")),
  (["--set", "/usr/bin", "--delete-all", "--kill-spurious"], Configuration(outputOptions: OutputOptions(), managementOptions: FBSimulatorManagementOptions.deleteAllOnFirstStart.union(.killSpuriousSimulatorsOnFirstStart), deviceSetPath: "/usr/bin"))
]

let validQueries: [([String], FBiOSTargetQuery)] = [
  (["all"], FBiOSTargetQuery.allTargets()),
  (["iPhone 5"], FBiOSTargetQuery.devices([FBControlCoreConfiguration_Device_iPhone5()])),
  (["iPad 2"], FBiOSTargetQuery.devices([FBControlCoreConfiguration_Device_iPad2()])),
  (["iOS 9.0", "iOS 9.1"], FBiOSTargetQuery.osVersions([FBControlCoreConfiguration_iOS_9_0(), FBControlCoreConfiguration_iOS_9_1()])),
  (["--state=creating"], FBiOSTargetQuery.simulatorStates([.creating])),
  (["--state=shutdown"], FBiOSTargetQuery.simulatorStates([.shutdown])),
  (["--state=booted"], FBiOSTargetQuery.simulatorStates([.booted])),
  (["--state=booting"], FBiOSTargetQuery.simulatorStates([.booting])),
  (["--state=shutting-down"], FBiOSTargetQuery.simulatorStates([.shuttingDown])),
  (["--simulators"], FBiOSTargetQuery.targetType(FBiOSTargetType.simulator)),
  (["--devices"], FBiOSTargetQuery.targetType(FBiOSTargetType.device)),
  (["--simulators", "--devices", "iPhone 6s"], FBiOSTargetQuery.targetType(FBiOSTargetType.simulator.union(FBiOSTargetType.device)).devices([FBControlCoreConfiguration_Device_iPhone6S()])),
  (["--first", "2", "iPhone 6"], FBiOSTargetQuery.devices([FBControlCoreConfiguration_Device_iPhone6()]).ofCount(2)),
  (["B8EEA6C4-841B-47E5-92DE-014E0ECD8139"], FBiOSTargetQuery.udids(["B8EEA6C4-841B-47E5-92DE-014E0ECD8139"])),
  (["0123456789abcdefABCDEFaaaaaaaaaaaaaaaaaa"], FBiOSTargetQuery.udids(["0123456789abcdefABCDEFaaaaaaaaaaaaaaaaaa"])),
  (["iPhone 5", "iPad 2"], FBiOSTargetQuery.devices([FBControlCoreConfiguration_Device_iPhone5(), FBControlCoreConfiguration_Device_iPad2()])),
  (["--state=creating", "--state=booting", "--state=shutdown"], FBiOSTargetQuery.simulatorStates([.creating, .booting, .shutdown])),
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
  (["approve", "com.foo.bar", "com.bing.bong"], Action.approve(["com.foo.bar", "com.bing.bong"])),
  (["approve", Fixtures.application.path], Action.approve([Fixtures.application.bundleID])),
  (["boot", "--locale", "en_US", "--scale=75"], Action.boot(FBSimulatorBootConfiguration.default().withLocalizationOverride(FBLocalizationOverride.withLocale(NSLocale(localeIdentifier: "en_US") as Locale)).scale75Percent())),
  (["boot", "--locale", "fr_FR"], Action.boot(FBSimulatorBootConfiguration.default().withLocalizationOverride(FBLocalizationOverride.withLocale(Locale(identifier: "fr_FR"))))),
  (["boot", "--scale=50"], Action.boot(FBSimulatorBootConfiguration.default().scale50Percent())),
  (["boot", "--scale=25", "--connect-bridge", "--use-nsworkspace"], Action.boot(FBSimulatorBootConfiguration.default().scale25Percent().withOptions([.connectBridge, .useNSWorkspace, .awaitServices]))),
  (["boot"], Action.boot(nil)),
  (["clear_keychain", "com.foo.bar"], Action.clearKeychain("com.foo.bar")),
  (["clear_keychain"], Action.clearKeychain(nil)),
  (["config"], Action.config),
  (["create", "--all-missing-defaults"], Action.create(CreationSpecification.allMissingDefaults)),
  (["create", "iOS 9.0"], Action.create(CreationSpecification.iOS9CreationSpecification)),
  (["create", "iPhone 6s", "iOS 9.3"], Action.create(CreationSpecification.compoundConfiguration0)),
  (["create", "iPhone 6"], Action.create(CreationSpecification.iPhone6Configuration)),
  (["delete"], Action.delete),
  (["diagnose", "--content", "--crashes-since", "200", "--system"], Action.diagnose(FBDiagnosticQuery.crashes(of: FBCrashLogInfoProcessType.system, since: Date(timeIntervalSince1970: 200)), DiagnosticFormat.Content)),
  (["diagnose", "--content", "com.foo.bar", "foo.txt", "bar.txt"], Action.diagnose(FBDiagnosticQuery.files(inApplicationOfBundleID: "com.foo.bar", withFilenames: ["foo.txt", "bar.txt"]), DiagnosticFormat.Content)),
  (["diagnose", "--crashes-since", "300", "--custom-agent"], Action.diagnose(FBDiagnosticQuery.crashes(of: FBCrashLogInfoProcessType.customAgent, since: Date(timeIntervalSince1970: 300)), DiagnosticFormat.CurrentFormat)),
  (["diagnose", "--name", "log1", "--name", "log2"], Action.diagnose(FBDiagnosticQuery.named(["log1", "log2"]), DiagnosticFormat.CurrentFormat)),
  (["diagnose", "--path", "--crashes-since", "100", "--application"], Action.diagnose(FBDiagnosticQuery.crashes(of: FBCrashLogInfoProcessType.application, since: Date(timeIntervalSince1970: 100)), DiagnosticFormat.Path)),
  (["diagnose"], Action.diagnose(FBDiagnosticQuery.all(), DiagnosticFormat.CurrentFormat)),
  (["erase"], Action.erase),
  (["install", Fixtures.application.path], Action.install(Fixtures.application.path)),
  (["launch", "--stderr", "com.foo.bar", "--foo", "-b", "-a", "-r"], Action.launchApp(FBApplicationLaunchConfiguration(bundleID: "com.foo.bar", bundleName: nil, arguments: ["--foo", "-b", "-a", "-r"], environment: [:], options: .writeStderr))),
  (["launch", "com.foo.bar"], Action.launchApp(FBApplicationLaunchConfiguration(bundleID: "com.foo.bar", bundleName: nil, arguments: [], environment: [:], options: FBProcessLaunchOptions()))),
  (["launch", "--stderr", Fixtures.application.path], Action.launchApp(FBApplicationLaunchConfiguration(bundleID: Fixtures.application.bundleID, bundleName: nil, arguments: [], environment: [:], options: .writeStderr))),
  (["launch", Fixtures.application.path], Action.launchApp(FBApplicationLaunchConfiguration(bundleID: Fixtures.application.bundleID, bundleName: nil, arguments: [], environment: [:], options: FBProcessLaunchOptions()))),
  (["launch", Fixtures.binary.path, "--foo", "-b", "-a", "-r"], Action.launchAgent(FBAgentLaunchConfiguration(binary: Fixtures.binary, arguments: ["--foo", "-b", "-a", "-r"], environment: [:], options: FBProcessLaunchOptions()))),
  (["launch", Fixtures.binary.path], Action.launchAgent(FBAgentLaunchConfiguration(binary: Fixtures.binary, arguments: [], environment: [:], options: FBProcessLaunchOptions()))),
  (["launch_xctest", Fixtures.testBundlePath, "com.foo.bar", "--foo", "-b", "-a", "-r"], Action.launchXCTest(FBTestLaunchConfiguration(testBundlePath: Fixtures.testBundlePath).withApplicationLaunchConfiguration(FBApplicationLaunchConfiguration(bundleID: "com.foo.bar", bundleName: nil, arguments: ["--foo", "-b", "-a", "-r"], environment: [:], options: FBProcessLaunchOptions())))),
  (["launch_xctest", Fixtures.testBundlePath, "com.foo.bar"], Action.launchXCTest(FBTestLaunchConfiguration(testBundlePath: Fixtures.testBundlePath).withApplicationLaunchConfiguration(FBApplicationLaunchConfiguration(bundleID: "com.foo.bar", bundleName: nil, arguments: [], environment: [:], options: FBProcessLaunchOptions())))),
  (["launch_xctest", Fixtures.testBundlePath, Fixtures.application.path], Action.launchXCTest(FBTestLaunchConfiguration(testBundlePath: Fixtures.testBundlePath).withApplicationLaunchConfiguration(FBApplicationLaunchConfiguration(bundleID: Fixtures.application.bundleID, bundleName: nil, arguments: [], environment: [:], options: FBProcessLaunchOptions())).withTestHostPath(Fixtures.application.path))),
  (["launch_xctest", "--test-timeout", "900", Fixtures.testBundlePath, Fixtures.application.path], Action.launchXCTest(FBTestLaunchConfiguration(testBundlePath: Fixtures.testBundlePath).withApplicationLaunchConfiguration(FBApplicationLaunchConfiguration(bundleID: Fixtures.application.bundleID, bundleName: nil, arguments: [], environment: [:], options: FBProcessLaunchOptions())).withTestHostPath(Fixtures.application.path).withTimeout(900))),
  (["list"], Action.list),
  (["list_apps"], Action.listApps),
  (["list_device_sets"], Action.listDeviceSets),
  (["listen", "--stdin"], Action.listen(Server.stdin)),
  (["listen", "--http", "43"], Action.listen(Server.http(43))),
  (["listen"], Action.listen(Server.empty)),
  (["open", "aoo://bar/baz"], Action.open(URL(string: "aoo://bar/baz")!)),
  (["open", "http://facebook.com"], Action.open(URL(string: "http://facebook.com")!)),
  (["record", "start"], Action.record(true)),
  (["record", "stop"], Action.record(false)),
  (["relaunch", "com.foo.bar", "--foo", "-b", "-a", "-r"], Action.relaunch(FBApplicationLaunchConfiguration(bundleID: "com.foo.bar", bundleName: nil, arguments: ["--foo", "-b", "-a", "-r"], environment: [:], options: FBProcessLaunchOptions()))),
  (["relaunch", "com.foo.bar"], Action.relaunch(FBApplicationLaunchConfiguration(bundleID: "com.foo.bar", bundleName: nil, arguments: [], environment: [:], options: FBProcessLaunchOptions()))),
  (["service_info", "com.foo.bar"], Action.serviceInfo("com.foo.bar")),
  (["shutdown"], Action.shutdown),
  (["shutdown"], Action.shutdown),
  (["terminate", "com.foo.bar"], Action.terminate("com.foo.bar")),
  (["uninstall", "com.foo.bar"], Action.uninstall("com.foo.bar")),
  (["upload", Fixtures.photoPath, Fixtures.videoPath], Action.upload([Fixtures.photoDiagnostic, Fixtures.videoDiagnostic])),
  (["watchdog_override", "60", "com.foo.bar", "com.bar.baz"], Action.watchdogOverride(["com.foo.bar", "com.bar.baz"], 60)),
  (["set_location", "39.9", "116.39"], Action.setLocation(39.9, 116.39)),
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
    let actions: [Action] = [Action.list, Action.boot(nil), Action.listen(Server.http(1000)), Action.shutdown]
    self.assertParsesImplodingCompoundActions(actions, compoundComponents: compoundComponents)
  }

  func testParsesListBootListenShutdownDiagnose() {
    let compoundComponents = [
      ["list"], ["create", "iPhone 6"], ["boot", "--direct-launch"], ["listen", "--http", "8090"], ["shutdown"], ["diagnose"],
    ]
    let launchConfiguration = FBSimulatorBootConfiguration.default()
      .withOptions([.enableDirectLaunch, .awaitServices])
      .withFramebuffer(FBFramebufferConfiguration.default())
    let diagnoseAction = Action.diagnose(FBDiagnosticQuery.all(), DiagnosticFormat.CurrentFormat)
    let actions: [Action] = [Action.list, Action.create(CreationSpecification.iPhone6Configuration), Action.boot(launchConfiguration), Action.listen(Server.http(8090)), Action.shutdown, diagnoseAction]
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
    let launchConfig1 = FBApplicationLaunchConfiguration(bundleID: "com.foo.bar", bundleName: nil, arguments: ["--foo", "--bar"], environment: [:], options: .writeStdout)
    let launchConfig2 = FBApplicationLaunchConfiguration(bundleID: Fixtures.application.bundleID, bundleName: nil, arguments: ["--bing", "--bong"], environment: [:], options: FBProcessLaunchOptions())
    let actions: [Action] = [Action.launchApp(launchConfig1), Action.launchApp(launchConfig2)]
    self.assertParsesImplodingCompoundActions(actions, compoundComponents: compoundComponents)
  }

  func assertWithDefaultAction(_ action: Action, suffix: [String]) {
    self.assertWithDefaultActions([action], suffix: suffix)
  }

  func assertWithDefaultActions(_ actions: [Action], suffix: [String]) {
    return self.unzipAndAssert(actions, suffix: suffix, extras: [
      ([], nil, nil),
      (["all"], FBiOSTargetQuery.allTargets(), nil),
      (["iPad 2"], FBiOSTargetQuery.devices([FBControlCoreConfiguration_Device_iPad2()]), nil),
      (["B8EEA6C4-841B-47E5-92DE-014E0ECD8139"], FBiOSTargetQuery.udids(["B8EEA6C4-841B-47E5-92DE-014E0ECD8139"]), nil),
      (["iPhone 5", "--state=shutdown", "iPhone 6"], FBiOSTargetQuery.devices([FBControlCoreConfiguration_Device_iPhone5(), FBControlCoreConfiguration_Device_iPhone6()]).simulatorStates([.shutdown]), nil),
      (["iPad 2", "--device-name", "--os"], FBiOSTargetQuery.devices([FBControlCoreConfiguration_Device_iPad2()]), FBiOSTargetFormat(fields: [FBiOSTargetFormatDeviceName, FBiOSTargetFormatOSVersion])),
      (["B8EEA6C4-841B-47E5-92DE-014E0ECD8139"], FBiOSTargetQuery.udids(["B8EEA6C4-841B-47E5-92DE-014E0ECD8139"]), nil),
    ])
  }

  func assertParsesImplodingCompoundActions(_ actions: [Action], compoundComponents: [[String]]) {
    self.assertWithDefaultActions(actions, suffix: CommandParserTests.implodeCompoundActions(compoundComponents))
  }

  func assertFailsToParseImplodingCompoundActions(_ compoundComponents: [[String]]) {
    self.assertParseFails(
      Command.parser,
      CommandParserTests.implodeCompoundActions(compoundComponents)
    )
  }

  func unzipAndAssert(_ actions: [Action], suffix: [String], extras: [([String], FBiOSTargetQuery?, FBiOSTargetFormat?)]) {
    let pairs = extras.map { (tokens, query, format) in
      return (tokens + suffix, Command(configuration: Configuration.defaultValue, actions: actions, query: query, format: format))
    }
    self.assertParsesAll(Command.parser, pairs)
  }

  static func implodeCompoundActions(_ compoundComponents: [[String]]) -> [String] {
    return Array(compoundComponents.joined(separator: ["--"]))
  }
}
