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
      (["creating"], .State([.Creating])),
      (["shutdown"], .State([.Shutdown])),
      (["booted"], .State([.Booted])),
      (["booting"], .State([.Booting])),
      (["shutting-down"], .State([.ShuttingDown])),
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
      (["creating", "booting", "shutdown"], .State([.Creating, .Booting, .Shutdown])),
      (["B8EEA6C4-841B-47E5-92DE-014E0ECD8139", "124DAC9C-4DFF-4F0C-9828-998CCFFCD4C8"], .UDID(["B8EEA6C4-841B-47E5-92DE-014E0ECD8139", "124DAC9C-4DFF-4F0C-9828-998CCFFCD4C8"])),
      (["B8EEA6C4-841B-47E5-92DE-014E0ECD8139", "124DAC9C-4DFF-4F0C-9828-998CCFFCD4C8", "booted"], .And([.UDID(["B8EEA6C4-841B-47E5-92DE-014E0ECD8139", "124DAC9C-4DFF-4F0C-9828-998CCFFCD4C8"]), .State([.Booted])]))
    ])
  }

  func testParsesPartially() {
    self.assertParsesAll(Query.parser(), [
      (["iPhone 5", "Nexus 5", "iPad 2"], Query.Configured([FBSimulatorConfiguration.iPhone5()])),
      (["creating", "booting", "jelly", "shutdown"], Query.State([.Creating, .Booting])),
      (["B8EEA6C4-841B-47E5-92DE-014E0ECD8139", "banana", "D7DA55E9-26FF-44FD-91A1-5B30DB68A4BB"], .UDID(["B8EEA6C4-841B-47E5-92DE-014E0ECD8139"])),
    ])
  }

  func testFailsPartialParse() {
    self.assertFailsToParseAll(Query.parser(), [
      ["Nexus 5", "iPhone 5", "iPad 2"],
      ["jelly", "creating", "booting", "shutdown"],
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
      (["--os"], .OSVersion)
    ])
  }

  func testParsesCompoundFormats() {
    self.assertParsesAll(Format.parser(), [
      (["--name", "--device-name"], .Compound([.Name, .DeviceName])),
      (["--udid", "--name", "--device-name", "--os"], .Compound([.UDID, .Name, .DeviceName, .OSVersion]))
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
        debugLogging: true
      )
    )
  }

  func testParsesWithSetPath() {
    self.assertParses(
      Configuration.parser(),
      ["--device-set", "/usr/bin"],
      Configuration(
        controlConfiguration: FBSimulatorControlConfiguration(
          deviceSetPath: "/usr/bin",
          options: FBSimulatorManagementOptions.defaultValue()
        ),
        debugLogging: false
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
        debugLogging: false
      )
    )
  }

  func testParsesWithSetPathAndOptions() {
    self.assertParses(
      Configuration.parser(),
      ["--device-set", "/usr/bin", "--delete-all", "--kill-spurious"],
      Configuration(
        controlConfiguration: FBSimulatorControlConfiguration(
          deviceSetPath: "/usr/bin",
          options: FBSimulatorManagementOptions.DeleteAllOnFirstStart.union(.KillSpuriousSimulatorsOnFirstStart)
        ),
        debugLogging: false
      )
    )
  }

  func testParsesWithAllTheAbove() {
    self.assertParses(
      Configuration.parser(),
      ["--debug-logging", "--device-set", "/usr/bin", "--delete-all", "--kill-spurious"],
      Configuration(
        controlConfiguration: FBSimulatorControlConfiguration(
          deviceSetPath: "/usr/bin",
          options: FBSimulatorManagementOptions.DeleteAllOnFirstStart.union(.KillSpuriousSimulatorsOnFirstStart)
        ),
        debugLogging: true
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
    self.assertParsesAll(Action.parser(), [
      (["list"], Action(interaction: .List, query: Query.defaultValue(), format: Format.defaultValue())),
      (["list", "booted"], Action(interaction: .List, query: Query.State([.Booted]), format: Format.defaultValue())),
      (["list", "--name"], Action(interaction: .List, query: Query.defaultValue(), format: Format.Name)),
      (["list", "B8EEA6C4-841B-47E5-92DE-014E0ECD8139", "--os"], Action(interaction: .List, query: Query.UDID(["B8EEA6C4-841B-47E5-92DE-014E0ECD8139"]), format: Format.OSVersion)),
      (["list", "booted", "iPhone 5", "--device-name", "--os"], Action(interaction: .List, query: Query.And([.State([.Booted]), .Configured([FBSimulatorConfiguration.iPhone5()])]), format: Format.Compound([.DeviceName, .OSVersion])))
    ])
  }

  func testParsesBoot() {
    self.assertParsesAll(Action.parser(), [
      (["boot"], Action(interaction: .Boot, query: Query.defaultValue(), format: Format.defaultValue())),
      (["boot", "iPad 2"], Action(interaction: .Boot, query: .Configured([FBSimulatorConfiguration.iPad2()]), format: Format.defaultValue())),
      (["boot", "B8EEA6C4-841B-47E5-92DE-014E0ECD8139"], Action(interaction: .Boot, query: .UDID(["B8EEA6C4-841B-47E5-92DE-014E0ECD8139"]), format: Format.defaultValue())),
      (["boot", "iPhone 5", "shutdown", "iPhone 6"], Action(interaction: .Boot, query: .And([.Configured([FBSimulatorConfiguration.iPhone5(), FBSimulatorConfiguration.iPhone6()]), .State([.Shutdown])]), format: Format.defaultValue()))
    ])
  }

  func testParsesInstall() {
    let interaction = Interaction.Install(Fixtures.application())
    let prefix: [String] = ["install", Fixtures.application().path]

    self.assertParsesAll(Action.parser(), [
      (prefix, Action(interaction: interaction, query: Query.defaultValue(), format: Format.defaultValue())),
      (prefix + ["iPad 2"], Action(interaction: interaction, query: .Configured([FBSimulatorConfiguration.iPad2()]), format: Format.defaultValue())),
      (prefix + ["B8EEA6C4-841B-47E5-92DE-014E0ECD8139"], Action(interaction: interaction, query: .UDID(["B8EEA6C4-841B-47E5-92DE-014E0ECD8139"]), format: Format.defaultValue())),
      (prefix + ["iPhone 5", "shutdown", "iPhone 6"], Action(interaction: interaction, query: .And([.Configured([FBSimulatorConfiguration.iPhone5(), FBSimulatorConfiguration.iPhone6()]), .State([.Shutdown])]), format: Format.defaultValue())),
    ])
  }

  func testParsesAppLaunch() {
    let interaction = Interaction.Launch(FBApplicationLaunchConfiguration(application: Fixtures.application(), arguments: [], environment: [:]))
    let prefix: [String] = ["launch", Fixtures.application().path]

    self.assertParsesAll(Action.parser(), [
      (prefix, Action(interaction: interaction, query: Query.defaultValue(), format: Format.defaultValue())),
      (prefix + ["iPad 2"], Action(interaction: interaction, query: .Configured([FBSimulatorConfiguration.iPad2()]), format: Format.defaultValue())),
      (prefix + ["B8EEA6C4-841B-47E5-92DE-014E0ECD8139"], Action(interaction: interaction, query: .UDID(["B8EEA6C4-841B-47E5-92DE-014E0ECD8139"]), format: Format.defaultValue())),
      (prefix + ["iPhone 5", "shutdown", "iPhone 6"], Action(interaction: interaction, query: .And([.Configured([FBSimulatorConfiguration.iPhone5(), FBSimulatorConfiguration.iPhone6()]), .State([.Shutdown])]), format: Format.defaultValue())),
    ])
  }

  func testParsesAgentLaunch() {
    let interaction = Interaction.Launch(FBAgentLaunchConfiguration(binary: Fixtures.binary(), arguments: [], environment: [:]))
    let prefix: [String] = ["launch", Fixtures.binary().path]

    self.assertParsesAll(Action.parser(), [
      (prefix, Action(interaction: interaction, query: Query.defaultValue(), format: Format.defaultValue())),
      (prefix + ["iPad 2"], Action(interaction: interaction, query: .Configured([FBSimulatorConfiguration.iPad2()]), format: Format.defaultValue())),
      (prefix + ["B8EEA6C4-841B-47E5-92DE-014E0ECD8139"], Action(interaction: interaction, query: .UDID(["B8EEA6C4-841B-47E5-92DE-014E0ECD8139"]), format: Format.defaultValue())),
      (prefix + ["iPhone 5", "shutdown", "iPhone 6"], Action(interaction: interaction, query: .And([.Configured([FBSimulatorConfiguration.iPhone5(), FBSimulatorConfiguration.iPhone6()]), .State([.Shutdown])]), format: Format.defaultValue())),
    ])
  }

  func testParsesShutdown() {
    self.assertParsesAll(Action.parser(), [
      (["shutdown"], Action(interaction: .Shutdown, query: Query.defaultValue(), format: Format.defaultValue())),
      (["shutdown", "iPad 2"], Action(interaction: .Shutdown, query: .Configured([FBSimulatorConfiguration.iPad2()]), format: Format.defaultValue())),
      (["shutdown", "B8EEA6C4-841B-47E5-92DE-014E0ECD8139"], Action(interaction: .Shutdown, query: .UDID(["B8EEA6C4-841B-47E5-92DE-014E0ECD8139"]), format: Format.defaultValue())),
      (["shutdown", "iPhone 5", "shutdown", "iPhone 6"], Action(interaction: .Shutdown, query: .And([.Configured([FBSimulatorConfiguration.iPhone5(), FBSimulatorConfiguration.iPhone6()]), .State([.Shutdown])]), format: Format.defaultValue())),
    ])
  }

  func testParsesDiagnose() {
    self.assertParsesAll(Action.parser(), [
      (["diagnose"], Action(interaction: .Diagnose, query: Query.defaultValue(), format: Format.defaultValue())),
      (["diagnose", "iPad 2"], Action(interaction: .Diagnose, query: .Configured([FBSimulatorConfiguration.iPad2()]), format: Format.defaultValue())),
      (["diagnose", "B8EEA6C4-841B-47E5-92DE-014E0ECD8139"], Action(interaction: .Diagnose, query: .UDID(["B8EEA6C4-841B-47E5-92DE-014E0ECD8139"]), format: Format.defaultValue())),
      (["diagnose", "iPhone 5", "shutdown", "iPhone 6"], Action(interaction: .Diagnose, query: .And([.Configured([FBSimulatorConfiguration.iPhone5(), FBSimulatorConfiguration.iPhone6()]), .State([.Shutdown])]), format: Format.defaultValue())),
    ])
  }
}

class CommandParserTests : XCTestCase {
  func testParsesSingleAction() {
    self.assertParsesAll(Command.parser(), [
      (["boot", "B8EEA6C4-841B-47E5-92DE-014E0ECD8139"], Command.Perform(Configuration.defaultValue(), [Action(interaction: .Boot, query: .UDID(["B8EEA6C4-841B-47E5-92DE-014E0ECD8139"]), format: Format.defaultValue())])),
    ])
  }

  func testParsesMultipleActions() {
    self.assertParsesAll(Command.parser(), [
      (["list", "booted", "boot", "B8EEA6C4-841B-47E5-92DE-014E0ECD8139"], Command.Perform(Configuration.defaultValue(), [
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
