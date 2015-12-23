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
    self.assertParses(Configuration.parser(), [], Configuration(
      simulatorApplication: try! FBSimulatorApplication(error: ()),
      deviceSetPath: nil,
      options: FBSimulatorManagementOptions()
    ))
  }

  func testParsesWithSetPath() {
    self.assertParses(
      Configuration.parser(),
      ["--device-set", "/usr/bin"],
      Configuration(
        simulatorApplication: try! FBSimulatorApplication(error: ()),
        deviceSetPath: "/usr/bin",
        options: FBSimulatorManagementOptions()
      )
    )
  }

  func testParseFailureWithInvalidSetPath() {
    self.assertParseFails(
      Configuration.deviceSetParser(),
      ["--device-set", "/usr/asd2asd2___2332213/asdbin"]
    )
  }

  func testParsesWithOptions() {
    self.assertParses(
      Configuration.parser(),
      ["--kill-all", "--process-killing"],
      Configuration(
        simulatorApplication: try! FBSimulatorApplication(error: ()),
        deviceSetPath: nil,
        options: FBSimulatorManagementOptions.KillAllOnFirstStart.union(.UseProcessKilling)
      )
    )
  }

  func testParsesWithSetPathAndOptions() {
    self.assertParses(
      Configuration.parser(),
      ["--device-set", "/usr/bin", "--delete-all", "--kill-spurious"],
      Configuration(
        simulatorApplication: try! FBSimulatorApplication(error: ()),
        deviceSetPath: "/usr/bin",
        options: FBSimulatorManagementOptions.DeleteAllOnFirstStart.union(.KillSpuriousSimulatorsOnFirstStart)
      )
    )
  }
}

class ActionParserTests : XCTestCase {
  func testParsesInteract() {
    self.assertParsesAll(Action.parser(), [
      (["interact"], Action.Interact(nil)),
      (["interact", "--port", "42"], Action.Interact(42))
    ])
  }

  func testParsesList() {
    self.assertParsesAll(Action.parser(), [
      (["list"], Action.List(Query.defaultValue(), Format.defaultValue())),
      (["list", "booted"], Action.List(Query.State([.Booted]), Format.defaultValue())),
      (["list", "--name"], Action.List(Query.defaultValue(), Format.Name)),
      (["list", "B8EEA6C4-841B-47E5-92DE-014E0ECD8139", "--os"], Action.List(Query.UDID(["B8EEA6C4-841B-47E5-92DE-014E0ECD8139"]), Format.OSVersion)),
      (["list", "booted", "iPhone 5", "--device-name", "--os"], Action.List(Query.And([.State([.Booted]), .Configured([FBSimulatorConfiguration.iPhone5()])]), Format.Compound([.DeviceName, .OSVersion])))
    ])
  }

  func testParsesBoot() {
    self.assertParsesAll(Action.parser(), [
      (["boot"], Action.Boot(Query.defaultValue())),
      (["boot", "iPad 2"], Action.Boot(.Configured([FBSimulatorConfiguration.iPad2()]))),
      (["boot", "B8EEA6C4-841B-47E5-92DE-014E0ECD8139"], Action.Boot(.UDID(["B8EEA6C4-841B-47E5-92DE-014E0ECD8139"]))),
      (["boot", "iPhone 5", "shutdown", "iPhone 6"], Action.Boot(.And([.Configured([FBSimulatorConfiguration.iPhone5(), FBSimulatorConfiguration.iPhone6()]), .State([.Shutdown])]))),
    ])
  }

  func testParsesShutdown() {
    self.assertParsesAll(Action.parser(), [
      (["shutdown"], Action.Shutdown(Query.defaultValue())),
      (["shutdown", "iPad 2"], Action.Shutdown(.Configured([FBSimulatorConfiguration.iPad2()]))),
      (["shutdown", "B8EEA6C4-841B-47E5-92DE-014E0ECD8139"], Action.Shutdown(.UDID(["B8EEA6C4-841B-47E5-92DE-014E0ECD8139"]))),
      (["shutdown", "iPhone 5", "shutdown", "iPhone 6"], Action.Shutdown(.And([.Configured([FBSimulatorConfiguration.iPhone5(), FBSimulatorConfiguration.iPhone6()]), .State([.Shutdown])]))),
    ])
  }

  func testParsesDiagnose() {
    self.assertParsesAll(Action.parser(), [
      (["diagnose"], Action.Diagnose(Query.defaultValue())),
      (["diagnose", "iPad 2"], Action.Diagnose(.Configured([FBSimulatorConfiguration.iPad2()]))),
      (["diagnose", "B8EEA6C4-841B-47E5-92DE-014E0ECD8139"], Action.Diagnose(.UDID(["B8EEA6C4-841B-47E5-92DE-014E0ECD8139"]))),
      (["diagnose", "iPhone 5", "shutdown", "iPhone 6"], Action.Diagnose(.And([.Configured([FBSimulatorConfiguration.iPhone5(), FBSimulatorConfiguration.iPhone6()]), .State([.Shutdown])]))),
    ])
  }
}

class CommandParserTests : XCTestCase {
  func testParsesSingleAction() {
    self.assertParsesAll(Command.parser(), [
      (["interact"], Command.Single(Configuration.defaultValue(), Action.Interact(nil))),
      (["boot", "B8EEA6C4-841B-47E5-92DE-014E0ECD8139"], Command.Single(Configuration.defaultValue(), Action.Boot(.UDID(["B8EEA6C4-841B-47E5-92DE-014E0ECD8139"])))),
    ])
  }

  func testParsesHelp() {
    self.assertParsesAll(Command.parser(), [
      (["help"], Command.Help(nil))
    ])
  }
}
