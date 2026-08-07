/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import <SimulatorFrameworkBridgeLib/AXRuntimePrivate.h>
#import <SimulatorFrameworkBridgeLib/AccessibilityRuntime.h>
#import <SimulatorFrameworkBridgeLib/AccessibilityService.h>
#import <SimulatorFrameworkBridgeLib/AccessibilityService+Testing.h>
#import <SimulatorFrameworkBridgeLib/XCTAutomationSupportPrivate.h>

#import "FBAXFakeRuntime.h"

static NSString *const kAXElementType = @"XC_kAXXCAttributeElementType";
static NSString *const kAXLabel = @"XC_kAXXCAttributeLabel";
static NSString *const kAXChildren = @"XC_kAXXCAttributeChildren";

// The pid every test that needs a readable application uses. Arbitrary, but a plausible one — nothing in
// the reader treats any particular value specially beyond the non-positive rejection.
static const pid_t kAppPid = 4321;

static NSError *FBAXTestsErrorWithCode(int32_t code)
{
  return [NSError errorWithDomain:@"XCTAutomationErrorDomain"
                             code:1
                         userInfo:@{FBAXAccessibilityErrorKey : @(code), NSLocalizedDescriptionKey : @"runtime said no"}];
}

/**
 * Drives `FBAXBridgeHandleRequest` against a fake `FBAXRuntime`.
 *
 * Every outcome below is one the live runtime only produces against an application that is dead, has no
 * accessibility server, is mid-launch or has stopped answering — states that on a real simulator have to
 * be manufactured by killing or SIGSTOP-ing an app and racing the read. Behind the seam they are just
 * values, so the reader's response shaping is checkable on macOS with nothing booted.
 */
@interface AccessibilityRuntimeTests : XCTestCase
@end

@implementation AccessibilityRuntimeTests
{
  FBAXFakeRuntime *_runtime;
}

- (void)setUp
{
  [super setUp];
  _runtime = [FBAXFakeRuntime new];
  FBAXBridgeSetRuntimeForTesting(_runtime);
}

- (void)tearDown
{
  // The substitution is process-wide, so leaving it set would leak into every other test in the bundle.
  FBAXBridgeSetRuntimeForTesting(nil);
  _runtime = nil;
  [super tearDown];
}

#pragma mark - Read-error classification

// `FBAXErrorServerNotFound` is the one AX error the host maps onto a typed, backend-neutral error, so the
// classifier has to recognise it by the code the runtime reports and treat every other code as an opaque
// failure. Getting this wrong in either direction is invisible on the wire until a real app misbehaves:
// too broad and a genuine reader bug is reported to the host as "the app isn't there", too narrow and a
// dead app produces an untyped error the host cannot act on.
- (void)testOnlyServerNotFoundClassifiesAsAnUnavailableApplication
{
  FBAXReadOutcome *unavailable = [FBAXReadOutcome failureForAttributeError:FBAXTestsErrorWithCode(FBAXErrorServerNotFound)];
  XCTAssertEqual(unavailable.status, FBAXReadStatusApplicationUnavailable);

  for (NSNumber *code in @[@(FBAXErrorInvalidUIElement), @(FBAXErrorIPCTimeout), @(FBAXErrorSuccess), @(-1)]) {
    FBAXReadOutcome *outcome = [FBAXReadOutcome failureForAttributeError:FBAXTestsErrorWithCode(code.intValue)];
    XCTAssertEqual(outcome.status, FBAXReadStatusFailed, @"AX code %@ must not be tagged unavailable", code);
  }
}

// An error carrying no accessibility code — a nil error, or one from some other layer — is a failure, not
// an unavailable application. `nil` in particular reaches the classifier whenever the runtime returns
// false without populating the out-parameter.
- (void)testErrorWithoutAnAccessibilityCodeIsAPlainFailure
{
  XCTAssertEqual([FBAXReadOutcome failureForAttributeError:nil].status, FBAXReadStatusFailed);

  NSError *foreign = [NSError errorWithDomain:NSCocoaErrorDomain code:-25215 userInfo:nil];
  FBAXReadOutcome *outcome = [FBAXReadOutcome failureForAttributeError:foreign];
  XCTAssertEqual(outcome.status, FBAXReadStatusFailed, @"the code must be read from the userInfo, not the NSError code");
}

#pragma mark - Hit-test outcomes

- (void)testHitOnASeededPointAnswersWithTheElementAndItsOwningPid
{
  _runtime.hitTestOutcome = [FBAXHitTestOutcome hit:[FBAXFakeElement readable:@"XCUIElementTypeButton"]
                             owningProcessIdentifier:kAppPid];

  NSDictionary *response = FBAXBridgeHandleRequest(@{@"verb" : @"hittest", @"pid" : @(kAppPid), @"x" : @10, @"y" : @20});
  XCTAssertEqualObjects(response[@"ok"], @YES);
  XCTAssertEqualObjects(response[@"pid"], @(kAppPid));
  XCTAssertEqualObjects(response[@"tree"][kAXElementType], @"XCUIElementTypeButton");
  XCTAssertEqual(_runtime.lastHitTestProcessIdentifier, kAppPid, @"an explicit pid must scope the hit-test");
  XCTAssertEqual(_runtime.lastHitTestPoint.x, 10);
  XCTAssertEqual(_runtime.lastHitTestPoint.y, 20);
}

// With no pid the hit-test is display-wide, and the owning pid comes back on the outcome rather than
// being something the caller already knew — that is what lets the host hit-test without a frontmost query.
- (void)testHitWithNoPidIsDisplayWideAndReportsTheOwningPid
{
  _runtime.hitTestOutcome = [FBAXHitTestOutcome hit:[FBAXFakeElement readable:@"XCUIElementTypeCell"]
                             owningProcessIdentifier:99];

  NSDictionary *response = FBAXBridgeHandleRequest(@{@"verb" : @"hittest", @"x" : @1, @"y" : @2});
  XCTAssertEqualObjects(response[@"ok"], @YES);
  XCTAssertEqualObjects(response[@"pid"], @99, @"the owning pid must come from the outcome");
  XCTAssertEqual(_runtime.lastHitTestProcessIdentifier, 0, @"no pid means a display-wide hit-test");
}

// Empty space is a successful result, not a failure. A host doing a streaming hit-test after a tap
// depends on telling "nothing is there" apart from "the reader broke", so this must stay `ok:true`.
- (void)testEmptyPointIsASuccessfulEmptyResult
{
  _runtime.hitTestOutcome = [FBAXHitTestOutcome empty];

  NSDictionary *response = FBAXBridgeHandleRequest(@{@"verb" : @"hittest", @"x" : @1, @"y" : @2});
  XCTAssertEqualObjects(response[@"ok"], @YES);
  XCTAssertEqualObjects(response[@"empty"], @YES);
  XCTAssertNil(response[@"tree"]);
  XCTAssertNil(response[@"error"]);
}

// Nothing answering the hit-test carries the `application_unavailable` kind, and the message names the
// pid when there is one — a seeded hit-test on a dead app and a display-wide one with nothing listening
// are different diagnostics.
- (void)testUnavailableApplicationIsTaggedAndNamesThePidWhenSeeded
{
  _runtime.hitTestOutcome = [FBAXHitTestOutcome applicationUnavailable];

  NSDictionary *seeded = FBAXBridgeHandleRequest(@{@"verb" : @"hittest", @"pid" : @(kAppPid), @"x" : @1, @"y" : @2});
  XCTAssertEqualObjects(seeded[@"ok"], @NO);
  XCTAssertEqualObjects(seeded[@"error_kind"], @"application_unavailable");
  XCTAssertEqualObjects(seeded[@"error"], @"pid 4321 has no accessibility server to hit-test");

  NSDictionary *systemWide = FBAXBridgeHandleRequest(@{@"verb" : @"hittest", @"x" : @1, @"y" : @2});
  XCTAssertEqualObjects(systemWide[@"error_kind"], @"application_unavailable");
  XCTAssertEqualObjects(systemWide[@"error"], @"no accessibility server answered the system-wide hit-test");
}

// A hit-test that went wrong is an opaque failure carrying the runtime's reason, and must *not* pick up
// the `application_unavailable` kind — the host acts on that kind, and a reader bug is not an absent app.
- (void)testFailedHitTestIsAnOpaqueFailureCarryingTheReason
{
  _runtime.hitTestOutcome = [FBAXHitTestOutcome failed:@"AXUIElementCreateSystemWide returned NULL"];

  NSDictionary *response = FBAXBridgeHandleRequest(@{@"verb" : @"hittest", @"x" : @1, @"y" : @2});
  XCTAssertEqualObjects(response[@"ok"], @NO);
  XCTAssertEqualObjects(response[@"error"], @"AXUIElementCreateSystemWide returned NULL");
  XCTAssertNil(response[@"error_kind"], @"a reader failure must not be tagged as an unavailable application");
}

// The hit lands but the element cannot be read: the app went away between the two round trips. The
// response is shaped from the *read's* outcome, and still names the pid the hit-test attributed it to.
- (void)testHitElementThatCannotBeReadIsReportedFromTheReadOutcome
{
  _runtime.hitTestOutcome = [FBAXHitTestOutcome hit:[FBAXFakeElement applicationUnavailable]
                             owningProcessIdentifier:kAppPid];
  NSDictionary *unavailable = FBAXBridgeHandleRequest(@{@"verb" : @"hittest", @"x" : @1, @"y" : @2});
  XCTAssertEqualObjects(unavailable[@"error_kind"], @"application_unavailable");
  XCTAssertEqualObjects(unavailable[@"error"], @"pid 4321 has no accessibility server");

  _runtime.hitTestOutcome = [FBAXHitTestOutcome hit:[FBAXFakeElement failed:FBAXTestsErrorWithCode(FBAXErrorIPCTimeout)]
                             owningProcessIdentifier:kAppPid];
  NSDictionary *failed = FBAXBridgeHandleRequest(@{@"verb" : @"hittest", @"x" : @1, @"y" : @2});
  XCTAssertEqualObjects(failed[@"ok"], @NO);
  XCTAssertEqualObjects(failed[@"error"], @"failed to read the hit element");
  XCTAssertNil(failed[@"error_kind"]);
}

#pragma mark - Describe outcomes

- (void)testDescribeReadsTheTreeAndReportsThePid
{
  FBAXFakeElement *root = [FBAXFakeElement readable:@"UIApplication"];
  root.children = @[[FBAXFakeElement readable:@"XCUIElementTypeWindow"]];
  _runtime.applicationElements[@(kAppPid)] = root;

  NSDictionary *response = FBAXBridgeHandleRequest(@{@"verb" : @"describe", @"pid" : @(kAppPid), @"maxDepth" : @5});
  XCTAssertEqualObjects(response[@"ok"], @YES);
  XCTAssertEqualObjects(response[@"pid"], @(kAppPid));
  XCTAssertEqualObjects(response[@"truncated"], @NO);
  XCTAssertEqualObjects(response[@"tree"][kAXElementType], @"UIApplication");
  XCTAssertEqualObjects(response[@"tree"][kAXChildren][0][kAXElementType], @"XCUIElementTypeWindow");
}

// A pid the runtime vends no element for. Distinct from an element that cannot be read: nothing was
// reached at all, so there is no read outcome to shape the response from.
- (void)testDescribeWithNoApplicationElementIsAFailureNamingThePid
{
  NSDictionary *response = FBAXBridgeHandleRequest(@{@"verb" : @"describe", @"pid" : @(kAppPid)});
  XCTAssertEqualObjects(response[@"ok"], @NO);
  XCTAssertEqualObjects(response[@"error"], @"no application element for pid 4321");
}

- (void)testDescribeOfAnUnreadableRootIsTaggedUnavailable
{
  _runtime.applicationElements[@(kAppPid)] = [FBAXFakeElement applicationUnavailable];

  NSDictionary *response = FBAXBridgeHandleRequest(@{@"verb" : @"describe", @"pid" : @(kAppPid)});
  XCTAssertEqualObjects(response[@"ok"], @NO);
  XCTAssertEqualObjects(response[@"error_kind"], @"application_unavailable");
  XCTAssertEqualObjects(response[@"error"], @"pid 4321 has no accessibility server");
}

// A root that failed for any other reason is an opaque failure quoting what the runtime said — and when
// the runtime said nothing, the message says that rather than trailing off into `(null)`.
- (void)testDescribeOfAFailedRootQuotesTheRuntimeOrSaysItReportedNothing
{
  _runtime.applicationElements[@(kAppPid)] = [FBAXFakeElement failed:FBAXTestsErrorWithCode(FBAXErrorIPCTimeout)];
  NSDictionary *quoted = FBAXBridgeHandleRequest(@{@"verb" : @"describe", @"pid" : @(kAppPid)});
  XCTAssertEqualObjects(quoted[@"ok"], @NO);
  XCTAssertNil(quoted[@"error_kind"]);
  XCTAssertEqualObjects(quoted[@"error"], @"failed to read the element tree for pid 4321: runtime said no");

  _runtime.applicationElements[@(kAppPid)] = [FBAXFakeElement failed:nil];
  NSDictionary *silent = FBAXBridgeHandleRequest(@{@"verb" : @"describe", @"pid" : @(kAppPid)});
  XCTAssertEqualObjects(
    silent[@"error"],
    @"failed to read the element tree for pid 4321: the accessibility runtime reported no error"
  );
}

// A child that cannot be read is dropped from the tree rather than failing the whole read. A single
// unreadable subview in a large app must not cost the host the entire dump — and its siblings must
// survive alongside it, not be cut short at the failure.
- (void)testAnUnreadableChildIsDroppedWithoutFailingTheRead
{
  FBAXFakeElement *root = [FBAXFakeElement readable:@"UIApplication"];
  root.children = @[
    [FBAXFakeElement readable:@"first"],
    [FBAXFakeElement applicationUnavailable],
    [FBAXFakeElement failed:FBAXTestsErrorWithCode(FBAXErrorIPCTimeout)],
    [FBAXFakeElement readable:@"last"],
  ];
  _runtime.applicationElements[@(kAppPid)] = root;

  NSDictionary *response = FBAXBridgeHandleRequest(@{@"verb" : @"describe", @"pid" : @(kAppPid), @"maxDepth" : @5});
  XCTAssertEqualObjects(response[@"ok"], @YES, @"an unreadable child must not fail the whole read");
  NSArray *children = response[@"tree"][kAXChildren];
  XCTAssertEqual(children.count, 2u, @"only the readable children survive");
  XCTAssertEqualObjects(children[0][kAXLabel], @"first");
  XCTAssertEqualObjects(children[1][kAXLabel], @"last", @"a later sibling must survive an earlier failure");
  XCTAssertEqualObjects(response[@"truncated"], @NO, @"a dropped child is not truncation");
}

// The depth cap stopping descent into children that exist sets `truncated`, so the host warns rather than
// passing a partial tree off as complete. A node whose children were all visited does not.
- (void)testDepthCapMarksTheReadTruncated
{
  FBAXFakeElement *root = [FBAXFakeElement readable:@"UIApplication"];
  FBAXFakeElement *child = [FBAXFakeElement readable:@"XCUIElementTypeWindow"];
  child.children = @[[FBAXFakeElement readable:@"XCUIElementTypeButton"]];
  root.children = @[child];
  _runtime.applicationElements[@(kAppPid)] = root;

  NSDictionary *cut = FBAXBridgeHandleRequest(@{@"verb" : @"describe", @"pid" : @(kAppPid), @"maxDepth" : @1});
  XCTAssertEqualObjects(cut[@"truncated"], @YES);
  XCTAssertEqual([cut[@"tree"][kAXChildren][0][kAXChildren] count], 0u, @"descent stopped at the cap");

  NSDictionary *whole = FBAXBridgeHandleRequest(@{@"verb" : @"describe", @"pid" : @(kAppPid), @"maxDepth" : @5});
  XCTAssertEqualObjects(whole[@"truncated"], @NO);
  XCTAssertEqual([whole[@"tree"][kAXChildren][0][kAXChildren] count], 1u);
}

// The node budget is shared across the whole walk, so running out mid-traversal also sets `truncated`.
// This is the cap that protects the reader from an unbounded tree, and the host has to know it fired.
- (void)testNodeBudgetExhaustionMarksTheReadTruncated
{
  FBAXFakeElement *root = [FBAXFakeElement readable:@"UIApplication"];
  root.children = @[
    [FBAXFakeElement readable:@"first"],
    [FBAXFakeElement readable:@"second"],
    [FBAXFakeElement readable:@"third"],
  ];
  _runtime.applicationElements[@(kAppPid)] = root;

  NSDictionary *response =
  FBAXBridgeHandleRequest(@{@"verb" : @"describe", @"pid" : @(kAppPid), @"maxDepth" : @5, @"maxNodes" : @2});
  XCTAssertEqualObjects(response[@"ok"], @YES);
  XCTAssertEqualObjects(response[@"truncated"], @YES);
  XCTAssertEqual([response[@"tree"][kAXChildren] count], 2u, @"the walk stopped when the budget ran out");
}

#pragma mark - Frontmost dispatch

- (void)testCenterPointIsTheDefaultMethodAndIsEchoedBack
{
  _runtime.hitTestOutcome = [FBAXHitTestOutcome hit:[FBAXFakeElement readable:@"leaf"] owningProcessIdentifier:kAppPid];
  _runtime.applicationElements[@(kAppPid)] = [FBAXFakeElement readable:@"UIApplication"];

  NSDictionary *response = FBAXBridgeHandleRequest(@{@"verb" : @"describe", @"x" : @201, @"y" : @437});
  XCTAssertEqualObjects(response[@"ok"], @YES);
  XCTAssertEqualObjects(response[@"pid"], @(kAppPid));
  XCTAssertEqualObjects(response[@"method"], @"center-point");
  XCTAssertEqual(_runtime.hitTestCount, 1u);
  XCTAssertEqual(_runtime.lastHitTestProcessIdentifier, 0, @"the frontmost hit-test is display-wide");
  XCTAssertEqual(_runtime.lastHitTestPoint.x, 201, @"the request's anchor is what gets hit-tested");
}

- (void)testEachFrontmostMethodIsDispatchedToItsOwnResolverAndEchoedBack
{
  _runtime.applicationElements[@(kAppPid)] = [FBAXFakeElement readable:@"UIApplication"];
  _runtime.windowServerOutcome = [FBAXFrontmostOutcome resolved:kAppPid];
  _runtime.runningBoardOutcome = [FBAXFrontmostOutcome resolved:kAppPid];

  NSDictionary *windowServer =
  FBAXBridgeHandleRequest(@{@"verb" : @"describe", @"x" : @1, @"y" : @2, @"method" : @"window-server"});
  XCTAssertEqualObjects(windowServer[@"method"], @"window-server");
  XCTAssertEqual(_runtime.windowServerCount, 1u);
  XCTAssertEqual(_runtime.runningBoardCount, 0u);
  XCTAssertEqual(_runtime.hitTestCount, 0u);

  NSDictionary *runningBoard =
  FBAXBridgeHandleRequest(@{@"verb" : @"describe", @"x" : @1, @"y" : @2, @"method" : @"runningboard"});
  XCTAssertEqualObjects(runningBoard[@"method"], @"runningboard");
  XCTAssertEqual(_runtime.runningBoardCount, 1u);
  XCTAssertEqual(_runtime.windowServerCount, 1u, @"the window-server resolver must not run again");
}

// Each method answers on its own. A resolver that fails is reported as a failure rather than quietly
// falling through to another one — the host picked the method deliberately, and a response whose `method`
// disagrees with the resolver that ran would be worse than no answer.
- (void)testAFailedResolverDoesNotFallBackToAnotherMethod
{
  _runtime.windowServerOutcome = [FBAXFrontmostOutcome unresolved:@"the window server did not answer"];
  _runtime.hitTestOutcome = [FBAXHitTestOutcome hit:[FBAXFakeElement readable:@"leaf"] owningProcessIdentifier:kAppPid];
  _runtime.applicationElements[@(kAppPid)] = [FBAXFakeElement readable:@"UIApplication"];

  NSDictionary *response =
  FBAXBridgeHandleRequest(@{@"verb" : @"describe", @"x" : @1, @"y" : @2, @"method" : @"window-server"});
  XCTAssertEqualObjects(response[@"ok"], @NO);
  XCTAssertEqualObjects(response[@"error"], @"the window server did not answer");
  XCTAssertEqual(_runtime.hitTestCount, 0u, @"no fallback to the positional resolver");
  XCTAssertEqual(_runtime.runningBoardCount, 0u, @"no fallback to RunningBoard");
}

// The positional resolver's two non-resolving outcomes get distinct messages: nothing at the anchor (an
// app mid-launch, or genuinely empty space) versus nothing answering at all.
- (void)testCenterPointReportsAnEmptyAnchorAndAnUnanswerableOneDifferently
{
  _runtime.hitTestOutcome = [FBAXHitTestOutcome empty];
  NSDictionary *empty = FBAXBridgeHandleRequest(@{@"verb" : @"describe", @"x" : @9999, @"y" : @9999});
  XCTAssertEqualObjects(empty[@"ok"], @NO);
  XCTAssertEqualObjects(empty[@"error"], @"system-wide hit-test at (9999.0, 9999.0) found no element");

  _runtime.hitTestOutcome = [FBAXHitTestOutcome applicationUnavailable];
  NSDictionary *unavailable = FBAXBridgeHandleRequest(@{@"verb" : @"describe", @"x" : @5, @"y" : @6});
  XCTAssertEqualObjects(
    unavailable[@"error"],
    @"no accessibility server answered the system-wide hit-test at (5.0, 6.0)"
  );
  // Deliberately untagged: the host treats `application_unavailable` as "this pid names no readable app",
  // and a frontmost query has no pid to say that about.
  XCTAssertNil(unavailable[@"error_kind"]);
}

- (void)testAnUnsupportedFrontmostMethodConsultsNoResolver
{
  NSDictionary *response =
  FBAXBridgeHandleRequest(@{@"verb" : @"describe", @"x" : @1, @"y" : @2, @"method" : @"telepathy"});
  XCTAssertEqualObjects(response[@"ok"], @NO);
  XCTAssertEqualObjects(response[@"error"], @"unsupported frontmost method: telepathy");
  XCTAssertEqual(_runtime.hitTestCount, 0u);
  XCTAssertEqual(_runtime.windowServerCount, 0u);
  XCTAssertEqual(_runtime.runningBoardCount, 0u);
}

// A `method` of the wrong type is not a method name — it falls back to the default rather than being
// stringified into an unsupported-method error. `method` arrives as whatever JSON the host sent.
- (void)testANonStringMethodFallsBackToTheDefault
{
  _runtime.hitTestOutcome = [FBAXHitTestOutcome hit:[FBAXFakeElement readable:@"leaf"] owningProcessIdentifier:kAppPid];
  _runtime.applicationElements[@(kAppPid)] = [FBAXFakeElement readable:@"UIApplication"];

  NSDictionary *response = FBAXBridgeHandleRequest(@{@"verb" : @"describe", @"x" : @1, @"y" : @2, @"method" : @7});
  XCTAssertEqualObjects(response[@"method"], @"center-point");
  XCTAssertEqual(_runtime.hitTestCount, 1u);
}

@end
