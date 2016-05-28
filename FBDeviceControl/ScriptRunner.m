//
//  ScriptLauncher.m
//  XCUITestManagerDLink
//
//  Created by Chris Fuentes on 2/21/16.
//  Copyright © 2016 calabash. All rights reserved.
//

#import "ScriptRunner.h"

@implementation ScriptRunner
/*
 http://stackoverflow.com/questions/412562/execute-a-terminal-command-from-a-cocoa-app/696942#696942
 */
+ (NSString *)runCommand:(NSString*)command args:(NSArray *)args; {
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:command];
    [task setArguments: args];
    
    NSPipe *pipe = [NSPipe pipe];
    [task setStandardOutput: pipe];
    
    NSFileHandle *file = [pipe fileHandleForReading];
    
    [task launch];
    
    NSData *data = [file readDataToEndOfFile];
    
    NSString *string = [[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding];
    NSLog(@"%@ %@ => %@", command, args, string);
    return string;
}
@end
