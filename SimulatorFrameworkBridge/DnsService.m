/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "DnsService.h"

#if __has_include(<SimulatorFrameworkBridgeRuntime/NetworkConfigurationStore.h>)
 #import <SimulatorFrameworkBridgeRuntime/NetworkConfigurationStore.h>
#else
 #import "Runtime/NetworkConfigurationStore.h"
#endif

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
  FBNetworkConfigurationStore *store = [FBNetworkConfigurationStore dnsStore];
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

  NSDictionary<NSString *, id> *dnsDict = nil;
  if ([action isEqualToString:@"set"]) {
    if (arguments.count < 1) {
      NSLog(@"[DnsService] set requires at least one DNS server address");
      return 1;
    }
    dnsDict = buildDnsDict(arguments);
    NSLog(@"[DnsService] Setting DNS servers to %@", [arguments componentsJoinedByString:@", "]);
  } else if ([action isEqualToString:@"clear"]) {
    dnsDict = buildEmptyDnsDict();
    NSLog(@"[DnsService] Clearing DNS configuration");
  } else {
    NSLog(@"[DnsService] Unknown action: %@. Use 'set', 'clear', or 'list'.", action);
    return 1;
  }

  BOOL success = [store writeConfiguration:dnsDict];

  if (!success) {
    return 1;
  }

  [store notifyChange];

  NSLog(@"[DnsService] DNS configuration updated successfully");
  return 0;
}
