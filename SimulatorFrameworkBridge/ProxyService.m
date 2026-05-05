/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "ProxyService.h"

#import <dlfcn.h>

#import <CoreFoundation/CoreFoundation.h>

// SCDynamicStore function types — loaded at runtime via dlsym
// because the headers mark these API_UNAVAILABLE(ios), but the
// functions exist in the simulator runtime.
typedef void *SCDynStoreRef;
typedef SCDynStoreRef (*SCDynamicStoreCreate_fn)(CFAllocatorRef, CFStringRef, void *, void *);
typedef Boolean (*SCDynamicStoreSetValue_fn)(SCDynStoreRef, CFStringRef, CFPropertyListRef);
typedef CFPropertyListRef (*SCDynamicStoreCopyValue_fn)(SCDynStoreRef, CFStringRef);
typedef CFStringRef (*SCDynamicStoreKeyCreateProxies_fn)(CFAllocatorRef);
typedef Boolean (*SCDynamicStoreNotifyValue_fn)(SCDynStoreRef, CFStringRef);

static void *loadSystemConfiguration(void)
{
  void *sc = dlopen("/System/Library/Frameworks/SystemConfiguration.framework/SystemConfiguration", RTLD_LAZY);
  if (!sc) {
    NSLog(@"[ProxyService] Failed to load SystemConfiguration.framework: %s", dlerror());
  }
  return sc;
}

static CFMutableDictionaryRef buildHTTPProxyDict(NSString *host, int port)
{
  CFMutableDictionaryRef dict = CFDictionaryCreateMutable(
    kCFAllocatorDefault,
    0,
    &kCFTypeDictionaryKeyCallBacks,
    &kCFTypeDictionaryValueCallBacks
  );

  CFStringRef h = (__bridge CFStringRef)host;
  CFNumberRef p = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &port);
  int one = 1;
  CFNumberRef enabled = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &one);

  CFDictionarySetValue(dict, CFSTR("HTTPEnable"), enabled);
  CFDictionarySetValue(dict, CFSTR("HTTPProxy"), h);
  CFDictionarySetValue(dict, CFSTR("HTTPPort"), p);
  CFDictionarySetValue(dict, CFSTR("HTTPSEnable"), enabled);
  CFDictionarySetValue(dict, CFSTR("HTTPSProxy"), h);
  CFDictionarySetValue(dict, CFSTR("HTTPSPort"), p);
  CFDictionarySetValue(dict, CFSTR("FTPPassive"), enabled);

  CFStringRef exceptions[] = {CFSTR("*.local"), CFSTR("169.254/16")};
  CFArrayRef excList = CFArrayCreate(kCFAllocatorDefault, (const void **)exceptions, 2, &kCFTypeArrayCallBacks);
  CFDictionarySetValue(dict, CFSTR("ExceptionsList"), excList);

  CFRelease(p);
  CFRelease(enabled);
  CFRelease(excList);
  return dict;
}

static CFMutableDictionaryRef buildSOCKSProxyDict(NSString *host, int port)
{
  CFMutableDictionaryRef dict = CFDictionaryCreateMutable(
    kCFAllocatorDefault,
    0,
    &kCFTypeDictionaryKeyCallBacks,
    &kCFTypeDictionaryValueCallBacks
  );

  CFStringRef h = (__bridge CFStringRef)host;
  CFNumberRef p = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &port);
  int one = 1;
  CFNumberRef enabled = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &one);

  CFDictionarySetValue(dict, CFSTR("SOCKSEnable"), enabled);
  CFDictionarySetValue(dict, CFSTR("SOCKSProxy"), h);
  CFDictionarySetValue(dict, CFSTR("SOCKSPort"), p);
  CFDictionarySetValue(dict, CFSTR("FTPPassive"), enabled);

  CFStringRef exceptions[] = {CFSTR("*.local"), CFSTR("169.254/16")};
  CFArrayRef excList = CFArrayCreate(kCFAllocatorDefault, (const void **)exceptions, 2, &kCFTypeArrayCallBacks);
  CFDictionarySetValue(dict, CFSTR("ExceptionsList"), excList);

  CFRelease(p);
  CFRelease(enabled);
  CFRelease(excList);
  return dict;
}

static CFMutableDictionaryRef buildEmptyProxyDict(void)
{
  CFMutableDictionaryRef dict = CFDictionaryCreateMutable(
    kCFAllocatorDefault,
    0,
    &kCFTypeDictionaryKeyCallBacks,
    &kCFTypeDictionaryValueCallBacks
  );
  int one = 1;
  CFNumberRef enabled = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &one);
  CFDictionarySetValue(dict, CFSTR("FTPPassive"), enabled);
  CFRelease(enabled);
  return dict;
}

int handleProxyAction(NSString *action, NSArray<NSString *> *arguments)
{
  void *sc = loadSystemConfiguration();
  if (!sc) {
    return 1;
  }

  SCDynamicStoreCreate_fn fn_create = dlsym(sc, "SCDynamicStoreCreate");
  SCDynamicStoreSetValue_fn fn_set = dlsym(sc, "SCDynamicStoreSetValue");
  SCDynamicStoreKeyCreateProxies_fn fn_key = dlsym(sc, "SCDynamicStoreKeyCreateProxies");
  SCDynamicStoreNotifyValue_fn fn_notify = dlsym(sc, "SCDynamicStoreNotifyValue");

  if (!fn_create || !fn_set || !fn_key) {
    NSLog(@"[ProxyService] Required SCDynamicStore symbols not found");
    return 1;
  }

  SCDynStoreRef store = fn_create(NULL, CFSTR("SimulatorFrameworkBridge.proxy"), NULL, NULL);
  if (!store) {
    NSLog(@"[ProxyService] SCDynamicStoreCreate failed");
    return 1;
  }

  CFStringRef key = fn_key(NULL);

  CFDictionaryRef proxyDict = NULL;
  if ([action isEqualToString:@"set"]) {
    if (arguments.count < 2) {
      NSLog(@"[ProxyService] set requires <host> <port> [http|socks]");
      CFRelease(key);
      return 1;
    }
    NSString *host = arguments[0];
    int port = [arguments[1] intValue];
    NSString *type = arguments.count >= 3 ? arguments[2] : @"http";

    if ([type isEqualToString:@"socks"]) {
      proxyDict = buildSOCKSProxyDict(host, port);
    } else {
      proxyDict = buildHTTPProxyDict(host, port);
    }
    NSLog(@"[ProxyService] Setting %@ proxy to %@:%d", type, host, port);
  } else if ([action isEqualToString:@"clear"]) {
    proxyDict = buildEmptyProxyDict();
    NSLog(@"[ProxyService] Clearing proxy settings");
  } else {
    NSLog(@"[ProxyService] Unknown action: %@. Use 'set' or 'clear'.", action);
    CFRelease(key);
    return 1;
  }

  Boolean success = fn_set(store, key, proxyDict);
  CFRelease(proxyDict);

  if (!success) {
    NSLog(@"[ProxyService] SCDynamicStoreSetValue failed");
    CFRelease(key);
    return 1;
  }

  if (fn_notify) {
    fn_notify(store, key);
  }

  NSLog(@"[ProxyService] Proxy settings updated successfully");
  CFRelease(key);
  return 0;
}
