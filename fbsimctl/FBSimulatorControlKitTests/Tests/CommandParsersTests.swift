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
    self.assertParsesAll(Query.parser(), [
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
    self.assertFailsToParseAll(Query.parser(), [
      ["Galaxy S5"],
      ["Nexus Chromebook Pixel G4 Droid S5 S1 S4 4S"],
      ["makingtea"],
      ["B8EEA6C4-47E5-92DE-014E0ECD8139"],
      []
    ])
  }

  func testParsesCompoundQueries() {
    self.assertParsesAll(Query.parser(), [
      (["iPhone 5", "iPad 2"], .Configured([FBSimulatorConfiguration.iPhone5(), FBSimulatorConfiguration.iPad2()])),
      (["--state=creating", "--state=booting", "--state=shutdown"], .State([.Creating, .Booting, .Shutdown])),
      (["B8EEA6C4-841B-47E5-92DE-014E0ECD8139", "124DAC9C-4DFF-4F0C-9828-998CCFFCD4C8"], .UDID(["B8EEA6C4-841B-47E5-92DE-014E0ECD8139", "124DAC9C-4DFF-4F0C-9828-998CCFFCD4C8"])),
      (["B8EEA6C4-841B-47E5-92DE-014E0ECD8139", "124DAC9C-4DFF-4F0C-9828-998CCFFCD4C8", "--state=booted"], .And([.UDID(["B8EEA6C4-841B-47E5-92DE-014E0ECD8139", "124DAC9C-4DFF-4F0C-9828-998CCFFCD4C8"]), .State([.Booted])]))
    ])
  }

  func testParsesPartially() {
    self.assertParsesAll(Query.parser(), [
      (["iPhone 5", "Nexus 5", "iPad 2"], Query.Configured([FBSimulatorConfiguration.iPhone5()])),
      (["--state=creating", "--state=booting", "jelly", "shutdown"], Query.State([.Creating, .Booting])),
      (["B8EEA6C4-841B-47E5-92DE-014E0ECD8139", "banana", "D7DA55E9-26FF-44FD-91A1-5B30DB68A4BB"], .UDID(["B8EEA6C4-841B-47E5-92DE-014E0ECD8139"])),
    ])
  }

  func testFailsPartialParse() {
    self.assertFailsToParseAll(Query.parser(), [
      ["Nexus 5", "iPhone 5", "iPad 2"],
      ["jelly", "--state=creating", "--state=booting", "shutdown"],
      ["banana", "B8EEA6C4-841B-47E5-92DE-014E0ECD8139", "D7DA55E9-26FF-44FD-91A1-5B30DB68A4BB"],
    ])
  }
}

class KeywordParserTests : XCTestCase {
  func testParsesKeywords() {
    self.assertParsesAll(Keyword.parser(), [
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
    self.assertParsesAll(FBSimulatorManagementOptions.parser(), [
      (["--delete-all"], FBSimulatorManagementOptions.DeleteAllOnFirstStart),
      (["--kill-all"], FBSimulatorManagementOptions.KillAllOnFirstStart),
      (["--kill-spurious"], FBSimulatorManagementOptions.KillSpuriousSimulatorsOnFirstStart),
      (["--ignore-spurious-kill-fail"], FBSimulatorManagementOptions.IgnoreSpuriousKillFail),
      (["--kill-spurious-services"], FBSimulatorManagementOptions.KillSpuriousCoreSimulatorServices),
      (["--timeout-resiliance"], FBSimulatorManagementOptions.UseSimDeviceTimeoutResiliance)
    ])
  }

  func testParsesCompound() {
    self.assertParsesAll(FBSimulatorManagementOptions.parser(), [
      (["--delete-all", "--kill-all"], FBSimulatorManagementOptions.DeleteAllOnFirstStart.union(.KillAllOnFirstStart)),
      (["--kill-spurious-services"], FBSimulatorManagementOptions.KillSpuriousCoreSimulatorServices),
      (["--ignore-spurious-kill-fail", "--timeout-resiliance"], FBSimulatorManagementOptions.IgnoreSpuriousKillFail.union(.UseSimDeviceTimeoutResiliance)),
      (["--kill-spurious", "--ignore-spurious-kill-fail"], FBSimulatorManagementOptions.KillSpuriousSimulatorsOnFirstStart.union(.IgnoreSpuriousKillFail))
    ])
  }
}

class FBSimulatorAllocationOptionsParserTests : XCTestCase {
  func testParsesSimple() {
    self.assertParsesAll(FBSimulatorAllocationOptions.parser(), [
      (["--create"], FBSimulatorAllocationOptions.Create),
      (["--reuse"], FBSimulatorAllocationOptions.Reuse),
      (["--shutdown-on-allocate"], FBSimulatorAllocationOptions.ShutdownOnAllocate),
      (["--erase-on-allocate"], FBSimulatorAllocationOptions.EraseOnAllocate),
      (["--delete-on-free"], FBSimulatorAllocationOptions.DeleteOnFree),
      (["--erase-on-free"], FBSimulatorAllocationOptions.EraseOnFree)
    ])
  }

  func testParsesCompound() {
    self.assertParsesAll(FBSimulatorAllocationOptions.parser(), [
      (["--create", "--reuse", "--erase-on-free"], FBSimulatorAllocationOptions.Create.union(.Reuse).union(.EraseOnFree)),
      (["--shutdown-on-allocate", "--create", "--erase-on-free"], FBSimulatorAllocationOptions.Create.union(.ShutdownOnAllocate).union(.EraseOnFree)),
    ])
  }
}

class FBSimulatorConfigurationParserTests : XCTestCase {
  func testFailsToParseEmpty() {
    self.assertParseFails(FBSimulatorConfigurationParser.parser(), [])
  }

  func testParsesOSAlone() {
    self.assertParses(
      FBSimulatorConfigurationParser.parser(),
      ["iOS 9.2"],
      FBSimulatorConfiguration.defaultConfiguration().iOS_9_2()
    )
  }

  func testParsesDeviceAlone() {
    self.assertParses(
      FBSimulatorConfigurationParser.parser(),
      ["iPhone 6"],
      FBSimulatorConfiguration.defaultConfiguration().iPhone6()
    )
  }

  func testParsesAuxDirectoryAlone() {
    self.assertParses(
      FBSimulatorConfigurationParser.parser(),
      ["--aux", "/usr/bin"],
      FBSimulatorConfiguration.defaultConfiguration().withAuxillaryDirectory("/usr/bin")
    )
  }

  func parsesOSAndDevice(){
    self.assertParsesAll(FBSimulatorConfigurationParser.parser(), [
      (["iPhone 6", "iOS 9.2"], FBSimulatorConfiguration.defaultConfiguration().iPhone6().iOS_9_2()),
      (["iPad 2", "iOS 9.0"], FBSimulatorConfiguration.defaultConfiguration().iPad2().iOS_9_0()),
    ])
  }
}

class FBSimulatorLaunchConfigurationTests : XCTestCase {
  func testParsesLocale() {
    self.assertParses(
      FBSimulatorLaunchConfigurationParser.parser(),
      ["--locale", "fr_FR"],
      FBSimulatorLaunchConfiguration.defaultConfiguration().withLocaleNamed("fr_FR")
    )
  }

  func testParsesScale() {
    self.assertParses(
      FBSimulatorLaunchConfigurationParser.parser(),
      ["--scale=50"],
      FBSimulatorLaunchConfiguration.defaultConfiguration().scale50Percent()
    )
  }

  func testParsesOptions() {
    self.assertParses(
      FBSimulatorLaunchConfigurationParser.parser(),
      ["--record-video", "--direct-launch"],
      FBSimulatorLaunchConfiguration.defaultConfiguration().withOptions(FBSimulatorLaunchOptions.RecordVideo.union(FBSimulatorLaunchOptions.EnableDirectLaunch))
    )
  }

  func testParsesAllTheAbove() {
    self.assertParses(
      FBSimulatorLaunchConfigurationParser.parser(),
      ["--locale", "en_GB", "--scale=75", "--direct-launch","--record-video"],
      FBSimulatorLaunchConfiguration.defaultConfiguration().withLocaleNamed("en_GB").scale75Percent().withOptions(FBSimulatorLaunchOptions.RecordVideo.union(FBSimulatorLaunchOptions.EnableDirectLaunch))
    )
  }
}

class ConfigurationParserTests : XCTestCase {
  func testParsesEmptyAsDefaultValue() {
    self.assertParses(
      Configuration.parser(),
      [],
      Configuration.defaultValue
    )
  }

  func testParsesWithDebugLogging() {
    self.assertParses(
      Configuration.parser(),
      ["--debug-logging"],
      Configuration(
        options: Configuration.Options.DebugLogging,
        deviceSetPath: nil,
        managementOptions: FBSimulatorManagementOptions()
      )
    )
  }

  func testParsesWithSetPath() {
    self.assertParses(
      Configuration.parser(),
      ["--set", "/usr/bin"],
      Configuration(
        options: Configuration.Options(),
        deviceSetPath: "/usr/bin",
        managementOptions: FBSimulatorManagementOptions()
      )
    )
  }

  func testParsesWithOptions() {
    self.assertParses(
      Configuration.parser(),
      ["--kill-all", "--kill-spurious"],
      Configuration(
        options: Configuration.Options(),
        deviceSetPath: nil,
        managementOptions: FBSimulatorManagementOptions.KillAllOnFirstStart.union(.KillSpuriousSimulatorsOnFirstStart)
      )
    )
  }

  func testParsesWithSetPathAndOptions() {
    self.assertParses(
      Configuration.parser(),
      ["--set", "/usr/bin", "--delete-all", "--kill-spurious"],
      Configuration(
        options: Configuration.Options(),
        deviceSetPath: "/usr/bin",
        managementOptions: FBSimulatorManagementOptions.DeleteAllOnFirstStart.union(.KillSpuriousSimulatorsOnFirstStart)
      )
    )
  }

  func testParsesWithAllTheAbove() {
    self.assertParses(
      Configuration.parser(),
      ["--debug-logging", "--set", "/usr/bin", "--delete-all", "--kill-spurious"],
      Configuration(
        options: Configuration.Options.DebugLogging,
        deviceSetPath: "/usr/bin",
        managementOptions: FBSimulatorManagementOptions.DeleteAllOnFirstStart.union(.KillSpuriousSimulatorsOnFirstStart)
      )
    )
  }
}

class ActionParserTests : XCTestCase {
  func testParsesAllCases() {
    self.assertParsesAll(Action.parser(), [
      (["list"], Action.List),
      (["approve", "com.foo.bar", "com.bing.bong"], Action.Approve(["com.foo.bar", "com.bing.bong"])),
      (["approve", Fixtures.application().path], Action.Approve([Fixtures.application().bundleID])),
      (["boot"], Action.Boot(nil)),
      (["boot", "--locale", "fr_FR"], Action.Boot(FBSimulatorLaunchConfiguration.defaultConfiguration().withLocale(NSLocale(localeIdentifier: "fr_FR")))),
      (["boot", "--scale=50"], Action.Boot(FBSimulatorLaunchConfiguration.defaultConfiguration().scale50Percent())),
      (["boot", "--locale", "en_US", "--scale=75"], Action.Boot(FBSimulatorLaunchConfiguration.defaultConfiguration().withLocale(NSLocale(localeIdentifier: "en_US")).scale75Percent())),
      (["shutdown"], Action.Shutdown),
      (["diagnose"], Action.Diagnose),
      (["delete"], Action.Delete),
      (["install", Fixtures.application().path], Action.Install(Fixtures.application())),
      (["launch", Fixtures.application().path], Action.Launch(FBApplicationLaunchConfiguration(bundleID: Fixtures.application().bundleID, bundleName: nil, arguments: [], environment: [:]))),
      (["launch", Fixtures.binary().path], Action.Launch(FBAgentLaunchConfiguration(binary: Fixtures.binary(), arguments: [], environment: [:])))
    ])
  }

  func testDoesNotParseInvalidTokens() {
    self.assertFailsToParseAll(Action.parser(), [
      ["listaa"],
      ["approve"],
      ["approve", "dontadddotstome"],
      ["aboota"],
      ["ddshutdown"],
      ["install"],
      ["install", "/dev/null"],
    ])
  }
}

class CommandParserTests : XCTestCase {
  func testParsesHelp() {
    self.assertParsesAll(Command.parser(), [
      (["help"], Command.Help(true, nil))
    ])
  }

  func testParsesApprove() {
    self.assertWithDefaultAction(Action.Approve(["com.foo.bar", "com.bing.bong"]), suffix: ["approve", "com.foo.bar", "com.bing.bong"])
  }

  func testParsesBoot() {
    self.assertWithDefaultAction(Action.Boot(nil), suffix: ["boot"])
  }

  func testFailsToParseCreate() {
    self.assertParseFails(Action.parser(), ["create"])
  }

  func testParsesDelete() {
    self.assertWithDefaultAction(Action.Delete, suffix: ["delete"])
  }

  func testParsesDiagnose() {
    self.assertWithDefaultAction(Action.Diagnose, suffix: ["diagnose"])
  }

  func testParsesInstall() {
    let action = Action.Install(Fixtures.application())
    let suffix: [String] = ["install", Fixtures.application().path]
    self.assertWithDefaultAction(action, suffix: suffix)
  }

  func testParsesList() {
    self.assertWithDefaultAction(Action.List, suffix: ["list"])
  }

  func testParsesListenSTDIO() {
    self.assertWithDefaultAction(Action.Listen(Server.StdIO), suffix: ["listen"])
  }

  func testParsesListenWithSocket() {
    self.assertWithDefaultAction(Action.Listen(Server.Socket(42)), suffix: ["listen", "--socket", "42"])
  }

  func testParsesListenWithHttp() {
    self.assertWithDefaultAction(Action.Listen(Server.Http(43)), suffix: ["listen", "--http", "43"])
  }

  func testParsesLaunchAgent() {
    let action = Action.Launch(FBAgentLaunchConfiguration(binary: Fixtures.binary(), arguments: [], environment: [:]))
    let suffix: [String] = ["launch", Fixtures.binary().path]
    self.assertWithDefaultAction(action, suffix: suffix)
  }

  func testParsesLaunchAgentWithArguments() {
    let action = Action.Launch(FBAgentLaunchConfiguration(binary: Fixtures.binary(), arguments: ["--foo", "-b", "-a", "-r"], environment: [:]))
    let suffix: [String] = ["launch", Fixtures.binary().path, "--foo", "-b", "-a", "-r"]
    self.assertWithDefaultAction(action, suffix: suffix)
  }

  func testParseLaunchAppByPath() {
    let action = Action.Launch(FBApplicationLaunchConfiguration(bundleID: Fixtures.application().bundleID, bundleName: nil, arguments: [], environment: [:]))
    let suffix: [String] = ["launch", Fixtures.application().path]
    self.assertWithDefaultAction(action, suffix: suffix)
  }

  func testParsesLaunchAppByPathWithArguments() {
    let action = Action.Launch(FBApplicationLaunchConfiguration(bundleID: Fixtures.application().bundleID, bundleName: nil, arguments: ["--foo", "-b", "-a", "-r"], environment: [:]))
    let suffix: [String] = ["launch", Fixtures.application().path, "--foo", "-b", "-a", "-r"]
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

  func testParsesShutdown() {
    self.assertWithDefaultAction(Action.Shutdown, suffix: ["shutdown"])
  }

  func testParsesTerminateByBundleID() {
    self.assertWithDefaultAction(Action.Terminate("com.foo.bar"), suffix: ["terminate", "com.foo.bar"])
  }

  func testParsesListBootListenShutdown() {
    let actions: [Action] = [Action.List, Action.Boot(nil), Action.Listen(Server.Http(1000)), Action.Shutdown]
    let suffix: [String] = ["list", "boot", "listen", "--http", "1000", "shutdown"]
    self.assertWithDefaultActions(actions, suffix: suffix)
  }

  func testParsesListBootListenShutdownDiagnose() {
    let launchConfiguration = FBSimulatorLaunchConfiguration.withOptions(FBSimulatorLaunchOptions.EnableDirectLaunch.union(FBSimulatorLaunchOptions.RecordVideo))
    let simulatorConfiguration = FBSimulatorConfiguration.iPhone5()
    let actions: [Action] = [Action.List, Action.Create(simulatorConfiguration), Action.Boot(launchConfiguration), Action.Listen(Server.Http(8090)), Action.Shutdown, Action.Diagnose]
    let suffix: [String] = ["list", "create", "iPhone 5", "boot", "--direct-launch", "--record-video", "listen", "--http", "8090", "shutdown", "diagnose"]
    self.assertWithDefaultActions(actions, suffix: suffix)
  }

  func testParsesCreate() {
    self.assertParsesAll(Action.parser(), [
      (["create", "iPhone 6"], Action.Create(FBSimulatorConfiguration.defaultConfiguration().iPhone6())),
      (["create", "iOS 9.2"], Action.Create(FBSimulatorConfiguration.defaultConfiguration().iOS_9_2())),
      (["create", "iPhone 6", "iOS 9.2"], Action.Create(FBSimulatorConfiguration.defaultConfiguration().iPhone6().iOS_9_2())),
    ])
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
    self.assertParsesAll(Command.parser(), pairs)
  }
}
