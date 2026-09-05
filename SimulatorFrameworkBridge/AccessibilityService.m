/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "AccessibilityService.h"
#import "AccessibilityService+Testing.h"

#import <dlfcn.h>
#import <math.h>
#import <objc/message.h>

#import <CoreGraphics/CoreGraphics.h>

#import "AXPAttributes.h"
#import "AccessibilityRuntime.h"
#import "AccessibilityServiceServer.h"
#import "AccessibilityService_Private.h"

// The `XC_kAXXC*` attribute keys. These MUST match `FBAXWire.Node` host-side so the emitted tree feeds
// the shared serializer (via `FBAXBridgePlatformElement`) unchanged.
static NSString *const kAXElementType = @"XC_kAXXCAttributeElementType";
static NSString *const kAXElementBaseType = @"XC_kAXXCAttributeElementBaseType";
static NSString *const kAXLabel = @"XC_kAXXCAttributeLabel";
static NSString *const kAXValue = @"XC_kAXXCAttributeValue";
static NSString *const kAXIdentifier = @"XC_kAXXCAttributeIdentifier";
static NSString *const kAXFrame = @"XC_kAXXCAttributeFrame";
static NSString *const kAXAutomationType = @"XC_kAXXCAttributeAutomationType";
static NSString *const kAXChildren = @"XC_kAXXCAttributeChildren";
// Both answered as CGPoint. `VisiblePoint` reads `(-1, -1)` when the server believes no touch reaches the
// element; carried verbatim, sentinel included — deciding what unreachable means is the host's job.
static NSString *const kAXVisiblePoint = @"XC_kAXXCAttributeVisiblePoint";
static NSString *const kAXCenterPoint = @"XC_kAXXCAttributeCenterPoint";
// Whether the server can name a point at which a touch reaches the element; the walk uses it to pick
// nodes worth explaining.
static NSString *const kAXIsVisible = @"XC_kAXXCAttributeIsVisible";

static NSString *const kRequestVerb = @"verb";
static NSString *const kRequestPid = @"pid";
static NSString *const kRequestMaxDepth = @"maxDepth";
static NSString *const kRequestMaxNodes = @"maxNodes";
// The attributes fetched per element. Optional: absent means `FBAXBridgeDefaultFetchList()`. Named per
// request so an attribute nobody asked for stays off the wire entirely.
static NSString *const kRequestAttributes = @"attributes";
// Whether this read wants the device in accessibility automation mode. Tri-state on purpose: **absent**
// means observe and report without touching the device, which is what a host that does not know about
// this field gets; `true` and `false` each assert that state. Absent and `false` are not the same thing —
// one leaves the device alone and the other actively turns the mode off.
static NSString *const kRequestAutomationMode = @"automationMode";
// Asks the walk to explain each element the accessibility server reports unreachable, by hit-testing that
// element's centre and reporting whatever answered. Optional and off by default: it costs an extra AX
// round trip per unreachable element, and only a caller that intends to use the answer should pay.
static NSString *const kRequestExplainUnreachable = @"explainUnreachable";
// Reads through the translator's vocabulary instead of XCTest's. Off by default; the two disagree on
// some screens.
static NSString *const kRequestTranslatorVocabulary = @"translatorVocabulary";
// Reads the whole subtree in one call, through `userTestingSnapshotForElement:options:error:`, instead
// of one call per node. Selected by the host's `single-fetch` traversal; the per-node walk is still the
// default.
static NSString *const kRequestSnapshotTree = @"snapshotTree";
// Reader-derived keys (below) are spelled in the reader's own namespace, not `XC_kAXXC*`, so the two
// kinds stay distinguishable on the wire.
static NSString *const kNodeExplainedBy = @"FBExplainedBy";
// The translator's own `enabled` answer; XCTest's vocabulary has no counterpart. Only a translator read
// carries this.
static NSString *const kNodeIsEnabled = @"FBIsEnabled";
// The translator's `role`, carried as its raw integer for the host to map. Not folded into `elementType`,
// which carries `XCUIElementType` names.
static NSString *const kNodeTranslatorRole = @"FBTranslatorRole";
// The translator's `subrole`, as its raw integer; it refines the role rather than replacing it.
static NSString *const kNodeTranslatorSubrole = @"FBTranslatorSubrole";
// The `UIAccessibilityTraits` bitmask, carried raw. Decoding it needs the trait constants, which live in
// a macOS-only header this binary cannot import — so the number rides the wire and the host names it.
static NSString *const kNodeTraits = @"FBTraits";
// A per-element identity from the translator, so two reads can be compared element by element.
static NSString *const kNodeElementIdentity = @"FBElementIdentity";
// Present only on a node where at least one attribute failed to read, mapping the attribute's key to the
// reason.
static NSString *const kNodeAttributeReadFailures = @"FBAttributeReadFailures";
// Echoed back by the shutdown verb so a caller can tell an honoured shutdown from an ok-shaped response
// to something else.
static NSString *const kResponseShutdown = @"shutdown";
static NSString *const kRequestX = @"x";
static NSString *const kRequestY = @"y";
// Selects how a fused frontmost read (a `describe` with no pid) resolves the foreground app. Optional;
// defaults to `window-server` (the authoritative query).
static NSString *const kRequestMethod = @"method";
// The semantic action a `perform` asks for, and the string a `setvalue` writes.
static NSString *const kRequestAction = @"action";
static NSString *const kRequestValue = @"value";
// What the element at the point must still be for the write to go ahead: one node attribute key and the
// value it has to equal. Optional, and only meaningful together.
static NSString *const kRequestAssertKey = @"assertKey";
static NSString *const kRequestAssertValue = @"assertValue";
static NSString *const kResponseOk = @"ok";
static NSString *const kResponseTree = @"tree";
static NSString *const kResponseError = @"error";
// A successful hit-test that found no element at the point: `{ok:true, empty:true}` — distinct from a
// reader failure (`{ok:false, error:...}`), so the host can tell empty space from a broken reader.
static NSString *const kResponseEmpty = @"empty";
// A closed-vocabulary failure kind, so the host picks a remedy structurally rather than by matching the
// free-text `error`. Absent kind = plain reader failure; a host must treat an unknown kind the same way,
// so adding a value here degrades an older host's precision rather than breaking it.
static NSString *const kResponseErrorKind = @"error_kind";
// The named process has no accessibility server: a dead pid, or a process that is not an application.
static NSString *const kErrorKindApplicationUnavailable = @"application_unavailable";
// The named process has one and it did not answer in time — alive but busy, suspended or wedged.
static NSString *const kErrorKindApplicationNotResponding = @"application_not_responding";
// The selected frontmost strategy could not name an application, for a reason that is about the strategy
// rather than about any one application.
static NSString *const kErrorKindFrontmostUnresolved = @"frontmost_unresolved";
// The reader could not bind the private frameworks it reads through, so no request can be served. The
// `error` names what was missing and what else about the runtime has moved.
static NSString *const kErrorKindReaderUnavailable = @"reader_unavailable";
// The request itself was malformed — an unknown verb, or a missing or wrongly-typed argument.
static NSString *const kErrorKindBadRequest = @"bad_request";
// A write was refused before it was attempted: the element found at the point is not the one the caller
// named. Held apart from `bad_request` because the request was well-formed — the screen moved.
static NSString *const kErrorKindAssertionFailed = @"assertion_failed";
// A whole-tree read whose walk was cut short by the depth cap or the node budget: the returned tree is
// a partial view, so the host can warn rather than pass it off as complete. Absent or `false` means the
// walk visited every element within the bounds.
static NSString *const kResponseTruncated = @"truncated";
// The resolved foreground pid and the mechanism that resolved it. The pid also tags the owning element
// of a hit-test result.
static NSString *const kResponsePid = @"pid";
static NSString *const kResponseMethod = @"method";
// The automation mode this read ran under, and whether this read changed it. Reported on every describe:
// a tree read with subtree collapsing on is a different answer from the same tree read with it off.
static NSString *const kResponseAutomation = @"automation";
// Where the guest spent its time and how many round trips it took. Reported on every describe (a handful
// of clock reads). Guest-side JSON encoding is not included — it falls into the host's residual.
static NSString *const kResponsePhases = @"phases";
static NSString *const kPhaseTraverse = @"traverse_ms";
static NSString *const kPhaseMachRoundTrips = @"mach_round_trips";
static NSString *const kAutomationEnabled = @"enabled";
static NSString *const kAutomationAsserted = @"asserted";
// A fullscreen modal/alert descriptor added to a describe response when one is detected in the tree.
// Host-facing enrichment on the wire; the host does not put it in the serialized CLI output.
static NSString *const kResponseModal = @"modal";
static NSString *const kModalKind = @"kind";
static NSString *const kModalKindSystem = @"system";
static NSString *const kModalKindApp = @"app";
static NSString *const kModalElementType = @"elementType";
static NSString *const kModalLabel = @"label";
// Concrete accessibility element classes that mark a modal: a SpringBoard system alert window, and the
// UIKit alert controller view (matched by prefix — the concrete class varies by idiom/OS).
static NSString *const kSystemAlertWindowClass = @"SBAlertItemWindow";
static NSString *const kAlertControllerClassPrefix = @"_UIAlertController";

static NSString *const kVerbDescribe = @"describe";
static NSString *const kVerbHitTest = @"hittest";
// Asks a `serve` process to exit; answered before exiting so the caller learns it was honoured. The serve
// loop holds one client at a time, so any answer proves the caller is the only client — being answered is
// how a host learns a bridge is free.
static NSString *const kVerbShutdown = @"shutdown";
static NSString *const kVerbPerform = @"perform";
static NSString *const kVerbSetValue = @"setvalue";
static NSString *const kActionServe = @"serve";

// The semantic actions a `perform` request can name — the wire spelling of `FBAXAction`, which is what the
// host sends and what the guest maps back. Unrelated to `kActionServe`, which is an argv sub-command.
static NSString *const kActionPress = @"press";
static NSString *const kActionScrollUp = @"scroll-up";
static NSString *const kActionScrollDown = @"scroll-down";
static NSString *const kActionScrollLeft = @"scroll-left";
static NSString *const kActionScrollRight = @"scroll-right";
static NSString *const kActionScrollToVisible = @"scroll-to-visible";

// The frontmost-resolution methods, shared by the request `method` selector and the response `method`
// value: a request selects a strategy with one of these, and a fused frontmost response echoes back the
// one that answered, so a guest-reported `method` round-trips into the host's `FBAXBridgeFrontmostMethod`.
// `center-point` is the positional system-wide hit-test; `window-server` is the authoritative query, and
// the default when a request names no method.
static NSString *const kMethodCenterPoint = @"center-point";
static NSString *const kMethodWindowServer = @"window-server";
static NSString *const kMethodRunningBoard = @"runningboard";

// A depth cap and a total-node budget guard against pathological trees. A request carries the
// caller's own bounds (the host sets them so every backend truncates alike); these apply only when it
// does not — e.g. the one-shot front-end invoked by hand.
static const int kDefaultMaxDepth = 100;
static const int kDefaultNodeBudget = 5000;

#pragma mark - AX client setup

// Set by `FBAXBridgeSetRuntimeForTesting`; nil in the product.
static id<FBAXRuntime> gInjectedRuntime = nil;

// The runtime is bound once and reused across requests: `dlopen` + `initForRemoteAccess` is the
// dominant setup cost (~260ms), so caching it is what makes the persistent `serve` mode fast.
// Not thread-safe by design — requests are handled serially.
static id<FBAXRuntime> _Nullable FBAXBridgeSharedRuntime(NSString *_Nullable *_Nullable error)
{
  if (gInjectedRuntime) {
    return gInjectedRuntime;
  }
  static FBAXLiveRuntime *shared;
  static NSString *cachedError;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    NSString *setupError = nil;
    shared = [[FBAXLiveRuntime alloc] initWithError:&setupError];
    cachedError = setupError;
  });
  if (!shared && error) {
    *error = cachedError ?: @"accessibility setup failed";
  }
  return shared;
}

void FBAXBridgePrepareRuntime(void)
{
  FBAXBridgeSharedRuntime(NULL);
}

void FBAXBridgeSetRuntimeForTesting(id<FBAXRuntime> _Nullable runtime)
{
  gInjectedRuntime = runtime;
}

// Kept short: read once per unreachable element.
static NSArray<NSString *> *FBAXBridgeExplanationFetchList(void)
{
  return @[kAXElementType, kAXLabel, kAXIdentifier, kAXFrame, kAXAutomationType];
}

// The attributes a read fetches when the request names none. Membership *and* order are part of the wire
// contract, mirrored host-side by `FBAXWire.Node.defaultFetchList`.
static NSArray<NSString *> *FBAXBridgeDefaultFetchList(void)
{
  return @[
    kAXElementType, kAXElementBaseType, kAXLabel, kAXValue, kAXIdentifier, kAXFrame, kAXAutomationType,
    kAXChildren
  ];
}

// Names are forwarded unfiltered — the vocabulary is far wider than the constants here. The children key
// is always appended: the walk recurses on it, and omitting it would flatten the tree to its root.
//
// Hazard: the framework drops any name it has no number for, then fails the whole read on the count
// mismatch — one unknown key costs every attribute for that node, not just itself.
static NSArray<NSString *> *FBAXBridgeFetchListForRequest(NSDictionary<NSString *, id> *request)
{
  id requested = request[kRequestAttributes];
  if (![requested isKindOfClass:NSArray.class]) {
    return FBAXBridgeDefaultFetchList();
  }
  NSMutableArray<NSString *> *attributes = [NSMutableArray array];
  for (id name in (NSArray *)requested) {
    if ([name isKindOfClass:NSString.class]) {
      [attributes addObject:name];
    }
  }
  if (attributes.count == 0) {
    return FBAXBridgeDefaultFetchList();
  }
  if (![attributes containsObject:kAXChildren]) {
    [attributes addObject:kAXChildren];
  }
  return attributes;
}

// Counted rather than inferred from node count, which would undercount by up to 2x (the translator walk
// makes two requests per node; explaining an unreachable element adds two more). A file-static is safe:
// requests are answered one at a time.
static int64_t gRoundTrips;

static void FBAXBridgeCountRoundTrip(void)
{
  gRoundTrips++;
}

// An outcome whose status and payload disagree. Unreachable through the factories; reported as a response
// rather than raised because the guest serves a long-lived connection.
static NSError *FBAXBridgeInvariantError(NSString *description)
{
  return [NSError errorWithDomain:@"FBAXBridgeInvariant" code:1 userInfo:@{NSLocalizedDescriptionKey : description}];
}

#pragma mark - JSON coercion

// A geometry value none of a coercion's branches recognises. Answered as null — the same answer a
// missing attribute gets — never as a zeroed dictionary, which is well-formed geometry at the screen
// origin and indistinguishable from a real answer.
static id FBAXBridgeRejectedGeometry(NSString *kind, id value)
{
  NSLog(@"[AccessibilityService] unexpected %@ value class: %@", kind, [value class]);
  return NSNull.null;
}

// The frame arrives from `attributesForElement:` as an `NSValue`-wrapped `CGRect` (or, tolerantly, an
// existing dictionary representation). Emit the CGRect dictionary representation the host consumes via
// `CGRectMakeWithDictionaryRepresentation`.
static id FBAXBridgeFrameDictionary(id frameValue)
{
  CGRect rect = CGRectZero;
  if ([frameValue isKindOfClass:NSDictionary.class]) {
    if (!CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)frameValue, &rect)) {
      return FBAXBridgeRejectedGeometry(@"frame", frameValue);
    }
    return (NSDictionary *)frameValue;
  }
  if ([frameValue isKindOfClass:NSValue.class]) {
    NSValue *value = (NSValue *)frameValue;
    if (strcmp(value.objCType, @encode(CGRect)) != 0) {
      return FBAXBridgeRejectedGeometry(@"frame", frameValue);
    }
    [value getValue:&rect size:sizeof(rect)];
  } else if (frameValue && [FBAXBridgeSharedRuntime(NULL) getRect:&rect fromValue:frameValue]) {
    // An `AXValue`-wrapped rect, which is how the single-fetch read answers. Not an `NSValue`: it is a
    // CFType with its own accessor, so the `NSValue` branch above sees only `__NSCFType` and drops it.
  } else {
    return FBAXBridgeRejectedGeometry(@"frame", frameValue);
  }
  return (NSDictionary *)CFBridgingRelease(CGRectCreateDictionaryRepresentation(rect));
}

// Keyed on the attribute name, as the frame is, so a value that merely looks like an X/Y pair is never
// reinterpreted as a coordinate.
static BOOL FBAXBridgeIsPointAttribute(NSString *key)
{
  return [key isEqualToString:kAXVisiblePoint] || [key isEqualToString:kAXCenterPoint];
}

// Emit the `CGPoint` dictionary representation the host consumes, as the frame's coercion does. Rejection
// matters more here than for the frame: the host taps these points and `{0,0}` is a plausible target.
static id FBAXBridgePointDictionary(id pointValue)
{
  CGPoint point = CGPointZero;
  if ([pointValue isKindOfClass:NSDictionary.class]) {
    if (!CGPointMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)pointValue, &point)) {
      return FBAXBridgeRejectedGeometry(@"point", pointValue);
    }
    return (NSDictionary *)pointValue;
  }
  if ([pointValue isKindOfClass:NSValue.class]) {
    NSValue *value = (NSValue *)pointValue;
    if (strcmp(value.objCType, @encode(CGPoint)) != 0) {
      return FBAXBridgeRejectedGeometry(@"point", pointValue);
    }
    [value getValue:&point size:sizeof(point)];
  } else if (pointValue && [FBAXBridgeSharedRuntime(NULL) getPoint:&point fromValue:pointValue]) {
    // An `AXValue`-wrapped point, which is how the single-fetch read answers. Not an `NSValue`: it is a
    // CFType with its own accessor, so the `NSValue` branch above sees only `__NSCFType` and drops it.
  } else {
    return FBAXBridgeRejectedGeometry(@"point", pointValue);
  }
  return (NSDictionary *)CFBridgingRelease(CGPointCreateDictionaryRepresentation(point));
}

// JSON cannot represent infinity or NaN: `NSJSONSerialization` *raises* an `NSInvalidArgumentException`
// on a non-finite number rather than returning an error, which would abort this process and drop the
// client's connection mid-read. An element that is off-screen or still being laid out (common on the
// first read after launch) reports a non-finite frame coordinate, so every number is checked and a
// non-finite one is emitted as null — matching the host serializer, which sanitizes the same way.
static id FBAXBridgeJSONSafeNumber(NSNumber *number)
{
  if (CFNumberIsFloatType((__bridge CFNumberRef)number) && !isfinite(number.doubleValue)) {
    return NSNull.null;
  }
  return number;
}

// Recursively replaces every non-finite number in a response with null before serialization.
static id FBAXBridgeJSONSanitized(id value)
{
  if ([value isKindOfClass:NSNumber.class]) {
    return FBAXBridgeJSONSafeNumber(value);
  }
  if ([value isKindOfClass:NSDictionary.class]) {
    NSDictionary *dictionary = value;
    NSMutableDictionary *sanitized = [NSMutableDictionary dictionaryWithCapacity:dictionary.count];
    for (id key in dictionary) {
      sanitized[key] = FBAXBridgeJSONSanitized(dictionary[key]);
    }
    return sanitized;
  }
  if ([value isKindOfClass:NSArray.class]) {
    NSArray *array = value;
    NSMutableArray *sanitized = [NSMutableArray arrayWithCapacity:array.count];
    for (id element in array) {
      [sanitized addObject:FBAXBridgeJSONSanitized(element)];
    }
    return sanitized;
  }
  return value;
}

// Coerce an attribute value to a JSON-serializable form. Strings and numbers pass through; the frame
// becomes a dictionary; anything else is stringified so the payload never fails serialization.
static id FBAXBridgeJSONSafeValue(id _Nullable value, NSString *key)
{
  if (value == nil || value == NSNull.null) {
    return NSNull.null;
  }
  if ([key isEqualToString:kAXFrame]) {
    return FBAXBridgeFrameDictionary(value);
  }
  if (FBAXBridgeIsPointAttribute(key)) {
    return FBAXBridgePointDictionary(value);
  }
  if ([value isKindOfClass:NSString.class] || [value isKindOfClass:NSNumber.class]) {
    return value;
  }
  // The framework reports a failed attribute by returning the error in place of the value, so an error
  // arrives in the same shape as an answer. Stringifying it would describe the element as having that
  // string as the attribute — a label of "Error Domain=..." reads as a real label to anything matching on
  // one. Absent a value, the honest answer is that there is none; `kNodeAttributeReadFailures` carries
  // which keys failed and why.
  if ([value isKindOfClass:NSError.class]) {
    return NSNull.null;
  }
  return [value description];
}

#pragma mark - Tree walk

// Whether the accessibility server said this node is reachable. Absent or non-boolean counts as
// reachable, so an explanation is never attempted for a node the caller did not ask visibility about.
static BOOL FBAXBridgeNodeIsUnreachable(NSDictionary<NSString *, id> *node)
{
  id visible = node[kAXIsVisible];
  return [visible isKindOfClass:NSNumber.class] && ![(NSNumber *)visible boolValue];
}

// The element a display-wide hit-test finds at `point`, described by the explanation fetch list, or nil.
// Display-wide on purpose: an element covered by another process's chrome is covered whoever drew it.
static NSDictionary<NSString *, id> *_Nullable FBAXBridgeExplanationAtPoint(id<FBAXRuntime> runtime, CGPoint point)
{
  FBAXBridgeCountRoundTrip();
  FBAXHitTestOutcome *hit = [runtime hitTestAtPoint:point processIdentifier:0];
  if (hit.status != FBAXHitTestStatusHit) {
    return nil;
  }
  id hitElement = hit.element;
  if (!hitElement) {
    return nil;
  }
  FBAXBridgeCountRoundTrip();
  FBAXReadOutcome *read = [runtime readAttributes:FBAXBridgeExplanationFetchList() ofElement:hitElement];
  if (read.status != FBAXReadStatusRead || !read.attributes) {
    return nil;
  }
  NSMutableDictionary *explanation = [NSMutableDictionary dictionaryWithCapacity:read.attributes.count];
  for (NSString *key in read.attributes) {
    explanation[key] = FBAXBridgeJSONSafeValue(read.attributes[key], key);
  }
  return explanation;
}

// Read from the node rather than derived from the frame, so it matches what the server measured
// reachability against.
static BOOL FBAXBridgeNodeCentre(NSDictionary<NSString *, id> *node, CGPoint *point)
{
  id centre = node[kAXCenterPoint];
  if (![centre isKindOfClass:NSDictionary.class]) {
    return NO;
  }
  return CGPointMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)centre, point);
}

// One mach round-trip per node: read the element's attributes, coerce them to JSON, then recurse into
// its children (replacing the child `XCAccessibilityElement`s with their read dictionaries in place).
//
// The outcome describes only *this* element. A child that fails to read is dropped from the tree rather
// than failing the whole read, so a child's outcome never becomes the caller's.
static FBAXReadOutcome *FBAXBridgeBuildNode(id<FBAXRuntime> runtime,
                                            id element,
                                            NSArray<NSString *> *fetchList,
                                            BOOL explainUnreachable,
                                            int depth,
                                            int maxDepth,
                                            int *budget,
                                            BOOL *truncated)
{
  FBAXBridgeCountRoundTrip();
  FBAXReadOutcome *outcome = [runtime readAttributes:fetchList ofElement:element];
  if (outcome.status != FBAXReadStatusRead) {
    return outcome;
  }
  NSDictionary<NSString *, id> *attributes = outcome.attributes;
  if (!attributes) {
    return [FBAXReadOutcome failed:FBAXBridgeInvariantError(@"a read reported success but returned no attributes")];
  }

  NSMutableDictionary *node = [NSMutableDictionary dictionaryWithCapacity:attributes.count];
  NSMutableDictionary<NSString *, NSString *> *readFailures = nil;
  for (NSString *key in attributes) {
    if ([key isEqualToString:kAXChildren]) {
      continue;
    }
    id value = attributes[key];
    if ([value isKindOfClass:NSError.class]) {
      if (!readFailures) {
        readFailures = [NSMutableDictionary dictionary];
      }
      readFailures[key] = [(NSError *)value localizedDescription] ?: [value description];
    }
    node[key] = FBAXBridgeJSONSafeValue(value, key);
  }
  if (readFailures) {
    node[kNodeAttributeReadFailures] = readFailures;
  }

  NSMutableArray<NSDictionary *> *children = [NSMutableArray array];
  NSArray *childElements =
  [attributes[kAXChildren] isKindOfClass:NSArray.class] ? attributes[kAXChildren] : nil;
  if (depth < maxDepth) {
    for (id child in childElements) {
      if (*budget <= 0) {
        *truncated = YES;
        break;
      }
      (*budget)--;
      FBAXReadOutcome *childOutcome =
      FBAXBridgeBuildNode(runtime, child, fetchList, explainUnreachable, depth + 1, maxDepth, budget, truncated);
      if (childOutcome.status == FBAXReadStatusRead) {
        [children addObject:(NSDictionary *)childOutcome.attributes];
      }
    }
  } else if (childElements.count > 0) {
    *truncated = YES;
  }
  node[kAXChildren] = children;

  CGPoint centre = CGPointZero;
  if (explainUnreachable && FBAXBridgeNodeIsUnreachable(node) && FBAXBridgeNodeCentre(node, &centre)) {
    NSDictionary *explanation = FBAXBridgeExplanationAtPoint(runtime, centre);
    if (explanation) {
      node[kNodeExplainedBy] = explanation;
    }
  }
  return [FBAXReadOutcome read:node];
}

#pragma mark - Translator vocabulary

// Builds a node through the translator's vocabulary, keyed the same way the XCTest walk keys it where the
// two vocabularies agree, so the serializer above needs no knowledge of which one produced a tree. The two
// attributes XCTest has no counterpart for — `enabled` and the translator's own `role` — are keyed in the
// reader's namespace instead; see `kNodeIsEnabled` and `kNodeTranslatorRole`.
static NSDictionary *_Nullable FBAXBridgeBuildTranslatorNode(id<FBAXRuntime> runtime,
                                                             id element,
                                                             int depth,
                                                             int maxDepth,
                                                             int *budget,
                                                             BOOL *truncated)
{
  if (*budget <= 0) {
    *truncated = YES;
    return nil;
  }
  (*budget)--;

  NSArray<NSNumber *> *wanted = @[
    @(FBAXPAttributeLabel), @(FBAXPAttributeFrame), @(FBAXPAttributeIdentifier),
    @(FBAXPAttributeValue), @(FBAXPAttributeIsVisible), @(FBAXPAttributeIsEnabled),
    @(FBAXPAttributeRole), @(FBAXPAttributeSubrole), @(FBAXPAttributeVisiblePoint),
    @(FBAXPAttributeTraits), @(FBAXPAttributeMemoryAddress),
  ];
  FBAXBridgeCountRoundTrip();
  NSDictionary<NSNumber *, id> *values = [runtime translatorAttributes:wanted ofElement:element];
  // Nil is "could not read", not "empty element": building a node from it would report a failed bind as a
  // healthy application with no content.
  if (!values) {
    return nil;
  }
  NSMutableDictionary *node = [NSMutableDictionary dictionary];
  if (values[@(FBAXPAttributeLabel)]) {
    node[kAXLabel] = values[@(FBAXPAttributeLabel)];
  }
  if (values[@(FBAXPAttributeIdentifier)]) {
    node[kAXIdentifier] = values[@(FBAXPAttributeIdentifier)];
  }
  if (values[@(FBAXPAttributeValue)]) {
    node[kAXValue] = FBAXBridgeJSONSafeValue(values[@(FBAXPAttributeValue)], kAXValue);
  }
  if (values[@(FBAXPAttributeFrame)]) {
    node[kAXFrame] = FBAXBridgeJSONSafeValue(values[@(FBAXPAttributeFrame)], kAXFrame);
  }
  if (values[@(FBAXPAttributeIsVisible)]) {
    node[kAXIsVisible] = values[@(FBAXPAttributeIsVisible)];
  }
  if (values[@(FBAXPAttributeIsEnabled)]) {
    node[kNodeIsEnabled] = values[@(FBAXPAttributeIsEnabled)];
  }
  if (values[@(FBAXPAttributeRole)]) {
    node[kNodeTranslatorRole] = values[@(FBAXPAttributeRole)];
  }
  if (values[@(FBAXPAttributeSubrole)]) {
    node[kNodeTranslatorSubrole] = values[@(FBAXPAttributeSubrole)];
  }
  if (values[@(FBAXPAttributeTraits)]) {
    node[kNodeTraits] = values[@(FBAXPAttributeTraits)];
  }
  if (values[@(FBAXPAttributeMemoryAddress)]) {
    node[kNodeElementIdentity] = values[@(FBAXPAttributeMemoryAddress)];
  }
  // Keyed as XCTest names it, because the host derives `interactable` from that key and the two answer
  // the same question. Without it the derivation has hittability and no point, which is the shape it
  // reports as no verdict at all.
  if (values[@(FBAXPAttributeVisiblePoint)]) {
    node[kAXVisiblePoint] = FBAXBridgeJSONSafeValue(values[@(FBAXPAttributeVisiblePoint)], kAXVisiblePoint);
  }

  NSMutableArray *children = [NSMutableArray array];
  // Children are a separate request (the handler special-cases the attribute out of the batch). Asked even
  // at the depth cap, because `truncated` needs to know whether this node has children.
  FBAXBridgeCountRoundTrip();
  NSDictionary<NSNumber *, id> *kids = [runtime translatorAttributes:@[@(FBAXPAttributeChildren)] ofElement:element];
  id list = kids[@(FBAXPAttributeChildren)];
  NSArray *childElements = [list isKindOfClass:NSArray.class] ? (NSArray *)list : nil;
  if (depth < maxDepth) {
    for (id child in childElements) {
      NSDictionary *built = FBAXBridgeBuildTranslatorNode(runtime, child, depth + 1, maxDepth, budget, truncated);
      if (built) {
        [children addObject:built];
      }
    }
  } else if (childElements.count > 0) {
    *truncated = YES;
  }
  node[kAXChildren] = children;
  return node;
}

#pragma mark - Modal detection

// Recursively scans a built node for the concrete alert classes. `SBAlertItemWindow` (a SpringBoard
// system alert window) sets `*hasSystemAlertWindow`; the first `_UIAlertController*` view captures the
// alert's element type and label (its title). Reads the same keys the tree carries on the wire.
static void FBAXBridgeScanForAlert(NSDictionary *node,
                                   BOOL *hasSystemAlertWindow,
                                   NSString *_Nullable *_Nullable alertElementType,
                                   NSString *_Nullable *_Nullable alertLabel)
{
  NSString *elementType = node[kAXElementType];
  if ([elementType isKindOfClass:NSString.class]) {
    if ([elementType isEqualToString:kSystemAlertWindowClass]) {
      *hasSystemAlertWindow = YES;
    }
    if (!*alertElementType && [elementType hasPrefix:kAlertControllerClassPrefix]) {
      *alertElementType = elementType;
      NSString *label = node[kAXLabel];
      if ([label isKindOfClass:NSString.class] && label.length > 0) {
        *alertLabel = label;
      }
    }
  }
  NSArray *children = node[kAXChildren];
  if ([children isKindOfClass:NSArray.class]) {
    for (id child in children) {
      if ([child isKindOfClass:NSDictionary.class]) {
        FBAXBridgeScanForAlert(child, hasSystemAlertWindow, alertElementType, alertLabel);
      }
    }
  }
}

// A fullscreen-modal descriptor for a built tree, or nil when none is present. `kind` is `system` when
// a SpringBoard alert window is present (a system/permission alert), otherwise `app` (an in-app UIKit
// alert). Host-facing enrichment: the host reads this to detect a modal without geometry.
NSDictionary<NSString *, NSString *> *_Nullable FBAXBridgeModalDescriptor(NSDictionary<NSString *, id> *tree)
{
  BOOL hasSystemAlertWindow = NO;
  NSString *alertElementType = nil;
  NSString *alertLabel = nil;
  FBAXBridgeScanForAlert(tree, &hasSystemAlertWindow, &alertElementType, &alertLabel);
  if (!hasSystemAlertWindow && !alertElementType) {
    return nil;
  }
  NSMutableDictionary *modal = [NSMutableDictionary dictionary];
  modal[kModalKind] = hasSystemAlertWindow ? kModalKindSystem : kModalKindApp;
  modal[kModalElementType] = alertElementType ?: kSystemAlertWindowClass;
  if (alertLabel) {
    modal[kModalLabel] = alertLabel;
  }
  return modal;
}

#pragma mark - Frontmost resolution

// Resolves the frontmost application positionally: a system-wide hit-test at the caller's screen anchor
// reads whichever element owns that point, and its owning pid is the frontmost app.
//
// A *positional* proxy for frontmost: agrees with the window server for a fullscreen app or the home
// screen, but a centred element owned by another process (e.g. a system modal) answers that process.
static FBAXFrontmostOutcome *FBAXBridgeCenterPointFrontmost(id<FBAXRuntime> runtime, CGPoint anchor)
{
  FBAXBridgeCountRoundTrip();
  FBAXHitTestOutcome *outcome = [runtime hitTestAtPoint:anchor processIdentifier:0];
  switch (outcome.status) {
    case FBAXHitTestStatusHit:
      return [FBAXFrontmostOutcome resolved:outcome.owningProcessIdentifier];
    case FBAXHitTestStatusEmpty:
      // Nothing at the anchor: an app mid-launch whose AX tree is not up yet, or a genuinely empty point.
      // The host treats this as "not ready" and retries, so the same outcome that answers a `hittest` with
      // an empty result answers a frontmost query with a resolution failure.
      return [FBAXFrontmostOutcome unresolved:
              [NSString stringWithFormat:@"system-wide hit-test at (%.1f, %.1f) found no element", anchor.x, anchor.y]];
    case FBAXHitTestStatusApplicationUnavailable:
      return [FBAXFrontmostOutcome applicationUnavailable:
              [NSString stringWithFormat:@"no accessibility server answered the system-wide hit-test at (%.1f, %.1f)", anchor.x, anchor.y]];
    case FBAXHitTestStatusApplicationNotResponding:
      return [FBAXFrontmostOutcome applicationNotResponding:
              [NSString stringWithFormat:@"the application at (%.1f, %.1f) did not answer the system-wide hit-test in time", anchor.x, anchor.y]];
    case FBAXHitTestStatusFailed:
    default:
      return [FBAXFrontmostOutcome unresolved:outcome.failureReason ?: @"the system-wide hit-test failed"];
  }
}

// `center-point` is the positional hit-test at `anchor`; `window-server` (default) is the in-guest
// AXPTranslator query; `runningboard` reads RunningBoard's visibility endowment. No fallback between
// them: a caller who asked for the authoritative answer is not served by silently getting the proxy.
static FBAXFrontmostOutcome *FBAXBridgeResolveFrontmost(id<FBAXRuntime> runtime, NSString *method, CGPoint anchor)
{
  if ([method isEqualToString:kMethodCenterPoint]) {
    return FBAXBridgeCenterPointFrontmost(runtime, anchor);
  }
  if ([method isEqualToString:kMethodWindowServer]) {
    return [runtime windowServerFrontmost];
  }
  if ([method isEqualToString:kMethodRunningBoard]) {
    return [runtime runningBoardFrontmost];
  }
  return [FBAXFrontmostOutcome unresolved:[NSString stringWithFormat:@"unsupported frontmost method: %@", method]];
}

#pragma mark - Request handling

static NSDictionary *FBAXBridgeErrorResponse(NSString *message)
{
  return @{kResponseOk : @NO, kResponseError : message};
}

// A failure the host can act on: the message says what happened, the kind says what class of thing it
// was, and the pid names the process it was about when there is one. A display-wide hit-test that nothing
// answers has no pid to name, so it is optional rather than a sentinel the host has to know to ignore.
static NSDictionary *FBAXBridgeTaggedErrorResponse(NSString *message, NSString *kind, NSNumber *_Nullable pid)
{
  NSMutableDictionary *response =
  [@{kResponseOk : @NO, kResponseError : message, kResponseErrorKind : kind} mutableCopy];
  if (pid) {
    response[kResponsePid] = pid;
  }
  return response;
}

// The response a failed read answers with, or nil when it succeeded. Only the XCTest read produces these
// statuses, which is why the translator path spends a round trip to obtain one.
static NSDictionary *_Nullable FBAXBridgeReadFailureResponse(FBAXReadOutcome *read, pid_t pid)
{
  switch (read.status) {
    case FBAXReadStatusRead:
      return nil;
    case FBAXReadStatusApplicationUnavailable:
      return FBAXBridgeTaggedErrorResponse(
        [NSString stringWithFormat:@"pid %d has no accessibility server", pid],
        kErrorKindApplicationUnavailable,
        @(pid)
      );
    case FBAXReadStatusApplicationNotResponding:
      return FBAXBridgeTaggedErrorResponse(
        [NSString stringWithFormat:@"pid %d did not answer the read of its element tree in time", pid],
        kErrorKindApplicationNotResponding,
        @(pid)
      );
    case FBAXReadStatusFailed:
    default:
      return FBAXBridgeErrorResponse(
        [NSString stringWithFormat:@"failed to read the element tree for pid %d: %@",
         pid,
         read.error.localizedDescription ?: @"the accessibility runtime reported no error"]
      );
  }
}

// The snapshot API's own keys. Its nodes nest under `Children`, carry attributes keyed by number under
// `Attributes` (rather than the `XC_kAXXCAttribute*` names the per-node walk produces), and name the
// element each node was read from under `Element`.
static NSString *const kSnapshotAttributes = @"UIAccessibilitySnapshotKeyAttributes";
static NSString *const kSnapshotChildren = @"UIAccessibilitySnapshotKeyChildren";
static NSString *const kSnapshotElement = @"UIAccessibilitySnapshotKeyElement";

// How many boundary continuations one read may fetch. Depth and node budget already bound the recursion
// — a continuation replaces a node at its own depth and never re-triggers on its own root, so every
// further boundary sits at least one level deeper — but each continuation is fetched before the node it
// replaces is counted, and this caps what a pathological ownership graph can spend on fetches. Screens
// measured so far carry one or two boundaries; a read that hits the cap reports `truncated`.
static const int kSnapshotBoundaryFetchBudget = 64;

// Maps one snapshot node into the reader's node shape, recursing.
//
// `namesByNumber` inverts the positional name→number conversion, so no attribute number is hardcoded.
//
// A snapshot is served by the process owning its root and cannot serialize a subtree another process
// draws (a web view's page, a picker, an autofill sheet). A node with no nesting whose element is owned by
// a different process is refetched rooted at that element, and the continuation replaces the stub
// wholesale. `ownerPid` 0 disables the comparison. A continuation that fails leaves the stub childless —
// the same silence the per-node walk answers with.
//
// Bounded by the same depth and node budget as the walk (the server's own bounds are set generously), so
// `truncated` means the same thing on both paths, including for a boundary a bound stopped.
static NSDictionary *_Nullable FBAXBridgeNodeFromSnapshot(id<FBAXRuntime> runtime,
                                                          id snapshotNode,
                                                          NSArray<NSString *> *fetchList,
                                                          NSDictionary<NSNumber *, NSString *> *namesByNumber,
                                                          pid_t ownerPid,
                                                          int depth,
                                                          int maxDepth,
                                                          int *budget,
                                                          int *boundaryFetches,
                                                          BOOL *truncated
)
{
  if (![snapshotNode isKindOfClass:NSDictionary.class]) {
    return nil;
  }
  if (*budget <= 0) {
    *truncated = YES;
    return nil;
  }

  NSArray *nesting = [((NSDictionary *)snapshotNode)[kSnapshotChildren] isKindOfClass:NSArray.class]
  ? ((NSDictionary *)snapshotNode)[kSnapshotChildren]
  : @[];
  if (ownerPid != 0 && nesting.count == 0) {
    id element = ((NSDictionary *)snapshotNode)[kSnapshotElement];
    pid_t elementPid = element ? [runtime owningProcessIdentifierForSnapshotElement:element] : 0;
    if (elementPid != 0 && elementPid != ownerPid) {
      if (depth >= maxDepth || *boundaryFetches <= 0) {
        // A bound stopped the continuation, so the subtree is missing for the same reason one below the
        // depth cap is — and is reported the same way.
        *truncated = YES;
      } else {
        (*boundaryFetches)--;
        FBAXBridgeCountRoundTrip();
        NSDictionary<NSNumber *, NSString *> *continuationNames = nil;
        NSError *continuationError = nil;
        id continuation = [runtime snapshotOfSnapshotElement:element
                                              attributeNames:fetchList
                                               namesByNumber:&continuationNames
                                                       error:&continuationError];
        if (continuation) {
          return FBAXBridgeNodeFromSnapshot(
            runtime,
            continuation,
            fetchList,
            continuationNames,
            elementPid,
            depth,
            maxDepth,
            budget,
            boundaryFetches,
            truncated
          );
        }
        // Fall through and map the stub: absence, not an error, is also the walk's answer at a boundary
        // it cannot cross.
      }
    }
  }
  (*budget)--;

  NSDictionary *attributes = ((NSDictionary *)snapshotNode)[kSnapshotAttributes];
  NSMutableDictionary *node = [NSMutableDictionary dictionary];
  if ([attributes isKindOfClass:NSDictionary.class]) {
    for (NSNumber *number in attributes) {
      NSString *name = namesByNumber[number];
      // The children attribute is answered from the snapshot's own nesting below, not copied across: it
      // arrives as raw element references, which are no use to a host reading a materialized tree.
      if (!name || [name isEqualToString:kAXChildren]) {
        continue;
      }
      // The same coercion the per-node walk applies. Without it an attribute the server answers with an
      // object — a point, an error, anything not a string or number — reaches the encoder raw and fails
      // the whole read rather than that one value.
      node[name] = FBAXBridgeJSONSafeValue(attributes[number], name);
    }
  }

  if (depth >= maxDepth) {
    if (nesting.count > 0) {
      *truncated = YES;
    }
    return node;
  }

  NSMutableArray *children = [NSMutableArray array];
  for (id child in nesting) {
    NSDictionary *built = FBAXBridgeNodeFromSnapshot(
      runtime,
      child,
      fetchList,
      namesByNumber,
      ownerPid,
      depth + 1,
      maxDepth,
      budget,
      boundaryFetches,
      truncated
    );
    if (built) {
      [children addObject:built];
    }
  }
  node[kAXChildren] = children;
  return node;
}

static NSDictionary<NSString *, id> *FBAXBridgeDispatchRequest(NSDictionary<NSString *, id> *request);

// Answers a request, turning a raise into a response. This is the only way into the dispatcher, so the
// serve loop, the argv front-end and the tests are all guarded alike. The private frameworks raise where
// they are meant to return; unguarded, the first raise unwinds out of the serve loop and costs a client
// every later request on the connection. Distinct from `FBAXBridgeSerializeResponse`'s guard, which
// covers the answer failing to be written rather than produced.
NSDictionary<NSString *, id> *FBAXBridgeHandleRequest(NSDictionary<NSString *, id> *request)
{
  @try {
    return FBAXBridgeDispatchRequest(request);
  } @catch (NSException *exception) {
    NSLog(@"[AccessibilityService] answering a request raised: %@", exception);
    return FBAXBridgeErrorResponse(
      [NSString stringWithFormat:@"the reader raised while answering: %@", exception.reason ?: exception.name]
    );
  }
}

NSDictionary<NSString *, id> *FBAXBridgeHandleRequestData(NSData *data, BOOL *_Nullable shutdownRequested)
{
  id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
  NSDictionary<NSString *, id> *response;
  if ([parsed isKindOfClass:NSDictionary.class]) {
    response = FBAXBridgeHandleRequest(parsed);
  } else {
    response = FBAXBridgeTaggedErrorResponse(@"malformed request frame", kErrorKindBadRequest, nil);
  }
  if (shutdownRequested) {
    *shutdownRequested = [response[kResponseShutdown] boolValue];
  }
  return response;
}

NSData *FBAXBridgeSerializeResponse(NSDictionary<NSString *, id> *response)
{
  // Sanitize first (non-finite numbers would otherwise raise), then still guard the call: an
  // unforeseen unserializable value must degrade to an error frame the client can read, never abort
  // the process and sever the connection.
  id sanitized = FBAXBridgeJSONSanitized(response);
  NSData *data = nil;
  if ([NSJSONSerialization isValidJSONObject:sanitized]) {
    @try {
      data = [NSJSONSerialization dataWithJSONObject:sanitized options:0 error:NULL];
    } @catch (NSException *exception) {
      NSLog(@"[AccessibilityService] response serialization raised: %@", exception);
      data = nil;
    }
  } else {
    NSLog(@"[AccessibilityService] response is not a valid JSON object; emitting an error frame");
  }
  if (data) {
    return data;
  }
  static const char *const fallback = "{\"ok\":false,\"error\":\"response serialization failed\"}";
  return [NSData dataWithBytes:fallback length:strlen(fallback)];
}

// Answers `hittest`: one round trip reading only the element at the point. With no pid it is
// display-wide, so the host learns the owning app without a separate frontmost query.
static NSDictionary *FBAXBridgeHitTest(id<FBAXRuntime> runtime, NSDictionary *request)
{
  NSNumber *xNumber = request[kRequestX];
  NSNumber *yNumber = request[kRequestY];
  if (![xNumber isKindOfClass:NSNumber.class] || ![yNumber isKindOfClass:NSNumber.class]) {
    return FBAXBridgeTaggedErrorResponse(@"hittest requires numeric x and y", kErrorKindBadRequest, nil);
  }
  NSNumber *pidNumber = [request[kRequestPid] isKindOfClass:NSNumber.class] ? request[kRequestPid] : nil;

  FBAXBridgeCountRoundTrip();

  FBAXHitTestOutcome *outcome = [runtime hitTestAtPoint:CGPointMake(xNumber.doubleValue, yNumber.doubleValue)
                                      processIdentifier:pidNumber ? pidNumber.intValue : 0];
  switch (outcome.status) {
    case FBAXHitTestStatusHit:
      break;
    case FBAXHitTestStatusApplicationUnavailable:
      return FBAXBridgeTaggedErrorResponse(
        pidNumber ? [NSString stringWithFormat:@"pid %d has no accessibility server to hit-test", pidNumber.intValue]
        : @"no accessibility server answered the system-wide hit-test",
        kErrorKindApplicationUnavailable,
        pidNumber
      );
    case FBAXHitTestStatusApplicationNotResponding:
      return FBAXBridgeTaggedErrorResponse(
        pidNumber ? [NSString stringWithFormat:@"pid %d did not answer the hit-test in time", pidNumber.intValue]
        : @"the application at the hit-test point did not answer in time",
        kErrorKindApplicationNotResponding,
        pidNumber
      );
    case FBAXHitTestStatusEmpty:
      return @{kResponseOk : @YES, kResponseEmpty : @YES};
    case FBAXHitTestStatusFailed:
    default:
      return FBAXBridgeErrorResponse(outcome.failureReason ?: @"the hit-test failed");
  }

  int budget = 1;
  BOOL truncated = NO;
  // maxDepth 0 reads just the hit element's own attributes (no child recursion) — the leaf at the point.
  id hitElement = outcome.element;
  if (!hitElement) {
    return FBAXBridgeErrorResponse(@"the hit-test reported an element but returned none");
  }
  FBAXReadOutcome *read =
  FBAXBridgeBuildNode(runtime, hitElement, FBAXBridgeFetchListForRequest(request), NO, 0, 0, &budget, &truncated);
  switch (read.status) {
    case FBAXReadStatusRead:
      break;
    case FBAXReadStatusApplicationUnavailable:
      return FBAXBridgeTaggedErrorResponse(
        [NSString stringWithFormat:@"pid %d has no accessibility server", outcome.owningProcessIdentifier],
        kErrorKindApplicationUnavailable,
        @(outcome.owningProcessIdentifier)
      );
    case FBAXReadStatusApplicationNotResponding:
      return FBAXBridgeTaggedErrorResponse(
        [NSString stringWithFormat:@"pid %d did not answer the read of the hit element in time",
         outcome.owningProcessIdentifier],
        kErrorKindApplicationNotResponding,
        @(outcome.owningProcessIdentifier)
      );
    case FBAXReadStatusFailed:
    default:
      return FBAXBridgeErrorResponse(@"failed to read the hit element");
  }
  NSDictionary<NSString *, id> *node = read.attributes;
  if (!node) {
    return FBAXBridgeErrorResponse(@"the hit element read reported success but returned no attributes");
  }
  return @{
    kResponseOk : @YES,
    kResponseTree : node,
    kResponsePid : @(outcome.owningProcessIdentifier),
  };
}

#pragma mark - Writes

// The semantic action a wire name asks for. Answers NO for a name this guest does not know, leaving
// `*action` untouched — an unrecognised action must be refused rather than quietly becoming a press.
static BOOL FBAXBridgeActionForName(NSString *name, FBAXAction *action)
{
  if ([name isEqualToString:kActionPress]) {
    *action = FBAXActionPress;
  } else if ([name isEqualToString:kActionScrollUp]) {
    *action = FBAXActionScrollUp;
  } else if ([name isEqualToString:kActionScrollDown]) {
    *action = FBAXActionScrollDown;
  } else if ([name isEqualToString:kActionScrollLeft]) {
    *action = FBAXActionScrollLeft;
  } else if ([name isEqualToString:kActionScrollRight]) {
    *action = FBAXActionScrollRight;
  } else if ([name isEqualToString:kActionScrollToVisible]) {
    *action = FBAXActionScrollToVisible;
  } else {
    return NO;
  }
  return YES;
}

// Compared in the coerced wire form: the host derived the assertion from a tree it read off this wire.
static BOOL FBAXBridgeAttributeMatches(id _Nullable actual, NSString *expected)
{
  if ([actual isKindOfClass:NSString.class]) {
    return [(NSString *)actual isEqualToString:expected];
  }
  if (!actual || actual == NSNull.null) {
    return NO;
  }
  return [[actual description] isEqualToString:expected];
}

static NSDictionary *_Nullable FBAXBridgeWriteArgumentError(NSDictionary *request)
{
  if (![request[kRequestX] isKindOfClass:NSNumber.class] || ![request[kRequestY] isKindOfClass:NSNumber.class]) {
    return FBAXBridgeTaggedErrorResponse(@"a write requires numeric x and y", kErrorKindBadRequest, nil);
  }
  NSString *assertKey = [request[kRequestAssertKey] isKindOfClass:NSString.class] ? request[kRequestAssertKey] : nil;
  NSString *assertValue = [request[kRequestAssertValue] isKindOfClass:NSString.class] ? request[kRequestAssertValue] : nil;
  if ((assertKey == nil) != (assertValue == nil)) {
    return FBAXBridgeTaggedErrorResponse(
      [NSString stringWithFormat:@"%@ and %@ are only meaningful together", kRequestAssertKey, kRequestAssertValue],
      kErrorKindBadRequest,
      nil
    );
  }
  // Only a fetched attribute can be asserted on: the host built the assertion from a node it read, so a
  // key this request does not fetch cannot have come from there.
  if (assertKey && ![FBAXBridgeFetchListForRequest(request) containsObject:assertKey]) {
    return FBAXBridgeTaggedErrorResponse(
      [NSString stringWithFormat:@"%@ is not an attribute a write can assert on", assertKey],
      kErrorKindBadRequest,
      nil
    );
  }
  return nil;
}

// Between the host's read and this hit-test the element under the point can have changed (occlusion, a
// non-rectangular element, a screen that moved on). Checking one attribute of what is actually there is
// what stops the action landing somewhere else.
static FBAXWriteOutcome *_Nullable FBAXBridgeResolveWriteTarget(id<FBAXRuntime> runtime,
                                                                NSDictionary *request,
                                                                id _Nullable *element,
                                                                pid_t *pid)
{
  NSNumber *xNumber = request[kRequestX];
  NSNumber *yNumber = request[kRequestY];
  NSString *assertKey = [request[kRequestAssertKey] isKindOfClass:NSString.class] ? request[kRequestAssertKey] : nil;
  NSString *assertValue = [request[kRequestAssertValue] isKindOfClass:NSString.class] ? request[kRequestAssertValue] : nil;

  NSNumber *pidNumber = [request[kRequestPid] isKindOfClass:NSNumber.class] ? request[kRequestPid] : nil;
  FBAXBridgeCountRoundTrip();
  FBAXHitTestOutcome *hit = [runtime hitTestAtPoint:CGPointMake(xNumber.doubleValue, yNumber.doubleValue)
                                  processIdentifier:pidNumber ? pidNumber.intValue : 0];
  switch (hit.status) {
    case FBAXHitTestStatusHit:
      break;
    case FBAXHitTestStatusEmpty:
      return [FBAXWriteOutcome empty];
    case FBAXHitTestStatusApplicationUnavailable:
      return [FBAXWriteOutcome applicationUnavailable];
    case FBAXHitTestStatusApplicationNotResponding:
      return [FBAXWriteOutcome applicationNotResponding];
    case FBAXHitTestStatusFailed:
    default:
      return [FBAXWriteOutcome failed:hit.failureReason ?: @"the hit-test failed"];
  }
  id hitElement = hit.element;
  if (!hitElement) {
    return [FBAXWriteOutcome failed:@"the hit-test reported an element but returned none"];
  }

  if (assertKey) {
    FBAXBridgeCountRoundTrip();
    FBAXReadOutcome *read = [runtime readAttributes:@[assertKey] ofElement:hitElement];
    switch (read.status) {
      case FBAXReadStatusRead:
        break;
      case FBAXReadStatusApplicationUnavailable:
        return [FBAXWriteOutcome applicationUnavailable];
      case FBAXReadStatusApplicationNotResponding:
        return [FBAXWriteOutcome applicationNotResponding];
      // An assertion that cannot be read is not an assertion that failed — the caller is owed the
      // difference between "the screen moved" and "the element could not be inspected".
      case FBAXReadStatusFailed:
      default:
        return [FBAXWriteOutcome failed:
                [NSString stringWithFormat:@"could not read %@ to check the assertion", assertKey]];
    }
    id actual = FBAXBridgeJSONSafeValue(read.attributes[assertKey], assertKey);
    if (!FBAXBridgeAttributeMatches(actual, assertValue)) {
      return [FBAXWriteOutcome assertionFailed:
              [NSString stringWithFormat:@"the element at (%.1f, %.1f) has %@ %@, expected %@",
               xNumber.doubleValue, yNumber.doubleValue, assertKey, actual, assertValue]];
    }
  }

  *element = hitElement;
  *pid = hit.owningProcessIdentifier;
  return nil;
}

// The envelope a write outcome is reported in. Total over the status, so every way a write can end has one
// answer decided in one place rather than per verb.
static NSDictionary *FBAXBridgeWriteResponse(FBAXWriteOutcome *outcome, pid_t pid)
{
  switch (outcome.status) {
    case FBAXWriteStatusWritten:
      return @{kResponseOk : @YES, kResponsePid : @(pid)};
    case FBAXWriteStatusEmpty:
      return @{kResponseOk : @YES, kResponseEmpty : @YES};
    case FBAXWriteStatusAssertionFailed:
      return @{
        kResponseOk : @NO,
        kResponseError : outcome.failureReason ?: @"the element at the point is not the one named",
        kResponseErrorKind : kErrorKindAssertionFailed,
      };
    case FBAXWriteStatusApplicationUnavailable:
      return FBAXBridgeTaggedErrorResponse(
        pid > 0 ? [NSString stringWithFormat:@"pid %d has no accessibility server to accept the write", pid]
        : @"no accessibility server answered the write",
        kErrorKindApplicationUnavailable,
        pid > 0 ? @(pid) : nil
      );
    case FBAXWriteStatusApplicationNotResponding:
      return FBAXBridgeTaggedErrorResponse(
        pid > 0 ? [NSString stringWithFormat:@"pid %d did not answer the write in time", pid]
        : @"the application did not answer the write in time",
        kErrorKindApplicationNotResponding,
        pid > 0 ? @(pid) : nil
      );
    case FBAXWriteStatusFailed:
    default:
      return FBAXBridgeErrorResponse(outcome.failureReason ?: @"the write failed");
  }
}

// Answers `perform`. No pre-check that the element accepts the action — see
// `+[FBAXWriteOutcome outcomeForWriteError:]`.
static NSDictionary *FBAXBridgePerform(id<FBAXRuntime> runtime, NSDictionary *request)
{
  id requestedAction = request[kRequestAction];
  NSString *name = [requestedAction isKindOfClass:NSString.class] ? requestedAction : nil;
  FBAXAction action = FBAXActionPress;
  if (!name || !FBAXBridgeActionForName(name, &action)) {
    return FBAXBridgeTaggedErrorResponse(
      [NSString stringWithFormat:@"unsupported action: %@", requestedAction ?: @"(nil)"],
      kErrorKindBadRequest,
      nil
    );
  }
  NSDictionary *argumentError = FBAXBridgeWriteArgumentError(request);
  if (argumentError) {
    return argumentError;
  }

  id element = nil;
  pid_t pid = 0;
  FBAXWriteOutcome *outcome = FBAXBridgeResolveWriteTarget(runtime, request, &element, &pid);
  if (!outcome) {
    FBAXBridgeCountRoundTrip();
    outcome = [runtime performAction:action onElement:element];
  }
  return FBAXBridgeWriteResponse(outcome, pid);
}

// Answers `setvalue`. Nothing an element reports says whether its value is writable, so — as with a
// `perform` — the runtime's own answer is the only judgement.
static NSDictionary *FBAXBridgeSetValue(id<FBAXRuntime> runtime, NSDictionary *request)
{
  id requestedValue = request[kRequestValue];
  if (![requestedValue isKindOfClass:NSString.class]) {
    return FBAXBridgeTaggedErrorResponse(@"setvalue requires a string value", kErrorKindBadRequest, nil);
  }
  NSDictionary *argumentError = FBAXBridgeWriteArgumentError(request);
  if (argumentError) {
    return argumentError;
  }

  id element = nil;
  pid_t pid = 0;
  FBAXWriteOutcome *outcome = FBAXBridgeResolveWriteTarget(runtime, request, &element, &pid);
  if (!outcome) {
    FBAXBridgeCountRoundTrip();
    outcome = [runtime setValue:requestedValue onElement:element];
  }
  return FBAXBridgeWriteResponse(outcome, pid);
}

static NSDictionary<NSString *, id> *FBAXBridgeDispatchRequest(NSDictionary<NSString *, id> *request)
{
  // The frame is JSON from the client, so the value can be of any type — narrow it to a string before
  // comparing, rather than sending `isEqualToString:` to whatever arrived.
  id requestedVerb = request[kRequestVerb];
  NSString *verb = [requestedVerb isKindOfClass:NSString.class] ? requestedVerb : nil;
  BOOL isDescribe = [verb isEqualToString:kVerbDescribe];
  BOOL isHitTest = [verb isEqualToString:kVerbHitTest];
  BOOL isPerform = [verb isEqualToString:kVerbPerform];
  BOOL isSetValue = [verb isEqualToString:kVerbSetValue];
  if ([verb isEqualToString:kVerbShutdown]) {
    // Answered here, above the pid check and the runtime bind: shutting down needs neither, and a
    // reader that cannot bind is exactly the one a caller most wants to be able to end.
    return @{kResponseOk : @YES, kResponseShutdown : @YES};
  }
  if (!isDescribe && !isHitTest && !isPerform && !isSetValue) {
    return FBAXBridgeTaggedErrorResponse(
      [NSString stringWithFormat:@"unsupported verb: %@", requestedVerb ?: @"(nil)"],
      kErrorKindBadRequest,
      nil
    );
  }

  // Every verb takes a `pid`, and a non-positive one names no process. The accessibility runtime does not
  // reject it — pid 0 reads back as an application with an empty tree — so it is rejected here, before
  // any setup, and every verb answers alike.
  NSNumber *requestedPid = [request[kRequestPid] isKindOfClass:NSNumber.class] ? request[kRequestPid] : nil;
  if (requestedPid && requestedPid.intValue <= 0) {
    return FBAXBridgeTaggedErrorResponse(
      [NSString stringWithFormat:@"pid %d names no application", requestedPid.intValue],
      kErrorKindApplicationUnavailable,
      requestedPid
    );
  }

  NSString *setupError = nil;
  id<FBAXRuntime> runtime = FBAXBridgeSharedRuntime(&setupError);
  if (!runtime) {
    // Neither the request nor the application can fix a reader that cannot bind; the message is the only
    // place the missing class and drifted signatures are named.
    return FBAXBridgeTaggedErrorResponse(
      setupError ?: @"accessibility setup failed",
      kErrorKindReaderUnavailable,
      nil
    );
  }

  // `hittest` is self-contained: with a pid it hit-tests that app; with no pid it hit-tests display-wide
  // — the app owning the point, resolved in-guest, with no frontmost pid query.
  if (isHitTest) {
    return FBAXBridgeHitTest(runtime, request);
  }

  // Writes are point-addressed: a one-shot guest exits between requests, so an element handle cannot
  // survive one.
  if (isPerform) {
    return FBAXBridgePerform(runtime, request);
  }
  if (isSetValue) {
    return FBAXBridgeSetValue(runtime, request);
  }

  // `describe`: an explicit `pid` names the app directly; with no pid it is a fused frontmost read — the
  // guest resolves the frontmost app in-guest (via the selected method, anchored at `x`/`y`) and reads
  // its tree in this one call, with no separate pid round-trip.
  pid_t pid = 0;
  NSString *frontmostMethod = nil;  // non-nil when the pid was resolved in-guest (fused frontmost read)
  if (requestedPid) {
    pid = requestedPid.intValue;
  } else {
    NSNumber *xNumber = request[kRequestX];
    NSNumber *yNumber = request[kRequestY];
    if (![xNumber isKindOfClass:NSNumber.class] || ![yNumber isKindOfClass:NSNumber.class]) {
      return FBAXBridgeTaggedErrorResponse(
        @"describe requires either a numeric pid or the frontmost anchor (x, y)",
        kErrorKindBadRequest,
        nil
      );
    }
    NSString *requestedMethod = [request[kRequestMethod] isKindOfClass:NSString.class] ? request[kRequestMethod] : nil;
    NSString *method = requestedMethod ?: kMethodWindowServer;
    FBAXFrontmostOutcome *frontmost =
    FBAXBridgeResolveFrontmost(runtime, method, CGPointMake(xNumber.doubleValue, yNumber.doubleValue));
    switch (frontmost.status) {
      case FBAXFrontmostStatusResolved:
        break;
      case FBAXFrontmostStatusApplicationUnavailable:
        return FBAXBridgeTaggedErrorResponse(
          frontmost.failureReason ?: @"nothing frontmost has an accessibility server",
          kErrorKindApplicationUnavailable,
          nil
        );
      case FBAXFrontmostStatusApplicationNotResponding:
        return FBAXBridgeTaggedErrorResponse(
          frontmost.failureReason ?: @"the frontmost application did not answer in time",
          kErrorKindApplicationNotResponding,
          nil
        );
      case FBAXFrontmostStatusUnresolved:
      default:
        return FBAXBridgeTaggedErrorResponse(
          frontmost.failureReason ?: @"could not resolve the frontmost application pid",
          kErrorKindFrontmostUnresolved,
          nil
        );
    }
    pid = frontmost.processIdentifier;
    frontmostMethod = method;
  }

  // Asserted before the tree is read, not after: the mode decides how much structure the read sees, so
  // asking for it afterwards would report a state this read did not benefit from.
  BOOL automationAsserted = NO;
  BOOL automationEnabled = [runtime automationModeEnabled];
  id requestedAutomation = request[kRequestAutomationMode];
  if ([requestedAutomation isKindOfClass:NSNumber.class]) {
    const BOOL wanted = [(NSNumber *)requestedAutomation boolValue];
    // Only write when it would change something. A no-op write is still a preference write, and
    // reporting `asserted` for one would tell a caller this read altered a device it left alone.
    if (wanted != automationEnabled) {
      automationEnabled = [runtime setAutomationModeEnabled:wanted];
      // True only if the write took; a preference write can be accepted and not apply.
      automationAsserted = (automationEnabled == wanted);
    }
  }

  id root = [runtime applicationElementForProcessIdentifier:pid];
  if (!root) {
    return FBAXBridgeErrorResponse([NSString stringWithFormat:@"no application element for pid %d", pid]);
  }

  int maxDepth = [request[kRequestMaxDepth] isKindOfClass:NSNumber.class]
  ? [(NSNumber *)request[kRequestMaxDepth] intValue]
  : kDefaultMaxDepth;
  int budget = [request[kRequestMaxNodes] isKindOfClass:NSNumber.class]
  ? [(NSNumber *)request[kRequestMaxNodes] intValue]
  : kDefaultNodeBudget;

  BOOL truncated = NO;
  NSDictionary *tree = nil;
  gRoundTrips = 0;
  const CFAbsoluteTime traverseStarted = CFAbsoluteTimeGetCurrent();
  if ([request[kRequestSnapshotTree] boolValue]) {
    NSArray<NSString *> *names = FBAXBridgeFetchListForRequest(request);
    NSDictionary<NSNumber *, NSString *> *namesByNumber = nil;
    NSError *snapshotError = nil;
    id snapshot = [runtime snapshotOfElement:root
                              attributeNames:names
                               namesByNumber:&namesByNumber
                                       error:&snapshotError];
    if (!snapshot) {
      return FBAXBridgeTaggedErrorResponse(
        snapshotError.localizedDescription ?: @"the single-fetch read returned no tree",
        kErrorKindApplicationNotResponding,
        @(pid)
      );
    }
    // One fetch for the whole tree, counted up-front so the boundary continuations the mapper fetches
    // land on top of it.
    gRoundTrips = 1;
    // The owner every node's element is compared against, read from the snapshot's own root element
    // rather than taken from the request: the two agree on a live runtime, and a runtime that cannot
    // attribute elements answers 0, which disables boundary continuation rather than mistargeting it.
    id rootElement = [snapshot isKindOfClass:NSDictionary.class] ? ((NSDictionary *)snapshot)[kSnapshotElement] : nil;
    pid_t ownerPid = rootElement ? [runtime owningProcessIdentifierForSnapshotElement:rootElement] : 0;
    int boundaryFetches = kSnapshotBoundaryFetchBudget;
    tree = FBAXBridgeNodeFromSnapshot(
      runtime,
      snapshot,
      names,
      namesByNumber,
      ownerPid,
      0,
      maxDepth,
      &budget,
      &boundaryFetches,
      &truncated
    );
    if (!tree) {
      return FBAXBridgeErrorResponse(@"the single-fetch read returned a shape with no root node");
    }
  } else if ([request[kRequestTranslatorVocabulary] boolValue]) {
    // Whether the application is there at all is a question only the XCTest read answers. The runtime
    // vends an application element for any pid, including one that names no process, and the translator
    // answers against it with synthesized defaults rather than failing — so without this check the read
    // would report a healthy tree for a dead process. One extra round trip, on the opt-in path only.
    NSDictionary *unavailable =
    FBAXBridgeReadFailureResponse([runtime readAttributes:@[kAXElementType] ofElement:root], pid);
    if (unavailable) {
      return unavailable;
    }
    tree = FBAXBridgeBuildTranslatorNode(runtime, root, 0, maxDepth, &budget, &truncated);
    if (!tree) {
      return FBAXBridgeErrorResponse(@"the translator vocabulary returned no attributes for this element");
    }
  } else {
    FBAXReadOutcome *read =
    FBAXBridgeBuildNode(
      runtime,
      root,
      FBAXBridgeFetchListForRequest(request),
      [request[kRequestExplainUnreachable] boolValue],
      0,
      maxDepth,
      &budget,
      &truncated
    );
    NSDictionary *failure = FBAXBridgeReadFailureResponse(read, pid);
    if (failure) {
      return failure;
    }
    tree = read.attributes;
    if (!tree) {
      return FBAXBridgeErrorResponse(@"the tree read reported success but returned no attributes");
    }
  }
  // Closed before the response is assembled, so it measures the walk and not the bookkeeping after it.
  const CFAbsoluteTime traverseDuration = CFAbsoluteTimeGetCurrent() - traverseStarted;

  // Always report the pid read, so the host tags elements with it — for a fused frontmost read the host
  // does not know the pid until now. `method` rides along when the pid was resolved in-guest.
  NSMutableDictionary *response =
  [@{kResponseOk : @YES, kResponseTree : tree, kResponseTruncated : @(truncated), kResponsePid : @(pid)} mutableCopy];
  response[kResponseAutomation] = @{
    kAutomationEnabled : @(automationEnabled),
    kAutomationAsserted : @(automationAsserted),
  };
  response[kResponsePhases] = [@{
                                 kPhaseTraverse : @(traverseDuration * 1000),
                                 kPhaseMachRoundTrips : @(gRoundTrips),
                               } mutableCopy];
  if (frontmostMethod) {
    response[kResponseMethod] = frontmostMethod;
  }
  // Enrich the wire with a fullscreen-modal descriptor when one is present in the tree (host-facing;
  // not emitted in the serialized CLI output).
  NSDictionary *modal = FBAXBridgeModalDescriptor(tree);
  if (modal) {
    response[kResponseModal] = modal;
  }
  return response;
}

#pragma mark - Argv front-end

int handleAccessibilityAction(NSString *action, NSArray<NSString *> *arguments)
{
  if ([action isEqualToString:kActionServe]) {
    NSString *socketPath = arguments.firstObject;
    if (socketPath.length == 0) {
      NSLog(@"[AccessibilityService] serve requires a socket path argument");
      return 1;
    }
    return FBAXBridgeServe(socketPath, [arguments subarrayWithRange:NSMakeRange(1, arguments.count - 1)]);
  }

  NSMutableDictionary<NSString *, id> *request = [NSMutableDictionary dictionary];
  request[kRequestVerb] = action;
  for (NSUInteger i = 0; i + 1 < arguments.count; i += 2) {
    NSString *flag = arguments[i];
    NSString *argValue = arguments[i + 1];
    if ([flag isEqualToString:@"--pid"]) {
      request[kRequestPid] = @(argValue.intValue);
    } else if ([flag isEqualToString:@"--max-depth"]) {
      request[kRequestMaxDepth] = @(argValue.intValue);
    } else if ([flag isEqualToString:@"--max-nodes"]) {
      request[kRequestMaxNodes] = @(argValue.intValue);
    } else if ([flag isEqualToString:@"--translator-vocabulary"]) {
      // Takes a value like every other flag: the argv parser walks pairs, so a valueless flag is
      // silently dropped rather than rejected.
      request[kRequestTranslatorVocabulary] = @(argValue.boolValue);
    } else if ([flag isEqualToString:@"--snapshot-tree"]) {
      request[kRequestSnapshotTree] = @([argValue boolValue]);
    } else if ([flag isEqualToString:@"--explain-unreachable"]) {
      request[kRequestExplainUnreachable] = @([argValue boolValue]);
    } else if ([flag isEqualToString:@"--attributes"]) {
      // Comma-separated, because argv is read strictly in flag/value pairs and an attribute name never
      // contains a comma. The socket transport sends the same field as a JSON array.
      request[kRequestAttributes] = [argValue componentsSeparatedByString:@","];
    } else if ([flag isEqualToString:@"--x"]) {
      request[kRequestX] = @(argValue.doubleValue);
    } else if ([flag isEqualToString:@"--y"]) {
      request[kRequestY] = @(argValue.doubleValue);
    } else if ([flag isEqualToString:@"--method"]) {
      request[kRequestMethod] = argValue;
    } else if ([flag isEqualToString:@"--action"]) {
      request[kRequestAction] = argValue;
    } else if ([flag isEqualToString:@"--value"]) {
      request[kRequestValue] = argValue;
    } else if ([flag isEqualToString:@"--assert-key"]) {
      request[kRequestAssertKey] = argValue;
    } else if ([flag isEqualToString:@"--assert-value"]) {
      request[kRequestAssertValue] = argValue;
    }
  }

  NSDictionary *response = FBAXBridgeHandleRequest(request);
  NSData *json = FBAXBridgeSerializeResponse(response);
  fwrite(json.bytes, 1, json.length, stdout);
  fputc('\n', stdout);
  return [response[kResponseOk] boolValue] ? 0 : 1;
}

#pragma mark - Testing

NSDictionary<NSString *, NSString *> *FBAXBridgeWireConstantsForTesting(void)
{
  return @{
    @"node.elementType" : kAXElementType,
    @"node.elementBaseType" : kAXElementBaseType,
    @"node.label" : kAXLabel,
    @"node.value" : kAXValue,
    @"node.identifier" : kAXIdentifier,
    @"node.frame" : kAXFrame,
    @"node.automationType" : kAXAutomationType,
    @"node.children" : kAXChildren,
    @"request.verb" : kRequestVerb,
    @"request.pid" : kRequestPid,
    @"request.maxDepth" : kRequestMaxDepth,
    @"request.maxNodes" : kRequestMaxNodes,
    @"request.automationMode" : kRequestAutomationMode,
    @"request.attributes" : kRequestAttributes,
    @"request.translatorVocabulary" : kRequestTranslatorVocabulary,
    @"request.explainUnreachable" : kRequestExplainUnreachable,
    @"node.explainedBy" : kNodeExplainedBy,
    @"node.isEnabled" : kNodeIsEnabled,
    @"node.translatorRole" : kNodeTranslatorRole,
    @"node.translatorSubrole" : kNodeTranslatorSubrole,
    @"node.traits" : kNodeTraits,
    @"node.elementIdentity" : kNodeElementIdentity,
    @"request.x" : kRequestX,
    @"request.y" : kRequestY,
    @"request.method" : kRequestMethod,
    @"request.action" : kRequestAction,
    @"request.value" : kRequestValue,
    @"request.assertKey" : kRequestAssertKey,
    @"request.assertValue" : kRequestAssertValue,
    @"envelope.ok" : kResponseOk,
    @"envelope.tree" : kResponseTree,
    @"envelope.error" : kResponseError,
    @"envelope.empty" : kResponseEmpty,
    @"envelope.errorKind" : kResponseErrorKind,
    @"envelope.errorKindApplicationUnavailable" : kErrorKindApplicationUnavailable,
    @"envelope.errorKindApplicationNotResponding" : kErrorKindApplicationNotResponding,
    @"envelope.errorKindFrontmostUnresolved" : kErrorKindFrontmostUnresolved,
    @"envelope.errorKindReaderUnavailable" : kErrorKindReaderUnavailable,
    @"envelope.errorKindBadRequest" : kErrorKindBadRequest,
    @"envelope.errorKindAssertionFailed" : kErrorKindAssertionFailed,
    @"envelope.truncated" : kResponseTruncated,
    @"envelope.pid" : kResponsePid,
    @"envelope.method" : kResponseMethod,
    @"envelope.modal" : kResponseModal,
    @"envelope.automation" : kResponseAutomation,
    @"envelope.phases" : kResponsePhases,
    @"phases.traverse" : kPhaseTraverse,
    @"phases.machRoundTrips" : kPhaseMachRoundTrips,
    @"automation.enabled" : kAutomationEnabled,
    @"automation.asserted" : kAutomationAsserted,
    @"modal.kind" : kModalKind,
    @"modal.kindSystem" : kModalKindSystem,
    @"modal.kindApp" : kModalKindApp,
    @"modal.elementType" : kModalElementType,
    @"modal.label" : kModalLabel,
    @"modal.systemAlertWindowClass" : kSystemAlertWindowClass,
    @"modal.alertControllerClassPrefix" : kAlertControllerClassPrefix,
    @"verb.describe" : kVerbDescribe,
    @"verb.hittest" : kVerbHitTest,
    @"verb.perform" : kVerbPerform,
    @"verb.setvalue" : kVerbSetValue,
    @"verb.shutdown" : kVerbShutdown,
    @"action.press" : kActionPress,
    @"action.scrollUp" : kActionScrollUp,
    @"action.scrollDown" : kActionScrollDown,
    @"action.scrollLeft" : kActionScrollLeft,
    @"action.scrollRight" : kActionScrollRight,
    @"action.scrollToVisible" : kActionScrollToVisible,
    @"method.centerPoint" : kMethodCenterPoint,
    @"method.windowServer" : kMethodWindowServer,
    @"method.runningBoard" : kMethodRunningBoard,
  };
}
