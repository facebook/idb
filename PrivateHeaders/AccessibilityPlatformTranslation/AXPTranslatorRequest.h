/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

@class AXPTranslationObject, NSDictionary;

@interface AXPTranslatorRequest : NSObject <NSCopying, NSSecureCoding>
{
    AXPTranslationObject *_translation;
    unsigned long long _requestType;
    unsigned long long _attributeType;
    unsigned long long _actionType;
    NSDictionary *_parameters;
    unsigned long long _clientType;
}

+ (id)allowedDecodableClasses;
+ (id)requestWithTranslation:(id)arg1;
+ (BOOL)supportsSecureCoding;
@property(nonatomic) unsigned long long clientType; // @synthesize clientType=_clientType;
@property(retain, nonatomic) NSDictionary *parameters; // @synthesize parameters=_parameters;
@property(nonatomic) unsigned long long actionType; // @synthesize actionType=_actionType;
@property(nonatomic) unsigned long long attributeType; // @synthesize attributeType=_attributeType;
@property(nonatomic) unsigned long long requestType; // @synthesize requestType=_requestType;
@property(retain, nonatomic) AXPTranslationObject *translation; // @synthesize translation=_translation;
- (id)description;
- (id)initWithCoder:(id)arg1;
- (void)encodeWithCoder:(id)arg1;
- (id)copyWithZone:(struct _NSZone *)arg1;

@end

