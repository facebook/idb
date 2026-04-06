// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

import FBControlCore
import Foundation

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
public class FBDeviceDebuggerCommands: NSObject, FBDebuggerCommands {
  private weak var device: FBDevice?

  // MARK: - Initializers

  public class func commands(with target: any FBiOSTarget) -> Self {
    return self.init(device: target as! FBDevice)
  }

  required init(device: FBDevice) {
    self.device = device
    super.init()
  }

  // MARK: - FBDebuggerCommands

  public func launchDebugServer(forHostApplication application: FBBundleDescriptor, port: in_port_t) -> FBFuture<any FBDebugServer> {
    guard let device = device else {
      return FBFuture(error: FBDeviceControlError().describe("Device is nil").build())
    }
    if device.osVersion.version.majorVersion >= 17 {
      return FBFuture(
        error: FBDeviceControlError()
          .describe("Debugging is not supported for devices running iOS 17 and higher. Device OS version: \(device.osVersion.versionString)")
          .build()
      )
    }
    return
      (lldbBootstrapCommands(forApplicationAtPath: application.path, port: port)
      .onQueue(
        device.workQueue,
        fmap: { commands -> FBFuture<AnyObject> in
          return FBDeviceDebugServer.debugServer(
            forServiceConnection: self.connectToDebugServer(),
            port: port,
            lldbBootstrapCommands: commands as! [String],
            queue: device.workQueue,
            logger: device.logger
          )
        })) as! FBFuture<any FBDebugServer>
  }

  // MARK: - Public

  /**
   Starts the Debug Server and exposes it via a service connection.
  
   @return a future context with the service connection to the debug server.
   */
  public func connectToDebugServer() -> FBFutureContext<FBAMDServiceConnection> {
    guard let device = device else {
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

  // MARK: - Private

  private func applicationBundle(forPath path: String) -> FBFuture<FBBundleDescriptor> {
    do {
      let bundle = try FBBundleDescriptor.bundle(fromPath: path)
      return FBFuture(result: bundle)
    } catch {
      return FBFuture(error: error)
    }
  }

  private func lldbBootstrapCommands(forApplicationAtPath path: String, port: in_port_t) -> FBFuture<NSArray> {
    guard let device = device else {
      return FBFuture(error: FBDeviceControlError().describe("Device is nil").build())
    }
    return
      (applicationBundle(forPath: path)
      .onQueue(
        device.workQueue,
        fmap: { bundle -> FBFuture<AnyObject> in
          let platformSelectFuture = self.platformSelectCommand()
          let localTargetFuture = FBDeviceDebuggerCommands.localTarget(forApplicationAtPath: path)
          let remoteTargetFuture = self.remoteTarget(forBundleID: bundle.identifier)
          let processConnectFuture = FBDeviceDebuggerCommands.processConnect(forPort: port)
          // Chain: start with platformSelect, then accumulate the rest
          return platformSelectFuture.onQueue(
            device.workQueue,
            fmap: { cmd1 -> FBFuture<AnyObject> in
              return localTargetFuture.onQueue(
                device.workQueue,
                fmap: { cmd2 -> FBFuture<AnyObject> in
                  return remoteTargetFuture.onQueue(
                    device.workQueue,
                    fmap: { cmd3 -> FBFuture<AnyObject> in
                      return processConnectFuture.onQueue(
                        device.workQueue,
                        map: { cmd4 -> AnyObject in
                          return [cmd1, cmd2, cmd3, cmd4] as NSArray
                        })
                    })
                })
            })
        })) as! FBFuture<NSArray>
  }

  private func platformSelectCommand() -> FBFuture<NSString> {
    guard let device = device else {
      return FBFuture(error: FBDeviceControlError().describe("Device is nil").build())
    }
    return FBFuture.onQueue(
      device.asyncQueue,
      resolveValue: { _ in
        let platformSelectCommand = "platform select remote-ios"
        guard let buildVersion = device.buildVersion else {
          device.logger?.log("No build version available for \(device), no symbolication of system libraries will occur.")
          return platformSelectCommand as NSString
        }
        do {
          let developerSymbolsPath = try FBDeveloperDiskImage.pathForDeveloperSymbols(buildVersion, logger: device.logger ?? FBControlCoreGlobalConfiguration.defaultLogger)
          return (platformSelectCommand + " --sysroot '\(developerSymbolsPath)'") as NSString
        } catch {
          device.logger?.log("Failed to get developer symbols for \(device), no symbolication of system libraries will occur. To fix ensure developer symbols are downloaded from the device using the 'Devices and Simulators' tool within Xcode: \(error)")
          return platformSelectCommand as NSString
        }
      }) as! FBFuture<NSString>
  }

  private class func localTarget(forApplicationAtPath path: String) -> FBFuture<NSString> {
    return FBFuture(result: "target create '\(path)'" as NSString)
  }

  private func remoteTarget(forBundleID bundleID: String) -> FBFuture<NSString> {
    guard let device = device else {
      return FBFuture(error: FBDeviceControlError().describe("Device is nil").build())
    }
    return
      (device.installedApplication(withBundleID: bundleID)
      .onQueue(
        device.asyncQueue,
        map: { installedApplication -> AnyObject in
          return "script lldb.target.modules[0].SetPlatformFileSpec(lldb.SBFileSpec(\"\(installedApplication.bundle.path)\"))" as NSString
        })) as! FBFuture<NSString>
  }

  private class func processConnect(forPort port: in_port_t) -> FBFuture<NSString> {
    return FBFuture(result: "process connect connect://localhost:\(port)" as NSString)
  }
}
