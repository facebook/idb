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
- (void)testSignatureReportsWhatIsNotInTheRuntimeAtAll
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
  XCTAssertEqual(notResponding.status, FBAXReadStatusApplicationNotResponding, @"a live app that did not answer has not gone away");

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
    @"success with an element is the caller's to wrap"
  );
  // Success with no element out is still nothing at the point, not a contradiction to report.
  XCTAssertEqual(
    [FBAXHitTestOutcome outcomeForHitTestError:FBAXErrorSuccess hasElement:NO].status,
    FBAXHitTestStatusEmpty
  );
  XCTAssertEqual(
    [FBAXHitTestOutcome outcomeForHitTestError:FBAXErrorServerNotFound hasElement:NO].status,
    FBAXHitTestStatusApplicationUnavailable,
    @"nothing answered at all is not an empty point"
  );
  XCTAssertEqual(
    [FBAXHitTestOutcome outcomeForHitTestError:FBAXErrorInvalidUIElement hasElement:NO].status,
    FBAXHitTestStatusEmpty,
    @"a genuinely empty point"
  );
  XCTAssertEqual(
    [FBAXHitTestOutcome outcomeForHitTestError:FBAXErrorIPCTimeout hasElement:NO].status,
    FBAXHitTestStatusApplicationNotResponding,
    @"a live application that did not answer is neither an empty point nor an absent app"
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
- (void)testAnApplicationThatDidNotAnswerIsTaggedApartFromOneThatIsAbsent
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
  XCTAssertNil(systemWide[@"empty"], @"an app that did not answer must never read as empty space");
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
  NSDictionary *empty = FBAXBridgeHandleRequest(@{@"verb" : @"describe", @"x" : @9999, @"y" : @9999});
  XCTAssertEqualObjects(empty[@"ok"], @NO);
  XCTAssertEqualObjects(empty[@"error"], @"system-wide hit-test at (9999.0, 9999.0) found no element");
  XCTAssertEqualObjects(empty[@"error_kind"], @"frontmost_unresolved");

  _runtime.hitTestOutcome = [FBAXHitTestOutcome applicationUnavailable];
  NSDictionary *unavailable = FBAXBridgeHandleRequest(@{@"verb" : @"describe", @"x" : @5, @"y" : @6});
  XCTAssertEqualObjects(
    unavailable[@"error"],
    @"no accessibility server answered the system-wide hit-test at (5.0, 6.0)"
  );
  XCTAssertEqualObjects(unavailable[@"error_kind"], @"application_unavailable");
  XCTAssertNil(unavailable[@"pid"], @"a frontmost query that resolved nothing has no process to name");

  _runtime.hitTestOutcome = [FBAXHitTestOutcome applicationNotResponding];
  NSDictionary *notResponding = FBAXBridgeHandleRequest(@{@"verb" : @"describe", @"x" : @5, @"y" : @6});
  XCTAssertEqualObjects(
    notResponding[@"error"],
    @"the application at (5.0, 6.0) did not answer the system-wide hit-test in time"
  );
  XCTAssertEqualObjects(notResponding[@"error_kind"], @"application_not_responding");
}

- (void)testAnUnsupportedFrontmostMethodConsultsNoResolver
{
  NSDictionary *response =
  FBAXBridgeHandleRequest(@{@"verb" : @"describe", @"x" : @1, @"y" : @2, @"method" : @"telepathy"});
  XCTAssertEqualObjects(response[@"ok"], @NO);
  XCTAssertEqualObjects(response[@"error"], @"unsupported frontmost method: telepathy");
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

  NSDictionary *response = FBAXBridgeHandleRequest(@{@"verb" : @"describe", @"x" : @1, @"y" : @2, @"method" : @7});
  XCTAssertEqualObjects(response[@"method"], @"center-point");
  XCTAssertEqual(_runtime.hitTestCount, 1u);
}

@end
