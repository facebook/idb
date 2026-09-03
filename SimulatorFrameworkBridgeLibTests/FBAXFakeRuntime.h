/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <SimulatorFrameworkBridgeLib/AccessibilityRuntime.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * An element in a fake accessibility tree.
 *
 * Stands in for the opaque handle `FBAXRuntime` vends. It carries the attributes a read of it answers
 * with, the children a read of it exposes, and — the point of the fake — the outcome that read produces,
 * so a subtree can be made unreadable at any node.
 */
@interface FBAXFakeElement : NSObject

/** The element's attributes, excluding children. */
@property (nonatomic, copy) NSDictionary<NSString *, id> *attributes;
/** Children exposed under the children key when this element is read. */
@property (nonatomic, copy) NSArray<FBAXFakeElement *> *children;
/** What a read of this element answers with. */
@property (nonatomic, assign) FBAXReadStatus readStatus;
/** The error a `Failed` read carries. Nil models a runtime that failed while reporting nothing. */
@property (nullable, nonatomic, strong) NSError *readError;
/**
 * The process this element is drawn by, as `-owningProcessIdentifierForSnapshotElement:` reports it.
 *
 * What makes a process boundary expressible: a snapshot stops nesting where a child's owner differs
 * from its root's, exactly as the live server cannot serialize into a process it does not own — while
 * the per-node walk still exposes the children, because the server bridges each walked read across.
 * The default 0 is the interface's "unknown", which existing trees keep: everything owned by 0 is one
 * process and no read behaves differently.
 */
@property (nonatomic, assign) pid_t owningProcessIdentifier;

/** A readable element of the given type, labelled with it. */
+ (instancetype)readable:(NSString *)elementType;
/** An element whose read reports that its application has no accessibility server. */
+ (instancetype)applicationUnavailable;
/** An element whose read reports that its application did not answer in time. */
+ (instancetype)applicationNotResponding;
/** An element whose read fails, carrying `error` (which may be nil). */
+ (instancetype)failed:(nullable NSError *)error;

@end

/**
 * A rect only the fake runtime can unwrap, standing in for the `AXValue` a single fetch answers a frame
 * with.
 *
 * An `AXValue` cannot be constructed in a test: it is a CFType private to the real runtime. What a test
 * needs from a stand-in is only that no production branch recognises it, so that asking the runtime is
 * the only way to unwrap it. An `NSValue` would not do — the coercions unwrap `NSValue` themselves,
 * before asking the runtime, so a test feeding one never exercises the runtime's unwrapping at all.
 */
@interface FBAXFakeRectValue : NSObject

+ (instancetype)withRect:(CGRect)rect;

@property (nonatomic, readonly, assign) CGRect rect;

@end

/** A point only the fake runtime can unwrap; see `FBAXFakeRectValue`. */
@interface FBAXFakePointValue : NSObject

+ (instancetype)withPoint:(CGPoint)point;

@property (nonatomic, readonly, assign) CGPoint point;

@end

/**
 * A fake `FBAXRuntime`, wired into the service by `FBAXBridgeSetRuntimeForTesting`.
 *
 * Reaches the outcomes the live runtime only produces against a broken, dead or unresponsive
 * application — which on a real simulator need an app to be killed, SIGSTOP-ed or hit mid-launch — with
 * nothing booted. It also records what it was asked, so a test can assert which resolver actually ran
 * rather than only what came back.
 */
@interface FBAXFakeRuntime : NSObject <FBAXRuntime>

/** Application elements by pid. A pid absent here is answered with nil, as an unknown pid is. */
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, FBAXFakeElement *> *applicationElements;

/** What `-hitTestAtPoint:processIdentifier:` answers with. */
@property (nonatomic, strong) FBAXHitTestOutcome *hitTestOutcome;
/** What `-windowServerFrontmost` answers with. */
@property (nonatomic, strong) FBAXFrontmostOutcome *windowServerOutcome;
/** What `-runningBoardFrontmost` answers with. */
@property (nonatomic, strong) FBAXFrontmostOutcome *runningBoardOutcome;

/** What `-automationModeEnabled` answers with, and what a successful `-setAutomationModeEnabled:` sets. */
@property (nonatomic, assign) BOOL automationMode;
/**
 * When YES, `-setAutomationModeEnabled:` leaves `automationMode` untouched — the shape of a preference
 * write that is accepted and silently does not take, which is the case a caller must not read as success.
 */
@property (nonatomic, assign) BOOL automationModeWriteFails;
/** Every value passed to `-setAutomationModeEnabled:`, in order. Empty when nothing asked. */
@property (nonatomic, strong) NSMutableArray<NSNumber *> *automationModeWrites;

/** What `-translatorAttributes:ofElement:` answers with. Nil means the read could not be performed. */
@property (nullable, nonatomic, copy) NSDictionary<NSNumber *, id> *translatorAttributeValues;

/**
 * When set, `-snapshotOfElement:…` reports this instead of answering — the shape of a runtime with no
 * snapshot support, or an application that did not answer the one fetch in time.
 */
@property (nullable, nonatomic, strong) NSError *snapshotError;
/**
 * When YES, `-snapshotOfElement:…` answers nil with no error — what the accessibility server does when
 * handed options it will not accept, which is the failure that reads as an empty screen rather than as
 * an error.
 */
@property (nonatomic, assign) BOOL snapshotAnswersNothing;
/**
 * When set, `-snapshotOfSnapshotElement:…` reports this instead of answering, while the root fetch
 * still answers — the shape of a process boundary whose owner is not serving, which a read must survive
 * with the stub rather than fail on.
 */
@property (nullable, nonatomic, strong) NSError *snapshotContinuationError;

/**
 * How many snapshots were fetched, root fetches and boundary continuations alike — one for a whole tree
 * is the point of the single-fetch path, and one more per crossed boundary is its cost.
 */
@property (nonatomic, readonly) NSUInteger snapshotCount;
/** The attribute names the most recent snapshot was asked for, so a test can assert the ask. */
@property (nullable, nonatomic, readonly, copy) NSArray<NSString *> *lastSnapshotAttributeNames;

/** The attributes the last `-translatorAttributes:ofElement:` asked for, so a test can assert the ask. */
@property (nullable, nonatomic, readonly, copy) NSArray<NSNumber *> *lastTranslatorAttributes;

/** How many translator reads have been made — one request per node is the point of the batched form. */
@property (nonatomic, readonly) NSUInteger translatorReadCount;
/** What both write methods answer with. */
@property (nonatomic, strong) FBAXWriteOutcome *writeOutcome;

/**
 * When set, `-readAttributes:ofElement:` raises with this reason rather than answering.
 *
 * Stands in for the four private frameworks the live runtime reaches, which raise where they are meant to
 * return — the condition the reader's outcome types cannot express, because a raise is not a value.
 */
@property (nullable, nonatomic, copy) NSString *readRaiseReason;

/** How many times each interaction was asked for — the evidence that a resolver did or did not run. */
@property (nonatomic, readonly) NSUInteger hitTestCount;
@property (nonatomic, readonly) NSUInteger windowServerCount;
@property (nonatomic, readonly) NSUInteger runningBoardCount;
@property (nonatomic, readonly) NSUInteger performCount;
@property (nonatomic, readonly) NSUInteger setValueCount;
/**
 * The attribute list the most recent read was asked for.
 *
 * Records the request's own choice rather than the fake's answer: the fake echoes back whatever the
 * element holds, so this is the only way to assert *what was asked*, which is the whole of the
 * request-named-attributes mechanism.
 */
@property (nullable, nonatomic, readonly, copy) NSArray<NSString *> *lastReadAttributes;

/** The point of the most recent hit-test, and the pid it was scoped to (0 for display-wide). */
@property (nonatomic, readonly) CGPoint lastHitTestPoint;
@property (nonatomic, readonly) pid_t lastHitTestProcessIdentifier;
/**
 * What the most recent write was asked to do.
 *
 * `FBAXAction` has no "nothing yet" case, so `lastPerformedAction` reads as `FBAXActionPress` on a runtime
 * that was never asked to perform anything — assert `performCount` before believing it.
 */
@property (nonatomic, readonly) FBAXAction lastPerformedAction;
/** The element handle the most recent write of either kind was given, and the value a set-value wrote. */
@property (nullable, nonatomic, readonly, strong) id lastWrittenElement;
@property (nullable, nonatomic, readonly, strong) id lastWrittenValue;

@end

NS_ASSUME_NONNULL_END
