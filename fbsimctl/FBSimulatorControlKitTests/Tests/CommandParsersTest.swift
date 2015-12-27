// Copyright 2004-present Facebook. All Rights Reserved.

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
