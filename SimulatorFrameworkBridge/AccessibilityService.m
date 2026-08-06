/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "AccessibilityService.h"
#import "AccessibilityService+Testing.h"

#import <arpa/inet.h>
#import <dlfcn.h>
#import <errno.h>
#import <math.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <poll.h>
#import <sys/socket.h>
#import <sys/time.h>
#import <sys/un.h>
#import <unistd.h>

#import <CoreGraphics/CoreGraphics.h>

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

// `kAXErrorServerNotFound`, from the AX runtime's C ABI — no SDK header available here declares it. The
// runtime returns it when a process has no accessibility server to answer: the pid is dead, or names a
// process that is not an application. It is what separates an unreadable application from the neighbouring
// codes — `kAXErrorIPCTimeout` (-25216) for a live app that is not responding, and
// `kAXErrorInvalidUIElement` (-25202) for a hit-test on genuinely empty space.
static const int32_t kAXErrorServerNotFound = -25215;
// The key `-attributesForElement:attributes:error:` reports the underlying AX runtime code under.
static NSString *const kAXAccessibilityErrorKey = @"accessibility-error";

static NSString *const kVerbDescribe = @"describe";
static NSString *const kVerbHitTest = @"hittest";
static NSString *const kActionServe = @"serve";

// The private AccessibilityPlatformTranslation framework, loaded from the booted runtime root — the same
// AXPTranslator the host bridges to for a window-server frontmost, driven here entirely in-guest.
static NSString *const kAXPTranslationPath =
@"/System/Library/PrivateFrameworks/AccessibilityPlatformTranslation.framework/AccessibilityPlatformTranslation";

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
//
// `AXUIElement` returns a *borrowed* ref owned by the element: it dies with the element, and ARC is free
// to release the element at its last use, so a caller that outlives that use must retain the ref.
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
//
// `errorOut` reports why *this* element could not be read, and is the read's only window onto the AX
// runtime's own error. Only the root caller passes one: a child that fails to read is dropped from the
// tree rather than failing the whole read, so a child's error is not the read's error.
static NSDictionary *_Nullable FBAXBridgeBuildNode(XCTAccessibilityFramework *framework,
                                                   id element,
                                                   int depth,
                                                   int maxDepth,
                                                   int *budget,
                                                   BOOL *truncated,
                                                   NSError *_Nullable *_Nullable errorOut)
{
  NSError *error = nil;
  NSDictionary *attributes = [framework attributesForElement:element
                                                  attributes:FBAXBridgeFetchList()
                                                       error:&error];
  if (![attributes isKindOfClass:NSDictionary.class]) {
    if (errorOut) {
      *errorOut = error;
    }
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
      NSDictionary *childNode = FBAXBridgeBuildNode(framework, child, depth + 1, maxDepth, budget, truncated, NULL);
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

// The bridge/token delegate for the in-guest AXPTranslator window-server frontmost. The host normally
// provides this delegate and services each per-element request over CoreSimulator; in-guest we close the
// loop locally: the callback routes every request the translator emits back into the translator's own
// `processTranslatorRequest:`, which resolves it against the guest AX server. This makes the iOS
// translator resolve the true window-server frontmost with no host round-trip. Requests are serviced
// serially by the guest, so the depth guard only bounds re-entrant sub-reads.
static NSInteger gAXPSelfServiceDepth = 0;

@interface FBAXWindowServerDelegate : NSObject
@property (nonatomic, weak) id translator;
@end
@implementation FBAXWindowServerDelegate
- (id)selfServiceCallback
{
  id translator = self.translator;
  // Resolved by name (the AXPTranslator selectors are not declared to this translation unit).
  SEL processSelector = NSSelectorFromString(@"processTranslatorRequest:");
  return ^id (id request) {
    if (gAXPSelfServiceDepth > 500) {
      return nil;
    }
    gAXPSelfServiceDepth++;
    id result = nil;
    if (translator && [translator respondsToSelector:processSelector]) {
      @try {
        result = ((id (*)(id, SEL, id)) objc_msgSend)(translator, processSelector, request);
      } @catch (NSException *exception) {
        result = nil;
      }
    }
    gAXPSelfServiceDepth--;
    return result;
  };
}

- (id)accessibilityTranslationDelegateBridgeCallbackWithToken:(NSString *)token { return [self selfServiceCallback]; }

- (id)accessibilityTranslationDelegateBridgeCallback { return [self selfServiceCallback]; }

- (CGRect)accessibilityTranslationConvertPlatformFrameToSystem:(CGRect)rect withToken:(NSString *)token { return rect; }

- (CGRect)accessibilityTranslationConvertPlatformFrameToSystem:(CGRect)rect { return rect; }

- (id)accessibilityTranslationRootParentWithToken:(NSString *)token { return nil; }

- (id)accessibilityTranslationRootParent { return nil; }

@end

// The AXPTranslator (iOS instance) wired for in-guest window-server frontmost, set up once and reused
// (installing the self-service delegate is the one-time cost). The delegate is retained here so it
// outlives the translator's weak/assign reference. Returns nil (with `*error` set) if AXPTranslator is
// unavailable.
static id _Nullable FBAXBridgeWindowServerTranslator(NSString *_Nullable *_Nullable error)
{
  static id translator;
  static FBAXWindowServerDelegate *delegate;
  static NSString *cachedError;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    dlopen(kAXPTranslationPath.fileSystemRepresentation, RTLD_NOW);
    SEL sharedSelector = NSSelectorFromString(@"sharediOSInstance");
    Class translatorClass = objc_lookUpClass("AXPTranslator");
    if (!translatorClass || ![translatorClass respondsToSelector:sharedSelector]) {
      cachedError = @"AXPTranslator unavailable — is AccessibilityPlatformTranslation loaded?";
      return;
    }
    id instance = ((id (*)(id, SEL)) objc_msgSend)(translatorClass, sharedSelector);
    if (!instance) {
      cachedError = @"AXPTranslator sharediOSInstance was nil";
      return;
    }
    FBAXWindowServerDelegate *serviceDelegate = [FBAXWindowServerDelegate new];
    serviceDelegate.translator = instance;
    @try {
      [instance setValue:serviceDelegate forKey:@"bridgeTokenDelegate"];
      [instance setValue:@YES forKey:@"supportsDelegateTokens"];
    } @catch (NSException *exception) {
      cachedError = exception.reason ?: @"failed to wire the AXPTranslator bridge delegate";
      return;
    }
    translator = instance;
    delegate = serviceDelegate;
  });
  (void)delegate;  // retained only to outlive the translator's weak reference to its bridge delegate
  if (!translator && error) {
    *error = cachedError ?: @"AXPTranslator setup failed";
  }
  return translator;
}

// Resolves the frontmost application's pid via the in-guest window-server query — the authoritative
// frontmost the host obtains through AXPTranslator, obtained here with no host round-trip. Asks the
// wired iOS translator for `frontmostApplicationWithDisplayId:0` and reads the owning pid of the
// returned application object.
static BOOL FBAXBridgeCopyWindowServerFrontmostPid(pid_t *pidOut, NSString *_Nullable *_Nullable methodOut, NSString *_Nullable *_Nullable errorOut)
{
  NSString *setupError = nil;
  id translator = FBAXBridgeWindowServerTranslator(&setupError);
  if (!translator) {
    if (errorOut) {
      *errorOut = setupError ?: @"AXPTranslator unavailable";
    }
    return NO;
  }
  SEL frontmostSelector = NSSelectorFromString(@"frontmostApplicationWithDisplayId:bridgeDelegateToken:");
  if (![translator respondsToSelector:frontmostSelector]) {
    if (errorOut) {
      *errorOut = @"AXPTranslator does not respond to frontmostApplicationWithDisplayId:";
    }
    return NO;
  }
  SEL pidSelector = NSSelectorFromString(@"pid");
  id application = ((id (*)(id, SEL, unsigned int, id)) objc_msgSend)(translator, frontmostSelector, 0, @"axbridge");
  if (!application || ![application respondsToSelector:pidSelector]) {
    if (errorOut) {
      *errorOut = @"window-server frontmost returned no application object";
    }
    return NO;
  }
  pid_t pid = ((int (*)(id, SEL)) objc_msgSend)(application, pidSelector);
  if (pid <= 0) {
    if (errorOut) {
      *errorOut = [NSString stringWithFormat:@"window-server frontmost returned no pid (%d)", pid];
    }
    return NO;
  }
  if (pidOut) {
    *pidOut = pid;
  }
  if (methodOut) {
    *methodOut = kMethodWindowServer;
  }
  return YES;
}

// The RunningBoardServices framework, loaded from the booted runtime root — driven through the ObjC
// runtime, never linked. Enumerating another process's state requires the private
// `com.apple.runningboard.process-state` entitlement, which the guest binary carries (ad-hoc signed); the
// simulator's runningboardd honors it.
static NSString *const kRunningBoardServicesPath =
@"/System/Library/PrivateFrameworks/RunningBoardServices.framework/RunningBoardServices";

// The endowment namespace RunningBoard grants a process whose scene is on-screen. The foreground app is
// the launch-services process that holds it.
static NSString *const kFrontboardVisibilityEndowment = @"com.apple.frontboard.visibility";

// Resolves the frontmost application's pid via RunningBoard: enumerate every launch-services process and
// return the one endowed with on-screen visibility (`com.apple.frontboard.visibility`). This reads the
// window server's own notion of foreground — the same pid the window-server method resolves — from the
// process-lifecycle daemon rather than the accessibility stack, so it needs neither a screen anchor nor
// the AX server.
//
// Enumerating other processes' state requires the `com.apple.runningboard.process-state` entitlement;
// without it runningboardd rejects the query with "Client not entitled". The RBS classes are resolved by
// name (they are not declared to this translation unit) and messaged defensively.
static BOOL FBAXBridgeCopyRunningBoardFrontmostPid(pid_t *pidOut, NSString *_Nullable *_Nullable methodOut, NSString *_Nullable *_Nullable errorOut)
{
  dlopen(kRunningBoardServicesPath.fileSystemRepresentation, RTLD_NOW);
  Class predicateClass = objc_lookUpClass("RBSProcessPredicate");
  Class stateClass = objc_lookUpClass("RBSProcessState");
  Class descriptorClass = objc_lookUpClass("RBSProcessStateDescriptor");
  SEL statesSelector = NSSelectorFromString(@"statesForPredicate:withDescriptor:error:");
  if (!predicateClass || !stateClass || ![stateClass respondsToSelector:statesSelector]) {
    if (errorOut) {
      *errorOut = @"RunningBoardServices unavailable — is RunningBoardServices loaded?";
    }
    return NO;
  }

  id predicate = ((id (*)(id, SEL)) objc_msgSend)(predicateClass, NSSelectorFromString(@"predicateMatchingLaunchServicesProcesses"));

  // The descriptor selects which fields RunningBoard populates. Request the endowment namespaces so each
  // returned state carries its visibility endowment: the concrete "values" bitmask is not stable across
  // OS versions, so it is set to all-bits defensively and the specific endowment namespace is named too.
  id descriptor = nil;
  if (descriptorClass) {
    descriptor = ((id (*)(id, SEL)) objc_msgSend)(descriptorClass, NSSelectorFromString(@"descriptor"));
    @try {
      SEL setValues = NSSelectorFromString(@"setValues:");
      if ([descriptor respondsToSelector:setValues]) {
        ((void (*)(id, SEL, unsigned long long)) objc_msgSend)(descriptor, setValues, ~0ull);
      }
      SEL setEndowments = NSSelectorFromString(@"setEndowmentNamespaces:");
      if ([descriptor respondsToSelector:setEndowments]) {
        ((void (*)(id, SEL, id)) objc_msgSend)(descriptor, setEndowments, @[kFrontboardVisibilityEndowment]);
      }
    } @catch (NSException *exception) {
      // fall through with the default descriptor
    }
  }

  NSError *error = nil;
  NSArray *states = ((id (*)(id, SEL, id, id, NSError **)) objc_msgSend)(stateClass, statesSelector, predicate, descriptor, &error);
  if (![states isKindOfClass:NSArray.class]) {
    if (errorOut) {
      *errorOut = [NSString stringWithFormat:@"RunningBoard process-state query failed: %@", error ?: @"(no states returned)"];
    }
    return NO;
  }

  SEL endowmentsSelector = NSSelectorFromString(@"endowmentNamespaces");
  SEL processSelector = NSSelectorFromString(@"process");
  SEL pidSelector = NSSelectorFromString(@"pid");
  for (id state in states) {
    if (![state respondsToSelector:endowmentsSelector]) {
      continue;
    }
    id endowments = ((id (*)(id, SEL)) objc_msgSend)(state, endowmentsSelector);
    if (![endowments containsObject:kFrontboardVisibilityEndowment]) {
      continue;
    }
    id process = [state respondsToSelector:processSelector] ? ((id (*)(id, SEL)) objc_msgSend)(state, processSelector) : nil;
    if (!process || ![process respondsToSelector:pidSelector]) {
      continue;
    }
    pid_t pid = ((int (*)(id, SEL)) objc_msgSend)(process, pidSelector);
    if (pid > 0) {
      if (pidOut) {
        *pidOut = pid;
      }
      if (methodOut) {
        *methodOut = kMethodRunningBoard;
      }
      return YES;
    }
  }

  if (errorOut) {
    *errorOut = @"no launch-services process holds the on-screen visibility endowment";
  }
  return NO;
}

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
    *methodOut = kMethodCenterPoint;
  }
  return YES;
}

// Resolves the frontmost pid by the requested `method`. `center-point` (default) is the positional
// system-wide hit-test at (x, y); `window-server` is the in-guest AXPTranslator query; `runningboard`
// reads the foreground app from RunningBoard's visibility endowment. `x`/`y` are the screen anchor for
// the positional method and ignored by the others.
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
  if ([method isEqualToString:kMethodWindowServer]) {
    return FBAXBridgeCopyWindowServerFrontmostPid(pidOut, methodOut, errorOut);
  }
  if ([method isEqualToString:kMethodRunningBoard]) {
    return FBAXBridgeCopyRunningBoardFrontmostPid(pidOut, methodOut, errorOut);
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

// Whether a read failed because the process has no accessibility server to answer it, rather than
// because the read itself went wrong. This is the one failure the host maps onto a typed,
// backend-neutral error, so it is recognised by the runtime's own code rather than inferred.
static BOOL FBAXBridgeIsApplicationUnavailableError(NSError *_Nullable error)
{
  NSNumber *code = error.userInfo[kAXAccessibilityErrorKey];
  return [code isKindOfClass:NSNumber.class] && code.intValue == kAXErrorServerNotFound;
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
//
// The hit-test seed is the system-wide element when no pid is given — a display-wide hit-test that finds
// whichever app owns the point, so the host needs no separate frontmost pid query (one IPC hop for
// `describe(.point)` / `hitTest`) — or a specific app's element when a pid is given. The owning pid of
// the hit element is always reported, so the host can tag it (for the system-wide case it did not know
// the pid in advance).
static NSDictionary *FBAXBridgeHitTest(XCTAccessibilityFramework *framework,
                                       Class elementClass,
                                       NSDictionary *request)
{
  NSNumber *xNumber = request[kRequestX];
  NSNumber *yNumber = request[kRequestY];
  if (![xNumber isKindOfClass:NSNumber.class] || ![yNumber isKindOfClass:NSNumber.class]) {
    return FBAXBridgeErrorResponse(@"hittest requires numeric x and y");
  }
  FBAXCopyElementAtPositionFn copyElementAtPosition = dlsym(RTLD_DEFAULT, "AXUIElementCopyElementAtPosition");
  FBAXGetPidFn getPid = dlsym(RTLD_DEFAULT, "AXUIElementGetPid");
  if (!copyElementAtPosition || !getPid) {
    return FBAXBridgeErrorResponse(@"AXUIElementCopyElementAtPosition/GetPid unavailable");
  }

  // Resolve the seed: a specific app element for an explicit pid, otherwise the system-wide element.
  // Owned (+1) either way, so the ref outlives whatever vended it and both branches release alike.
  void *seed = NULL;
  NSNumber *pidNumber = [request[kRequestPid] isKindOfClass:NSNumber.class] ? request[kRequestPid] : nil;
  if (pidNumber) {
    XCAccessibilityElement *root = [(id)elementClass elementWithProcessIdentifier:pidNumber.intValue];
    if (!root) {
      return FBAXBridgeErrorResponse([NSString stringWithFormat:@"no application element for pid %d", pidNumber.intValue]);
    }
    void *applicationElement = [root AXUIElement];
    if (!applicationElement) {
      return FBAXBridgeErrorResponse([NSString stringWithFormat:@"no AXUIElement for pid %d", pidNumber.intValue]);
    }
    seed = (void *)CFRetain(applicationElement);
  } else {
    FBAXCreateSystemWideFn createSystemWide = dlsym(RTLD_DEFAULT, "AXUIElementCreateSystemWide");
    if (!createSystemWide) {
      return FBAXBridgeErrorResponse(@"AXUIElementCreateSystemWide unavailable");
    }
    seed = createSystemWide();
    if (!seed) {
      return FBAXBridgeErrorResponse(@"AXUIElementCreateSystemWide returned NULL");
    }
  }

  void *hit = NULL;
  int32_t axError = copyElementAtPosition(seed, (float)xNumber.doubleValue, (float)yNumber.doubleValue, &hit);
  CFRelease(seed);
  if (axError == kAXErrorServerNotFound) {
    // Nothing answered the hit-test at all. Reporting that as an empty result would tell the caller the
    // app is on screen with nothing under the point, which is the opposite of what happened.
    return FBAXBridgeApplicationUnavailableResponse(
      pidNumber ? [NSString stringWithFormat:@"pid %d has no accessibility server to hit-test", pidNumber.intValue]
      : @"no accessibility server answered the system-wide hit-test"
    );
  }
  if (axError != 0 || !hit) {
    // No element at the point is a valid empty result, not a failure: a caller doing a streaming
    // hit-test (e.g. after a tap) must be able to tell "empty space" apart from "the reader broke".
    return @{kResponseOk : @YES, kResponseEmpty : @YES};
  }
  // The host tags the hit element with its owning process, so an unattributable hit is not a result. A
  // seeded hit-test already knows the pid and falls back to it; a system-wide one has no other source.
  pid_t owningPid = 0;
  int32_t pidError = getPid(hit, &owningPid);
  if (pidError != 0 || owningPid <= 0) {
    if (!pidNumber) {
      CFRelease(hit);
      return FBAXBridgeErrorResponse([NSString stringWithFormat:@"could not resolve the owning pid of the hit element (%d)", pidError]);
    }
    owningPid = pidNumber.intValue;
  }
  XCAccessibilityElement *hitElement = [(id)elementClass elementWithAXUIElement:hit];
  int budget = 1;
  BOOL truncated = NO;  // a hit-test reads only the leaf at the point; truncation is not meaningful here
  NSError *readError = nil;
  // maxDepth 0 reads just the hit element's own attributes (no child recursion) — the leaf at the point.
  NSDictionary *node = hitElement ? FBAXBridgeBuildNode(framework, hitElement, 0, 0, &budget, &truncated, &readError) : nil;
  CFRelease(hit);  // +1-retained by the Copy; the node has already been read from it above.
  if (!node) {
    if (FBAXBridgeIsApplicationUnavailableError(readError)) {
      return FBAXBridgeApplicationUnavailableResponse([NSString stringWithFormat:@"pid %d has no accessibility server", owningPid]);
    }
    return FBAXBridgeErrorResponse(@"failed to read the hit element");
  }
  return @{kResponseOk : @YES, kResponseTree : node, kResponsePid : @(owningPid)};
}

NSDictionary<NSString *, id> *FBAXBridgeHandleRequest(NSDictionary<NSString *, id> *request)
{
  // The frame is JSON from the client, so the value can be of any type — narrow it to a string before
  // comparing, rather than sending `isEqualToString:` to whatever arrived.
  id requestedVerb = request[kRequestVerb];
  NSString *verb = [requestedVerb isKindOfClass:NSString.class] ? requestedVerb : nil;
  BOOL isDescribe = [verb isEqualToString:kVerbDescribe];
  BOOL isHitTest = [verb isEqualToString:kVerbHitTest];
  if (!isDescribe && !isHitTest) {
    return FBAXBridgeErrorResponse([NSString stringWithFormat:@"unsupported verb: %@", requestedVerb ?: @"(nil)"]);
  }

  // Both verbs take a `pid`, and a non-positive one names no process. The accessibility runtime does not
  // reject it — pid 0 reads back as an application with an empty tree — so it is rejected here, before
  // any setup, and both verbs answer alike.
  NSNumber *requestedPid = [request[kRequestPid] isKindOfClass:NSNumber.class] ? request[kRequestPid] : nil;
  if (requestedPid && requestedPid.intValue <= 0) {
    return FBAXBridgeApplicationUnavailableResponse([NSString stringWithFormat:@"pid %d names no application", requestedPid.intValue]);
  }

  NSString *setupError = nil;
  XCTAccessibilityFramework *framework = FBAXBridgeSharedFramework(&setupError);
  if (!framework) {
    return FBAXBridgeErrorResponse(setupError ?: @"accessibility setup failed");
  }

  Class elementClass = objc_lookUpClass("XCAccessibilityElement");
  if (!elementClass) {
    return FBAXBridgeErrorResponse(@"XCAccessibilityElement unavailable");
  }

  // `hittest` is self-contained: with a pid it hit-tests that app; with no pid it hit-tests the
  // system-wide element — the app owning the point, resolved in-guest, with no frontmost pid query.
  if (isHitTest) {
    return FBAXBridgeHitTest(framework, elementClass, request);
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
      return FBAXBridgeErrorResponse(@"describe requires either a numeric pid or the frontmost anchor (x, y)");
    }
    NSString *frontmostError = nil;
    NSString *requestedMethod = [request[kRequestMethod] isKindOfClass:NSString.class] ? request[kRequestMethod] : nil;
    if (!FBAXBridgeResolveFrontmostPid(requestedMethod, xNumber.floatValue, yNumber.floatValue, &pid, &frontmostMethod, &frontmostError)) {
      return FBAXBridgeErrorResponse(frontmostError ?: @"could not resolve the frontmost application pid");
    }
  }

  XCAccessibilityElement *root = [(id)elementClass elementWithProcessIdentifier:pid];
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
  NSError *readError = nil;
  NSDictionary *tree = FBAXBridgeBuildNode(framework, root, 0, maxDepth, &budget, &truncated, &readError);
  if (!tree) {
    if (FBAXBridgeIsApplicationUnavailableError(readError)) {
      return FBAXBridgeApplicationUnavailableResponse([NSString stringWithFormat:@"pid %d has no accessibility server", pid]);
    }
    return FBAXBridgeErrorResponse(
      [NSString stringWithFormat:@"failed to read the element tree for pid %d: %@",
       pid,
       readError.localizedDescription ?: @"the accessibility runtime reported no error"]
    );
  }
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
    @"envelope.ok" : kResponseOk,
    @"envelope.tree" : kResponseTree,
    @"envelope.error" : kResponseError,
    @"envelope.empty" : kResponseEmpty,
    @"envelope.errorKind" : kResponseErrorKind,
    @"envelope.errorKindApplicationUnavailable" : kErrorKindApplicationUnavailable,
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
    @"method.centerPoint" : kMethodCenterPoint,
    @"method.windowServer" : kMethodWindowServer,
    @"method.runningBoard" : kMethodRunningBoard,
  };
}
