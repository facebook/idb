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

// BUG: `approve` and `revoke` work or raise depending on which runtime they are run against, because
// `HealthSettingsService` sends the five-part spelling unconditionally. iOS 26.x declares it and the
// verbs return a status; iOS 27 renamed it to take `modeInfos:`, so the send finds no such selector and
// raises out of a service entry point that is supposed to always answer with an exit code.
//
// Pinned by asking the runtime what it declares, rather than asserting the raise outright: this bundle
// runs on whichever simulator it is given, so a pin that only holds on one runtime is as version-
// dependent as the bug it is pinning, and would be red wherever the other runtime is used. Stating the
// defect as what it is — a contract that holds on one runtime and not the other — is what makes it true
// everywhere. Flipped to an unconditional no-throw by the fix, further up the stack.

- (void)testApproveOnlyAnswersOnARuntimeDeclaringTheLegacySelector
{
  if (FBHealthRuntimeDeclaresSelector(kLegacyAuthorizationSelector)) {
    XCTAssertNoThrow(handleHealthSettingsAction(@"approve", @"com.example.test", @[@"HKQuantityTypeIdentifierStepCount"]));
  } else {
    XCTAssertThrows(handleHealthSettingsAction(@"approve", @"com.example.test", @[@"HKQuantityTypeIdentifierStepCount"]));
  }
}

- (void)testApproveWithDefaultTypesOnlyAnswersOnARuntimeDeclaringTheLegacySelector
{
  if (FBHealthRuntimeDeclaresSelector(kLegacyAuthorizationSelector)) {
    XCTAssertNoThrow(handleHealthSettingsAction(@"approve", @"com.example.test", @[]));
  } else {
    XCTAssertThrows(handleHealthSettingsAction(@"approve", @"com.example.test", @[]));
  }
}

- (void)testRevokeOnlyAnswersOnARuntimeDeclaringTheLegacySelector
{
  if (FBHealthRuntimeDeclaresSelector(kLegacyAuthorizationSelector)) {
    XCTAssertNoThrow(handleHealthSettingsAction(@"revoke", @"com.example.test", @[]));
  } else {
    XCTAssertThrows(handleHealthSettingsAction(@"revoke", @"com.example.test", @[]));
  }
}

// Exactly one of the two spellings is present, whichever runtime this is. That is what makes a
// `respondsToSelector:` dispatch between them a total decision rather than a guess with a hole in it,
// and if a third rename ever lands, this is what says so.
- (void)testTheRuntimeDeclaresExactlyOneAuthorizationSpelling
{
  XCTAssertNotNil(FBHealthAuthorizationStoreClass(), @"HealthKit must be loadable for any of this to mean anything");
  BOOL legacy = FBHealthRuntimeDeclaresSelector(kLegacyAuthorizationSelector);
  BOOL modeInfos = FBHealthRuntimeDeclaresSelector(kModeInfosAuthorizationSelector);
  XCTAssertNotEqual(legacy, modeInfos, @"expected one spelling, got legacy=%d modeInfos=%d", legacy, modeInfos);
}

// BUG: the header declares `options:` as an `NSDictionary *`, but every runtime encodes it as `Q` — an
// NSUInteger. The service only ever passes `nil`, which marshals as 0 and hides the mistake, so the
// declaration has been wrong for as long as it has existed and would miscompile the moment a real
// options value was passed. Corrected by the fix, which flips this to an agreement assertion.
//
// Separated from the selector-drift pins below the stack only because it needs `FBAXSignatureMismatch`,
// which does not exist until two commits later.
- (void)testTheAuthorizationSelectorTakesAnIntegerOptionsArgumentAndNotADictionary
{
  NSString *declared = FBHealthRuntimeDeclaresSelector(kLegacyAuthorizationSelector)
  ? kLegacyAuthorizationSelector
  : kModeInfosAuthorizationSelector;
  NSString *asObject = [declared isEqualToString:kLegacyAuthorizationSelector] ? @"v@:@@@@@?" : @"v@:@@@@@@?";
  XCTAssertNotNil(
    FBAXSignatureMismatch("HKAuthorizationStore", declared.UTF8String, NO, asObject.UTF8String),
    @"the header's object-typed `options:` must not agree with the runtime — if it does, this pin is stale"
  );
}

- (void)testUnknownActionReturnsFailure
{
  XCTAssertEqual(handleHealthSettingsAction(@"frobnicate", @"com.example.test", @[]), 1);
}

@end
