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

/**
 Defines a single transaction with FBSimulatorControl
*/
public struct Command {
  let configuration: Configuration
  let subcommand: Subcommand
}

/**
  Describes the Configuration for the running of a Command
*/
public struct Configuration {
  let deviceSetPath: String?

  static func defaultConfiguration() -> Configuration {
    return Configuration(deviceSetPath: nil)
  }
}

/**
 Defines a Format for displaying Simulator Information
*/
public indirect enum Format {
  case UDID
  case Name
  case DeviceName
  case OSVersion
  case Compound([Format])
}

/**
 Defines the pieces of a Query for Simulators
*/
public indirect enum Query {
  case UDID(String)
  case State(FBSimulatorState)
  case Compound([Query])
  case Configured(FBSimulatorConfiguration)
}

/**
 The Base of all fbsimctl commands
*/
public indirect enum Subcommand {
  case Interact(Int?)
  case List(Query, Format)
  case Boot(Query)
  case Shutdown(Query)
  case Diagnose(Query)
  case Help(Subcommand?)
}
