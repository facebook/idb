/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

// The accessibility runtime, as one interface with one set of results.
//
// Everything the reader needs from the four private frameworks it binds — XCTAutomationSupport, AXRuntime,
// AccessibilityPlatformTranslation and RunningBoardServices — is stated here as `FBAXRuntime`, and
// `FBAXLiveRuntime` is the only thing in the product that touches them. Above the interface is policy:
// verbs, pid selection, tree walking, budgets, the wire envelope. Below it are the dlopens, the class
// lookups, the C entry points and the reference counting.
//
// Two problems motivate the split. The ownership and signature rules of a private API cannot be enforced
// where they are only observed — a rule stated in a comment beside one call site is not a rule, which is
// how a borrowed AXUIElementRef became a SIGSEGV. And the private-API-facing half of the reader had no
// seam, so none of it could be tested: a fake conformer reaches every outcome below without a booted
// simulator.
//
// The results are tagged unions. Every interaction has more than two outcomes and the interesting ones
// are not failures: a hit-test on empty space succeeded and found nothing, and a read of a process with
// no accessibility server is neither a hit nor a reader bug. Returning `nil` plus an out-parameter forces
// each caller to re-derive which of those happened from whatever it was handed. A result type per
// interaction states the cases once. The constructors are the enforcement: nothing stops a caller reading
// `.attributes` on a failure, but nothing lets it *build* that combination, and a `switch` over the status
// warns when a case is left unhandled.

#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Reads

/** How a read of an element's attributes turned out. */
typedef NS_ENUM(NSUInteger, FBAXReadStatus) {
  /** The element was read; `attributes` holds what it said. */
  FBAXReadStatusRead,
  /** The owning process has no accessibility server to answer the read. */
  FBAXReadStatusApplicationUnavailable,
  /** The owning process has an accessibility server that did not answer in time. */
  FBAXReadStatusApplicationNotResponding,
  /** The read went wrong; `error` holds why, if the runtime said. */
  FBAXReadStatusFailed,
};

/**
 * The result of reading an element.
 *
 * A read names an element that already exists, so there is no "nothing there" case — an element that
 * cannot be read either belongs to an unreadable application or failed outright.
 */
@interface FBAXReadOutcome : NSObject

@property (nonatomic, readonly) FBAXReadStatus status;
/** The attributes read, with children nested under the children key. Non-nil iff `Read`. */
@property (nullable, nonatomic, readonly, copy) NSDictionary<NSString *, id> *attributes;
/** Why the read failed. Only meaningful when `Failed`, and nil when the runtime reported no error. */
@property (nullable, nonatomic, readonly) NSError *error;

+ (instancetype)read:(NSDictionary<NSString *, id> *)attributes;
+ (instancetype)applicationUnavailable;
+ (instancetype)applicationNotResponding;
+ (instancetype)failed:(nullable NSError *)error;

/**
 * Classifies a failed `-[XCTAccessibilityFramework attributesForElement:attributes:error:]` into
 * `ApplicationUnavailable`, `ApplicationNotResponding` or `Failed`, from the FBAXError the reader
 * reported under FBAXAccessibilityErrorKey.
 *
 * This is the only place that judgement is made, so every read answers alike and callers switch on the
 * status rather than re-inspecting the error.
 */
+ (instancetype)failureForAttributeError:(nullable NSError *)error;

@end

#pragma mark - Hit-tests

/** How a hit-test at a point turned out. */
typedef NS_ENUM(NSUInteger, FBAXHitTestStatus) {
  /** An element owns the point; `element` and `owningProcessIdentifier` describe it. */
  FBAXHitTestStatusHit,
  /** Nothing is at the point — a valid result, distinct from the hit-test having gone wrong. */
  FBAXHitTestStatusEmpty,
  /** Nothing answered the hit-test: the process has no accessibility server. */
  FBAXHitTestStatusApplicationUnavailable,
  /**
   * The process has an accessibility server and it did not answer in time.
   *
   * Held apart from `Empty` because the two look identical to a caller and mean opposite things: an app
   * that is busy or suspended reads as blank space, which is exactly what a caller sees after a tap it is
   * still processing. Held apart from `ApplicationUnavailable` because the application has not gone away.
   */
  FBAXHitTestStatusApplicationNotResponding,
  /** The hit-test went wrong; `failureReason` says how. */
  FBAXHitTestStatusFailed,
};

/**
 * The result of hit-testing a point.
 *
 * The hit element is vended already wrapped: the raw +1 AXUIElementRef the AX runtime copies out never
 * escapes the runtime that asked for it, so no caller can outlive or over-release it.
 */
@interface FBAXHitTestOutcome : NSObject

@property (nonatomic, readonly) FBAXHitTestStatus status;
/** An opaque handle to the element at the point, readable only through the runtime. Non-nil iff `Hit`. */
@property (nullable, nonatomic, readonly) id element;
/** The process owning `element`, always positive when `Hit`. */
@property (nonatomic, readonly) pid_t owningProcessIdentifier;
/** A diagnostic for the caller. Non-nil iff `Failed`. */
@property (nullable, nonatomic, readonly, copy) NSString *failureReason;

+ (instancetype)hit:(id)element owningProcessIdentifier:(pid_t)pid;
+ (instancetype)empty;
+ (instancetype)applicationUnavailable;
+ (instancetype)applicationNotResponding;
+ (instancetype)failed:(NSString *)failureReason;

/**
 * Classifies the AXError from `AXUIElementCopyElementAtPosition`, given whether it also produced an
 * element, into the outcome that error implies. The wording of what the caller is eventually told is
 * the caller's — this decides only which of the four things happened.
 *
 * Returns nil — and only then — when the point resolved to an element the caller should go on to
 * attribute and wrap. Every other answer is complete, so a caller that gets non-nil is done.
 *
 * Split out from the hit-test itself because that method cannot be constructed off a simulator, which
 * left this judgement — the one that decides whether the host is told "nothing is there", "nothing
 * answered" or "the read broke" — reachable only by manufacturing the condition on a booted device.
 */
+ (nullable instancetype)outcomeForHitTestError:(int32_t)axError hasElement:(BOOL)hasElement;

@end

#pragma mark - Writes

/**
 * A semantic action an element can be asked to perform.
 *
 * The numbers the AX runtime takes stay below this line: an action crosses the interface as what it means,
 * so a runtime that renumbers them is one table in the implementation rather than a constant threaded
 * through the service, the wire and the host.
 *
 * Only actions with a caller are listed. Increment and Decrement exist in the runtime and are deliberately
 * absent — nothing above the seam can ask for them, and an action no caller can reach is a case every
 * switch has to handle for nothing.
 */
typedef NS_ENUM(NSUInteger, FBAXAction) {
  /** Activate the element — the semantic equivalent of tapping it. */
  FBAXActionPress,
  FBAXActionScrollUp,
  FBAXActionScrollDown,
  FBAXActionScrollLeft,
  FBAXActionScrollRight,
  /** Bring the element into its scroll container's viewport. */
  FBAXActionScrollToVisible,
};

/** How a write to an element turned out. */
typedef NS_ENUM(NSUInteger, FBAXWriteStatus) {
  /** The application accepted the write. */
  FBAXWriteStatusWritten,
  /** Nothing was at the point, so there was nothing to write to — a valid result, not a failure. */
  FBAXWriteStatusEmpty,
  /** The element at the point is not the one the caller named; `failureReason` says how it differed. */
  FBAXWriteStatusAssertionFailed,
  /** The owning process has no accessibility server to accept the write. */
  FBAXWriteStatusApplicationUnavailable,
  /** It has one and did not answer in time, so whether the write ran is unknown. */
  FBAXWriteStatusApplicationNotResponding,
  /** The write went wrong; `failureReason` says how. */
  FBAXWriteStatusFailed,
};

/**
 * The result of a write interaction.
 *
 * Unlike the read outcomes this one has two producers, and the status says which. The runtime produces
 * `Written`, `ApplicationUnavailable`, `ApplicationNotResponding` and `Failed` — everything an AXError can
 * mean. The other two are decided before the runtime is ever asked: nothing was at the point, or what was
 * there is not the element the caller named. They share one type because a write reports one outcome, and a
 * caller made to switch over two types to learn whether its tap landed has been handed back the problem the
 * outcomes exist to remove.
 */
@interface FBAXWriteOutcome : NSObject

@property (nonatomic, readonly) FBAXWriteStatus status;
/** A diagnostic for the caller. Non-nil iff `AssertionFailed` or `Failed`. */
@property (nullable, nonatomic, readonly, copy) NSString *failureReason;

+ (instancetype)written;
+ (instancetype)empty;
+ (instancetype)assertionFailed:(NSString *)failureReason;
+ (instancetype)applicationUnavailable;
+ (instancetype)applicationNotResponding;
+ (instancetype)failed:(NSString *)failureReason;

/**
 * Classifies the AXError from `AXUIElementPerformAction` or `AXUIElementSetAttributeValue` into the outcome
 * it implies, including success.
 *
 * Unlike the hit-test classifier this one is total — a write either happened or it did not, so there is no
 * "the caller finishes this" case.
 *
 * There is deliberately no "the element does not accept this action" outcome. The AX runtime has a code for
 * it and does not emit it, and nothing an element advertises can be consulted instead:
 * `XC_kAXXCAttributeUserTestingActions` is absent on every element (a sweep of SpringBoard and Settings
 * found it on none of 206 nodes). An action an element ignores is therefore reported as a plain success,
 * and there is no honest way to tell that apart from a write that landed.
 */
+ (instancetype)outcomeForWriteError:(int32_t)axError;

@end

#pragma mark - Frontmost

/** How a frontmost-application query turned out. */
typedef NS_ENUM(NSUInteger, FBAXFrontmostStatus) {
  /** The frontmost application is `processIdentifier`. */
  FBAXFrontmostStatusResolved,
  /** Whatever is frontmost has no accessibility server, so the query could not name it. */
  FBAXFrontmostStatusApplicationUnavailable,
  /** Whatever is frontmost has an accessibility server that did not answer in time. */
  FBAXFrontmostStatusApplicationNotResponding,
  /** The frontmost application could not be determined; `failureReason` says why. */
  FBAXFrontmostStatusUnresolved,
};

/**
 * The result of asking the runtime which application is frontmost.
 *
 * It carries no notion of *which* strategy answered. A resolver reports only what it found, and the
 * caller that chose the resolver is the one that names it on the wire — so a response whose `method`
 * disagrees with the resolver that ran is not something this can express.
 *
 * It does distinguish *why* it did not answer. "Nothing on screen has an accessibility server" and
 * "AXPTranslator is not in this runtime" are both a frontmost that could not be named, and they need
 * opposite things done about them, so they are separate cases rather than two spellings of one.
 */
@interface FBAXFrontmostOutcome : NSObject

@property (nonatomic, readonly) FBAXFrontmostStatus status;
/** The frontmost application's process. Always positive when `Resolved`. */
@property (nonatomic, readonly) pid_t processIdentifier;
/** A diagnostic for the caller. Non-nil unless `Resolved`. */
@property (nullable, nonatomic, readonly, copy) NSString *failureReason;

+ (instancetype)resolved:(pid_t)pid;
+ (instancetype)applicationUnavailable:(NSString *)failureReason;
+ (instancetype)applicationNotResponding:(NSString *)failureReason;
+ (instancetype)unresolved:(NSString *)failureReason;

@end

#pragma mark - Bound signatures

/**
 * A method type encoding with its frame size and argument offsets dropped, leaving only the types.
 *
 * `method_getTypeEncoding` returns the types interleaved with byte offsets — `Q16@0:8` is a `Q` return,
 * `@` self at 0, `:` selector at 8, in a 16-byte frame. The numbers are derived from the types by the
 * ABI, so they add no detection power and differ between architectures; comparing them would make the
 * signature check fire where nothing had actually changed.
 *
 * Digits *inside* a struct, union or array encoding are part of the type and are kept: `{Q=[4i]}` and
 * `{Q=[8i]}` are different types, and collapsing them would let a bound API taking one compare equal to
 * one taking the other.
 *
 * Exported for its own tests. It is the whole of what makes the comparison below trustworthy, and it is
 * easier to say what it does with a table of examples than with prose.
 */
extern NSString *FBAXTypesOnly(const char *encoding);

/**
 * Checks a private API's signature against the one this code was written for.
 *
 * Returns nil when they agree, and otherwise a diagnostic naming both — including when the class or the
 * selector is not in the runtime at all, which is the same problem arriving a different way.
 *
 * A private API can change shape under a new Xcode or a new OS with nothing to say so. The declaration or
 * the `objc_msgSend` cast at the call site keeps compiling, and the process goes on reading arguments and
 * return values off offsets that are no longer where the runtime puts them. `method_getTypeEncoding` is
 * the runtime's own record of the real signature, so comparing it against a written-down constant is what
 * turns that into something with a name.
 *
 * Only the types are compared. The frame size and argument offsets an encoding also carries are derived
 * from the types by the ABI, so they add no detection power — and they are ABI-dependent, so comparing
 * them would make the check fire on an architecture where nothing has actually changed. `expected` may
 * therefore be written either verbatim from `method_getTypeEncoding` or with the numbers already dropped.
 */
extern NSString *_Nullable FBAXSignatureMismatch(
  const char *className,
  const char *selectorName,
  BOOL isClassMethod,
  const char *expected);

/**
 * Every bound private API whose runtime signature disagrees with the one this code assumes, named.
 *
 * Empty on a runtime the reader agrees with. `SimulatorFrameworkBridgeLibTests` asserts exactly that, and
 * runs inside a booted simulator, which is where a drifting signature is meant to be caught: a failing test
 * is a signal somebody acts on, where a warning logged by a guest process on a booted simulator is not. The
 * simulator is what makes the assertion worth anything -- the four frameworks exist on macOS too, and a
 * shape that moved only inside an iOS runtime image would pass against the host's copies.
 *
 * The product itself calls this only when a bind has already failed, to say alongside the missing class
 * what else about the runtime moved. A process that bound cleanly never sweeps.
 */
extern NSArray<NSString *> *FBAXSignatureWarnings(void);

#pragma mark - The runtime

/**
 * Everything the reader needs from the accessibility runtime.
 *
 * The interface is drawn around whole interactions rather than around individual runtime calls. A
 * hit-test is one method, not a seed-element method plus a copy method plus a pid method, because a seed
 * handed across the interface is a reference whose lifetime the caller becomes responsible for — which
 * is the hazard the interface exists to remove. Elements are vended only as opaque handles that the
 * runtime itself interprets; no raw AXUIElementRef is ever produced above this line.
 */
@protocol FBAXRuntime <NSObject>

/**
 * An opaque handle to a process's application element, to be read with `-readAttributes:ofElement:`.
 *
 * Non-nil for any pid: the runtime vends an element for a dead pid, a non-application process and pid 0
 * alike. Whether the pid names something readable is knowable only from reading it.
 */
- (nullable id)applicationElementForProcessIdentifier:(pid_t)pid;

/** Reads `attributes` off an element handle in one round trip. */
- (FBAXReadOutcome *)readAttributes:(NSArray<NSString *> *)attributes ofElement:(id)element;

/**
 * A whole bounded subtree in **one** round trip, via the call XCUITest walks hierarchies with.
 *
 * The alternative to `-readAttributes:ofElement:` per node. A tree of N nodes costs N round trips that
 * way and one this way, which matters because each round trip is a rendezvous with the target's main
 * thread — on a busy application that wait, not the work, is the dominant cost of a read.
 *
 * Resolved lazily rather than through `kFBAXBoundSelectors`, so a runtime without the selector loses this
 * path and keeps every other one. Nil means the read could not be performed — including "this runtime
 * does not have the selector", which `*error` distinguishes.
 *
 * `names` are the same `XC_kAXXCAttribute*` names `-readAttributes:ofElement:` takes, but a snapshot
 * answers keyed by the numbers they convert to, so `namesByNumber` comes back carrying that mapping.
 * Building the options is part of this interaction rather than the caller's: the server rejects a
 * dictionary not derived from its own defaults by answering nothing, which reads as an empty screen.
 */
- (nullable id)snapshotOfElement:(id)element
                  attributeNames:(NSArray<NSString *> *)names
                   namesByNumber:(NSDictionary<NSNumber *, NSString *> *_Nullable *_Nonnull)namesByNumber
                           error:(NSError **)error;

/**
 * The process that answers for the element a snapshot node carries under its element key.
 *
 * A snapshot is served by the process that owns its root, and it cannot serialize a subtree another
 * process draws — a web view's page, a picker, an autofill sheet. The node it stops at still names the
 * element it could not descend into, and which process owns that element is what tells a reader the
 * nesting ended at a process boundary rather than at a leaf.
 *
 * 0 when the value does not carry an element this runtime can attribute; a caller must read that as
 * unknown, never as a process.
 */
- (pid_t)owningProcessIdentifierForSnapshotElement:(id)element;

/**
 * The counterpart of `-snapshotOfElement:…` for an element a snapshot node carries: one more fetch,
 * rooted at that element, answered by the process that owns it.
 *
 * This is what continues a snapshot across a process boundary. The hosting process's snapshot stops at
 * the boundary element with no nesting; a snapshot rooted at the same element is served by the process
 * drawing the subtree, and descends until ownership changes again. Ask, options and `namesByNumber` are
 * exactly `-snapshotOfElement:…`'s.
 */
- (nullable id)snapshotOfSnapshotElement:(id)element
                          attributeNames:(NSArray<NSString *> *)names
                           namesByNumber:(NSDictionary<NSNumber *, NSString *> *_Nullable *_Nonnull)namesByNumber
                                   error:(NSError **)error;

/**
 * Unwraps the `CGRect` an `AXValue` wraps, which is the form a snapshot answers frames in.
 *
 * An `AXValue` is a CFType with its own accessor rather than an `NSValue`, so a caller that only knows
 * about `NSValue` sees `__NSCFType` and drops the frame.
 *
 * NO when the value does not hold a rect, leaving `*rect` untouched. Unwrapping is type-checked here
 * because the runtime does not check it: a point read as a rect answers with a frame rather than failing.
 */
- (BOOL)getRect:(CGRect *)rect fromValue:(id)value;

/**
 * Unwraps the `CGPoint` an `AXValue` wraps, which is the form a snapshot answers the reachability hit
 * points in. The counterpart to `-getRect:fromValue:` for `kAXValueCGPointType`.
 *
 * NO when the value does not hold a point, leaving `*point` untouched. Unwrapping is type-checked here
 * because the runtime does not check it: a rect read as a point answers with a coordinate rather than
 * failing, and the host taps the points this method unwraps.
 */
- (BOOL)getPoint:(CGPoint *)point fromValue:(id)value;

/**
 * The element at a point, in one round trip.
 *
 * A positive `pid` scopes the hit-test to that application; a non-positive one makes it display-wide, so
 * the point is resolved against whichever application owns it without the caller knowing that in advance.
 * Either way the owning process comes back on the outcome.
 */
- (FBAXHitTestOutcome *)hitTestAtPoint:(CGPoint)point processIdentifier:(pid_t)pid;

/**
 * Performs a semantic action on an element handle, in one round trip.
 *
 * The handle is the one a hit-test vends, so a write takes the same opaque element a read does. Whether
 * the element advertises the action is not asked here — the runtime performs what it is told and reports
 * an unadvertised action as a success, so that judgement belongs to the caller that read the element.
 */
- (FBAXWriteOutcome *)performAction:(FBAXAction)action onElement:(id)element;

/** Writes an element handle's value attribute, in one round trip. */
- (FBAXWriteOutcome *)setValue:(id)value onElement:(id)element;

/** The frontmost application according to the window server, via the in-guest AXPTranslator. */
- (FBAXFrontmostOutcome *)windowServerFrontmost;

/** The frontmost application according to RunningBoard's on-screen visibility endowment. */
- (FBAXFrontmostOutcome *)runningBoardFrontmost;

/**
 * Reads `attributes` off `element` through the in-guest accessibility translator, in one round trip.
 *
 * A second vocabulary alongside `-readAttributes:ofElement:`, which asks in XCTest's `XC_kAXXCAttribute*`
 * names. Both reach the same server, but they are separate namespaces with separate handlers and the two
 * disagree on some screens — the translator answers what an out-of-process client sees, which is not
 * always what XCTest's attribute bundle reports.
 *
 * `element` may be either an element handle from this seam or a translation object returned by an
 * earlier translator read — a walk hands its own children straight back in, and having to remember
 * which kind is in hand at each level is a bug waiting to happen.
 *
 * `attributes` are `FBAXPAttribute` values. The result is keyed by those same values, and omits any the
 * server did not answer. Nil means the read could not be performed at all, which is distinct from a read
 * that succeeded and returned nothing.
 */
- (nullable NSDictionary<NSNumber *, id> *)translatorAttributes:(NSArray<NSNumber *> *)attributes
                                                      ofElement:(id)element;

/**
 * Whether the device is in accessibility automation mode.
 *
 * This is `_AXSAutomationEnabled()` — a device-wide setting, not a property of this process or of the
 * target. With it off, UIKit collapses subtrees behind opaque element providers and caches a container's
 * children; with it on, the full structure is exposed and children are recomputed per read.
 *
 * Read in the *guest*, which is not the target application. The value is the same device-wide setting
 * either way, but the target caches its own view of it behind a notification observer, so a read here
 * says what the device is set to and not that the target has already observed it.
 */
- (BOOL)automationModeEnabled;

/**
 * Asks the device for automation mode, and reports what the flag reads back as afterwards.
 *
 * Returns the read-back state rather than whether the write was attempted, because the two differ: this
 * writes a preference through `AXSettings`, and a preference write can fail silently. A caller that
 * assumed success would report a mode the device is not in.
 *
 * Device-wide and persistent. It is not restored when this process exits, and `AXRuntime` clears it
 * unconditionally when an accessibility observer client dies — so a caller must not assume a value it set
 * earlier is still in force.
 */
- (BOOL)setAutomationModeEnabled:(BOOL)enabled;

@end

/**
 * The one conformer in the product: the private frameworks themselves.
 *
 * Constructing one is the whole bind — the dlopens, the class lookups and the C entry-point resolution
 * all happen here and nowhere else, so a runtime that cannot be bound is a named setup failure rather
 * than a null pointer discovered halfway through a request.
 */
@interface FBAXLiveRuntime : NSObject <FBAXRuntime>

/** Binds the private frameworks, or returns nil with `*error` set to what was missing. */
- (nullable instancetype)initWithError:(NSString *_Nullable *_Nullable)error NS_DESIGNATED_INITIALIZER;

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
