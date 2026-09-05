/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <CoreGraphics/CoreGraphics.h>
#import <XCTest/XCTest.h>

#import <SimulatorFrameworkBridgeLib/AccessibilityService.h>
#import <SimulatorFrameworkBridgeLib/AccessibilityService+Testing.h>

@interface AccessibilityServiceTests : XCTestCase
@end

@implementation AccessibilityServiceTests

static NSDictionary *FBAXTestsFrameResponse(CGRect rect)
{
  NSDictionary *frame = (NSDictionary *)CFBridgingRelease(CGRectCreateDictionaryRepresentation(rect));
  return @{@"ok" : @YES, @"tree" : @{@"XC_kAXXCAttributeLabel" : @"icon", @"XC_kAXXCAttributeFrame" : frame}};
}

static NSDictionary *FBAXTestsParse(NSData *data)
{
  return [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
}

// `NSJSONSerialization` raises on a non-finite number rather than returning an error, which would abort
// the reader mid-read.
- (void)testInfiniteFrameValueSerializesAsNull
{
  NSData *data = FBAXBridgeSerializeResponse(FBAXTestsFrameResponse(CGRectMake(INFINITY, 0, 10, 20)));
  NSDictionary *parsed = FBAXTestsParse(data);
  XCTAssertNotNil(parsed, @"a non-finite frame must still produce parseable JSON");
  XCTAssertEqualObjects(parsed[@"ok"], @YES);

  NSDictionary *frame = parsed[@"tree"][@"XC_kAXXCAttributeFrame"];
  XCTAssertEqualObjects(frame[@"X"], NSNull.null, @"the non-finite member must be null, got: %@", frame[@"X"]);
  XCTAssertEqualObjects(frame[@"Height"], @20, @"finite members must be preserved");
  XCTAssertEqualObjects(parsed[@"tree"][@"XC_kAXXCAttributeLabel"], @"icon", @"the rest of the node must survive");
}

- (void)testFiniteResponseIsUnchanged
{
  NSData *data = FBAXBridgeSerializeResponse(FBAXTestsFrameResponse(CGRectMake(16, 293, 370, 52)));
  NSDictionary *frame = FBAXTestsParse(data)[@"tree"][@"XC_kAXXCAttributeFrame"];
  XCTAssertEqualObjects(frame[@"X"], @16);
  XCTAssertEqualObjects(frame[@"Y"], @293);
  XCTAssertEqualObjects(frame[@"Width"], @370);
  XCTAssertEqualObjects(frame[@"Height"], @52);
}

- (void)testUnserializableValueYieldsAnErrorFrameRatherThanRaising
{
  NSDictionary *response = @{@"ok" : @YES, @"tree" : [NSDate date]};
  NSDictionary *parsed = FBAXTestsParse(FBAXBridgeSerializeResponse(response));
  XCTAssertEqualObjects(parsed[@"ok"], @NO);
  XCTAssertNotNil(parsed[@"error"]);
}

#pragma mark - Request validation

- (void)testNonStringVerbIsRejectedWithAnErrorFrame
{
  for (id verb in @[@123, @{@"a" : @1}, @[@"describe"], NSNull.null]) {
    NSDictionary *response = FBAXBridgeHandleRequest(@{@"verb" : verb});
    XCTAssertEqualObjects(response[@"ok"], @NO, @"a %@ verb must be rejected", [verb class]);
    XCTAssertNotNil(response[@"error"], @"a %@ verb must carry an error message", [verb class]);
    XCTAssertEqualObjects(response[@"error_kind"], @"bad_request", @"a %@ verb", [verb class]);
  }
}

- (void)testShutdownIsAnsweredWithoutARuntimeOrAPid
{
  FBAXBridgeSetRuntimeForTesting(nil);
  NSDictionary *response = FBAXBridgeHandleRequest(@{@"verb" : @"shutdown"});
  XCTAssertEqualObjects(response[@"ok"], @YES);
  XCTAssertEqualObjects(response[@"shutdown"], @YES);
  XCTAssertNil(response[@"error"]);
}

// A caller reaping an orphan has no pid in mind; refusing would make the orphan unreapable.
- (void)testShutdownIgnoresAnUnusablePid
{
  NSDictionary *response = FBAXBridgeHandleRequest(@{@"verb" : @"shutdown", @"pid" : @0});
  XCTAssertEqualObjects(response[@"ok"], @YES);
  XCTAssertEqualObjects(response[@"shutdown"], @YES);
}

// `nil` takes `isEqualToString:` without complaint and matches no verb.
- (void)testMissingVerbIsRejectedWithAnErrorFrame
{
  NSDictionary *response = FBAXBridgeHandleRequest(@{@"pid" : @1234});
  XCTAssertEqualObjects(response[@"ok"], @NO);
  XCTAssertEqualObjects(response[@"error"], @"unsupported verb: (nil)");
  XCTAssertEqualObjects(response[@"error_kind"], @"bad_request");
}

// The host maps `application_unavailable` onto a typed error, so a pid that names no process must carry
// that kind on every verb.
- (void)testNonPositivePidIsReportedAsAnUnavailableApplication
{
  NSArray<NSDictionary *> *requests = @[
    @{@"verb" : @"describe", @"pid" : @0},
    @{@"verb" : @"describe", @"pid" : @(-1)},
    @{@"verb" : @"hittest", @"pid" : @0, @"x" : @200, @"y" : @400},
    @{@"verb" : @"hittest", @"pid" : @(-1), @"x" : @200, @"y" : @400},
    @{@"verb" : @"perform", @"pid" : @0, @"x" : @200, @"y" : @400, @"action" : @"press"},
    @{@"verb" : @"perform", @"pid" : @(-1), @"x" : @200, @"y" : @400, @"action" : @"press"},
    @{@"verb" : @"setvalue", @"pid" : @0, @"x" : @200, @"y" : @400, @"value" : @"hello"},
    @{@"verb" : @"setvalue", @"pid" : @(-1), @"x" : @200, @"y" : @400, @"value" : @"hello"},
  ];
  for (NSDictionary *request in requests) {
    NSDictionary *response = FBAXBridgeHandleRequest(request);
    XCTAssertEqualObjects(response[@"ok"], @NO, @"%@ pid %@", request[@"verb"], request[@"pid"]);
    XCTAssertEqualObjects(
      response[@"error_kind"],
      @"application_unavailable",
      @"%@ pid %@",
      request[@"verb"],
      request[@"pid"]
    );
    XCTAssertEqualObjects(response[@"pid"], request[@"pid"], @"the rejected pid must be named back");
  }
}

#pragma mark - Wire contract

// Guest and host share no header for these strings. This pins the guest's constants to the literals the
// host pins in `FBAXWireContractTests`; the two files agreeing is the contract.
- (void)testGuestWireConstantsMatchTheHostContract
{
  NSDictionary<NSString *, NSString *> *expected = @{
    @"node.elementType" : @"XC_kAXXCAttributeElementType",
    @"node.elementBaseType" : @"XC_kAXXCAttributeElementBaseType",
    @"node.label" : @"XC_kAXXCAttributeLabel",
    @"node.value" : @"XC_kAXXCAttributeValue",
    @"node.identifier" : @"XC_kAXXCAttributeIdentifier",
    @"node.frame" : @"XC_kAXXCAttributeFrame",
    @"node.automationType" : @"XC_kAXXCAttributeAutomationType",
    @"node.children" : @"XC_kAXXCAttributeChildren",
    @"request.verb" : @"verb",
    @"request.pid" : @"pid",
    @"request.maxDepth" : @"maxDepth",
    @"request.maxNodes" : @"maxNodes",
    @"request.automationMode" : @"automationMode",
    @"request.attributes" : @"attributes",
    @"request.translatorVocabulary" : @"translatorVocabulary",
    @"request.explainUnreachable" : @"explainUnreachable",
    @"node.explainedBy" : @"FBExplainedBy",
    @"node.isEnabled" : @"FBIsEnabled",
    @"node.translatorRole" : @"FBTranslatorRole",
    @"node.translatorSubrole" : @"FBTranslatorSubrole",
    @"node.traits" : @"FBTraits",
    @"node.elementIdentity" : @"FBElementIdentity",
    @"request.x" : @"x",
    @"request.y" : @"y",
    @"request.method" : @"method",
    @"request.action" : @"action",
    @"request.value" : @"value",
    @"request.assertKey" : @"assertKey",
    @"request.assertValue" : @"assertValue",
    @"envelope.ok" : @"ok",
    @"envelope.tree" : @"tree",
    @"envelope.error" : @"error",
    @"envelope.empty" : @"empty",
    @"envelope.errorKind" : @"error_kind",
    @"envelope.errorKindApplicationUnavailable" : @"application_unavailable",
    @"envelope.errorKindApplicationNotResponding" : @"application_not_responding",
    @"envelope.errorKindFrontmostUnresolved" : @"frontmost_unresolved",
    @"envelope.errorKindReaderUnavailable" : @"reader_unavailable",
    @"envelope.errorKindBadRequest" : @"bad_request",
    @"envelope.errorKindAssertionFailed" : @"assertion_failed",
    @"envelope.truncated" : @"truncated",
    @"envelope.pid" : @"pid",
    @"envelope.method" : @"method",
    @"envelope.modal" : @"modal",
    @"envelope.automation" : @"automation",
    @"envelope.phases" : @"phases",
    @"phases.traverse" : @"traverse_ms",
    @"phases.machRoundTrips" : @"mach_round_trips",
    @"automation.enabled" : @"enabled",
    @"automation.asserted" : @"asserted",
    @"modal.kind" : @"kind",
    @"modal.kindSystem" : @"system",
    @"modal.kindApp" : @"app",
    @"modal.elementType" : @"elementType",
    @"modal.label" : @"label",
    @"modal.systemAlertWindowClass" : @"SBAlertItemWindow",
    @"modal.alertControllerClassPrefix" : @"_UIAlertController",
    @"verb.describe" : @"describe",
    @"verb.hittest" : @"hittest",
    @"verb.perform" : @"perform",
    @"verb.setvalue" : @"setvalue",
    @"verb.shutdown" : @"shutdown",
    @"action.press" : @"press",
    @"action.scrollUp" : @"scroll-up",
    @"action.scrollDown" : @"scroll-down",
    @"action.scrollLeft" : @"scroll-left",
    @"action.scrollRight" : @"scroll-right",
    @"action.scrollToVisible" : @"scroll-to-visible",
    @"method.centerPoint" : @"center-point",
    @"method.windowServer" : @"window-server",
    @"method.runningBoard" : @"runningboard",
  };
  // Whole-dictionary equality also fails on any guest constant this test forgot to pin (or any removed),
  // not just a changed value.
  XCTAssertEqualObjects(FBAXBridgeWireConstantsForTesting(), expected);
}

#pragma mark - Modal detection

- (void)testModalDescriptorReportsSystemAlertWindowAsSystemKind
{
  NSDictionary *tree = @{
    @"XC_kAXXCAttributeLabel" : @"root",
    @"XC_kAXXCAttributeChildren" : @[
      @{@"XC_kAXXCAttributeElementType" : @"SBAlertItemWindow"},
    ],
  };
  NSDictionary *modal = FBAXBridgeModalDescriptor(tree);
  XCTAssertEqualObjects(modal[@"kind"], @"system");
  XCTAssertEqualObjects(modal[@"elementType"], @"SBAlertItemWindow");
  XCTAssertNil(modal[@"label"], @"a system-only alert carries no captured label");
}

// `_UIAlertController*` is matched by prefix; the concrete class varies.
- (void)testModalDescriptorReportsAlertControllerAsAppKindWithElementTypeAndLabel
{
  NSDictionary *tree = @{
    @"XC_kAXXCAttributeLabel" : @"root",
    @"XC_kAXXCAttributeChildren" : @[
      @{
        @"XC_kAXXCAttributeElementType" : @"_UIAlertControllerView",
        @"XC_kAXXCAttributeLabel" : @"Delete this item?",
      },
    ],
  };
  NSDictionary *modal = FBAXBridgeModalDescriptor(tree);
  XCTAssertEqualObjects(modal[@"kind"], @"app");
  XCTAssertEqualObjects(modal[@"elementType"], @"_UIAlertControllerView");
  XCTAssertEqualObjects(modal[@"label"], @"Delete this item?");
}

- (void)testModalDescriptorPrefersSystemKindWhenBothAlertsPresent
{
  NSDictionary *tree = @{
    @"XC_kAXXCAttributeLabel" : @"root",
    @"XC_kAXXCAttributeChildren" : @[
      @{@"XC_kAXXCAttributeElementType" : @"SBAlertItemWindow"},
      @{
        @"XC_kAXXCAttributeElementType" : @"_UIAlertControllerView",
        @"XC_kAXXCAttributeLabel" : @"Allow",
      },
    ],
  };
  NSDictionary *modal = FBAXBridgeModalDescriptor(tree);
  XCTAssertEqualObjects(modal[@"kind"], @"system", @"a system alert window wins over an app alert");
  XCTAssertEqualObjects(modal[@"elementType"], @"_UIAlertControllerView", @"the captured alert-controller class is still reported");
  XCTAssertEqualObjects(modal[@"label"], @"Allow");
}

- (void)testModalDescriptorReturnsNilWhenNoAlertPresent
{
  NSDictionary *tree = @{
    @"XC_kAXXCAttributeLabel" : @"root",
    @"XC_kAXXCAttributeChildren" : @[
      @{@"XC_kAXXCAttributeElementType" : @"XCUIElementTypeButton", @"XC_kAXXCAttributeLabel" : @"OK"},
    ],
  };
  XCTAssertNil(FBAXBridgeModalDescriptor(tree));
}

@end
