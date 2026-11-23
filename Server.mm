#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#ifndef ASC_HOST_TEST
#import <substrate.h>
#import <roothide.h>
#include <mach-o/dyld.h>
#endif
#include <atomic>
#include <stdio.h>
#include <unistd.h>
#include "Policy.h"

static std::atomic_bool enabled(true), recordingEnabled(true), initialized;
static std::atomic_flag preparing = ATOMIC_FLAG_INIT;
static std::atomic_uint logBudget;
static Class coreClass;
static SEL categorySEL, modeSEL, displaySEL, phoneSEL, assistantSEL, hardwareSEL,
    carSEL, shareCallSEL, routeSEL;
typedef bool (*BoolGetter)(id,SEL);
typedef unsigned int (*UIntGetter)(id,SEL);
static BoolGetter originalMix, originalAllowRecording;
static UIntGetter originalInterruption;

static id objectValue(id receiver, SEL sel) {
    return ((id (*)(id,SEL))objc_msgSend)(receiver,sel);
}
static bool boolValue(id receiver, SEL sel) {
    return ((bool (*)(id,SEL))objc_msgSend)(receiver,sel);
}
static bool eligible(id session) {
    if (!enabled.load(std::memory_order_relaxed) || ![session isKindOfClass:coreClass] || !originalInterruption) return false;
    unsigned int style=originalInterruption(session,sel_registerName("interruptionStyle"));
    if(style!=0 && style!=0x8 && style!=0x10)return false;
    NSString *display=objectValue(session,displaySEL);
    if (![display isKindOfClass:NSString.class] || !display.length) return false;
    // The same session policy applies to every attributed client. Protection
    // comes from session purpose/category, never an application allowlist.
    bool client = true;
    bool protect=boolValue(session,phoneSEL) || boolValue(session,assistantSEL) ||
        boolValue(session,hardwareSEL) || boolValue(session,carSEL) || boolValue(session,shareCallSEL);
    NSString *category=objectValue(session,categorySEL);
    NSString *mode=objectValue(session,modeSEL);
    ASCCategory kind=ASCUnsupported;
    if ([category isEqual:@"MediaPlayback"] || [category isEqual:@"Audio/Video"] ||
        [category isEqual:@"AmbientSound"] || [category isEqual:@"SoloAmbientSound"])
        kind=ASCPlayback;
    else if ([category isEqual:@"Record"] || [category hasPrefix:@"PlayAndRecord"])
        kind=ASCRecord;
    int route=((int (*)(id,SEL))objc_msgSend)(session,routeSEL);
    // Long-form audio/video are media-sharing policies, not evidence of an
    // exclusive physical route. Do not carry the public setCategory option
    // restrictions into this server-side decision. Keep independent routes out.
    bool mediaRoute=route==0 || route==1 || route==3;
    return ASCEligible(enabled.load(std::memory_order_relaxed),
        recordingEnabled.load(std::memory_order_relaxed),client,protect,mediaRoute,
        [mode isEqual:@"Default"], [mode isEqual:@"MoviePlayback"] || [mode isEqual:@"SpokenAudio"],kind);
}
static void logApplied(id session, const char *operation, unsigned int oldValue, unsigned int newValue) {
#ifndef ASC_HOST_TEST
    if (oldValue==newValue || logBudget.fetch_add(1)>=16) return;
    @autoreleasepool {
        NSString *line=[NSString stringWithFormat:@"APPLIED pid=%d app=%@ category=%@ mode=%@ %s=0x%x->0x%x\n",
            getpid(),objectValue(session,displaySEL),objectValue(session,categorySEL),
            objectValue(session,modeSEL),operation,oldValue,newValue];
        FILE *file=fopen(jbroot("/tmp/AudioCoexistServer.runtime"),"a");
        if(file){ fputs(line.UTF8String,file); fclose(file); }
    }
#else
    (void)session;(void)operation;(void)oldValue;(void)newValue;
#endif
}
// Only intercept reads. The daemon's original stored values stay intact, so
// entering a protected mode immediately exposes the original interruption rules.
static bool mixGetter(id session,SEL sel) {
    bool original=originalMix(session,sel);
    if (!eligible(session)) return original;
    logApplied(session,"mix",original,true);
    return true;
}
static unsigned int interruptionGetter(id session,SEL sel) {
    unsigned int original=originalInterruption(session,sel);
    if (!eligible(session)) return original;
    // Observed native iOS17 mapping: 0x8 exclusive, 0x10 mix with others.
    // Leave other priority/ducking combinations alone until their ABI is proven.
    if (original!=0 && original!=0x8 && original!=0x10) return original;
    logApplied(session,"interruption",original,0x10);
    return 0x10;
}
static bool allowRecordingGetter(id session,SEL sel) {
    bool original=originalAllowRecording(session,sel);
    if (!eligible(session)) return original;
    NSString *category=objectValue(session,categorySEL);
    if(![category isEqual:@"Record"] && ![category hasPrefix:@"PlayAndRecord"])return original;
    logApplied(session,"allowRecording",original,true);
    return true;
}
static bool compatible(Class c,SEL sel,const char *types) {
    Method m=class_getInstanceMethod(c,sel);
    if(!m || method_getNumberOfArguments(m)!=2) return false;
    char *type=method_copyReturnType(m);
    bool result=type && strchr(types,type[0]);free(type);return result;
}
static bool prepareSelectors(Class c) {
    categorySEL=sel_registerName("audioCategory");modeSEL=sel_registerName("audioMode");
    displaySEL=sel_registerName("displayID");phoneSEL=sel_registerName("hasPhoneCallBehavior");
    assistantSEL=sel_registerName("isTheAssistant");hardwareSEL=sel_registerName("isHardwareSafetySession");
    carSEL=sel_registerName("isCarSession");shareCallSEL=sel_registerName("isSharePlayCallSession");
    routeSEL=sel_registerName("routeSharingPolicy");
    return compatible(c,categorySEL,"@") && compatible(c,modeSEL,"@") && compatible(c,displaySEL,"@") &&
        compatible(c,phoneSEL,"Bc") && compatible(c,assistantSEL,"Bc") && compatible(c,hardwareSEL,"Bc") &&
        compatible(c,carSEL,"Bc") && compatible(c,shareCallSEL,"Bc") && compatible(c,routeSEL,"i") &&
        compatible(c,sel_registerName("mixesWithEveryone"),"Bc") &&
        compatible(c,sel_registerName("interruptionStyle"),"I") &&
        compatible(c,sel_registerName("allowMixableAudioWhileRecording"),"Bc");
}
#ifndef ASC_HOST_TEST
@protocol ASCDiagnosticManager
+ (id)sharedInstance;
- (NSArray *)copyMXCoreSessionList;
@end
static void dumpSessions(void) {
    @autoreleasepool {
        Class<ASCDiagnosticManager> c=(Class<ASCDiagnosticManager>)objc_getClass("MXSessionManager");
        id<ASCDiagnosticManager> manager=[c sharedInstance];
        NSArray *list=[manager copyMXCoreSessionList];
        NSMutableString *text=[NSMutableString stringWithFormat:@"pid=%d time=%.0f sessions=%lu\n",
            getpid(),NSDate.date.timeIntervalSince1970,(unsigned long)list.count];
        for(id s in list){
            if(![s isKindOfClass:coreClass])continue;
            [text appendFormat:@"app=%@ category=%@ mode=%@ rawStyle=0x%x rawMix=%d rawRecordMix=%d recording=%d playing=%d output=%d active=%d input=%d phone=%d assistant=%d safety=%d car=%d shareCall=%d route=%d eligible=%d\n",
                objectValue(s,displaySEL),objectValue(s,categorySEL),objectValue(s,modeSEL),
                originalInterruption(s,sel_registerName("interruptionStyle")),
                originalMix(s,sel_registerName("mixesWithEveryone")),
                originalAllowRecording(s,sel_registerName("allowMixableAudioWhileRecording")),
                boolValue(s,sel_registerName("isRecording")),boolValue(s,sel_registerName("isPlaying")),
                boolValue(s,sel_registerName("isPlayingOutput")),boolValue(s,sel_registerName("isActive")),
                boolValue(s,sel_registerName("hasInput")),boolValue(s,phoneSEL),boolValue(s,assistantSEL),
                boolValue(s,hardwareSEL),boolValue(s,carSEL),boolValue(s,shareCallSEL),
                ((int(*)(id,SEL))objc_msgSend)(s,routeSEL),eligible(s)];
        }
        [text writeToFile:jbroot(@"/tmp/AudioCoexistServer.sessions") atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
}
static void requestDump(CFNotificationCenterRef,void*,CFStringRef,const void*,CFDictionaryRef){dumpSessions();}
static void loadSettings(void) {
    NSDictionary *p=[NSDictionary dictionaryWithContentsOfFile:
        jbroot(@"/var/mobile/Library/Preferences/com.codex.audiocoexistserver.plist")];
    enabled.store(!p[@"Enabled"] || [p[@"Enabled"] boolValue]);
    recordingEnabled.store(!p[@"Recording"] || [p[@"Recording"] boolValue]);
}
static void settingsChanged(CFNotificationCenterRef,void*,CFStringRef,const void*,CFDictionaryRef){loadSettings();}
static void installServerHooks(void) {
    @autoreleasepool {
        Class c=objc_getClass("MXCoreSession");
        if(!c || initialized.load() || preparing.test_and_set()) return;
        if(!prepareSelectors(c)){preparing.clear();return;}
        initialized.store(true);
        coreClass=c;loadSettings();
        MSHookMessageEx(c,sel_registerName("mixesWithEveryone"),(IMP)mixGetter,(IMP*)&originalMix);
        MSHookMessageEx(c,sel_registerName("interruptionStyle"),(IMP)interruptionGetter,(IMP*)&originalInterruption);
        MSHookMessageEx(c,sel_registerName("allowMixableAudioWhileRecording"),(IMP)allowRecordingGetter,(IMP*)&originalAllowRecording);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),nullptr,
            settingsChanged,CFSTR("com.codex.audiocoexistserver/settingsChanged"),nullptr,
            CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),nullptr,
            requestDump,CFSTR("com.codex.audiocoexistserver/dump"),nullptr,
            CFNotificationSuspensionBehaviorDeliverImmediately);
        FILE *file=fopen(jbroot("/tmp/AudioCoexistServer.runtime"),"a");
        if(file){fprintf(file,"READY v0.2.4 process=audiomxd pid=%d enabled=%d recording=%d\n",
            getpid(),enabled.load(),recordingEnabled.load());fclose(file);}
    }
}
static void imageAdded(const struct mach_header*,intptr_t){
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{installServerHooks();});
}
__attribute__((constructor)) static void initializeServer(void){
    if(strcmp(getprogname(),"audiomxd")!=0)return;
    _dyld_register_func_for_add_image(imageAdded);installServerHooks();
}
#endif
