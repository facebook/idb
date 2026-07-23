/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "DnsService.h"

#import <dlfcn.h>

#import "SystemConfigurationPrivate.h"

static void *loadSystemConfiguration(void)
{
  void *sc = dlopen("/System/Library/Frameworks/SystemConfiguration.framework/SystemConfiguration", RTLD_LAZY);
  if (!sc) {
    NSLog(@"[DnsService] Failed to load SystemConfiguration.framework: %s", dlerror());
  }
  return sc;
}

NSDictionary<NSString *, id> *buildDnsDict(NSArray<NSString *> *servers)
{
  return @{
    @"ServerAddresses" : servers,
  };
}

NSDictionary<NSString *, id> *buildEmptyDnsDict(void)
{
  return @{};
}

int handleDnsAction(NSString *action, NSArray<NSString *> *arguments)
{
  void *sc = loadSystemConfiguration();
  if (!sc) {
    return 1;
  }

  SCDynamicStoreCreate_fn fn_create = dlsym(sc, "SCDynamicStoreCreate");

  if (!fn_create) {
    NSLog(@"[DnsService] Required SCDynamicStore symbols not found");
    return 1;
  }

  SCDynStoreRef store = fn_create(NULL, CFSTR("SimulatorFrameworkBridge.dns"), NULL, NULL);
  if (!store) {
    NSLog(@"[DnsService] SCDynamicStoreCreate failed");
    return 1;
  }

  CFStringRef key = CFSTR("State:/Network/Global/DNS");

  if ([action isEqualToString:@"list"]) {
    SCDynamicStoreCopyValue_fn fn_copy = dlsym(sc, "SCDynamicStoreCopyValue");
    if (!fn_copy) {
      NSLog(@"[DnsService] SCDynamicStoreCopyValue not found");
      CFRelease(store);
      return 1;
    }
    CFPropertyListRef value = fn_copy(store, key);
    if (value) {
      NSDictionary *dict = (__bridge_transfer NSDictionary *)value;
      NSData *json = [NSJSONSerialization dataWithJSONObject:dict options:NSJSONWritingPrettyPrinted error:nil];
      NSString *str = json ? [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] : nil;
      if (str) {
        printf("%s\n", str.UTF8String);
      }
    } else {
      printf("{}\n");
    }
    CFRelease(store);
    return 0;
  }

  SCDynamicStoreSetValue_fn fn_set = dlsym(sc, "SCDynamicStoreSetValue");
  SCDynamicStoreNotifyValue_fn fn_notify = dlsym(sc, "SCDynamicStoreNotifyValue");

  if (!fn_set) {
    NSLog(@"[DnsService] SCDynamicStoreSetValue not found");
    CFRelease(store);
    return 1;
  }

  NSDictionary<NSString *, id> *dnsDict = nil;
  if ([action isEqualToString:@"set"]) {
    if (arguments.count < 1) {
      NSLog(@"[DnsService] set requires at least one DNS server address");
      CFRelease(store);
      return 1;
    }
    dnsDict = buildDnsDict(arguments);
    NSLog(@"[DnsService] Setting DNS servers to %@", [arguments componentsJoinedByString:@", "]);
  } else if ([action isEqualToString:@"clear"]) {
    dnsDict = buildEmptyDnsDict();
    NSLog(@"[DnsService] Clearing DNS configuration");
  } else {
    NSLog(@"[DnsService] Unknown action: %@. Use 'set', 'clear', or 'list'.", action);
    CFRelease(store);
    return 1;
  }

  Boolean success = fn_set(store, key, (__bridge CFDictionaryRef)dnsDict);

  if (!success) {
    NSLog(@"[DnsService] SCDynamicStoreSetValue failed");
    CFRelease(store);
    return 1;
  }

  if (fn_notify) {
    fn_notify(store, key);
  }

  NSLog(@"[DnsService] DNS configuration updated successfully");
  CFRelease(store);
  return 0;
}
