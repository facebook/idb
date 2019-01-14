/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBDeviceDebuggerCommands.h"

#import "FBAMDevice+Private.h"
#import "FBAMDevice.h"
#import "FBDeveloperDiskImage.h"
#import "FBDevice+Private.h"
#import "FBDevice.h"
#import "FBDeviceControlError.h"

// Much of the implementation here comes from:
// - DTDeviceKitBase which provides implementations of functions for calling AMDevice calls.
// - IDEiOSSupportCore that is a a client of 'DTDeviceKitBase'
// - DebuggerLLDB.ideplugin is the Xcode plugin responsible for executing the lldb commands via a C++ for launching an Application. This is linked directly by the Xcode App, but can use a remote interface.
//  - This can be traced with dtrace, (e.g. `sudo dtrace -n 'objc$target:*:*HandleCommand*:entry { ustack();} ' -p XCODE_PID`)
//  - Also effective tracing is to see the commands that lldb has downstream by setting in lldbinit `log enable -v -f /tmp/lldb.log lldb api`
//  - DebuggerLLDB uses a combination of calls to the C++ LLDB API and executing command strings here.

static void MountCallback(NSDictionary<NSString *, id> *callbackDictionary, FBAMDevice *device)
{
  [device.logger logFormat:@"Mount Progress: %@", [FBCollectionInformation oneLineDescriptionFromDictionary:callbackDictionary]];
}

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

#pragma mark Public

- (FBFutureContext<FBAMDServiceConnection *> *)connectToDebugServer
{
  return [[self
    mountDeveloperDiskImage]
    onQueue:self.device.workQueue pushTeardown:^(id _) {
      return [self.device.amDevice startService:@"com.apple.debugserver"];
    }];
}

#pragma mark Private

- (FBFuture<FBDeveloperDiskImage *> *)mountDeveloperDiskImage
{
  NSError *error = nil;
  FBDeveloperDiskImage *diskImage = [FBDeveloperDiskImage developerDiskImage:self.device error:&error];
  if (!diskImage) {
    return [FBFuture futureWithError:error];
  }
  return [[self.device.amDevice
    connectToDeviceWithPurpose:@"mount_disk_image"]
    onQueue:self.device.workQueue pop:^ FBFuture<NSDictionary<NSString *, NSDictionary<NSString *, id> *> *> * (FBAMDevice *device) {
      NSDictionary *options = @{
        @"ImageSignature": diskImage.signature,
        @"ImageType": @"Developer",
      };
      int status = device.calls.MountImage(
        device.amDevice,
        (__bridge CFStringRef)(diskImage.diskImagePath),
        (__bridge CFDictionaryRef)(options),
        (AMDeviceProgressCallback) MountCallback,
        (__bridge void *) (device)
      );
      if (status != 0) {
        NSString *internalMessage = CFBridgingRelease(self.device.amDevice.calls.CopyErrorText(status));
        return [[FBDeviceControlError
          describeFormat:@"Failed to mount image '%@' with error (%@)", diskImage.diskImagePath, internalMessage]
          failFuture];
      }
      return [FBFuture futureWithResult:diskImage];
    }];
}


@end
