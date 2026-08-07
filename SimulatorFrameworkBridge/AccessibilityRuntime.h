/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

// The results the accessibility runtime can produce, as tagged unions.
//
// Every interaction with the private AX API has more than two outcomes, and the interesting ones are not
// failures: a hit-test on empty space succeeded and found nothing, and a read of a process with no
// accessibility server is neither a hit nor a reader bug. Returning `nil` plus an out-parameter forces
// each caller to re-derive which of those happened from whatever it was handed, and the one that matters
// most — an unreadable application, which the host maps onto a typed error — was previously recovered by
// re-reading an NSError userInfo key at every call site.
//
// A result type per interaction states the cases once. The constructors are the enforcement: nothing
// stops a caller reading `.attributes` on a failure, but nothing lets it *build* that combination, and a
// `switch` over the status warns when a case is left unhandled.

#import <Foundation/Foundation.h>

#import "XCTAutomationSupportPrivate.h"

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
 * escapes the code that asked for it, so no caller can outlive or over-release it.
 */
@interface FBAXHitTestOutcome : NSObject

@property (nonatomic, readonly) FBAXHitTestStatus status;
/** The element at the point. Non-nil iff `Hit`. */
@property (nullable, nonatomic, readonly) XCAccessibilityElement *element;
/** The process owning `element`, always positive when `Hit`. */
@property (nonatomic, readonly) pid_t owningProcessIdentifier;
/** A diagnostic for the caller. Non-nil iff `Failed`. */
@property (nullable, nonatomic, readonly, copy) NSString *failureReason;

+ (instancetype)hit:(XCAccessibilityElement *)element owningProcessIdentifier:(pid_t)pid;
+ (instancetype)empty;
+ (instancetype)applicationUnavailable;
+ (instancetype)failed:(NSString *)failureReason;

@end

NS_ASSUME_NONNULL_END
