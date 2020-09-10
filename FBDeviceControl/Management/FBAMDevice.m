/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBAMDevice.h"
#import "FBAMDevice+Private.h"

#import <FBControlCore/FBControlCore.h>

#include <dlfcn.h>

#import "FBAFCConnection.h"
#import "FBAMDeviceManager.h"
#import "FBAMDeviceServiceManager.h"
#import "FBAMDServiceConnection.h"
#import "FBAMRestorableDevice.h"
#import "FBDeveloperDiskImage.h"
#import "FBDeviceActivationCommands.h"
#import "FBDeviceControlError.h"
#import "FBDeviceControlFrameworkLoader.h"
#import "FBDeviceLinkClient.h"

static void MountCallback(NSDictionary<NSString *, id> *callbackDictionary, FBAMDevice *device)
{
  [device.logger logFormat:@"Mount Progress: %@", [FBCollectionInformation oneLineDescriptionFromDictionary:callbackDictionary]];
}

#pragma mark - FBAMDevice Implementation

@implementation FBAMDevice

@synthesize amDeviceRef = _amDeviceRef;
@synthesize calls = _calls;
@synthesize contextPoolTimeout = _contextPoolTimeout;
@synthesize logger = _logger;

#pragma mark Initializers

- (instancetype)initWithAllValues:(NSDictionary<NSString *, id> *)allValues calls:(AMDCalls)calls connectionReuseTimeout:(nullable NSNumber *)connectionReuseTimeout serviceReuseTimeout:(nullable NSNumber *)serviceReuseTimeout workQueue:(dispatch_queue_t)workQueue logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _allValues = allValues;
  _calls = calls;
  _workQueue = workQueue;
  _logger = [logger withName:self.udid];
  _connectionContextManager = [FBFutureContextManager managerWithQueue:workQueue delegate:self logger:logger];
  _contextPoolTimeout = connectionReuseTimeout;
  _serviceManager = [FBAMDeviceServiceManager managerWithAMDevice:self serviceTimeout:serviceReuseTimeout];

  return self;
}

#pragma mark Properties

- (void)setAmDeviceRef:(AMDeviceRef)amDeviceRef
{
  AMDeviceRef oldAMDeviceRef = _amDeviceRef;
  _amDeviceRef = amDeviceRef;
  if (amDeviceRef) {
    self.calls.Retain(amDeviceRef);
  }
  if (oldAMDeviceRef) {
    self.calls.Release(oldAMDeviceRef);
  }
}

- (AMDeviceRef)amDevice
{
  return _amDeviceRef;
}

- (NSDictionary<NSString *, id> *)extendedInformation
{
  return @{
    @"device": [FBCollectionOperations recursiveFilteredJSONSerializableRepresentationOfDictionary:self.allValues],
  };
}

- (NSString *)uniqueIdentifier
{
  return [self.allValues[FBDeviceKeyUniqueChipID] stringValue];
}

- (NSString *)udid
{
  return self.allValues[FBDeviceKeyUniqueDeviceID];
}

- (NSString *)architecture
{
  return self.allValues[FBDeviceKeyCPUArchitecture];
}

- (NSString *)buildVersion
{
  return self.allValues[FBDeviceKeyBuildVersion];
}

- (NSString *)productVersion
{
  return self.allValues[FBDeviceKeyProductVersion];
}

- (NSString *)name
{
  return self.allValues[FBDeviceKeyDeviceName];
}

- (FBDeviceType *)deviceType
{
  return FBiOSTargetConfiguration.productTypeToDevice[self.allValues[FBDeviceKeyProductType]];
}

- (FBOSVersion *)osVersion
{
  NSString *osVersion = [FBAMDevice osVersionForDeviceClass:self.allValues[FBDeviceKeyDeviceClass] productVersion:self.productVersion];
  return FBiOSTargetConfiguration.nameToOSVersion[osVersion] ?: [FBOSVersion genericWithName:osVersion];
}

- (FBiOSTargetState)state
{
  return FBiOSTargetStateBooted;
}

- (FBiOSTargetType)targetType
{
  return FBiOSTargetTypeDevice;
}

#pragma mark FBDevice Protocol Implementation

- (AMRecoveryModeDeviceRef)recoveryModeDeviceRef
{
  return NULL;
}

- (FBDeviceActivationState)activationState
{
  return FBDeviceActivationStateCoerceFromString(self.allValues[FBDeviceKeyActivationState]);
}

#pragma mark FBDeviceCommands Protocol Implementation

- (FBFutureContext<FBAMDevice *> *)connectToDeviceWithPurpose:(NSString *)format, ...
{
  va_list args;
  va_start(args, format);
  NSString *string = [[NSString alloc] initWithFormat:format arguments:args];
  va_end(args);
  return [self.connectionContextManager utilizeWithPurpose:string];
}

- (FBFutureContext<FBAMDServiceConnection *> *)startService:(NSString *)service
{
  NSDictionary<NSString *, id> *userInfo = @{
    @"CloseOnInvalidate" : @1,
    @"InvalidateOnDetach" : @1,
  };
  // NOTE - The pop: after connectToDeviceWithPurpose: is critical to ensure we stop the AMDevice session
  //        immediately after the service is started. See longer description in FBAMDevice.h to understand why.
  return [[[self
    connectToDeviceWithPurpose:@"start_service_%@", service]
    onQueue:self.workQueue pop:^ FBFuture<FBAMDServiceConnection *> * (id<FBDeviceCommands> device) {
      AMDServiceConnectionRef serviceConnection;
      [self.logger logFormat:@"Starting service %@", service];
      int status = self.calls.SecureStartService(
        device.amDeviceRef,
        (__bridge CFStringRef)(service),
        (__bridge CFDictionaryRef)(userInfo),
        &serviceConnection
      );
      if (status != 0) {
        NSString *errorDescription = CFBridgingRelease(self.calls.CopyErrorText(status));
        return [[[FBDeviceControlError
          describeFormat:@"SecureStartService of %@ Failed with 0x%x %@", service, status, errorDescription]
          logger:self.logger]
          failFuture];
      }
      FBAMDServiceConnection *connection = [[FBAMDServiceConnection alloc] initWithServiceConnection:serviceConnection device:device.amDeviceRef calls:self.calls logger:self.logger];
      [self.logger logFormat:@"Service %@ started", service];
      return [FBFuture futureWithResult:connection];
    }]
    onQueue:self.workQueue contextualTeardown:^(id connection, FBFutureState __) {
      [self.logger logFormat:@"Invalidating service %@", service];
      NSError *error = nil;
      if (![connection invalidateWithError:&error]) {
        [self.logger logFormat:@"Failed to invalidate service %@ with error %@", service, error];
      } else {
        [self.logger logFormat:@"Invalidated service %@", service];
      }
      return FBFuture.empty;
    }];
}

- (FBFutureContext<FBDeviceLinkClient *> *)startDeviceLinkService:(NSString *)service
{
  return [[self
    startService:service]
    onQueue:self.workQueue pend:^(FBAMDServiceConnection *connection) {
      return [FBDeviceLinkClient deviceLinkClientWithConnection:connection];
    }];
}

- (FBFutureContext<FBAFCConnection *> *)startAFCService:(NSString *)service
{
  return [[self
    startService:service]
    onQueue:self.workQueue push:^(FBAMDServiceConnection *connection) {
      return [FBAFCConnection afcFromServiceConnection:connection calls:FBAFCConnection.defaultCalls logger:self.logger queue:self.workQueue];
    }];
}

- (FBFutureContext<FBAFCConnection *> *)houseArrestAFCConnectionForBundleID:(NSString *)bundleID afcCalls:(AFCCalls)afcCalls
{
  return [[self
    connectToDeviceWithPurpose:@"house_arrest"]
    onQueue:self.workQueue replace:^ FBFutureContext<FBAFCConnection *> * (id<FBDeviceCommands> device) {
      return [[self.serviceManager
        houseArrestAFCConnectionForBundleID:bundleID afcCalls:afcCalls]
        utilizeWithPurpose:self.udid];
    }];
}

static const int DiskImageAlreadyMountedCode = -402653066;  // 0xe8000076 in hex

- (FBFuture<FBDeveloperDiskImage *> *)mountDeveloperDiskImage
{
  NSError *error = nil;
  FBDeveloperDiskImage *diskImage = [FBDeveloperDiskImage developerDiskImage:self logger:self.logger error:&error];
  if (!diskImage) {
    return [FBFuture futureWithError:error];
  }
  return [[self
    connectToDeviceWithPurpose:@"mount_disk_image"]
    onQueue:self.workQueue pop:^ FBFuture<NSDictionary<NSString *, NSDictionary<NSString *, id> *> *> * (id<FBDeviceCommands> device) {
      NSDictionary *options = @{
        @"ImageSignature": diskImage.signature,
        @"ImageType": @"Developer",
      };
      int status = device.calls.MountImage(
        device.amDeviceRef,
        (__bridge CFStringRef)(diskImage.diskImagePath),
        (__bridge CFDictionaryRef)(options),
        (AMDeviceProgressCallback) MountCallback,
        (__bridge void *) (device)
      );
      if (status == DiskImageAlreadyMountedCode) {
        [device.logger logFormat:@"There is a disk image already mounted. Assuming that it is correct...."];
      }
      else if (status != 0) {
        NSString *internalMessage = CFBridgingRelease(device.calls.CopyErrorText(status));
        return [[FBDeviceControlError
          describeFormat:@"Failed to mount image '%@' with error 0x%x (%@)", diskImage.diskImagePath, status, internalMessage]
          failFuture];
      }
      return [FBFuture futureWithResult:diskImage];
    }];
}

#pragma mark FBFutureContextManager Implementation

- (FBFuture<FBAMDevice *> *)prepare:(id<FBControlCoreLogger>)logger
{
  NSError *error = nil;
  if (![FBAMDeviceManager startUsing:self.amDevice calls:self.calls logger:logger error:&error]) {
    return [FBFuture futureWithError:error];
  }
  return [FBFuture futureWithResult:self];
}

- (FBFuture<NSNull *> *)teardown:(FBAMDevice *)device logger:(id<FBControlCoreLogger>)logger;
{
  NSError *error = nil;
  if (![FBAMDeviceManager stopUsing:self.amDevice calls:self.calls logger:logger error:&error]) {
    return [FBFuture futureWithError:error];
  }
  return FBFuture.empty;
}

- (NSString *)contextName
{
  return [NSString stringWithFormat:@"%@_connection", self.udid];
}

- (BOOL)isContextSharable
{
  return YES;
}

#pragma mark NSObject

- (id)device:(AMDeviceRef)device valueForKey:(NSString *)key
{
  return CFBridgingRelease(self.calls.CopyValue(device, NULL, (__bridge CFStringRef)(key)));
}

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"AMDevice %@ | %@",
    self.udid,
    self.name
  ];
}

#pragma mark Private

+ (NSString *)osVersionForDeviceClass:(NSString *)deviceClass productVersion:(NSString *)productVersion
{
  NSDictionary<NSString *, NSString *> *deviceClassOSPrefixMapping = @{
    @"iPhone" : @"iOS",
    @"iPad" : @"iOS",
  };
  NSString *osPrefix = deviceClassOSPrefixMapping[deviceClass];
  if (!osPrefix) {
    return productVersion;
  }
  return [NSString stringWithFormat:@"%@ %@", osPrefix, productVersion];
}

@end
