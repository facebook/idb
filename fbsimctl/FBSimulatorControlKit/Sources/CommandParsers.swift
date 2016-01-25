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

  static func ofBundleID() -> Parser<String> {
    return Parser<String>
      .alternative([
        Parser<FBSimulatorApplication>.ofApplication().fmap { $0.bundleID },
        Parser<String>.single("A Bundle ID") { token in
          let components = token.componentsSeparatedByCharactersInSet(NSCharacterSet(charactersInString: "."))
          if components.count < 2 {
            throw ParseError.Custom("Bundle ID must contain a '.'")
          }
          return token
        }
      ])
  }
}

extension Configuration : Parsable {
  public static func parser() -> Parser<Configuration> {
    return Parser
      .ofThreeSequenced(
        self.optionsParser(),
        Parser.succeeded("--set", Parser<String>.ofDirectory()).optional(),
        FBSimulatorManagementOptions.parser()
      )
      .fmap { (options, deviceSetPath, managementOptions) in
        return Configuration(options: options, deviceSetPath: deviceSetPath, managementOptions: managementOptions)
      }
  }

  static func optionsParser() -> Parser<Configuration.Options> {
    return Parser<Configuration.Options>
      .unionOptions([
        Parser.ofString(Flags.DebugLogging, Configuration.Options.DebugLogging),
        Parser.ofString("--json", Configuration.Options.JSON),
        Parser.ofString("---pretty", Configuration.Options.Pretty)
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
        self.approveParser(),
        self.bootParser(),
        Parser.ofString("shutdown", Interaction.Shutdown),
        Parser.ofString("diagnose", Interaction.Diagnose),
        Parser.ofString("delete", Interaction.Delete),
        self.installParser(),
        self.launchParser()
      ])
  }

  private static func approveParser() -> Parser<Interaction> {
    return Parser
      .succeeded("approve", Parser.manyCount(1, Parser<String>.ofBundleID()))
      .fmap { Interaction.Approve($0) }
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
        self.appLaunchParser(),
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
        Parser<FBSimulatorApplication>.ofBundleID(),
        self.argumentParser()
      )
      .fmap { (bundleID, arguments) in
        return FBApplicationLaunchConfiguration(bundleID: bundleID, bundleName: nil, arguments: arguments, environment : [:])
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

extension Keyword : Parsable {
  public static func parser() -> Parser<Keyword> {
    return Parser
      .alternative([
        Parser.ofString(Keyword.UDID.rawValue, Keyword.UDID),
        Parser.ofString(Keyword.Name.rawValue, Keyword.Name),
        Parser.ofString(Keyword.DeviceName.rawValue, Keyword.DeviceName),
        Parser.ofString(Keyword.OSVersion.rawValue, Keyword.OSVersion),
        Parser.ofString(Keyword.State.rawValue, Keyword.State),
        Parser.ofString(Keyword.ProcessIdentifier.rawValue, Keyword.ProcessIdentifier)
      ])
  }
}

extension SequenceType where Generator.Element == Keyword {
  public static func parser() -> Parser<Format> {
    return Parser.manyCount(1, Keyword.parser())
  }
}

/**
 A separate struct for FBSimulatorConfiguration is needed as Parsable protcol conformance cannot be
 applied to FBSimulatorConfiguration as it is a non-final.
 */
struct FBSimulatorConfigurationParser {
  static func parser() -> Parser<FBSimulatorConfiguration> {
    return Parser
      .ofThreeSequenced(
        self.deviceParser().optional(),
        self.osVersionParser().optional(),
        self.auxDirectoryParser().optional()
      )
      .fmap { (device, os, auxDirectory) in
        if device == nil && os == nil && auxDirectory == nil {
          throw ParseError.Custom("Simulator Configuration must contain at least one of: Device Name, OS Version or Aux Directory")
        }
        let configuration = FBSimulatorConfiguration.defaultConfiguration().copy() as! FBSimulatorConfiguration
        if let device = device {
          configuration.device = device
        }
        if let os = os {
          configuration.os = os
        }
        if let auxDirectory = auxDirectory {
          configuration.auxillaryDirectory = auxDirectory
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

  static func auxDirectoryParser() -> Parser<String> {
    return Parser.succeeded("--aux", Parser<String>.ofDirectory())
  }
}

/**
 A separate struct for FBSimulatorLaunchConfigurationParser is needed as Parsable protcol conformance cannot be
 applied to FBSimulatorLaunchConfigurationParser as it is a non-final.
 */
struct FBSimulatorLaunchConfigurationParser {
  static func parser() -> Parser<FBSimulatorLaunchConfiguration> {
    return Parser
      .ofThreeSequenced(
        self.localeParser().optional(),
        self.scaleParser().optional(),
        self.optionsParser().optional()
      )
      .fmap { (locale, scale, options) in
        if locale == nil && scale == nil && options == nil {
          throw ParseError.Custom("Simulator Launch Configuration must contain at least a locale or scale")
        }
        var configuration = FBSimulatorLaunchConfiguration.defaultConfiguration().copy() as! FBSimulatorLaunchConfiguration
        if let locale = locale {
          configuration = configuration.withLocale(locale)
        }
        if let scale = scale {
          configuration = configuration.withScale(scale)
        }
        if let options = options {
          configuration = configuration.withOptions(options)
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

  static func optionsParser() -> Parser<FBSimulatorLaunchOptions> {
    return Parser<FBSimulatorLaunchOptions>
      .unionOptions(1, [
        Parser.ofString("--direct-launch", FBSimulatorLaunchOptions.EnableDirectLaunch),
        Parser.ofString("--record-video", FBSimulatorLaunchOptions.RecordVideo),
        Parser.ofString("--debug-window", FBSimulatorLaunchOptions.ShowDebugWindow)
      ])
  }
}

