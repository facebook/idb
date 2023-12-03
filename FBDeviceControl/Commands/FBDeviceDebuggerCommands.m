/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBDeviceDebuggerCommands.h"

#import "FBDevice+Private.h"
#import "FBDevice.h"
#import "FBDeviceControlError.h"
#import "FBDeviceDebugServer.h"

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

@interface FBDeviceDebuggerCommands ()

@property (nonatomic, weak, readonly) FBDevice *device;

@end

@implementation FBDeviceDebuggerCommands

#pragma mark Public

+ (instancetype)commandsWithTarget:(FBDevice *)target
{
  return [[self alloc] initWithDevice:target];
}

- (instancetype)initWithDevice:(FBDevice *)device
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _device = device;

  return self;
}

#pragma mark FBDebuggerCommands Implementation

- (FBFuture<id<FBDebugServer>> *)launchDebugServerForHostApplication:(FBBundleDescriptor *)application port:(in_port_t)port
{
  if (self.device.osVersion.version.majorVersion >= 17) {
    return [[FBDeviceControlError
           describeFormat:@"Debugging is not supported for devices running iOS 17 and higher. Device OS version: %@", self.device.osVersion.versionString]
        failFuture];
  }
  return [[self
    lldbBootstrapCommandsForApplicationAtPath:application.path port:port]
    onQueue:self.device.workQueue fmap:^(NSArray<NSString *> *commands) {
      return [FBDeviceDebugServer debugServerForServiceConnection:[self connectToDebugServer] port:port lldbBootstrapCommands:commands queue:self.device.workQueue logger:self.device.logger];
    }];
}

#pragma mark Public

- (FBFutureContext<FBAMDServiceConnection *> *)connectToDebugServer
{
  return [[self.device
    ensureDeveloperDiskImageIsMounted]
    onQueue:self.device.workQueue pushTeardown:^(FBDeveloperDiskImage *diskImage) {
      // Xcode 12 and after uses a different service name for the debugserver.
      return [self.device startService:(diskImage.xcodeVersion.majorVersion >= 12 ? @"com.apple.debugserver.DVTSecureSocketProxy" : @"com.apple.debugserver")];
    }];
}

#pragma mark Private

- (FBFuture<FBBundleDescriptor *> *)applicationBundleForPath:(NSString *)path
{
  return [FBFuture resolveValue:^(NSError **error) {
    return [FBBundleDescriptor bundleFromPath:path error:error];
  }];
}

- (FBFuture<NSArray<NSString *> *> *)lldbBootstrapCommandsForApplicationAtPath:(NSString *)path port:(in_port_t)port
{
  return [[self
    applicationBundleForPath:path]
    onQueue:self.device.workQueue fmap:^(FBBundleDescriptor *bundle) {
      return [FBFuture futureWithFutures:@[
        [self platformSelectCommand],
        [FBDeviceDebuggerCommands localTargetForApplicationAtPath:path],
        [self remoteTargetForBundleID:bundle.identifier],
        [FBDeviceDebuggerCommands processConnectForPort:port],
      ]];
    }];
}

- (FBFuture<NSString *> *)platformSelectCommand
{
  FBDevice *device = self.device;
  id<FBControlCoreLogger> logger = self.device.logger;
  return [FBFuture
    onQueue:self.device.asyncQueue resolveValue:^(NSError **error) {
      NSError *innerError = nil;
      NSString *developerSymbolsPath = [FBDeveloperDiskImage pathForDeveloperSymbols:device.buildVersion logger:logger error:&innerError];
      NSString *platformSelectCommand = @"platform select remote-ios";
      if (!developerSymbolsPath) {
        [logger logFormat:@"Failed to get developer symbols for %@, no symbolication of system libraries will occur. To fix ensure developer symbols are downloaded from the device using the 'Devices and Simulators' tool within Xcode: %@", device, innerError];
        return platformSelectCommand;
      }
      return [platformSelectCommand stringByAppendingFormat:@" --sysroot '%@'", developerSymbolsPath];
    }];
}

+ (FBFuture<NSString *> *)localTargetForApplicationAtPath:(NSString *)path
{
  return [FBFuture futureWithResult:[NSString stringWithFormat:@"target create '%@'", path]];
}

- (FBFuture<NSString *> *)remoteTargetForBundleID:(NSString *)bundleID
{
  return [[self.device
    installedApplicationWithBundleID:bundleID]
    onQueue:self.device.asyncQueue map:^(FBInstalledApplication *installedApplication) {
      return [NSString stringWithFormat:@"script lldb.target.modules[0].SetPlatformFileSpec(lldb.SBFileSpec(\"%@\"))", installedApplication.bundle.path];
    }];
}

+ (FBFuture<NSString *> *)processConnectForPort:(in_port_t)port
{
  return [FBFuture futureWithResult:[NSString stringWithFormat:@"process connect connect://localhost:%d", port]];
}

@end
