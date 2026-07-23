/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBAXRuntimeBridge.h"

#import <FBControlCore/FBAccessibilityTraits.h>
#import <objc/message.h>
#import <objc/runtime.h>

@protocol FBAXRuntimeTranslatorMessaging <NSObject>

- (nullable id)frontmostApplicationWithDisplayId:(uint32_t)displayID bridgeDelegateToken:(NSString *)token;
- (nullable id)objectAtPoint:(CGPoint)point displayId:(uint32_t)displayID bridgeDelegateToken:(NSString *)token;
- (nullable id)macPlatformElementFromTranslation:(id)translation;
- (void)setBridgeTokenDelegate:(id<FBAXRuntimeTranslationDelegate>)delegate;

@end

@protocol FBAXRuntimeTranslationMessaging <NSObject>

- (nullable NSString *)bridgeDelegateToken;
- (void)setBridgeDelegateToken:(nullable NSString *)token;
- (pid_t)pid;

@end

@protocol FBAXRuntimePlatformElementMessaging <NSObject>

- (NSRect)accessibilityFrame;
- (nullable NSString *)accessibilityRole;
- (nullable NSString *)accessibilityLabel;
- (nullable id)accessibilityValue;
- (nullable NSString *)accessibilityIdentifier;
- (nullable NSString *)accessibilityTitle;
- (nullable NSString *)accessibilityHelp;
- (nullable NSString *)accessibilityRoleDescription;
- (nullable NSString *)accessibilitySubrole;
- (nullable NSString *)accessibilityPlaceholderValue;
- (BOOL)isAccessibilityEnabled;
- (BOOL)isAccessibilityRequired;
- (BOOL)isAccessibilityExpanded;
- (BOOL)isAccessibilityHidden;
- (BOOL)isAccessibilityFocused;
- (nullable NSArray *)accessibilityCustomActions;
- (nullable NSArray<NSString *> *)accessibilityActionNames;
- (nullable NSArray *)accessibilityChildren;
- (nullable id)accessibilityAttributeValue:(id)attribute;
- (BOOL)accessibilityPerformPress;
- (void)performScrollDownByPageAction;
- (void)performScrollUpByPageAction;
- (void)performScrollLeftByPageAction;
- (void)performScrollRightByPageAction;
- (void)performScrollToVisible;
- (void)setAccessibilityValue:(nullable id)value;
- (nullable id<FBAXRuntimeTranslationMessaging>)translation;

@end

@protocol FBAXRuntimeDeviceMessaging <NSObject>

- (void)sendAccessibilityRequestAsync:(id)request
                      completionQueue:(dispatch_queue_t)completionQueue
                    completionHandler:(void (^)(id _Nullable response))completionHandler;

@end

@interface FBAXRuntimePlatformElement ()

@property (nonatomic, strong, readonly) NSObject<FBAXRuntimePlatformElementMessaging> *rawElement;

- (instancetype)initWithRawElement:(NSObject<FBAXRuntimePlatformElementMessaging> *)rawElement;

@end

@implementation FBAXRuntimePlatformElement

- (instancetype)initWithRawElement:(NSObject<FBAXRuntimePlatformElementMessaging> *)rawElement
{
  self = [super init];
  if (!self) {
    return nil;
  }
  _rawElement = rawElement;
  return self;
}

- (NSRect)frame
{
  return [self.rawElement accessibilityFrame];
}

- (nullable NSString *)role
{
  return [self.rawElement accessibilityRole];
}

- (nullable NSString *)label
{
  return [self.rawElement accessibilityLabel];
}

- (nullable id)value
{
  return [self.rawElement accessibilityValue];
}

- (nullable NSString *)identifier
{
  return [self.rawElement accessibilityIdentifier];
}

- (nullable NSString *)title
{
  return [self.rawElement accessibilityTitle];
}

- (nullable NSString *)help
{
  return [self.rawElement accessibilityHelp];
}

- (nullable NSString *)roleDescription
{
  return [self.rawElement accessibilityRoleDescription];
}

- (nullable NSString *)subrole
{
  return [self.rawElement accessibilitySubrole];
}

- (nullable NSString *)placeholderValue
{
  return [self.rawElement accessibilityPlaceholderValue];
}

- (BOOL)isEnabled
{
  return [self.rawElement isAccessibilityEnabled];
}

- (BOOL)isRequired
{
  return [self.rawElement isAccessibilityRequired];
}

- (BOOL)isExpanded
{
  return [self.rawElement isAccessibilityExpanded];
}

- (BOOL)isHidden
{
  return [self.rawElement isAccessibilityHidden];
}

- (BOOL)isFocused
{
  return [self.rawElement isAccessibilityFocused];
}

- (NSArray<NSString *> *)customActionNames
{
  NSArray *actions = [self.rawElement accessibilityCustomActions] ?: @[];
  NSArray *names = [actions valueForKey:@"name"];
  return [names isKindOfClass:NSArray.class] ? names : @[];
}

- (NSArray<NSString *> *)actionNames
{
  SEL selector = NSSelectorFromString(@"accessibilityActionNames");
  if (![self.rawElement respondsToSelector:selector]) {
    return @[];
  }
  NSArray<NSString *> *result = ((id (*)(id, SEL))objc_msgSend)(self.rawElement, selector);
  return result ?: @[];
}

- (nullable NSArray<NSString *> *)traits
{
  SEL selector = @selector(accessibilityAttributeValue:);
  if (![self.rawElement respondsToSelector:selector]) {
    return nil;
  }
  id value = ((id (*)(id, SEL, id))objc_msgSend)(self.rawElement, selector, @"AXTraits");
  if (![value isKindOfClass:NSNumber.class]) {
    return nil;
  }
  return AXExtractTraits([(NSNumber *)value unsignedLongLongValue]).allObjects;
}

- (NSArray<FBAXRuntimePlatformElement *> *)children
{
  NSArray *rawChildren = [self.rawElement accessibilityChildren] ?: @[];
  NSMutableArray<FBAXRuntimePlatformElement *> *children = [NSMutableArray arrayWithCapacity:rawChildren.count];
  for (id child in rawChildren) {
    if (![child isKindOfClass:NSObject.class]) {
      continue;
    }
    [children addObject:[[FBAXRuntimePlatformElement alloc] initWithRawElement:child]];
  }
  return [children copy];
}

- (BOOL)performPress
{
  return [self.rawElement accessibilityPerformPress];
}

- (void)scrollDown
{
  [self.rawElement performScrollDownByPageAction];
}

- (void)scrollUp
{
  [self.rawElement performScrollUpByPageAction];
}

- (void)scrollLeft
{
  [self.rawElement performScrollLeftByPageAction];
}

- (void)scrollRight
{
  [self.rawElement performScrollRightByPageAction];
}

- (void)scrollToVisible
{
  [self.rawElement performScrollToVisible];
}

- (void)setValue:(nullable id)value
{
  [self.rawElement setAccessibilityValue:value];
}

- (pid_t)translationPID
{
  return [[self.rawElement translation] pid];
}

- (void)setBridgeDelegateToken:(nullable NSString *)token
{
  [[self.rawElement translation] setBridgeDelegateToken:token];
}

@end

@implementation FBAXRuntimeBridge

+ (nullable NSObject *)sharedTranslator
{
  Class translatorClass = objc_getClass("AXPTranslator");
  SEL selector = NSSelectorFromString(@"sharedInstance");
  if (!translatorClass || ![translatorClass respondsToSelector:selector]) {
    return nil;
  }
  return ((id (*)(id, SEL))objc_msgSend)(translatorClass, selector);
}

+ (void)setBridgeDelegate:(id<FBAXRuntimeTranslationDelegate>)delegate
             onTranslator:(NSObject *)translator
{
  [(id<FBAXRuntimeTranslatorMessaging>)translator setBridgeTokenDelegate:delegate];
}

+ (nullable NSObject *)frontmostApplicationUsingTranslator:(NSObject *)translator
                                                  displayID:(uint32_t)displayID
                                                      token:(NSString *)token
{
  return [(id<FBAXRuntimeTranslatorMessaging>)translator frontmostApplicationWithDisplayId:displayID bridgeDelegateToken:token];
}

+ (nullable NSObject *)objectAtPoint:(CGPoint)point
                    usingTranslator:(NSObject *)translator
                           displayID:(uint32_t)displayID
                               token:(NSString *)token
{
  return [(id<FBAXRuntimeTranslatorMessaging>)translator objectAtPoint:point displayId:displayID bridgeDelegateToken:token];
}

+ (nullable FBAXRuntimePlatformElement *)platformElementFromTranslation:(NSObject *)translation
                                                        usingTranslator:(NSObject *)translator
{
  NSObject<FBAXRuntimePlatformElementMessaging> *rawElement =
    [(id<FBAXRuntimeTranslatorMessaging>)translator macPlatformElementFromTranslation:translation];
  if (!rawElement) {
    return nil;
  }
  return [[FBAXRuntimePlatformElement alloc] initWithRawElement:rawElement];
}

+ (void)setBridgeDelegateToken:(nullable NSString *)token onTranslation:(NSObject *)translation
{
  [(id<FBAXRuntimeTranslationMessaging>)translation setBridgeDelegateToken:token];
}

+ (pid_t)processIdentifierForTranslation:(NSObject *)translation
{
  return [(id<FBAXRuntimeTranslationMessaging>)translation pid];
}

+ (nullable NSObject *)emptyResponse
{
  Class responseClass = objc_getClass("AXPTranslatorResponse");
  SEL selector = NSSelectorFromString(@"emptyResponse");
  if (!responseClass || ![responseClass respondsToSelector:selector]) {
    return nil;
  }
  return ((id (*)(id, SEL))objc_msgSend)(responseClass, selector);
}

+ (void)sendAccessibilityRequest:(NSObject *)request
                        toDevice:(NSObject *)device
                 completionQueue:(dispatch_queue_t)completionQueue
               completionHandler:(FBAXRuntimeResponseHandler)completionHandler
{
  [(id<FBAXRuntimeDeviceMessaging>)device
    sendAccessibilityRequestAsync:request
    completionQueue:completionQueue
    completionHandler:completionHandler];
}

@end
