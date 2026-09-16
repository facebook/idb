/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <dlfcn.h>

#import <Foundation/Foundation.h>

#import "SystemConfigurationProbePrivate.h"

static void require(BOOL success, id detail)
{
  if (!success) {
    [NSException raise:@"ServiceProbeFailure" format:@"%@", detail];
  }
}

static NSDictionary *networkState(NSString *service, BOOL restore)
{
  void *framework = dlopen("/System/Library/Frameworks/SystemConfiguration.framework/SystemConfiguration", RTLD_NOW);
  require(framework != NULL, @"SystemConfiguration unavailable");
  ProbeStoreCreate create = dlsym(framework, "SCDynamicStoreCreate");
  ProbeStoreCopy copy = dlsym(framework, "SCDynamicStoreCopyValue");
  ProbeStoreSet set = dlsym(framework, "SCDynamicStoreSetValue");
  ProbeStoreRemove remove = dlsym(framework, "SCDynamicStoreRemoveValue");
  ProbeStoreNotify notify = dlsym(framework, "SCDynamicStoreNotifyValue");
  ProbeSCError lastError = dlsym(framework, "SCError");
  require(create && copy && set && remove && lastError, @"Missing dynamic store symbols");
  CFTypeRef store = create(NULL, CFSTR("idb.EndToEndServiceProbe"), NULL, NULL);
  require(store != NULL, @"Cannot open dynamic store");
  @try {
    CFStringRef key = [service isEqualToString:@"dns"] ? CFSTR("State:/Network/Global/DNS") : CFSTR("State:/Network/Global/Proxies");
    id current = CFBridgingRelease(copy(store, key));
    require(current != nil || lastError() == 1004, @"Cannot read dynamic store key"); // kSCStatusNoKey
    if (restore) {
      NSError *error = nil;
      NSData *data = [[NSFileHandle fileHandleWithStandardInput] readDataToEndOfFile];
      NSDictionary *snapshot = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:&error];
      require([snapshot isKindOfClass:NSDictionary.class] && [snapshot[@"present"] isKindOfClass:NSNumber.class], error ?: @"Invalid snapshot");
      if ([snapshot[@"present"] boolValue]) {
        require(snapshot[@"value"] != nil, @"Snapshot has no value");
        require(set(store, key, (__bridge CFPropertyListRef)snapshot[@"value"]), @"Cannot restore dynamic store value");
      } else if (current != nil) {
        require(remove(store, key), @"Cannot restore absent dynamic store key");
      }
      if (notify) {
        require(notify(store, key), @"Cannot notify restored dynamic store value");
      }
      current = CFBridgingRelease(copy(store, key));
      require(current != nil || lastError() == 1004, @"Cannot verify dynamic store restoration");
    }
    return current ? @{@"present" : @YES, @"value" : current} : @{@"present" : @NO};
  } @finally {
    CFRelease(store);
    dlclose(framework);
  }
}

int main(int argc, const char *argv[])
{
  @autoreleasepool {
    @try {
      require(argc >= 3, @"Expected service and action");
      NSArray<NSString *> *arguments = NSProcessInfo.processInfo.arguments;
      NSString *service = arguments[1];
      NSString *action = arguments[2];
      require([service isEqualToString:@"dns"] || [service isEqualToString:@"proxy"], @"Unknown network service");
      require([action isEqualToString:@"snapshot"] || [action isEqualToString:@"restore"], @"Unknown network probe action");
      NSDictionary *result = networkState(service, [action isEqualToString:@"restore"]);
      NSError *error = nil;
      NSData *data = [NSPropertyListSerialization dataWithPropertyList:result format:NSPropertyListBinaryFormat_v1_0 options:0 error:&error];
      require(data != nil, error);
      [[NSFileHandle fileHandleWithStandardOutput] writeData:data];
      return 0;
    } @catch (NSException *exception) {
      fprintf(stderr, "%s\n", exception.description.UTF8String);
      return 1;
    }
  }
}
