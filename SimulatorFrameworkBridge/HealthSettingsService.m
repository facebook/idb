/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "HealthSettingsService.h"

#import "HealthKitPrivate.h"

#import <dlfcn.h>

#pragma mark - Framework loader

static id loadHealthStore(void) {
  if (!dlopen("/System/Library/Frameworks/HealthKit.framework/HealthKit", RTLD_NOW)) {
    NSLog(@"[Health] Failed to load HealthKit.framework: %s", dlerror());
    return nil;
  }
  Class HKHealthStoreClass = NSClassFromString(@"HKHealthStore");
  if (!HKHealthStoreClass) {
    NSLog(@"[Health] HKHealthStore class not found");
    return nil;
  }
  return [[HKHealthStoreClass alloc] init];
}

static HKAuthorizationStore *loadAuthStore(void) {
  id store = loadHealthStore();
  if (!store) {
    return nil;
  }
  Class HKAuthStoreClass = NSClassFromString(@"HKAuthorizationStore");
  if (!HKAuthStoreClass) {
    NSLog(@"[Health] HKAuthorizationStore class not found");
    return nil;
  }
  return [[HKAuthStoreClass alloc] initWithHealthStore:store];
}

#pragma mark - JSON output helpers

static NSString *jsonStringFromObject(id obj) {
  NSError *err = nil;
  NSData *data = [NSJSONSerialization dataWithJSONObject:obj options:0 error:&err];
  if (!data) {
    return [NSString stringWithFormat:@"\"<json-error: %@>\"", err.localizedDescription];
  }
  return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

static NSDictionary *recordToDictionary(id record) {
  // Records are opaque private ObjC objects. Probe likely identifying
  // KVC keys (object type, sharing/read status). Keys that aren't
  // present on the record return nil and are skipped.
  static NSArray<NSString *> *probeKeys;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    probeKeys = @[
      @"objectType",
      @"sharingAuthorizationStatus",
      @"readAuthorizationStatus",
      @"sharingRequestStatus",
      @"readRequestStatus",
      @"requestStatus",
      @"authorizationStatus",
      @"bundleIdentifier",
    ];
  });

  NSMutableDictionary *out = [NSMutableDictionary dictionary];
  for (NSString *key in probeKeys) {
    @try {
      id value = [record valueForKey:key];
      if (!value) {
        continue;
      }
      if ([value isKindOfClass:NSString.class] || [value isKindOfClass:NSNumber.class]) {
        out[key] = value;
      } else {
        out[key] = [NSString stringWithFormat:@"%@", value];
      }
    } @catch (NSException *exception) {
      // KVC missing key — record doesn't expose this property; skip.
    }
  }
  return out;
}

#pragma mark - Verb implementations

static int handleClearAction(HKAuthorizationStore *authStore, NSString *bundleID) {
  __block BOOL clearOK = NO;
  __block NSError *clearError = nil;
  dispatch_semaphore_t sem = dispatch_semaphore_create(0);
  [authStore resetAuthorizationStatusForBundleIdentifier:bundleID
                                              completion:^(BOOL ok, NSError *_Nullable e) {
    clearOK = ok;
    clearError = e;
    dispatch_semaphore_signal(sem);
  }];
  dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));

  NSDictionary *output = @{
    @"action": @"clear",
    @"bundleID": bundleID,
    @"ok": @(clearOK),
    @"error": clearError.localizedDescription ?: [NSNull null],
  };
  printf("%s\n", jsonStringFromObject(output).UTF8String);
  return clearOK ? 0 : 1;
}

static int handleListAction(HKAuthorizationStore *authStore, NSString *bundleID) {
  __block NSArray *records = nil;
  __block NSError *fetchError = nil;
  dispatch_semaphore_t sem = dispatch_semaphore_create(0);
  [authStore fetchAuthorizationRecordsForBundleIdentifier:bundleID
                                               completion:^(NSArray *_Nullable r, NSError *_Nullable e) {
    records = r;
    fetchError = e;
    dispatch_semaphore_signal(sem);
  }];
  dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));

  NSMutableArray *recordDicts = [NSMutableArray array];
  for (id record in records) {
    [recordDicts addObject:recordToDictionary(record)];
  }
  NSDictionary *output = @{
    @"action": @"list",
    @"bundleID": bundleID,
    @"ok": @(fetchError == nil),
    @"error": fetchError.localizedDescription ?: [NSNull null],
    @"records": recordDicts,
  };
  printf("%s\n", jsonStringFromObject(output).UTF8String);
  return fetchError == nil ? 0 : 1;
}

#pragma mark - Dispatch

int handleHealthSettingsAction(NSString *action, NSString *bundleID, NSArray<NSString *> *typeIdentifiers) {
  HKAuthorizationStore *authStore = loadAuthStore();
  if (!authStore) {
    return 1;
  }
  if (!bundleID) {
    NSLog(@"[Health] bundleID is required for action '%@'", action);
    return 1;
  }
  if ([action isEqualToString:@"list"]) {
    return handleListAction(authStore, bundleID);
  }
  if ([action isEqualToString:@"clear"]) {
    return handleClearAction(authStore, bundleID);
  }
  NSLog(@"[Health] Unknown action '%@'. Supported: list, clear", action);
  return 1;
}
