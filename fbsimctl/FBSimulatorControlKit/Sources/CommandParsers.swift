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
    let expected = NSStringFromClass(NSUUID.self)
    return Parser<NSUUID>.single("A \(expected)") { token in
      guard let uuid = NSUUID(UUIDString: token) else {
        throw ParseError.CouldNotInterpret(expected, token)
      }
      return uuid
    }
  }

  static func ofDirectory() -> Parser<String> {
    let expected = "A Directory"
    return Parser<String>.single(expected) { token in
      var isDirectory: ObjCBool = false
      if !NSFileManager.defaultManager().fileExistsAtPath(token, isDirectory: &isDirectory) {
        throw ParseError.Custom("'\(token)' should exist, but doesn't")
      }
      if (!isDirectory) {
        throw ParseError.Custom("'\(token)' should be a directory, but isn't")
      }
      return token
    }
  }

  static func ofFile() -> Parser<String> {
    let expected = "A File"
    return Parser<String>.single(expected) { token in
      var isDirectory: ObjCBool = false
      if !NSFileManager.defaultManager().fileExistsAtPath(token, isDirectory: &isDirectory) {
        throw ParseError.Custom("'\(token)' should exist, but doesn't")
      }
      if (isDirectory) {
        throw ParseError.Custom("'\(token)' should be a file, but isn't")
      }
      return token
    }
  }

  static func ofApplication() -> Parser<FBSimulatorApplication> {
    let expected = "An Application"
    return Parser<FBSimulatorApplication>.single(expected) { token in
      do {
        return try FBSimulatorApplication(path: token)
      } catch let error as NSError {
        throw ParseError.Custom("Could not get an app \(token) \(error.description)")
      }
    }
  }

  static func ofBinary() -> Parser<FBSimulatorBinary> {
    let expected = "A Binary"
    return Parser<FBSimulatorBinary>.single(expected) { token in
      do {
        return try FBSimulatorBinary(path: token)
      } catch let error as NSError {
        throw ParseError.Custom("Could not get an binary \(token) \(error.description)")
      }
    }
  }
}

extension FBSimulatorState : Parsable {
  public static func parser() -> Parser<FBSimulatorState> {
    return Parser.alternative([
        Parser.ofString("--state=creating", FBSimulatorState.Creating),
        Parser.ofString("--state=shutdown", FBSimulatorState.Shutdown),
        Parser.ofString("--state=booting", FBSimulatorState.Booting),
        Parser.ofString("--state=booted", FBSimulatorState.Booted),
        Parser.ofString("--state=shutting-down", FBSimulatorState.ShuttingDown),
      ])
    }
}

extension Command : Parsable {
  public static func parser() -> Parser<Command> {
    return Parser
      .alternative([
        self.helpParser(),
        self.interactParser(),
        self.actionParser()
      ])
  }

  static func actionParser() -> Parser<Command> {
    return Parser
      .ofTwoSequenced(
        Configuration.parser(),
        Parser.manyCount(1, Action.parser())
      )
      .fmap { (configuration, actions) in
        return Command.Perform(configuration, actions)
      }
  }

  static func interactParser() -> Parser<Command> {
    return Parser
      .ofTwoSequenced(
        Configuration.parser(),
        Parser.succeeded("interact", Parser.succeeded("--port", Parser<Int>.ofInt()).optional())
      )
      .fmap { (configuration, port) in
        return Command.Interact(configuration, port)
      }
  }

  static func helpParser() -> Parser<Command> {
    return Parser
      .ofString("help", .Help(nil))
  }
}

extension FBSimulatorAllocationOptions : Parsable {
  public static func parser() -> Parser<FBSimulatorAllocationOptions> {
    return Parser
      .alternativeMany([
        self.createParser(),
        self.reuseParser(),
        self.shutdownOnAllocateParser(),
        self.eraseOnAllocateParser(),
        self.deleteOnFreeParser(),
        self.eraseOnAllocateParser(),
        self.eraseOnFreeParser()
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
    return Parser.ofString("--create", FBSimulatorAllocationOptions.Create)
  }

  static func reuseParser() -> Parser<FBSimulatorAllocationOptions> {
    return Parser.ofString("--reuse", FBSimulatorAllocationOptions.Reuse)
  }

  static func shutdownOnAllocateParser() -> Parser<FBSimulatorAllocationOptions> {
    return Parser.ofString("--shutdown-on-allocate", FBSimulatorAllocationOptions.ShutdownOnAllocate)
  }

  static func eraseOnAllocateParser() -> Parser<FBSimulatorAllocationOptions> {
    return Parser.ofString("--erase-on-allocate", FBSimulatorAllocationOptions.EraseOnAllocate)
  }

  static func deleteOnFreeParser() -> Parser<FBSimulatorAllocationOptions> {
    return Parser.ofString("--delete-on-free", FBSimulatorAllocationOptions.DeleteOnFree)
  }

  static func eraseOnFreeParser() -> Parser<FBSimulatorAllocationOptions> {
    return Parser.ofString("--erase-on-free", FBSimulatorAllocationOptions.EraseOnFree)
  }
}

extension FBSimulatorManagementOptions : Parsable {
  public static func parser() -> Parser<FBSimulatorManagementOptions> {
    return Parser
      .alternativeMany(1, [
        self.deleteAllOnFirstParser(),
        self.killAllOnFirstParser(),
        self.killSpuriousSimulatorsOnFirstStartParser(),
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
    return Parser.ofString("--delete-all", .DeleteAllOnFirstStart)
  }

  static func killAllOnFirstParser() -> Parser<FBSimulatorManagementOptions> {
    return Parser.ofString("--kill-all", .KillAllOnFirstStart)
  }

  static func killSpuriousSimulatorsOnFirstStartParser() -> Parser<FBSimulatorManagementOptions> {
    return Parser.ofString("--kill-spurious", .KillSpuriousSimulatorsOnFirstStart)
  }

  static func ignoreSpuriousKillFailParser() -> Parser<FBSimulatorManagementOptions> {
    return Parser.ofString("--ignore-spurious-kill-fail", .IgnoreSpuriousKillFail)
  }

  static func killSpuriousCoreSimulatorServicesParser() -> Parser<FBSimulatorManagementOptions> {
    return Parser.ofString("--kill-spurious-services", .KillSpuriousCoreSimulatorServices)
  }

  static func useProcessKillingParser() -> Parser<FBSimulatorManagementOptions> {
    return Parser.ofString("--process-killing", .UseProcessKilling)
  }

  static func useSimDeviceTimeoutResilianceParser() -> Parser<FBSimulatorManagementOptions> {
    return Parser.ofString("--timeout-resiliance", .UseSimDeviceTimeoutResiliance)
  }
}

extension Configuration : Parsable {
  public static func parser() -> Parser<Configuration> {
    return Parser
      .ofTwoSequenced(
        Parser<Bool>.ofFlag(Flags.DebugLogging),
        self.controlConfigurationParser()
      )
      .fmap { (debugLogging, controlConfiguration) in
        return Configuration(controlConfiguration: controlConfiguration, debugLogging: debugLogging)
      }
  }

  public static func controlConfigurationParser() -> Parser<FBSimulatorControlConfiguration> {
    return Parser.ofTwoSequenced(
        Parser.succeeded("--set", Parser<String>.ofDirectory()).optional(),
        FBSimulatorManagementOptions.parser().fallback(FBSimulatorManagementOptions.defaultValue())
      )
      .fmap { setPath, options in
        return FBSimulatorControlConfiguration(deviceSetPath: setPath, options: options)
      }
  }
}

extension Interaction : Parsable {
  public static func parser() -> Parser<Interaction> {
    return Parser.alternative([
      Parser.ofString("list", Interaction.List),
      Parser.ofString("boot", Interaction.Boot),
      Parser.ofString("shutdown", Interaction.Shutdown),
      Parser.ofString("diagnose", Interaction.Diagnose),
      self.installParser(),
      self.launchParser()
    ])
  }

  private static func installParser() -> Parser<Interaction> {
    return Parser
      .succeeded("install", Parser<FBSimulatorApplication>.ofApplication())
      .fmap { Interaction.Install($0) }
  }

  private static func launchParser() -> Parser<Interaction> {
    return Parser
      .succeeded("launch", self.processLaunchParser())
      .fmap { Interaction.Launch($0) }
  }

  private static func processLaunchParser() -> Parser<FBProcessLaunchConfiguration> {
    return Parser<FBProcessLaunchConfiguration>
      .alternative([
        self.agentLaunchParser(),
        self.appLaunchParser()
      ])
  }

  private static func agentLaunchParser() -> Parser<FBProcessLaunchConfiguration> {
    return Parser<FBSimulatorBinary>
      .ofBinary()
      .fmap { FBAgentLaunchConfiguration(binary: $0, arguments: [], environment: [:]) }
  }

  private static func appLaunchParser() -> Parser<FBProcessLaunchConfiguration> {
    return Parser<FBSimulatorApplication>
      .ofApplication()
      .fmap { FBApplicationLaunchConfiguration(application: $0, arguments: [], environment: [:]) }
  }
}

extension Action : Parsable {
  public static func parser() -> Parser<Action> {
    return Parser
      .ofThreeSequenced(
        Query.parser().fallback(Query.defaultValue()),
        Format.parser().fallback(Format.defaultValue()),
        Interaction.parser()
      )
      .fmap { (query, format, interaction) in
        return Action(interaction: interaction, query: query, format: format)
      }
  }
}

extension Query : Parsable {
  public static func parser() -> Parser<Query> {
    return Parser
      .alternativeMany(1, [
        FBSimulatorState.parser().fmap { Query.State([$0]) },
        Query.uuidParser(),
        Query.nameParser()
      ])
      .fmap { Query.flatten($0) }
  }

  private static func nameParser() -> Parser<Query> {
    return Parser.single("A Device Name") { token in
      let deviceConfigurations = FBSimulatorConfiguration.deviceConfigurations() as! [FBSimulatorConfiguration_Device]
      let deviceNames = Set(deviceConfigurations.map { $0.deviceName() })
      if (!deviceNames.contains(token)) {
        throw ParseError.Custom("\(token) is not a valid device name")
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
      .alternativeMany(1, [
        Parser.ofString("--udid", Format.UDID),
        Parser.ofString("--name", Format.Name),
        Parser.ofString("--device-name", Format.DeviceName),
        Parser.ofString("--os", Format.OSVersion),
        Parser.ofString("--state", Format.State),
        Parser.ofString("--pid", Format.ProcessIdentifier)
      ])
      .fmap { Format.flatten($0) }
    }
}
