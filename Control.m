#import <Foundation/Foundation.h>
#import <roothide.h>
int main(int argc,char **argv){
    @autoreleasepool {
        NSString *path=jbroot(@"/var/mobile/Library/Preferences/com.codex.audiocoexistserver.plist");
        NSMutableDictionary *p=[[NSDictionary dictionaryWithContentsOfFile:path] mutableCopy] ?: [NSMutableDictionary new];
        NSString *action=argc==2?@(argv[1]):@"status";
        NSString *key=nil;BOOL value=YES;
        if([action isEqual:@"on"])key=@"Enabled";
        else if([action isEqual:@"off"]){key=@"Enabled";value=NO;}
        else if([action isEqual:@"record-on"])key=@"Recording";
        else if([action isEqual:@"record-off"]){key=@"Recording";value=NO;}
        else if([action isEqual:@"dump"]){
            CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                CFSTR("com.codex.audiocoexistserver/dump"),NULL,NULL,true);
        }
        else if(![action isEqual:@"status"]){fprintf(stderr,"usage: audio-coexist on|off|record-on|record-off|status|dump\n");return 2;}
        if(key){
            p[key]=@(value);
            if(![p writeToFile:path atomically:YES]){fprintf(stderr,"cannot write settings (run as root)\n");return 1;}
            [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0644} ofItemAtPath:path error:nil];
            CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                CFSTR("com.codex.audiocoexistserver/settingsChanged"),NULL,NULL,true);
        }
        printf("enabled=%d recording=%d; scope=audiomxd-only\n",!p[@"Enabled"]||[p[@"Enabled"] boolValue],
            !p[@"Recording"]||[p[@"Recording"] boolValue]);
    }
    return 0;
}
