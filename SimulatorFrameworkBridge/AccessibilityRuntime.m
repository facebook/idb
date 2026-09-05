/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "AccessibilityRuntime.h"

#import <dlfcn.h>
#import <objc/runtime.h>

#import "AXPAttributes.h"
#import "AXPTranslationPrivate.h"
#import "AXRuntimePrivate.h"
#import "AccessibilityUtilitiesPrivate.h"
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

+ (instancetype)applicationNotResponding
{
  return [[self alloc] initWithStatus:FBAXReadStatusApplicationNotResponding attributes:nil error:nil];
}

+ (instancetype)failed:(nullable NSError *)error
{
  return [[self alloc] initWithStatus:FBAXReadStatusFailed attributes:nil error:error];
}

+ (instancetype)failureForAttributeError:(nullable NSError *)error
{
  NSNumber *code = error.userInfo[FBAXAccessibilityErrorKey];
  if (![code isKindOfClass:NSNumber.class]) {
    return [self failed:error];
  }
  switch (code.intValue) {
    case FBAXErrorServerNotFound:
      return [self applicationUnavailable];
    case FBAXErrorIPCTimeout:
      return [self applicationNotResponding];
    default:
      return [self failed:error];
  }
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

+ (instancetype)applicationNotResponding
{
  return [[self alloc] initWithStatus:FBAXHitTestStatusApplicationNotResponding
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
    return [self applicationUnavailable];
  }
  if (axError == FBAXErrorIPCTimeout) {
    return [self applicationNotResponding];
  }
  if (axError != FBAXErrorSuccess || !hasElement) {
    return [self empty];
  }
  return nil;
}

@end

@implementation FBAXWriteOutcome

- (instancetype)initWithStatus:(FBAXWriteStatus)status failureReason:(nullable NSString *)failureReason
{
  self = [super init];
  if (!self) {
    return nil;
  }
  _status = status;
  _failureReason = [failureReason copy];
  return self;
}

+ (instancetype)written
{
  return [[self alloc] initWithStatus:FBAXWriteStatusWritten failureReason:nil];
}

+ (instancetype)empty
{
  return [[self alloc] initWithStatus:FBAXWriteStatusEmpty failureReason:nil];
}

+ (instancetype)assertionFailed:(NSString *)failureReason
{
  return [[self alloc] initWithStatus:FBAXWriteStatusAssertionFailed failureReason:failureReason];
}

+ (instancetype)applicationUnavailable
{
  return [[self alloc] initWithStatus:FBAXWriteStatusApplicationUnavailable failureReason:nil];
}

+ (instancetype)applicationNotResponding
{
  return [[self alloc] initWithStatus:FBAXWriteStatusApplicationNotResponding failureReason:nil];
}

+ (instancetype)failed:(NSString *)failureReason
{
  return [[self alloc] initWithStatus:FBAXWriteStatusFailed failureReason:failureReason];
}

+ (instancetype)outcomeForWriteError:(int32_t)axError
{
  if (axError == FBAXErrorSuccess) {
    return [self written];
  }
  if (axError == FBAXErrorServerNotFound) {
    return [self applicationUnavailable];
  }
  if (axError == FBAXErrorIPCTimeout) {
    return [self applicationNotResponding];
  }
  return [self failed:[NSString stringWithFormat:@"the accessibility runtime rejected the write (%d)", axError]];
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

+ (instancetype)applicationUnavailable:(NSString *)failureReason
{
  return [[self alloc] initWithStatus:FBAXFrontmostStatusApplicationUnavailable
                    processIdentifier:0
                        failureReason:failureReason];
}

+ (instancetype)applicationNotResponding:(NSString *)failureReason
{
  return [[self alloc] initWithStatus:FBAXFrontmostStatusApplicationNotResponding
                    processIdentifier:0
                        failureReason:failureReason];
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

// Every private selector this file sends, with the encoding `method_getTypeEncoding` reports for it on a
// real runtime (taken from the runtime, never hand-written).
//
// `-[AXPTranslator setSupportsDelegateTokens:]` is absent on purpose: its `BOOL` encodes as `B` on
// arm64 and `c` on x86_64, so there is no one encoding to compare against.
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
  // AccessibilityUtilities. `setAutomationEnabled:` takes BOOL, whose encoding differs by architecture.
  {"AXSettings", "sharedInstance", YES, "@@:"},
  // AccessibilityPlatformTranslation
  {"AXPTranslator", "sharediOSInstance", YES, "@@:"},
  {"AXPTranslator", "frontmostApplicationWithDisplayId:bridgeDelegateToken:", NO, "@@:I@"},
  {"AXPTranslator", "processTranslatorRequest:", NO, "@@:@"},
  {"AXPTranslator", "setBridgeTokenDelegate:", NO, "v@:@"},
  // Declared by the concrete iOS subclass `sharediOSInstance` vends, not by `AXPTranslator` itself.
  {"AXPTranslator_iOS", "translationObjectFromPlatformElement:", NO, "@@:^{__AXUIElement=}"},
  {"AXPTranslationObject", "pid", NO, "i@:"},
  {"AXPTranslatorRequest", "requestWithTranslation:", YES, "@@:@"},
  {"AXPTranslatorRequest", "setRequestType:", NO, "v@:Q"},
  {"AXPTranslatorRequest", "setAttributeType:", NO, "v@:Q"},
  {"AXPTranslatorRequest", "setParameters:", NO, "v@:@"},
  {"AXPTranslatorResponse", "resultData", NO, "@@:"},
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
  dlopen(FBAXPathAccessibilityUtilities, RTLD_NOW);
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

// Appends the signature sweep to a bind failure, so the message also names what else about the runtime
// moved. Swept only here: a process that bound cleanly has nothing to report.
static NSString *FBAXSetupFailure(NSString *reason)
{
  NSArray<NSString *> *warnings = FBAXSignatureWarnings();
  if (warnings.count == 0) {
    return reason;
  }
  return [NSString stringWithFormat:@"%@ (also: %@)", reason, [warnings componentsJoinedByString:@"; "]];
}

#pragma mark - The AXRuntime C entry points

// The AXRuntime entry points, resolved once, with the ownership each one transfers restated where the
// table is declared. `AXRuntimePrivate.h` carries the full contract; this is the reminder at the only
// place a raw AXUIElementRef is ever held.
typedef struct {
  void *(*createSystemWide)(void);                                            // returns +1
  int32_t (*copyElementAtPosition)(void *app, float x, float y, void **out);  // out-parameter is +1
  int32_t (*getPid)(void *element, pid_t *pid);                               // borrows
  int32_t (*performAction)(void *element, uint32_t action);                   // borrows
  int32_t (*setAttributeValue)(void *element, uint32_t attribute, const void *value);  // borrows both
  // Device-wide accessibility automation mode. Optional: a runtime without it is not a setup failure,
  // because every read this bundle performs works either way — the flag changes how much structure the
  // target exposes, not whether it answers.
  bool (*automationEnabled)(void);
  // The single-fetch read's entry points. Optional as a group, for the same reason the snapshot selector
  // is resolved lazily: a runtime without them loses that one path and keeps every other.
  FBAXValueGetTypeFn valueGetType;                                  // borrows
  FBAXValueGetValueFn valueGetValue;                                // borrows
  FBAXDefaultSnapshotParametersFn defaultSnapshotParameters;
  FBAXAttributeNumbersForNamesFn attributeNumbersForNames;
  // Proves a snapshot element is an AXUIElementRef before it reaches the C entry points, which do not
  // check. Optional: without it boundary continuation stays off.
  CFTypeID (*elementTypeID)(void);
} FBAXRuntimeFunctions;

// The one place an `FBAXAction` becomes the number the C ABI takes. `-Wswitch-default` forces the
// `default`, which costs the exhaustiveness warning, so an action added without a mapping is caught here
// at run time: answer NO rather than send a number — the C ABI treats zero as a real action, not "none".
static BOOL FBAXActionIdentifierForAction(FBAXAction action, uint32_t *identifier)
{
  switch (action) {
    case FBAXActionPress:
      *identifier = FBAXActionIdentifierPress;
      return YES;
    case FBAXActionScrollUp:
      *identifier = FBAXActionIdentifierScrollUpByPage;
      return YES;
    case FBAXActionScrollDown:
      *identifier = FBAXActionIdentifierScrollDownByPage;
      return YES;
    case FBAXActionScrollLeft:
      *identifier = FBAXActionIdentifierScrollLeftByPage;
      return YES;
    case FBAXActionScrollRight:
      *identifier = FBAXActionIdentifierScrollRightByPage;
      return YES;
    case FBAXActionScrollToVisible:
      *identifier = FBAXActionIdentifierScrollToVisible;
      return YES;
    default:
      return NO;
  }
}

#pragma mark - Owned AXUIElement references

// The one owner of a raw AXUIElementRef in the product. Wrapping a +1 reference at acquisition makes the
// release ARC's job, so it happens exactly once on every early-return path.
@interface FBAXElementRef : NSObject

/** Takes ownership of an already-retained (+1) reference — what the AX runtime's Create and Copy give. */
- (instancetype)initWithOwnedElement:(void *)element NS_DESIGNATED_INITIALIZER;

/**
 * Takes a reference of its own on a borrowed one. `-[XCAccessibilityElement AXUIElement]` returns a
 * reference that dies with the element that vended it; retaining lets a hit-test seed outlive it.
 */
+ (instancetype)retainingBorrowedElement:(void *)element;

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

/**
 * Runs `body` with the raw reference, keeping the wrapper alive for the whole call. A `void *` is
 * invisible to ARC, which could otherwise release the wrapper mid-call. `NS_NOESCAPE`: the reference is
 * guaranteed only for the call.
 */
- (int32_t)axErrorFromElement:(NS_NOESCAPE int32_t (^)(void *element))body;

/** As above, for the one caller that wants an object back rather than an AX error code. */
- (nullable id)objectFromElement:(NS_NOESCAPE id _Nullable (^)(void *element))body;

@end

@implementation FBAXElementRef
{
  void *_element;
}

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

- (int32_t)axErrorFromElement:(NS_NOESCAPE int32_t (^)(void *element))body
{
  // The local is what keeps the wrapper alive across the call: reading the ivar through a reference ARC
  // can see, rather than handing the pointer to someone it cannot.
  NS_VALID_UNTIL_END_OF_SCOPE FBAXElementRef *alive = self;
  return body(alive->_element);
}

- (nullable id)objectFromElement:(NS_NOESCAPE id _Nullable (^)(void *element))body
{
  NS_VALID_UNTIL_END_OF_SCOPE FBAXElementRef *alive = self;
  return body(alive->_element);
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

@interface FBAXWindowServerDelegate : NSObject <AXPTranslationTokenDelegateHelper>
@property (nonatomic, weak) AXPTranslator *translator;
@end
@implementation FBAXWindowServerDelegate
- (nullable AXPTranslationBridgeCallback)selfServiceCallback
{
  // Captured strongly by the block: the property is weak so the translator can go, but a callback the
  // translator is in the middle of calling must not have it vanish underneath.
  AXPTranslator *translator = self.translator;
  return ^id _Nullable (id request) {
    if (gAXPSelfServiceDepth > 500) {
      return nil;
    }
    gAXPSelfServiceDepth++;
    id result = nil;
    // Declaring the selector says what its signature is if the runtime has it, not that the runtime has
    // it — so the guard stays.
    if ([translator respondsToSelector:@selector(processTranslatorRequest:)]) {
      @try {
        result = [translator processTranslatorRequest:request];
      } @catch (NSException *exception) {
        result = nil;
      }
    }
    gAXPSelfServiceDepth--;
    return result;
  };
}

- (nullable AXPTranslationBridgeCallback)accessibilityTranslationDelegateBridgeCallbackWithToken:(NSString *)token { return [self selfServiceCallback]; }

- (nullable AXPTranslationBridgeCallback)accessibilityTranslationDelegateBridgeCallback { return [self selfServiceCallback]; }

- (CGRect)accessibilityTranslationConvertPlatformFrameToSystem:(CGRect)rect withToken:(NSString *)token { return rect; }

- (CGRect)accessibilityTranslationConvertPlatformFrameToSystem:(CGRect)rect { return rect; }

- (nullable id)accessibilityTranslationRootParentWithToken:(NSString *)token { return nil; }

- (nullable id)accessibilityTranslationRootParent { return nil; }

@end

// The AXPTranslator (iOS instance) wired for in-guest window-server frontmost, set up once and reused
// (installing the self-service delegate is the one-time cost). The delegate is retained here so it
// outlives the translator's weak/assign reference. Returns nil (with `*error` set) if AXPTranslator is
// unavailable.
static AXPTranslator *_Nullable FBAXBridgeWindowServerTranslator(NSString *_Nullable *_Nullable error)
{
  static AXPTranslator *translator;
  static FBAXWindowServerDelegate *delegate;
  static NSString *cachedError;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    dlopen(FBAXPathAXPTranslation, RTLD_NOW);
    // The class is still looked up by name — nothing in AXPTranslationPrivate.h is linked against, so
    // naming `AXPTranslator` as a receiver directly would be an undefined symbol. The `Class<...>` cast is
    // what lets the compiler check the class-method send against that class's own declaration.
    Class<AXPTranslatorClass> translatorClass = (Class<AXPTranslatorClass>)objc_lookUpClass("AXPTranslator");
    if (!translatorClass || ![translatorClass respondsToSelector:@selector(sharediOSInstance)]) {
      cachedError = @"AXPTranslator unavailable — is AccessibilityPlatformTranslation loaded?";
      return;
    }
    AXPTranslator *instance = [translatorClass sharediOSInstance];
    if (!instance) {
      cachedError = @"AXPTranslator sharediOSInstance was nil";
      return;
    }
    FBAXWindowServerDelegate *serviceDelegate = [FBAXWindowServerDelegate new];
    serviceDelegate.translator = instance;
    // Still guarded: a runtime without these setters raises rather than returning, and the reader would
    // rather report that than trap.
    @try {
      instance.bridgeTokenDelegate = serviceDelegate;
      instance.supportsDelegateTokens = YES;
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
  AXPTranslator *translator = FBAXBridgeWindowServerTranslator(&setupError);
  if (!translator) {
    return [FBAXFrontmostOutcome unresolved:setupError ?: @"AXPTranslator unavailable"];
  }
  if (![translator respondsToSelector:@selector(frontmostApplicationWithDisplayId:bridgeDelegateToken:)]) {
    return [FBAXFrontmostOutcome unresolved:@"AXPTranslator does not respond to frontmostApplicationWithDisplayId:"];
  }
  AXPTranslationObject *application = [translator frontmostApplicationWithDisplayId:0 bridgeDelegateToken:@"axbridge"];
  if (!application || ![application respondsToSelector:@selector(pid)]) {
    return [FBAXFrontmostOutcome unresolved:@"window-server frontmost returned no application object"];
  }
  pid_t pid = application.pid;
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
  Class<XCAccessibilityElementClass> _elementClass;
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

  _elementClass = (Class<XCAccessibilityElementClass>)objc_lookUpClass("XCAccessibilityElement");
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
  _functions.performAction = dlsym(RTLD_DEFAULT, "AXUIElementPerformAction");
  _functions.setAttributeValue = dlsym(RTLD_DEFAULT, "AXUIElementSetAttributeValue");
  // Not part of the null check below: this one is optional, so a runtime without it degrades to
  // "cannot say" rather than failing a bind that every read would otherwise have survived.
  _functions.automationEnabled = dlsym(RTLD_DEFAULT, "_AXSAutomationEnabled");
  // Optional for the same reason, and checked where the single-fetch read uses them.
  _functions.valueGetType = dlsym(RTLD_DEFAULT, "AXValueGetType");
  _functions.valueGetValue = dlsym(RTLD_DEFAULT, "AXValueGetValue");
  _functions.defaultSnapshotParameters = dlsym(RTLD_DEFAULT, "XCTDefaultSnapshotParameters");
  _functions.attributeNumbersForNames = dlsym(RTLD_DEFAULT, "XCAXAccessibilityAttributesForStringAttributes");
  _functions.elementTypeID = dlsym(RTLD_DEFAULT, "AXUIElementGetTypeID");
  if (!_functions.createSystemWide || !_functions.copyElementAtPosition || !_functions.getPid
      || !_functions.performAction || !_functions.setAttributeValue) {
    if (error) {
      *error = @"AXUIElementCreateSystemWide/CopyElementAtPosition/GetPid/PerformAction/SetAttributeValue unavailable";
    }
    return nil;
  }

  return self;
}

#pragma mark Automation mode

- (BOOL)automationModeEnabled
{
  if (!_functions.automationEnabled) {
    return NO;
  }
  return _functions.automationEnabled();
}

- (BOOL)setAutomationModeEnabled:(BOOL)enabled
{
  dlopen(FBAXPathAccessibilityUtilities, RTLD_NOW);
  Class<AXSettingsClass> settingsClass = (Class<AXSettingsClass>)objc_lookUpClass("AXSettings");
  if (!settingsClass || ![settingsClass respondsToSelector:@selector(sharedInstance)]) {
    return [self automationModeEnabled];
  }
  AXSettings *settings = [settingsClass sharedInstance];
  if (!settings || ![settings respondsToSelector:@selector(setAutomationEnabled:)]) {
    return [self automationModeEnabled];
  }
  [settings setAutomationEnabled:enabled];

  // Read back rather than reporting the write. A preference write can fail silently — the sandbox
  // refuses it outright on a real device — and the target consults the preference per read, so what
  // matters to a caller is what the device now says, not that we asked.
  return [self automationModeEnabled];
}

#pragma mark Element references

// A retained reference on the AXUIElementRef behind a handle, for the duration of a call that needs the
// raw pointer (see `+retainingBorrowedElement:`).
- (nullable FBAXElementRef *)referenceForElement:(id)element
{
  // Handles are opaque above the seam, so a non-handle is a named failure rather than an unrecognised selector.
  if (![element respondsToSelector:@selector(AXUIElement)]) {
    return nil;
  }
  void *raw = [(XCAccessibilityElement *)element AXUIElement];
  if (!raw) {
    return nil;
  }
  return [FBAXElementRef retainingBorrowedElement:raw];
}

#pragma mark FBAXRuntime

- (nullable id)applicationElementForProcessIdentifier:(pid_t)pid
{
  return [_elementClass elementWithProcessIdentifier:pid];
}

// The snapshot path's failures, kept together so each one names what is missing rather than sharing a
// code with the others.
static NSError *FBAXSnapshotFailure(NSInteger code, NSString *description)
{
  return [NSError errorWithDomain:@"FBAXBridgeSnapshot"
                             code:code
                         userInfo:@{NSLocalizedDescriptionKey : description}];
}

// The body both snapshot entry points share, taking the raw reference the framework wants. The framework
// passes its argument straight to the accessibility call without unwrapping it, which is why the callers
// unwrap on their side of this seam rather than handing over the element wrapper the other methods take.
- (nullable id)snapshotOfReference:(id)reference
                    attributeNames:(NSArray<NSString *> *)names
                     namesByNumber:(NSDictionary<NSNumber *, NSString *> *_Nullable *_Nonnull)namesByNumber
                             error:(NSError **)error
{
  SEL selector = @selector(userTestingSnapshotForElement:options:error:);
  if (![_framework respondsToSelector:selector]) {
    if (error) {
      *error = FBAXSnapshotFailure(1, @"this runtime's XCTAccessibilityFramework has no userTestingSnapshotForElement:options:error:");
    }
    return nil;
  }
  if (!_functions.defaultSnapshotParameters || !_functions.attributeNumbersForNames) {
    if (error) {
      *error = FBAXSnapshotFailure(3, @"this runtime has no XCTDefaultSnapshotParameters/XCAXAccessibilityAttributesForStringAttributes");
    }
    return nil;
  }

  // Positional: the numbers come back in the order the names went in, so zipping the two recovers the
  // mapping the snapshot's numeric keys are read through. A result of another length cannot be zipped,
  // and guessing at the alignment would mislabel every attribute in the tree.
  NSArray<NSNumber *> *numbers = _functions.attributeNumbersForNames(names);
  if (![numbers isKindOfClass:NSArray.class] || numbers.count != names.count) {
    if (error) {
      *error = FBAXSnapshotFailure(4, @"the attribute name conversion answered a list of a different length");
    }
    return nil;
  }
  NSMutableDictionary<NSNumber *, NSString *> *inverse = [NSMutableDictionary dictionary];
  [numbers enumerateObjectsUsingBlock:^(id number, NSUInteger index, BOOL *stop) {
    if ([number isKindOfClass:NSNumber.class]) {
      inverse[number] = names[index];
    }
  }];
  *namesByNumber = inverse;

  NSMutableDictionary *options = [_functions.defaultSnapshotParameters() mutableCopy] ?: [NSMutableDictionary dictionary];
  options[@"attributes"] = numbers;

  return [_framework userTestingSnapshotForElement:reference options:options error:error];
}

- (nullable id)snapshotOfElement:(id)element
                  attributeNames:(NSArray<NSString *> *)names
                   namesByNumber:(NSDictionary<NSNumber *, NSString *> *_Nullable *_Nonnull)namesByNumber
                           error:(NSError **)error
{
  // Unwrapped here, where the accessor is declared and its signature is checked.
  XCAccessibilityElement *wrapper = element;
  void *reference = [wrapper respondsToSelector:@selector(AXUIElement)] ? [wrapper AXUIElement] : NULL;
  if (!reference) {
    if (error) {
      *error = FBAXSnapshotFailure(2, @"the element carries no AXUIElement to snapshot");
    }
    return nil;
  }
  return [self snapshotOfReference:(__bridge id)reference attributeNames:names namesByNumber:namesByNumber error:error];
}

- (pid_t)owningProcessIdentifierForSnapshotElement:(id)element
{
  // The snapshot's element key holds a raw AXUIElementRef, which is exactly what the pid lookup takes —
  // but the C entry points do not check what they are handed, so the type is proven before the call
  // rather than trusted from the key's name. A failed lookup answers 0, the value the interface names
  // "unknown" — never a guess.
  if (!element || !_functions.getPid || !_functions.elementTypeID) {
    return 0;
  }
  if (CFGetTypeID((__bridge CFTypeRef)element) != _functions.elementTypeID()) {
    return 0;
  }
  pid_t pid = 0;
  if (_functions.getPid((__bridge void *)element, &pid) != FBAXErrorSuccess) {
    return 0;
  }
  return pid;
}

- (nullable id)snapshotOfSnapshotElement:(id)element
                          attributeNames:(NSArray<NSString *> *)names
                           namesByNumber:(NSDictionary<NSNumber *, NSString *> *_Nullable *_Nonnull)namesByNumber
                                   error:(NSError **)error
{
  // The snapshot's element key already holds the raw reference the framework wants; there is nothing to
  // unwrap. The reference is owned by the snapshot dictionary it came from, which the caller is holding.
  if (!element) {
    if (error) {
      *error = FBAXSnapshotFailure(2, @"the snapshot node carries no element to snapshot");
    }
    return nil;
  }
  return [self snapshotOfReference:element attributeNames:names namesByNumber:namesByNumber error:error];
}

- (BOOL)getRect:(CGRect *)rect fromValue:(id)value
{
  if (!rect || !value || !_functions.valueGetType || !_functions.valueGetValue) {
    return NO;
  }
  CFTypeRef reference = (__bridge CFTypeRef)value;
  if (_functions.valueGetType(reference) != FBAXValueTypeCGRect) {
    return NO;
  }
  return _functions.valueGetValue(reference, FBAXValueTypeCGRect, rect) ? YES : NO;
}

- (BOOL)getPoint:(CGPoint *)point fromValue:(id)value
{
  if (!point || !value || !_functions.valueGetType || !_functions.valueGetValue) {
    return NO;
  }
  CFTypeRef reference = (__bridge CFTypeRef)value;
  if (_functions.valueGetType(reference) != FBAXValueTypeCGPoint) {
    return NO;
  }
  return _functions.valueGetValue(reference, FBAXValueTypeCGPoint, point) ? YES : NO;
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
  // The seed is owned either way so both branches release alike; every raw use below goes through
  // `-axErrorFromElement:`.
  FBAXElementRef *seed = nil;
  if (pid > 0) {
    XCAccessibilityElement *root = [_elementClass elementWithProcessIdentifier:pid];
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

  __block void *copied = NULL;
  int32_t axError = [seed axErrorFromElement:^int32_t (void *element) {
    return self->_functions.copyElementAtPosition(element, (float)point.x, (float)point.y, &copied);
  }];
  // Wrapped before anything else can fail. The copy is +1 whenever it produced one, so from here every
  // exit releases it without having to say so — including the error paths, where the runtime is not
  // supposed to have produced an element at all but nothing stops it.
  FBAXElementRef *hit = copied ? [[FBAXElementRef alloc] initWithOwnedElement:copied] : nil;

  FBAXHitTestOutcome *unresolved = [FBAXHitTestOutcome outcomeForHitTestError:axError hasElement:hit != nil];
  if (unresolved) {
    return unresolved;
  }

  // The host tags the hit element with its owning process, so an unattributable hit is not a result. A
  // seeded hit-test already knows the pid and falls back to it; a system-wide one has no other source.
  __block pid_t owningPid = 0;
  int32_t pidError = [hit axErrorFromElement:^int32_t (void *element) {
    return self->_functions.getPid(element, &owningPid);
  }];
  if (pidError != FBAXErrorSuccess || owningPid <= 0) {
    if (pid <= 0) {
      return [FBAXHitTestOutcome failed:[NSString stringWithFormat:@"could not resolve the owning pid of the hit element (%d)", pidError]];
    }
    owningPid = pid;
  }

  // `elementWithAXUIElement:` takes a reference of its own, so the wrapper's goes when it leaves scope.
  XCAccessibilityElement *hitElement = [hit objectFromElement:^id _Nullable (void *element) {
    return [self->_elementClass elementWithAXUIElement:element];
  }];
  if (!hitElement) {
    return [FBAXHitTestOutcome failed:@"failed to read the hit element"];
  }
  return [FBAXHitTestOutcome hit:hitElement owningProcessIdentifier:owningPid];
}

- (FBAXWriteOutcome *)performAction:(FBAXAction)action onElement:(id)element
{
  // Only reachable when an `FBAXAction` case is added without a mapping in `FBAXActionIdentifierForAction`.
  uint32_t identifier = 0;
  if (!FBAXActionIdentifierForAction(action, &identifier)) {
    return [FBAXWriteOutcome failed:[NSString stringWithFormat:@"no AX runtime identifier for action %lu", (unsigned long)action]];
  }
  FBAXElementRef *reference = [self referenceForElement:element];
  if (!reference) {
    return [FBAXWriteOutcome failed:@"the element has no AXUIElement to act on"];
  }
  // A write is the shape most exposed to the reference dying under the call — it is live across a
  // cross-process round trip that lasts as long as the application takes to run the action.
  // `-axErrorFromElement:` is what holds it open for that.
  int32_t axError = [reference axErrorFromElement:^int32_t (void *raw) {
    return self->_functions.performAction(raw, identifier);
  }];
  return [FBAXWriteOutcome outcomeForWriteError:axError];
}

- (FBAXWriteOutcome *)setValue:(id)value onElement:(id)element
{
  FBAXElementRef *reference = [self referenceForElement:element];
  if (!reference) {
    return [FBAXWriteOutcome failed:@"the element has no AXUIElement to write to"];
  }
  // __bridge and not __bridge_retained: the runtime borrows the value, and `value` is an argument the
  // caller owns for longer than this call takes.
  int32_t axError = [reference axErrorFromElement:^int32_t (void *raw) {
    return self->_functions.setAttributeValue(raw, FBAXAttributeIdentifierValue, (__bridge const void *)value);
  }];
  return [FBAXWriteOutcome outcomeForWriteError:axError];
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

// Reads a batch of attributes through the translator rather than through XCTest's attribute bundle. The
// element may be an `XCAccessibilityElement` or a translation object the translator itself returned, and
// both are accepted so a walk can hand its own children straight back in.
- (nullable NSDictionary<NSNumber *, id> *)translatorAttributes:(NSArray<NSNumber *> *)attributes
                                                      ofElement:(id)element
{
  if (attributes.count == 0 || !element) {
    return nil;
  }
  __block NSDictionary *result = nil;
  FBAXBridgeRunOffMainQueue(^{
    NSString *setupError = nil;
    AXPTranslator *translator = FBAXBridgeWindowServerTranslator(&setupError);
    if (!translator) {
      return;
    }
    id translation = element;
    if ([element respondsToSelector:@selector(AXUIElement)]) {
      void *raw = [(XCAccessibilityElement *)element AXUIElement];
      if (!raw) {
        return;
      }
      translation = [translator translationObjectFromPlatformElement:raw];
    }
    if (!translation) {
      return;
    }
    Class requestClass = objc_lookUpClass("AXPTranslatorRequest");
    if (!requestClass) {
      return;
    }
    AXPTranslatorRequest *request = [requestClass requestWithTranslation:translation];
    request.requestType = FBAXPRequestTypeMultipleAttribute;
    // `clientType` is left unset on purpose. The app-side children handler answers a client that "deserves
    // automation" from its stored `automationElements` override, which nothing invalidates — a stale one
    // serves the previous screen. No client type keeps this read on the live traversal.
    // The handler subscripts `parameters` by this key; an array here throws and takes the reader down.
    request.parameters = @{@"attributes" : attributes};
    @try {
      AXPTranslatorResponse *response = [translator processTranslatorRequest:request];
      id data = response.resultData;
      result = [data isKindOfClass:NSDictionary.class] ? data : nil;
    } @catch (NSException *exception) {
      result = nil;
    }
  });
  return result;
}

// The launch-services process holding `com.apple.frontboard.visibility` is the foreground app — the
// window server's own notion, read from RunningBoard rather than the AX stack, so it needs neither an
// anchor nor the AX server. Requires the `com.apple.runningboard.process-state` entitlement; without it
// runningboardd answers "Client not entitled".
- (FBAXFrontmostOutcome *)runningBoardFrontmost
{
  dlopen(FBAXPathRunningBoardServices, RTLD_NOW);
  // Cast to the `Class<…>` protocols: `+descriptor` also exists on NSAppleEventDescriptor (see the header).
  Class<RBSProcessPredicateClass> predicateClass = (Class<RBSProcessPredicateClass>)objc_lookUpClass("RBSProcessPredicate");
  Class<RBSProcessStateClass> stateClass = (Class<RBSProcessStateClass>)objc_lookUpClass("RBSProcessState");
  Class<RBSProcessStateDescriptorClass> descriptorClass = (Class<RBSProcessStateDescriptorClass>)objc_lookUpClass("RBSProcessStateDescriptor");
  if (!predicateClass || !stateClass || ![stateClass respondsToSelector:@selector(statesForPredicate:withDescriptor:error:)]) {
    return [FBAXFrontmostOutcome unresolved:@"RunningBoardServices unavailable — is RunningBoardServices loaded?"];
  }

  RBSProcessPredicate *predicate = [predicateClass predicateMatchingLaunchServicesProcesses];

  // The descriptor selects which fields RunningBoard populates. Request the endowment namespaces so each
  // returned state carries its visibility endowment: the concrete "values" bitmask is not stable across
  // OS versions, so it is set to all-bits defensively and the specific endowment namespace is named too.
  RBSProcessStateDescriptor *descriptor = nil;
  if (descriptorClass) {
    descriptor = [descriptorClass descriptor];
    @try {
      if ([descriptor respondsToSelector:@selector(setValues:)]) {
        descriptor.values = ~0ull;
      }
      if ([descriptor respondsToSelector:@selector(setEndowmentNamespaces:)]) {
        descriptor.endowmentNamespaces = @[kFrontboardVisibilityEndowment];
      }
    } @catch (NSException *exception) {
      // fall through with the default descriptor
    }
  }

  NSError *error = nil;
  NSArray<RBSProcessState *> *states = [stateClass statesForPredicate:predicate withDescriptor:descriptor error:&error];
  if (![states isKindOfClass:NSArray.class]) {
    return [FBAXFrontmostOutcome unresolved:
            [NSString stringWithFormat:@"RunningBoard process-state query failed: %@", error ?: @"(no states returned)"]];
  }

  for (RBSProcessState *state in states) {
    if (![state respondsToSelector:@selector(endowmentNamespaces)]) {
      continue;
    }
    if (![state.endowmentNamespaces containsObject:kFrontboardVisibilityEndowment]) {
      continue;
    }
    RBSProcessHandle *process = [state respondsToSelector:@selector(process)] ? state.process : nil;
    if (!process || ![process respondsToSelector:@selector(pid)]) {
      continue;
    }
    if (process.pid > 0) {
      return [FBAXFrontmostOutcome resolved:process.pid];
    }
  }

  return [FBAXFrontmostOutcome unresolved:@"no launch-services process holds the on-screen visibility endowment"];
}

@end
