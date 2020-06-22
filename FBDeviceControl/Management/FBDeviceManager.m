/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBDeviceManager.h"

#import "FBDeviceControlError.h"
#import "FBDeviceControlFrameworkLoader.h"
#import "FBAMDevice+Private.h"

@interface FBDeviceManager ()

@property (nonatomic, strong, readonly) NSMutableDictionary<NSString *, id> *attachedDevices;
@property (nonatomic, strong, readonly) NSMapTable<NSString *, id> *referencedDevices;

@end

@implementation FBDeviceManager

@synthesize delegate = _delegate;

- (instancetype)initWithCalls:(AMDCalls)calls queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _calls = calls;
  _queue = queue;
  _logger = logger;
  _attachedDevices = [NSMutableDictionary dictionary];
  _referencedDevices = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsCopyIn valueOptions:NSPointerFunctionsWeakMemory];

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
  id device = [self.referencedDevices objectForKey:identifier];
  id attachedDevice = self.attachedDevices[identifier];
  if (device) {
    [self.logger.info logFormat:@"Device has been re-attached %@", device];
    NSAssert(attachedDevice == nil || device == attachedDevice, @"Known referenced device %@ does not match the attached one %@!", device, attachedDevice);
  } else {
    device = [self constructPublic:privateDevice identifier:identifier info:info];
    [self.logger.info logFormat:@"Created a new Device instance %@", device];
    NSAssert(attachedDevice == nil, @"An device is in the attached but it is not in the weak set! Attached device %@", attachedDevice);
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

  // Set both the strong-memory and the weak-memory device.
  // If it already exists this is fine, otherwise it will ensure that this mapping is preserved.
  // Any removed devies will be removed from attachedDevices on disconnect so that abandoned device references are cleaned up.
  self.attachedDevices[identifier] = device;
  [self.referencedDevices setObject:device forKey:identifier];

  [self.delegate targetAdded:device inTargetSet:self];
}

- (void)deviceDisconnected:(PrivateDevice)privateDevice identifier:(NSString *)identifier
{
  [self.logger logFormat:@"Device Disconnected %@", privateDevice];
  id device = self.attachedDevices[identifier];
  if (!device) {
    [self.logger logFormat:@"No Device named %@ from attached devices, nothing to remove", identifier];
    return;
  }
  [self.logger logFormat:@"Removing Device %@ from attached devices", identifier];

  // Remove only from the list of attached devices.
  // If the device instance is not referenced elsewhere it will be removed from the referencedDevices dictionary.
  // This is because the values in that dictionary are weakly referenced.
  [self.attachedDevices removeObjectForKey:identifier];
  [self.delegate targetRemoved:device inTargetSet:self];
}

#pragma mark Public

- (NSArray<id> *)currentDeviceList
{
  return [self.attachedDevices.allValues sortedArrayUsingSelector:@selector(udid)];
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
