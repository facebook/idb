/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 New crash log format is just concated json files that *not* follows json spec. This is not array of json objects
 delimited with comma, that is just several json files that glued together. We need to parse this to handle correctly
 */
@interface FBConcatedJsonParser : NSObject

+ (nullable NSDictionary<NSString *, id> *)parseConcatenatedJSONFromString:(NSString *)str error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
