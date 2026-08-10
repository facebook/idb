/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "AccessibilityRuntime.h"

#import <dlfcn.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "AXPTranslationPrivate.h"
#import "AXRuntimePrivate.h"
#import "RunningBoardServicesPrivate.h"
#import "XCTAutomationSupportPrivate.h"

#pragma mark - Outcomes

@implementation FBAXReadOutcome

- (instancetype)initWithStatus:(FBAXReadStatus)status
                    attributes:(nullable NSDictionary<NSString *, id> *)attributes
                         error:(nullable NSError *)error
{
  self = [super init];
  if (!self) {
    return nil;
  }
  _status = status;
  _attributes = [attributes copy];
  _error = error;
  return self;
}

+ (instancetype)read:(NSDictionary<NSString *, id> *)attributes
{
  return [[self alloc] initWithStatus:FBAXReadStatusRead attributes:attributes error:nil];
}

+ (instancetype)applicationUnavailable
{
  return [[self alloc] initWithStatus:FBAXReadStatusApplicationUnavailable attributes:nil error:nil];
}

+ (instancetype)failed:(nullable NSError *)error
{
  return [[self alloc] initWithStatus:FBAXReadStatusFailed attributes:nil error:error];
}

+ (instancetype)failureForAttributeError:(nullable NSError *)error
{
  // FBAXErrorServerNotFound means nothing answered, rather than that the answer was bad — the one failure
  // the host maps onto a typed, backend-neutral error, so it is recognised by the code the runtime
  // reports rather than by matching on a message.
  NSNumber *code = error.userInfo[FBAXAccessibilityErrorKey];
  if ([code isKindOfClass:NSNumber.class] && code.intValue == FBAXErrorServerNotFound) {
    return [self applicationUnavailable];
  }
  return [self failed:error];
}

@end

@implementation FBAXHitTestOutcome

- (instancetype)initWithStatus:(FBAXHitTestStatus)status
                       element:(nullable id)element
       owningProcessIdentifier:(pid_t)pid
                 failureReason:(nullable NSString *)failureReason
{
  self = [super init];
  if (!self) {
    return nil;
  }
  _status = status;
  _element = element;
  _owningProcessIdentifier = pid;
  _failureReason = [failureReason copy];
  return self;
}

+ (instancetype)hit:(id)element owningProcessIdentifier:(pid_t)pid
{
  return [[self alloc] initWithStatus:FBAXHitTestStatusHit
                              element:element
              owningProcessIdentifier:pid
                        failureReason:nil];
}

+ (instancetype)empty
{
  return [[self alloc] initWithStatus:FBAXHitTestStatusEmpty
                              element:nil
              owningProcessIdentifier:0
                        failureReason:nil];
}

+ (instancetype)applicationUnavailable
{
  return [[self alloc] initWithStatus:FBAXHitTestStatusApplicationUnavailable
                              element:nil
              owningProcessIdentifier:0
                        failureReason:nil];
}

+ (instancetype)failed:(NSString *)failureReason
{
  return [[self alloc] initWithStatus:FBAXHitTestStatusFailed
                              element:nil
              owningProcessIdentifier:0
                        failureReason:failureReason];
}

+ (nullable instancetype)outcomeForHitTestError:(int32_t)axError hasElement:(BOOL)hasElement
{
  if (axError == FBAXErrorServerNotFound) {
    // Nothing answered the hit-test at all. Reporting that as an empty result would tell the caller the
    // app is on screen with nothing under the point, which is the opposite of what happened.
    return [self applicationUnavailable];
  }
  if (axError == FBAXErrorIPCTimeout) {
    // The application is there and did not answer in time. Empty would tell a caller the point is blank,
    // which is what it looks like after a tap that is still being processed — so this stays a failure the
    // caller can retry, and is not tagged unavailable, because the application has not gone away.
    return [self failed:@"the application did not answer the hit-test in time"];
  }
  if (axError != FBAXErrorSuccess || !hasElement) {
    // No element at the point is a valid empty result, not a failure: a caller doing a streaming
    // hit-test (e.g. after a tap) must be able to tell "empty space" apart from "the reader broke".
    return [self empty];
  }
  return nil;
}

@end

@implementation FBAXFrontmostOutcome

- (instancetype)initWithStatus:(FBAXFrontmostStatus)status
             processIdentifier:(pid_t)pid
                 failureReason:(nullable NSString *)failureReason
{
  self = [super init];
  if (!self) {
    return nil;
  }
  _status = status;
  _processIdentifier = pid;
  _failureReason = [failureReason copy];
  return self;
}

+ (instancetype)resolved:(pid_t)pid
{
  return [[self alloc] initWithStatus:FBAXFrontmostStatusResolved processIdentifier:pid failureReason:nil];
}

+ (instancetype)unresolved:(NSString *)failureReason
{
  return [[self alloc] initWithStatus:FBAXFrontmostStatusUnresolved
                    processIdentifier:0
                        failureReason:failureReason];
}

@end

#pragma mark - Bound signatures

// Contract and rationale are on the declaration in AccessibilityRuntime.h.
NSString *FBAXTypesOnly(const char *encoding)
{
  NSMutableString *types = [NSMutableString string];
  NSInteger depth = 0;
  for (const char *character = encoding; *character; character++) {
    switch (*character) {
      case '{':
      case '(':
      case '[':
        depth++;
        break;
      case '}':
      case ')':
      case ']':
        depth--;
        break;
      default:
        break;
    }
    if (depth == 0 && *character >= '0' && *character <= '9') {
      continue;
    }
    [types appendFormat:@"%c", *character];
  }
  return types;
}

NSString *_Nullable FBAXSignatureMismatch(const char *className,
                                          const char *selectorName,
                                          BOOL isClassMethod,
                                          const char *expected)
{
  NSString *name = [NSString stringWithFormat:@"%c[%s %s]", isClassMethod ? '+' : '-', className, selectorName];
  Class cls = objc_lookUpClass(className);
  if (!cls) {
    return [NSString stringWithFormat:@"%@ cannot be checked: %s is not in the runtime", name, className];
  }
  SEL selector = sel_registerName(selectorName);
  Method method = isClassMethod ? class_getClassMethod(cls, selector) : class_getInstanceMethod(cls, selector);
  if (!method) {
    return [NSString stringWithFormat:@"%@ is not in the runtime", name];
  }
  const char *encoding = method_getTypeEncoding(method);
  if (!encoding) {
    return [NSString stringWithFormat:@"%@ has no type encoding", name];
  }
  NSString *actual = FBAXTypesOnly(encoding);
  NSString *assumed = FBAXTypesOnly(expected);
  if ([actual isEqualToString:assumed]) {
    return nil;
  }
  return [NSString stringWithFormat:@"%@ is %@ but %@ was assumed", name, actual, assumed];
}

// Every private selector this file reaches through a declaration or an `objc_msgSend` cast, with the
// signature that declaration or cast assumes.
//
// The encodings were taken from `method_getTypeEncoding` on the runtime the reader is written against, so
// this table is the assumption made explicit and checkable rather than left implicit in the casts. The
// KVC-driven setters are here too: KVC ends up calling them, so their shape matters as much as the ones
// messaged directly.
typedef struct {
  const char *className;
  const char *selectorName;
  BOOL isClassMethod;
  const char *expected;
} FBAXBoundSelector;

static const FBAXBoundSelector kFBAXBoundSelectors[] = {
  // XCTAutomationSupport
  {"XCTAccessibilityFramework", "initForRemoteAccess", NO, "@@:"},
  {"XCTAccessibilityFramework", "attributesForElement:attributes:error:", NO, "@@:@@^@"},
  {"XCAccessibilityElement", "elementWithProcessIdentifier:", YES, "@@:i"},
  {"XCAccessibilityElement", "elementWithAXUIElement:", YES, "@@:^{__AXUIElement=}"},
  {"XCAccessibilityElement", "AXUIElement", NO, "^{__AXUIElement=}@:"},
  // AccessibilityPlatformTranslation
  {"AXPTranslator", "sharediOSInstance", YES, "@@:"},
  {"AXPTranslator", "frontmostApplicationWithDisplayId:bridgeDelegateToken:", NO, "@@:I@"},
  {"AXPTranslator", "processTranslatorRequest:", NO, "@@:@"},
  {"AXPTranslationObject", "pid", NO, "i@:"},
  // RunningBoardServices
  {"RBSProcessPredicate", "predicateMatchingLaunchServicesProcesses", YES, "@@:"},
  {"RBSProcessState", "statesForPredicate:withDescriptor:error:", YES, "@@:@@o^@"},
  {"RBSProcessState", "endowmentNamespaces", NO, "@@:"},
  {"RBSProcessState", "process", NO, "@@:"},
  {"RBSProcessStateDescriptor", "descriptor", YES, "@@:"},
  {"RBSProcessStateDescriptor", "setValues:", NO, "v@:Q"},
  {"RBSProcessStateDescriptor", "setEndowmentNamespaces:", NO, "v@:@"},
  {"RBSProcessHandle", "pid", NO, "i@:"},
};

NSArray<NSString *> *FBAXSignatureWarnings(void)
{
  // Opened here rather than relied on being open, so the sweep sees every bound selector however it was
  // reached. dlopen on an already-open image is a refcount bump.
  dlopen(FBAXPathAXRuntime, RTLD_NOW);
  dlopen(FBAXPathXCTAutomationSupport, RTLD_NOW);
  dlopen(FBAXPathAXPTranslation, RTLD_NOW);
  dlopen(FBAXPathRunningBoardServices, RTLD_NOW);

  NSMutableArray<NSString *> *warnings = [NSMutableArray array];
  for (size_t index = 0; index < sizeof(kFBAXBoundSelectors) / sizeof(*kFBAXBoundSelectors); index++) {
    const FBAXBoundSelector bound = kFBAXBoundSelectors[index];
    NSString *mismatch = FBAXSignatureMismatch(bound.className, bound.selectorName, bound.isClassMethod, bound.expected);
    if (mismatch) {
      [warnings addObject:mismatch];
    }
  }
  return warnings;
}

// Composes a setup failure with whatever else about the runtime does not match, so a bind that fails on a
// missing class says alongside it what other shapes moved. Swept here and nowhere else: a signature that
// moved is the likeliest reason a class or selector went missing beside it, and a process that bound
// cleanly has nothing to report.
static NSString *FBAXSetupFailure(NSString *reason)
{
  NSArray<NSString *> *warnings = FBAXSignatureWarnings();
  if (warnings.count == 0) {
    return reason;
  }
  return [NSString stringWithFormat:@"%@ (also: %@)", reason, [warnings componentsJoinedByString:@"; "]];
}

#pragma mark - The AXRuntime C entry points

// The three AXRuntime entry points, resolved once, with the ownership each one transfers restated where
// the table is declared. `AXRuntimePrivate.h` carries the full contract; this is the reminder at the only
// place a raw AXUIElementRef is ever held.
typedef struct {
  void *(*createSystemWide)(void);                                            // returns +1
  int32_t (*copyElementAtPosition)(void *app, float x, float y, void **out);  // out-parameter is +1
  int32_t (*getPid)(void *element, pid_t *pid);                               // borrows
} FBAXRuntimeFunctions;

#pragma mark - Owned AXUIElement references

// The one owner of a raw AXUIElementRef in the product.
//
// The AX runtime's C entry points transfer +1 references that have to be released exactly once on every
// path out of the function that took them. In a method with eight early returns that is a rule no reader
// can check by looking, and the failure modes are a leak or a use-after-free. Wrapping the reference at
// the moment it is acquired makes the release ARC's job, so it happens on every path — including paths
// added later by someone who never read this comment.
@interface FBAXElementRef : NSObject

/** Takes ownership of an already-retained (+1) reference — what the AX runtime's Create and Copy give. */
- (instancetype)initWithOwnedElement:(void *)element NS_DESIGNATED_INITIALIZER;

/**
 * Takes a reference of its own on a borrowed one.
 *
 * `-[XCAccessibilityElement AXUIElement]` returns a reference it continues to own, so it dies with the
 * element that vended it. Retaining is what let the seed of a hit-test outlive that element — reading it
 * without doing so is the SIGSEGV this whole layer exists to prevent.
 */
+ (instancetype)retainingBorrowedElement:(void *)element;

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, readonly) void *element;

@end

@implementation FBAXElementRef

- (instancetype)initWithOwnedElement:(void *)element
{
  NSParameterAssert(element);
  self = [super init];
  if (!self) {
    return nil;
  }
  _element = element;
  return self;
}

+ (instancetype)retainingBorrowedElement:(void *)element
{
  return [[self alloc] initWithOwnedElement:(void *)CFRetain(element)];
}

- (void)dealloc
{
  CFRelease(_element);
}

@end

#pragma mark - The in-guest window-server bridge delegate

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
    dlopen(FBAXPathAXPTranslation, RTLD_NOW);
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

// Runs `block` somewhere other than the main queue and waits for it to finish.
//
// AXPTranslator lazily enables its bridge runtime on first use, and that path asserts it is *not* running
// on the main queue (`-[AXPTranslator_iOS _enableAccessibilityBridgeRuntime]` calls
// `dispatch_assert_queue_not`). The in-guest self-service delegate re-enters the translator on whichever
// thread called in, so driving it from the reader's main thread trips the assert and traps the process.
//
// Blocking the caller is deliberate: the reader handles one request at a time, so the main thread has
// nothing else to do while the translator answers.
static void FBAXBridgeRunOffMainQueue(dispatch_block_t block)
{
  if (!NSThread.isMainThread) {
    block();
    return;
  }
  dispatch_semaphore_t completed = dispatch_semaphore_create(0);
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    block();
    dispatch_semaphore_signal(completed);
  });
  dispatch_semaphore_wait(completed, DISPATCH_TIME_FOREVER);
}

// The window-server frontmost query itself, which must already be off the main queue — see
// `FBAXBridgeRunOffMainQueue`. Asks the wired iOS translator for `frontmostApplicationWithDisplayId:0`
// and reads the owning pid of the returned application object.
static FBAXFrontmostOutcome *FBAXBridgeWindowServerFrontmostOffMain(void)
{
  NSString *setupError = nil;
  id translator = FBAXBridgeWindowServerTranslator(&setupError);
  if (!translator) {
    return [FBAXFrontmostOutcome unresolved:setupError ?: @"AXPTranslator unavailable"];
  }
  SEL frontmostSelector = NSSelectorFromString(@"frontmostApplicationWithDisplayId:bridgeDelegateToken:");
  if (![translator respondsToSelector:frontmostSelector]) {
    return [FBAXFrontmostOutcome unresolved:@"AXPTranslator does not respond to frontmostApplicationWithDisplayId:"];
  }
  SEL pidSelector = NSSelectorFromString(@"pid");
  id application = ((id (*)(id, SEL, unsigned int, id)) objc_msgSend)(translator, frontmostSelector, 0, @"axbridge");
  if (!application || ![application respondsToSelector:pidSelector]) {
    return [FBAXFrontmostOutcome unresolved:@"window-server frontmost returned no application object"];
  }
  pid_t pid = ((int (*)(id, SEL)) objc_msgSend)(application, pidSelector);
  if (pid <= 0) {
    return [FBAXFrontmostOutcome unresolved:[NSString stringWithFormat:@"window-server frontmost returned no pid (%d)", pid]];
  }
  return [FBAXFrontmostOutcome resolved:pid];
}

// The endowment namespace RunningBoard grants a process whose scene is on-screen. The foreground app is
// the launch-services process that holds it.
static NSString *const kFrontboardVisibilityEndowment = @"com.apple.frontboard.visibility";

#pragma mark - The live runtime

@implementation FBAXLiveRuntime
{
  XCTAccessibilityFramework *_framework;
  Class _elementClass;
  FBAXRuntimeFunctions _functions;
}

- (nullable instancetype)initWithError:(NSString *_Nullable *_Nullable)error
{
  self = [super init];
  if (!self) {
    return nil;
  }

  // Only the two this bind needs. The frontmost resolvers open the other two at their own call sites, so
  // neither depends on this one having run.
  dlopen(FBAXPathAXRuntime, RTLD_NOW);
  dlopen(FBAXPathXCTAutomationSupport, RTLD_NOW);

  Class frameworkClass = objc_lookUpClass("XCTAccessibilityFramework");
  if (!frameworkClass) {
    if (error) {
      *error = FBAXSetupFailure(@"XCTAccessibilityFramework unavailable — is XCTAutomationSupport loaded?");
    }
    return nil;
  }
  _framework = [(XCTAccessibilityFramework *)[frameworkClass alloc] initForRemoteAccess];
  if (!_framework) {
    if (error) {
      *error = FBAXSetupFailure(@"initForRemoteAccess returned nil");
    }
    return nil;
  }

  _elementClass = objc_lookUpClass("XCAccessibilityElement");
  if (!_elementClass) {
    if (error) {
      *error = FBAXSetupFailure(@"XCAccessibilityElement unavailable");
    }
    return nil;
  }

  // Resolved here rather than per request, so a runtime missing an entry point is a setup failure naming
  // it rather than a request that gets partway and cannot finish.
  _functions.createSystemWide = dlsym(RTLD_DEFAULT, "AXUIElementCreateSystemWide");
  _functions.copyElementAtPosition = dlsym(RTLD_DEFAULT, "AXUIElementCopyElementAtPosition");
  _functions.getPid = dlsym(RTLD_DEFAULT, "AXUIElementGetPid");
  if (!_functions.createSystemWide || !_functions.copyElementAtPosition || !_functions.getPid) {
    if (error) {
      *error = @"AXUIElementCreateSystemWide/CopyElementAtPosition/GetPid unavailable";
    }
    return nil;
  }

  return self;
}

#pragma mark FBAXRuntime

- (nullable id)applicationElementForProcessIdentifier:(pid_t)pid
{
  return [(id)_elementClass elementWithProcessIdentifier:pid];
}

- (FBAXReadOutcome *)readAttributes:(NSArray<NSString *> *)attributes ofElement:(id)element
{
  NSError *error = nil;
  NSDictionary<NSString *, id> *read = [_framework attributesForElement:element
                                                             attributes:attributes
                                                                  error:&error];
  if (![read isKindOfClass:NSDictionary.class]) {
    return [FBAXReadOutcome failureForAttributeError:error];
  }
  return [FBAXReadOutcome read:read];
}

// Every raw AXUIElementRef in the product is acquired inside this method and owned by an `FBAXElementRef`
// from the moment it is, and the hit is handed back already wrapped as an opaque element handle — so
// nothing outside can outlive or over-release either, and nothing inside has to remember to.
- (FBAXHitTestOutcome *)hitTestAtPoint:(CGPoint)point processIdentifier:(pid_t)pid
{
  // Both references below are declared NS_VALID_UNTIL_END_OF_SCOPE. `-element` hands out a non-object
  // pointer, so ARC cannot see that the C call using it depends on the wrapper still being alive, and
  // would otherwise be free to release the wrapper — and with it the reference — before the call returns.
  //
  // Resolve the seed: a specific app element for an explicit pid, otherwise the system-wide element.
  // Owned either way, so it outlives whatever vended it and both branches are released alike.
  NS_VALID_UNTIL_END_OF_SCOPE FBAXElementRef *seed = nil;
  if (pid > 0) {
    XCAccessibilityElement *root = [(id)_elementClass elementWithProcessIdentifier:pid];
    if (!root) {
      return [FBAXHitTestOutcome failed:[NSString stringWithFormat:@"no application element for pid %d", pid]];
    }
    void *applicationElement = [root AXUIElement];
    if (!applicationElement) {
      return [FBAXHitTestOutcome failed:[NSString stringWithFormat:@"no AXUIElement for pid %d", pid]];
    }
    seed = [FBAXElementRef retainingBorrowedElement:applicationElement];
  } else {
    void *systemWide = _functions.createSystemWide();
    if (!systemWide) {
      return [FBAXHitTestOutcome failed:@"AXUIElementCreateSystemWide returned NULL"];
    }
    seed = [[FBAXElementRef alloc] initWithOwnedElement:systemWide];
  }

  void *copied = NULL;
  int32_t axError = _functions.copyElementAtPosition(seed.element, (float)point.x, (float)point.y, &copied);
  // Wrapped before anything else can fail. The copy is +1 whenever it produced one, so from here every
  // exit releases it without having to say so — including the error paths, where the runtime is not
  // supposed to have produced an element at all but nothing stops it.
  NS_VALID_UNTIL_END_OF_SCOPE FBAXElementRef *hit =
  copied ? [[FBAXElementRef alloc] initWithOwnedElement:copied] : nil;

  FBAXHitTestOutcome *unresolved = [FBAXHitTestOutcome outcomeForHitTestError:axError hasElement:hit != nil];
  if (unresolved) {
    return unresolved;
  }

  // The host tags the hit element with its owning process, so an unattributable hit is not a result. A
  // seeded hit-test already knows the pid and falls back to it; a system-wide one has no other source.
  pid_t owningPid = 0;
  int32_t pidError = _functions.getPid(hit.element, &owningPid);
  if (pidError != FBAXErrorSuccess || owningPid <= 0) {
    if (pid <= 0) {
      return [FBAXHitTestOutcome failed:[NSString stringWithFormat:@"could not resolve the owning pid of the hit element (%d)", pidError]];
    }
    owningPid = pid;
  }

  // `elementWithAXUIElement:` takes a reference of its own, so the wrapper's goes when it leaves scope.
  XCAccessibilityElement *hitElement = [(id)_elementClass elementWithAXUIElement:hit.element];
  if (!hitElement) {
    return [FBAXHitTestOutcome failed:@"failed to read the hit element"];
  }
  return [FBAXHitTestOutcome hit:hitElement owningProcessIdentifier:owningPid];
}

// The authoritative frontmost the host obtains through AXPTranslator, obtained here with no host
// round-trip.
- (FBAXFrontmostOutcome *)windowServerFrontmost
{
  __block FBAXFrontmostOutcome *outcome = nil;
  FBAXBridgeRunOffMainQueue(^{
    outcome = FBAXBridgeWindowServerFrontmostOffMain();
  });
  return outcome ?: [FBAXFrontmostOutcome unresolved:@"window-server frontmost resolution failed"];
}

// Enumerates every launch-services process and returns the one endowed with on-screen visibility
// (`com.apple.frontboard.visibility`). This reads the window server's own notion of foreground — the same
// pid the window-server method resolves — from the process-lifecycle daemon rather than the accessibility
// stack, so it needs neither a screen anchor nor the AX server.
//
// Enumerating other processes' state requires the `com.apple.runningboard.process-state` entitlement;
// without it runningboardd rejects the query with "Client not entitled". The RBS classes are resolved by
// name (they are not declared to this translation unit) and messaged defensively.
- (FBAXFrontmostOutcome *)runningBoardFrontmost
{
  dlopen(FBAXPathRunningBoardServices, RTLD_NOW);
  Class predicateClass = objc_lookUpClass("RBSProcessPredicate");
  Class stateClass = objc_lookUpClass("RBSProcessState");
  Class descriptorClass = objc_lookUpClass("RBSProcessStateDescriptor");
  SEL statesSelector = NSSelectorFromString(@"statesForPredicate:withDescriptor:error:");
  if (!predicateClass || !stateClass || ![stateClass respondsToSelector:statesSelector]) {
    return [FBAXFrontmostOutcome unresolved:@"RunningBoardServices unavailable — is RunningBoardServices loaded?"];
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
    return [FBAXFrontmostOutcome unresolved:
            [NSString stringWithFormat:@"RunningBoard process-state query failed: %@", error ?: @"(no states returned)"]];
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
      return [FBAXFrontmostOutcome resolved:pid];
    }
  }

  return [FBAXFrontmostOutcome unresolved:@"no launch-services process holds the on-screen visibility endowment"];
}

@end
