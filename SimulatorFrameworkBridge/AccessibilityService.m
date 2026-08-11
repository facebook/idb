/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "AccessibilityService.h"
#import "AccessibilityService+Testing.h"

#import <arpa/inet.h>
#import <errno.h>
#import <math.h>
#import <poll.h>
#import <sys/socket.h>
#import <sys/time.h>
#import <sys/un.h>
#import <unistd.h>

#import <CoreGraphics/CoreGraphics.h>

#import "AccessibilityRuntime.h"

// The `XC_kAXXC*` attribute keys. These MUST match `FBAXWire.Node` host-side so the emitted tree feeds
// the shared serializer (via `FBRemoteAutomationPlatformElement`) unchanged.
static NSString *const kAXElementType = @"XC_kAXXCAttributeElementType";
static NSString *const kAXElementBaseType = @"XC_kAXXCAttributeElementBaseType";
static NSString *const kAXLabel = @"XC_kAXXCAttributeLabel";
static NSString *const kAXValue = @"XC_kAXXCAttributeValue";
static NSString *const kAXIdentifier = @"XC_kAXXCAttributeIdentifier";
static NSString *const kAXFrame = @"XC_kAXXCAttributeFrame";
static NSString *const kAXAutomationType = @"XC_kAXXCAttributeAutomationType";
static NSString *const kAXChildren = @"XC_kAXXCAttributeChildren";

static NSString *const kRequestVerb = @"verb";
static NSString *const kRequestPid = @"pid";
static NSString *const kRequestMaxDepth = @"maxDepth";
static NSString *const kRequestMaxNodes = @"maxNodes";
static NSString *const kRequestX = @"x";
static NSString *const kRequestY = @"y";
// Selects how a fused frontmost read (a `describe` with no pid) resolves the foreground app. Optional;
// defaults to `center-point` (the positional system-wide hit-test).
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
// A machine-readable failure kind: what went wrong, as a closed vocabulary, so the host chooses what to
// tell the user structurally rather than by matching the free-text `error` string. The `error` still
// carries the detail — the kind decides which remedy, if any, applies to it.
//
// A failure with no kind is a reader failure with nothing further to say about it. That is the default,
// and a host that does not know a kind must treat it as one, so adding a value here degrades an older
// host's precision rather than breaking it.
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
// The resolved foreground pid a fused frontmost read reports, plus the mechanism that resolved it (a
// diagnostic tag, so a future alternate strategy is distinguishable in logs from the current one). The
// pid also tags the owning element of a hit-test result.
static NSString *const kResponsePid = @"pid";
static NSString *const kResponseMethod = @"method";
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
// Two write verbs rather than one: performing a semantic action and setting an attribute are separate
// runtime calls that take different arguments, and fusing them would leave every request carrying a field
// the other kind ignores.
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
// `center-point` is the positional system-wide hit-test — the default when a request names no method.
static NSString *const kMethodCenterPoint = @"center-point";
static NSString *const kMethodWindowServer = @"window-server";
static NSString *const kMethodRunningBoard = @"runningboard";

// Frame cap for the persistent `serve` transport: a frame larger than this is treated as a protocol
// error rather than allocating unbounded memory. This is a property of the wire protocol, so the host
// client caps reads at the same value — keep the two in step.
static const uint32_t kMaxFrameBytes = 16 * 1024 * 1024;

// A depth cap and a total-node budget guard against pathological trees. A request carries the
// caller's own bounds (the host sets them so every backend truncates alike); these apply only when it
// does not — e.g. the one-shot front-end invoked by hand.
static const int kDefaultMaxDepth = 100;
static const int kDefaultNodeBudget = 5000;

// The persistent `serve` exits after sitting idle this long — no client connected, or a connected
// client sending nothing — so an orphaned serve (the host crashed, or was replaced by the host's
// recovery path) is reaped rather than lingering. `establish` spawns the serve into the booted
// launchd domain, so it is parented to launchd_sim, not the host; there is no parent-death signal to
// watch, hence an idle timeout. A live host that pauses longer is transparently re-spawned on its next
// read, so this only ever costs a re-spawn, never correctness.
static const int kIdleTimeoutSeconds = 300;

#pragma mark - AX client setup

// Set by `FBAXBridgeSetRuntimeForTesting` to stand in for the live runtime. Nil in the product, and the
// only reason this file knows the runtime has more than one possible conformer.
static id<FBAXRuntime> gInjectedRuntime = nil;

// The runtime is bound once and reused across requests: `dlopen` + `initForRemoteAccess` is the
// dominant setup cost (~260ms), so caching it is what makes the persistent `serve` mode fast (the
// oneshot path binds it once too). Not thread-safe by design — requests are handled serially.
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

void FBAXBridgeSetRuntimeForTesting(id<FBAXRuntime> _Nullable runtime)
{
  gInjectedRuntime = runtime;
}

static NSArray<NSString *> *FBAXBridgeFetchList(void)
{
  return @[
    kAXElementType, kAXElementBaseType, kAXLabel, kAXValue, kAXIdentifier, kAXFrame, kAXAutomationType,
    kAXChildren
  ];
}

#pragma mark - JSON coercion

// The frame arrives from `attributesForElement:` as an `NSValue`-wrapped `CGRect` (or, tolerantly, an
// existing dictionary representation). Emit the CGRect dictionary representation the host consumes via
// `CGRectMakeWithDictionaryRepresentation`.
static NSDictionary *FBAXBridgeFrameDictionary(id frameValue)
{
  CGRect rect = CGRectZero;
  if ([frameValue isKindOfClass:NSDictionary.class]) {
    if (CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)frameValue, &rect)) {
      return (NSDictionary *)frameValue;
    }
  } else if ([frameValue isKindOfClass:NSValue.class]) {
    NSValue *value = (NSValue *)frameValue;
    if (strcmp(value.objCType, @encode(CGRect)) == 0) {
      [value getValue:&rect size:sizeof(rect)];
    }
  } else if (frameValue) {
    NSLog(@"[AccessibilityService] unexpected frame value class: %@", [frameValue class]);
  }
  NSDictionary *dictionary = (NSDictionary *)CFBridgingRelease(CGRectCreateDictionaryRepresentation(rect));
  return dictionary ?: @{};
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

// Recursively replaces every non-finite number in a response with null. Applied once to the whole
// response before serialization, so a non-finite value anywhere — a frame member, or any future
// numeric attribute — degrades that one value instead of killing the read.
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
  if ([value isKindOfClass:NSString.class] || [value isKindOfClass:NSNumber.class]) {
    return value;
  }
  return [value description];
}

#pragma mark - Tree walk

// One mach round-trip per node: read the element's attributes, coerce them to JSON, then recurse into
// its children (replacing the child `XCAccessibilityElement`s with their read dictionaries in place).
//
// The outcome describes only *this* element. A child that fails to read is dropped from the tree rather
// than failing the whole read, so a child's outcome never becomes the caller's.
static FBAXReadOutcome *FBAXBridgeBuildNode(id<FBAXRuntime> runtime,
                                            id element,
                                            int depth,
                                            int maxDepth,
                                            int *budget,
                                            BOOL *truncated)
{
  FBAXReadOutcome *outcome = [runtime readAttributes:FBAXBridgeFetchList() ofElement:element];
  if (outcome.status != FBAXReadStatusRead) {
    return outcome;
  }
  NSDictionary<NSString *, id> *attributes = (NSDictionary *)outcome.attributes;

  NSMutableDictionary *node = [NSMutableDictionary dictionaryWithCapacity:attributes.count];
  for (NSString *key in attributes) {
    if ([key isEqualToString:kAXChildren]) {
      continue;
    }
    node[key] = FBAXBridgeJSONSafeValue(attributes[key], key);
  }

  NSMutableArray<NSDictionary *> *children = [NSMutableArray array];
  NSArray *childElements =
  [attributes[kAXChildren] isKindOfClass:NSArray.class] ? attributes[kAXChildren] : nil;
  if (depth < maxDepth) {
    for (id child in childElements) {
      if (*budget <= 0) {
        *truncated = YES;  // the shared node budget ran out before every child was visited
        break;
      }
      (*budget)--;
      FBAXReadOutcome *childOutcome = FBAXBridgeBuildNode(runtime, child, depth + 1, maxDepth, budget, truncated);
      if (childOutcome.status == FBAXReadStatusRead) {
        [children addObject:(NSDictionary *)childOutcome.attributes];
      }
    }
  } else if (childElements.count > 0) {
    *truncated = YES;  // the depth cap stopped descent into this node's existing children
  }
  node[kAXChildren] = children;
  return [FBAXReadOutcome read:node];
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
// (the screen centre — the anchor the testmanagerd backend also uses) reads whichever element owns that
// point, and its owning pid is the frontmost app.
//
// This is a *positional* proxy for frontmost, not the window server's notion of frontmost. It agrees with
// it for a fullscreen app or the home screen, but can differ for a centred element owned by another
// process (e.g. a system modal). The other two methods resolve the authoritative frontmost.
static FBAXFrontmostOutcome *FBAXBridgeCenterPointFrontmost(id<FBAXRuntime> runtime, CGPoint anchor)
{
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
    // The next two carry the hit-test's own judgement through rather than flattening it into a generic
    // unresolved: whether the frontmost app is absent or merely slow is the difference between the caller
    // reconfiguring accessibility and the caller waiting, and only the runtime knows which it was.
    case FBAXHitTestStatusApplicationUnavailable:
      return [FBAXFrontmostOutcome applicationUnavailable:
              [NSString stringWithFormat:@"no accessibility server answered the system-wide hit-test at (%.1f, %.1f)", anchor.x, anchor.y]];
    case FBAXHitTestStatusApplicationNotResponding:
      return [FBAXFrontmostOutcome applicationNotResponding:
              [NSString stringWithFormat:@"the application at (%.1f, %.1f) did not answer the system-wide hit-test in time", anchor.x, anchor.y]];
    // `default` sits with the failure case rather than alone: a status this does not know never resolves
    // to a pid.
    case FBAXHitTestStatusFailed:
    default:
      return [FBAXFrontmostOutcome unresolved:outcome.failureReason ?: @"the system-wide hit-test failed"];
  }
}

// Resolves the frontmost application by the named `method`: `center-point` (the default) is the positional
// system-wide hit-test at `anchor`; `window-server` is the in-guest AXPTranslator query; `runningboard`
// reads the foreground app from RunningBoard's visibility endowment. `anchor` is ignored by the latter two.
//
// A request names exactly one method and gets exactly that one — there is deliberately no fallback between
// them, because a caller that asked for the authoritative frontmost is not served by silently receiving the
// positional proxy instead. The caller therefore already knows which method answered, which is why nothing
// below reports one back.
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

// Answers `hittest` from the outcome of the hit-test at the requested point: the runtime says what
// happened, and this decides what the client is told about it.
//
// A hit-test is a single round trip that reads only the element at the point (no tree walk), which is what
// makes it cheap next to a whole-tree describe. With no pid it is display-wide, so the host gets the app
// owning the point without a separate frontmost query.
static NSDictionary *FBAXBridgeHitTest(id<FBAXRuntime> runtime, NSDictionary *request)
{
  NSNumber *xNumber = request[kRequestX];
  NSNumber *yNumber = request[kRequestY];
  if (![xNumber isKindOfClass:NSNumber.class] || ![yNumber isKindOfClass:NSNumber.class]) {
    return FBAXBridgeTaggedErrorResponse(@"hittest requires numeric x and y", kErrorKindBadRequest, nil);
  }
  NSNumber *pidNumber = [request[kRequestPid] isKindOfClass:NSNumber.class] ? request[kRequestPid] : nil;

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
    // `default` sits with the failure case rather than alone: a status this does not know is reported as
    // a failure, never mistaken for a hit.
    case FBAXHitTestStatusFailed:
    default:
      return FBAXBridgeErrorResponse(outcome.failureReason ?: @"the hit-test failed");
  }

  int budget = 1;
  BOOL truncated = NO;  // a hit-test reads only the leaf at the point; truncation is not meaningful here
  // maxDepth 0 reads just the hit element's own attributes (no child recursion) — the leaf at the point.
  FBAXReadOutcome *read = FBAXBridgeBuildNode(runtime, (id)outcome.element, 0, 0, &budget, &truncated);
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
  return @{
    kResponseOk : @YES,
    kResponseTree : (NSDictionary *)read.attributes,
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

// Compares an already-JSON-coerced attribute against the assertion's wire value. The assertion is a string
// because the host derived it from a tree it read off this same wire, so the comparison is made in the form
// the wire carried — anything else would have the guest and the host disagreeing about what they both read.
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

// The arguments every write shares, checked before anything is touched. Answers the response the request is
// refused with, or nil when it is well-formed. A malformed request is the caller's to fix and is held apart
// from every failure of the reader or of the application, exactly as the read verbs hold it apart.
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
  // Only the attributes the tree walk fetches can be asserted on. That is not a restriction so much as the
  // contract: the host builds an assertion out of a node it read, and a key that never appears in a node is
  // one it could not have got from there.
  if (assertKey && ![FBAXBridgeFetchList() containsObject:assertKey]) {
    return FBAXBridgeTaggedErrorResponse(
      [NSString stringWithFormat:@"%@ is not an attribute a write can assert on", assertKey],
      kErrorKindBadRequest,
      nil
    );
  }
  return nil;
}

// Resolves what a write acts on: the element at the requested point, checked against the caller's assertion.
// The request's arguments are assumed well-formed — `FBAXBridgeWriteArgumentError` has already run.
//
// Answers nil — and only then — when the write should go ahead, having filled `element` and `pid`. Every
// other answer is the outcome the request is reported with, so a caller that gets non-nil is done. Same
// shape as `+outcomeForHitTestError:hasElement:`, for the same reason: most of the answers are not failures.
//
// The assertion is what makes a two-step write safe. A marker is resolved host-side against a tree it read
// and reaches the guest as a point, so between that read and this hit-test the element under the point can
// have changed — an occluding view, a non-rectangular element, or a screen that moved on. Verifying one
// attribute of the element actually found there is what stops the action landing somewhere else.
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
    // `default` sits with the failure case rather than alone: a status this does not know never becomes an
    // element something is written to.
    case FBAXHitTestStatusFailed:
    default:
      return [FBAXWriteOutcome failed:hit.failureReason ?: @"the hit-test failed"];
  }
  id hitElement = (id)hit.element;  // non-nil on a `Hit`, which the switch above has established

  if (assertKey) {
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
    // `default` sits with the failure case rather than alone: a status this does not know is reported as a
    // failure, never mistaken for a write that landed.
    case FBAXWriteStatusFailed:
    default:
      return FBAXBridgeErrorResponse(outcome.failureReason ?: @"the write failed");
  }
}

// Answers `perform`: resolve the element at the point, then act on it.
//
// Nothing pre-checks that the element accepts the action. `XC_kAXXCAttributeUserTestingActions` is the
// obvious candidate and is the wrong tool: no element populates it — a sweep of SpringBoard and Settings
// found it absent on all 206 nodes — so a guard built on it refuses nothing and only makes every perform
// pay an extra attribute read. The runtime's own answer is the judgement.
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
    outcome = [runtime setValue:requestedValue onElement:element];
  }
  return FBAXBridgeWriteResponse(outcome, pid);
}

NSDictionary<NSString *, id> *FBAXBridgeHandleRequest(NSDictionary<NSString *, id> *request)
{
  // The frame is JSON from the client, so the value can be of any type — narrow it to a string before
  // comparing, rather than sending `isEqualToString:` to whatever arrived.
  id requestedVerb = request[kRequestVerb];
  NSString *verb = [requestedVerb isKindOfClass:NSString.class] ? requestedVerb : nil;
  BOOL isDescribe = [verb isEqualToString:kVerbDescribe];
  BOOL isHitTest = [verb isEqualToString:kVerbHitTest];
  BOOL isPerform = [verb isEqualToString:kVerbPerform];
  BOOL isSetValue = [verb isEqualToString:kVerbSetValue];
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
    // Its own kind because it is the one failure that is about neither the request nor the application:
    // no configuration of either fixes a reader that cannot bind, and the message is the only place the
    // missing class and the drifted signatures are named.
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

  // The write verbs are point-addressed for the same reason: a one-shot guest exits between requests, so an
  // element handle cannot survive one. Naming the target and acting on it in a single request is what makes
  // a write work identically on both transports.
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
    NSString *method = requestedMethod ?: kMethodCenterPoint;
    FBAXFrontmostOutcome *frontmost =
    FBAXBridgeResolveFrontmost(runtime, method, CGPointMake(xNumber.doubleValue, yNumber.doubleValue));
    // A frontmost that did not resolve says why in its own terms. The kind is what the resolver decided,
    // not "the frontmost query failed" — a fused read of an app with no accessibility server is the same
    // condition as a `--pid` read of one, and answering it differently is what left the host guessing.
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
      // `default` sits with the unresolved case: a status this does not know has not named a pid.
      case FBAXFrontmostStatusUnresolved:
      default:
        return FBAXBridgeTaggedErrorResponse(
          frontmost.failureReason ?: @"could not resolve the frontmost application pid",
          kErrorKindFrontmostUnresolved,
          nil
        );
    }
    pid = frontmost.processIdentifier;
    // The method that answered is the method that was asked for, so the response echoes back what the
    // request selected rather than something the resolver had to report.
    frontmostMethod = method;
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
  FBAXReadOutcome *read = FBAXBridgeBuildNode(runtime, root, 0, maxDepth, &budget, &truncated);
  switch (read.status) {
    case FBAXReadStatusRead:
      break;
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
  NSDictionary *tree = (NSDictionary *)read.attributes;
  // Always report the pid read, so the host tags elements with it — for a fused frontmost read the host
  // does not know the pid until now. `method` rides along when the pid was resolved in-guest.
  NSMutableDictionary *response =
  [@{kResponseOk : @YES, kResponseTree : tree, kResponseTruncated : @(truncated), kResponsePid : @(pid)} mutableCopy];
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

#pragma mark - Persistent serve transport

static BOOL FBAXBridgeWriteFully(int fd, const void *buffer, size_t length)
{
  const char *bytes = buffer;
  size_t offset = 0;
  while (offset < length) {
    ssize_t written = send(fd, bytes + offset, length - offset, MSG_NOSIGNAL);
    if (written < 0) {
      if (errno == EINTR) {
        continue;  // interrupted by a signal, not a real failure — retry
      }
      return NO;
    }
    if (written == 0) {
      return NO;
    }
    offset += (size_t)written;
  }
  return YES;
}

static BOOL FBAXBridgeReadFully(int fd, void *buffer, size_t length)
{
  char *bytes = buffer;
  size_t offset = 0;
  while (offset < length) {
    ssize_t got = recv(fd, bytes + offset, length - offset, 0);
    if (got < 0) {
      if (errno == EINTR) {
        continue;  // interrupted by a signal — retry
      }
      return NO;
    }
    if (got == 0) {
      return NO;  // EOF: the client disconnected
    }
    offset += (size_t)got;
  }
  return YES;
}

// Serves the transport-agnostic request handler over a Unix-domain socket so a host client can reuse
// one warm process for many reads (the ~30x amortization). The framing is a 4-byte big-endian length
// prefix followed by a JSON request/response object — the same envelope the oneshot path emits. The
// host binds/connects the same `/tmp` path (host and this in-simulator process share the filesystem
// namespace as the same user, so no data-container translation is needed).
//
// This intentionally serves one client at a time, serially: the host holds a single long-lived
// connection for the session, so requests are processed one-by-one over that connection with a
// blocking read between them (the read blocks waiting for the next command — the expected interactive
// idle, not a stall). When the client disconnects, the inner read returns EOF and the outer loop
// re-`accept`s, allowing a reconnect. The process is torn down by the host at end of session.
static int FBAXBridgeServe(NSString *socketPath)
{
  int listenFd = socket(AF_UNIX, SOCK_STREAM, 0);
  if (listenFd < 0) {
    NSLog(@"[AccessibilityService] socket() failed: %s", strerror(errno));
    return 1;
  }

  struct sockaddr_un address;
  memset(&address, 0, sizeof(address));
  address.sun_family = AF_UNIX;
  if (strlen(socketPath.fileSystemRepresentation) >= sizeof(address.sun_path)) {
    NSLog(@"[AccessibilityService] socket path too long: %@", socketPath);
    close(listenFd);
    return 1;
  }
  strlcpy(address.sun_path, socketPath.fileSystemRepresentation, sizeof(address.sun_path));
  unlink(address.sun_path);

  if (bind(listenFd, (struct sockaddr *)&address, sizeof(address)) != 0) {
    NSLog(@"[AccessibilityService] bind(%@) failed: %s", socketPath, strerror(errno));
    close(listenFd);
    return 1;
  }
  if (listen(listenFd, 1) != 0) {
    NSLog(@"[AccessibilityService] listen() failed: %s", strerror(errno));
    close(listenFd);
    return 1;
  }

  // Warm the runtime up front so the first served request is already fast.
  NSString *warmupError = nil;
  FBAXBridgeSharedRuntime(&warmupError);
  NSLog(@"[AccessibilityService] serving accessibility on %@", socketPath);

  while (YES) {
    struct pollfd listenPoll = {.fd = listenFd, .events = POLLIN, .revents = 0};
    int ready = poll(&listenPoll, 1, kIdleTimeoutSeconds * 1000);
    if (ready == 0) {
      NSLog(@"[AccessibilityService] idle %ds with no client; exiting", kIdleTimeoutSeconds);
      break;  // reap this (likely orphaned) serve
    }
    if (ready < 0) {
      if (errno == EINTR) {
        continue;
      }
      break;
    }
    int connection = accept(listenFd, NULL, NULL);
    if (connection < 0) {
      if (errno == EINTR) {
        continue;
      }
      break;
    }
    // Bound the per-request wait too: a `recv` on a connected-but-idle client (or a dead host still
    // holding the socket) that blocks past the window fails, the inner loop breaks, and the outer
    // `poll` then reaps the serve if no new client arrives.
    struct timeval recvTimeout = {.tv_sec = kIdleTimeoutSeconds, .tv_usec = 0};
    setsockopt(connection, SOL_SOCKET, SO_RCVTIMEO, &recvTimeout, sizeof(recvTimeout));
    while (YES) {
      // A pool per request. `serve` never returns, so the process-lifetime pool `main` opens is never
      // popped: without this, every tree, node dictionary and attribute string autoreleased while
      // answering a request is held until the serve exits.
      @autoreleasepool {
        uint32_t frameLength = 0;
        if (!FBAXBridgeReadFully(connection, &frameLength, sizeof(frameLength))) {
          break;
        }
        frameLength = ntohl(frameLength);
        if (frameLength == 0 || frameLength > kMaxFrameBytes) {
          break;
        }
        NSMutableData *requestData = [NSMutableData dataWithLength:frameLength];
        if (!FBAXBridgeReadFully(connection, requestData.mutableBytes, frameLength)) {
          break;
        }
        id parsed = [NSJSONSerialization JSONObjectWithData:requestData options:0 error:NULL];
        NSDictionary *response = [parsed isKindOfClass:NSDictionary.class]
        ? FBAXBridgeHandleRequest(parsed)
        : FBAXBridgeTaggedErrorResponse(@"malformed request frame", kErrorKindBadRequest, nil);
        NSData *responseData = FBAXBridgeSerializeResponse(response);
        uint32_t responseLength = htonl((uint32_t)responseData.length);
        if (!FBAXBridgeWriteFully(connection, &responseLength, sizeof(responseLength))) {
          break;
        }
        if (!FBAXBridgeWriteFully(connection, responseData.bytes, responseData.length)) {
          break;
        }
      }
    }
    close(connection);
    // Loop back to accept: the host may reconnect within the session. The process is torn down by the
    // host at end of session.
  }

  close(listenFd);
  unlink(address.sun_path);
  return 0;
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
    return FBAXBridgeServe(socketPath);
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
