// Copyright 2004-present Facebook. All Rights Reserved.

#import "FBLineReader.h"

@interface FBLineReader ()

@property (nonatomic, strong) void (^consumer)(NSString *);
@property (nonatomic, strong) NSMutableData *buffer;

@end

@implementation FBLineReader

+ (instancetype)lineReaderWithConsumer:(void (^)(NSString *))consumer
{
  FBLineReader *reader = [self new];
  reader.consumer = consumer;
  reader.buffer = [NSMutableData data];
  return reader;
}

- (void)consumeData:(NSData *)data
{
  [self.buffer appendData:data];
  while (self.buffer.length != 0) {
    NSRange newlineRange = [self.buffer rangeOfData:[NSData dataWithBytes:"\n" length:1]
                                            options:0
                                              range:NSMakeRange(0, self.buffer.length)];
    if (newlineRange.length == 0) {
      break;
    }
    NSData *lineData = [self.buffer subdataWithRange:NSMakeRange(0, newlineRange.location)];
    [self.buffer replaceBytesInRange:NSMakeRange(0, newlineRange.location + 1) withBytes:"" length:0];
    NSString *line = [[NSString alloc] initWithData:lineData encoding:NSUTF8StringEncoding];
    self.consumer(line);
  }
}

- (void)consumeEndOfFile
{
  if (self.buffer.length != 0) {
    NSString *line = [[NSString alloc] initWithData:self.buffer encoding:NSUTF8StringEncoding];
    self.consumer(line);
    self.buffer = [NSMutableData data];
  }
}

@end
