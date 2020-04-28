/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */


@class NSData, NSDate, NSDictionary, NSString, _XCTAttachmentImplementation;

@interface XCTAttachment : NSObject <NSSecureCoding>
{
    id _internalImplementation;
}

+ (id)attachmentWithXCTImage:(id)arg1 quality:(long long)arg2;
+ (id)attachmentWithUniformTypeIdentifier:(id)arg1 name:(id)arg2 payload:(id)arg3 userInfo:(id)arg4;
+ (_Bool)supportsSecureCoding;
+ (void)setUserAttachmentLifetime:(long long)arg1;
+ (long long)userAttachmentLifetime;
+ (void)setSystemAttachmentLifetime:(long long)arg1;
+ (long long)systemAttachmentLifetime;
+ (id)attachmentWithScreenshot:(id)arg1 quality:(long long)arg2;
+ (id)attachmentWithScreenshot:(id)arg1;
+ (id)attachmentWithImage:(id)arg1 quality:(long long)arg2;
+ (id)attachmentWithImage:(id)arg1;
+ (id)attachmentWithContentsOfFileAtURL:(id)arg1;
+ (id)attachmentWithContentsOfFileAtURL:(id)arg1 uniformTypeIdentifier:(id)arg2;
+ (id)_attachmentWithContentsOfFileAtURL:(id)arg1 uniformTypeIdentifier:(id)arg2;
+ (id)attachmentWithPlistObject:(id)arg1;
+ (id)attachmentWithArchivableObject:(id)arg1;
+ (id)attachmentWithArchivableObject:(id)arg1 uniformTypeIdentifier:(id)arg2;
+ (id)_attachmentWithArchivableObject:(id)arg1 uniformTypeIdentifier:(id)arg2;
+ (id)attachmentWithString:(id)arg1;
+ (id)attachmentWithData:(id)arg1;
+ (id)attachmentWithData:(id)arg1 uniformTypeIdentifier:(id)arg2;
+ (id)_attachmentWithData:(id)arg1 uniformTypeIdentifier:(id)arg2;
@property(readonly) _XCTAttachmentImplementation *internalImplementation; // @synthesize internalImplementation=_internalImplementation;
- (id)debugQuickLookObject;
- (void)makeSystem;
- (id)debugDescription;
- (void)encodeWithCoder:(id)arg1;
- (id)initWithCoder:(id)arg1;
- (void)prepareForEncoding;
@property(readonly) _Bool hasPayload;
@property(copy) NSString *fileNameOverride;
@property(readonly, copy) NSData *payload;
@property(copy) NSDictionary *userInfo;
@property(copy) NSDate *timestamp;
@property(copy) NSString *name;
@property long long lifetime;
@property long long internalLifetime;
@property(readonly, copy) NSString *uniformTypeIdentifier;
- (id)initWithUniformTypeIdentifier:(id)arg1 name:(id)arg2 payload:(id)arg3 userInfo:(id)arg4;

@end
