/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "HealthSettingsService.h"

#import "HealthKitPrivate.h"

#import <dlfcn.h>

// HKInternalAuthorizationStatus values used on the wire to healthd.
// Reverse-engineered from `_HKInternalAuthorizationStatusMake` and the
// daemon validator at `+[HDAuthorizationEntity _insertAuthorizationWith…]`.
// These are NOT the public HKAuthorizationStatus enum (0..4).
static const NSUInteger kHealthInternalAuthShareAndRead = 101;
static const NSUInteger kHealthInternalAuthShareAndReadDenied = 104;

// The curated default set of HKQuantity types used by `approve` when
// the caller does not specify any. Kept small to match the most common
// HealthKit consumer use-cases in tests.
static NSArray<NSString *> *defaultApproveTypeIdentifiers(void) {
  static dispatch_once_t onceToken;
  static NSArray<NSString *> *defaults;
  dispatch_once(&onceToken, ^{
    defaults = @[
      @"HKQuantityTypeIdentifierStepCount",
      @"HKQuantityTypeIdentifierHeartRate",
      @"HKQuantityTypeIdentifierActiveEnergyBurned",
      @"HKQuantityTypeIdentifierDistanceWalkingRunning",
      @"HKQuantityTypeIdentifierBodyMass",
    ];
  });
  return defaults;
}

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
  // fetchAuthorizationRecordsForBundleIdentifier: returns HKObjectType
  // instances (HKQuantityType, HKCategoryType, etc.) — not dedicated
  // authorization-record objects. The authorization state is exposed as
  // properties on the type itself.
  //
  // Property names confirmed via runtime introspection on iOS 26.2.
  // The @try/@catch keeps this forward-compatible if a future runtime
  // drops or renames a property.
  static NSArray<NSString *> *probeKeys;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    probeKeys = @[
      @"identifier",
      @"sharingAuthorizationAllowed",
      @"readingAuthorizationAllowed",
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
      // Property not present on this runtime version; skip.
    }
  }
  return out;
}

#pragma mark - HKObjectType resolution

// Resolve an HKQuantityTypeIdentifier* / HKCategoryTypeIdentifier* /
// HKCharacteristicTypeIdentifier* / HKCorrelationTypeIdentifier* /
// HKDocumentTypeIdentifier* string into the matching HKObjectType
// via the runtime. Returns nil for identifiers that aren't known to
// the iOS runtime version on this simulator (rare, but logged).
static id resolveHealthKitObjectType(NSString *identifier) {
  static NSArray<NSString *> *factoryClasses;
  static NSArray<NSString *> *factorySelectors;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    factoryClasses = @[
      @"HKQuantityType",
      @"HKCategoryType",
      @"HKCharacteristicType",
      @"HKCorrelationType",
      @"HKDocumentType",
    ];
    factorySelectors = @[
      @"quantityTypeForIdentifier:",
      @"categoryTypeForIdentifier:",
      @"characteristicTypeForIdentifier:",
      @"correlationTypeForIdentifier:",
      @"documentTypeForIdentifier:",
    ];
  });

  for (NSUInteger i = 0; i < factoryClasses.count; i++) {
    Class cls = NSClassFromString(factoryClasses[i]);
    SEL sel = NSSelectorFromString(factorySelectors[i]);
    if (!cls || ![cls respondsToSelector:sel]) {
      continue;
    }
    NSMethodSignature *sig = [cls methodSignatureForSelector:sel];
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    inv.target = cls;
    inv.selector = sel;
    [inv setArgument:&identifier atIndex:2];
    [inv invoke];
    __unsafe_unretained id type = nil;
    [inv getReturnValue:&type];
    if (type) {
      return type;
    }
  }
  return nil;
}

#pragma mark - Verb implementations

static int handleSetAction(HKAuthorizationStore *authStore,
                           NSString *bundleID,
                           NSArray<NSString *> *typeIdentifiers,
                           NSUInteger statusCode,
                           NSString *actionName) {
  NSArray<NSString *> *requested = typeIdentifiers.count > 0
    ? typeIdentifiers
    : defaultApproveTypeIdentifiers();

  NSMutableSet *resolvedTypes = [NSMutableSet set];
  NSMutableArray<NSString *> *resolvedIdentifiers = [NSMutableArray array];
  NSMutableArray<NSString *> *unresolvedIdentifiers = [NSMutableArray array];
  for (NSString *identifier in requested) {
    id type = resolveHealthKitObjectType(identifier);
    if (type) {
      [resolvedTypes addObject:type];
      [resolvedIdentifiers addObject:identifier];
    } else {
      NSLog(@"[Health] Skipping unresolved HK type identifier: %@", identifier);
      [unresolvedIdentifiers addObject:identifier];
    }
  }
  if (resolvedTypes.count == 0) {
    NSDictionary *output = @{
      @"action": actionName,
      @"bundleID": bundleID,
      @"ok": @NO,
      @"error": @"no resolvable HK types in request",
      @"unresolvedTypes": unresolvedIdentifiers,
    };
    printf("%s\n", jsonStringFromObject(output).UTF8String);
    return 1;
  }

  // Step 1: seed the authorisation request rows. Without this, the
  // daemon silently drops status writes for unseen (bundleID, type) pairs.
  __block BOOL seedOK = NO;
  __block NSError *seedError = nil;
  dispatch_semaphore_t seedSem = dispatch_semaphore_create(0);
  [authStore setRequestedAuthorizationForBundleIdentifier:bundleID
                                                shareTypes:resolvedTypes
                                                 readTypes:resolvedTypes
                                                completion:^(BOOL ok, NSError *_Nullable err) {
    seedOK = ok;
    seedError = err;
    dispatch_semaphore_signal(seedSem);
  }];
  dispatch_semaphore_wait(seedSem, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));

  // Step 2: write the requested status for every resolved type.
  NSMutableDictionary *statuses = [NSMutableDictionary dictionary];
  for (id type in resolvedTypes) {
    statuses[type] = @(statusCode);
  }
  __block BOOL setOK = NO;
  __block NSError *setError = nil;
  dispatch_semaphore_t setSem = dispatch_semaphore_create(0);
  [authStore setAuthorizationStatuses:statuses
                   authorizationModes:@{}
                  forBundleIdentifier:bundleID
                              options:nil
                           completion:^(BOOL ok, NSError *_Nullable err) {
    setOK = ok;
    setError = err;
    dispatch_semaphore_signal(setSem);
  }];
  dispatch_semaphore_wait(setSem, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));

  NSDictionary *output = @{
    @"action": actionName,
    @"bundleID": bundleID,
    @"ok": @(seedOK && setOK),
    @"resolvedTypes": resolvedIdentifiers,
    @"unresolvedTypes": unresolvedIdentifiers,
    @"seedError": seedError.localizedDescription ?: [NSNull null],
    @"setError": setError.localizedDescription ?: [NSNull null],
  };
  printf("%s\n", jsonStringFromObject(output).UTF8String);
  return (seedOK && setOK) ? 0 : 1;
}

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
  if ([action isEqualToString:@"approve"]) {
    return handleSetAction(authStore, bundleID, typeIdentifiers,
                           kHealthInternalAuthShareAndRead, @"approve");
  }
  if ([action isEqualToString:@"revoke"]) {
    return handleSetAction(authStore, bundleID, typeIdentifiers,
                           kHealthInternalAuthShareAndReadDenied, @"revoke");
  }
  NSLog(@"[Health] Unknown action '%@'. Supported: list, clear, approve, revoke", action);
  return 1;
}
