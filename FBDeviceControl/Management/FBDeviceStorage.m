/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBDeviceStorage.h"

@interface FBDeviceStorage ()

@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;
@property (nonatomic, strong, readonly) NSMutableDictionary<NSString *, id> *attachedDevices;
@property (nonatomic, strong, readonly) NSMapTable<NSString *, id> *referencedDevices;

@end

@implementation FBDeviceStorage

- (instancetype)initWithLogger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _logger = logger;
  _attachedDevices = [NSMutableDictionary dictionary];
  _referencedDevices = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsCopyIn valueOptions:NSPointerFunctionsWeakMemory];

  return self;
}

#pragma mark Public Methods

- (void)deviceAttached:(id)device forKey:(NSString *)key
{
  // Set both the strong-memory and the weak-memory device.
  // If it already exists this is fine, otherwise it will ensure that this mapping is preserved.
  // Any removed devies will be removed from attachedDevices on disconnect so that abandoned device references are cleaned up.
  id attached = self.attachedDevices[key];
  id referenced = [self.referencedDevices objectForKey:key];
  if (attached && referenced) {
    [self.logger logFormat:@"%@ is an attached device update", device];
  } else if (referenced) {
    [self.logger logFormat:@"%@ is referenced and now attached again", device];
  } else {
    [self.logger logFormat:@"%@ appeared for the first time", device];
  }
  self.attachedDevices[key] = device;
  [self.referencedDevices setObject:device forKey:key];
}

- (void)deviceDetachedForKey:(NSString *)key
{
  // Remove only from the list of attached devices.
  // If the device instance is not referenced elsewhere it will be removed from the referencedDevices dictionary.
  // This is because the values in that dictionary are weakly referenced.
  [self.attachedDevices removeObjectForKey:key];
}

- (nullable id)deviceForKey:(NSString *)key
{
  return self.attachedDevices[key] ?: [self.referencedDevices objectForKey:key];
}

#pragma mark Public

- (NSDictionary<NSString *, id> *)attached
{
  return [self.attachedDevices copy];
}

- (NSDictionary<NSString *, id> *)referenced
{
  return self.referencedDevices.dictionaryRepresentation;
}

@end
