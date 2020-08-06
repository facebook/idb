/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBAMDeviceServiceManager.h"

#import "FBAMDevice.h"
#import "FBDeviceControlError.h"
#import "FBAMDevice+Private.h"

@interface FBAMDeviceServiceManager_HouseArrest : NSObject<FBFutureContextManagerDelegate>

@property (nonatomic, weak, readonly) FBAMDevice *device;
@property (nonatomic, copy, readonly) NSString *bundleID;
@property (nonatomic, assign, readonly) AFCCalls calls;

@end

@implementation FBAMDeviceServiceManager_HouseArrest

@synthesize contextPoolTimeout = _contextPoolTimeout;

- (instancetype)initWithDevice:(FBAMDevice *)device bundleID:(NSString *)bundleID calls:(AFCCalls)calls serviceTimeout:(nullable NSNumber *)serviceTimeout
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _device = device;
  _bundleID = bundleID;
  _calls = calls;
  _contextPoolTimeout = serviceTimeout;

  return self;
}

- (FBFuture<FBAFCConnection *> *)prepare:(id<FBControlCoreLogger>)logger
{
  AFCConnectionRef afcConnection = NULL;
  [logger logFormat:@"Starting house arrest for '%@'", self.bundleID];
  int status = self.device.calls.CreateHouseArrestService(
    self.device.amDeviceRef,
    (__bridge CFStringRef _Nonnull)(self.bundleID),
    NULL,
    &afcConnection
  );
  if (status != 0) {
    NSString *internalMessage = CFBridgingRelease(self.device.calls.CopyErrorText(status));
    return [[[FBDeviceControlError
      describeFormat:@"Failed to start house_arrest service for '%@' with error 0x%x (%@)", self.bundleID, status, internalMessage]
      logger:logger]
      failFuture];
  }
  FBAFCConnection *connection = [[FBAFCConnection alloc] initWithConnection:afcConnection calls:self.calls logger:logger];
  return [FBFuture futureWithResult:connection];
}

- (FBFuture<NSNull *> *)teardown:(FBAFCConnection *)connection logger:(id<FBControlCoreLogger>)logger
{
  [logger logFormat:@"Closing connection to House Arrest for '%@'", self.bundleID];
  NSError *error = nil;
  if (![connection closeWithError:&error]) {
    [logger logFormat:@"Failed to close House Arrest for '%@' with error %@", self.bundleID, error];
    return [FBFuture futureWithError:error];
  } else {
    [logger logFormat:@"Closed House Arrest service for '%@'", self.bundleID];
    return FBFuture.empty;
  }
}

- (NSString *)contextName
{
  return [NSString stringWithFormat:@"house_arrest_%@", self.bundleID];
}

- (BOOL)isContextSharable
{
  return NO;
}

@end

@interface FBAMDeviceServiceManager ()

@property (nonatomic, weak, readonly) FBAMDevice *device;
@property (nonatomic, copy, nullable, readonly) NSNumber *serviceTimeout;
@property (nonatomic, strong, readonly) NSMutableDictionary<NSString *, FBFutureContextManager<FBAFCConnection *> *> *houseArrestManagers;
@property (nonatomic, strong, readonly) NSMutableDictionary<NSString *, FBAMDeviceServiceManager_HouseArrest *> *houseArrestDelegates;

@end

@implementation FBAMDeviceServiceManager

#pragma mark Initializers

+ (instancetype)managerWithAMDevice:(FBAMDevice *)device serviceTimeout:(nullable NSNumber *)serviceTimeout
{
  return [[self alloc] initWithAMDevice:device serviceTimeout:serviceTimeout];
}

- (instancetype)initWithAMDevice:(FBAMDevice *)device serviceTimeout:(nullable NSNumber *)serviceTimeout
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _device = device;
  _serviceTimeout = serviceTimeout;
  _houseArrestManagers = [NSMutableDictionary dictionary];
  _houseArrestDelegates = [NSMutableDictionary dictionary];

  return self;
}

#pragma mark Public Services

- (FBFutureContextManager<FBAFCConnection *> *)houseArrestAFCConnectionForBundleID:(NSString *)bundleID afcCalls:(AFCCalls)afcCalls
{
  FBFutureContextManager<FBAFCConnection *> *manager = self.houseArrestManagers[bundleID];
  if (manager) {
    return manager;
  }
  FBAMDeviceServiceManager_HouseArrest *delegate = [[FBAMDeviceServiceManager_HouseArrest alloc] initWithDevice:self.device bundleID:bundleID calls:afcCalls serviceTimeout:self.serviceTimeout];
  manager = [FBFutureContextManager managerWithQueue:self.device.workQueue delegate:delegate logger:self.device.logger];
  self.houseArrestManagers[bundleID] = manager;
  self.houseArrestDelegates[bundleID] = delegate;
  return manager;
}

@end
