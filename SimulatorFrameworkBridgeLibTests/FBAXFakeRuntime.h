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
