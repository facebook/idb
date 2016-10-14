// Copyright 2004-present Facebook. All Rights Reserved.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 A Reader of Text Data, calling the callback when a full line is available.
 */
@interface FBLineReader : NSObject

/**
 Creates a Consumer

 @param consumer the block to call when a line has been consumed.
 @return a new Line Reader.
 */
+ (instancetype)lineReaderWithConsumer:(void (^)(NSString *))consumer;

/**
 Consumes the provided text data.

 @param data the data to consume.
 */
- (void)consumeData:(NSData *)data;

/**
 Consumes an EOF.
 */
- (void)consumeEndOfFile;

@end

NS_ASSUME_NONNULL_END
