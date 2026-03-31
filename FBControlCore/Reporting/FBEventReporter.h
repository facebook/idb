/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

@class FBEventReporterSubject;

/**
 An Event Reporter Protocol to interface to event reporting.
 */
@protocol FBEventReporter <NSObject>

/**
 Reports a Subject

 @param subject the subject to report.
 */
- (void)report:(nonnull FBEventReporterSubject *)subject;

/**
 Add metadata to attach to each report.

 @param metadata Metadata to append
 */
- (void)addMetadata:(nonnull NSDictionary<NSString *, NSString *> *)metadata;

/**
 Gets the total metadata.
 */
@property (nonnull, nonatomic, readonly, strong) NSDictionary<NSString *, NSString *> *metadata;

@end
