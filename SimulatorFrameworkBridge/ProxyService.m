/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "ProxyService.h"

#import "SystemConfigurationPrivate.h"

#import <dlfcn.h>

static void *loadSystemConfiguration(void) {
  void *sc = dlopen("/System/Library/Frameworks/SystemConfiguration.framework/SystemConfiguration", RTLD_LAZY);
  if (!sc) {
    NSLog(@"[ProxyService] Failed to load SystemConfiguration.framework: %s", dlerror());
  }
  return sc;
}

NSDictionary<NSString *, id> *buildHTTPProxyDict(NSString *host, int port) {
  return @{
    @"HTTPEnable": @1,
    @"HTTPProxy": host,
    @"HTTPPort": @(port),
    @"HTTPSEnable": @1,
    @"HTTPSProxy": host,
    @"HTTPSPort": @(port),
    @"FTPPassive": @1,
    @"ExceptionsList": @[@"*.local", @"169.254/16"],
  };
}

NSDictionary<NSString *, id> *buildSOCKSProxyDict(NSString *host, int port) {
  return @{
    @"SOCKSEnable": @1,
    @"SOCKSProxy": host,
    @"SOCKSPort": @(port),
    @"FTPPassive": @1,
    @"ExceptionsList": @[@"*.local", @"169.254/16"],
  };
}

NSDictionary<NSString *, id> *buildEmptyProxyDict(void) {
  return @{
    @"FTPPassive": @1,
  };
}

int handleProxyAction(NSString *action, NSArray<NSString *> *arguments) {
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

  NSDictionary<NSString *, id> *proxyDict = nil;
  if ([action isEqualToString:@"set"]) {
    if (arguments.count < 2) {
      NSLog(@"[ProxyService] set requires <host> <port> [http|socks]");
      CFRelease(key);
      CFRelease(store);
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
    CFRelease(store);
    return 1;
  }

  Boolean success = fn_set(store, key, (__bridge CFDictionaryRef)proxyDict);

  if (!success) {
    NSLog(@"[ProxyService] SCDynamicStoreSetValue failed");
    CFRelease(key);
    CFRelease(store);
    return 1;
  }

  if (fn_notify) {
    fn_notify(store, key);
  }

  NSLog(@"[ProxyService] Proxy settings updated successfully");
  CFRelease(key);
  CFRelease(store);
  return 0;
}
