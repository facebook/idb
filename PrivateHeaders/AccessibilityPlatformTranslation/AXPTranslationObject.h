/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

@class NSData, NSString;

@interface AXPTranslationObject : NSObject <NSCopying, NSSecureCoding>
{
    BOOL _isApplicationElement;
    BOOL _didPopuldateAppInfo;
    int _pid;
    unsigned long long _objectID;
    NSString *_bridgeDelegateToken;
    NSData *_rawElementData;
    CDUnknownBlockType _remoteDescriptionBlock;
    NSString *_remoteDebugDescription;
}

+ (BOOL)supportsSecureCoding;
+ (id)allowedDecodableClasses;
+ (void)initialize;
@property(copy, nonatomic) NSString *remoteDebugDescription; // @synthesize remoteDebugDescription=_remoteDebugDescription;
@property(copy, nonatomic) CDUnknownBlockType remoteDescriptionBlock; // @synthesize remoteDescriptionBlock=_remoteDescriptionBlock;
@property(nonatomic) BOOL didPopuldateAppInfo; // @synthesize didPopuldateAppInfo=_didPopuldateAppInfo;
@property(copy, nonatomic) NSData *rawElementData; // @synthesize rawElementData=_rawElementData;
@property(copy, nonatomic) NSString *bridgeDelegateToken; // @synthesize bridgeDelegateToken=_bridgeDelegateToken;
@property(nonatomic) BOOL isApplicationElement; // @synthesize isApplicationElement=_isApplicationElement;
@property(nonatomic) int pid; // @synthesize pid=_pid;
@property(nonatomic) unsigned long long objectID; // @synthesize objectID=_objectID;
- (id)description;
- (id)initWithCoder:(id)arg1;
- (void)encodeWithCoder:(id)arg1;
- (id)copyWithZone:(struct _NSZone *)arg1;
- (unsigned long long)hash;
- (BOOL)isEqual:(id)arg1;
- (id)init;

@end

