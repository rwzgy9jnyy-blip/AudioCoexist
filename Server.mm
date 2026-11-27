#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>
#import <roothide.h>
#include <mach-o/dyld.h>
#include <atomic>
#include <mutex>
#include <stdio.h>
#include <unistd.h>
#include "Policy.h"
#include "Settings.h"
#include "FileIO.h"

static std::atomic_bool initialized(false), dumpPending(false), settingsPending(false), installPending(false);
static std::atomic_uint settingsFlags(ASCDefaults);
static std::atomic_flag preparing = ATOMIC_FLAG_INIT;
static std::atomic_uint logBudget;
static Class coreClass;
static SEL categorySEL, modeSEL, displaySEL, interruptionSEL, candidateSEL, clientSEL, playingSEL, phoneSEL, assistantSEL, hardwareSEL,
    carSEL, shareCallSEL, routeSEL;
typedef bool (*BoolGetter)(id,SEL);
typedef unsigned int (*UIntGetter)(id,SEL);
static std::atomic<BoolGetter> originalMix(nullptr), originalAllowRecording(nullptr);
static std::atomic<UIntGetter> originalInterruption(nullptr);
typedef void (*BoolSetter)(id,SEL,bool);
static std::atomic<BoolSetter> originalPlaying(nullptr);
// A lease never retains sessions. It expires after the client's last leased
// playback session is released.
// Generation tags prevent an older session's cleanup from clearing a successor.
static std::atomic_uint64_t primaryStamp(0);
static std::atomic_uint primaryGeneration(0);
static std::mutex primaryWriteLock;
static char primaryLeaseKey;
@interface ASCPrimaryLease : NSObject
@property(nonatomic) uint64_t stamp;
@end
@implementation ASCPrimaryLease
- (void)dealloc {
    uint64_t expected=_stamp;
    primaryStamp.compare_exchange_strong(expected,0,std::memory_order_acq_rel);
}
@end
static __weak ASCPrimaryLease *primaryGroup;
static int clientPID(id session) {
    id value=((id(*)(id,SEL))objc_msgSend)(session,clientSEL);
    return [value isKindOfClass:NSNumber.class] ? [value intValue] : 0;
}

static id objectValue(id receiver, SEL sel) {
    return ((id (*)(id,SEL))objc_msgSend)(receiver,sel);
}
static bool boolValue(id receiver, SEL sel) {
    return ((bool (*)(id,SEL))objc_msgSend)(receiver,sel);
}
static bool eligible(id session, const unsigned int *knownStyle=nullptr, ASCCategory *categoryOut=nullptr) {
    // Publish selectors/class/original implementations as one ready state.
    if (!initialized.load(std::memory_order_acquire)) return false;
    unsigned flags=settingsFlags.load(std::memory_order_relaxed);
    if (!(flags & ASCEnabled) || ![session isKindOfClass:coreClass]) return false;
    UIntGetter interruption=originalInterruption.load(std::memory_order_acquire);
    if (!interruption) return false;
    unsigned int style=knownStyle ? *knownStyle : interruption(session,interruptionSEL);
    if(style!=0 && style!=0x8 && style!=0x10)return false;
    NSString *display=objectValue(session,displaySEL);
    if (![display isKindOfClass:NSString.class] || !display.length) return false;
    // The same session policy applies to every attributed client. Protection
    // comes from session purpose/category, never an application allowlist.
    bool protect=boolValue(session,phoneSEL) || boolValue(session,assistantSEL) ||
        boolValue(session,hardwareSEL) || boolValue(session,carSEL) || boolValue(session,shareCallSEL);
    if(protect)return false;
    NSString *category=objectValue(session,categorySEL);
    NSString *mode=objectValue(session,modeSEL);
    if (![category isKindOfClass:NSString.class] || ![mode isKindOfClass:NSString.class]) return false;
    ASCCategory kind=ASCUnsupported;
    if ([category isEqual:@"MediaPlayback"] || [category isEqual:@"Audio/Video"] ||
        [category isEqual:@"AmbientSound"] || [category isEqual:@"SoloAmbientSound"])
        kind=ASCPlayback;
    else if ([category isEqual:@"Record"] || [category hasPrefix:@"PlayAndRecord"])
        kind=ASCRecord;
    if(categoryOut)*categoryOut=kind;
    int route=((int (*)(id,SEL))objc_msgSend)(session,routeSEL);
    // Long-form audio/video are media-sharing policies, not evidence of an
    // exclusive physical route. Do not carry the public setCategory option
    // restrictions into this server-side decision. Keep independent routes out.
    bool mediaRoute=route==0 || route==1 || route==3;
    return ASCEligible(true,flags & ASCRecording,true,protect,mediaRoute,
        [mode isEqual:@"Default"], [mode isEqual:@"MoviePlayback"] || [mode isEqual:@"SpokenAudio"],kind);
}
static bool mixPolicy(id session,const unsigned int *style=nullptr,ASCCategory *out=nullptr) {
    ASCCategory kind=ASCUnsupported;
    if(!eligible(session,style,&kind))return false;
    if(out)*out=kind;
    if(kind!=ASCPlayback)return true;
    unsigned owner=(unsigned)primaryStamp.load(std::memory_order_acquire);
    // Before a primary starts, preserve native playback metadata. Afterwards
    // only later clients mix in; the primary keeps native media controls.
    int pid=clientPID(session);return owner && pid>0 && (unsigned)pid!=owner;
}
static void claimPrimary(id session) {
    ASCCategory kind=ASCUnsupported;
    if(!eligible(session,nullptr,&kind) || kind!=ASCPlayback || !boolValue(session,candidateSEL))return;
    NSString *category=objectValue(session,categorySEL);
    if(![category isEqual:@"MediaPlayback"] && ![category isEqual:@"Audio/Video"])return;
    if(originalMix.load()(session,sel_registerName("mixesWithEveryone")) ||
       originalInterruption.load()(session,interruptionSEL)!=0x8)return;
    int pid=clientPID(session);if(pid<=0)return;
    std::lock_guard<std::mutex> lock(primaryWriteLock);
    ASCPrimaryLease *lease=primaryGroup;
    uint64_t current=primaryStamp.load(std::memory_order_acquire);
    // A zeroed weak group can precede its dealloc callback's atomic clear.
    // Do not reject a new primary during that teardown window.
    if(current && (!lease || lease.stamp!=current)){
        primaryStamp.compare_exchange_strong(current,0,std::memory_order_acq_rel);
        current=primaryStamp.load(std::memory_order_acquire);
    }
    if(current && (unsigned)current!=(unsigned)pid)return;
    if(!current || !lease || lease.stamp!=current){
        uint64_t generation=(uint64_t)primaryGeneration.fetch_add(1,std::memory_order_relaxed)+1;
        lease=[ASCPrimaryLease new];lease.stamp=(generation<<32)|(unsigned)pid;
        primaryStamp.store(lease.stamp,std::memory_order_release);primaryGroup=lease;
    }
    // Share the lease across this client's playback sessions. Ending a short
    // auxiliary session must not release a still-live primary playback session.
    if(objc_getAssociatedObject(session,&primaryLeaseKey)!=lease)
        objc_setAssociatedObject(session,&primaryLeaseKey,lease,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static void playingSetter(id session,SEL sel,bool playing) {
    // Claim when the first real output starts, before native selection observes
    // the new playing state. Pausing does not release the lease: Bluetooth play must still resume the primary.
    if(playing && initialized.load(std::memory_order_acquire))claimPrimary(session);
    BoolSetter setter=originalPlaying.load(std::memory_order_acquire);
    if(setter)setter(session,sel,playing);
}
static dispatch_queue_t diagnosticQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once,^{queue=dispatch_queue_create("com.codex.audiocoexistserver.diagnostics",DISPATCH_QUEUE_SERIAL);});
    return queue;
}
static void appendRuntime(NSString *line) {
    int fd=ASCOpenRegular(jbroot(@"/tmp/AudioCoexistServer.runtime"),O_WRONLY|O_CREAT|O_APPEND,0600);
    if(fd>=0){ASCWriteAll(fd,[line dataUsingEncoding:NSUTF8StringEncoding]);close(fd);}
}
static void writeRuntimeAsync(NSString *line) {
    dispatch_async(diagnosticQueue(),^{@autoreleasepool{appendRuntime(line);}});
}
static bool takeLogToken(void) {
    unsigned used=logBudget.load(std::memory_order_relaxed);
    while(used<16){
        if(logBudget.compare_exchange_weak(used,used+1,std::memory_order_relaxed))return true;
    }
    return false;
}
static void logApplied(id session, const char *operation, unsigned int oldValue, unsigned int newValue) {
    if (oldValue==newValue || !takeLogToken()) return;
    @autoreleasepool {
        NSString *line=[NSString stringWithFormat:@"APPLIED pid=%d app=%@ category=%@ mode=%@ %s=0x%x->0x%x\n",
            getpid(),objectValue(session,displaySEL),objectValue(session,categorySEL),
            objectValue(session,modeSEL),operation,oldValue,newValue];
        // Never perform filesystem I/O on the audio policy caller's thread.
        writeRuntimeAsync(line);
    }
}
// Only intercept reads. The daemon's original stored values stay intact, so
// entering a protected mode immediately exposes the original interruption rules.
static bool mixGetter(id session,SEL sel) {
    BoolGetter getter=originalMix.load(std::memory_order_acquire);
    bool original=getter ? getter(session,sel) : false;
    // Native permission already satisfies this getter. Do not re-query the
    // entire session on this frequently used path or cache mutable eligibility.
    if(original)return original;
    if (!mixPolicy(session)) return original;
    logApplied(session,"mix",original,true);
    return true;
}
static unsigned int interruptionGetter(id session,SEL sel) {
    UIntGetter getter=originalInterruption.load(std::memory_order_acquire);
    unsigned int original=getter ? getter(session,sel) : 0;
    // Observed native iOS17 mapping: 0x8 exclusive, 0x10 mix with others.
    // Leave other priority/ducking combinations alone until their ABI is proven.
    if (original!=0 && original!=0x8) return original;
    if (!mixPolicy(session,&original)) return original;
    logApplied(session,"interruption",original,0x10);
    return 0x10;
}
static bool allowRecordingGetter(id session,SEL sel) {
    BoolGetter getter=originalAllowRecording.load(std::memory_order_acquire);
    bool original=getter ? getter(session,sel) : false;
    if(original)return original;
    ASCCategory category=ASCUnsupported;
    if (!eligible(session,nullptr,&category) || category!=ASCRecord) return original;
    logApplied(session,"allowRecording",original,true);
    return true;
}
static bool compatible(Class c,SEL sel,const char *types,const char *argument=nullptr) {
    Method m=class_getInstanceMethod(c,sel);
    if(!m || method_getNumberOfArguments(m)!=(argument?3u:2u)) return false;
    char *type=method_copyReturnType(m);
    bool result=type && type[0] && strchr(types,type[0]);free(type);
    if(argument){type=method_copyArgumentType(m,2);result=result && type && type[0] && strchr(argument,type[0]);free(type);}
    return result;
}
static bool prepareSelectors(Class c) {
    categorySEL=sel_registerName("audioCategory");modeSEL=sel_registerName("audioMode");
    interruptionSEL=sel_registerName("interruptionStyle");
    candidateSEL=sel_registerName("isEligibleForNowPlayingAppConsideration");
    clientSEL=sel_registerName("clientPID");playingSEL=sel_registerName("setIsPlayingOutput:");
    displaySEL=sel_registerName("displayID");phoneSEL=sel_registerName("hasPhoneCallBehavior");
    assistantSEL=sel_registerName("isTheAssistant");hardwareSEL=sel_registerName("isHardwareSafetySession");
    carSEL=sel_registerName("isCarSession");shareCallSEL=sel_registerName("isSharePlayCallSession");
    routeSEL=sel_registerName("routeSharingPolicy");
    return compatible(c,categorySEL,"@") && compatible(c,modeSEL,"@") && compatible(c,displaySEL,"@") &&
        compatible(c,phoneSEL,"Bc") && compatible(c,assistantSEL,"Bc") && compatible(c,hardwareSEL,"Bc") &&
        compatible(c,carSEL,"Bc") && compatible(c,shareCallSEL,"Bc") && compatible(c,routeSEL,"i") &&
        compatible(c,sel_registerName("mixesWithEveryone"),"Bc") &&
        compatible(c,sel_registerName("interruptionStyle"),"I") &&
        compatible(c,sel_registerName("allowMixableAudioWhileRecording"),"Bc") &&
        compatible(c,candidateSEL,"Bc") && compatible(c,clientSEL,"@") && compatible(c,playingSEL,"v","Bc");
}
@protocol ASCDiagnosticManager
+ (id)sharedInstance;
- (NSArray *)copyMXCoreSessionList;
@end
static int diagnosticBool(id session,const char *name) {
    SEL selector=sel_registerName(name);
    return compatible(object_getClass(session),selector,"Bc") ? boolValue(session,selector) : -1;
}
static NSString *sessionSnapshot(void) {
    if(!initialized.load(std::memory_order_acquire))return @"unavailable: hooks not ready\n";
    @try {
        Class c=objc_getClass("MXSessionManager");
        if(!compatible(object_getClass(c),@selector(sharedInstance),"@"))
            return @"unavailable: session manager ABI\n";
        id<ASCDiagnosticManager> manager=[(Class<ASCDiagnosticManager>)c sharedInstance];
        if(!compatible(object_getClass(manager),@selector(copyMXCoreSessionList),"@"))
            return @"unavailable: session list ABI\n";
        id value=[manager copyMXCoreSessionList];
        if(![value isKindOfClass:NSArray.class])return @"unavailable: session list type\n";
        NSArray *list=value;
        NSMutableString *text=[NSMutableString stringWithFormat:@"pid=%d time=%.0f sessions=%lu primaryPID=%u\n",
            getpid(),NSDate.date.timeIntervalSince1970,(unsigned long)list.count,(unsigned)primaryStamp.load()];
        for(id s in list){
            if(![s isKindOfClass:coreClass])continue;
            [text appendFormat:@"app=%@ category=%@ mode=%@ rawStyle=0x%x rawMix=%d rawRecordMix=%d recording=%d playing=%d output=%d active=%d input=%d phone=%d assistant=%d safety=%d car=%d shareCall=%d route=%d eligible=%d candidate=%d clientPID=%d primary=%d nativeAllowed=%d\n",
                objectValue(s,displaySEL),objectValue(s,categorySEL),objectValue(s,modeSEL),
                originalInterruption.load()(s,sel_registerName("interruptionStyle")),
                originalMix.load()(s,sel_registerName("mixesWithEveryone")),
                originalAllowRecording.load()(s,sel_registerName("allowMixableAudioWhileRecording")),
                diagnosticBool(s,"isRecording"),diagnosticBool(s,"isPlaying"),
                diagnosticBool(s,"isPlayingOutput"),diagnosticBool(s,"isActive"),diagnosticBool(s,"hasInput"),
                boolValue(s,phoneSEL),boolValue(s,assistantSEL),boolValue(s,hardwareSEL),
                boolValue(s,carSEL),boolValue(s,shareCallSEL),
                ((int(*)(id,SEL))objc_msgSend)(s,routeSEL),eligible(s),boolValue(s,candidateSEL),
                clientPID(s),(unsigned)clientPID(s)==(unsigned)primaryStamp.load() && primaryStamp.load()!=0,
                diagnosticBool(s,"allowedToBeNowPlayingApp")];
        }
        return text;
    } @catch(NSException *exception) {
        return [NSString stringWithFormat:@"unavailable: diagnostic exception %@\n",exception.name];
    }
}
static void dumpSessions(void) {
    @autoreleasepool {
        NSData *data=[sessionSnapshot() dataUsingEncoding:NSUTF8StringEncoding];
        if(!ASCWriteAtomic(jbroot(@"/tmp/AudioCoexistServer.sessions"),data,0600))
            appendRuntime(@"ERROR cannot write session snapshot\n");
    }
}
static void requestDump(CFNotificationCenterRef,void*,CFStringRef,const void*,CFDictionaryRef){
    if(dumpPending.exchange(true))return;
    dispatch_async(diagnosticQueue(),^{dumpSessions();dumpPending.store(false);});
}
static void loadSettings(void) {
    @autoreleasepool {
        settingsFlags.store(ASCSettingsFlags(ASCReadSettings(jbroot(ASCSettingsPath))),std::memory_order_relaxed);
    }
}
static void settingsChanged(CFNotificationCenterRef,void*,CFStringRef,const void*,CFDictionaryRef){
    if(settingsPending.exchange(true))return;
    dispatch_async(diagnosticQueue(),^{settingsPending.store(false);loadSettings();});
}
template<typename Getter>
static bool installGetter(Class c,SEL selector,IMP replacement,std::atomic<Getter> &original) {
    // Supply a valid native fallback before publishing any replacement IMP.
    original.store((Getter)method_getImplementation(class_getInstanceMethod(c,selector)),std::memory_order_release);
    IMP displaced=nullptr;
    MSHookMessageEx(c,selector,replacement,&displaced);
    if(displaced)original.store((Getter)displaced,std::memory_order_release);
    return displaced!=nullptr;
}
static void installServerHooks(void) {
    @autoreleasepool {
        Class c=objc_getClass("MXCoreSession");
        if(!c || initialized.load() || preparing.test_and_set()) return;
        if(!prepareSelectors(c)){preparing.clear();return;}
        coreClass=c;
        bool mix=installGetter(c,sel_registerName("mixesWithEveryone"),(IMP)mixGetter,originalMix);
        bool interruption=installGetter(c,sel_registerName("interruptionStyle"),(IMP)interruptionGetter,originalInterruption);
        bool recording=installGetter(c,sel_registerName("allowMixableAudioWhileRecording"),(IMP)allowRecordingGetter,originalAllowRecording);
        bool playing=installGetter(c,playingSEL,(IMP)playingSetter,originalPlaying);
        // A partial attempt stays inactive and is not re-hooked on image loads.
        if(!mix || !interruption || !recording || !playing){writeRuntimeAsync(@"INACTIVE hook installation failed\n");return;}
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),nullptr,
            settingsChanged,CFSTR("com.codex.audiocoexistserver/settingsChanged"),nullptr,
            CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),nullptr,
            requestDump,CFSTR("com.codex.audiocoexistserver/dump"),nullptr,
            CFNotificationSuspensionBehaviorDeliverImmediately);
        // Register first, then read: do not miss an update between these steps.
        loadSettings();
        initialized.store(true,std::memory_order_release);
        unsigned flags=settingsFlags.load();
        writeRuntimeAsync([NSString stringWithFormat:@"READY v0.2.16 process=audiomxd pid=%d enabled=%d recording=%d primaryPolicy=%d\n",
            getpid(),!!(flags&ASCEnabled),!!(flags&ASCRecording),originalPlaying.load()!=nullptr]);
    }
}
static void imageAdded(const struct mach_header*,intptr_t){
    if(initialized.load() || installPending.exchange(true))return;
    dispatch_async(diagnosticQueue(),^{installPending.store(false);installServerHooks();});
}
__attribute__((constructor)) static void initializeServer(void){
    if(strcmp(getprogname(),"audiomxd")!=0)return;
    _dyld_register_func_for_add_image(imageAdded);installServerHooks();
}
