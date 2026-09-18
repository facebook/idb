/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "ProxyService.h"

#if __has_include(<SimulatorFrameworkBridgeRuntime/NetworkConfigurationStore.h>)
 #import <SimulatorFrameworkBridgeRuntime/NetworkConfigurationStore.h>
#else
 #import "Runtime/NetworkConfigurationStore.h"
#endif

NSDictionary<NSString *, id> *buildHTTPProxyDict(NSString *host, int port)
{
  return @{
    @"HTTPEnable" : @1,
    @"HTTPProxy" : host,
    @"HTTPPort" : @(port),
    @"HTTPSEnable" : @1,
    @"HTTPSProxy" : host,
    @"HTTPSPort" : @(port),
    @"FTPPassive" : @1,
    @"ExceptionsList" : @[@"*.local", @"169.254/16"],
  };
}

NSDictionary<NSString *, id> *buildSOCKSProxyDict(NSString *host, int port)
{
  return @{
    @"SOCKSEnable" : @1,
    @"SOCKSProxy" : host,
    @"SOCKSPort" : @(port),
    @"FTPPassive" : @1,
    @"ExceptionsList" : @[@"*.local", @"169.254/16"],
  };
}

NSDictionary<NSString *, id> *buildEmptyProxyDict(void)
{
  return @{
    @"FTPPassive" : @1,
  };
}

int handleProxyAction(NSString *action, NSArray<NSString *> *arguments)
{
  FBNetworkConfigurationStore *store = [FBNetworkConfigurationStore proxyStore];
  if (!store) {
    return 1;
  }

  if ([action isEqualToString:@"list"]) {
    FBNetworkConfigurationRead *read = [store readConfiguration];
    if (!read) {
      return 1;
    }
    if (read.configuration) {
      NSDictionary *dict = read.configuration;
      NSData *json = [NSJSONSerialization dataWithJSONObject:dict options:NSJSONWritingPrettyPrinted error:nil];
      NSString *str = json ? [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] : nil;
      if (str) {
        printf("%s\n", str.UTF8String);
      }
    } else {
      printf("{}\n");
    }
    return 0;
  }

  if (![store prepareToWrite]) {
    return 1;
  }

  NSDictionary<NSString *, id> *proxyDict = nil;
  if ([action isEqualToString:@"set"]) {
    if (arguments.count < 2) {
      NSLog(@"[ProxyService] set requires <host> <port> [http|socks]");
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
    NSLog(@"[ProxyService] Unknown action: %@. Use 'set', 'clear', or 'list'.", action);
    return 1;
  }

  BOOL success = [store writeConfiguration:proxyDict];

  if (!success) {
    return 1;
  }

  [store notifyChange];

  NSLog(@"[ProxyService] Proxy settings updated successfully");
  return 0;
}
