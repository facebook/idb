/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

// Synthetic header for the RunningBoardServices private API.
//
// RunningBoard is the process-lifecycle daemon, and it knows which process holds an on-screen scene —
// the same foreground app the accessibility stack reports, read from a different source. The framework
// is dlopen-loaded from the booted runtime root and its classes resolved with objc_lookUpClass, so
// nothing here is referenced at link time.
//
// Enumerating another process's state requires the private com.apple.runningboard.process-state
// entitlement; without it runningboardd rejects the query with "Client not entitled". The guest binary
// carries it and the simulator's runningboardd honours it.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/** The framework's path inside the booted runtime root, for dlopen. */
#define FBAXPathRunningBoardServices \
        "/System/Library/PrivateFrameworks/RunningBoardServices.framework/RunningBoardServices"

/** A handle on a running process. */
@interface RBSProcessHandle : NSObject

@property (nonatomic, readonly) pid_t pid;

@end

/** Selects which processes a state query returns. */
@interface RBSProcessPredicate : NSObject

/** Every process launch services knows about — the set an application is drawn from. */
+ (instancetype)predicateMatchingLaunchServicesProcesses;

@end

/**
 * Selects which fields RunningBoard populates on each returned state. Fields not asked for come back
 * empty, so the endowment namespaces have to be requested explicitly.
 */
@interface RBSProcessStateDescriptor : NSObject

+ (instancetype)descriptor;

/**
 * A bitmask of the field groups to populate. The concrete bit values are not stable across OS versions,
 * so it is set all-bits rather than to a named constant.
 */
@property (nonatomic) unsigned long long values;

/** The endowment namespaces to report on each state. */
@property (nullable, nonatomic, copy) NSArray<NSString *> *endowmentNamespaces;

@end

/** A snapshot of one process's state, as RunningBoard sees it. */
@interface RBSProcessState : NSObject

/**
 * The states of every process matching `predicate`, with the fields `descriptor` asks for.
 *
 * Returns nil with `*error` set when the query is rejected — most often for want of the
 * com.apple.runningboard.process-state entitlement.
 */
+ (nullable NSArray<RBSProcessState *> *)statesForPredicate:(RBSProcessPredicate *)predicate
                                             withDescriptor:(nullable RBSProcessStateDescriptor *)descriptor
                                                      error:(NSError **)error;

/** The process this state describes. */
@property (nullable, nonatomic, readonly) RBSProcessHandle *process;

/** The endowments RunningBoard has granted the process, populated only if the descriptor asked. */
@property (nullable, nonatomic, copy) NSSet<NSString *> *endowmentNamespaces;

@end

NS_ASSUME_NONNULL_END
