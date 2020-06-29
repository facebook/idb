/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

@class AXPTranslationObject, NSArray;

@interface AXPTranslatorResponse : NSObject <NSCopying, NSSecureCoding>
{
    id <NSObject, NSCopying, NSSecureCoding> _resultData;
    unsigned long long _attribute;
    unsigned long long _notification;
    AXPTranslationObject *_associatedNotificationObject;
    unsigned long long _error;
}

+ (id)allowedDecodableClasses;
+ (id)emptyResponse;
+ (BOOL)supportsSecureCoding;
@property(nonatomic) unsigned long long error; // @synthesize error=_error;
@property(retain, nonatomic) AXPTranslationObject *associatedNotificationObject; // @synthesize associatedNotificationObject=_associatedNotificationObject;
@property(nonatomic) unsigned long long notification; // @synthesize notification=_notification;
@property(nonatomic) unsigned long long attribute; // @synthesize attribute=_attribute;
@property(retain, nonatomic) id <NSObject, NSCopying, NSSecureCoding> resultData; // @synthesize resultData=_resultData;
- (id)description;
@property(readonly, nonatomic) BOOL boolResponse;
@property(readonly, nonatomic) NSArray *translationsResponse;
@property(readonly, nonatomic) AXPTranslationObject *translationResponse;
- (id)initWithCoder:(id)arg1;
- (void)encodeWithCoder:(id)arg1;
- (id)copyWithZone:(struct _NSZone *)arg1;

@end

