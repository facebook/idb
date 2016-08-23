
#import <Foundation/Foundation.h>

@interface ScriptRunner : NSObject
+ (NSString *)runCommand:(NSString*)command args:(NSArray *)args;
@end
