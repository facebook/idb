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
+ (instancetype)failed:(nullable NSError *)error;

/**
 * Classifies a failed `-[XCTAccessibilityFramework attributesForElement:attributes:error:]` into
 * `ApplicationUnavailable` or `Failed`, from the FBAXError the reader reported under
 * FBAXAccessibilityErrorKey.
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
+ (instancetype)failed:(NSString *)failureReason;

@end

#pragma mark - Frontmost

/** How a frontmost-application query turned out. */
typedef NS_ENUM(NSUInteger, FBAXFrontmostStatus) {
  /** The frontmost application is `processIdentifier`. */
  FBAXFrontmostStatusResolved,
  /** The frontmost application could not be determined; `failureReason` says why. */
  FBAXFrontmostStatusUnresolved,
};

/**
 * The result of asking the runtime which application is frontmost.
 *
 * It carries no notion of *which* strategy answered. A resolver reports only what it found, and the
 * caller that chose the resolver is the one that names it on the wire — so a response whose `method`
 * disagrees with the resolver that ran is not something this can express.
 */
@interface FBAXFrontmostOutcome : NSObject

@property (nonatomic, readonly) FBAXFrontmostStatus status;
/** The frontmost application's process. Always positive when `Resolved`. */
@property (nonatomic, readonly) pid_t processIdentifier;
/** A diagnostic for the caller. Non-nil iff `Unresolved`. */
@property (nullable, nonatomic, readonly, copy) NSString *failureReason;

+ (instancetype)resolved:(pid_t)pid;
+ (instancetype)unresolved:(NSString *)failureReason;

@end

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
 * The element at a point, in one round trip.
 *
 * A positive `pid` scopes the hit-test to that application; a non-positive one makes it display-wide, so
 * the point is resolved against whichever application owns it without the caller knowing that in advance.
 * Either way the owning process comes back on the outcome.
 */
- (FBAXHitTestOutcome *)hitTestAtPoint:(CGPoint)point processIdentifier:(pid_t)pid;

/** The frontmost application according to the window server, via the in-guest AXPTranslator. */
- (FBAXFrontmostOutcome *)windowServerFrontmost;

/** The frontmost application according to RunningBoard's on-screen visibility endowment. */
- (FBAXFrontmostOutcome *)runningBoardFrontmost;

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
