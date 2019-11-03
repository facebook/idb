/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBSimulatorControl
@testable import FBSimulatorControlKit
import XCTest

class FBiOSTargetFormatParserTests: XCTestCase {
  func testParsesKeywords() {
    assertParsesAll(FBiOSTargetFormatParsers.parser, [
      (["--format", "%u"], FBiOSTargetFormat(fields: [.UDID])),
      (["--format=%u"], FBiOSTargetFormat(fields: [.UDID])),
      (["--format", "%n"], FBiOSTargetFormat(fields: [.name])),
      (["--format=%n"], FBiOSTargetFormat(fields: [.name])),
      (["--format", "%m"], FBiOSTargetFormat(fields: [.model])),
      (["--format=%m"], FBiOSTargetFormat(fields: [.model])),
      (["--format", "%o"], FBiOSTargetFormat(fields: [.osVersion])),
      (["--format=%o"], FBiOSTargetFormat(fields: [.osVersion])),
      (["--format", "%s"], FBiOSTargetFormat(fields: [.state])),
      (["--format=%s"], FBiOSTargetFormat(fields: [.state])),
      (["--format", "%a"], FBiOSTargetFormat(fields: [.architecture])),
      (["--format=%a"], FBiOSTargetFormat(fields: [.architecture])),
      (["--format", "%p"], FBiOSTargetFormat(fields: [.processIdentifier])),
      (["--format=%p"], FBiOSTargetFormat(fields: [.processIdentifier])),
    ])
  }
}

class FBSimulatorManagementOptionsParserTests: XCTestCase {
  func testParsesSimple() {
    assertParsesAll(FBSimulatorManagementOptions.parser, [
      (["--delete-all"], FBSimulatorManagementOptions.deleteAllOnFirstStart),
      (["--kill-all"], FBSimulatorManagementOptions.killAllOnFirstStart),
      (["--kill-spurious"], FBSimulatorManagementOptions.killSpuriousSimulatorsOnFirstStart),
      (["--ignore-spurious-kill-fail"], FBSimulatorManagementOptions.ignoreSpuriousKillFail),
      (["--kill-spurious-services"], FBSimulatorManagementOptions.killSpuriousCoreSimulatorServices),
    ])
  }

  func testParsesCompound() {
    assertParsesAll(FBSimulatorManagementOptions.parser, [
      (["--delete-all", "--kill-all"], FBSimulatorManagementOptions.deleteAllOnFirstStart.union(.killAllOnFirstStart)),
      (["--ignore-spurious-kill-fail", "--kill-spurious-services"], FBSimulatorManagementOptions.ignoreSpuriousKillFail.union(.killSpuriousCoreSimulatorServices)),
      (["--kill-spurious", "--ignore-spurious-kill-fail"], FBSimulatorManagementOptions.killSpuriousSimulatorsOnFirstStart.union(.ignoreSpuriousKillFail)),
    ])
  }
}

class CreationSpecificationParserTests: XCTestCase {
  func testParses() {
    assertParsesAll(CreationSpecification.parser, [
      ([], CreationSpecification.empty),
      (["iOS 9.0"], CreationSpecification.iOS9CreationSpecification),
      (["iPhone 6"], CreationSpecification.iPhone6Configuration),
      (["--aux", "/usr/bin"], CreationSpecification.auxDirectoryConfiguration),
      (["iPhone 6s", "iOS 9.3"], CreationSpecification.compoundConfiguration0),
      (["iPad Air 2", "iOS 10.0"], CreationSpecification.compoundConfiguration1),
    ])
  }
}

class FBSimulatorBootConfigurationTests: XCTestCase {
  func testParsesLocale() {
    assertParses(
      FBSimulatorBootConfigurationParser.parser,
      ["--locale", "fr_FR"],
      FBSimulatorBootConfiguration.default.withLocalizationOverride(FBLocalizationOverride.withLocale(Locale(identifier: "fr_FR")))
    )
  }

  func testParsesScale() {
    assertParses(
      FBSimulatorBootConfigurationParser.parser,
      ["--scale=50"],
      FBSimulatorBootConfiguration.default.withScale(.scale50)
    )
  }

  func testParsesConnectBridge() {
    assertParses(
      FBSimulatorBootConfigurationParser.parser,
      ["--connect-bridge"],
      FBSimulatorBootConfiguration
        .default
        .withOptions([.connectBridge, .verifyUsable, .useNSWorkspace])
    )
  }

  func testUseNSWorkspace() {
    assertParses(
      FBSimulatorBootConfigurationParser.parser,
      ["--use-nsworkspace"],
      FBSimulatorBootConfiguration
        .default
        .withOptions([.useNSWorkspace, .verifyUsable])
    )
  }

  func testParsesDirectLaunchToMakeFramebuffer() {
    assertParses(
      FBSimulatorBootConfigurationParser.parser,
      ["--direct-launch"],
      FBSimulatorBootConfiguration.default
        .withOptions([.enableDirectLaunch, .verifyUsable, .useNSWorkspace])
    )
  }

  func testParsesAllTheAbove() {
    assertParses(
      FBSimulatorBootConfigurationParser.parser,
      ["--locale", "en_GB", "--scale=75", "--direct-launch", "--connect-bridge"],
      FBSimulatorBootConfiguration.default
        .withLocalizationOverride(FBLocalizationOverride.withLocale(Locale(identifier: "en_GB")))
        .withScale(.scale75)
        .withOptions([.enableDirectLaunch, .connectBridge, .verifyUsable, .useNSWorkspace])
    )
  }
}

let validConfigurations: [([String], Configuration)] = [
  ([], Configuration.defaultValue),
  (["--debug-logging"], Configuration(outputOptions: OutputOptions.DebugLogging, managementOptions: FBSimulatorManagementOptions(), deviceSetPath: nil)),
  (["--kill-all", "--kill-spurious"], Configuration(outputOptions: OutputOptions(), managementOptions: FBSimulatorManagementOptions.killAllOnFirstStart.union(.killSpuriousSimulatorsOnFirstStart), deviceSetPath: nil)),
  (["--set", "/usr/bin"], Configuration(outputOptions: OutputOptions(), managementOptions: FBSimulatorManagementOptions(), deviceSetPath: "/usr/bin")),
  (["--set=/usr/bin"], Configuration(outputOptions: OutputOptions(), managementOptions: FBSimulatorManagementOptions(), deviceSetPath: "/usr/bin")),
  (["--debug-logging", "--set", "/usr/bin", "--delete-all", "--kill-spurious"], Configuration(outputOptions: OutputOptions.DebugLogging, managementOptions: FBSimulatorManagementOptions.deleteAllOnFirstStart.union(.killSpuriousSimulatorsOnFirstStart), deviceSetPath: "/usr/bin")),
  (["--delete-all", "--set", "/usr/bin", "--debug-logging", "--kill-spurious"], Configuration(outputOptions: OutputOptions.DebugLogging, managementOptions: FBSimulatorManagementOptions.deleteAllOnFirstStart.union(.killSpuriousSimulatorsOnFirstStart), deviceSetPath: "/usr/bin")),
  (["--set", "/usr/bin", "--delete-all", "--kill-spurious"], Configuration(outputOptions: OutputOptions(), managementOptions: FBSimulatorManagementOptions.deleteAllOnFirstStart.union(.killSpuriousSimulatorsOnFirstStart), deviceSetPath: "/usr/bin")),
]

let validQueries: [([String], FBiOSTargetQuery)] = [
  (["all"], .allTargets()),
  (["iPhone 5"], .device(.modeliPhone5)),
  (["iPad 2"], .device(.modeliPad2)),
  (["iOS 9.0", "iOS 9.1"], .osVersions([.nameiOS_9_0, .nameiOS_9_1])),
  (["--name=foo"], .named("foo")),
  (["--name", "boo"], .named("boo")),
  (["--name='Foo Bar'"], .named("Foo Bar")),
  (["--state=creating"], .state(.creating)),
  (["--state", "creating"], .state(.creating)),
  (["--state=shutdown"], .state(.shutdown)),
  (["--state", "shutdown"], .state(.shutdown)),
  (["--state=booted"], .state(.booted)),
  (["--state", "booted"], .state(.booted)),
  (["--state=booting"], .state(.booting)),
  (["--state", "booting"], .state(.booting)),
  (["--state=shutting-down"], .state(.shuttingDown)),
  (["--state", "shutting-down"], .state(.shuttingDown)),
  (["--arch=i386"], .architecture(.I386)),
  (["--arch=x86_64"], .architecture(.X86_64)),
  (["--arch=armv7"], .architecture(.armv7)),
  (["--arch=armv7s"], .architecture(.armv7s)),
  (["--arch=arm64"], .architecture(.arm64)),
  (["--simulators"], .targetType(.simulator)),
  (["--devices"], .targetType(.device)),
  (["--simulators", "--devices", "iPhone 6s"], FBiOSTargetQuery.targetType(FBiOSTargetType.simulator.union(FBiOSTargetType.device)).device(.modeliPhone6S)),
  (["--first", "2", "iPhone 6"], FBiOSTargetQuery.device(.modeliPhone6).ofCount(2)),
  (["B8EEA6C4-841B-47E5-92DE-014E0ECD8139"], .udids(["B8EEA6C4-841B-47E5-92DE-014E0ECD8139"])),
  (["0123456789abcdefABCDEFaaaaaaaaaaaaaaaaaa"], .udids(["0123456789abcdefABCDEFaaaaaaaaaaaaaaaaaa"])),
  (["iPhone 5", "iPad 2"], .devices([.modeliPhone5, .modeliPad2])),
  (["--state=creating", "--state=booting", "--state=shutdown"], .simulatorStates([.creating, .booting, .shutdown])),
  (["--arch=i386", "--arch=armv7s"], .architectures([.I386, .armv7s])),
  (["B8EEA6C4-841B-47E5-92DE-014E0ECD8139", "124DAC9C-4DFF-4F0C-9828-998CCFFCD4C8", "0123456789abcdefABCDEFaaaaaaaaaaaaaaaaaa"], .udids(["B8EEA6C4-841B-47E5-92DE-014E0ECD8139", "124DAC9C-4DFF-4F0C-9828-998CCFFCD4C8", "0123456789abcdefABCDEFaaaaaaaaaaaaaaaaaa"])),
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
  (["accessibility_fetch"], .accessibility),
  (["approve", "com.foo.bar", "com.bing.bong"], .approve(["com.foo.bar", "com.bing.bong"])),
  (["approve", Fixtures.application.path], .approve([Fixtures.application.identifier])),
  (["boot", "--locale", "en_US", "--scale=75"], .boot(FBSimulatorBootConfiguration.default.withLocalizationOverride(FBLocalizationOverride.withLocale(NSLocale(localeIdentifier: "en_US") as Locale)).withScale(.scale75))),
  (["boot", "--locale", "fr_FR"], .boot(FBSimulatorBootConfiguration.default.withLocalizationOverride(FBLocalizationOverride.withLocale(Locale(identifier: "fr_FR"))))),
  (["boot", "--scale=50"], .boot(FBSimulatorBootConfiguration.default.withScale(.scale50))),
  (["boot", "--scale=25", "--connect-bridge", "--use-nsworkspace"], .boot(FBSimulatorBootConfiguration.default.withScale(.scale25).withOptions([.connectBridge, .useNSWorkspace, .verifyUsable]))),
  (["boot"], .boot(FBSimulatorBootConfiguration.default)),
  (["clear_keychain", "com.foo.bar"], .clearKeychain("com.foo.bar")),
  (["clear_keychain"], .clearKeychain(nil)),
  (["contacts_update", "/tmp"], .contactsUpdate("/tmp")),
  (["config"], .config),
  (["clone"], .clone),
  (["create", "--all-missing-defaults"], .create(CreationSpecification.allMissingDefaults)),
  (["create", "iOS 9.0"], .create(CreationSpecification.iOS9CreationSpecification)),
  (["create", "iPhone 6s", "iOS 9.3"], .create(CreationSpecification.compoundConfiguration0)),
  (["create", "iPhone 6"], .create(CreationSpecification.iPhone6Configuration)),
  (["delete"], .delete),
  (["diagnose", "--content", "--crashes-since", "200", "--system"], .diagnose(FBDiagnosticQuery.crashes(of: FBCrashLogInfoProcessType.system, since: Date(timeIntervalSince1970: 200)).withFormat(.content))),
  (["diagnose", "--content", "com.foo.bar", "foo.txt", "bar.txt"], .diagnose(FBDiagnosticQuery.files(inApplicationOfBundleID: "com.foo.bar", withFilenames: ["foo.txt", "bar.txt"], withFilenameGlobs: []).withFormat(.content))),
  (["diagnose", "--crashes-since", "300", "--custom-agent"], .diagnose(FBDiagnosticQuery.crashes(of: FBCrashLogInfoProcessType.customAgent, since: Date(timeIntervalSince1970: 300)).withFormat(.current))),
  (["diagnose", "--name", "log1", "--name", "log2"], .diagnose(FBDiagnosticQuery.named(["log1", "log2"]).withFormat(.current))),
  (["diagnose", "--path", "--crashes-since", "100", "--application"], .diagnose(FBDiagnosticQuery.crashes(of: FBCrashLogInfoProcessType.application, since: Date(timeIntervalSince1970: 100)).withFormat(.path))),
  (["diagnose"], .diagnose(FBDiagnosticQuery.all().withFormat(.current))),
  (["erase"], .erase),
  (["focus"], .focus),
  (["install", Fixtures.application.path], .install(Fixtures.application.path, false)),
  (["install", Fixtures.application.path, "--codesign"], .install(Fixtures.application.path, true)),
  (["keyboard_override"], .keyboardOverride),
  (["launch", "--stderr", "com.foo.bar", "--foo", "-b", "-a", "-r"], .launchApp(FBApplicationLaunchConfiguration(bundleID: "com.foo.bar", bundleName: nil, arguments: ["--foo", "-b", "-a", "-r"], environment: [:], waitForDebugger: false, output: try! FBProcessOutputConfiguration(stdOut: NSNull(), stdErr: FBProcessOutputToFileDefaultLocation)))),
  (["launch", "com.foo.bar"], .launchApp(FBApplicationLaunchConfiguration(bundleID: "com.foo.bar", bundleName: nil, arguments: [], environment: [:], waitForDebugger: false, output: FBProcessOutputConfiguration.outputToDevNull()))),
  (["launch", "-w", "com.foo.bar"], .launchApp(FBApplicationLaunchConfiguration(bundleID: "com.foo.bar", bundleName: nil, arguments: [], environment: [:], waitForDebugger: true, output: FBProcessOutputConfiguration.outputToDevNull()))),
  (["launch", "--wait-for-debugger", "com.foo.bar"], .launchApp(FBApplicationLaunchConfiguration(bundleID: "com.foo.bar", bundleName: nil, arguments: [], environment: [:], waitForDebugger: true, output: FBProcessOutputConfiguration.outputToDevNull()))),
  (["launch", "--stderr", Fixtures.application.path], .launchApp(FBApplicationLaunchConfiguration(bundleID: Fixtures.application.identifier, bundleName: nil, arguments: [], environment: [:], waitForDebugger: false, output: try! FBProcessOutputConfiguration(stdOut: NSNull(), stdErr: FBProcessOutputToFileDefaultLocation)))),
  (["launch", Fixtures.application.path], .launchApp(FBApplicationLaunchConfiguration(bundleID: Fixtures.application.identifier, bundleName: nil, arguments: [], environment: [:], waitForDebugger: false, output: FBProcessOutputConfiguration.outputToDevNull()))),
  (["launch", Fixtures.binary.path, "--foo", "-b", "-a", "-r"], .launchAgent(FBAgentLaunchConfiguration(binary: Fixtures.binary, arguments: ["--foo", "-b", "-a", "-r"], environment: [:], output: FBProcessOutputConfiguration.outputToDevNull()))),
  (["launch", Fixtures.binary.path], .launchAgent(FBAgentLaunchConfiguration(binary: Fixtures.binary, arguments: [], environment: [:], output: FBProcessOutputConfiguration.outputToDevNull()))),
  (["launch_xctest", Fixtures.testBundlePath, "com.foo.bar", "--foo", "-b", "-a", "-r"], .launchXCTest(FBTestLaunchConfiguration(testBundlePath: Fixtures.testBundlePath).withApplicationLaunchConfiguration(FBApplicationLaunchConfiguration(bundleID: "com.foo.bar", bundleName: nil, arguments: ["--foo", "-b", "-a", "-r"], environment: [:], waitForDebugger: false, output: FBProcessOutputConfiguration.outputToDevNull())))),
  (["launch_xctest", Fixtures.testBundlePath, "com.foo.bar"], .launchXCTest(FBTestLaunchConfiguration(testBundlePath: Fixtures.testBundlePath).withApplicationLaunchConfiguration(FBApplicationLaunchConfiguration(bundleID: "com.foo.bar", bundleName: nil, arguments: [], environment: [:], waitForDebugger: false, output: FBProcessOutputConfiguration.outputToDevNull())))),
  (["launch_xctest", Fixtures.testBundlePath, Fixtures.application.path], .launchXCTest(FBTestLaunchConfiguration(testBundlePath: Fixtures.testBundlePath).withApplicationLaunchConfiguration(FBApplicationLaunchConfiguration(bundleID: Fixtures.application.identifier, bundleName: nil, arguments: [], environment: [:], waitForDebugger: false, output: FBProcessOutputConfiguration.outputToDevNull())).withTestHostPath(Fixtures.application.path))),
  (["launch_xctest", "--test-timeout", "900", Fixtures.testBundlePath, Fixtures.application.path], .launchXCTest(FBTestLaunchConfiguration(testBundlePath: Fixtures.testBundlePath).withApplicationLaunchConfiguration(FBApplicationLaunchConfiguration(bundleID: Fixtures.application.identifier, bundleName: nil, arguments: [], environment: [:], waitForDebugger: false, output: FBProcessOutputConfiguration.outputToDevNull())).withTestHostPath(Fixtures.application.path).withTimeout(900))),
  (["list"], .list),
  (["list_apps"], .listApps),
  (["list_device_sets"], .listDeviceSets),
  (["listen", "--stdin"], .listen(ListenInterface(stdin: true, http: nil, hid: nil, continuation: nil))),
  (["listen", "--http", "43"], .listen(ListenInterface(stdin: false, http: 43, hid: nil, continuation: nil))),
  (["listen", "--socket", "44"], .listen(ListenInterface(stdin: false, http: nil, hid: 44, continuation: nil))),
  (["listen", "--http", "43", "--stdin"], .listen(ListenInterface(stdin: true, http: 43, hid: nil, continuation: nil))),
  (["listen", "--http", "43", "--socket", "44"], .listen(ListenInterface(stdin: false, http: 43, hid: 44, continuation: nil))),
  (["listen"], .listen(ListenInterface(stdin: false, http: nil, hid: nil, continuation: nil))),
  (["logtail"], .logTail(FBLogTailConfiguration(arguments: []))),
  (["logtail", "some", "--other", "args"], .logTail(FBLogTailConfiguration(arguments: ["some", "--other", "args"]))),
  (["open", "aoo://bar/baz"], .open(URL(string: "aoo://bar/baz")!)),
  (["open", "http://facebook.com"], .open(URL(string: "http://facebook.com")!)),
  (["record", "start"], .record(.start(nil))),
  (["record", "start", "/var/video.mp4"], .record(.start("/var/video.mp4"))),
  (["record", "stop"], .record(.stop)),
  (["relaunch", "com.foo.bar", "--foo", "-b", "-a", "-r"], .relaunch(FBApplicationLaunchConfiguration(bundleID: "com.foo.bar", bundleName: nil, arguments: ["--foo", "-b", "-a", "-r"], environment: [:], waitForDebugger: false, output: FBProcessOutputConfiguration.outputToDevNull()))),
  (["relaunch", "com.foo.bar"], .relaunch(FBApplicationLaunchConfiguration(bundleID: "com.foo.bar", bundleName: nil, arguments: [], environment: [:], waitForDebugger: false, output: FBProcessOutputConfiguration.outputToDevNull()))),
  (["relaunch", "--wait-for-debugger", "com.foo.bar"], .relaunch(FBApplicationLaunchConfiguration(bundleID: "com.foo.bar", bundleName: nil, arguments: [], environment: [:], waitForDebugger: true, output: FBProcessOutputConfiguration.outputToDevNull()))),
  (["service_info", "com.foo.bar"], .serviceInfo("com.foo.bar")),
  (["shutdown"], .shutdown),
  (["shutdown"], .shutdown),
  (["stream", "-"], Action.stream(FBBitmapStreamConfiguration(encoding: .BGRA, framesPerSecond: nil), .standardOut)),
  (["stream", "/tmp/video.dump"], Action.stream(FBBitmapStreamConfiguration(encoding: .BGRA, framesPerSecond: nil), .path("/tmp/video.dump"))),
  (["stream", "--bgra", "-"], Action.stream(FBBitmapStreamConfiguration(encoding: .BGRA, framesPerSecond: nil), .standardOut)),
  (["stream", "--h264", "-"], Action.stream(FBBitmapStreamConfiguration(encoding: .H264, framesPerSecond: nil), .standardOut)),
  (["stream", "--fps=30", "-"], Action.stream(FBBitmapStreamConfiguration(encoding: .BGRA, framesPerSecond: 30), .standardOut)),
  (["stream", "--bgra", "--fps=25", "-"], Action.stream(FBBitmapStreamConfiguration(encoding: .BGRA, framesPerSecond: 25), .standardOut)),
  (["stream", "--fps", "60", "/tmp/video.dump"], Action.stream(FBBitmapStreamConfiguration(encoding: .BGRA, framesPerSecond: 60), .path("/tmp/video.dump"))),
  (["terminate", "com.foo.bar"], .terminate("com.foo.bar")),
  (["uninstall", "com.foo.bar"], .uninstall("com.foo.bar")),
  (["upload", Fixtures.photoPath, Fixtures.videoPath], .upload([Fixtures.photoDiagnostic, Fixtures.videoDiagnostic])),
  (["watchdog_override", "60", "com.foo.bar", "com.bar.baz"], .watchdogOverride(["com.foo.bar", "com.bar.baz"], 60)),
  (["set_location", "39.9", "116.39"], .setLocation(39.9, 116.39)),
]

let invalidActions: [[String]] = [
  ["aboota"],
  ["approve", "dontadddotstome"],
  ["approve"],
  ["ddshutdown"],
  ["install"],
  ["listaa"],
]

class ConfigurationParserTests: XCTestCase {
  func testParsesValidConfigurations() {
    assertParsesAll(Configuration.parser, validConfigurations)
  }
}

class QueryParserTests: XCTestCase {
  func testParsesValidQueries() {
    assertParsesAll(FBiOSTargetQueryParsers.parser, validQueries)
  }

  func testParsesInvalidQueries() {
    assertFailsToParseAll(FBiOSTargetQueryParsers.parser, invalidQueries)
  }
}

class ActionParserTests: XCTestCase {
  func testParsesValidActions() {
    assertParsesAll(Action.parser, validActions)
  }

  func testFailsToParseInvalidActions() {
    assertFailsToParseAll(Action.parser, invalidActions)
  }

  func testParsesInsidePrint() {
    let pairs = validActions.map { tokens, action in
      (["print"] + tokens, CLI.print(action))
    }
    assertParsesAll(CLI.parser, pairs)
  }
}

class CommandParserTests: XCTestCase {
  func testParsesValidActions() {
    for (suffix, action) in validActions {
      assertWithDefaultAction(action, suffix: suffix)
    }
  }

  func testParsesListBootListenShutdown() {
    let compoundComponents = [
      ["list"], ["boot"], ["listen", "--http", "1000"], ["shutdown"],
    ]
    let actions: [Action] = [.list, .boot(FBSimulatorBootConfiguration.default), .listen(ListenInterface(stdin: false, http: 1000, hid: nil, continuation: nil)), .shutdown]
    assertParsesImplodingCompoundActions(actions, compoundComponents: compoundComponents)
  }

  func testParsesListBootListenShutdownDiagnose() {
    let compoundComponents = [
      ["list"], ["create", "iPhone 6"], ["boot", "--direct-launch"], ["listen", "--http", "8090"], ["shutdown"], ["diagnose"],
    ]
    let launchConfiguration = FBSimulatorBootConfiguration.default
      .withOptions([.enableDirectLaunch, .verifyUsable, .useNSWorkspace])
    let diagnoseAction = Action.diagnose(FBDiagnosticQuery.all())
    let actions: [Action] = [.list, .create(CreationSpecification.iPhone6Configuration), .boot(launchConfiguration), .listen(ListenInterface(stdin: false, http: 8090, hid: nil, continuation: nil)), .shutdown, diagnoseAction]
    assertParsesImplodingCompoundActions(actions, compoundComponents: compoundComponents)
  }

  func testParsesRecordStartListen() {
    let compoundComponents = [
      ["record", "start"], ["listen"],
    ]
    let actions: [Action] = [.record(.start(nil)), .listen(ListenInterface())]
    assertParsesImplodingCompoundActions(actions, compoundComponents: compoundComponents)
  }

  func testParsesRecordToPathStartListen() {
    let compoundComponents = [
      ["record", "start", "/tmp/video.mp4"], ["listen"],
    ]
    let actions: [Action] = [.record(.start("/tmp/video.mp4")), .listen(ListenInterface())]
    assertParsesImplodingCompoundActions(actions, compoundComponents: compoundComponents)
  }

  func testFailsToParseDanglingTokens() {
    let compoundComponents = [
      ["list"], ["create", "iPhone 5"], ["boot", "--direct-launch"], ["listen", "--http", "8090"], ["YOLO"],
    ]
    assertFailsToParseImplodingCompoundActions(compoundComponents)
  }

  func testParsesMultipleConsecutiveLaunches() {
    let compoundComponents = [
      ["launch", "--stdout", "com.foo.bar", "--foo", "--bar"], ["launch", Fixtures.application.path, "--bing", "--bong"],
    ]
    let launchConfig1 = FBApplicationLaunchConfiguration(bundleID: "com.foo.bar", bundleName: nil, arguments: ["--foo", "--bar"], environment: [:], waitForDebugger: false, output: try! FBProcessOutputConfiguration(stdOut: FBProcessOutputToFileDefaultLocation, stdErr: NSNull()))
    let launchConfig2 = FBApplicationLaunchConfiguration(bundleID: Fixtures.application.identifier, bundleName: nil, arguments: ["--bing", "--bong"], environment: [:], waitForDebugger: false, output: FBProcessOutputConfiguration.outputToDevNull())
    let actions: [Action] = [.launchApp(launchConfig1), .launchApp(launchConfig2)]
    assertParsesImplodingCompoundActions(actions, compoundComponents: compoundComponents)
  }

  func assertWithDefaultAction(_ action: Action, suffix: [String]) {
    assertWithDefaultActions([action], suffix: suffix)
  }

  func assertWithDefaultActions(_ actions: [Action], suffix: [String]) {
    return unzipAndAssert(actions, suffix: suffix, extras: [
      ([], nil, nil),
      (["all"], .allTargets(), nil),
      (["iPad 2"], .device(.modeliPad2), nil),
      (["B8EEA6C4-841B-47E5-92DE-014E0ECD8139"], .udids(["B8EEA6C4-841B-47E5-92DE-014E0ECD8139"]), nil),
      (["iPhone 5", "--state=shutdown", "iPhone 6"], FBiOSTargetQuery.devices([.modeliPhone5, .modeliPhone6]).state(.shutdown), nil),
      (["iPad 2", "--format=%m%o"], .device(.modeliPad2), FBiOSTargetFormat(fields: [.model, .osVersion])),
      (["B8EEA6C4-841B-47E5-92DE-014E0ECD8139"], .udids(["B8EEA6C4-841B-47E5-92DE-014E0ECD8139"]), nil),
    ])
  }

  func assertParsesImplodingCompoundActions(_ actions: [Action], compoundComponents: [[String]]) {
    assertWithDefaultActions(actions, suffix: CommandParserTests.implodeCompoundActions(compoundComponents))
  }

  func assertFailsToParseImplodingCompoundActions(_ compoundComponents: [[String]]) {
    assertParseFails(
      Command.parser,
      CommandParserTests.implodeCompoundActions(compoundComponents)
    )
  }

  func unzipAndAssert(_ actions: [Action], suffix: [String], extras: [([String], FBiOSTargetQuery?, FBiOSTargetFormat?)]) {
    let pairs = extras.map { tokens, query, format in
      (tokens + suffix, Command(configuration: Configuration.defaultValue, actions: actions, query: query, format: format))
    }
    assertParsesAll(Command.parser, pairs)
  }

  static func implodeCompoundActions(_ compoundComponents: [[String]]) -> [String] {
    return Array(compoundComponents.joined(separator: ["--"]))
  }
}
