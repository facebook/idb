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

  static func ofLocale() -> Parser<NSLocale> {
    let expected = "A Locale"
    return Parser<NSLocale>.single(expected) { token in
      return NSLocale(localeIdentifier: token)
    }
  }
}

extension Configuration : Parsable {
  public static func parser() -> Parser<Configuration> {
    return Parser
      .ofTwoSequenced(
        self.optionsParser(),
        self.controlConfigurationParser()
      )
      .fmap { (options, controlConfiguration) in
        return Configuration(controlConfiguration: controlConfiguration, options: options)
      }
  }

  public static func controlConfigurationParser() -> Parser<FBSimulatorControlConfiguration> {
    return Parser
      .ofTwoSequenced(
        Parser.succeeded("--set", Parser<String>.ofDirectory()).optional(),
        FBSimulatorManagementOptions.parser()
      )
      .fmap { setPath, options in
        return FBSimulatorControlConfiguration(deviceSetPath: setPath, options: options)
      }
  }

  static func optionsParser() -> Parser<Configuration.Options> {
    return Parser<Configuration.Options>
      .unionOptions([
        Parser.ofString(Flags.DebugLogging, Configuration.Options.DebugLogging),
        Parser.ofString("--json", Configuration.Options.JSONOutput)
      ])
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
        Action.parser()
      )
      .fmap { (configuration, action) in
        return Command.Perform(configuration, action)
      }
  }

  static func interactParser() -> Parser<Command> {
    return Parser
      .ofTwoSequenced(
        Configuration.parser(),
        Parser.succeeded("-i", Parser.succeeded("--port", Parser<Int>.ofInt()).optional())
      )
      .fmap { (configuration, port) in
        return Command.Interactive(configuration, port)
      }
  }

  static func helpParser() -> Parser<Command> {
    return Parser
      .ofString("help", .Help(nil))
  }
}

extension FBSimulatorAllocationOptions : Parsable {
  public static func parser() -> Parser<FBSimulatorAllocationOptions> {
    return Parser<FBSimulatorAllocationOptions>
      .unionOptions([
        self.createParser(),
        self.reuseParser(),
        self.shutdownOnAllocateParser(),
        self.eraseOnAllocateParser(),
        self.deleteOnFreeParser(),
        self.eraseOnAllocateParser(),
        self.eraseOnFreeParser()
      ])
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
    return Parser<FBSimulatorManagementOptions>
      .unionOptions([
        self.deleteAllOnFirstParser(),
        self.killAllOnFirstParser(),
        self.killSpuriousSimulatorsOnFirstStartParser(),
        self.ignoreSpuriousKillFailParser(),
        self.killSpuriousCoreSimulatorServicesParser(),
        self.useProcessKillingParser(),
        self.useSimDeviceTimeoutResilianceParser()
      ])
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

extension Interaction : Parsable {
  public static func parser() -> Parser<Interaction> {
    return Parser
      .alternative([
        Parser.ofString("list", Interaction.List),
        self.bootParser(),
        Parser.ofString("shutdown", Interaction.Shutdown),
        Parser.ofString("diagnose", Interaction.Diagnose),
        Parser.ofString("delete", Interaction.Delete),
        self.installParser(),
        self.launchParser()
      ])
  }

  private static func bootParser() -> Parser<Interaction> {
    return Parser
      .succeeded("boot", FBSimulatorLaunchConfigurationParser.parser().optional())
      .fmap { Interaction.Boot($0) }
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
    return Parser
      .ofTwoSequenced(
        Parser<FBSimulatorBinary>.ofBinary(),
        self.argumentParser()
      )
      .fmap { (binary, arguments) in
        return FBAgentLaunchConfiguration(binary: binary, arguments: arguments, environment : [:])
      }
  }

  private static func appLaunchParser() -> Parser<FBProcessLaunchConfiguration> {
    return Parser
      .ofTwoSequenced(
        Parser<FBSimulatorApplication>.ofApplication(),
        self.argumentParser()
      )
      .fmap { (application, arguments) in
        return FBApplicationLaunchConfiguration(application: application, arguments: arguments, environment : [:])
      }
    }

  private static func argumentParser() -> Parser<[String]> {
    return Parser.many(Parser<String>.ofAny())
  }
}

extension Action : Parsable {
  public static func parser() -> Parser<Action> {
    return Parser
      .alternative([
        self.interactionParser(),
        self.createParser()
      ])
  }

  private static func interactionParser() -> Parser<Action> {
    return Parser
      .ofThreeSequenced(
        Query.parser().optional(),
        Format.parser().optional(),
        Parser.manyCount(1, Interaction.parser())
      )
      .fmap { (query, format, interactions) in
        return Action.Interact(interactions, query, format)
      }
  }

  private static func createParser() -> Parser<Action> {
    return Parser
      .ofThreeSequenced(
        Format.parser().optional(),
        Parser.ofString("create", true),
        FBSimulatorConfigurationParser.parser()
      )
      .fmap { (format, _, configuration) in
        return Action.Create(configuration, format)
      }
  }
}

extension Query : Parsable {
  public static func parser() -> Parser<Query> {
    return Parser<Query>
      .alternativeMany(1, [
        self.simulatorStateParser(),
        self.uuidParser(),
        self.simulatorConfigurationParser()
      ])
      .fmap { Query.flatten($0) }
  }

  private static func uuidParser() -> Parser<Query> {
    return Parser<Query>
      .ofUDID()
      .fmap { Query.UDID([$0.UUIDString]) }
  }

  private static func simulatorStateParser() -> Parser<Query> {
    return FBSimulatorState
      .parser()
      .fmap { Query.State([$0]) }
  }

  private static func simulatorConfigurationParser() -> Parser<Query> {
    return FBSimulatorConfigurationParser
      .parser()
      .fmap { configuration in
        Query.Configured(Set([configuration]))
      }
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

/**
 A separate struct for FBSimulatorConfiguration is needed as Parsable protcol conformance cannot be
 applied to FBSimulatorConfiguration as it is a non-final.
 */
struct FBSimulatorConfigurationParser {
  static func parser() -> Parser<FBSimulatorConfiguration> {
    return Parser
      .ofTwoSequenced(
        self.deviceParser().optional(),
        self.osVersionParser().optional()
      )
      .fmap { (device, os) in
        if device == nil && os == nil {
          throw ParseError.Custom("Simulator Configuration must contain at least a device name or os version")
        }
        let configuration = FBSimulatorConfiguration.defaultConfiguration().copy() as! FBSimulatorConfiguration
        if let device = device {
          configuration.device = device
        }
        if let os = os {
          configuration.os = os
        }
        return configuration
      }
  }

  static func deviceParser() -> Parser<FBSimulatorConfiguration_Device> {
    return Parser.single("A Device Name") { token in
      let nameToDevice = FBSimulatorConfiguration.nameToDevice() as! [String : FBSimulatorConfiguration_Device]
      guard let device = nameToDevice[token] else {
        throw ParseError.Custom("\(token) is not a valid device name")
      }
      return device
    }
  }

  static func osVersionParser() -> Parser<FBSimulatorConfiguration_OS> {
    return Parser.single("An OS Version") { token in
      let nameToOSVersion = FBSimulatorConfiguration.nameToOSVersion() as! [String : FBSimulatorConfiguration_OS]
      guard let osVersion = nameToOSVersion[token] else {
        throw ParseError.Custom("\(token) is not a valid device name")
      }
      return osVersion
    }
  }
}

/**
 A separate struct for FBSimulatorLaunchConfigurationParser is needed as Parsable protcol conformance cannot be
 applied to FBSimulatorLaunchConfigurationParser as it is a non-final.
 */
struct FBSimulatorLaunchConfigurationParser {
  static func parser() -> Parser<FBSimulatorLaunchConfiguration> {
    return Parser
      .ofTwoSequenced(
        self.localeParser().optional(),
        self.scaleParser().optional()
      )
      .fmap { (locale, scale) in
        if locale == nil && scale == nil {
          throw ParseError.Custom("Simulator Launch Configuration must contain at least a locale or scale")
        }
        var configuration = FBSimulatorLaunchConfiguration.defaultConfiguration().copy() as! FBSimulatorLaunchConfiguration
        if let locale = locale {
          configuration = configuration.withLocale(locale)
        }
        if let scale = scale {
          configuration = configuration.withScale(scale)
        }
        return configuration
    }
  }

  static func localeParser() -> Parser<NSLocale> {
    return Parser
      .succeeded("--locale", Parser<NSLocale>.ofLocale())
  }

  static func scaleParser() -> Parser<FBSimulatorLaunchConfiguration_Scale> {
    return Parser.alternative([
      Parser.ofString("--scale=25", FBSimulatorLaunchConfiguration_Scale_25()),
      Parser.ofString("--scale=50", FBSimulatorLaunchConfiguration_Scale_50()),
      Parser.ofString("--scale=75", FBSimulatorLaunchConfiguration_Scale_75()),
      Parser.ofString("--scale=100", FBSimulatorLaunchConfiguration_Scale_100())
    ])
  }
}

