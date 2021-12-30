/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*! Checks whether bitmask includes all of given traits */
BOOL AXBitmaskContainsAllTraits(uint64_t bitmask, uint64_t traits);

/*! Checks whether bitmask includes any of given traits */
BOOL AXBitmaskContainsAnyOfTraits(uint64_t bitmask, uint64_t traits);

/*! Returns mapping from bitmask values to names as strings */
NSDictionary<NSNumber *, NSString *> *AXTraitToNameMap(void);

/*! Returns extracted set of trait names from given traitBitmask */
NSSet<NSString *> *AXExtractTraits(uint64_t traitBitmask);

/*! Returns element type extracted from bitmask */
NSString *AXExtractTypeFromTraits(uint64_t traits);

NS_ASSUME_NONNULL_END
