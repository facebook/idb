/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBDeviceDebuggerCommands.h"

#import "FBDeveloperDiskImage.h"
#import "FBDevice+Private.h"
#import "FBDevice.h"
#import "FBDeviceControlError.h"
#import "FBDeviceDebugServer.h"

// Much of the implementation here comes from:
// - DTDeviceKitBase which provides implementations of functions for calling AMDevice calls.
// - IDEiOSSupportCore that is a a client of 'DTDeviceKitBase'
// - DebuggerLLDB.ideplugin is the Xcode plugin responsible for executing the lldb commands via a C++ for launching an Application. This is linked directly by the Xcode App, but can use a remote interface.
//  - This can be traced with dtrace, (e.g. `sudo dtrace -n 'objc$target:*:*HandleCommand*:entry { ustack();} ' -p XCODE_PID`)
//  - Also effective tracing is to see the commands that lldb has downstream by setting in lldbinit `log enable -v -f /tmp/lldb.log lldb api`
//  - DebuggerLLDB uses a combination of calls to the C++ LLDB API and executing command strings here.

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
    mountDeveloperDiskImage]
    onQueue:self.device.workQueue pushTeardown:^(id _) {
      return [self.device startService:@"com.apple.debugserver"];
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
  return [[FBFuture
    resolveValue:^(NSError **error) {
      return [FBDeveloperDiskImage pathForDeveloperSymbols:self.device logger:self.device.logger error:error];
    }]
    onQueue:self.device.workQueue map:^(NSString *path) {
      return [NSString stringWithFormat:@"platform select remote-ios --sysroot '%@'", path];
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
