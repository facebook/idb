/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "AccessibilityService.h"

#import <arpa/inet.h>
#import <dlfcn.h>
#import <errno.h>
#import <math.h>
#import <objc/runtime.h>
#import <poll.h>
#import <sys/socket.h>
#import <sys/time.h>
#import <sys/un.h>
#import <unistd.h>

#import <CoreGraphics/CoreGraphics.h>

// The `XC_kAXXC*` attribute keys. These MUST match `FBRemoteAutomationAXAttribute` host-side so the
// emitted tree feeds the shared serializer (`FBRemoteAutomationPlatformElement`) unchanged.
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
// Selects how a frontmost read (the `frontmost` verb) resolves the foreground app. Optional; defaults to
// `center-point` (the positional system-wide hit-test).
static NSString *const kRequestMethod = @"method";
static NSString *const kResponseOk = @"ok";
static NSString *const kResponseTree = @"tree";
static NSString *const kResponseError = @"error";
// A successful hit-test that found no element at the point: `{ok:true, empty:true}` — distinct from a
// reader failure (`{ok:false, error:...}`), so the host can tell empty space from a broken reader.
static NSString *const kResponseEmpty = @"empty";
// A machine-readable failure kind. The host maps exactly one failure — a pid that names no readable
// application — to a backend-neutral error; tagging it here lets the host recognize it structurally
// rather than matching the free-text `error` string. Every other failure carries no kind.
static NSString *const kResponseErrorKind = @"error_kind";
static NSString *const kErrorKindApplicationUnavailable = @"application_unavailable";
// A whole-tree read whose walk was cut short by the depth cap or the node budget: the returned tree is
// a partial view, so the host can warn rather than pass it off as complete. Absent or `false` means the
// walk visited every element within the bounds.
static NSString *const kResponseTruncated = @"truncated";
// The frontmost-application response: the resolved foreground pid, plus the mechanism that resolved it
// (a diagnostic tag, so a future alternate strategy is distinguishable in logs from the current one).
static NSString *const kResponsePid = @"pid";
static NSString *const kResponseMethod = @"method";

static NSString *const kVerbDescribe = @"describe";
static NSString *const kVerbHitTest = @"hittest";
// Resolves the frontmost application's pid entirely in-guest — a system-wide hit-test at the caller's
// screen-anchor point, with no host-side CoreSimulator AX round-trip.
static NSString *const kVerbFrontmost = @"frontmost";
static NSString *const kActionServe = @"serve";

// The `method` a successful `frontmost` response reports (the mechanism that answered).
static NSString *const kFrontmostMethodSystemWideHitTest = @"system_wide_hit_test";

// Frontmost-resolution methods a request may select (the `method` request key). `center-point` is the
// positional system-wide hit-test (default); other methods are added in later changes and slot into the
// resolution dispatcher below.
static NSString *const kMethodCenterPoint = @"center-point";

// Frame cap for the persistent `serve` transport: a frame larger than this is treated as a protocol
// error rather than allocating unbounded memory. This is a property of the wire protocol, so the host
// client caps reads at the same value — keep the two in step.
static const uint32_t kMaxFrameBytes = 16 * 1024 * 1024;

// The private frameworks are loaded from the booted runtime root at these paths (spike-proven via
// `simctl spawn`); they are driven through the ObjC runtime, never linked.
static NSString *const kAXRuntimePath =
@"/System/Library/PrivateFrameworks/AXRuntime.framework/AXRuntime";
static NSString *const kXCTAutomationSupportPath =
@"/Developer/Library/PrivateFrameworks/XCTAutomationSupport.framework/XCTAutomationSupport";

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

// File-local declarations of the private classes we drive. The classes are `dlopen`-loaded and
// resolved via `objc_lookUpClass`, so we never reference the class symbols at link time; these
// interfaces exist only to type the instance/class messages (avoiding raw `objc_msgSend`).
@interface XCTAccessibilityFramework : NSObject
- (instancetype)initForRemoteAccess;
- (nullable NSDictionary *)attributesForElement:(id)element
                                     attributes:(NSArray<NSString *> *)attributes
                                          error:(NSError **)error;
@end

@interface XCAccessibilityElement : NSObject
+ (nullable instancetype)elementWithProcessIdentifier:(pid_t)pid;
// The bridge to/from the raw AXRuntime `AXUIElementRef` (an opaque CFType, held as `void *` here so we
// avoid linking the AX C types): `AXUIElement` unwraps the application element for a point hit-test,
// and `elementWithAXUIElement:` re-wraps the hit result so the normal attribute reader can read it.
+ (nullable instancetype)elementWithAXUIElement:(void *)axUIElement;
- (void *)AXUIElement;
@end

// `AXUIElementCopyElementAtPosition(app, x, y, &out)` (AXRuntime) — a single-round-trip hit-test that
// returns just the element at a point, resolved by `dlsym` because AXRuntime is `dlopen`-loaded rather
// than linked. Returns 0 (kAXErrorSuccess) and a +1-retained element on success; x/y are 32-bit float.
typedef int32_t (*FBAXCopyElementAtPositionFn)(void *application, float x, float y, void **element);

// The AXRuntime C functions used to resolve the frontmost application in-guest, resolved by `dlsym` for
// the same reason (AXRuntime is `dlopen`-loaded, not linked). AXUIElementRefs are opaque CFTypes held
// as `void *` here to avoid linking the AX C types.
//   - `AXUIElementCreateSystemWide()` returns the +1-retained system-wide element — the seed for a
//     display-wide (rather than pid-scoped) hit-test.
//   - `AXUIElementGetPid(el, &pid)` reads an element's owning pid (no ownership transfer), which for the
//     element hit at the screen anchor is the frontmost app's pid.
//
// `AXFocusedApplication` on the system-wide element is deliberately *not* used: the simulator's AX
// server reports it as kAXErrorNoValue (unlike macOS), so focus is resolved positionally instead.
typedef void *(*FBAXCreateSystemWideFn)(void);
typedef int32_t (*FBAXGetPidFn)(void *element, pid_t *pid);

#pragma mark - AX client setup

static XCTAccessibilityFramework *_Nullable FBAXBridgeMakeFramework(NSString *_Nullable *_Nullable error)
{
  dlopen(kAXRuntimePath.fileSystemRepresentation, RTLD_NOW);
  dlopen(kXCTAutomationSupportPath.fileSystemRepresentation, RTLD_NOW);
  Class frameworkClass = objc_lookUpClass("XCTAccessibilityFramework");
  if (!frameworkClass) {
    if (error) {
      *error = @"XCTAccessibilityFramework unavailable — is XCTAutomationSupport loaded?";
    }
    return nil;
  }
  XCTAccessibilityFramework *framework =
  [(XCTAccessibilityFramework *)[frameworkClass alloc] initForRemoteAccess];
  if (!framework) {
    if (error) {
      *error = @"initForRemoteAccess returned nil";
    }
    return nil;
  }
  return framework;
}

// The framework is created once and reused across requests: `dlopen` + `initForRemoteAccess` is the
// dominant setup cost (~260ms), so caching it is what makes the persistent `serve` mode fast (the
// oneshot path creates it once too). Not thread-safe by design — requests are handled serially.
static XCTAccessibilityFramework *_Nullable FBAXBridgeSharedFramework(NSString *_Nullable *_Nullable error)
{
  static XCTAccessibilityFramework *shared;
  static NSString *cachedError;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    NSString *setupError = nil;
    shared = FBAXBridgeMakeFramework(&setupError);
    cachedError = setupError;
  });
  if (!shared && error) {
    *error = cachedError ?: @"accessibility setup failed";
  }
  return shared;
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
static NSDictionary *_Nullable FBAXBridgeBuildNode(XCTAccessibilityFramework *framework,
                                                   id element,
                                                   int depth,
                                                   int maxDepth,
                                                   int *budget,
                                                   BOOL *truncated)
{
  NSError *error = nil;
  NSDictionary *attributes = [framework attributesForElement:element
                                                  attributes:FBAXBridgeFetchList()
                                                       error:&error];
  if (![attributes isKindOfClass:NSDictionary.class]) {
    return nil;
  }

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
      NSDictionary *childNode = FBAXBridgeBuildNode(framework, child, depth + 1, maxDepth, budget, truncated);
      if (childNode) {
        [children addObject:childNode];
      }
    }
  } else if (childElements.count > 0) {
    *truncated = YES;  // the depth cap stopped descent into this node's existing children
  }
  node[kAXChildren] = children;
  return node;
}

#pragma mark - Frontmost resolution

// Resolves the frontmost application's pid entirely in-guest, with no host-side CoreSimulator AX
// round-trip: a system-wide hit-test at the caller's screen anchor (the screen centre — the anchor the
// testmanagerd backend also uses) reads whichever element owns that point, and its owning pid is the
// frontmost app.
//
// This is a *positional* proxy for frontmost, not the window server's notion of frontmost. It agrees
// with it for a fullscreen app or the home screen, but can differ for a centred element owned by another
// process (e.g. a system modal). Alternate methods that resolve the authoritative frontmost are added in
// later changes and dispatched through `FBAXBridgeResolveFrontmostPid`.
//
// The AX runtime must already be loaded (the caller warms `FBAXBridgeSharedFramework` first, which
// `dlopen`s AXRuntime and registers the remote-access client context the AX server answers to). Returns
// YES with `*pidOut`/`*methodOut` set, or NO with `*errorOut` set to a diagnostic message.
static BOOL FBAXBridgeCopyForegroundPid(float x, float y, pid_t *pidOut, NSString *_Nullable *_Nullable methodOut, NSString *_Nullable *_Nullable errorOut)
{
  FBAXCreateSystemWideFn createSystemWide = dlsym(RTLD_DEFAULT, "AXUIElementCreateSystemWide");
  FBAXCopyElementAtPositionFn copyElementAtPosition = dlsym(RTLD_DEFAULT, "AXUIElementCopyElementAtPosition");
  FBAXGetPidFn getPid = dlsym(RTLD_DEFAULT, "AXUIElementGetPid");
  if (!createSystemWide || !copyElementAtPosition || !getPid) {
    if (errorOut) {
      *errorOut = @"AXUIElementCreateSystemWide/CopyElementAtPosition/GetPid unavailable";
    }
    return NO;
  }

  void *systemWide = createSystemWide();
  if (!systemWide) {
    if (errorOut) {
      *errorOut = @"AXUIElementCreateSystemWide returned NULL";
    }
    return NO;
  }

  void *hit = NULL;
  int32_t axError = copyElementAtPosition(systemWide, x, y, &hit);
  CFRelease(systemWide);
  if (axError != 0 || !hit) {
    // No element at the anchor: an app mid-launch whose AX tree is not up yet, or a genuinely empty
    // point. The host treats this as "not ready" and retries, so surface it as a resolution failure.
    if (errorOut) {
      *errorOut = [NSString stringWithFormat:@"system-wide hit-test at (%.1f, %.1f) found no element (axError %d)", x, y, axError];
    }
    return NO;
  }

  pid_t pid = 0;
  axError = getPid(hit, &pid);
  CFRelease(hit);
  if (axError != 0 || pid <= 0) {
    if (errorOut) {
      *errorOut = [NSString stringWithFormat:@"AXUIElementGetPid failed (axError %d, pid %d)", axError, pid];
    }
    return NO;
  }

  if (pidOut) {
    *pidOut = pid;
  }
  if (methodOut) {
    *methodOut = kFrontmostMethodSystemWideHitTest;
  }
  return YES;
}

// Resolves the frontmost pid by the requested `method`. `center-point` (default) is the positional
// system-wide hit-test at (x, y); other methods slot in here as they are added. `x`/`y` are the screen
// anchor for the positional method and ignored by the others.
static BOOL FBAXBridgeResolveFrontmostPid(NSString *_Nullable method,
                                          float x,
                                          float y,
                                          pid_t *pidOut,
                                          NSString *_Nullable *_Nullable methodOut,
                                          NSString *_Nullable *_Nullable errorOut)
{
  if (!method || [method isEqualToString:kMethodCenterPoint]) {
    return FBAXBridgeCopyForegroundPid(x, y, pidOut, methodOut, errorOut);
  }
  if (errorOut) {
    *errorOut = [NSString stringWithFormat:@"unsupported frontmost method: %@", method];
  }
  return NO;
}

#pragma mark - Request handling

static NSDictionary *FBAXBridgeErrorResponse(NSString *message)
{
  return @{kResponseOk : @NO, kResponseError : message};
}

static NSDictionary *FBAXBridgeApplicationUnavailableResponse(NSString *message)
{
  return @{kResponseOk : @NO, kResponseError : message, kResponseErrorKind : kErrorKindApplicationUnavailable};
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

// A single-round-trip hit-test: `AXUIElementCopyElementAtPosition` returns just the element at (x, y),
// which is re-wrapped and read once (no tree walk) — ~1 mach round-trip vs the whole-tree walk's N.
static NSDictionary *FBAXBridgeHitTest(XCTAccessibilityFramework *framework,
                                       Class elementClass,
                                       XCAccessibilityElement *root,
                                       NSDictionary *request,
                                       pid_t pid)
{
  NSNumber *xNumber = request[kRequestX];
  NSNumber *yNumber = request[kRequestY];
  if (![xNumber isKindOfClass:NSNumber.class] || ![yNumber isKindOfClass:NSNumber.class]) {
    return FBAXBridgeErrorResponse(@"hittest requires numeric x and y");
  }
  FBAXCopyElementAtPositionFn copyElementAtPosition = dlsym(RTLD_DEFAULT, "AXUIElementCopyElementAtPosition");
  if (!copyElementAtPosition) {
    return FBAXBridgeErrorResponse(@"AXUIElementCopyElementAtPosition unavailable");
  }
  void *appElement = [root AXUIElement];
  if (!appElement) {
    return FBAXBridgeErrorResponse([NSString stringWithFormat:@"no AXUIElement for pid %d", pid]);
  }
  void *hit = NULL;
  int32_t axError = copyElementAtPosition(appElement, (float)xNumber.doubleValue, (float)yNumber.doubleValue, &hit);
  if (axError != 0 || !hit) {
    // No element at the point is a valid empty result, not a failure: a caller doing a streaming
    // hit-test (e.g. after a tap) must be able to tell "empty space" apart from "the reader broke".
    return @{kResponseOk : @YES, kResponseEmpty : @YES};
  }
  XCAccessibilityElement *hitElement = [(id)elementClass elementWithAXUIElement:hit];
  int budget = 1;
  BOOL truncated = NO;  // a hit-test reads only the leaf at the point; truncation is not meaningful here
  // maxDepth 0 reads just the hit element's own attributes (no child recursion) — the leaf at the point.
  NSDictionary *node = hitElement ? FBAXBridgeBuildNode(framework, hitElement, 0, 0, &budget, &truncated) : nil;
  CFRelease(hit);  // +1-retained by the Copy; the node has already been read from it above.
  if (!node) {
    return FBAXBridgeErrorResponse(@"failed to read the hit element");
  }
  return @{kResponseOk : @YES, kResponseTree : node};
}

NSDictionary<NSString *, id> *FBAXBridgeHandleRequest(NSDictionary<NSString *, id> *request)
{
  NSString *verb = request[kRequestVerb];
  BOOL isDescribe = [verb isEqualToString:kVerbDescribe];
  BOOL isHitTest = [verb isEqualToString:kVerbHitTest];
  BOOL isFrontmost = [verb isEqualToString:kVerbFrontmost];
  if (!isDescribe && !isHitTest && !isFrontmost) {
    return FBAXBridgeErrorResponse([NSString stringWithFormat:@"unsupported verb: %@", verb ?: @"(nil)"]);
  }

  NSString *setupError = nil;
  XCTAccessibilityFramework *framework = FBAXBridgeSharedFramework(&setupError);
  if (!framework) {
    return FBAXBridgeErrorResponse(setupError ?: @"accessibility setup failed");
  }

  // `frontmost` resolves the foreground pid via the selected method (default: a system-wide hit-test at
  // the caller's screen anchor) — no input pid — so it is handled before the pid-scoped describe/hittest.
  if (isFrontmost) {
    NSNumber *xNumber = request[kRequestX];
    NSNumber *yNumber = request[kRequestY];
    if (![xNumber isKindOfClass:NSNumber.class] || ![yNumber isKindOfClass:NSNumber.class]) {
      return FBAXBridgeErrorResponse(@"frontmost requires numeric x and y (the screen anchor point)");
    }
    pid_t frontmostPid = 0;
    NSString *method = nil;
    NSString *frontmostError = nil;
    NSString *requestedMethod = [request[kRequestMethod] isKindOfClass:NSString.class] ? request[kRequestMethod] : nil;
    if (!FBAXBridgeResolveFrontmostPid(requestedMethod, xNumber.floatValue, yNumber.floatValue, &frontmostPid, &method, &frontmostError)) {
      return FBAXBridgeErrorResponse(frontmostError ?: @"could not resolve the frontmost application pid");
    }
    return @{kResponseOk : @YES, kResponsePid : @(frontmostPid), kResponseMethod : method ?: @""};
  }

  NSNumber *pidNumber = request[kRequestPid];
  if (![pidNumber isKindOfClass:NSNumber.class]) {
    return FBAXBridgeErrorResponse(@"request requires a numeric pid");
  }
  pid_t pid = pidNumber.intValue;

  Class elementClass = objc_lookUpClass("XCAccessibilityElement");
  if (!elementClass) {
    return FBAXBridgeErrorResponse(@"XCAccessibilityElement unavailable");
  }
  XCAccessibilityElement *root = [(id)elementClass elementWithProcessIdentifier:pid];
  if (!root) {
    return FBAXBridgeApplicationUnavailableResponse([NSString stringWithFormat:@"no application element for pid %d", pid]);
  }

  if (isHitTest) {
    return FBAXBridgeHitTest(framework, elementClass, root, request, pid);
  }

  int maxDepth = [request[kRequestMaxDepth] isKindOfClass:NSNumber.class]
  ? [(NSNumber *)request[kRequestMaxDepth] intValue]
  : kDefaultMaxDepth;
  int budget = [request[kRequestMaxNodes] isKindOfClass:NSNumber.class]
  ? [(NSNumber *)request[kRequestMaxNodes] intValue]
  : kDefaultNodeBudget;
  BOOL truncated = NO;
  NSDictionary *tree = FBAXBridgeBuildNode(framework, root, 0, maxDepth, &budget, &truncated);
  if (!tree) {
    return FBAXBridgeErrorResponse([NSString stringWithFormat:@"failed to read the element tree for pid %d", pid]);
  }
  return @{kResponseOk : @YES, kResponseTree : tree, kResponseTruncated : @(truncated)};
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

  // Warm the framework up front so the first served request is already fast.
  NSString *warmupError = nil;
  FBAXBridgeSharedFramework(&warmupError);
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
      : FBAXBridgeErrorResponse(@"malformed request frame");
      NSData *responseData = FBAXBridgeSerializeResponse(response);
      uint32_t responseLength = htonl((uint32_t)responseData.length);
      if (!FBAXBridgeWriteFully(connection, &responseLength, sizeof(responseLength))) {
        break;
      }
      if (!FBAXBridgeWriteFully(connection, responseData.bytes, responseData.length)) {
        break;
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
    }
  }

  NSDictionary *response = FBAXBridgeHandleRequest(request);
  NSData *json = FBAXBridgeSerializeResponse(response);
  fwrite(json.bytes, 1, json.length, stdout);
  fputc('\n', stdout);
  return [response[kResponseOk] boolValue] ? 0 : 1;
}
