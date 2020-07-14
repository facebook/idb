/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBDeviceManager.h"

#import "FBAMDevice+Private.h"
#import "FBDeviceControlError.h"
#import "FBDeviceControlFrameworkLoader.h"
#import "FBDeviceStorage.h"

@implementation FBDeviceManager

@synthesize delegate = _delegate;

- (instancetype)initWithLogger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _logger = logger;
  _storage = [[FBDeviceStorage alloc] initWithLogger:logger];

  return self;
}

- (void)dealloc
{
  [self stopListeningWithError:nil];
}

#pragma mark Implemented in Subclasses

- (BOOL)startListeningWithError:(NSError **)error
{
  return [[FBDeviceControlError
    describeFormat:@"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd)]
    failBool:error];
}

- (BOOL)stopListeningWithError:(NSError **)error
{
  return [[FBDeviceControlError
    describeFormat:@"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd)]
    failBool:error];
}

- (id)constructPublic:(PrivateDevice)privateDevice identifier:(NSString *)identifier info:(NSDictionary<NSString *,id> *)info
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

+ (void)updatePublicReference:(id)publicDevice privateDevice:(PrivateDevice)privateDevice identifier:(NSString *)identifier info:(NSDictionary<NSString *,id> *)info
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self), NSStringFromSelector(_cmd));
}

+ (PrivateDevice)extractPrivateReference:(id)publicDevice
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self), NSStringFromSelector(_cmd));
  return nil;
}

#pragma mark Called in Subclasses

- (void)deviceConnected:(PrivateDevice)privateDevice identifier:(NSString *)identifier info:(NSDictionary<NSString *,id> *)info
{
  [self.logger logFormat:@"Device Connected %@", privateDevice];

  // Make sure that we pull from all known instances created by this class.
  // We do this instead of the attached ones.
  // The reason for doing so is that consumers of these instances may be holding onto a reference to a device that's been re-connected.
  // Pulling from the map of referenced devices means that we re-use these referenced devices if they are present and the underlying reference is replaced.
  // If the device is no-longer referenced it will have been removed from the referencedDevices mapping as it's values are weakly-held.
  id device = [self.storage deviceForKey:identifier];
  if (device) {
    [self.logger.info logFormat:@"Device has been re-attached %@", device];
  } else {
    device = [self constructPublic:privateDevice identifier:identifier info:info];
    [self.logger.info logFormat:@"Created a new Device instance %@", device];
  }

  // See whether the Private API reference represents a replacement of something we already know bout.
  PrivateDevice oldPrivateDevice = [self.class extractPrivateReference:device];
  if (oldPrivateDevice == NULL) {
    [self.logger logFormat:@"New '%@' appeared for the first time", privateDevice];
    [self.class updatePublicReference:device privateDevice:privateDevice identifier:identifier info:info];
  } else if (privateDevice != oldPrivateDevice) {
    [self.logger logFormat:@"New '%@' replaces Old Device '%@'", privateDevice, oldPrivateDevice];
    [self.class updatePublicReference:device privateDevice:privateDevice identifier:identifier info:info];
  } else {
    [self.logger logFormat:@"Existing Device %@ is the same as the old", privateDevice];
  }

  // Update the internal state
  [self.storage deviceAttached:device forKey:identifier];

  // Notify the delegate.
  [self.delegate targetAdded:device inTargetSet:self];
}

- (void)deviceDisconnected:(PrivateDevice)privateDevice identifier:(NSString *)identifier
{
  [self.logger logFormat:@"Device Disconnected %@", privateDevice];
  id device = [self.storage deviceForKey:identifier];
  if (!device) {
    [self.logger logFormat:@"No Device named %@ from attached devices, nothing to remove", identifier];
    return;
  }
  [self.logger logFormat:@"Removing Device %@ from attached devices", identifier];

  // Update the internal state.
  [self.storage deviceDetachedForKey:identifier];

  // Notify the delegate
  [self.delegate targetRemoved:device inTargetSet:self];
}

#pragma mark Public

- (NSArray<id> *)currentDeviceList
{
  return [self.storage.attached.allValues sortedArrayUsingSelector:@selector(uniqueIdentifier)];
}

- (NSArray<id<FBiOSTargetInfo>> *)allTargetInfos
{
  return self.currentDeviceList;
}

- (NSString *)description
{
  return [NSString stringWithFormat:@"%@: %@", NSStringFromClass(self.class), [FBCollectionInformation oneLineDescriptionFromArray:self.allTargetInfos]];
}

@end
