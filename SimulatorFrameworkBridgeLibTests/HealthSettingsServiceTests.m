/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <dlfcn.h>
#import <objc/runtime.h>

#import <XCTest/XCTest.h>

#import <SimulatorFrameworkBridgeLib/AccessibilityRuntime.h>
#import <SimulatorFrameworkBridgeLib/HealthSettingsService.h>

// The two spellings `-[HKAuthorizationStore setAuthorizationStatuses:…]` has had. iOS 26.x declares the
// five-part one; iOS 27 renamed it to take `modeInfos:`. Which one a runtime has decides what this
// service does, so the tests below ask rather than assume.
static NSString *const kLegacyAuthorizationSelector =
@"setAuthorizationStatuses:authorizationModes:forBundleIdentifier:options:completion:";
static NSString *const kModeInfosAuthorizationSelector =
@"setAuthorizationStatuses:authorizationModes:modeInfos:forBundleIdentifier:options:completion:";

// HealthKit is dlopen-loaded by the service; the tests load it too so they can inspect the class before
// any verb has run.
static Class FBHealthAuthorizationStoreClass(void)
{
  dlopen("/System/Library/Frameworks/HealthKit.framework/HealthKit", RTLD_NOW);
  return objc_lookUpClass("HKAuthorizationStore");
}

static BOOL FBHealthRuntimeDeclaresSelector(NSString *selectorName)
{
  Class cls = FBHealthAuthorizationStoreClass();
  return cls != Nil && [cls instancesRespondToSelector:NSSelectorFromString(selectorName)];
}

@interface HealthSettingsServiceTests : XCTestCase
@end

@implementation HealthSettingsServiceTests

// HealthKit is present in the simulator, so every action reaches a real HKAuthorizationStore
// and healthd. `com.example.test` is not an installed app, which is why the read verbs report
// failure rather than returning records.

- (void)testListReportsFailureForAnUnknownBundleIdentifier
{
  XCTAssertEqual(handleHealthSettingsAction(@"list", @"com.example.test", @[]), 1);
}

- (void)testClearReportsFailureForAnUnknownBundleIdentifier
{
  XCTAssertEqual(handleHealthSettingsAction(@"clear", @"com.example.test", @[]), 1);
}

#pragma mark - The drifted authorization selector

// `approve` and `revoke` answer with an exit code on every runtime, whichever spelling of
// `setAuthorizationStatuses:…` it declares.

- (void)testApproveAnswersWithAStatusOnAnyRuntime
{
  XCTAssertNoThrow(handleHealthSettingsAction(@"approve", @"com.example.test", @[@"HKQuantityTypeIdentifierStepCount"]));
}

- (void)testApproveWithDefaultTypesAnswersWithAStatusOnAnyRuntime
{
  XCTAssertNoThrow(handleHealthSettingsAction(@"approve", @"com.example.test", @[]));
}

- (void)testRevokeAnswersWithAStatusOnAnyRuntime
{
  XCTAssertNoThrow(handleHealthSettingsAction(@"revoke", @"com.example.test", @[]));
}

// Exactly one of the two spellings is present on any runtime, so the service's
// `respondsToSelector:` dispatch between them is total. A third rename shows up as a failure here.
- (void)testTheRuntimeDeclaresExactlyOneAuthorizationSpelling
{
  XCTAssertNotNil(FBHealthAuthorizationStoreClass(), @"HealthKit must be loadable for any of this to mean anything");
  BOOL legacy = FBHealthRuntimeDeclaresSelector(kLegacyAuthorizationSelector);
  BOOL modeInfos = FBHealthRuntimeDeclaresSelector(kModeInfosAuthorizationSelector);
  XCTAssertNotEqual(legacy, modeInfos, @"expected one spelling, got legacy=%d modeInfos=%d", legacy, modeInfos);
}

// The header declares whichever spelling the runtime reports, with `options:` as the integer both
// take. A rename or a retyped argument is a red test here rather than a silent miscompile at the send.
- (void)testTheDeclaredAuthorizationSignatureAgreesWithTheRuntime
{
  BOOL legacy = FBHealthRuntimeDeclaresSelector(kLegacyAuthorizationSelector);
  NSString *declared = legacy ? kLegacyAuthorizationSelector : kModeInfosAuthorizationSelector;
  const char *expected = legacy ? "v@:@@@Q@?" : "v@:@@@@Q@?";
  NSString *mismatch = FBAXSignatureMismatch("HKAuthorizationStore", declared.UTF8String, NO, expected);
  XCTAssertNil(mismatch, @"%@", mismatch);
}

- (void)testUnknownActionReturnsFailure
{
  XCTAssertEqual(handleHealthSettingsAction(@"frobnicate", @"com.example.test", @[]), 1);
}

@end
