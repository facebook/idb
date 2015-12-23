/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

import Foundation
import FBSimulatorControl

extension Parser {
  static func ofUDID() -> Parser<NSUUID> {
    return Parser<NSUUID>.single { token in
      guard let uuid = NSUUID(UUIDString: token) else {
        throw ParseError.InvalidNumber
      }
      return uuid
    }
  }

  static func ofDirectory() -> Parser<String> {
    return Parser<String>.single { token in
      var isDirectory: ObjCBool = false
      if !NSFileManager.defaultManager().fileExistsAtPath(token, isDirectory: &isDirectory) {
        throw ParseError.InvalidNumber
      }
      if (!isDirectory) {
        throw ParseError.InvalidNumber
      }
      return token
    }
  }

  static func ofFile() -> Parser<String> {
    return Parser<String>.single { token in
      var isDirectory: ObjCBool = false
      if !NSFileManager.defaultManager().fileExistsAtPath(token, isDirectory: &isDirectory) {
        throw ParseError.InvalidNumber
      }
      if (isDirectory) {
        throw ParseError.InvalidNumber
      }
      return token
    }
  }
}

extension FBSimulatorState : Parsable {
  public static func parser() -> Parser<FBSimulatorState> {
    return Parser<FBSimulatorState>.single { token in
      let state = FBSimulator.simulatorStateFromStateString(token)
      switch (state) {
      case .Unknown:
        throw ParseError.DoesNotMatchAnyOf([
          FBSimulatorState.Creating.description,
          FBSimulatorState.Shutdown.description,
          FBSimulatorState.Booting.description,
          FBSimulatorState.Booted.description,
          FBSimulatorState.ShuttingDown.description
        ])
      default:
        return state
      }
    }
  }
}

extension Command : Parsable {
  public static func parser() -> Parser<Command> {
    return Parser
      .ofTwo(Configuration.parser(), b: Subcommand.parser())
      .fmap { (configuration, subcommand) in
        Command(configuration: configuration, subcommand: subcommand)
    }
  }
}

extension FBSimulatorAllocationOptions : Parsable {
  public static func parser() -> Parser<FBSimulatorAllocationOptions> {
    return Parser
      .ofMany([
        self.createParser(),
        self.reuseParser(),
        self.shutdownOnAllocateParser(),
        self.eraseOnAllocateParser(),
        self.deleteOnFreeParser(),
        self.eraseOnAllocateParser()
        ])
      .fmap { options in
        var set = FBSimulatorAllocationOptions()
        for option in options {
          set.unionInPlace(option)
        }
        return set
      }
  }

  static func createParser() -> Parser<FBSimulatorAllocationOptions> {
    return Parser.ofString("--create", constant: FBSimulatorAllocationOptions.Create)
  }

  static func reuseParser() -> Parser<FBSimulatorAllocationOptions> {
    return Parser.ofString("--reuse", constant: FBSimulatorAllocationOptions.Reuse)
  }

  static func shutdownOnAllocateParser() -> Parser<FBSimulatorAllocationOptions> {
    return Parser.ofString("--shutdown-on-allocate", constant: FBSimulatorAllocationOptions.ShutdownOnAllocate)
  }

  static func eraseOnAllocateParser() -> Parser<FBSimulatorAllocationOptions> {
    return Parser.ofString("--erase-on-allocate", constant: FBSimulatorAllocationOptions.EraseOnAllocate)
  }

  static func deleteOnFreeParser() -> Parser<FBSimulatorAllocationOptions> {
    return Parser.ofString("--delete-on-free", constant: FBSimulatorAllocationOptions.DeleteOnFree)
  }

  static func eraseOnFreeParser() -> Parser<FBSimulatorAllocationOptions> {
    return Parser.ofString("--erase-on-free", constant: FBSimulatorAllocationOptions.EraseOnFree)
  }
}

extension FBSimulatorManagementOptions : Parsable {
  public static func parser() -> Parser<FBSimulatorManagementOptions> {
    return Parser
      .ofMany([
        self.deleteAllOnFirstParser(),
        self.killSpuriousCoreSimulatorServicesParser(),
        self.ignoreSpuriousKillFailParser(),
        self.killSpuriousCoreSimulatorServicesParser(),
        self.useProcessKillingParser(),
        self.useSimDeviceTimeoutResilianceParser()
        ])
      .fmap { options in
        var set = FBSimulatorManagementOptions()
        for option in options {
          set.unionInPlace(option)
        }
        return set
    }
  }

  static func deleteAllOnFirstParser() -> Parser<FBSimulatorManagementOptions> {
    return Parser.ofString("--delete-all", constant: FBSimulatorManagementOptions.DeleteAllOnFirstStart)
  }

  static func killSpuriousSimulatorsOnFirstStartParser() -> Parser<FBSimulatorManagementOptions> {
    return Parser.ofString("--kill-spurious", constant: FBSimulatorManagementOptions.KillSpuriousCoreSimulatorServices)
  }

  static func ignoreSpuriousKillFailParser() -> Parser<FBSimulatorManagementOptions> {
    return Parser.ofString("--ignore-spurious-kill-fail", constant: FBSimulatorManagementOptions.IgnoreSpuriousKillFail)
  }

  static func killSpuriousCoreSimulatorServicesParser() -> Parser<FBSimulatorManagementOptions> {
    return Parser.ofString("--kill-spurious-services", constant: FBSimulatorManagementOptions.KillSpuriousCoreSimulatorServices)
  }

  static func useProcessKillingParser() -> Parser<FBSimulatorManagementOptions> {
    return Parser.ofString("--process-killing", constant: FBSimulatorManagementOptions.UseProcessKilling)
  }

  static func useSimDeviceTimeoutResilianceParser() -> Parser<FBSimulatorManagementOptions> {
    return Parser.ofString("--timeout-resiliance", constant: FBSimulatorManagementOptions.KillSpuriousCoreSimulatorServices)
  }
}

extension Configuration : Parsable {
  public static func parser() -> Parser<Configuration> {
    return Parser.ofTwo(deviceSetParser(), b: FBSimulatorManagementOptions.parser())
      .fmap { setPath, options in
        return Configuration(
          simulatorApplication: try! FBSimulatorApplication(error: ()),
          deviceSetPath: setPath,
          options: options
        )
      }
  }

  static func deviceSetParser() -> Parser<String?> {
    return Parser
      .succeeded("--device-set", by: Parser<String>.ofDirectory() )
      .optional()
  }
}

extension Subcommand : Parsable {
  public static func parser() -> Parser<Subcommand> {
    return Parser.ofAny([
      self.helpParser(),
      self.interactParser(),
      self.listParser(),
      self.bootParser(),
      self.shutdownParser(),
      self.diagnoseParser(),
    ])
  }

  static func helpParser() -> Parser<Subcommand> {
    return Parser.ofString("help", constant: .Help(nil))
  }

  static func interactParser() -> Parser<Subcommand> {
    return Parser
      .succeeded("interact", by: Parser.succeeded("--port", by: Parser<Int>.ofInt()).optional())
      .fmap { Subcommand.Interact($0) }
  }

  static func listParser() -> Parser<Subcommand> {
    let followingParser = Parser
      .ofTwo(Query.parser(), b: Format.parser())
      .fmap { (query, format) in
        Subcommand.List(query, format)
    }

    return Parser.succeeded("list", by: followingParser)
  }

  static func bootParser() -> Parser<Subcommand> {
    return Parser
      .succeeded("boot", by: Query.parser())
      .fmap { Subcommand.Boot($0) }
  }

  static func shutdownParser() -> Parser<Subcommand> {
    return Parser
      .succeeded("shutdown", by: Query.parser())
      .fmap { Subcommand.Shutdown($0) }
  }

  static func diagnoseParser() -> Parser<Subcommand> {
    return Parser
      .succeeded("diagnose", by: Query.parser())
      .fmap { Subcommand.Diagnose($0) }
  }
}

extension Query : Parsable {
  public static func parser() -> Parser<Query> {
    return Parser
      .ofManyCount(1, parsers: [
        FBSimulatorState.parser().fmap { Query.State([$0]) },
        Query.uuidParser(),
        Query.nameParser()
      ])
      .fmap { Query.flatten($0) }
  }

  private static func nameParser() -> Parser<Query> {
    return Parser.single { token in
      let deviceConfigurations = FBSimulatorConfiguration.deviceConfigurations() as! [FBSimulatorConfiguration_Device]
      let deviceNames = Set(deviceConfigurations.map { $0.deviceName() })
      if (!deviceNames.contains(token)) {
        throw ParseError.InvalidNumber
      }
      let configuration: FBSimulatorConfiguration! = FBSimulatorConfiguration.withDeviceNamed(token)
      return Query.Configured([configuration])
    }
  }

  private static func uuidParser() -> Parser<Query> {
    return Parser<Query>
      .ofUDID()
      .fmap { Query.UDID([$0.UUIDString]) }
  }
}

extension Format : Parsable {
  public static func parser() -> Parser<Format> {
    return Parser
      .ofManyCount(1, parsers: [
        Parser.ofString("--udid", constant: Format.UDID),
        Parser.ofString("--name", constant: Format.Name),
        Parser.ofString("--device-name", constant: Format.DeviceName),
        Parser.ofString("--os", constant: Format.OSVersion)
      ])
      .fmap { Format.flatten($0) }
    }
}
