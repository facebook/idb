/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "NetworkConfigurationStore.h"

#import <dlfcn.h>

#import "SystemConfigurationLoader.h"
#import "SystemConfigurationPrivate.h"

@implementation FBNetworkConfigurationRead
- (instancetype)initWithConfiguration:(NSDictionary<NSString *, id> *)configuration
{
  self = [super init];
  if (self) {
    _configuration = configuration;
  }
  return self;
}

@end

@implementation FBNetworkConfigurationStore
{
  void *_library;
  SCDynStoreRef _store;
  CFStringRef _key;
  NSString *_service;
  SCDynamicStoreSetValue_fn _setValue;
  SCDynamicStoreNotifyValue_fn _notifyValue;
}

+ (instancetype)dnsStore
{
  return [[self alloc] initWithProxy:NO];
}

+ (instancetype)proxyStore
{
  return [[self alloc] initWithProxy:YES];
}

- (instancetype)initWithProxy:(BOOL)proxy
{
  self = [super init];
  if (!self) {
    return nil;
  }
  _service = proxy ? @"ProxyService" : @"DnsService";
  _library = FBSystemConfigurationLoad();
  if (!_library) {
    NSLog(@"[%@] Failed to load SystemConfiguration.framework: %s", _service, dlerror());
    return nil;
  }
  SCDynamicStoreCreate_fn create = FBSystemConfigurationLookup(_library, "SCDynamicStoreCreate");
  SCDynamicStoreKeyCreateProxies_fn key = proxy ? FBSystemConfigurationLookup(_library, "SCDynamicStoreKeyCreateProxies") : NULL;
  if (!create || (proxy && !key)) {
    NSLog(@"[%@] Required SCDynamicStore symbols not found", _service);
    return nil;
  }
  _store = create(NULL, proxy ? CFSTR("SimulatorFrameworkBridge.proxy") : CFSTR("SimulatorFrameworkBridge.dns"), NULL, NULL);
  if (!_store) {
    NSLog(@"[%@] SCDynamicStoreCreate failed", _service);
    return nil;
  }
  _key = proxy ? key(NULL) : CFRetain(CFSTR("State:/Network/Global/DNS"));
  return self;
}

- (void)dealloc
{
  if (_key) {
    CFRelease(_key);
  }
  if (_store) {
    CFRelease(_store);
  }
}

- (FBNetworkConfigurationRead *)readConfiguration
{
  SCDynamicStoreCopyValue_fn copyValue = FBSystemConfigurationLookup(_library, "SCDynamicStoreCopyValue");
  if (!copyValue) {
    NSLog(@"[%@] SCDynamicStoreCopyValue not found", _service);
    return nil;
  }
  NSDictionary *configuration = CFBridgingRelease(copyValue(_store, _key));
  return [[FBNetworkConfigurationRead alloc] initWithConfiguration:configuration];
}

- (BOOL)prepareToWrite
{
  _setValue = FBSystemConfigurationLookup(_library, "SCDynamicStoreSetValue");
  _notifyValue = FBSystemConfigurationLookup(_library, "SCDynamicStoreNotifyValue");
  if (!_setValue) {
    NSLog(@"[%@] SCDynamicStoreSetValue not found", _service);
    return NO;
  }
  return YES;
}

- (BOOL)writeConfiguration:(NSDictionary<NSString *, id> *)configuration
{
  if (!_setValue || !_setValue(_store, _key, (__bridge CFDictionaryRef)configuration)) {
    NSLog(@"[%@] SCDynamicStoreSetValue failed", _service);
    return NO;
  }
  return YES;
}

- (void)notifyChange
{
  if (_notifyValue) {
    _notifyValue(_store, _key);
  }
}

@end
