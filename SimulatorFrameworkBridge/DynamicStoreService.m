/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "DynamicStoreService.h"

#import <dlfcn.h>

#import "SystemConfigurationLoader.h"
#import "SystemConfigurationPrivate.h"

// kSCStatusNoKey. An absent key and a failed read both copy NULL, and this status is the only thing
// that tells them apart.
static const int NoKeyStatus = 1004;

NSString *dynamicStoreKeyForName(NSString *name)
{
  if ([name isEqualToString:@"dns"]) {
    return @"State:/Network/Global/DNS";
  }
  if ([name isEqualToString:@"proxy"]) {
    return @"State:/Network/Global/Proxies";
  }
  // Every configd key is a domain followed by a path. A name without one is not a key, and this
  // service has no alias for it.
  return [name containsString:@":"] ? name : nil;
}

static BOOL readValue(SCDynStoreRef store, SCDynamicStoreCopyValue_fn copy, SCError_fn lastError, CFStringRef key, id *value)
{
  *value = CFBridgingRelease(copy(store, key));
  return *value != nil || lastError() == NoKeyStatus;
}

static int writeSnapshot(id value)
{
  NSDictionary<NSString *, id> *snapshot = value ? @{@"present" : @YES, @"value" : value} : @{@"present" : @NO};
  NSError *error = nil;
  NSData *data = [NSPropertyListSerialization dataWithPropertyList:snapshot format:NSPropertyListBinaryFormat_v1_0 options:0 error:&error];
  if (!data) {
    NSLog(@"[DynamicStoreService] Cannot serialise the snapshot: %@", error);
    return 1;
  }
  [[NSFileHandle fileHandleWithStandardOutput] writeData:data];
  return 0;
}

static NSDictionary<NSString *, id> *readRequestedSnapshot(void)
{
  NSData *data = [[NSFileHandle fileHandleWithStandardInput] readDataToEndOfFile];
  NSError *error = nil;
  id snapshot = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:&error];
  if (![snapshot isKindOfClass:NSDictionary.class] || ![snapshot[@"present"] isKindOfClass:NSNumber.class]) {
    NSLog(@"[DynamicStoreService] Cannot read the snapshot to restore: %@", error ?: snapshot);
    return nil;
  }
  if ([snapshot[@"present"] boolValue] && snapshot[@"value"] == nil) {
    NSLog(@"[DynamicStoreService] The snapshot to restore is present but carries no value");
    return nil;
  }
  return snapshot;
}

static int restoreValue(void *sc, SCDynStoreRef store, SCDynamicStoreCopyValue_fn copy, SCError_fn lastError, CFStringRef key, id current)
{
  NSDictionary<NSString *, id> *snapshot = readRequestedSnapshot();
  if (!snapshot) {
    return 1;
  }

  if ([snapshot[@"present"] boolValue]) {
    SCDynamicStoreSetValue_fn set = FBSystemConfigurationLookup(sc, "SCDynamicStoreSetValue");
    if (!set) {
      NSLog(@"[DynamicStoreService] SCDynamicStoreSetValue not found");
      return 1;
    }
    if (!set(store, key, (__bridge CFPropertyListRef)snapshot[@"value"])) {
      NSLog(@"[DynamicStoreService] SCDynamicStoreSetValue failed");
      return 1;
    }
  } else if (current != nil) {
    SCDynamicStoreRemoveValue_fn remove = FBSystemConfigurationLookup(sc, "SCDynamicStoreRemoveValue");
    if (!remove) {
      NSLog(@"[DynamicStoreService] SCDynamicStoreRemoveValue not found");
      return 1;
    }
    if (!remove(store, key)) {
      NSLog(@"[DynamicStoreService] SCDynamicStoreRemoveValue failed");
      return 1;
    }
  }

  SCDynamicStoreNotifyValue_fn notify = FBSystemConfigurationLookup(sc, "SCDynamicStoreNotifyValue");
  if (notify) {
    notify(store, key);
  }

  id restored = nil;
  if (!readValue(store, copy, lastError, key, &restored)) {
    NSLog(@"[DynamicStoreService] Cannot read back the restored value");
    return 1;
  }
  return writeSnapshot(restored);
}

static int runDynamicStore(void *sc, SCDynStoreRef store, CFStringRef key, BOOL restore)
{
  SCDynamicStoreCopyValue_fn copy = FBSystemConfigurationLookup(sc, "SCDynamicStoreCopyValue");
  SCError_fn lastError = FBSystemConfigurationLookup(sc, "SCError");
  if (!copy || !lastError) {
    NSLog(@"[DynamicStoreService] Required SCDynamicStore symbols not found");
    return 1;
  }

  id current = nil;
  if (!readValue(store, copy, lastError, key, &current)) {
    NSLog(@"[DynamicStoreService] Cannot read the dynamic store key");
    return 1;
  }
  if (!restore) {
    return writeSnapshot(current);
  }
  return restoreValue(sc, store, copy, lastError, key, current);
}

int handleDynamicStoreAction(NSString *action, NSArray<NSString *> *arguments)
{
  BOOL restore = [action isEqualToString:@"restore"];
  if (!restore && ![action isEqualToString:@"snapshot"]) {
    NSLog(@"[DynamicStoreService] Unknown action: %@. Use 'snapshot' or 'restore'.", action);
    return 1;
  }

  NSString *name = arguments.firstObject;
  if (name.length == 0) {
    NSLog(@"[DynamicStoreService] %@ requires a configd key, or one of 'dns' and 'proxy'", action);
    return 1;
  }
  NSString *key = dynamicStoreKeyForName(name);
  if (!key) {
    NSLog(@"[DynamicStoreService] %@ is neither a configd key nor a known alias", name);
    return 1;
  }

  void *sc = FBSystemConfigurationLoad();
  if (!sc) {
    NSLog(@"[DynamicStoreService] Failed to load SystemConfiguration.framework: %s", dlerror());
    return 1;
  }
  SCDynamicStoreCreate_fn create = FBSystemConfigurationLookup(sc, "SCDynamicStoreCreate");
  if (!create) {
    NSLog(@"[DynamicStoreService] SCDynamicStoreCreate not found");
    return 1;
  }
  SCDynStoreRef store = create(NULL, CFSTR("SimulatorFrameworkBridge.dynamic-store"), NULL, NULL);
  if (!store) {
    NSLog(@"[DynamicStoreService] SCDynamicStoreCreate failed");
    return 1;
  }

  int status = runDynamicStore(sc, store, (__bridge CFStringRef)key, restore);
  CFRelease(store);
  return status;
}
