/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NSObject * _Nullable (^FBAXRuntimeTranslationCallback)(NSObject *request);
typedef void (^FBAXRuntimeResponseHandler)(NSObject * _Nullable response);

/**
 The Objective-C delegate surface used by the accessibility translator.

 The private framework discovers these methods by selector. Keeping the protocol
 in this module gives Swift a type-safe conformance without importing private
 framework declarations.
 */
@protocol FBAXRuntimeTranslationDelegate <NSObject>

- (FBAXRuntimeTranslationCallback)accessibilityTranslationDelegateBridgeCallbackWithToken:(NSString *)token;
- (CGRect)accessibilityTranslationConvertPlatformFrameToSystem:(CGRect)rect withToken:(NSString *)token;
- (nullable id)accessibilityTranslationRootParentWithToken:(NSString *)token;

@end

/**
 Opaque adapter around the private platform element.

 Only Foundation/AppKit value types cross this boundary. The wrapped private
 object is messaged through locally declared protocols in the implementation.
 */
@interface FBAXRuntimePlatformElement : NSObject

- (NSRect)frame;
- (nullable NSString *)role;
- (nullable NSString *)label;
- (nullable id)value;
- (nullable NSString *)identifier;
- (nullable NSString *)title;
- (nullable NSString *)help;
- (nullable NSString *)roleDescription;
- (nullable NSString *)subrole;
- (nullable NSString *)placeholderValue;
- (BOOL)isEnabled;
- (BOOL)isRequired;
- (BOOL)isExpanded;
- (BOOL)isHidden;
- (BOOL)isFocused;
- (NSArray<NSString *> *)customActionNames;
- (NSArray<NSString *> *)actionNames;
- (nullable NSArray<NSString *> *)traits;
- (NSArray<FBAXRuntimePlatformElement *> *)children;
- (BOOL)performPress;
- (void)scrollDown;
- (void)scrollUp;
- (void)scrollLeft;
- (void)scrollRight;
- (void)scrollToVisible;
- (void)setValue:(nullable id)value;
- (pid_t)translationPID;
- (void)setBridgeDelegateToken:(nullable NSString *)token;

@end

/**
 Runtime-only entry points for the accessibility translation private framework.

 Class objects are always resolved with objc_getClass. No private class type is
 present in this public surface, allowing Swift to use the current translation
 behavior without generating direct Objective-C class references.
 */
@interface FBAXRuntimeBridge : NSObject

+ (nullable NSObject *)sharedTranslator;
+ (void)setBridgeDelegate:(id<FBAXRuntimeTranslationDelegate>)delegate
             onTranslator:(NSObject *)translator;
+ (nullable NSObject *)frontmostApplicationUsingTranslator:(NSObject *)translator
                                                  displayID:(uint32_t)displayID
                                                      token:(NSString *)token;
+ (nullable NSObject *)objectAtPoint:(CGPoint)point
                    usingTranslator:(NSObject *)translator
                           displayID:(uint32_t)displayID
                               token:(NSString *)token;
+ (nullable FBAXRuntimePlatformElement *)platformElementFromTranslation:(NSObject *)translation
                                                        usingTranslator:(NSObject *)translator;
+ (void)setBridgeDelegateToken:(nullable NSString *)token onTranslation:(NSObject *)translation;
+ (pid_t)processIdentifierForTranslation:(NSObject *)translation;
+ (nullable NSObject *)emptyResponse;
+ (void)sendAccessibilityRequest:(NSObject *)request
                        toDevice:(NSObject *)device
                 completionQueue:(dispatch_queue_t)completionQueue
               completionHandler:(FBAXRuntimeResponseHandler)completionHandler;

@end

NS_ASSUME_NONNULL_END
