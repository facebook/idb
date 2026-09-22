/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "HealthSettingsService.h"
#import "HealthSettingsService+Testing.h"

#if __has_include(<SimulatorFrameworkBridgeRuntime/HealthSettingsClient.h>)
 #import <SimulatorFrameworkBridgeRuntime/HealthSettingsClient.h>
#else
 #import "Runtime/HealthSettingsClient.h"
#endif

// HKInternalAuthorizationStatus values, as healthd expects them (from `_HKInternalAuthorizationStatusMake`
// and `+[HDAuthorizationEntity _insertAuthorizationWith…]`). NOT the public HKAuthorizationStatus 0..4.
static const NSUInteger kHealthInternalAuthShareAndRead = 101;
static const NSUInteger kHealthInternalAuthShareAndReadDenied = 104;

// The default HKQuantity types used by `approve` when the caller does not specify any.
static NSArray<NSString *> *defaultApproveTypeIdentifiers(void)
{
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

#pragma mark - JSON output helpers

static NSString *jsonStringFromObject(id obj)
{
  NSError *err = nil;
  NSData *data = [NSJSONSerialization dataWithJSONObject:obj options:0 error:&err];
  if (!data) {
    return [NSString stringWithFormat:@"\"<json-error: %@>\"", err.localizedDescription];
  }
  return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

static NSDictionary *recordToDictionary(FBHealthAuthorizationRecord *record)
{
  NSMutableDictionary *out = [NSMutableDictionary dictionary];
  if (record.identifier) {
    out[@"identifier"] = record.identifier;
  }
  if (record.sharingAuthorizationAllowed) {
    out[@"sharingAuthorizationAllowed"] = record.sharingAuthorizationAllowed;
  }
  if (record.readingAuthorizationAllowed) {
    out[@"readingAuthorizationAllowed"] = record.readingAuthorizationAllowed;
  }
  return out;
}

#pragma mark - Verb implementations

static int handleSetAction(FBHealthSettingsClient *client,
                           NSString *bundleID,
                           NSArray<NSString *> *typeIdentifiers,
                           NSUInteger statusCode,
                           NSString *actionName)
{
  NSArray<NSString *> *requested = typeIdentifiers.count > 0
  ? typeIdentifiers
  : defaultApproveTypeIdentifiers();

  FBHealthTypeSelection *selection = [[FBHealthTypeSelection alloc] init];
  NSMutableArray<NSString *> *resolvedIdentifiers = [NSMutableArray array];
  NSMutableArray<NSString *> *unresolvedIdentifiers = [NSMutableArray array];
  for (NSString *identifier in requested) {
    NSNumber *resolved = [selection resolveIdentifier:identifier error:nil];
    if (!resolved) {
      return 1;
    }
    if (resolved.boolValue) {
      [resolvedIdentifiers addObject:identifier];
    } else {
      NSLog(@"[Health] Skipping unresolved HK type identifier: %@", identifier);
      [unresolvedIdentifiers addObject:identifier];
    }
  }
  if (selection.isEmpty) {
    NSDictionary *output = @{
      @"action" : actionName,
      @"bundleID" : bundleID,
      @"ok" : @NO,
      @"error" : @"no resolvable HK types in request",
      @"unresolvedTypes" : unresolvedIdentifiers,
    };
    printf("%s\n", jsonStringFromObject(output).UTF8String);
    return 1;
  }

  // Seed first: the daemon drops status writes for unseen bundle/type pairs.
  FBHealthOperationResult *seed = [client seedAuthorizationForBundleIdentifier:bundleID selection:selection error:nil];
  if (!seed) {
    return 1;
  }
  FBHealthAuthorizationWrite *write = [client setAuthorizationForBundleIdentifier:bundleID selection:selection status:statusCode error:nil];
  if (!write) {
    return 1;
  }
  FBHealthOperationResult *set = write.operation;
  if (!set) {
    NSDictionary *output = @{
      @"action" : actionName,
      @"bundleID" : bundleID,
      @"ok" : @NO,
      @"error" : @"HKAuthorizationStore declares no known setAuthorizationStatuses: spelling",
      @"resolvedTypes" : resolvedIdentifiers,
      @"unresolvedTypes" : unresolvedIdentifiers,
    };
    printf("%s\n", jsonStringFromObject(output).UTF8String);
    return 1;
  }
  NSNumber *ok = @(seed.success && set.success);
  id seedError = [seed readErrorValueWithError:nil];
  if (!seedError) {
    return 1;
  }
  id setError = [set readErrorValueWithError:nil];
  if (!setError) {
    return 1;
  }
  NSDictionary *output = @{
    @"action" : actionName,
    @"bundleID" : bundleID,
    @"ok" : ok,
    @"resolvedTypes" : resolvedIdentifiers,
    @"unresolvedTypes" : unresolvedIdentifiers,
    @"seedError" : seedError,
    @"setError" : setError,
  };
  printf("%s\n", jsonStringFromObject(output).UTF8String);
  return (seed.success && set.success) ? 0 : 1;
}

static int handleClearAction(FBHealthSettingsClient *client, NSString *bundleID)
{
  FBHealthOperationResult *result = [client clearAuthorizationForBundleIdentifier:bundleID error:nil];
  if (!result) {
    return 1;
  }
  NSNumber *ok = @(result.success);
  id clearError = [result readErrorValueWithError:nil];
  if (!clearError) {
    return 1;
  }

  NSDictionary *output = @{
    @"action" : @"clear",
    @"bundleID" : bundleID,
    @"ok" : ok,
    @"error" : clearError,
  };
  printf("%s\n", jsonStringFromObject(output).UTF8String);
  return result.success ? 0 : 1;
}

static int handleListAction(FBHealthSettingsClient *client, NSString *bundleID)
{
  FBHealthRecordsResult *result = [client fetchRecordsForBundleIdentifier:bundleID error:nil];
  if (!result) {
    return 1;
  }
  NSArray<FBHealthAuthorizationRecord *> *records = [result readRecordsWithError:nil];
  if (!records) {
    return 1;
  }

  NSMutableArray *recordDicts = [NSMutableArray array];
  for (FBHealthAuthorizationRecord *record in records) {
    [recordDicts addObject:recordToDictionary(record)];
  }
  NSNumber *ok = @(!result.hasError);
  id fetchError = [result readErrorValueWithError:nil];
  if (!fetchError) {
    return 1;
  }
  NSDictionary *output = @{
    @"action" : @"list",
    @"bundleID" : bundleID,
    @"ok" : ok,
    @"error" : fetchError,
    @"records" : recordDicts,
  };
  printf("%s\n", jsonStringFromObject(output).UTF8String);
  return !result.hasError ? 0 : 1;
}

#pragma mark - Dispatch

static int handleHealthSettingsActionImpl(NSString *action, NSString *bundleID, NSArray<NSString *> *typeIdentifiers)
{
  FBHealthSettingsClient *client = [FBHealthSettingsClient liveClient];
  if (!client) {
    return 1;
  }
  if (!bundleID) {
    NSLog(@"[Health] bundleID is required for action '%@'", action);
    return 1;
  }
  if ([action isEqualToString:@"list"]) {
    return handleListAction(client, bundleID);
  }
  if ([action isEqualToString:@"clear"]) {
    return handleClearAction(client, bundleID);
  }
  if ([action isEqualToString:@"approve"]) {
    return handleSetAction(
      client,
      bundleID,
      typeIdentifiers,
      kHealthInternalAuthShareAndRead,
      @"approve"
    );
  }
  if ([action isEqualToString:@"revoke"]) {
    return handleSetAction(
      client,
      bundleID,
      typeIdentifiers,
      kHealthInternalAuthShareAndReadDenied,
      @"revoke"
    );
  }
  NSLog(@"[Health] Unknown action '%@'. Supported: list, clear, approve, revoke", action);
  return 1;
}

int handleHealthSettingsAction(NSString *action, NSString *bundleID, NSArray<NSString *> *typeIdentifiers)
{
  @try {
    return handleHealthSettingsActionImpl(action, bundleID, typeIdentifiers);
  } @catch (NSException *exception) {
    NSLog(@"[Health] Command raised: %@", exception);
    return 1;
  }
}
