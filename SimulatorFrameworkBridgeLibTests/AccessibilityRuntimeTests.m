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

#pragma mark - Encoding normalisation

// `FBAXTypesOnly` is the whole of what makes the signature comparison trustworthy, and every other test
// here reaches it only through `FBAXSignatureMismatch` against whatever encodings Foundation happens to
// have. A table says what it does far more plainly, and covers shapes no Foundation selector produces.
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

// The property the comparison actually depends on: an encoding straight from the runtime and the same
// signature written down without offsets have to normalise to the same string. That is what lets the
// table in the runtime be written either way.
- (void)testTypesOnlyMakesRuntimeAndHandWrittenEncodingsAgree
{
  Method length = class_getInstanceMethod(NSString.class, @selector(length));
  XCTAssertEqualObjects(FBAXTypesOnly(method_getTypeEncoding(length)), FBAXTypesOnly("Q@:"));

  Method objectAtIndex = class_getInstanceMethod(NSArray.class, @selector(objectAtIndex:));
  XCTAssertEqualObjects(FBAXTypesOnly(method_getTypeEncoding(objectAtIndex)), FBAXTypesOnly("@@:Q"));
}

// Normalising is idempotent — an already-normalised encoding is left alone — so it does not matter
// whether a caller has been through it once or twice.
- (void)testTypesOnlyIsIdempotent
{
  for (NSString *encoding in @[@"Q16@0:8", @"{FBAXQuad=[4i]}32@0:8{FBAXPair=ii}16", @"v32@0:8@?24"]) {
    NSString *once = FBAXTypesOnly(encoding.UTF8String);
    XCTAssertEqualObjects(FBAXTypesOnly(once.UTF8String), once, @"normalising %@ twice", encoding);
  }
}

#pragma mark - Bound signature checking

// A red test is the whole point: a private API that changed shape has to arrive as a signal somebody acts
// on, not as a line in a log on a booted simulator that nobody reads. This bundle runs inside a simulator,
// so the frameworks swept here are the guest's copies — the ones the reader sends messages to. All four
// exist on macOS too, and a shape that moved only inside an iOS runtime image would pass against those.
- (void)testEveryBoundSignatureAgreesWithTheRuntime
{
  NSArray<NSString *> *warnings = FBAXSignatureWarnings();
  XCTAssertEqualObjects(warnings, @[], @"%@", [warnings componentsJoinedByString:@"\n"]);
}

// The comparison the sweep above is only as good as, checked against Foundation — it does not care whose
// selector it is given, and Foundation is the one runtime guaranteed present.
- (void)testSignatureAgreesWithTheRuntime
{
  XCTAssertNil(FBAXSignatureMismatch("NSString", "length", NO, "Q@:"));
  XCTAssertNil(FBAXSignatureMismatch("NSString", "stringWithUTF8String:", YES, "@@:r*"));
  XCTAssertNil(FBAXSignatureMismatch("NSArray", "objectAtIndex:", NO, "@@:Q"));
}

// The expected encoding may be pasted straight out of `method_getTypeEncoding`, offsets and all, which is
// how the table in the runtime was built. Dropping them is what keeps the check from firing on an ABI
// where the types are unchanged but the numbers are not.
- (void)testSignatureIgnoresFrameSizesAndOffsets
{
  XCTAssertNil(FBAXSignatureMismatch("NSString", "length", NO, "Q16@0:8"));
  XCTAssertNil(FBAXSignatureMismatch("NSArray", "objectAtIndex:", NO, "@24@0:8Q16"));
}

// Digits inside a struct or array encoding are part of the type, so they survive — otherwise a bound API
// taking a differently-shaped struct would compare equal to one taking the right shape.
- (void)testSignatureKeepsDigitsInsideAggregateEncodings
{
  XCTAssertNil(FBAXSignatureMismatch("FBAXSignatureProbe", "quadFromPair:", NO, "{FBAXQuad=[4i]}@:{FBAXPair=ii}"));

  NSString *mismatch = FBAXSignatureMismatch("FBAXSignatureProbe", "quadFromPair:", NO, "{FBAXQuad=[8i]}@:{FBAXPair=ii}");
  XCTAssertNotNil(mismatch, @"an array length inside the struct is a different type and must not be dropped");
}

// The diagnostic has to carry both encodings: a mismatch is triaged by someone who has neither the runtime
// nor this table in front of them, and "the signature changed" on its own says nothing actionable.
- (void)testSignatureMismatchNamesWhatItFoundAndWhatItAssumed
{
  NSString *mismatch = FBAXSignatureMismatch("NSString", "length", NO, "i@:");
  XCTAssertNotNil(mismatch);
  XCTAssertTrue([mismatch containsString:@"-[NSString length]"], @"%@", mismatch);
  XCTAssertTrue([mismatch containsString:@"Q@:"], @"the encoding found must be named: %@", mismatch);
  XCTAssertTrue([mismatch containsString:@"i@:"], @"the encoding assumed must be named: %@", mismatch);
}

// A class or selector that has gone is the same failure as one that changed shape, and is reported the
// same way rather than passing silently for want of anything to compare.
- (void)testSignatureMismatchReportedForMissingClassOrSelector
{
  NSString *absentClass = FBAXSignatureMismatch("FBAXNoSuchClass", "length", NO, "Q@:");
  XCTAssertNotNil(absentClass);
  XCTAssertTrue([absentClass containsString:@"FBAXNoSuchClass"], @"%@", absentClass);

  XCTAssertNotNil(FBAXSignatureMismatch("NSString", "fbaxNoSuchSelector", NO, "Q@:"));
}

// The class/instance distinction is part of the binding: `+elementWithProcessIdentifier:` and
// `-AXUIElement` are both bound, and checking one against the other's method list would pass on a runtime
// that has neither where it is expected.
- (void)testSignatureDistinguishesClassFromInstanceMethods
{
  XCTAssertNotNil(FBAXSignatureMismatch("NSString", "length", YES, "Q@:"));
  XCTAssertNotNil(FBAXSignatureMismatch("NSString", "stringWithUTF8String:", NO, "@@:r*"));
}

#pragma mark - Read-error classification

// Two AX codes name a condition the host can act on, and the classifier has to recognise each by the code
// the runtime reports and treat every other code as an opaque failure. Getting this wrong in either
// direction is invisible on the wire until a real app misbehaves: too broad and a genuine reader bug is
// reported as "the app isn't there", too narrow and a dead app produces an untyped error the host cannot
// act on. The two are held apart from each other because an app that is gone and an app that is merely
// slow need opposite things done about them.
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

// The other half of the AX-error classification: what the hit-test itself makes of the code
// `AXUIElementCopyElementAtPosition` returned. Nil means an element came back and the caller wraps it;
// every other answer is the complete outcome.
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

  XCTAssertEqualObjects(seeded[@"pid"], @(kAppPid), @"a tagged failure names the process it is about");

  NSDictionary *systemWide = FBAXBridgeHandleRequest(@{@"verb" : @"hittest", @"x" : @1, @"y" : @2});
  XCTAssertEqualObjects(systemWide[@"error_kind"], @"application_unavailable");
  XCTAssertEqualObjects(systemWide[@"error"], @"no accessibility server answered the system-wide hit-test");
  XCTAssertNil(systemWide[@"pid"], @"a display-wide hit-test nothing answered has no process to name");
}

// An application that is there and did not answer in time. Its own kind because the two remedies diverge:
// an unavailable application is reconfigured or relaunched, one that did not answer is waited for. Empty
// would be worse than either — it says the point is blank, which is exactly what a busy app looks like.
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

// A fused frontmost read that names no method gets the authoritative frontmost: the window server's, which
// answers without looking at a pixel. The positional resolver is still there for a caller who wants the
// process owning a particular point, but it is a different question and no longer the one asked by default
// — it fails where nothing occupies the anchor, and answers the wrong application where something else does.
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

// The reader reaches four private frameworks, and a private API is exactly the thing that starts raising
// where it used to return. Unguarded, the first raise unwinds out of the serve loop and takes the reader
// with it — costing a client every later request on that connection, with no frame to say why. It comes
// back as a response instead, and the reader is still answering afterwards.
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

// A malformed request is the caller's to fix, and is held apart from every failure of the reader or of
// the application so it is never reported as either. Both verbs reject their own arguments, past the
// point where the runtime has been reached — hence a fake one, rather than the bundle's live bind.
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

// The whole point of the path: one fetch for a tree, rather than one read per node. The per-node walk is
// what it is being measured against, so both are driven over the same tree and the counters compared.
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

// The snapshot answers keyed by attribute number, and the numbers are the runtime's own. Mapping them
// back through the conversion that produced them is what keeps a hardcoded number out of the reader —
// so the fake numbers them differently from the runtime, and the names must still come out right.
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

// The snapshot nests its children under its own key, and separately answers a children *attribute* full
// of raw element references. Copying that attribute across would put unusable references in the tree, so
// the nesting is the only source of children.
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

// The server's own bounds are set generously and the host's are applied while building the tree, so that
// a tree read this way truncates where the same tree read per node does.
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

// A runtime that cannot perform the fetch must say so. Answering an empty tree instead would report a
// working application as a blank screen, which is the failure this path is most likely to produce.
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

// The server answers NULL under kAXErrorSuccess when it will not accept the options — no error, just
// nothing. That has to become a failure too, for the same reason.
- (void)testASnapshotThatAnswersNothingIsAFailureRatherThanAnEmptyTree
{
  _runtime.applicationElements[@(kAppPid)] = FBAXTestsNode(@{@"XC_kAXXCAttributeLabel" : @"root"}, @[]);
  _runtime.snapshotAnswersNothing = YES;

  NSDictionary *response = FBAXBridgeHandleRequest(FBAXTestsSnapshotRequest(@{}));
  XCTAssertEqualObjects(response[@"ok"], @NO);
  XCTAssertNil(response[@"tree"]);
}

// A frame comes back from the snapshot as an AXValue rather than the NSValue the per-node walk answers
// with, so it is unwrapped through the seam. Whichever form it takes, the host receives the same
// dictionary representation.
- (void)testASnapshotFrameIsUnwrappedThroughTheSeam
{
  _runtime.applicationElements[@(kAppPid)] = FBAXTestsNode(
    @{@"XC_kAXXCAttributeFrame" : [NSValue valueWithBytes:&(CGRect) {{16, 293}, {370, 52}} objCType:@encode(CGRect)]},
    @[]
  );

  NSDictionary *frame = FBAXBridgeHandleRequest(FBAXTestsSnapshotRequest(@{}))[@"tree"][@"XC_kAXXCAttributeFrame"];
  XCTAssertEqualObjects(frame[@"X"], @16);
  XCTAssertEqualObjects(frame[@"Y"], @293);
  XCTAssertEqualObjects(frame[@"Width"], @370);
  XCTAssertEqualObjects(frame[@"Height"], @52);
}

// A value that is not a rect must leave the frame alone rather than unwrap to zero: a point read as a
// rect would be reported as a real frame at the origin, which nothing downstream could tell from one.
- (void)testAValueThatIsNotARectDoesNotBecomeAZeroFrame
{
  CGRect rect = CGRectMake(1, 2, 3, 4);
  XCTAssertFalse([_runtime getRect:&rect fromValue:@"not a rect"]);
  XCTAssertTrue(CGRectEqualToRect(rect, CGRectMake(1, 2, 3, 4)), @"a rejected value must leave the rect untouched");
}

// BUG: an unrecognised frame value — not a dictionary, not an `NSValue`, rejected by the runtime — is
// emitted as `{"X":0,"Y":0,"Width":0,"Height":0}`. The host cannot tell that from a real frame at the
// origin. A missing attribute is emitted as null; a rejected one should be too. Flipped in the following
// commit.
- (void)testAnUnrecognisedFrameValueIsEmittedAsAZeroedFrame
{
  _runtime.applicationElements[@(kAppPid)] = FBAXTestsNode(@{kAXFrame : @"not a frame"}, @[]);

  NSDictionary *frame = FBAXBridgeHandleRequest(FBAXTestsSnapshotRequest(@{}))[@"tree"][kAXFrame];
  XCTAssertEqualObjects(frame[@"X"], @0);
  XCTAssertEqualObjects(frame[@"Y"], @0);
  XCTAssertEqualObjects(frame[@"Width"], @0);
  XCTAssertEqualObjects(frame[@"Height"], @0);
}

// BUG: an unrecognised point value is emitted as `{"X":0,"Y":0}` — the screen origin, a plausible
// tap target. Same defect as the frame above, and more dangerous: the host taps points. Flipped in the
// following commit.
- (void)testAnUnrecognisedPointValueIsEmittedAsAZeroedPoint
{
  _runtime.applicationElements[@(kAppPid)] = FBAXTestsNode(@{kAXVisiblePoint : @"not a point"}, @[]);

  NSDictionary *point = FBAXBridgeHandleRequest(
    FBAXTestsSnapshotRequest(
      @{@"attributes" : @[kAXVisiblePoint]}
    )
  )[@"tree"][kAXVisiblePoint];
  XCTAssertEqualObjects(point[@"X"], @0);
  XCTAssertEqualObjects(point[@"Y"], @0);
}

#pragma mark - Write outcomes

// The AX runtime reports every write with a code and nothing else, so this classifier is the only thing
// standing between "the app has gone" and "the writer is broken" — the same distinction the read and
// hit-test classifiers make, made once more for the codes a write can come back with.
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

// The factories are the enforcement — a caller cannot build an outcome carrying a payload its status does
// not license, so switching on the status is enough to know what is readable.
- (void)testEachWriteOutcomeCarriesOnlyItsOwnPayload
{
  for (FBAXWriteOutcome *empty in @[[FBAXWriteOutcome written],
                                    [FBAXWriteOutcome empty],
                                    [FBAXWriteOutcome applicationUnavailable],
                                    [FBAXWriteOutcome applicationNotResponding]]) {
    XCTAssertNil(empty.failureReason);
  }

  FBAXWriteOutcome *assertionFailed = [FBAXWriteOutcome assertionFailed:@"expected General, found Wi-Fi"];
  XCTAssertEqual(assertionFailed.status, FBAXWriteStatusAssertionFailed);
  XCTAssertEqualObjects(assertionFailed.failureReason, @"expected General, found Wi-Fi");

  FBAXWriteOutcome *failed = [FBAXWriteOutcome failed:@"the element has no AXUIElement to act on"];
  XCTAssertEqual(failed.status, FBAXWriteStatusFailed);
  XCTAssertEqualObjects(failed.failureReason, @"the element has no AXUIElement to act on");
}

// A dlsym'd C entry point is checked by a null test at bind time and by nothing else —
// `FBAXSignatureWarnings` sweeps ObjC selectors, and there is no equivalent record of a C function's shape
// to compare against. Asserting the two write entry points are in the runtime at all is the only part of
// that binding a test can carry, and it is worth carrying because this bundle runs inside a simulator: the
// symbols swept here are the guest's, on the runtime image the writer actually sends to.
- (void)testTheAXRuntimeWriteEntryPointsResolve
{
  XCTAssertTrue(dlopen(FBAXPathAXRuntime, RTLD_NOW) != NULL, @"AXRuntime could not be opened");
  XCTAssertTrue(dlsym(RTLD_DEFAULT, "AXUIElementPerformAction") != NULL);
  XCTAssertTrue(dlsym(RTLD_DEFAULT, "AXUIElementSetAttributeValue") != NULL);
}

// The automation-mode read is bound the same way and therefore checked the same way. It is deliberately
// optional in the live runtime — a runtime without it degrades to "cannot say" rather than failing a
// bind — so this asserts it is present today rather than that the code requires it.
- (void)testTheAutomationModeReadEntryPointResolves
{
  XCTAssertTrue(dlopen(FBAXPathAXRuntime, RTLD_NOW) != NULL, @"AXRuntime could not be opened");
  XCTAssertTrue(dlsym(RTLD_DEFAULT, "_AXSAutomationEnabled") != NULL);
}

// The fake has to behave like the live runtime on the one point a caller can get wrong: a write that is
// accepted and does not take must read back as the state the device is actually in, not as the state
// that was asked for. Pinned on the fake because commit-level coverage of the real setter needs a device.
- (void)testAWriteThatDoesNotTakeReadsBackAsTheUnchangedState
{
  FBAXFakeRuntime *runtime = [FBAXFakeRuntime new];
  runtime.automationMode = NO;
  runtime.automationModeWriteFails = YES;

  XCTAssertFalse([runtime setAutomationModeEnabled:YES], @"a silent write failure must not report success");
  XCTAssertFalse([runtime automationModeEnabled]);
  XCTAssertEqualObjects(runtime.automationModeWrites, @[@YES], @"the write is still attempted, and recorded");

  runtime.automationModeWriteFails = NO;
  XCTAssertTrue([runtime setAutomationModeEnabled:YES], @"a write that takes reads back as the new state");
}

#pragma mark - Guest phase reporting

// The counts are what make the durations interpretable, so they are pinned against a tree of known
// shape rather than asserted to be merely present.
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

// A round-trip count that does not track the tree is worse than none: it would make a per-node cost
// look constant while the tree grew.
- (void)testTheRoundTripCountTracksTheTree
{
  FBAXFakeElement *root = [FBAXFakeElement readable:@"UIApplication"];
  NSMutableArray *children = [NSMutableArray array];
  for (NSUInteger index = 0; index < 5; index++) {
    [children addObject:[FBAXFakeElement readable:@"UIButton"]];
  }
  root.children = children;
  _runtime.applicationElements[@(kAppPid)] = root;

  NSDictionary *response = FBAXBridgeHandleRequest(@{@"verb" : @"describe", @"pid" : @(kAppPid)});
  XCTAssertEqualObjects(response[@"phases"][@"mach_round_trips"], @6, @"root plus five children");
}

#pragma mark - Automation mode on the describe path

// The tri-state the wire carries, driven end to end through the request handler rather than against the
// runtime directly, because the thing that can regress is the handler's decision about when to write.

// ABSENT is the case most likely to break silently: a host that does not know about this field, or a
// caller that does not care, must leave the device exactly as it found it.
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

// A no-op write is still a preference write, and `asserted` on one would tell a caller this read altered
// a device it left alone.
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

// Explicitly false is a different request from absent: it turns the mode off rather than leaving it be.
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

// The readback is the point. A preference write can be accepted and silently not apply, and a caller
// told `asserted` for one of those would believe the device is in a mode it is not in.
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

// The wire spelling of an action is the host's whole vocabulary for what a write does, so every name has to
// arrive at the runtime as the action it names. A name that silently became a press would be a tap where
// the caller asked for a scroll — visible only as a test that navigated somewhere unexpected.
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

// An action name the guest cannot map has no number to perform, so it is refused outright rather than
// falling through to whichever action happens to be first in the enum.
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

// A write is addressed by point and nothing else, so coordinates that are absent or not numbers leave it
// with no target — and hit-testing (0, 0) instead would act on whatever is in the corner of the screen.
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

// Empty space is a successful result for a write for the same reason it is for a hit-test: the host has to
// tell "there was nothing to tap" apart from "the write broke", and only one of those is worth retrying.
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

// An application that has gone can take a write out at either step, and the diagnostic differs by what was
// known when: nothing answered the hit-test at all, or the app the hit-test attributed the element to died
// before the write reached it.
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

// Nothing stands between a resolved element and the perform. `XC_kAXXCAttributeUserTestingActions` looks
// like the way to pre-check that an element accepts an action, and is not: no element populates it, so a
// guard built on it refuses nothing and charges every perform an extra attribute read for the privilege.
- (void)testAnActionIsPerformedWhateverTheElementAdvertises
{
  for (id advertised in @[@[@"AXScrollToVisible"], @[], NSNull.null]) {
    [self seedHitElementWithAttributes:@{@"XC_kAXXCAttributeUserTestingActions" : advertised}];
    XCTAssertEqualObjects(FBAXBridgeHandleRequest(FBAXTestsPress())[@"ok"], @YES, @"%@", advertised);
  }
  XCTAssertEqual(_runtime.performCount, 3);
}

// A marker is resolved host-side against a tree that was read earlier, so the element under the point can
// have changed by the time the write arrives. The assertion is what catches that, and the diagnostic has to
// say what was found as well as what was expected — otherwise the caller cannot tell a moved screen from a
// wrong marker.
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

// Half an assertion is a request the caller got wrong, and answering it either way — checking nothing, or
// checking against nil — would silently do something other than what was asked.
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

// The host builds an assertion out of a node it read off this wire, so a key that never appears in a node
// is one it could not have come from there — and passing an unknown key through to the runtime would make
// an unreadable attribute look like an element that moved.
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

// The value is JSON off the wire, so it arrives as whatever the client sent. Anything but a string is
// rejected rather than stringified — writing "1" because the caller sent the number 1 is a guess.
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

// A write that went wrong carries the runtime's reason and must *not* pick up an error kind — the host acts
// on those kinds, and a slow application is neither an absent one nor an element that moved.
- (void)testAFailedWriteIsAnOpaqueFailureCarryingTheRuntimeReason
{
  [self seedHitElementWithAttributes:@{}];
  _runtime.writeOutcome = [FBAXWriteOutcome failed:@"the application did not answer the write in time"];

  NSDictionary *response = FBAXBridgeHandleRequest(FBAXTestsPress());
  XCTAssertEqualObjects(response[@"ok"], @NO);
  XCTAssertEqualObjects(response[@"error"], @"the application did not answer the write in time");
  XCTAssertNil(response[@"error_kind"]);
}

// A write with an explicit pid scopes the hit-test to that application, exactly as a `hittest` does — a
// write aimed at one app must not land on whatever is drawn over it.
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

// The tree walk coerces every attribute value into something JSON can carry. The accessibility runtime
// reports its geometric attributes as `X`/`Y`(`/Width`/`Height`) dictionaries, and a point attribute is
// given the same structural treatment the frame gets, so a consumer reads a coordinate rather than the
// text `NSDictionary` happens to print.
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

// The contrast that makes the above a statement about the *key* rather than about dictionaries: the
// frame, given the identical shape, is carried through structurally.
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

// XCTest's reader returns an `NSError` *as an attribute's value* for any AX failure other than no-value or
// unsupported, so a failed read arrives in the same shape as a successful one. Nothing downstream expects an
// error object, and the JSON coercion stringifies whatever it does not recognise.
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

// The seam carries the ask through verbatim. Worth pinning because the attribute list is the whole
// request: the wrong numbers reach the server as a different question, and the answer still looks valid.
- (void)testATranslatorReadPassesTheAttributesThrough
{
  _runtime.translatorAttributeValues = @{@(FBAXPAttributeLabel) : @"General"};
  NSArray *asked = @[@(FBAXPAttributeLabel), @(FBAXPAttributeFrame)];

  NSDictionary *read = [_runtime translatorAttributes:asked ofElement:[FBAXFakeElement readable:@"UIView"]];

  XCTAssertEqualObjects(read[@(FBAXPAttributeLabel)], @"General");
  XCTAssertEqualObjects(_runtime.lastTranslatorAttributes, asked);
}

// Both walks are asked for the same depth cap by the same request, so a read should mean the same thing by
// it. The view-hierarchy walk marks a read truncated only where the node it stopped at *had* children;
// this pins the translator walk deciding from the node's own attribute count instead.
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

// Round trips are the cost of a translator walk, not attribute count: every request hops onto the
// application's main thread and blocks there, so the number of requests is what a deep read pays.
// Pinning it per node makes a regression to more round trips visible.
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

// Nil is "the read could not be performed", which a caller must be able to tell from a read that
// succeeded and returned nothing — the same distinction the outcome types elsewhere exist to preserve.
- (void)testATranslatorReadThatCannotBePerformedAnswersNil
{
  _runtime.translatorAttributeValues = nil;
  XCTAssertNil([_runtime translatorAttributes:@[@(FBAXPAttributeLabel)] ofElement:[FBAXFakeElement readable:@"UIView"]]);
}

// One read per node is the reason the batched request type exists; a caller that regressed to one read
// per attribute would still be correct and would cost eight times as many round trips.
- (void)testABatchedReadIsOneRoundTripForManyAttributes
{
  _runtime.translatorAttributeValues = @{};
  [_runtime translatorAttributes:@[@(FBAXPAttributeLabel), @(FBAXPAttributeRole), @(FBAXPAttributeFrame),
                                   @(FBAXPAttributeIdentifier)]
                       ofElement:[FBAXFakeElement readable:@"UIView"]];
  XCTAssertEqual(_runtime.translatorReadCount, 1u);
}

// Every test above this line drives the seam directly, which pins what the fake echoes rather than what a
// read emits. These drive `describe` itself, so they fail if the build step stops emitting an attribute
// it fetched.

// `enabled` is the one answer this vocabulary has that XCTest's does not, and fetching it without emitting
// it is indistinguishable at the wire from not supporting it at all.
- (void)testATranslatorReadEmitsTheEnabledAnswerItFetched
{
  _runtime.applicationElements[@(kAppPid)] = [FBAXFakeElement readable:@"UIApplication"];
  _runtime.translatorAttributeValues = @{@(FBAXPAttributeLabel) : @"General", @(FBAXPAttributeIsEnabled) : @NO};

  NSDictionary *response =
  FBAXBridgeHandleRequest(@{@"verb" : @"describe", @"pid" : @(kAppPid), @"translatorVocabulary" : @YES});

  XCTAssertEqualObjects(response[@"ok"], @YES);
  XCTAssertEqualObjects(response[@"tree"][kNodeIsEnabled], @NO, @"the fetched enabled answer must reach the wire");
}

// The role rides the wire as the translator's own integer and is deliberately not merged into
// `elementType`, which carries `XCUIElementType` names. Pinned because emitting it under the wrong key
// would be read as a type name by every existing consumer.
- (void)testATranslatorReadEmitsTheTranslatorsOwnRoleUnmapped
{
  _runtime.applicationElements[@(kAppPid)] = [FBAXFakeElement readable:@"UIApplication"];
  _runtime.translatorAttributeValues = @{@(FBAXPAttributeRole) : @9};

  NSDictionary *tree =
  FBAXBridgeHandleRequest(@{@"verb" : @"describe", @"pid" : @(kAppPid), @"translatorVocabulary" : @YES})[@"tree"];

  XCTAssertEqualObjects(tree[kNodeTranslatorRole], @9);
  XCTAssertNil(tree[kAXElementType], @"the translator role must not be emitted under the elementType key");
}

// The point is what lets the host judge reachability on this path: it derives `interactable` from the
// same key an XCTest read supplies, so a walk that answers hittability and no point reports no verdict.
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

// The traits bitmask is the input the translator's own role handler classifies; carrying it lets a caller
// reach a distinction the role collapsed.
- (void)testATranslatorReadEmitsTheTraitsBitmask
{
  _runtime.applicationElements[@(kAppPid)] = [FBAXFakeElement readable:@"UIApplication"];
  _runtime.translatorAttributeValues = @{@(FBAXPAttributeTraits) : @(1 << 6)};

  NSDictionary *tree =
  FBAXBridgeHandleRequest(@{@"verb" : @"describe", @"pid" : @(kAppPid), @"translatorVocabulary" : @YES})[@"tree"];

  XCTAssertEqualObjects(tree[@"FBTraits"], @(1 << 6));
}

// Identity is what makes two reads comparable element by element. Without it, deciding whether a tree is
// the previous screen means comparing every attribute and trusting the combination to be unique.
- (void)testATranslatorReadEmitsAPerElementIdentity
{
  _runtime.applicationElements[@(kAppPid)] = [FBAXFakeElement readable:@"UIApplication"];
  _runtime.translatorAttributeValues = @{@(FBAXPAttributeMemoryAddress) : @(0x600001234560)};

  NSDictionary *tree =
  FBAXBridgeHandleRequest(@{@"verb" : @"describe", @"pid" : @(kAppPid), @"translatorVocabulary" : @YES})[@"tree"];

  XCTAssertEqualObjects(tree[@"FBElementIdentity"], @(0x600001234560));
}

// A translator read that could not be performed answers nil, which is not the same as an element with no
// attributes. Building a node from it emits a childless, attribute-less tree, so a failed bind reports as a
// successful read of an application with no content — a wrong answer that looks entirely healthy.
- (void)testATranslatorReadThatCannotBePerformedIsAFailureNotAnEmptyTree
{
  _runtime.applicationElements[@(kAppPid)] = [FBAXFakeElement readable:@"UIApplication"];
  _runtime.translatorAttributeValues = nil;

  NSDictionary *response =
  FBAXBridgeHandleRequest(@{@"verb" : @"describe", @"pid" : @(kAppPid), @"translatorVocabulary" : @YES});

  XCTAssertEqualObjects(response[@"ok"], @NO);
  XCTAssertNil(response[@"tree"], @"a read that could not be performed must not answer with a tree");
}

// The runtime vends an application element for any pid, including one that names no process, and the
// translator answers against it with synthesized defaults rather than failing. Without the availability
// probe, a read through this vocabulary would answer `ok:true` with a fabricated root — carrying a role
// and an enabled value — for a process that does not exist, and nothing about that response would look
// wrong to a caller.
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

// The envelope a translator read answers with is the same envelope every other read answers with,
// `method` included.
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

#pragma mark - The AXP attribute vocabulary

// These values are read off a private binary rather than a header, so they are pinned here: a runtime
// that renumbers them would otherwise be discovered as a reader silently fetching the wrong attribute,
// which reads as missing data rather than as a broken constant.
//
// `Children` is the one with two independent derivations — the `__AXPAttributeToString` table and the
// dispatch jump table that routes both 8 and 9 to the children handler — so it is the canary.
- (void)testTheAXPAttributeVocabularyIsPinned
{
  XCTAssertEqual(FBAXPAttributeVisiblePoint, 112);
  XCTAssertEqual(FBAXPAttributeTraits, 77);
  XCTAssertEqual(FBAXPAttributeMemoryAddress, 128);
  XCTAssertEqual(FBAXPAttributeIsElement, 26);
  XCTAssertEqual(FBAXPAttributeWindowSections, 79);
  XCTAssertEqual(FBAXPAttributeContainerType, 80);
  XCTAssertEqual(FBAXPAttributeViewControllerDescription, 82);
  XCTAssertEqual(FBAXPAttributeUserInputLabels, 87);
  XCTAssertEqual(FBAXPAttributeCustomContent, 89);
  XCTAssertEqual(FBAXPAttributeChildren, 8);
  XCTAssertEqual(FBAXPAttributeChildrenInNavigationOrder, 9);
  XCTAssertEqual(FBAXPAttributeLabel, 33);
  XCTAssertEqual(FBAXPAttributeFrame, 21);
  XCTAssertEqual(FBAXPAttributeIdentifier, 25);
  XCTAssertEqual(FBAXPAttributeValue, 53);
  XCTAssertEqual(FBAXPAttributeRole, 45);
  XCTAssertEqual(FBAXPAttributeIsVisible, 32);
  XCTAssertEqual(FBAXPAttributeIsEnabled, 27);
}

// The two request kinds a reader uses. `MultipleAttribute` is called out because passing its attribute
// list as an array rather than under the `attributes` key throws inside the guest.
- (void)testTheAXPRequestTypesArePinned
{
  XCTAssertEqual(FBAXPRequestTypeAttribute, 2);
  XCTAssertEqual(FBAXPRequestTypeMultipleAttribute, 5);
}

#pragma mark - Request-named attributes

// A request that names attributes is read with exactly those. The fake echoes back whatever it holds
// rather than filtering, so what this proves is that the *request's* list reached the runtime — which is
// the whole mechanism.
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

// A request that names none is read with the default list, unchanged — this is what keeps a default read
// byte-identical to one issued by a host that predates the field.
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

// The children key is what the walk recurses on, so a request that omits it must still get it — narrowing
// the attributes must narrow the read, not flatten the tree to its root.
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

// A malformed list is the caller's mistake and must not fail an otherwise well-formed read: a non-array,
// an empty array, and an array of no usable names all fall back to the default rather than reading
// nothing. A non-string member is dropped and the rest of the list survives.
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

// A write asserts on an attribute of the element found under its point, and the guard is that the key is
// one the request actually fetches. A non-default key is therefore assertable exactly when the write names
// it, which is the same condition the read that produced the assertion had to meet.
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
  XCTAssertEqualObjects(response[@"pid"], @(kAppPid));
}

// A root belonging to an app that did not answer. `describe` and `hittest` classify the same condition
// the same way, so a wedged app reads alike whichever verb found it.
- (void)testDescribeOfARootThatDidNotAnswerIsTaggedNotResponding
{
  _runtime.applicationElements[@(kAppPid)] = [FBAXFakeElement applicationNotResponding];

  NSDictionary *response = FBAXBridgeHandleRequest(@{@"verb" : @"describe", @"pid" : @(kAppPid)});
  XCTAssertEqualObjects(response[@"ok"], @NO);
  XCTAssertEqualObjects(response[@"error_kind"], @"application_not_responding");
  XCTAssertEqualObjects(response[@"error"], @"pid 4321 did not answer the read of its element tree in time");
  XCTAssertEqualObjects(response[@"pid"], @(kAppPid));
}

// A root that failed for any other reason is an opaque failure quoting what the runtime said — and when
// the runtime said nothing, the message says that rather than trailing off into `(null)`.
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
  // A strategy that could not answer is about the strategy, not about any one application — so it is its
  // own kind, and must not be reported as an application the caller should go and reconfigure.
  XCTAssertEqualObjects(response[@"error_kind"], @"frontmost_unresolved");
  XCTAssertEqual(_runtime.hitTestCount, 0u, @"no fallback to the positional resolver");
  XCTAssertEqual(_runtime.runningBoardCount, 0u, @"no fallback to RunningBoard");
}

// The positional resolver's non-resolving outcomes get distinct messages *and* distinct kinds: nothing at
// the anchor (an app mid-launch, or genuinely empty space) versus nothing answering at all versus an app
// that is there and slow. A fused frontmost read of an app with no accessibility server is the same
// condition as a `--pid` read of one, and answering it as a generic frontmost failure is what left the
// host unable to say which had happened.
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

// A `method` of the wrong type is not a method name — it falls back to the default rather than being
// stringified into an unsupported-method error. `method` arrives as whatever JSON the host sent.
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
