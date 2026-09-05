/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <dlfcn.h>
#import <objc/runtime.h>

#import <XCTest/XCTest.h>

#import <SimulatorFrameworkBridgeLib/AXRuntimePrivate.h>
#import <SimulatorFrameworkBridgeLib/AccessibilityRuntime.h>
#import <SimulatorFrameworkBridgeLib/AccessibilityService.h>
#import <SimulatorFrameworkBridgeLib/AccessibilityService+Testing.h>
#import <SimulatorFrameworkBridgeLib/XCTAutomationSupportPrivate.h>

#import "AXPAttributes.h"
#import "FBAXFakeRuntime.h"

static NSString *const kAXElementType = @"XC_kAXXCAttributeElementType";
static NSString *const kAXLabel = @"XC_kAXXCAttributeLabel";
static NSString *const kAXChildren = @"XC_kAXXCAttributeChildren";
static NSString *const kAXFrame = @"XC_kAXXCAttributeFrame";
static NSString *const kAXVisiblePoint = @"XC_kAXXCAttributeVisiblePoint";
static NSString *const kNodeIsEnabled = @"FBIsEnabled";
static NSString *const kNodeTranslatorRole = @"FBTranslatorRole";

// The pid every test that needs a readable application uses. Arbitrary, but a plausible one — nothing in
// the reader treats any particular value specially beyond the non-positive rejection.
static const pid_t kAppPid = 4321;

static NSError *FBAXTestsErrorWithCode(int32_t code)
{
  return [NSError errorWithDomain:@"XCTAutomationErrorDomain"
                             code:1
                         userInfo:@{FBAXAccessibilityErrorKey : @(code), NSLocalizedDescriptionKey : @"runtime said no"}];
}

// Carries an aggregate signature for the encoding-comparison tests. Foundation has plenty of selectors to
// compare against, but none whose encoding contains a digit that is part of the type rather than an
// offset, which is the case the comparison has to get right.
typedef struct FBAXQuad {
  int values[4];
} FBAXQuad;

typedef struct FBAXPair {
  int first;
  int second;
} FBAXPair;

@interface FBAXSignatureProbe : NSObject
- (FBAXQuad)quadFromPair:(FBAXPair)pair;
@end

@implementation FBAXSignatureProbe
- (FBAXQuad)quadFromPair:(FBAXPair)pair
{
  return (FBAXQuad) {{pair.first, pair.second, 0, 0}};
}

@end

/**
 * Drives `FBAXBridgeHandleRequest` against a fake `FBAXRuntime`, reaching outcomes a real simulator only
 * produces against a dead, mid-launch or SIGSTOP-ed application.
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

#pragma mark - Encoding normalisation

- (void)testTypesOnlyDropsOffsetsAndKeepsTypes
{
  NSDictionary<NSString *, NSString *> *examples = @{
    // Already normalised: nothing to drop.
    @"v@:" : @"v@:",
    @"Q@:" : @"Q@:",
    // The common case — a return, self, selector and their offsets.
    @"Q16@0:8" : @"Q@:",
    @"@24@0:8Q16" : @"@@:Q",
    @"v24@0:8@16" : @"v@:@",
    // Blocks, out-parameters, const char * and bare pointers keep their punctuation.
    @"v32@0:8@?24" : @"v@:@?",
    @"@40@0:8@16^@24@32" : @"@@:@^@@",
    @"@24@0:8r*16" : @"@@:r*",
    // A pointer to an opaque struct — the shape `AXUIElementRef` arrives as.
    @"^{__AXUIElement=}16@0:8" : @"^{__AXUIElement=}@:",
    // Digits inside an aggregate are part of the type and survive; the frame numbers around them do not.
    @"{FBAXQuad=[4i]}32@0:8{FBAXPair=ii}16" : @"{FBAXQuad=[4i]}@:{FBAXPair=ii}",
    @"[8i]16@0:8" : @"[8i]@:",
    @"(u=i[2c])16@0:8" : @"(u=i[2c])@:",
    // Nested aggregates: the depth counter has to come back to zero before dropping resumes.
    @"{a={b=[4i]}}24@0:8i16" : @"{a={b=[4i]}}@:i",
    // The empty encoding is not a crash.
    @"" : @"",
  };
  for (NSString *encoding in examples) {
    XCTAssertEqualObjects(
      FBAXTypesOnly(encoding.UTF8String),
      examples[encoding],
      @"normalising %@",
      encoding
    );
  }
}

// The table in the runtime may be written with or without offsets.
- (void)testTypesOnlyMakesRuntimeAndHandWrittenEncodingsAgree
{
  Method length = class_getInstanceMethod(NSString.class, @selector(length));
  XCTAssertEqualObjects(FBAXTypesOnly(method_getTypeEncoding(length)), FBAXTypesOnly("Q@:"));

  Method objectAtIndex = class_getInstanceMethod(NSArray.class, @selector(objectAtIndex:));
  XCTAssertEqualObjects(FBAXTypesOnly(method_getTypeEncoding(objectAtIndex)), FBAXTypesOnly("@@:Q"));
}

- (void)testTypesOnlyIsIdempotent
{
  for (NSString *encoding in @[@"Q16@0:8", @"{FBAXQuad=[4i]}32@0:8{FBAXPair=ii}16", @"v32@0:8@?24"]) {
    NSString *once = FBAXTypesOnly(encoding.UTF8String);
    XCTAssertEqualObjects(FBAXTypesOnly(once.UTF8String), once, @"normalising %@ twice", encoding);
  }
}

#pragma mark - Bound signature checking

// Runs against the guest's copies of the frameworks; a shape that moved only inside an iOS runtime
// image would pass against the host's.
- (void)testEveryBoundSignatureAgreesWithTheRuntime
{
  NSArray<NSString *> *warnings = FBAXSignatureWarnings();
  XCTAssertEqualObjects(warnings, @[], @"%@", [warnings componentsJoinedByString:@"\n"]);
}

- (void)testSignatureAgreesWithTheRuntime
{
  XCTAssertNil(FBAXSignatureMismatch("NSString", "length", NO, "Q@:"));
  XCTAssertNil(FBAXSignatureMismatch("NSString", "stringWithUTF8String:", YES, "@@:r*"));
  XCTAssertNil(FBAXSignatureMismatch("NSArray", "objectAtIndex:", NO, "@@:Q"));
}

// Offsets differ by ABI, so the check must not fire on them.
- (void)testSignatureIgnoresFrameSizesAndOffsets
{
  XCTAssertNil(FBAXSignatureMismatch("NSString", "length", NO, "Q16@0:8"));
  XCTAssertNil(FBAXSignatureMismatch("NSArray", "objectAtIndex:", NO, "@24@0:8Q16"));
}

- (void)testSignatureKeepsDigitsInsideAggregateEncodings
{
  XCTAssertNil(FBAXSignatureMismatch("FBAXSignatureProbe", "quadFromPair:", NO, "{FBAXQuad=[4i]}@:{FBAXPair=ii}"));

  NSString *mismatch = FBAXSignatureMismatch("FBAXSignatureProbe", "quadFromPair:", NO, "{FBAXQuad=[8i]}@:{FBAXPair=ii}");
  XCTAssertNotNil(mismatch, @"an array length inside the struct is a different type and must not be dropped");
}

- (void)testSignatureMismatchNamesWhatItFoundAndWhatItAssumed
{
  NSString *mismatch = FBAXSignatureMismatch("NSString", "length", NO, "i@:");
  XCTAssertNotNil(mismatch);
  XCTAssertTrue([mismatch containsString:@"-[NSString length]"], @"%@", mismatch);
  XCTAssertTrue([mismatch containsString:@"Q@:"], @"the encoding found must be named: %@", mismatch);
  XCTAssertTrue([mismatch containsString:@"i@:"], @"the encoding assumed must be named: %@", mismatch);
}

- (void)testSignatureMismatchReportedForMissingClassOrSelector
{
  NSString *absentClass = FBAXSignatureMismatch("FBAXNoSuchClass", "length", NO, "Q@:");
  XCTAssertNotNil(absentClass);
  XCTAssertTrue([absentClass containsString:@"FBAXNoSuchClass"], @"%@", absentClass);

  XCTAssertNotNil(FBAXSignatureMismatch("NSString", "fbaxNoSuchSelector", NO, "Q@:"));
}

- (void)testSignatureDistinguishesClassFromInstanceMethods
{
  XCTAssertNotNil(FBAXSignatureMismatch("NSString", "length", YES, "Q@:"));
  XCTAssertNotNil(FBAXSignatureMismatch("NSString", "stringWithUTF8String:", NO, "@@:r*"));
}

#pragma mark - Read-error classification

// Too broad and a reader bug reads as "the app isn't there"; too narrow and a dead app is an untyped error.
- (void)testEachActionableAXCodeClassifiesAsItsOwnCondition
{
  FBAXReadOutcome *unavailable = [FBAXReadOutcome failureForAttributeError:FBAXTestsErrorWithCode(FBAXErrorServerNotFound)];
  XCTAssertEqual(unavailable.status, FBAXReadStatusApplicationUnavailable);

  FBAXReadOutcome *notResponding = [FBAXReadOutcome failureForAttributeError:FBAXTestsErrorWithCode(FBAXErrorIPCTimeout)];
  XCTAssertEqual(notResponding.status, FBAXReadStatusApplicationNotResponding, @"an IPC timeout classifies as application-not-responding, not unavailable");

  for (NSNumber *code in @[@(FBAXErrorInvalidUIElement), @(FBAXErrorSuccess), @(-1)]) {
    FBAXReadOutcome *outcome = [FBAXReadOutcome failureForAttributeError:FBAXTestsErrorWithCode(code.intValue)];
    XCTAssertEqual(outcome.status, FBAXReadStatusFailed, @"AX code %@ must stay an opaque failure", code);
  }
}

// `nil` reaches the classifier whenever the runtime returns false without populating the out-parameter.
- (void)testErrorWithoutAnAccessibilityCodeIsAPlainFailure
{
  XCTAssertEqual([FBAXReadOutcome failureForAttributeError:nil].status, FBAXReadStatusFailed);

  NSError *foreign = [NSError errorWithDomain:NSCocoaErrorDomain code:-25215 userInfo:nil];
  FBAXReadOutcome *outcome = [FBAXReadOutcome failureForAttributeError:foreign];
  XCTAssertEqual(outcome.status, FBAXReadStatusFailed, @"the code must be read from the userInfo, not the NSError code");
}

#pragma mark - Hit-test outcomes

- (void)testHitTestErrorClassification
{
  XCTAssertNil(
    [FBAXHitTestOutcome outcomeForHitTestError:FBAXErrorSuccess hasElement:YES],
    @"success with an element returns nil; the caller wraps the element"
  );
  // Success with no element out is still nothing at the point, not a contradiction to report.
  XCTAssertEqual(
    [FBAXHitTestOutcome outcomeForHitTestError:FBAXErrorSuccess hasElement:NO].status,
    FBAXHitTestStatusEmpty
  );
  XCTAssertEqual(
    [FBAXHitTestOutcome outcomeForHitTestError:FBAXErrorServerNotFound hasElement:NO].status,
    FBAXHitTestStatusApplicationUnavailable,
    @"server-not-found classifies as application-unavailable, not empty"
  );
  XCTAssertEqual(
    [FBAXHitTestOutcome outcomeForHitTestError:FBAXErrorInvalidUIElement hasElement:NO].status,
    FBAXHitTestStatusEmpty,
    @"a genuinely empty point"
  );
  XCTAssertEqual(
    [FBAXHitTestOutcome outcomeForHitTestError:FBAXErrorIPCTimeout hasElement:NO].status,
    FBAXHitTestStatusApplicationNotResponding,
    @"an IPC timeout classifies as application-not-responding, not empty or unavailable"
  );
}

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

- (void)testHitWithNoPidIsDisplayWideAndReportsTheOwningPid
{
  _runtime.hitTestOutcome = [FBAXHitTestOutcome hit:[FBAXFakeElement readable:@"XCUIElementTypeCell"]
                             owningProcessIdentifier:99];

  NSDictionary *response = FBAXBridgeHandleRequest(@{@"verb" : @"hittest", @"x" : @1, @"y" : @2});
  XCTAssertEqualObjects(response[@"ok"], @YES);
  XCTAssertEqualObjects(response[@"pid"], @99, @"the owning pid must come from the outcome");
  XCTAssertEqual(_runtime.lastHitTestProcessIdentifier, 0, @"no pid means a display-wide hit-test");
}

- (void)testEmptyPointIsASuccessfulEmptyResult
{
  _runtime.hitTestOutcome = [FBAXHitTestOutcome empty];

  NSDictionary *response = FBAXBridgeHandleRequest(@{@"verb" : @"hittest", @"x" : @1, @"y" : @2});
  XCTAssertEqualObjects(response[@"ok"], @YES);
  XCTAssertEqualObjects(response[@"empty"], @YES);
  XCTAssertNil(response[@"tree"]);
  XCTAssertNil(response[@"error"]);
}

- (void)testUnavailableApplicationIsTaggedAndNamesThePidWhenSeeded
{
  _runtime.hitTestOutcome = [FBAXHitTestOutcome applicationUnavailable];

  NSDictionary *seeded = FBAXBridgeHandleRequest(@{@"verb" : @"hittest", @"pid" : @(kAppPid), @"x" : @1, @"y" : @2});
  XCTAssertEqualObjects(seeded[@"ok"], @NO);
  XCTAssertEqualObjects(seeded[@"error_kind"], @"application_unavailable");
  XCTAssertEqualObjects(seeded[@"error"], @"pid 4321 has no accessibility server to hit-test");

  XCTAssertEqualObjects(seeded[@"pid"], @(kAppPid), @"a tagged failure names the process it is about");

  NSDictionary *systemWide = FBAXBridgeHandleRequest(@{@"verb" : @"hittest", @"x" : @1, @"y" : @2});
  XCTAssertEqualObjects(systemWide[@"error_kind"], @"application_unavailable");
  XCTAssertEqualObjects(systemWide[@"error"], @"no accessibility server answered the system-wide hit-test");
  XCTAssertNil(systemWide[@"pid"], @"a display-wide hit-test nothing answered has no process to name");
}

- (void)testNotRespondingAndUnavailableProduceDistinctErrorKinds
{
  _runtime.hitTestOutcome = [FBAXHitTestOutcome applicationNotResponding];

  NSDictionary *seeded = FBAXBridgeHandleRequest(@{@"verb" : @"hittest", @"pid" : @(kAppPid), @"x" : @1, @"y" : @2});
  XCTAssertEqualObjects(seeded[@"ok"], @NO);
  XCTAssertEqualObjects(seeded[@"error_kind"], @"application_not_responding");
  XCTAssertEqualObjects(seeded[@"error"], @"pid 4321 did not answer the hit-test in time");
  XCTAssertEqualObjects(seeded[@"pid"], @(kAppPid));

  NSDictionary *systemWide = FBAXBridgeHandleRequest(@{@"verb" : @"hittest", @"x" : @1, @"y" : @2});
  XCTAssertEqualObjects(systemWide[@"error_kind"], @"application_not_responding");
  XCTAssertEqualObjects(systemWide[@"error"], @"the application at the hit-test point did not answer in time");
  XCTAssertNil(systemWide[@"empty"], @"empty must not be set on a not-responding response");
}

- (void)testFailedHitTestIsAnOpaqueFailureCarryingTheReason
{
  _runtime.hitTestOutcome = [FBAXHitTestOutcome failed:@"AXUIElementCreateSystemWide returned NULL"];

  NSDictionary *response = FBAXBridgeHandleRequest(@{@"verb" : @"hittest", @"x" : @1, @"y" : @2});
  XCTAssertEqualObjects(response[@"ok"], @NO);
  XCTAssertEqualObjects(response[@"error"], @"AXUIElementCreateSystemWide returned NULL");
  XCTAssertNil(response[@"error_kind"], @"a reader failure must not be tagged as an unavailable application");
}

- (void)testHitElementThatCannotBeReadIsReportedFromTheReadOutcome
{
  _runtime.hitTestOutcome = [FBAXHitTestOutcome hit:[FBAXFakeElement applicationUnavailable]
                             owningProcessIdentifier:kAppPid];
  NSDictionary *unavailable = FBAXBridgeHandleRequest(@{@"verb" : @"hittest", @"x" : @1, @"y" : @2});
  XCTAssertEqualObjects(unavailable[@"error_kind"], @"application_unavailable");
  XCTAssertEqualObjects(unavailable[@"error"], @"pid 4321 has no accessibility server");
  XCTAssertEqualObjects(unavailable[@"pid"], @(kAppPid), @"the pid the hit-test attributed it to is still named");

  _runtime.hitTestOutcome = [FBAXHitTestOutcome hit:[FBAXFakeElement applicationNotResponding]
                             owningProcessIdentifier:kAppPid];
  NSDictionary *notResponding = FBAXBridgeHandleRequest(@{@"verb" : @"hittest", @"x" : @1, @"y" : @2});
  XCTAssertEqualObjects(notResponding[@"error_kind"], @"application_not_responding");
  XCTAssertEqualObjects(notResponding[@"error"], @"pid 4321 did not answer the read of the hit element in time");

  _runtime.hitTestOutcome = [FBAXHitTestOutcome hit:[FBAXFakeElement failed:FBAXTestsErrorWithCode(FBAXErrorInvalidUIElement)]
                             owningProcessIdentifier:kAppPid];
  NSDictionary *failed = FBAXBridgeHandleRequest(@{@"verb" : @"hittest", @"x" : @1, @"y" : @2});
  XCTAssertEqualObjects(failed[@"ok"], @NO);
  XCTAssertEqualObjects(failed[@"error"], @"failed to read the hit element");
  XCTAssertNil(failed[@"error_kind"]);
}

#pragma mark - The default frontmost method

- (void)testAFrontmostReadWithNoMethodAsksTheWindowServer
{
  _runtime.hitTestOutcome = [FBAXHitTestOutcome empty];
  _runtime.windowServerOutcome = [FBAXFrontmostOutcome resolved:kAppPid];
  _runtime.applicationElements[@(kAppPid)] = [FBAXFakeElement readable:@"UIApplication"];

  NSDictionary *response = FBAXBridgeHandleRequest(@{@"verb" : @"describe", @"x" : @201, @"y" : @437});
  XCTAssertEqualObjects(response[@"ok"], @YES);
  XCTAssertEqualObjects(response[@"pid"], @(kAppPid));
  XCTAssertEqualObjects(response[@"method"], @"window-server", @"the response names the resolver that ran");
  XCTAssertEqual(_runtime.windowServerCount, 1u);
  XCTAssertEqual(_runtime.hitTestCount, 0u, @"the anchor is not consulted for the authoritative frontmost");
}

#pragma mark - Raises while answering

- (void)testARaiseWhileAnsweringBecomesAResponseAndLeavesTheReaderAnswering
{
  _runtime.applicationElements[@(kAppPid)] = [FBAXFakeElement readable:@"UIApplication"];
  _runtime.readRaiseReason = @"the runtime went away mid-read";

  NSDictionary *raised = FBAXBridgeHandleRequest(@{@"verb" : @"describe", @"pid" : @(kAppPid)});
  XCTAssertEqualObjects(raised[@"ok"], @NO);
  XCTAssertTrue(
    [raised[@"error"] containsString:@"the runtime went away mid-read"],
    @"the response must carry what was raised: %@",
    raised[@"error"]
  );

  // The point of answering rather than aborting: the next request is still served.
  _runtime.readRaiseReason = nil;
  NSDictionary *after = FBAXBridgeHandleRequest(@{@"verb" : @"describe", @"pid" : @(kAppPid)});
  XCTAssertEqualObjects(after[@"ok"], @YES, @"the reader must still answer after a raise: %@", after);
}

#pragma mark - Request validation

// Arguments are rejected after the runtime is reached, hence the fake.
- (void)testMalformedArgumentsAreReportedAsABadRequest
{
  NSDictionary *hitTest = FBAXBridgeHandleRequest(@{@"verb" : @"hittest", @"x" : @"left", @"y" : @2});
  XCTAssertEqualObjects(hitTest[@"error"], @"hittest requires numeric x and y");
  XCTAssertEqualObjects(hitTest[@"error_kind"], @"bad_request");
  XCTAssertEqual(_runtime.hitTestCount, 0u, @"a rejected request must not reach the runtime");

  NSDictionary *describe = FBAXBridgeHandleRequest(@{@"verb" : @"describe"});
  XCTAssertEqualObjects(describe[@"error"], @"describe requires either a numeric pid or the frontmost anchor (x, y)");
  XCTAssertEqualObjects(describe[@"error_kind"], @"bad_request");
}

#pragma mark - The single-fetch read

// A fake element carrying `attributes`, with `children` beneath it.
static FBAXFakeElement *FBAXTestsNode(NSDictionary<NSString *, id> *attributes, NSArray<FBAXFakeElement *> *children)
{
  FBAXFakeElement *element = [FBAXFakeElement readable:@"UIView"];
  element.attributes = attributes;
  element.children = children;
  return element;
}

static NSDictionary *FBAXTestsSnapshotRequest(NSDictionary<NSString *, id> *extra)
{
  NSMutableDictionary *request =
  [@{@"verb" : @"describe", @"pid" : @(kAppPid), @"snapshotTree" : @YES} mutableCopy];
  [request addEntriesFromDictionary:extra];
  return request;
}

- (void)testTheSingleFetchReadCostsOneRoundTripForTheWholeTree
{
  _runtime.applicationElements[@(kAppPid)] = FBAXTestsNode(
    @{@"XC_kAXXCAttributeLabel" : @"root"},
    @[FBAXTestsNode(@{@"XC_kAXXCAttributeLabel" : @"a"}, @[]), FBAXTestsNode(@{@"XC_kAXXCAttributeLabel" : @"b"}, @[])]
  );

  NSDictionary *response = FBAXBridgeHandleRequest(FBAXTestsSnapshotRequest(@{}));
  XCTAssertEqualObjects(response[@"ok"], @YES, @"the single fetch must answer: %@", response);
  XCTAssertEqual(_runtime.snapshotCount, 1u, @"a three-node tree must cost exactly one fetch");
  XCTAssertEqualObjects(response[@"phases"][@"mach_round_trips"], @1);
}

// The fake numbers attributes differently from the runtime, so a hardcoded number would fail here.
- (void)testSnapshotAttributesAreMappedBackFromNumbersToNames
{
  _runtime.applicationElements[@(kAppPid)] =
  FBAXTestsNode(@{@"XC_kAXXCAttributeLabel" : @"Cancel", @"XC_kAXXCAttributeIdentifier" : @"cancel-button"}, @[]);

  NSDictionary *tree = FBAXBridgeHandleRequest(FBAXTestsSnapshotRequest(@{}))[@"tree"];
  XCTAssertEqualObjects(tree[@"XC_kAXXCAttributeLabel"], @"Cancel");
  XCTAssertEqualObjects(tree[@"XC_kAXXCAttributeIdentifier"], @"cancel-button");
  XCTAssertTrue(
    [_runtime.lastSnapshotAttributeNames containsObject:@"XC_kAXXCAttributeLabel"],
    @"the fetch must ask for the names the request resolved to, got: %@",
    _runtime.lastSnapshotAttributeNames
  );
}

// The snapshot also answers a children *attribute* of raw element references; only the nesting is usable.
- (void)testSnapshotChildrenComeFromTheNestingAndNotTheChildrenAttribute
{
  FBAXFakeElement *child = FBAXTestsNode(@{@"XC_kAXXCAttributeLabel" : @"child"}, @[]);
  FBAXFakeElement *root = FBAXTestsNode(
    @{@"XC_kAXXCAttributeLabel" : @"root", @"XC_kAXXCAttributeChildren" : @[@"a raw element reference"]},
    @[child]
  );
  _runtime.applicationElements[@(kAppPid)] = root;

  NSDictionary *tree = FBAXBridgeHandleRequest(FBAXTestsSnapshotRequest(@{}))[@"tree"];
  NSArray *children = tree[@"XC_kAXXCAttributeChildren"];
  XCTAssertEqual(children.count, 1u, @"children must come from the nesting: %@", children);
  XCTAssertEqualObjects(children.firstObject[@"XC_kAXXCAttributeLabel"], @"child");
}

// The pid of the process drawing a hosted subtree in the boundary tests below. Distinct from `kAppPid`
// is all that matters: the boundary predicate is ownership changing, not any particular value.
static const pid_t kRemotePid = 8765;

// A tree in which another process draws a subtree — the shape of a web view's page, a photo picker or an
// autofill sheet. The snapshot served by the host process names the boundary element and cannot
// serialize beneath it; the per-node walk crosses because the server bridges each walked read.
static FBAXFakeElement *FBAXTestsTreeWithProcessBoundary(void)
{
  FBAXFakeElement *link = FBAXTestsNode(@{@"XC_kAXXCAttributeLabel" : @"Example Domain"}, @[]);
  FBAXFakeElement *page = FBAXTestsNode(@{@"XC_kAXXCAttributeLabel" : @"web page"}, @[link]);
  FBAXFakeElement *boundary = FBAXTestsNode(@{@"XC_kAXXCAttributeLabel" : @"remote element"}, @[page]);
  FBAXFakeElement *webView = FBAXTestsNode(@{@"XC_kAXXCAttributeLabel" : @"web view"}, @[boundary]);
  FBAXFakeElement *root = FBAXTestsNode(@{@"XC_kAXXCAttributeLabel" : @"root"}, @[webView]);
  root.owningProcessIdentifier = kAppPid;
  webView.owningProcessIdentifier = kAppPid;
  boundary.owningProcessIdentifier = kRemotePid;
  page.owningProcessIdentifier = kRemotePid;
  link.owningProcessIdentifier = kRemotePid;
  return root;
}

// The boundary node in a single-fetch response of the tree above: root -> web view -> remote element.
static NSDictionary *FBAXTestsBoundaryNode(NSDictionary *response)
{
  NSArray *webViews = response[@"tree"][@"XC_kAXXCAttributeChildren"];
  return [webViews.firstObject[@"XC_kAXXCAttributeChildren"] firstObject];
}

// A snapshot stops where another process draws; the boundary arrives as a childless stub.
- (void)testTheSingleFetchReadContinuesAcrossAProcessBoundary
{
  _runtime.applicationElements[@(kAppPid)] = FBAXTestsTreeWithProcessBoundary();

  NSDictionary *response = FBAXBridgeHandleRequest(FBAXTestsSnapshotRequest(@{}));
  XCTAssertEqualObjects(response[@"ok"], @YES, @"the read must answer: %@", response);
  NSDictionary *boundary = FBAXTestsBoundaryNode(response);
  NSArray *hosted = boundary[@"XC_kAXXCAttributeChildren"];
  XCTAssertEqual(hosted.count, 1u, @"the hosted subtree must be beneath the boundary: %@", boundary);
  XCTAssertEqualObjects(hosted.firstObject[@"XC_kAXXCAttributeLabel"], @"web page");
  XCTAssertEqual(_runtime.snapshotCount, 2u, @"one fetch for the tree and one to continue across the boundary");
  XCTAssertEqualObjects(response[@"phases"][@"mach_round_trips"], @2);
  XCTAssertEqualObjects(response[@"truncated"], @NO);
}

- (void)testBothTraversalsAnswerTheSameDocumentAcrossAProcessBoundary
{
  _runtime.applicationElements[@(kAppPid)] = FBAXTestsTreeWithProcessBoundary();

  NSDictionary *walked = FBAXBridgeHandleRequest(@{@"verb" : @"describe", @"pid" : @(kAppPid)});
  NSDictionary *fetched = FBAXBridgeHandleRequest(FBAXTestsSnapshotRequest(@{}));
  XCTAssertEqualObjects(walked[@"ok"], @YES);
  XCTAssertEqualObjects(fetched[@"ok"], @YES);
  XCTAssertEqualObjects(walked[@"tree"], fetched[@"tree"]);
}

- (void)testAContinuationContinuesAcrossAFurtherBoundary
{
  FBAXFakeElement *innermost = FBAXTestsNode(@{@"XC_kAXXCAttributeLabel" : @"innermost"}, @[]);
  innermost.owningProcessIdentifier = 111;
  FBAXFakeElement *root = FBAXTestsTreeWithProcessBoundary();
  FBAXFakeElement *link = root.children.firstObject.children.firstObject.children.firstObject.children.firstObject;
  link.children = @[innermost];
  _runtime.applicationElements[@(kAppPid)] = root;

  NSDictionary *response = FBAXBridgeHandleRequest(FBAXTestsSnapshotRequest(@{}));
  XCTAssertEqualObjects(response[@"ok"], @YES, @"the read must answer: %@", response);
  XCTAssertEqual(_runtime.snapshotCount, 3u, @"each boundary costs its own continuation");
  NSString *rendered = [NSString stringWithFormat:@"%@", response[@"tree"]];
  XCTAssertTrue([rendered containsString:@"innermost"], @"the twice-hosted subtree must be in the tree: %@", rendered);
}

- (void)testAProcessBoundaryWhoseOwnerIsNotServingKeepsTheStub
{
  _runtime.applicationElements[@(kAppPid)] = FBAXTestsTreeWithProcessBoundary();
  _runtime.snapshotContinuationError = [NSError errorWithDomain:@"FBAXTests"
                                                           code:1
                                                       userInfo:@{NSLocalizedDescriptionKey : @"the owner is not serving"}];

  NSDictionary *response = FBAXBridgeHandleRequest(FBAXTestsSnapshotRequest(@{}));
  XCTAssertEqualObjects(response[@"ok"], @YES, @"a failed continuation must not fail the read: %@", response);
  NSDictionary *boundary = FBAXTestsBoundaryNode(response);
  XCTAssertEqualObjects(boundary[@"XC_kAXXCAttributeLabel"], @"remote element");
  XCTAssertEqual([boundary[@"XC_kAXXCAttributeChildren"] count], 0u, @"the stub stays childless: %@", boundary);
  XCTAssertEqual(_runtime.snapshotCount, 2u, @"the continuation must have been attempted");
  XCTAssertEqualObjects(response[@"truncated"], @NO);
}

- (void)testAProcessBoundaryAtTheDepthBoundReportsTruncationWithoutFetching
{
  _runtime.applicationElements[@(kAppPid)] = FBAXTestsTreeWithProcessBoundary();

  NSDictionary *response = FBAXBridgeHandleRequest(FBAXTestsSnapshotRequest(@{@"maxDepth" : @2}));
  XCTAssertEqualObjects(response[@"ok"], @YES);
  XCTAssertEqualObjects(response[@"truncated"], @YES, @"the hosted subtree is beyond the bound");
  XCTAssertEqual(_runtime.snapshotCount, 1u, @"nothing below the bound is worth a fetch");
}

- (void)testTheNodeBudgetHoldsAcrossAProcessBoundary
{
  _runtime.applicationElements[@(kAppPid)] = FBAXTestsTreeWithProcessBoundary();

  NSDictionary *response = FBAXBridgeHandleRequest(FBAXTestsSnapshotRequest(@{@"maxNodes" : @3}));
  XCTAssertEqualObjects(response[@"ok"], @YES);
  XCTAssertEqualObjects(response[@"truncated"], @YES, @"the hosted subtree must not fit in three nodes");
  NSDictionary *boundary = FBAXTestsBoundaryNode(response);
  XCTAssertEqualObjects(boundary[@"XC_kAXXCAttributeLabel"], @"remote element");
  XCTAssertEqual([boundary[@"XC_kAXXCAttributeChildren"] count], 0u, @"the budget ran out at the boundary: %@", boundary);
}

- (void)testTheSingleFetchReadHonoursTheDepthBound
{
  _runtime.applicationElements[@(kAppPid)] = FBAXTestsNode(
    @{@"XC_kAXXCAttributeLabel" : @"root"},
    @[FBAXTestsNode(@{@"XC_kAXXCAttributeLabel" : @"deep"}, @[])]
  );

  NSDictionary *response = FBAXBridgeHandleRequest(FBAXTestsSnapshotRequest(@{@"maxDepth" : @0}));
  XCTAssertEqualObjects(response[@"truncated"], @YES, @"a tree cut at the depth bound reports truncation");
  XCTAssertNil(response[@"tree"][@"XC_kAXXCAttributeChildren"], @"nothing below the bound is reported");
}

- (void)testTheSingleFetchReadHonoursTheNodeBudget
{
  _runtime.applicationElements[@(kAppPid)] = FBAXTestsNode(
    @{@"XC_kAXXCAttributeLabel" : @"root"},
    @[FBAXTestsNode(@{}, @[]), FBAXTestsNode(@{}, @[])]
  );

  // Two nodes of budget for a three-node tree: the root and one child fit, the second does not.
  NSDictionary *response = FBAXBridgeHandleRequest(FBAXTestsSnapshotRequest(@{@"maxNodes" : @2}));
  XCTAssertEqualObjects(response[@"truncated"], @YES);
  XCTAssertEqual([response[@"tree"][@"XC_kAXXCAttributeChildren"] count], 1u);
}

- (void)testARuntimeWithoutSnapshotSupportIsReportedRatherThanReadAsEmpty
{
  _runtime.applicationElements[@(kAppPid)] = FBAXTestsNode(@{@"XC_kAXXCAttributeLabel" : @"root"}, @[]);
  _runtime.snapshotError = [NSError errorWithDomain:@"FBAXBridgeSnapshot"
                                               code:1
                                           userInfo:@{NSLocalizedDescriptionKey : @"no userTestingSnapshotForElement:"}];

  NSDictionary *response = FBAXBridgeHandleRequest(FBAXTestsSnapshotRequest(@{}));
  XCTAssertEqualObjects(response[@"ok"], @NO);
  XCTAssertTrue(
    [response[@"error"] containsString:@"no userTestingSnapshotForElement:"],
    @"the response must carry why the fetch could not be performed: %@",
    response[@"error"]
  );
}

// The server answers NULL under kAXErrorSuccess when it will not accept the options.
- (void)testASnapshotThatAnswersNothingIsAFailureRatherThanAnEmptyTree
{
  _runtime.applicationElements[@(kAppPid)] = FBAXTestsNode(@{@"XC_kAXXCAttributeLabel" : @"root"}, @[]);
  _runtime.snapshotAnswersNothing = YES;

  NSDictionary *response = FBAXBridgeHandleRequest(FBAXTestsSnapshotRequest(@{}));
  XCTAssertEqualObjects(response[@"ok"], @NO);
  XCTAssertNil(response[@"tree"]);
}

// A snapshot answers frames as `AXValue`, not the `NSValue` the per-node walk answers with.
- (void)testASnapshotFrameIsUnwrappedFromAnAXValue
{
  _runtime.applicationElements[@(kAppPid)] =
  FBAXTestsNode(@{kAXFrame : [FBAXFakeRectValue withRect:CGRectMake(16, 293, 370, 52)]}, @[]);

  NSDictionary *frame = FBAXBridgeHandleRequest(FBAXTestsSnapshotRequest(@{}))[@"tree"][kAXFrame];
  XCTAssertEqualObjects(frame[@"X"], @16);
  XCTAssertEqualObjects(frame[@"Y"], @293);
  XCTAssertEqualObjects(frame[@"Width"], @370);
  XCTAssertEqualObjects(frame[@"Height"], @52);
}

// Named in the request because a default read does not ask for the visible point.
- (void)testASnapshotVisiblePointIsUnwrappedFromAnAXValue
{
  _runtime.applicationElements[@(kAppPid)] = FBAXTestsNode(
    @{
      kAXFrame : [FBAXFakeRectValue withRect:CGRectMake(16, 293, 370, 52)],
      kAXVisiblePoint : [FBAXFakePointValue withPoint:CGPointMake(201, 319)],
    },
    @[]
  );

  NSDictionary *tree = FBAXBridgeHandleRequest(
    FBAXTestsSnapshotRequest(@{@"attributes" : @[kAXFrame, kAXVisiblePoint]})
  )[@"tree"];
  XCTAssertEqualObjects(tree[kAXVisiblePoint][@"X"], @201);
  XCTAssertEqualObjects(tree[kAXVisiblePoint][@"Y"], @319);
  XCTAssertEqualObjects(tree[kAXFrame][@"X"], @16, @"the frame on the same node is unwrapped the same way");
}

- (void)testAnUnrecognisedFrameValueIsEmittedAsNull
{
  _runtime.applicationElements[@(kAppPid)] = FBAXTestsNode(@{kAXFrame : @"not a frame"}, @[]);

  id frame = FBAXBridgeHandleRequest(FBAXTestsSnapshotRequest(@{}))[@"tree"][kAXFrame];
  XCTAssertEqualObjects(frame, NSNull.null);
}

- (void)testAnUnrecognisedPointValueIsEmittedAsNull
{
  _runtime.applicationElements[@(kAppPid)] = FBAXTestsNode(@{kAXVisiblePoint : @"not a point"}, @[]);

  id point = FBAXBridgeHandleRequest(
    FBAXTestsSnapshotRequest(
      @{@"attributes" : @[kAXVisiblePoint]}
    )
  )[@"tree"][kAXVisiblePoint];
  XCTAssertEqualObjects(point, NSNull.null);
}

#pragma mark - Write outcomes

- (void)testWriteErrorClassification
{
  XCTAssertEqual([FBAXWriteOutcome outcomeForWriteError:FBAXErrorSuccess].status, FBAXWriteStatusWritten);
  XCTAssertEqual(
    [FBAXWriteOutcome outcomeForWriteError:FBAXErrorServerNotFound].status,
    FBAXWriteStatusApplicationUnavailable
  );

  // A timeout is the application being slow, not the application being gone — tagging it unavailable would
  // tell the host to stop retrying something that is still there. It is not a plain failure either: a plain
  // failure means the write did not happen, and a timeout does not say that.
  XCTAssertEqual(
    [FBAXWriteOutcome outcomeForWriteError:FBAXErrorIPCTimeout].status,
    FBAXWriteStatusApplicationNotResponding
  );

  // Every other code is opaque, and the diagnostic has to carry it: triage happens from the wire response
  // alone, and "the write failed" without the number says nothing actionable.
  FBAXWriteOutcome *rejected = [FBAXWriteOutcome outcomeForWriteError:-25201];
  XCTAssertEqual(rejected.status, FBAXWriteStatusFailed);
  XCTAssertTrue([rejected.failureReason containsString:@"-25201"], @"%@", rejected.failureReason);
}

// `FBAXSignatureWarnings` sweeps only ObjC selectors; a C entry point has nothing but this presence check.
- (void)testTheAXRuntimeWriteEntryPointsResolve
{
  XCTAssertTrue(dlopen(FBAXPathAXRuntime, RTLD_NOW) != NULL, @"AXRuntime could not be opened");
  XCTAssertTrue(dlsym(RTLD_DEFAULT, "AXUIElementPerformAction") != NULL);
  XCTAssertTrue(dlsym(RTLD_DEFAULT, "AXUIElementSetAttributeValue") != NULL);
}

// Optional in the live runtime; this asserts it is present today, not that the code requires it.
- (void)testTheAutomationModeReadEntryPointResolves
{
  XCTAssertTrue(dlopen(FBAXPathAXRuntime, RTLD_NOW) != NULL, @"AXRuntime could not be opened");
  XCTAssertTrue(dlsym(RTLD_DEFAULT, "_AXSAutomationEnabled") != NULL);
}

#pragma mark - Guest phase reporting

- (void)testADescribeReportsItsWalkAndRoundTripCount
{
  FBAXFakeElement *leaf = [FBAXFakeElement readable:@"UIButton"];
  FBAXFakeElement *root = [FBAXFakeElement readable:@"UIApplication"];
  root.children = @[leaf];
  _runtime.applicationElements[@(kAppPid)] = root;

  NSDictionary *response = FBAXBridgeHandleRequest(@{@"verb" : @"describe", @"pid" : @(kAppPid)});
  NSDictionary *phases = response[@"phases"];

  XCTAssertNotNil(phases, @"phases must be present on every describe response");
  XCTAssertEqualObjects(phases[@"mach_round_trips"], @2, @"one round trip per node, root plus leaf");
  XCTAssertNotNil(phases[@"traverse_ms"]);
  XCTAssertGreaterThanOrEqual([phases[@"traverse_ms"] doubleValue], 0.0);
}

#pragma mark - Automation mode on the describe path

// Absent is not false: a host that does not know the field must leave the device alone.
- (void)testAnAbsentAutomationFieldMutatesNothing
{
  _runtime.applicationElements[@(kAppPid)] = [FBAXFakeElement readable:@"UIApplication"];
  _runtime.automationMode = NO;

  NSDictionary *response = FBAXBridgeHandleRequest(@{@"verb" : @"describe", @"pid" : @(kAppPid)});

  XCTAssertEqualObjects(_runtime.automationModeWrites, @[], @"an absent field must not write");
  XCTAssertEqualObjects(response[@"automation"][@"enabled"], @NO, @"the state is still reported");
  XCTAssertEqualObjects(response[@"automation"][@"asserted"], @NO);
}

- (void)testRequestingAutomationModeWritesAndReportsAsserted
{
  _runtime.applicationElements[@(kAppPid)] = [FBAXFakeElement readable:@"UIApplication"];
  _runtime.automationMode = NO;

  NSDictionary *response =
  FBAXBridgeHandleRequest(@{@"verb" : @"describe", @"pid" : @(kAppPid), @"automationMode" : @YES});

  XCTAssertEqualObjects(_runtime.automationModeWrites, @[@YES]);
  XCTAssertEqualObjects(response[@"automation"][@"enabled"], @YES);
  XCTAssertEqualObjects(response[@"automation"][@"asserted"], @YES, @"this read changed the device");
}

- (void)testRequestingAModeTheDeviceIsAlreadyInWritesNothing
{
  _runtime.applicationElements[@(kAppPid)] = [FBAXFakeElement readable:@"UIApplication"];
  _runtime.automationMode = YES;

  NSDictionary *response =
  FBAXBridgeHandleRequest(@{@"verb" : @"describe", @"pid" : @(kAppPid), @"automationMode" : @YES});

  XCTAssertEqualObjects(_runtime.automationModeWrites, @[], @"nothing to change, so nothing is written");
  XCTAssertEqualObjects(response[@"automation"][@"enabled"], @YES);
  XCTAssertEqualObjects(response[@"automation"][@"asserted"], @NO, @"it was already in that mode");
}

- (void)testRequestingAutomationModeOffTurnsItOff
{
  _runtime.applicationElements[@(kAppPid)] = [FBAXFakeElement readable:@"UIApplication"];
  _runtime.automationMode = YES;

  NSDictionary *response =
  FBAXBridgeHandleRequest(@{@"verb" : @"describe", @"pid" : @(kAppPid), @"automationMode" : @NO});

  XCTAssertEqualObjects(_runtime.automationModeWrites, @[@NO]);
  XCTAssertEqualObjects(response[@"automation"][@"enabled"], @NO);
  XCTAssertEqualObjects(response[@"automation"][@"asserted"], @YES);
}

// A preference write can be accepted and silently not apply.
- (void)testFailedAutomationModeWriteReportsAssertedFalse
{
  _runtime.applicationElements[@(kAppPid)] = [FBAXFakeElement readable:@"UIApplication"];
  _runtime.automationMode = NO;
  _runtime.automationModeWriteFails = YES;

  NSDictionary *response =
  FBAXBridgeHandleRequest(@{@"verb" : @"describe", @"pid" : @(kAppPid), @"automationMode" : @YES});

  XCTAssertEqualObjects(_runtime.automationModeWrites, @[@YES], @"the write was attempted");
  XCTAssertEqualObjects(response[@"automation"][@"enabled"], @NO, @"enabled reads back NO after the failed write");
  XCTAssertEqualObjects(response[@"automation"][@"asserted"], @NO, @"asserted is NO when the write did not take");
}

#pragma mark - Write dispatch

// Seeds the hit-test so a point-addressed write lands on an element reporting `attributes`, and hands the
// element back so a test can assert the write acted on that one.
- (FBAXFakeElement *)seedHitElementWithAttributes:(NSDictionary<NSString *, id> *)attributes
{
  FBAXFakeElement *element = [FBAXFakeElement new];
  element.attributes = attributes;
  _runtime.hitTestOutcome = [FBAXHitTestOutcome hit:element owningProcessIdentifier:kAppPid];
  return element;
}

static NSDictionary *FBAXTestsPress(void)
{
  return @{@"verb" : @"perform", @"x" : @1, @"y" : @2, @"action" : @"press"};
}

- (void)testEveryActionNameReachesTheRuntimeAsItsSemanticAction
{
  NSDictionary<NSString *, NSNumber *> *actions = @{
    @"press" : @(FBAXActionPress),
    @"scroll-up" : @(FBAXActionScrollUp),
    @"scroll-down" : @(FBAXActionScrollDown),
    @"scroll-left" : @(FBAXActionScrollLeft),
    @"scroll-right" : @(FBAXActionScrollRight),
    @"scroll-to-visible" : @(FBAXActionScrollToVisible),
  };
  NSUInteger performed = 0;
  for (NSString *name in actions) {
    [self seedHitElementWithAttributes:@{}];
    NSDictionary *response =
    FBAXBridgeHandleRequest(@{@"verb" : @"perform", @"x" : @10, @"y" : @20, @"action" : name});
    XCTAssertEqualObjects(response[@"ok"], @YES, @"%@", name);
    XCTAssertEqualObjects(response[@"pid"], @(kAppPid), @"%@", name);
    performed++;
    XCTAssertEqual(_runtime.performCount, performed, @"%@ must reach the runtime", name);
    XCTAssertEqual((NSUInteger)_runtime.lastPerformedAction, actions[name].unsignedIntegerValue, @"%@", name);
  }
}

- (void)testUnknownActionIsRejectedWithoutReachingTheRuntime
{
  [self seedHitElementWithAttributes:@{}];
  for (id action in @[@"pres", @"AXPress", @"", @123, NSNull.null]) {
    NSDictionary *response =
    FBAXBridgeHandleRequest(@{@"verb" : @"perform", @"x" : @1, @"y" : @2, @"action" : action});
    XCTAssertEqualObjects(response[@"ok"], @NO, @"%@", action);
    XCTAssertTrue([response[@"error"] hasPrefix:@"unsupported action:"], @"%@", response[@"error"]);
  }
  XCTAssertEqualObjects(
    FBAXBridgeHandleRequest(@{@"verb" : @"perform", @"x" : @1, @"y" : @2})[@"error"],
    @"unsupported action: (nil)"
  );
  XCTAssertEqual(_runtime.hitTestCount, 0, @"a request that cannot be understood must not reach the application");
  XCTAssertEqual(_runtime.performCount, 0);
}

- (void)testAWriteRequiresNumericCoordinates
{
  [self seedHitElementWithAttributes:@{}];
  NSArray<NSDictionary *> *requests = @[
    @{@"verb" : @"perform", @"action" : @"press"},
    @{@"verb" : @"perform", @"action" : @"press", @"x" : @1},
    @{@"verb" : @"perform", @"action" : @"press", @"x" : @"1", @"y" : @2},
    @{@"verb" : @"setvalue", @"value" : @"hello"},
    @{@"verb" : @"setvalue", @"value" : @"hello", @"x" : @1, @"y" : NSNull.null},
  ];
  for (NSDictionary *request in requests) {
    NSDictionary *response = FBAXBridgeHandleRequest(request);
    XCTAssertEqualObjects(response[@"ok"], @NO, @"%@", request);
    XCTAssertEqualObjects(response[@"error"], @"a write requires numeric x and y", @"%@", request);
  }
  XCTAssertEqual(_runtime.hitTestCount, 0);
}

- (void)testAWriteOnEmptySpaceIsASuccessfulEmptyResult
{
  _runtime.hitTestOutcome = [FBAXHitTestOutcome empty];
  NSArray<NSDictionary *> *requests = @[
    FBAXTestsPress(),
    @{@"verb" : @"setvalue", @"x" : @1, @"y" : @2, @"value" : @"hello"},
  ];
  for (NSDictionary *request in requests) {
    NSDictionary *response = FBAXBridgeHandleRequest(request);
    XCTAssertEqualObjects(response[@"ok"], @YES, @"%@", request[@"verb"]);
    XCTAssertEqualObjects(response[@"empty"], @YES, @"%@", request[@"verb"]);
    XCTAssertNil(response[@"error"], @"%@", request[@"verb"]);
  }
  XCTAssertEqual(_runtime.performCount, 0, @"nothing at the point means nothing to write to");
  XCTAssertEqual(_runtime.setValueCount, 0);
}

- (void)testAWriteToAnUnavailableApplicationIsTaggedAndNamesThePidWhenKnown
{
  _runtime.hitTestOutcome = [FBAXHitTestOutcome applicationUnavailable];
  NSDictionary *unhit = FBAXBridgeHandleRequest(FBAXTestsPress());
  XCTAssertEqualObjects(unhit[@"ok"], @NO);
  XCTAssertEqualObjects(unhit[@"error_kind"], @"application_unavailable");
  XCTAssertEqualObjects(unhit[@"error"], @"no accessibility server answered the write");

  [self seedHitElementWithAttributes:@{}];
  _runtime.writeOutcome = [FBAXWriteOutcome applicationUnavailable];
  NSDictionary *died = FBAXBridgeHandleRequest(FBAXTestsPress());
  XCTAssertEqualObjects(died[@"error_kind"], @"application_unavailable");
  XCTAssertEqualObjects(died[@"error"], @"pid 4321 has no accessibility server to accept the write");
}

// No element populates `XC_kAXXCAttributeUserTestingActions`, so there is no pre-check on it.
- (void)testAnActionIsPerformedWhateverTheElementAdvertises
{
  for (id advertised in @[@[@"AXScrollToVisible"], @[], NSNull.null]) {
    [self seedHitElementWithAttributes:@{@"XC_kAXXCAttributeUserTestingActions" : advertised}];
    XCTAssertEqualObjects(FBAXBridgeHandleRequest(FBAXTestsPress())[@"ok"], @YES, @"%@", advertised);
  }
  XCTAssertEqual(_runtime.performCount, 3);
}

- (void)testAnAssertionThatDoesNotMatchRefusesTheWrite
{
  [self seedHitElementWithAttributes:@{kAXLabel : @"Wi-Fi"}];

  NSDictionary *response = FBAXBridgeHandleRequest(
    @{
      @"verb" : @"perform",
      @"x" : @200,
      @"y" : @711,
      @"action" : @"press",
      @"assertKey" : kAXLabel,
      @"assertValue" : @"General",
    }
  );
  XCTAssertEqualObjects(response[@"ok"], @NO);
  XCTAssertEqualObjects(response[@"error_kind"], @"assertion_failed");
  XCTAssertEqualObjects(
    response[@"error"],
    @"the element at (200.0, 711.0) has XC_kAXXCAttributeLabel Wi-Fi, expected General"
  );
  XCTAssertEqual(_runtime.performCount, 0, @"a write must not land on an element that is not the one named");
}

- (void)testAnAssertionThatMatchesAllowsTheWrite
{
  [self seedHitElementWithAttributes:@{kAXLabel : @"General"}];

  NSDictionary *pressed = FBAXBridgeHandleRequest(
    @{
      @"verb" : @"perform",
      @"x" : @1,
      @"y" : @2,
      @"action" : @"press",
      @"assertKey" : kAXLabel,
      @"assertValue" : @"General",
    }
  );
  XCTAssertEqualObjects(pressed[@"ok"], @YES);
  XCTAssertEqual(_runtime.performCount, 1);

  NSDictionary *written = FBAXBridgeHandleRequest(
    @{
      @"verb" : @"setvalue",
      @"x" : @1,
      @"y" : @2,
      @"value" : @"hello",
      @"assertKey" : kAXLabel,
      @"assertValue" : @"General",
    }
  );
  XCTAssertEqualObjects(written[@"ok"], @YES, @"the assertion is not specific to one write verb");
  XCTAssertEqual(_runtime.setValueCount, 1);
}

- (void)testAnAssertionKeyAndValueAreOnlyMeaningfulTogether
{
  [self seedHitElementWithAttributes:@{kAXLabel : @"General"}];
  for (NSDictionary *partial in @[@{@"assertKey" : kAXLabel}, @{@"assertValue" : @"General"}]) {
    NSMutableDictionary *request = [FBAXTestsPress() mutableCopy];
    [request addEntriesFromDictionary:partial];
    NSDictionary *response = FBAXBridgeHandleRequest(request);
    XCTAssertEqualObjects(response[@"ok"], @NO, @"%@", partial);
    XCTAssertEqualObjects(response[@"error"], @"assertKey and assertValue are only meaningful together");
  }
  XCTAssertEqual(_runtime.hitTestCount, 0);
}

- (void)testAnAssertionOnAnAttributeTheReaderDoesNotFetchIsRejected
{
  [self seedHitElementWithAttributes:@{kAXLabel : @"General"}];
  NSMutableDictionary *request = [FBAXTestsPress() mutableCopy];
  request[@"assertKey"] = @"XC_kAXXCAttributeTraits";
  request[@"assertValue"] = @"button";

  NSDictionary *response = FBAXBridgeHandleRequest(request);
  XCTAssertEqualObjects(response[@"ok"], @NO);
  XCTAssertEqualObjects(response[@"error"], @"XC_kAXXCAttributeTraits is not an attribute a write can assert on");
  XCTAssertEqual(_runtime.hitTestCount, 0);
}

- (void)testSetValueSendsTheValueAndTheHitElementToTheRuntime
{
  FBAXFakeElement *element = [self seedHitElementWithAttributes:@{kAXLabel : @"Name"}];

  NSDictionary *response =
  FBAXBridgeHandleRequest(@{@"verb" : @"setvalue", @"x" : @30, @"y" : @40, @"value" : @"hello"});
  XCTAssertEqualObjects(response[@"ok"], @YES);
  XCTAssertEqualObjects(response[@"pid"], @(kAppPid));
  XCTAssertEqual(_runtime.setValueCount, 1);
  XCTAssertEqualObjects(_runtime.lastWrittenValue, @"hello");
  XCTAssertEqualObjects(_runtime.lastWrittenElement, element, @"the write must act on the element the hit-test found");
  XCTAssertEqual(_runtime.performCount, 0, @"a set-value is not an action");
}

- (void)testSetValueRequiresAStringValue
{
  [self seedHitElementWithAttributes:@{}];
  for (id value in @[@123, @[@"hello"], @{@"a" : @1}, NSNull.null]) {
    NSDictionary *response = FBAXBridgeHandleRequest(@{@"verb" : @"setvalue", @"x" : @1, @"y" : @2, @"value" : value});
    XCTAssertEqualObjects(response[@"ok"], @NO, @"%@", [value class]);
    XCTAssertEqualObjects(response[@"error"], @"setvalue requires a string value", @"%@", [value class]);
  }
  XCTAssertEqualObjects(
    FBAXBridgeHandleRequest(@{@"verb" : @"setvalue", @"x" : @1, @"y" : @2})[@"error"],
    @"setvalue requires a string value"
  );
  XCTAssertEqual(_runtime.hitTestCount, 0);
  XCTAssertEqual(_runtime.setValueCount, 0);
}

- (void)testAFailedWriteIsAnOpaqueFailureCarryingTheRuntimeReason
{
  [self seedHitElementWithAttributes:@{}];
  _runtime.writeOutcome = [FBAXWriteOutcome failed:@"the application did not answer the write in time"];

  NSDictionary *response = FBAXBridgeHandleRequest(FBAXTestsPress());
  XCTAssertEqualObjects(response[@"ok"], @NO);
  XCTAssertEqualObjects(response[@"error"], @"the application did not answer the write in time");
  XCTAssertNil(response[@"error_kind"]);
}

- (void)testAWriteWithAnExplicitPidScopesTheHitTest
{
  [self seedHitElementWithAttributes:@{}];
  NSMutableDictionary *request = [FBAXTestsPress() mutableCopy];
  request[@"pid"] = @(kAppPid);

  XCTAssertEqualObjects(FBAXBridgeHandleRequest(request)[@"ok"], @YES);
  XCTAssertEqual(_runtime.lastHitTestProcessIdentifier, kAppPid);

  XCTAssertEqualObjects(FBAXBridgeHandleRequest(FBAXTestsPress())[@"ok"], @YES);
  XCTAssertEqual(_runtime.lastHitTestProcessIdentifier, 0, @"no pid means a display-wide hit-test");
}

#pragma mark - Attribute value coercion

- (void)testPointValuedAttributeIsCarriedThroughStructurally
{
  NSDictionary *point = @{@"X" : @201, @"Y" : @789.5};
  FBAXFakeElement *root = [FBAXFakeElement readable:@"UIApplication"];
  root.attributes = @{kAXElementType : @"UIApplication", kAXVisiblePoint : point};
  _runtime.applicationElements[@(kAppPid)] = root;

  id emitted = FBAXBridgeHandleRequest(@{@"verb" : @"describe", @"pid" : @(kAppPid)})[@"tree"][kAXVisiblePoint];
  XCTAssertTrue([emitted isKindOfClass:NSDictionary.class], @"a point stays structured, got %@", [emitted class]);
  XCTAssertEqualObjects(emitted[@"X"], @201);
  XCTAssertEqualObjects(emitted[@"Y"], @789.5);
}

- (void)testTheFrameAttributeIsCarriedThroughStructurally
{
  FBAXFakeElement *root = [FBAXFakeElement readable:@"UIApplication"];
  root.attributes = @{
    kAXElementType : @"UIApplication",
    kAXFrame : @{@"X" : @0, @"Y" : @791, @"Width" : @402, @"Height" : @83},
  };
  _runtime.applicationElements[@(kAppPid)] = root;

  id emitted = FBAXBridgeHandleRequest(@{@"verb" : @"describe", @"pid" : @(kAppPid)})[@"tree"][kAXFrame];
  XCTAssertTrue([emitted isKindOfClass:NSDictionary.class], @"the frame stays structured, got %@", [emitted class]);
  XCTAssertEqualObjects(emitted[@"Width"], @402);
}

// XCTest's reader returns an `NSError` as the attribute's value for any AX failure other than no-value or
// unsupported.
- (void)testAnAttributeThatFailedToReadIsEmittedAsItsValue
{
  NSError *failure = [NSError
                      errorWithDomain:@"AXError"
                      code:-25204
                      userInfo:@{NSLocalizedDescriptionKey : @"kAXErrorCannotComplete"}];
  FBAXFakeElement *root = [FBAXFakeElement readable:@"UIApplication"];
  root.attributes = @{kAXElementType : @"UIApplication", kAXLabel : failure};
  _runtime.applicationElements[@(kAppPid)] = root;

  NSDictionary *tree = FBAXBridgeHandleRequest(@{@"verb" : @"describe", @"pid" : @(kAppPid)})[@"tree"];
  XCTAssertEqualObjects(tree[kAXLabel], NSNull.null, @"a failure is not the attribute's value");
  XCTAssertEqualObjects(
    tree[@"FBAttributeReadFailures"][kAXLabel],
    @"kAXErrorCannotComplete",
    @"the failed key is named with its reason rather than silently reading as no value"
  );
}

#pragma mark - The translator vocabulary seam

- (void)testATranslatorReadOfALeafAtTheDepthCapDoesNotReportTruncation
{
  FBAXFakeElement *root = [FBAXFakeElement readable:@"UIApplication"];
  root.attributes = @{kAXElementType : @"UIApplication"};
  _runtime.applicationElements[@(kAppPid)] = root;
  _runtime.translatorAttributeValues = @{@(FBAXPAttributeLabel) : @"Settings"};

  NSDictionary *response = FBAXBridgeHandleRequest(
    @{
      @"verb" : @"describe",
      @"pid" : @(kAppPid),
      @"translatorVocabulary" : @YES,
      @"maxDepth" : @0,
    }
  );

  XCTAssertEqualObjects(
    response[@"truncated"],
    @NO,
    @"truncated is NO when the depth cap cut nothing"
  );
}

- (void)testATranslatorWalkCostsTwoRoundTripsPerNode
{
  FBAXFakeElement *root = [FBAXFakeElement readable:@"UIApplication"];
  root.attributes = @{kAXElementType : @"UIApplication"};
  _runtime.applicationElements[@(kAppPid)] = root;
  _runtime.translatorAttributeValues = @{
    @(FBAXPAttributeLabel) : @"Settings",
    @(FBAXPAttributeChildren) : @[[FBAXFakeElement readable:@"UIView"], [FBAXFakeElement readable:@"UIView"]],
  };

  FBAXBridgeHandleRequest(
    @{
      @"verb" : @"describe",
      @"pid" : @(kAppPid),
      @"translatorVocabulary" : @YES,
      @"maxDepth" : @1,
    }
  );

  // Three nodes: the root and its two children. Two requests each — one batch of attributes, one for
  // children, which the handler special-cases out of the batch and so cannot be folded into it.
  XCTAssertEqual(_runtime.translatorReadCount, 6u);
}

- (void)testATranslatorReadEmitsTheEnabledAnswerItFetched
{
  _runtime.applicationElements[@(kAppPid)] = [FBAXFakeElement readable:@"UIApplication"];
  _runtime.translatorAttributeValues = @{@(FBAXPAttributeLabel) : @"General", @(FBAXPAttributeIsEnabled) : @NO};

  NSDictionary *response =
  FBAXBridgeHandleRequest(@{@"verb" : @"describe", @"pid" : @(kAppPid), @"translatorVocabulary" : @YES});

  XCTAssertEqualObjects(response[@"ok"], @YES);
  XCTAssertEqualObjects(response[@"tree"][kNodeIsEnabled], @NO, @"the fetched enabled answer must reach the wire");
}

- (void)testATranslatorReadEmitsTheTranslatorsOwnRoleUnmapped
{
  _runtime.applicationElements[@(kAppPid)] = [FBAXFakeElement readable:@"UIApplication"];
  _runtime.translatorAttributeValues = @{@(FBAXPAttributeRole) : @9};

  NSDictionary *tree =
  FBAXBridgeHandleRequest(@{@"verb" : @"describe", @"pid" : @(kAppPid), @"translatorVocabulary" : @YES})[@"tree"];

  XCTAssertEqualObjects(tree[kNodeTranslatorRole], @9);
  XCTAssertNil(tree[kAXElementType], @"the translator role must not be emitted under the elementType key");
}

// The host derives `interactable` from the XCTest key, so the point must land under it.
- (void)testATranslatorReadEmitsTheVisiblePoint
{
  _runtime.applicationElements[@(kAppPid)] = [FBAXFakeElement readable:@"UIApplication"];
  _runtime.translatorAttributeValues = @{
    @(FBAXPAttributeVisiblePoint) : [NSValue valueWithCGPoint:CGPointMake(201, 311)],
  };

  NSDictionary *tree =
  FBAXBridgeHandleRequest(@{@"verb" : @"describe", @"pid" : @(kAppPid), @"translatorVocabulary" : @YES})[@"tree"];

  XCTAssertEqualObjects(tree[@"XC_kAXXCAttributeVisiblePoint"][@"X"], @201);
  XCTAssertEqualObjects(tree[@"XC_kAXXCAttributeVisiblePoint"][@"Y"], @311);
}

- (void)testATranslatorReadEmitsTheTraitsBitmask
{
  _runtime.applicationElements[@(kAppPid)] = [FBAXFakeElement readable:@"UIApplication"];
  _runtime.translatorAttributeValues = @{@(FBAXPAttributeTraits) : @(1 << 6)};

  NSDictionary *tree =
  FBAXBridgeHandleRequest(@{@"verb" : @"describe", @"pid" : @(kAppPid), @"translatorVocabulary" : @YES})[@"tree"];

  XCTAssertEqualObjects(tree[@"FBTraits"], @(1 << 6));
}

- (void)testATranslatorReadEmitsAPerElementIdentity
{
  _runtime.applicationElements[@(kAppPid)] = [FBAXFakeElement readable:@"UIApplication"];
  _runtime.translatorAttributeValues = @{@(FBAXPAttributeMemoryAddress) : @(0x600001234560)};

  NSDictionary *tree =
  FBAXBridgeHandleRequest(@{@"verb" : @"describe", @"pid" : @(kAppPid), @"translatorVocabulary" : @YES})[@"tree"];

  XCTAssertEqualObjects(tree[@"FBElementIdentity"], @(0x600001234560));
}

- (void)testATranslatorReadThatCannotBePerformedIsAFailureNotAnEmptyTree
{
  _runtime.applicationElements[@(kAppPid)] = [FBAXFakeElement readable:@"UIApplication"];
  _runtime.translatorAttributeValues = nil;

  NSDictionary *response =
  FBAXBridgeHandleRequest(@{@"verb" : @"describe", @"pid" : @(kAppPid), @"translatorVocabulary" : @YES});

  XCTAssertEqualObjects(response[@"ok"], @NO);
  XCTAssertNil(response[@"tree"], @"a read that could not be performed must not answer with a tree");
}

// The translator answers synthesized defaults for a pid that names no process; only the availability
// probe fails this.
- (void)testATranslatorReadOfAnUnavailableApplicationFailsRatherThanFabricatingARoot
{
  _runtime.applicationElements[@(kAppPid)] = [FBAXFakeElement applicationUnavailable];
  _runtime.translatorAttributeValues = @{@(FBAXPAttributeRole) : @1, @(FBAXPAttributeIsEnabled) : @YES};

  NSDictionary *response =
  FBAXBridgeHandleRequest(@{@"verb" : @"describe", @"pid" : @(kAppPid), @"translatorVocabulary" : @YES});

  XCTAssertEqualObjects(response[@"ok"], @NO);
  XCTAssertEqualObjects(response[@"error_kind"], @"application_unavailable");
  XCTAssertNil(response[@"tree"], @"a process with no accessibility server must not answer with a root");
}

- (void)testAFusedFrontmostTranslatorReadStillNamesTheResolverThatRan
{
  _runtime.windowServerOutcome = [FBAXFrontmostOutcome resolved:kAppPid];
  _runtime.applicationElements[@(kAppPid)] = [FBAXFakeElement readable:@"UIApplication"];
  _runtime.translatorAttributeValues = @{@(FBAXPAttributeLabel) : @"SampleApp"};

  NSDictionary *response =
  FBAXBridgeHandleRequest(@{@"verb" : @"describe", @"x" : @201, @"y" : @437, @"translatorVocabulary" : @YES});

  XCTAssertEqualObjects(response[@"ok"], @YES);
  XCTAssertEqualObjects(response[@"pid"], @(kAppPid));
  XCTAssertEqualObjects(response[@"method"], @"window-server");
}

#pragma mark - Request-named attributes

// The fake echoes what it holds, so only the ask can be asserted.
- (void)testARequestNamingAttributesIsReadWithThem
{
  FBAXFakeElement *root = [FBAXFakeElement readable:@"UIApplication"];
  _runtime.applicationElements[@(kAppPid)] = root;

  FBAXBridgeHandleRequest(
    @{
      @"verb" : @"describe",
      @"pid" : @(kAppPid),
      @"attributes" : @[kAXLabel, kAXVisiblePoint],
    }
  );
  XCTAssertEqualObjects(_runtime.lastReadAttributes, (@[kAXLabel, kAXVisiblePoint, kAXChildren]));
}

- (void)testARequestNamingNoAttributesIsReadWithTheDefaultList
{
  _runtime.applicationElements[@(kAppPid)] = [FBAXFakeElement readable:@"UIApplication"];

  FBAXBridgeHandleRequest(@{@"verb" : @"describe", @"pid" : @(kAppPid)});
  XCTAssertEqualObjects(
    _runtime.lastReadAttributes,
    (@[
      @"XC_kAXXCAttributeElementType", @"XC_kAXXCAttributeElementBaseType", kAXLabel,
      @"XC_kAXXCAttributeValue", @"XC_kAXXCAttributeIdentifier", kAXFrame,
      @"XC_kAXXCAttributeAutomationType", kAXChildren,
      ])
  );
}

- (void)testTheChildrenAttributeIsAlwaysRead
{
  FBAXFakeElement *root = [FBAXFakeElement readable:@"UIApplication"];
  root.children = @[[FBAXFakeElement readable:@"XCUIElementTypeWindow"]];
  _runtime.applicationElements[@(kAppPid)] = root;

  NSDictionary *response =
  FBAXBridgeHandleRequest(@{@"verb" : @"describe", @"pid" : @(kAppPid), @"attributes" : @[kAXLabel]});
  XCTAssertTrue([_runtime.lastReadAttributes containsObject:kAXChildren], @"children is always read");
  XCTAssertEqualObjects(response[@"tree"][kAXChildren][0][kAXElementType], @"XCUIElementTypeWindow");
}

- (void)testAMalformedAttributeListFallsBackToTheDefault
{
  _runtime.applicationElements[@(kAppPid)] = [FBAXFakeElement readable:@"UIApplication"];
  NSUInteger defaultCount = 8;

  for (id malformed in @[@"XC_kAXXCAttributeLabel", @[], @[@123], @{@"a" : @1}]) {
    FBAXBridgeHandleRequest(@{@"verb" : @"describe", @"pid" : @(kAppPid), @"attributes" : malformed});
    XCTAssertEqual(_runtime.lastReadAttributes.count, defaultCount, @"a %@ list falls back", [malformed class]);
  }

  FBAXBridgeHandleRequest(
    @{
      @"verb" : @"describe",
      @"pid" : @(kAppPid),
      @"attributes" : @[kAXLabel, @123, kAXVisiblePoint],
    }
  );
  XCTAssertEqualObjects(
    _runtime.lastReadAttributes,
    (@[kAXLabel, kAXVisiblePoint, kAXChildren]),
    @"a non-string member is dropped and the rest survives"
  );
}

- (void)testAWriteCanAssertOnlyOnAnAttributeItNames
{
  _runtime.hitTestOutcome = [FBAXHitTestOutcome hit:[FBAXFakeElement readable:@"XCUIElementTypeButton"]
                             owningProcessIdentifier:kAppPid];

  NSDictionary *unnamed = FBAXBridgeHandleRequest(
    @{
      @"verb" : @"perform", @"x" : @10, @"y" : @20, @"action" : @"press",
      @"assertKey" : kAXVisiblePoint, @"assertValue" : @"anything",
    }
  );
  XCTAssertEqualObjects(unnamed[@"ok"], @NO, @"an unfetched key is not assertable");
  XCTAssertEqualObjects(unnamed[@"error_kind"], @"bad_request");

  NSDictionary *named = FBAXBridgeHandleRequest(
    @{
      @"verb" : @"perform", @"x" : @10, @"y" : @20, @"action" : @"press",
      @"attributes" : @[kAXVisiblePoint],
      @"assertKey" : kAXVisiblePoint, @"assertValue" : @"anything",
    }
  );
  XCTAssertNotEqualObjects(named[@"error_kind"], @"bad_request", @"naming the key makes it assertable");
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
  XCTAssertEqualObjects(response[@"pid"], @(kAppPid));
}

- (void)testDescribeOfARootThatDidNotAnswerIsTaggedNotResponding
{
  _runtime.applicationElements[@(kAppPid)] = [FBAXFakeElement applicationNotResponding];

  NSDictionary *response = FBAXBridgeHandleRequest(@{@"verb" : @"describe", @"pid" : @(kAppPid)});
  XCTAssertEqualObjects(response[@"ok"], @NO);
  XCTAssertEqualObjects(response[@"error_kind"], @"application_not_responding");
  XCTAssertEqualObjects(response[@"error"], @"pid 4321 did not answer the read of its element tree in time");
  XCTAssertEqualObjects(response[@"pid"], @(kAppPid));
}

- (void)testDescribeOfAFailedRootQuotesTheRuntimeOrSaysItReportedNothing
{
  _runtime.applicationElements[@(kAppPid)] = [FBAXFakeElement failed:FBAXTestsErrorWithCode(FBAXErrorInvalidUIElement)];
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

- (void)testCenterPointResolvesTheAnchorsOwnerAndIsEchoedBack
{
  _runtime.hitTestOutcome = [FBAXHitTestOutcome hit:[FBAXFakeElement readable:@"leaf"] owningProcessIdentifier:kAppPid];
  _runtime.applicationElements[@(kAppPid)] = [FBAXFakeElement readable:@"UIApplication"];

  NSDictionary *response = FBAXBridgeHandleRequest(
    @{@"verb" : @"describe", @"x" : @201, @"y" : @437, @"method" : @"center-point"}
  );
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

- (void)testAFailedResolverDoesNotFallBackToAnotherMethod
{
  _runtime.windowServerOutcome = [FBAXFrontmostOutcome unresolved:@"the window server did not answer"];
  _runtime.hitTestOutcome = [FBAXHitTestOutcome hit:[FBAXFakeElement readable:@"leaf"] owningProcessIdentifier:kAppPid];
  _runtime.applicationElements[@(kAppPid)] = [FBAXFakeElement readable:@"UIApplication"];

  NSDictionary *response =
  FBAXBridgeHandleRequest(@{@"verb" : @"describe", @"x" : @1, @"y" : @2, @"method" : @"window-server"});
  XCTAssertEqualObjects(response[@"ok"], @NO);
  XCTAssertEqualObjects(response[@"error"], @"the window server did not answer");
  // A strategy that could not answer is about the strategy, not about any one application — so it is its
  // own kind, and must not be reported as an application the caller should go and reconfigure.
  XCTAssertEqualObjects(response[@"error_kind"], @"frontmost_unresolved");
  XCTAssertEqual(_runtime.hitTestCount, 0u, @"no fallback to the positional resolver");
  XCTAssertEqual(_runtime.runningBoardCount, 0u, @"no fallback to RunningBoard");
}

- (void)testCenterPointCarriesEachNonResolvingOutcomeThroughAsItsOwnKind
{
  _runtime.hitTestOutcome = [FBAXHitTestOutcome empty];
  NSDictionary *empty = FBAXBridgeHandleRequest(
    @{@"verb" : @"describe", @"x" : @9999, @"y" : @9999, @"method" : @"center-point"}
  );
  XCTAssertEqualObjects(empty[@"ok"], @NO);
  XCTAssertEqualObjects(empty[@"error"], @"system-wide hit-test at (9999.0, 9999.0) found no element");
  XCTAssertEqualObjects(empty[@"error_kind"], @"frontmost_unresolved");

  _runtime.hitTestOutcome = [FBAXHitTestOutcome applicationUnavailable];
  NSDictionary *unavailable = FBAXBridgeHandleRequest(
    @{@"verb" : @"describe", @"x" : @5, @"y" : @6, @"method" : @"center-point"}
  );
  XCTAssertEqualObjects(
    unavailable[@"error"],
    @"no accessibility server answered the system-wide hit-test at (5.0, 6.0)"
  );
  XCTAssertEqualObjects(unavailable[@"error_kind"], @"application_unavailable");
  XCTAssertNil(unavailable[@"pid"], @"a frontmost query that resolved nothing has no process to name");

  _runtime.hitTestOutcome = [FBAXHitTestOutcome applicationNotResponding];
  NSDictionary *notResponding = FBAXBridgeHandleRequest(
    @{@"verb" : @"describe", @"x" : @5, @"y" : @6, @"method" : @"center-point"}
  );
  XCTAssertEqualObjects(
    notResponding[@"error"],
    @"the application at (5.0, 6.0) did not answer the system-wide hit-test in time"
  );
  XCTAssertEqualObjects(notResponding[@"error_kind"], @"application_not_responding");
}

- (void)testAnUnsupportedFrontmostMethodConsultsNoResolver
{
  NSDictionary *response =
  FBAXBridgeHandleRequest(@{@"verb" : @"describe", @"x" : @1, @"y" : @2, @"method" : @"not-a-method"});
  XCTAssertEqualObjects(response[@"ok"], @NO);
  XCTAssertEqualObjects(response[@"error"], @"unsupported frontmost method: not-a-method");
  XCTAssertEqualObjects(response[@"error_kind"], @"frontmost_unresolved");
  XCTAssertEqual(_runtime.hitTestCount, 0u);
  XCTAssertEqual(_runtime.windowServerCount, 0u);
  XCTAssertEqual(_runtime.runningBoardCount, 0u);
}

- (void)testANonStringMethodFallsBackToTheDefault
{
  _runtime.hitTestOutcome = [FBAXHitTestOutcome hit:[FBAXFakeElement readable:@"leaf"] owningProcessIdentifier:kAppPid];
  _runtime.applicationElements[@(kAppPid)] = [FBAXFakeElement readable:@"UIApplication"];

  _runtime.windowServerOutcome = [FBAXFrontmostOutcome resolved:kAppPid];

  NSDictionary *response = FBAXBridgeHandleRequest(@{@"verb" : @"describe", @"x" : @1, @"y" : @2, @"method" : @7});
  XCTAssertEqualObjects(response[@"method"], @"window-server");
  XCTAssertEqual(_runtime.windowServerCount, 1u);
}

@end
