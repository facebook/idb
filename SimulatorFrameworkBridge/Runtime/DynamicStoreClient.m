/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "DynamicStoreClient.h"

#import <dlfcn.h>

#import "Private/SystemConfigurationPrivate.h"
#import "SystemConfigurationLoader.h"

@implementation FBDynamicStoreSnapshot
- (instancetype)initWithValue:(id)value
{
  self = [super init];
  if (self) {
    _value = value;
  }
  return self;
}

@end

@implementation FBDynamicStoreClient
{
  void *_library;
  SCDynStoreRef _store;
  NSString *_key;
  SCDynamicStoreCopyValue_fn _copyValue;
  SCError_fn _lastError;
}

+ (instancetype)openKey:(NSString *)key
{
  return [[self alloc] initWithKey:key];
}

- (instancetype)initWithKey:(NSString *)key
{
  self = [super init];
  if (!self) {
    return nil;
  }
  _key = [key copy];
  _library = FBSystemConfigurationLoad();
  if (!_library) {
    NSLog(@"[DynamicStoreService] Failed to load SystemConfiguration.framework: %s", dlerror());
    return nil;
  }
  SCDynamicStoreCreate_fn create = FBSystemConfigurationLookup(_library, "SCDynamicStoreCreate");
  if (!create) {
    NSLog(@"[DynamicStoreService] SCDynamicStoreCreate not found");
    return nil;
  }
  _store = create(NULL, CFSTR("SimulatorFrameworkBridge.dynamic-store"), NULL, NULL);
  if (!_store) {
    NSLog(@"[DynamicStoreService] SCDynamicStoreCreate failed");
    return nil;
  }
  _copyValue = FBSystemConfigurationLookup(_library, "SCDynamicStoreCopyValue");
  _lastError = FBSystemConfigurationLookup(_library, "SCError");
  if (!_copyValue || !_lastError) {
    NSLog(@"[DynamicStoreService] Required SCDynamicStore symbols not found");
    return nil;
  }
  return self;
}

- (void)dealloc
{
  if (_store) {
    CFRelease(_store);
  }
}

- (FBDynamicStoreSnapshot *)read
{
  id value = CFBridgingRelease(_copyValue(_store, (__bridge CFStringRef)_key));
  // kSCStatusNoKey distinguishes absence from a failed copy, both of which return NULL.
  if (!value && _lastError() != 1004) {
    return nil;
  }
  return [[FBDynamicStoreSnapshot alloc] initWithValue:value];
}

- (BOOL)writeValue:(id)value
{
  SCDynamicStoreSetValue_fn set = FBSystemConfigurationLookup(_library, "SCDynamicStoreSetValue");
  if (!set) {
    NSLog(@"[DynamicStoreService] SCDynamicStoreSetValue not found");
    return NO;
  }
  if (!set(_store, (__bridge CFStringRef)_key, (__bridge CFPropertyListRef)value)) {
    NSLog(@"[DynamicStoreService] SCDynamicStoreSetValue failed");
    return NO;
  }
  return YES;
}

- (BOOL)removeValue
{
  SCDynamicStoreRemoveValue_fn remove = FBSystemConfigurationLookup(_library, "SCDynamicStoreRemoveValue");
  if (!remove) {
    NSLog(@"[DynamicStoreService] SCDynamicStoreRemoveValue not found");
    return NO;
  }
  if (!remove(_store, (__bridge CFStringRef)_key)) {
    NSLog(@"[DynamicStoreService] SCDynamicStoreRemoveValue failed");
    return NO;
  }
  return YES;
}

- (void)notifyChange
{
  SCDynamicStoreNotifyValue_fn notify = FBSystemConfigurationLookup(_library, "SCDynamicStoreNotifyValue");
  if (notify) {
    notify(_store, (__bridge CFStringRef)_key);
  }
}

@end
