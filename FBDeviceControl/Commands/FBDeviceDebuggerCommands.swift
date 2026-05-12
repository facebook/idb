/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

// swiftlint:disable force_cast

/*
Much of the implementation here comes from:
 - DTDeviceKitBase which provides implementations of functions for calling AMDevice calls. This is used to establish the 'debugserver' socket, which is then consumed by lldb itself.
 - DVTFoundation calls out to the DebuggerLLDB.ideplugin plugin, which provides implementations of lldb debugger clients.
 - DebuggerLLDB.ideplugin is the plugin/framework responsible for calling the underlying debugger, there are different objc class implementations depending on what is being debugged.
 - These implementations are backed by interfaces to the SBDebugger class (https://lldb.llvm.org/python_api/lldb.SBDebugger.html)
 - 'LLDBRPCDebugger' is the class responsible for debugging over an RPC interface, this is used for debugging iOS Devices, since it is running against a remote debugserver on the iOS device, forwarded over a socket on the host. This is backed by the lldb_rpc:SBDebugger class within the lldb codebase.
 - DebuggerLLDB uses a combination of calls to the C++ LLDB API and executing command strings here. The bulk of the implementation is in ` -[DBGLLDBLauncher _doRegularDebugWithTarget:usingDebugServer:errTargetString:outError:]`.
 - It is possible to trace (using dtrace) the commands that Xcode runs to start a debug session, by observing the 'HandleCommand:' method on the Objc class that wraps SBDebugger.
  - To trace the stacks of the command strings that are executed: `sudo dtrace -n 'objc$target:*:*HandleCommand*:entry { ustack(); }' -p XCODE_PID``
  - To trace the command strings that are executed: `sudo dtrace -n 'objc$target:*:*HandleCommand*:entry { printf("HandleCommand = %s\n", copyinstr(arg2)); }' -p XCODE_PID``
  - To trace stacks of all API calls: `sudo dtrace -n 'objc$target:LLDBRPCDebugger:*:entry { ustack(); }'  -p XCODE_PID`
 - It is also possible to use lldb's internal logging to see the API calls that it is making. This is done by configuring lldb via adding a line in ~/.lldbinit (e.g `log enable -v -f /tmp/lldb.log lldb api`)
 */
@objc(FBDeviceDebuggerCommands)
public class FBDeviceDebuggerCommands: NSObject, FBiOSTargetCommand {
  private weak var device: FBDevice?

  // MARK: - Initializers

  public class func commands(with target: any FBiOSTarget) -> Self {
    return self.init(device: target as! FBDevice)
  }

  required init(device: FBDevice) {
    self.device = device
    super.init()
  }

  // MARK: - FBDebuggerCommands (legacy FBFuture entry point)

  public func launchDebugServer(forHostApplication application: FBBundleDescriptor, port: in_port_t) -> FBFuture<any FBDebugServer> {
    fbFutureFromAsync { [self] in
      try await launchDebugServerAsync(forHostApplication: application, port: port)
    }
  }

  // MARK: - Public

  /**
   Starts the Debug Server and exposes it via a service connection.

   @return a future context with the service connection to the debug server.
   */
  public func connectToDebugServer() -> FBFutureContext<FBAMDServiceConnection> {
    guard let device else {
      return FBFutureContext(error: FBDeviceControlError().describe("Device is nil").build())
    }
    return
      device
      .ensureDeveloperDiskImageIsMounted()
      .onQueue(
        device.workQueue,
        pushTeardown: { diskImage -> FBFutureContext<AnyObject> in
          // Xcode 12 and after uses a different service name for the debugserver.
          let serviceName =
            diskImage.xcodeVersion.majorVersion >= 12
            ? "com.apple.debugserver.DVTSecureSocketProxy"
            : "com.apple.debugserver"
          return device.startService(serviceName) as! FBFutureContext<AnyObject>
        }) as! FBFutureContext<FBAMDServiceConnection>
  }

  // MARK: - Async

  fileprivate func launchDebugServerAsync(forHostApplication application: FBBundleDescriptor, port: in_port_t) async throws -> any FBDebugServer {
    guard let device else {
      throw FBDeviceControlError().describe("Device is nil").build()
    }
    if device.osVersion.version.majorVersion >= 17 {
      throw FBDeviceControlError()
        .describe("Debugging is not supported for devices running iOS 17 and higher. Device OS version: \(device.osVersion.versionString)")
        .build()
    }
    let commands = try await lldbBootstrapCommandsAsync(forApplicationAtPath: application.path, port: port)
    let server = FBDeviceDebugServer.debugServer(
      forServiceConnection: connectToDebugServer(),
      port: port,
      lldbBootstrapCommands: commands,
      queue: device.workQueue,
      logger: device.logger ?? FBControlCoreGlobalConfiguration.defaultLogger
    )
    let result = try await bridgeFBFuture(server)
    return result as! any FBDebugServer
  }

  // MARK: - Private

  private func lldbBootstrapCommandsAsync(forApplicationAtPath path: String, port: in_port_t) async throws -> [String] {
    guard device != nil else {
      throw FBDeviceControlError().describe("Device is nil").build()
    }
    let bundle = try FBBundleDescriptor.bundle(fromPath: path)
    let platformSelect = try platformSelectCommand()
    let localTarget = "target create '\(path)'"
    let remote = try await remoteTargetAsync(forBundleID: bundle.identifier)
    let processConnect = "process connect connect://localhost:\(port)"
    return [platformSelect, localTarget, remote, processConnect]
  }

  private func platformSelectCommand() throws -> String {
    guard let device else {
      throw FBDeviceControlError().describe("Device is nil").build()
    }
    let platformSelectCommand = "platform select remote-ios"
    guard let buildVersion = device.buildVersion else {
      device.logger?.log("No build version available for \(device), no symbolication of system libraries will occur.")
      return platformSelectCommand
    }
    do {
      let developerSymbolsPath = try FBDeveloperDiskImage.pathForDeveloperSymbols(buildVersion, logger: device.logger ?? FBControlCoreGlobalConfiguration.defaultLogger)
      return platformSelectCommand + " --sysroot '\(developerSymbolsPath)'"
    } catch {
      device.logger?.log("Failed to get developer symbols for \(device), no symbolication of system libraries will occur. To fix ensure developer symbols are downloaded from the device using the 'Devices and Simulators' tool within Xcode: \(error)")
      return platformSelectCommand
    }
  }

  private func remoteTargetAsync(forBundleID bundleID: String) async throws -> String {
    guard let device else {
      throw FBDeviceControlError().describe("Device is nil").build()
    }
    let installedApplication = try await bridgeFBFuture(device.installedApplication(withBundleID: bundleID))
    return "script lldb.target.modules[0].SetPlatformFileSpec(lldb.SBFileSpec(\"\(installedApplication.bundle.path)\"))"
  }
}

// MARK: - FBDevice+AsyncDebuggerCommands

extension FBDevice: AsyncDebuggerCommands {

  public func launchDebugServer(
    forHostApplication application: FBBundleDescriptor,
    port: in_port_t
  ) async throws -> any FBDebugServer {
    try await debuggerCommands().launchDebugServerAsync(forHostApplication: application, port: port)
  }
}

// MARK: - FBDevice+FBDebuggerCommands

extension FBDevice: FBDebuggerCommands {

  @objc(launchDebugServerForHostApplication:port:)
  public func launchDebugServer(forHostApplication application: FBBundleDescriptor, port: in_port_t) -> FBFuture<FBDebugServer> {
    do {
      return try debuggerCommands().launchDebugServer(forHostApplication: application, port: port)
    } catch {
      return FBFuture(error: error)
    }
  }
}
