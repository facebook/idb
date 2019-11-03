/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Model Representing the Override of Language & Keyboard Settings.
 */
@interface FBLocalizationOverride : NSObject <NSCopying, FBJSONSerializable, FBJSONDeserializable>

/**
 A Language Override with the given locale.

 @param locale the locale to override with.
 @return a new Language Override instance.
 */
+ (instancetype)withLocale:(NSLocale *)locale;

/**
 The Overrides for an NSUserDefaults dictionary.
 */
@property (nonatomic, copy, readonly) NSDictionary<NSString *, id> *defaultsDictionary;

/**
 Defaults Overrides passable as Arguments to an Application
 */
@property (nonatomic, copy, readonly) NSArray<NSString *> *arguments;

@end

NS_ASSUME_NONNULL_END
