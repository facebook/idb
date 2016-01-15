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

class FormatParserTests : XCTestCase {
  func testParsesSimpleFormats() {
    self.assertParsesAll(Format.parser(), [
      (["--udid"], .UDID),
      (["--name"], .Name),
      (["--device-name"], .DeviceName),
      (["--os"], .OSVersion),
      (["--state"], .State),
      (["--pid"], .ProcessIdentifier),
    ])
  }

  func testParsesCompoundFormats() {
    self.assertParsesAll(Format.parser(), [
      (["--name", "--device-name", "--pid"], .Compound([.Name, .DeviceName, .ProcessIdentifier])),
      (["--udid", "--name", "--state", "--device-name", "--os"], .Compound([.UDID, .Name, .State, .DeviceName, .OSVersion]))
    ])
  }

  func testFailsToParse() {
    self.assertFailsToParseAll(Format.parser(), [
      ["--foo"],
      ["--bar"],
      ["--something-else"]
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
      (["--process-killing"], FBSimulatorManagementOptions.UseProcessKilling),
      (["--timeout-resiliance"], FBSimulatorManagementOptions.UseSimDeviceTimeoutResiliance)
    ])
  }

  func testParsesCompound() {
    self.assertParsesAll(FBSimulatorManagementOptions.parser(), [
      (["--delete-all", "--kill-all"], FBSimulatorManagementOptions.DeleteAllOnFirstStart.union(.KillAllOnFirstStart)),
      (["--kill-spurious-services", "--process-killing"], FBSimulatorManagementOptions.KillSpuriousCoreSimulatorServices.union(.UseProcessKilling)),
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

class ConfigurationParserTests : XCTestCase {
  func testParsesEmpty() {
    self.assertParses(
      Configuration.parser(), [], Configuration.defaultValue()
    )
  }

  func testParsesWithDebugLogging() {
    self.assertParses(
      Configuration.parser(),
      ["--debug-logging"],
      Configuration(
        controlConfiguration: Configuration.defaultControlConfiguration(),
        options: Configuration.Options.DebugLogging
      )
    )
  }

  func testParsesWithJSONOutput() {
    self.assertParses(
      Configuration.parser(),
      ["--json"],
      Configuration(
        controlConfiguration: Configuration.defaultControlConfiguration(),
        options: Configuration.Options.JSONOutput
      )
    )
  }

  func testParsesWithSetPath() {
    self.assertParses(
      Configuration.parser(),
      ["--set", "/usr/bin"],
      Configuration(
        controlConfiguration: FBSimulatorControlConfiguration(
          deviceSetPath: "/usr/bin",
          options: FBSimulatorManagementOptions.defaultValue()
        ),
        options: Configuration.Options()
      )
    )
  }

  func testParsesWithOptions() {
    self.assertParses(
      Configuration.parser(),
      ["--kill-all", "--process-killing"],
      Configuration(
        controlConfiguration: FBSimulatorControlConfiguration(
          deviceSetPath: nil,
          options: FBSimulatorManagementOptions.KillAllOnFirstStart.union(.UseProcessKilling)
        ),
        options: Configuration.Options()
      )
    )
  }

  func testParsesWithSetPathAndOptions() {
    self.assertParses(
      Configuration.parser(),
      ["--set", "/usr/bin", "--delete-all", "--kill-spurious"],
      Configuration(
        controlConfiguration: FBSimulatorControlConfiguration(
          deviceSetPath: "/usr/bin",
          options: FBSimulatorManagementOptions.DeleteAllOnFirstStart.union(.KillSpuriousSimulatorsOnFirstStart)
        ),
        options: Configuration.Options()
      )
    )
  }

  func testParsesWithAllTheAbove() {
    self.assertParses(
      Configuration.parser(),
      ["--debug-logging", "--json", "--set", "/usr/bin", "--delete-all", "--kill-spurious"],
      Configuration(
        controlConfiguration: FBSimulatorControlConfiguration(
          deviceSetPath: "/usr/bin",
          options: FBSimulatorManagementOptions.DeleteAllOnFirstStart.union(.KillSpuriousSimulatorsOnFirstStart)
        ),
        options: Configuration.Options.DebugLogging.union(Configuration.Options.JSONOutput)
      )
    )
  }
}

class InteractionParserTests : XCTestCase {
  func testParsesAllCases() {
    self.assertParsesAll(Interaction.parser(), [
      (["list"], Interaction.List),
      (["boot"], Interaction.Boot),
      (["shutdown"], Interaction.Shutdown),
      (["diagnose"], Interaction.Diagnose),
      (["install", Fixtures.application().path], Interaction.Install(Fixtures.application())),
      (["launch", Fixtures.application().path], Interaction.Launch(FBApplicationLaunchConfiguration(application: Fixtures.application(), arguments: [], environment: [:]))),
      (["launch", Fixtures.binary().path], Interaction.Launch(FBAgentLaunchConfiguration(binary: Fixtures.binary(), arguments: [], environment: [:])))
    ])
  }

  func testDoesNotParseInvalidTokens() {
    self.assertFailsToParseAll(Interaction.parser(), [
      ["listaa"],
      ["aboota"],
      ["ddshutdown"],
      ["install"],
      ["install", "/dev/null"],
    ])
  }
}

class ActionParserTests : XCTestCase {
  func testParsesList() {
    self.assertWithDefaultActions(Interaction.List, suffix: ["list"])
  }

  func testParsesBoot() {
    self.assertWithDefaultActions(Interaction.Boot, suffix: ["boot"])
  }

  func testParsesInstall() {
    let interaction = Interaction.Install(Fixtures.application())
    let suffix: [String] = ["install", Fixtures.application().path]
    self.assertWithDefaultActions(interaction, suffix: suffix)
  }

  func testParsesAppLaunch() {
    let interaction = Interaction.Launch(FBApplicationLaunchConfiguration(application: Fixtures.application(), arguments: [], environment: [:]))
    let suffix: [String] = ["launch", Fixtures.application().path]
    self.assertWithDefaultActions(interaction, suffix: suffix)
  }

  func testParsesAppLaunchWithArguments() {
    let interaction = Interaction.Launch(FBApplicationLaunchConfiguration(application: Fixtures.application(), arguments: ["--foo", "-b", "-a", "-r"], environment: [:]))
    let suffix: [String] = ["launch", Fixtures.application().path, "--foo", "-b", "-a", "-r"]
    self.assertWithDefaultActions(interaction, suffix: suffix)
  }

  func testParsesAgentLaunch() {
    let interaction = Interaction.Launch(FBAgentLaunchConfiguration(binary: Fixtures.binary(), arguments: [], environment: [:]))
    let suffix: [String] = ["launch", Fixtures.binary().path]
    self.assertWithDefaultActions(interaction, suffix: suffix)
  }

  func testParsesAgentLaunchWithArguments() {
    let interaction = Interaction.Launch(FBAgentLaunchConfiguration(binary: Fixtures.binary(), arguments: ["--foo", "-b", "-a", "-r"], environment: [:]))
    let suffix: [String] = ["launch", Fixtures.binary().path, "--foo", "-b", "-a", "-r"]
    self.assertWithDefaultActions(interaction, suffix: suffix)
  }

  func testParsesShutdown() {
    self.assertWithDefaultActions(Interaction.Shutdown, suffix: ["shutdown"])
  }

  func testParsesDiagnose() {
    self.assertWithDefaultActions(Interaction.Diagnose, suffix: ["diagnose"])
  }

  func assertWithDefaultActions(interaction: Interaction, suffix: [String]) {
    return self.unzipAndAssert(interaction, suffix: suffix, extras: [
      ([], Query.defaultValue(), Format.defaultValue()),
      (["iPad 2"], Query.Configured([FBSimulatorConfiguration.iPad2()]), Format.defaultValue()),
      (["B8EEA6C4-841B-47E5-92DE-014E0ECD8139"], Query.UDID(["B8EEA6C4-841B-47E5-92DE-014E0ECD8139"]), Format.defaultValue()),
      (["iPhone 5", "--state=shutdown", "iPhone 6"], Query.And([.Configured([FBSimulatorConfiguration.iPhone5(), FBSimulatorConfiguration.iPhone6()]), .State([.Shutdown])]), Format.defaultValue()),
      (["iPad 2", "--device-name", "--os"], Query.Configured([FBSimulatorConfiguration.iPad2()]), Format.Compound([.DeviceName, .OSVersion]))
    ])
  }

  func unzipAndAssert(interaction: Interaction, suffix: [String], extras: [([String], Query, Format)]) {
    let pairs = extras.map { (tokens, query, format) in
      return (tokens + suffix, Action(interaction: interaction, query: query, format: format))
    }
    self.assertParsesAll(Action.parser(), pairs)
  }
}

class CommandParserTests : XCTestCase {
  func testParsesSingleAction() {
    self.assertParsesAll(Command.parser(), [
      (["B8EEA6C4-841B-47E5-92DE-014E0ECD8139", "boot"], Command.Perform(Configuration.defaultValue(), [Action(interaction: .Boot, query: .UDID(["B8EEA6C4-841B-47E5-92DE-014E0ECD8139"]), format: Format.defaultValue())])),
    ])
  }

  func testParsesMultipleActions() {
    self.assertParsesAll(Command.parser(), [
      (["--state=booted", "list", "B8EEA6C4-841B-47E5-92DE-014E0ECD8139", "boot"], Command.Perform(Configuration.defaultValue(), [
        Action(interaction: .List, query: Query.State([.Booted]), format: Format.defaultValue()),
        Action(interaction: .Boot, query: .UDID(["B8EEA6C4-841B-47E5-92DE-014E0ECD8139"]), format: Format.defaultValue())
      ])),
    ])
  }

  func testParsesInteract() {
    self.assertParsesAll(Command.parser(), [
      (["interact"], Command.Interact(Configuration.defaultValue(), nil)),
      (["interact", "--port", "42"], Command.Interact(Configuration.defaultValue(), 42))
    ])
  }

  func testParsesHelp() {
    self.assertParsesAll(Command.parser(), [
      (["help"], Command.Help(nil))
    ])
  }
}
