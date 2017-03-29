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
      (["--udid"], FBiOSTargetFormat(fields: [.UDID])),
      (["--name"], FBiOSTargetFormat(fields: [.name])),
      (["--device-name"], FBiOSTargetFormat(fields: [.deviceName])),
      (["--os"], FBiOSTargetFormat(fields: [.osVersion])),
      (["--state"], FBiOSTargetFormat(fields: [.state])),
      (["--arch"], FBiOSTargetFormat(fields: [.architecture])),
      (["--pid"], FBiOSTargetFormat(fields: [.processIdentifier])),
      (["--container_pid"], FBiOSTargetFormat(fields: [.containerApplicationProcessIdentifier]))
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
  (["iPhone 5"], FBiOSTargetQuery.device(.modeliPhone5)),
  (["iPad 2"], FBiOSTargetQuery.device(.modeliPad2)),
  (["iOS 9.0", "iOS 9.1"], FBiOSTargetQuery.osVersions([.nameiOS_9_0, .nameiOS_9_1])),
  (["--state=creating"], FBiOSTargetQuery.state(.creating)),
  (["--state=shutdown"], FBiOSTargetQuery.state(.shutdown)),
  (["--state=booted"], FBiOSTargetQuery.state(.booted)),
  (["--state=booting"], FBiOSTargetQuery.state(.booting)),
  (["--state=shutting-down"], FBiOSTargetQuery.state(.shuttingDown)),
  (["--arch=i386"], FBiOSTargetQuery.architecture(.I386)),
  (["--arch=x86_64"], FBiOSTargetQuery.architecture(.X86_64)),
  (["--arch=armv7"], FBiOSTargetQuery.architecture(.armv7)),
  (["--arch=armv7s"], FBiOSTargetQuery.architecture(.armv7s)),
  (["--arch=arm64"], FBiOSTargetQuery.architecture(.arm64)),
  (["--simulators"], FBiOSTargetQuery.targetType(FBiOSTargetType.simulator)),
  (["--devices"], FBiOSTargetQuery.targetType(FBiOSTargetType.device)),
  (["--simulators", "--devices", "iPhone 6s"], FBiOSTargetQuery.targetType(FBiOSTargetType.simulator.union(FBiOSTargetType.device)).device(.modeliPhone6S)),
  (["--first", "2", "iPhone 6"], FBiOSTargetQuery.device(.modeliPhone6).ofCount(2)),
  (["B8EEA6C4-841B-47E5-92DE-014E0ECD8139"], FBiOSTargetQuery.udids(["B8EEA6C4-841B-47E5-92DE-014E0ECD8139"])),
  (["0123456789abcdefABCDEFaaaaaaaaaaaaaaaaaa"], FBiOSTargetQuery.udids(["0123456789abcdefABCDEFaaaaaaaaaaaaaaaaaa"])),
  (["iPhone 5", "iPad 2"], FBiOSTargetQuery.devices([.modeliPhone5, .modeliPad2])),
  (["--state=creating", "--state=booting", "--state=shutdown"], FBiOSTargetQuery.simulatorStates([.creating, .booting, .shutdown])),
  (["--arch=i386", "--arch=armv7s"], FBiOSTargetQuery.architectures([.I386, .armv7s])),
  (["B8EEA6C4-841B-47E5-92DE-014E0ECD8139", "124DAC9C-4DFF-4F0C-9828-998CCFFCD4C8", "0123456789abcdefABCDEFaaaaaaaaaaaaaaaaaa"], FBiOSTargetQuery.udids(["B8EEA6C4-841B-47E5-92DE-014E0ECD8139", "124DAC9C-4DFF-4F0C-9828-998CCFFCD4C8", "0123456789abcdefABCDEFaaaaaaaaaaaaaaaaaa"])),
  (["iPhone 6", "124DAC9C-4DFF-4F0C-9828-998CCFFCD4C8"], FBiOSTargetQuery.device(.modeliPhone6).udids(["124DAC9C-4DFF-4F0C-9828-998CCFFCD4C8"])),
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
  (["focus"], Action.focus),
  (["install", Fixtures.application.path], Action.install(Fixtures.application.path, false)),
  (["install", Fixtures.application.path, "--codesign"], Action.install(Fixtures.application.path, true)),
  (["keyboard_override"], Action.keyboardOverride),
  (["launch", "--stderr", "com.foo.bar", "--foo", "-b", "-a", "-r"], Action.launchApp(FBApplicationLaunchConfiguration(bundleID: "com.foo.bar", bundleName: nil, arguments: ["--foo", "-b", "-a", "-r"], environment: [:], waitForDebugger: false, output: try! FBProcessOutputConfiguration(stdOut: NSNull(), stdErr: FBProcessOutputToFileDefaultLocation)))),
  (["launch", "com.foo.bar"], Action.launchApp(FBApplicationLaunchConfiguration(bundleID: "com.foo.bar", bundleName: nil, arguments: [], environment: [:], waitForDebugger: false, output: FBProcessOutputConfiguration.outputToDevNull()))),
  (["launch", "-w", "com.foo.bar"], Action.launchApp(FBApplicationLaunchConfiguration(bundleID: "com.foo.bar", bundleName: nil, arguments: [], environment: [:], waitForDebugger: true, output: FBProcessOutputConfiguration.outputToDevNull()))),
  (["launch", "--wait-for-debugger", "com.foo.bar"], Action.launchApp(FBApplicationLaunchConfiguration(bundleID: "com.foo.bar", bundleName: nil, arguments: [], environment: [:], waitForDebugger: true, output: FBProcessOutputConfiguration.outputToDevNull()))),
  (["launch", "--stderr", Fixtures.application.path], Action.launchApp(FBApplicationLaunchConfiguration(bundleID: Fixtures.application.bundleID, bundleName: nil, arguments: [], environment: [:], waitForDebugger: false, output: try! FBProcessOutputConfiguration(stdOut: NSNull(), stdErr: FBProcessOutputToFileDefaultLocation)))),
  (["launch", Fixtures.application.path], Action.launchApp(FBApplicationLaunchConfiguration(bundleID: Fixtures.application.bundleID, bundleName: nil, arguments: [], environment: [:], waitForDebugger: false, output: FBProcessOutputConfiguration.outputToDevNull()))),
  (["launch", Fixtures.binary.path, "--foo", "-b", "-a", "-r"], Action.launchAgent(FBAgentLaunchConfiguration(binary: Fixtures.binary, arguments: ["--foo", "-b", "-a", "-r"], environment: [:], output: FBProcessOutputConfiguration.outputToDevNull()))),
  (["launch", Fixtures.binary.path], Action.launchAgent(FBAgentLaunchConfiguration(binary: Fixtures.binary, arguments: [], environment: [:], output: FBProcessOutputConfiguration.outputToDevNull()))),
  (["launch_xctest", Fixtures.testBundlePath, "com.foo.bar", "--foo", "-b", "-a", "-r"], Action.launchXCTest(FBTestLaunchConfiguration(testBundlePath: Fixtures.testBundlePath).withApplicationLaunchConfiguration(FBApplicationLaunchConfiguration(bundleID: "com.foo.bar", bundleName: nil, arguments: ["--foo", "-b", "-a", "-r"], environment: [:], waitForDebugger: false, output: FBProcessOutputConfiguration.outputToDevNull())))),
  (["launch_xctest", Fixtures.testBundlePath, "com.foo.bar"], Action.launchXCTest(FBTestLaunchConfiguration(testBundlePath: Fixtures.testBundlePath).withApplicationLaunchConfiguration(FBApplicationLaunchConfiguration(bundleID: "com.foo.bar", bundleName: nil, arguments: [], environment: [:], waitForDebugger: false, output: FBProcessOutputConfiguration.outputToDevNull())))),
  (["launch_xctest", Fixtures.testBundlePath, Fixtures.application.path], Action.launchXCTest(FBTestLaunchConfiguration(testBundlePath: Fixtures.testBundlePath).withApplicationLaunchConfiguration(FBApplicationLaunchConfiguration(bundleID: Fixtures.application.bundleID, bundleName: nil, arguments: [], environment: [:], waitForDebugger: false, output: FBProcessOutputConfiguration.outputToDevNull())).withTestHostPath(Fixtures.application.path))),
  (["launch_xctest", "--test-timeout", "900", Fixtures.testBundlePath, Fixtures.application.path], Action.launchXCTest(FBTestLaunchConfiguration(testBundlePath: Fixtures.testBundlePath).withApplicationLaunchConfiguration(FBApplicationLaunchConfiguration(bundleID: Fixtures.application.bundleID, bundleName: nil, arguments: [], environment: [:], waitForDebugger: false, output: FBProcessOutputConfiguration.outputToDevNull())).withTestHostPath(Fixtures.application.path).withTimeout(900))),
  (["list"], Action.list),
  (["list_apps"], Action.listApps),
  (["list_device_sets"], Action.listDeviceSets),
  (["listen", "--stdin"], Action.listen(ListenInterface(stdin: true, http: nil, hid: nil, handle: nil))),
  (["listen", "--http", "43"], Action.listen(ListenInterface(stdin: false, http: 43, hid: nil, handle: nil))),
  (["listen", "--hid", "44"], Action.listen(ListenInterface(stdin: false, http: nil, hid: 44, handle: nil))),
  (["listen", "--http", "43", "--stdin"], Action.listen(ListenInterface(stdin: true, http: 43, hid: nil, handle: nil))),
  (["listen", "--http", "43", "--hid", "44"], Action.listen(ListenInterface(stdin: false, http: 43, hid: 44, handle: nil))),
  (["listen"], Action.listen(ListenInterface(stdin: false, http: nil, hid: nil, handle: nil))),
  (["open", "aoo://bar/baz"], Action.open(URL(string: "aoo://bar/baz")!)),
  (["open", "http://facebook.com"], Action.open(URL(string: "http://facebook.com")!)),
  (["record", "start"], Action.record(.start(nil))),
  (["record", "start", "/var/video.mp4"], Action.record(.start("/var/video.mp4"))),
  (["record", "stop"], Action.record(.stop)),
  (["relaunch", "com.foo.bar", "--foo", "-b", "-a", "-r"], Action.relaunch(FBApplicationLaunchConfiguration(bundleID: "com.foo.bar", bundleName: nil, arguments: ["--foo", "-b", "-a", "-r"], environment: [:], waitForDebugger: false, output: FBProcessOutputConfiguration.outputToDevNull()))),
  (["relaunch", "com.foo.bar"], Action.relaunch(FBApplicationLaunchConfiguration(bundleID: "com.foo.bar", bundleName: nil, arguments: [], environment: [:], waitForDebugger: false, output: FBProcessOutputConfiguration.outputToDevNull()))),
  (["relaunch", "--wait-for-debugger", "com.foo.bar"], Action.relaunch(FBApplicationLaunchConfiguration(bundleID: "com.foo.bar", bundleName: nil, arguments: [], environment: [:], waitForDebugger: true, output: FBProcessOutputConfiguration.outputToDevNull()))),
  (["service_info", "com.foo.bar"], Action.serviceInfo("com.foo.bar")),
  (["shutdown"], Action.shutdown),
  (["shutdown"], Action.shutdown),
  (["stream"], Action.stream(nil)),
  (["stream", "-"], Action.stream(.standardOut)),
  (["stream", "/tmp/video.dump"], Action.stream(.path("/tmp/video.dump"))),
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
    let actions: [Action] = [Action.list, Action.boot(nil), Action.listen(ListenInterface(stdin: false, http: 1000, hid: nil, handle: nil)), Action.shutdown]
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
    let actions: [Action] = [Action.list, Action.create(CreationSpecification.iPhone6Configuration), Action.boot(launchConfiguration), Action.listen(ListenInterface(stdin: false, http: 8090, hid: nil, handle: nil)), Action.shutdown, diagnoseAction]
    self.assertParsesImplodingCompoundActions(actions, compoundComponents: compoundComponents)
  }

  func testParsesRecordStartListen() {
    let compoundComponents = [
      ["record", "start"], ["listen"],
    ]
    let actions: [Action] = [Action.record(.start(nil)), Action.listen(ListenInterface())]
    self.assertParsesImplodingCompoundActions(actions, compoundComponents: compoundComponents)
  }

  func testParsesRecordToPathStartListen() {
    let compoundComponents = [
      ["record", "start", "/tmp/video.mp4"], ["listen"],
    ]
    let actions: [Action] = [Action.record(.start("/tmp/video.mp4")), Action.listen(ListenInterface())]
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
    let launchConfig1 = FBApplicationLaunchConfiguration(bundleID: "com.foo.bar", bundleName: nil, arguments: ["--foo", "--bar"], environment: [:], waitForDebugger: false, output: try! FBProcessOutputConfiguration(stdOut: FBProcessOutputToFileDefaultLocation, stdErr: NSNull()))
    let launchConfig2 = FBApplicationLaunchConfiguration(bundleID: Fixtures.application.bundleID, bundleName: nil, arguments: ["--bing", "--bong"], environment: [:], waitForDebugger: false, output: FBProcessOutputConfiguration.outputToDevNull())
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
      (["iPad 2"], FBiOSTargetQuery.device(.modeliPad2), nil),
      (["B8EEA6C4-841B-47E5-92DE-014E0ECD8139"], FBiOSTargetQuery.udids(["B8EEA6C4-841B-47E5-92DE-014E0ECD8139"]), nil),
      (["iPhone 5", "--state=shutdown", "iPhone 6"], FBiOSTargetQuery.devices([.modeliPhone5, .modeliPhone6]).state(.shutdown), nil),
      (["iPad 2", "--device-name", "--os"], FBiOSTargetQuery.device(.modeliPad2), FBiOSTargetFormat(fields: [.deviceName, .osVersion])),
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
