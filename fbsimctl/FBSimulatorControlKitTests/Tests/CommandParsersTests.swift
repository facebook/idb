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

class QueryParserTests : XCTestCase {
  func testParsesSimpleQueries() {
    self.assertParsesAll(Query.parser, [
      (["all"], .And([])),
      (["iPhone 5"], .Configured([FBSimulatorConfiguration.iPhone5()])),
      (["iPad 2"], .Configured([FBSimulatorConfiguration.iPad2()])),
      (["--state=creating"], .State([.Creating])),
      (["--state=shutdown"], .State([.Shutdown])),
      (["--state=booted"], .State([.Booted])),
      (["--state=booting"], .State([.Booting])),
      (["--state=shutting-down"], .State([.ShuttingDown])),
      (["B8EEA6C4-841B-47E5-92DE-014E0ECD8139"], .UDID(["B8EEA6C4-841B-47E5-92DE-014E0ECD8139"]))
    ])
  }

  func testFailsSimpleQueries() {
    self.assertFailsToParseAll(Query.parser, [
      ["Galaxy S5"],
      ["Nexus Chromebook Pixel G4 Droid S5 S1 S4 4S"],
      ["makingtea"],
      ["B8EEA6C4-47E5-92DE-014E0ECD8139"],
      []
    ])
  }

  func testParsesCompoundQueries() {
    self.assertParsesAll(Query.parser, [
      (["iPhone 5", "iPad 2"], .Configured([FBSimulatorConfiguration.iPhone5(), FBSimulatorConfiguration.iPad2()])),
      (["--state=creating", "--state=booting", "--state=shutdown"], .State([.Creating, .Booting, .Shutdown])),
      (["B8EEA6C4-841B-47E5-92DE-014E0ECD8139", "124DAC9C-4DFF-4F0C-9828-998CCFFCD4C8"], .UDID(["B8EEA6C4-841B-47E5-92DE-014E0ECD8139", "124DAC9C-4DFF-4F0C-9828-998CCFFCD4C8"])),
      (["B8EEA6C4-841B-47E5-92DE-014E0ECD8139", "124DAC9C-4DFF-4F0C-9828-998CCFFCD4C8", "--state=booted"], .And([.UDID(["B8EEA6C4-841B-47E5-92DE-014E0ECD8139", "124DAC9C-4DFF-4F0C-9828-998CCFFCD4C8"]), .State([.Booted])]))
    ])
  }

  func testParsesPartially() {
    self.assertParsesAll(Query.parser, [
      (["iPhone 5", "Nexus 5", "iPad 2"], Query.Configured([FBSimulatorConfiguration.iPhone5()])),
      (["--state=creating", "--state=booting", "jelly", "shutdown"], Query.State([.Creating, .Booting])),
      (["B8EEA6C4-841B-47E5-92DE-014E0ECD8139", "banana", "D7DA55E9-26FF-44FD-91A1-5B30DB68A4BB"], .UDID(["B8EEA6C4-841B-47E5-92DE-014E0ECD8139"])),
    ])
  }

  func testFailsPartialParse() {
    self.assertFailsToParseAll(Query.parser, [
      ["Nexus 5", "iPhone 5", "iPad 2"],
      ["jelly", "--state=creating", "--state=booting", "shutdown"],
      ["banana", "B8EEA6C4-841B-47E5-92DE-014E0ECD8139", "D7DA55E9-26FF-44FD-91A1-5B30DB68A4BB"],
    ])
  }
}

class KeywordParserTests : XCTestCase {
  func testParsesKeywords() {
    self.assertParsesAll(Keyword.parser, [
      (["--udid"], Keyword.UDID),
      (["--name"], Keyword.Name),
      (["--device-name"], Keyword.DeviceName),
      (["--os"], Keyword.OSVersion),
      (["--state"], Keyword.State),
      (["--pid"], Keyword.ProcessIdentifier)
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

class FBSimulatorConfigurationParserTests : XCTestCase {
  func testFailsToParseEmpty() {
    self.assertParseFails(FBSimulatorConfigurationParser.parser, [])
  }

  func testParsesOSAlone() {
    self.assertParses(
      FBSimulatorConfigurationParser.parser,
      ["iOS 9.2"],
      FBSimulatorConfiguration.defaultConfiguration().iOS_9_2()
    )
  }

  func testParsesDeviceAlone() {
    self.assertParses(
      FBSimulatorConfigurationParser.parser,
      ["iPhone 6"],
      FBSimulatorConfiguration.defaultConfiguration().iPhone6()
    )
  }

  func testParsesAuxDirectoryAlone() {
    self.assertParses(
      FBSimulatorConfigurationParser.parser,
      ["--aux", "/usr/bin"],
      FBSimulatorConfiguration.defaultConfiguration().withAuxillaryDirectory("/usr/bin")
    )
  }

  func parsesOSAndDevice(){
    self.assertParsesAll(FBSimulatorConfigurationParser.parser, [
      (["iPhone 6", "iOS 9.2"], FBSimulatorConfiguration.defaultConfiguration().iPhone6().iOS_9_2()),
      (["iPad 2", "iOS 9.0"], FBSimulatorConfiguration.defaultConfiguration().iPad2().iOS_9_0()),
    ])
  }
}

class FBSimulatorLaunchConfigurationTests : XCTestCase {
  func testParsesLocale() {
    self.assertParses(
      FBSimulatorLaunchConfigurationParser.parser,
      ["--locale", "fr_FR"],
      FBSimulatorLaunchConfiguration.defaultConfiguration().withLocaleNamed("fr_FR")
    )
  }

  func testParsesScale() {
    self.assertParses(
      FBSimulatorLaunchConfigurationParser.parser,
      ["--scale=50"],
      FBSimulatorLaunchConfiguration.defaultConfiguration().scale50Percent()
    )
  }

  func testParsesOptions() {
    self.assertParses(
      FBSimulatorLaunchConfigurationParser.parser,
      ["--direct-launch"],
      FBSimulatorLaunchConfiguration.defaultConfiguration().withOptions(FBSimulatorLaunchOptions.EnableDirectLaunch)
    )
  }

  func testParsesAllTheAbove() {
    self.assertParses(
      FBSimulatorLaunchConfigurationParser.parser,
      ["--locale", "en_GB", "--scale=75", "--direct-launch","--record-video"],
      FBSimulatorLaunchConfiguration.defaultConfiguration().withLocaleNamed("en_GB").scale75Percent().withOptions(FBSimulatorLaunchOptions.EnableDirectLaunch)
    )
  }
}

class ConfigurationParserTests : XCTestCase {
  func testParsesEmptyAsDefaultValue() {
    self.assertParses(
      Configuration.parser,
      [],
      Configuration.defaultValue
    )
  }

  func testParsesWithDebugLogging() {
    self.assertParses(
      Configuration.parser,
      ["--debug-logging"],
      Configuration(
        output: OutputOptions.DebugLogging,
        deviceSetPath: nil,
        managementOptions: FBSimulatorManagementOptions()
      )
    )
  }

  func testParsesWithSetPath() {
    self.assertParses(
      Configuration.parser,
      ["--set", "/usr/bin"],
      Configuration(
        output: OutputOptions(),
        deviceSetPath: "/usr/bin",
        managementOptions: FBSimulatorManagementOptions()
      )
    )
  }

  func testParsesWithOptions() {
    self.assertParses(
      Configuration.parser,
      ["--kill-all", "--kill-spurious"],
      Configuration(
        output: OutputOptions(),
        deviceSetPath: nil,
        managementOptions: FBSimulatorManagementOptions.KillAllOnFirstStart.union(.KillSpuriousSimulatorsOnFirstStart)
      )
    )
  }

  func testParsesWithSetPathAndOptions() {
    self.assertParses(
      Configuration.parser,
      ["--set", "/usr/bin", "--delete-all", "--kill-spurious"],
      Configuration(
        output: OutputOptions(),
        deviceSetPath: "/usr/bin",
        managementOptions: FBSimulatorManagementOptions.DeleteAllOnFirstStart.union(.KillSpuriousSimulatorsOnFirstStart)
      )
    )
  }

  func testParsesWithAllTheAbove() {
    self.assertParses(
      Configuration.parser,
      ["--debug-logging", "--set", "/usr/bin", "--delete-all", "--kill-spurious"],
      Configuration(
        output: OutputOptions.DebugLogging,
        deviceSetPath: "/usr/bin",
        managementOptions: FBSimulatorManagementOptions.DeleteAllOnFirstStart.union(.KillSpuriousSimulatorsOnFirstStart)
      )
    )
  }
}

let validActions: [([String], Action)] = [
  (["approve", "com.foo.bar", "com.bing.bong"], Action.Approve(["com.foo.bar", "com.bing.bong"])),
  (["approve", Fixtures.application.path], Action.Approve([Fixtures.application.bundleID])),
  (["boot", "--locale", "en_US", "--scale=75"], Action.Boot(FBSimulatorLaunchConfiguration.defaultConfiguration().withLocale(NSLocale(localeIdentifier: "en_US")).scale75Percent())),
  (["boot", "--locale", "fr_FR"], Action.Boot(FBSimulatorLaunchConfiguration.defaultConfiguration().withLocale(NSLocale(localeIdentifier: "fr_FR")))),
  (["boot", "--scale=50"], Action.Boot(FBSimulatorLaunchConfiguration.defaultConfiguration().scale50Percent())),
  (["boot"], Action.Boot(nil)),
  (["create", "iOS 9.2"], Action.Create(FBSimulatorConfiguration.defaultConfiguration().iOS_9_2())),
  (["create", "iPhone 6", "iOS 9.2"], Action.Create(FBSimulatorConfiguration.defaultConfiguration().iPhone6().iOS_9_2())),
  (["create", "iPhone 6"], Action.Create(FBSimulatorConfiguration.defaultConfiguration().iPhone6())),
  (["delete"], Action.Delete),
  (["diagnose", "--content", "--crashes-since", "200", "--system"], Action.Diagnose(FBSimulatorDiagnosticQuery.crashesOfType(FBCrashLogInfoProcessType.System, since: NSDate(timeIntervalSince1970: 200)), DiagnosticFormat.Content)),
  (["diagnose", "--content", "com.foo.bar", "foo.txt", "bar.txt"], Action.Diagnose(FBSimulatorDiagnosticQuery.filesInApplicationOfBundleID("com.foo.bar", withFilenames: ["foo.txt", "bar.txt"]), DiagnosticFormat.Content)),
  (["diagnose", "--crashes-since", "300", "--custom-agent"], Action.Diagnose(FBSimulatorDiagnosticQuery.crashesOfType(FBCrashLogInfoProcessType.CustomAgent, since: NSDate(timeIntervalSince1970: 300)), DiagnosticFormat.CurrentFormat)),
  (["diagnose", "--name", "log1", "--name", "log2"], Action.Diagnose(FBSimulatorDiagnosticQuery.named(["log1", "log2"]), DiagnosticFormat.CurrentFormat)),
  (["diagnose", "--path", "--crashes-since", "100", "--application"], Action.Diagnose(FBSimulatorDiagnosticQuery.crashesOfType(FBCrashLogInfoProcessType.Application, since: NSDate(timeIntervalSince1970: 100)), DiagnosticFormat.Path)),
  (["diagnose"], Action.Diagnose(FBSimulatorDiagnosticQuery.all(), DiagnosticFormat.CurrentFormat)),
  (["install", Fixtures.application.path], Action.Install(Fixtures.application)),
  (["launch", Fixtures.application.path], Action.Launch(FBApplicationLaunchConfiguration(bundleID: Fixtures.application.bundleID, bundleName: nil, arguments: [], environment: [:]))),
  (["launch", Fixtures.application.path], Action.Launch(FBApplicationLaunchConfiguration(bundleID: Fixtures.application.bundleID, bundleName: nil, arguments: [], environment: [:]))),
  (["launch", Fixtures.binary.path, "--foo", "-b", "-a", "-r"], Action.Launch(FBAgentLaunchConfiguration(binary: Fixtures.binary, arguments: ["--foo", "-b", "-a", "-r"], environment: [:]))),
  (["launch", Fixtures.binary.path], Action.Launch(FBAgentLaunchConfiguration(binary: Fixtures.binary, arguments: [], environment: [:]))),
  (["list"], Action.List),
  (["listen", "--http", "43"], Action.Listen(Server.Http(43))),
  (["listen", "--socket", "42"], Action.Listen(Server.Socket(42))),
  (["listen"], Action.Listen(Server.StdIO)),
  (["open", "aoo://bar/baz"], Action.Open(NSURL(string: "aoo://bar/baz")!)),
  (["open", "http://facebook.com"], Action.Open(NSURL(string: "http://facebook.com")!)),
  (["record", "start"], Action.Record(true)),
  (["record", "stop"], Action.Record(false)),
  (["shutdown"], Action.Shutdown),
  (["shutdown"], Action.Shutdown),
  (["terminate", "com.foo.bar"], Action.Terminate("com.foo.bar")),
]

let invalidActions: [[String]] = [
  ["aboota"],
  ["approve", "dontadddotstome"],
  ["approve"],
  ["create"],
  ["ddshutdown"],
  ["install", "/dev/null"],
  ["install"],
  ["listaa"],
]

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

  func testParsesLaunchAppByPathWithArguments() {
    let action = Action.Launch(FBApplicationLaunchConfiguration(bundleID: Fixtures.application.bundleID, bundleName: nil, arguments: ["--foo", "-b", "-a", "-r"], environment: [:]))
    let suffix: [String] = ["launch", Fixtures.application.path, "--foo", "-b", "-a", "-r"]
    self.assertWithDefaultAction(action, suffix: suffix)
  }

  func testParsesLaunchAppByBundleID() {
    let action = Action.Launch(FBApplicationLaunchConfiguration(bundleID: "com.foo.bar", bundleName: nil, arguments: [], environment: [:]))
    let suffix: [String] = ["launch", "com.foo.bar"]
    self.assertWithDefaultAction(action, suffix: suffix)
  }

  func testParsesLaunchAppByBundleIDWithArguments() {
    let action = Action.Launch(FBApplicationLaunchConfiguration(bundleID: "com.foo.bar", bundleName: nil, arguments: ["--foo", "-b", "-a", "-r"], environment: [:]))
    let suffix: [String] = ["launch", "com.foo.bar", "--foo", "-b", "-a", "-r"]
    self.assertWithDefaultAction(action, suffix: suffix)
  }

  func testParsesRelaunchAppByBundleID() {
    let action = Action.Relaunch(FBApplicationLaunchConfiguration(bundleID: "com.foo.bar", bundleName: nil, arguments: [], environment: [:]))
    let suffix: [String] = ["relaunch", "com.foo.bar"]
    self.assertWithDefaultAction(action, suffix: suffix)
  }

  func testParsesRelaunchAppByBundleIDArguments() {
    let action = Action.Relaunch(FBApplicationLaunchConfiguration(bundleID: "com.foo.bar", bundleName: nil, arguments: ["--foo", "-b", "-a", "-r"], environment: [:]))
    let suffix: [String] = ["relaunch", "com.foo.bar", "--foo", "-b", "-a", "-r"]
    self.assertWithDefaultAction(action, suffix: suffix)
  }

  func testParsesListBootListenShutdown() {
    let actions: [Action] = [Action.List, Action.Boot(nil), Action.Listen(Server.Http(1000)), Action.Shutdown]
    let suffix: [String] = ["list", "boot", "listen", "--http", "1000", "shutdown"]
    self.assertWithDefaultActions(actions, suffix: suffix)
  }

  func testParsesListBootListenShutdownDiagnose() {
    let launchConfiguration = FBSimulatorLaunchConfiguration.withOptions(FBSimulatorLaunchOptions.EnableDirectLaunch)
    let simulatorConfiguration = FBSimulatorConfiguration.iPhone5()
    let diagnoseAction = Action.Diagnose(FBSimulatorDiagnosticQuery.all(), DiagnosticFormat.CurrentFormat)
    let actions: [Action] = [Action.List, Action.Create(simulatorConfiguration), Action.Boot(launchConfiguration), Action.Listen(Server.Http(8090)), Action.Shutdown, diagnoseAction]
    let suffix: [String] = ["list", "create", "iPhone 5", "boot", "--direct-launch", "listen", "--http", "8090", "shutdown", "diagnose"]
    self.assertWithDefaultActions(actions, suffix: suffix)
  }

  func testParsesUpload() {
    self.assertWithDefaultAction(Action.Upload([Fixtures.photoDiagnostic, Fixtures.videoDiagnostic]), suffix: ["upload", Fixtures.photoPath, Fixtures.videoPath])
  }

  func assertWithDefaultAction(action: Action, suffix: [String]) {
    assertWithDefaultActions([action], suffix: suffix)
  }

  func assertWithDefaultActions(actions: [Action], suffix: [String]) {
    return self.unzipAndAssert(actions, suffix: suffix, extras: [
      ([], nil, nil),
      (["all"], Query.And([]), nil),
      (["iPad 2"], Query.Configured([FBSimulatorConfiguration.iPad2()]), nil),
      (["B8EEA6C4-841B-47E5-92DE-014E0ECD8139"], Query.UDID(["B8EEA6C4-841B-47E5-92DE-014E0ECD8139"]), nil),
      (["iPhone 5", "--state=shutdown", "iPhone 6"], Query.And([.Configured([FBSimulatorConfiguration.iPhone5(), FBSimulatorConfiguration.iPhone6()]), .State([.Shutdown])]), nil),
      (["iPad 2", "--device-name", "--os"], Query.Configured([FBSimulatorConfiguration.iPad2()]), [.DeviceName, .OSVersion]),
      (["B8EEA6C4-841B-47E5-92DE-014E0ECD8139"], Query.UDID(["B8EEA6C4-841B-47E5-92DE-014E0ECD8139"]), nil),
    ])
  }

  func unzipAndAssert(actions: [Action], suffix: [String], extras: [([String], Query?, Format?)]) {
    let pairs = extras.map { (tokens, query, format) in
      return (tokens + suffix, Command.Perform(Configuration.defaultValue, actions, query, format))
    }
    self.assertParsesAll(Command.parser, pairs)
  }
}
