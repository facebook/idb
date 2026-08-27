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

// An off-screen or still-laying-out element reports a non-finite frame coordinate. JSON cannot
// represent infinity, and `NSJSONSerialization` raises rather than returning an error — which would
// abort the reader process and drop the client's connection mid-read. The non-finite value must
// become null and the rest of the response must survive.
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

- (void)testNaNFrameValueSerializesAsNull
{
  NSData *data = FBAXBridgeSerializeResponse(FBAXTestsFrameResponse(CGRectMake(0, NAN, 10, 20)));
  NSDictionary *parsed = FBAXTestsParse(data);
  XCTAssertNotNil(parsed);
  XCTAssertEqualObjects(parsed[@"tree"][@"XC_kAXXCAttributeFrame"][@"Y"], NSNull.null);
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

// A whole-tree read whose walk was cut short carries a `truncated` flag in its envelope, so the host
// can warn rather than pass a partial tree off as complete. The flag must survive serialization.
- (void)testTruncatedFlagIsPreservedInTheEnvelope
{
  NSDictionary *response = @{@"ok" : @YES, @"tree" : @{@"XC_kAXXCAttributeLabel" : @"root"}, @"truncated" : @YES};
  NSDictionary *parsed = FBAXTestsParse(FBAXBridgeSerializeResponse(response));
  XCTAssertEqualObjects(parsed[@"ok"], @YES);
  XCTAssertEqualObjects(parsed[@"truncated"], @YES, @"the truncation flag must survive serialization");
}

// A frontmost response carries the resolved foreground pid and the method that resolved it, spelled with
// the same selector the request uses so the host can decode it back into `FBAXBridgeFrontmostMethod`.
// Both must survive serialization so the host can read the pid and surface which mechanism answered.
- (void)testFrontmostResponseSerializesPidAndMethod
{
  NSDictionary *response = @{@"ok" : @YES, @"pid" : @1234, @"method" : @"center-point"};
  NSDictionary *parsed = FBAXTestsParse(FBAXBridgeSerializeResponse(response));
  XCTAssertEqualObjects(parsed[@"ok"], @YES);
  XCTAssertEqualObjects(parsed[@"pid"], @1234, @"the resolved pid must survive serialization");
  XCTAssertEqualObjects(parsed[@"method"], @"center-point");
}

// A fullscreen-modal descriptor added to a describe response must survive serialization so the host can
// read it off the wire (host-facing enrichment; the host keeps it out of the serialized CLI output).
- (void)testModalDescriptorSurvivesSerialization
{
  NSDictionary *response = @{
    @"ok" : @YES,
    @"tree" : @{@"XC_kAXXCAttributeLabel" : @"root"},
    @"pid" : @20475,
    @"modal" : @{@"kind" : @"system", @"elementType" : @"SBAlertItemWindow", @"label" : @"Allow"},
  };
  NSDictionary *parsed = FBAXTestsParse(FBAXBridgeSerializeResponse(response));
  XCTAssertEqualObjects(parsed[@"modal"][@"kind"], @"system");
  XCTAssertEqualObjects(parsed[@"modal"][@"elementType"], @"SBAlertItemWindow");
  XCTAssertEqualObjects(parsed[@"modal"][@"label"], @"Allow");
}

// A value that cannot be represented at all must degrade to an error frame the client can read,
// rather than raising and terminating the reader.
- (void)testUnserializableValueYieldsAnErrorFrameRatherThanRaising
{
  NSDictionary *response = @{@"ok" : @YES, @"tree" : [NSDate date]};
  NSDictionary *parsed = FBAXTestsParse(FBAXBridgeSerializeResponse(response));
  XCTAssertEqualObjects(parsed[@"ok"], @NO);
  XCTAssertNotNil(parsed[@"error"]);
}

#pragma mark - Request validation

// A request frame is JSON decoded off the wire, so `verb` arrives as whatever type the host sent — a
// number, an object, an array, or null — and the reader must answer every one of them with an error
// frame. It is the only field read before the request is dispatched, so getting it wrong takes down the
// whole reader rather than failing the one request.
- (void)testNonStringVerbIsRejectedWithAnErrorFrame
{
  for (id verb in @[@123, @{@"a" : @1}, @[@"describe"], NSNull.null]) {
    NSDictionary *response = FBAXBridgeHandleRequest(@{@"verb" : verb});
    XCTAssertEqualObjects(response[@"ok"], @NO, @"a %@ verb must be rejected", [verb class]);
    XCTAssertNotNil(response[@"error"], @"a %@ verb must carry an error message", [verb class]);
    XCTAssertEqualObjects(response[@"error_kind"], @"bad_request", @"a %@ verb", [verb class]);
  }
}

// Shutdown is answered without binding the runtime and without a pid, because neither is needed to
// exit.
- (void)testShutdownIsAnsweredWithoutARuntimeOrAPid
{
  FBAXBridgeSetRuntimeForTesting(nil);
  NSDictionary *response = FBAXBridgeHandleRequest(@{@"verb" : @"shutdown"});
  XCTAssertEqualObjects(response[@"ok"], @YES);
  XCTAssertEqualObjects(response[@"shutdown"], @YES);
  XCTAssertNil(response[@"error"]);
}

// The non-positive pid that every other verb rejects must not stop a shutdown: the caller reaping an
// orphan has no application in mind, and refusing here would make the orphan unreapable.
- (void)testShutdownIgnoresAnUnusablePid
{
  NSDictionary *response = FBAXBridgeHandleRequest(@{@"verb" : @"shutdown", @"pid" : @0});
  XCTAssertEqualObjects(response[@"ok"], @YES);
  XCTAssertEqualObjects(response[@"shutdown"], @YES);
}

// An absent `verb` is rejected the same way as a wrong-typed one: `nil` takes `isEqualToString:`
// without complaint and matches no verb.
- (void)testMissingVerbIsRejectedWithAnErrorFrame
{
  NSDictionary *response = FBAXBridgeHandleRequest(@{@"pid" : @1234});
  XCTAssertEqualObjects(response[@"ok"], @NO);
  XCTAssertEqualObjects(response[@"error"], @"unsupported verb: (nil)");
  XCTAssertEqualObjects(response[@"error_kind"], @"bad_request");
}

// `pid 0` and negative pids name no process. The host distinguishes "this pid names no readable
// application" from every other failure by the `application_unavailable` kind on the envelope — it maps
// that one kind onto a backend-neutral typed error and leaves the rest as opaque guest failures — so a
// pid that cannot name an application has to carry the kind, whatever else the reader can or cannot
// reach. Every verb takes a `pid`, so all of them must answer alike.
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

// The guest and host cross the accessibility boundary with no shared header — each holds its own copy of
// the `XC_kAXXC*` node keys, the request/envelope keys, the modal-descriptor keys, and the
// frontmost-method selectors. A rename on either side is a silent protocol break, so this pins the
// guest's constants to the byte-identical literals the host pins in `FBAXWireContractTests` (node keys
// against `FBAXWire.Node`, request selectors against `FBAXBridgeFrontmostMethod`); the
// two files agreeing on these strings is what enforces the contract.
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

// The serve loop handles one client at a time, so the accept queue exists only to hold a second host
// while somebody else is connected. It is pinned because a host's classification depends on the number:
// a connect to a Unix socket whose backlog is full fails with `ECONNREFUSED`, the same errno as nothing
// being bound, so without a free slot a live guest would be mistaken for an absent one and duplicated.
- (void)testTheServeBacklogIsPinned
{
  XCTAssertEqual(FBAXBridgeServeBacklogForTesting(), 16);
}

#pragma mark - Exit on disconnect

// An exclusive bridge has one client for its whole life, so a disconnect means it is finished. A shared
// bridge wants the opposite: the next visitor is the point of staying up.

- (void)testExitOnDisconnectIsOffUnlessAsked
{
  XCTAssertFalse(FBAXBridgeExitOnDisconnectForTesting(@[]));
  XCTAssertFalse(FBAXBridgeExitOnDisconnectForTesting(@[@"--idle-timeout", @"30"]));
}

- (void)testExitOnDisconnectIsHonouredWhenAsked
{
  XCTAssertTrue(FBAXBridgeExitOnDisconnectForTesting(@[@"--exit-on-disconnect", @"1"]));
  XCTAssertTrue(FBAXBridgeExitOnDisconnectForTesting(@[@"--idle-timeout", @"30", @"--exit-on-disconnect", @"1"]));
}

// A guest predating the flag ignores it and keeps waiting for the next client, so a newer host talking
// to an older guest degrades to the idle timeout rather than failing.
- (void)testExitOnDisconnectCanBeTurnedOffExplicitly
{
  XCTAssertFalse(FBAXBridgeExitOnDisconnectForTesting(@[@"--exit-on-disconnect", @"0"]));
}

#pragma mark - Idle timeout

- (void)testAnIdleTimeoutOnTheCommandLineIsHonoured
{
  XCTAssertEqual(FBAXBridgeIdleTimeoutForTesting(@[@"--idle-timeout", @"45"], 300), 45);
}

// A host predating the flag lands here too: `serve` reads the socket path and ignores the rest of argv.
- (void)testAServeWithNoIdleTimeoutUsesTheDefault
{
  XCTAssertEqual(FBAXBridgeIdleTimeoutForTesting(@[], 300), 300);
  XCTAssertEqual(FBAXBridgeIdleTimeoutForTesting(@[@"--something-else", @"1"], 300), 300);
  XCTAssertEqual(FBAXBridgeDefaultIdleTimeoutForTesting(), 300);
}

- (void)testAnUnusableIdleTimeoutFallsBackToTheDefault
{
  XCTAssertEqual(FBAXBridgeIdleTimeoutForTesting(@[@"--idle-timeout", @"0"], 300), 300);
  XCTAssertEqual(FBAXBridgeIdleTimeoutForTesting(@[@"--idle-timeout", @"-5"], 300), 300);
  XCTAssertEqual(FBAXBridgeIdleTimeoutForTesting(@[@"--idle-timeout", @"soon"], 300), 300);
  XCTAssertEqual(FBAXBridgeIdleTimeoutForTesting(@[@"--idle-timeout", @"12x"], 300), 300);
  // A flag with no value at all: the parser walks pairs, so there is nothing to read.
  XCTAssertEqual(FBAXBridgeIdleTimeoutForTesting(@[@"--idle-timeout"], 300), 300);
}

#pragma mark - Modal detection

// A SpringBoard system alert window anywhere in the tree marks a `system` modal. With no
// `_UIAlertController` present the descriptor's `elementType` falls back to the alert-window class and
// carries no label (the label is only captured off an alert-controller node).
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

// A `_UIAlertController*` element (matched by prefix — the concrete class varies) with no system alert
// window marks an `app` modal, capturing the concrete element type and the alert's title label.
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

// When both alert kinds are present the `kind` is `system` (the system alert wins), but the descriptor
// still reports the captured alert-controller element type and label rather than the window class.
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

// A tree with neither alert class carries no modal descriptor.
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
