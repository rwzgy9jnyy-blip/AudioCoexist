#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <cassert>
#include <atomic>
#include <thread>
#include <vector>

// macOS also ships MediaExperience classes. Map lookups to distinct test names;
// never define or modify the host system framework's MXCoreSession class.
static Class mappedCoreClass, mappedManagerClass;
static Class testClass(const char *name) {
    if(strcmp(name,"MXCoreSession")==0)return mappedCoreClass;
    if(strcmp(name,"MXSessionManager")==0)return mappedManagerClass;
    return objc_getClass(name);
}
#define objc_getClass testClass
#include "../Server.mm"
#undef objc_getClass

NSString *ASCTestRoot;
@interface ASCTestSession : NSObject
@property(nonatomic,copy) NSString *audioCategory,*audioMode,*displayID;
@property(nonatomic) bool hasPhoneCallBehavior,isTheAssistant,isHardwareSafetySession,isCarSession,isSharePlayCallSession;
@property(nonatomic) int routeSharingPolicy;
@property(nonatomic) bool mixesWithEveryone,allowMixableAudioWhileRecording;
@property(nonatomic) unsigned int interruptionStyle;
@end
@implementation ASCTestSession
@end

static id snapshotValue;
static bool throwSnapshot;
@interface ASCTestManager : NSObject <ASCDiagnosticManager>
@end
@implementation ASCTestManager
+(id)sharedInstance {static id manager;static dispatch_once_t once;dispatch_once(&once,^{manager=[self new];});return manager;}
-(NSArray *)copyMXCoreSessionList {
    if(throwSnapshot)[NSException raise:@"TestException" format:@"test diagnostic failure"];
    return snapshotValue;
}
@end
@interface ASCTestManagerWithoutList : NSObject
+(id)sharedInstance;
@end
@implementation ASCTestManagerWithoutList
+(id)sharedInstance {return [NSObject new];}
@end
@interface ASCTestOptionalSession : ASCTestSession
-(NSString *)isRecording;
-(bool)isPlaying;
@end
@implementation ASCTestOptionalSession
-(NSString *)isRecording {return @"wrong ABI";}
-(bool)isPlaying {return true;}
@end

static std::atomic_uint checks(0);
static unsigned hookCalls, failHook;
static ASCTestSession *probe;
#define CHECK(...) do{assert((__VA_ARGS__));checks.fetch_add(1);}while(0)

void MSHookMessageEx(Class cls,SEL selector,IMP replacement,IMP *original) {
    hookCalls++;
    IMP previous=method_setImplementation(class_getInstanceMethod(cls,selector),replacement);
    // Exercise a caller after the replacement is visible, before MSHook returns.
    std::thread caller([]{
        @autoreleasepool {
            CHECK(!initialized.load());CHECK(!probe.mixesWithEveryone);
            CHECK(probe.interruptionStyle==0x8);CHECK(!probe.allowMixableAudioWhileRecording);
        }
    });
    caller.join();
    *original=hookCalls==failHook ? nullptr : previous;
}

static int wrongCategory(id,SEL) {return 0;}
static void flushDiagnostics(void) {dispatch_sync(diagnosticQueue(),^{});}
static void setFlags(unsigned flags) {settingsFlags.store(flags);}
static void testPolicy(ASCTestSession *s) {
    CHECK(s.mixesWithEveryone);CHECK(s.interruptionStyle==0x10);
    CHECK(!originalMix.load()(s,@selector(mixesWithEveryone)));
    CHECK(originalInterruption.load()(s,@selector(interruptionStyle))==0x8);
    for(NSString *mode in @[@"VoiceChat",@"VideoChat",@"UnknownMode"]){
        s.audioMode=mode;CHECK(!s.mixesWithEveryone);CHECK(s.interruptionStyle==0x8);
    }
    s.audioMode=@"Default";
    for(NSString *key in @[@"hasPhoneCallBehavior",@"isTheAssistant",@"isHardwareSafetySession",@"isCarSession",@"isSharePlayCallSession"]){
        [s setValue:@YES forKey:key];CHECK(!s.mixesWithEveryone);CHECK(s.interruptionStyle==0x8);
        [s setValue:@NO forKey:key];CHECK(s.mixesWithEveryone);
    }
    for(int route : {0,1,3}){s.routeSharingPolicy=route;CHECK(s.mixesWithEveryone);}
    for(int route : {-1,2,4}){s.routeSharingPolicy=route;CHECK(!s.mixesWithEveryone);}
    s.routeSharingPolicy=0;
    for(NSString *mode in @[@"SpokenAudio",@"MoviePlayback"]){s.audioMode=mode;CHECK(s.mixesWithEveryone);}
    s.audioMode=@"Default";
    for(NSString *category in @[@"MediaPlayback",@"Audio/Video",@"AmbientSound",@"SoloAmbientSound"]){
        s.audioCategory=category;CHECK(s.mixesWithEveryone);CHECK(s.interruptionStyle==0x10);
    }
    for(id category in @[@"PhoneCall",@"SystemSoundsAndHaptics",@"Unknown",@42,NSNull.null]){
        s.audioCategory=category;CHECK(!s.mixesWithEveryone);CHECK(s.interruptionStyle==0x8);
    }
    s.audioCategory=nil;CHECK(!s.mixesWithEveryone);s.audioCategory=@"MediaPlayback";
    for(id mode in @[@42,NSNull.null]){s.audioMode=mode;CHECK(!s.mixesWithEveryone);}
    s.audioMode=nil;CHECK(!s.mixesWithEveryone);s.audioMode=@"Default";
    for(unsigned style : {0u,0x8u,0x10u}){s.interruptionStyle=style;CHECK(s.mixesWithEveryone);CHECK(s.interruptionStyle==0x10);}
    for(unsigned style : {1u,0x20u,0x18u,~0u}){s.interruptionStyle=style;CHECK(!s.mixesWithEveryone);CHECK(s.interruptionStyle==style);}
    s.interruptionStyle=0x8;setFlags(0);CHECK(s.interruptionStyle==0x8);CHECK(!s.mixesWithEveryone);
    setFlags(ASCDefaults);
    for(id display in @[@"",@42,NSNull.null]){s.displayID=display;CHECK(!s.mixesWithEveryone);}
    s.displayID=nil;CHECK(!s.mixesWithEveryone);
    for(NSString *display in @[@"com.soda.music",@"com.apple.Music",@"com.apple.WebKit.WebContent",@"arbitrary.client"]){
        s.displayID=display;CHECK(s.mixesWithEveryone);
    }
    s.displayID=@"com.tencent.xin";
    for(NSString *category in @[@"Record",@"PlayAndRecord",@"PlayAndRecord_WithBluetooth"]){
        s.audioCategory=category;CHECK(s.allowMixableAudioWhileRecording);CHECK(s.interruptionStyle==0x10);
        s.audioMode=@"VoiceChat";CHECK(!s.allowMixableAudioWhileRecording);CHECK(s.interruptionStyle==0x8);
        s.audioMode=@"Default";setFlags(ASCEnabled);CHECK(!s.allowMixableAudioWhileRecording);CHECK(s.interruptionStyle==0x8);
        setFlags(ASCDefaults);
    }
    setFlags(0);CHECK(originalInterruption.load()(s,@selector(interruptionStyle))==0x8);
    CHECK(!originalAllowRecording.load()(s,@selector(allowMixableAudioWhileRecording)));
    for(int category=ASCUnsupported;category<=ASCRecord;category++)
        for(unsigned flags=0;flags<128;flags++){
            bool e=flags&1,r=flags&2,c=flags&4,p=flags&8,d=flags&16,m=flags&32,v=flags&64;
            bool expected=e&&c&&!p&&d&&((category==ASCPlayback&&(m||v))||(category==ASCRecord&&r&&m));
            CHECK(ASCEligible(e,r,c,p,d,m,v,(ASCCategory)category)==expected);
        }
    setFlags(ASCDefaults);s.audioCategory=@"MediaPlayback";
}

static void testSettings(void) {
    CHECK(ASCSettingsFlags(nil)==ASCDefaults);CHECK(ASCSettingsFlags(@[])==ASCDefaults);
    CHECK(ASCSettingsFlags(@{@"Enabled":@[],@"Recording":NSNull.null})==ASCDefaults);
    CHECK(ASCSettingsFlags(@{@"Enabled":@NO,@"Recording":@YES})==ASCRecording);
    CHECK(ASCSettingsFlags(@{@"Enabled":@" NO ",@"Recording":@"false"})==0);
    CHECK(ASCSettingsFlags(@{@"Enabled":@"yes",@"Recording":@"1"})==ASCDefaults);
    CHECK(ASCSettingsFlags(@{@"Enabled":@"unrecognized",@"Recording":@{}})==ASCDefaults);
    CHECK([@{@"Enabled":@[],@"Recording":@{}} writeToFile:jbroot(ASCSettingsPath) atomically:YES]);
    loadSettings();CHECK(settingsFlags.load()==ASCDefaults);
    CHECK([@{@"Enabled":@NO,@"Recording":@NO} writeToFile:jbroot(ASCSettingsPath) atomically:YES]);
    settingsChanged(nullptr,nullptr,nullptr,nullptr,nullptr);flushDiagnostics();CHECK(settingsFlags.load()==0);
    std::atomic_bool bad(false);
    std::thread writer([]{for(unsigned i=0;i<20000;i++)setFlags(i&1?0:ASCDefaults);});
    for(unsigned i=0;i<20000;i++){unsigned f=settingsFlags.load();if(f!=0&&f!=ASCDefaults)bad.store(true);}
    writer.join();CHECK(!bad.load());setFlags(ASCDefaults);
}

static void testDiagnostics(ASCTestSession *s) {
    snapshotValue=@[s,@"other object"];
    NSString *snapshot=sessionSnapshot();CHECK([snapshot containsString:@"sessions=2"]);
    CHECK([snapshot containsString:@"recording=-1"]);CHECK([snapshot containsString:@"rawStyle=0x8"]);
    snapshotValue=@{};CHECK([sessionSnapshot() containsString:@"session list type"]);
    snapshotValue=@[s];throwSnapshot=true;CHECK([sessionSnapshot() containsString:@"TestException"]);throwSnapshot=false;
    mappedManagerClass=NSObject.class;CHECK([sessionSnapshot() containsString:@"manager ABI"]);
    mappedManagerClass=ASCTestManagerWithoutList.class;CHECK([sessionSnapshot() containsString:@"session list ABI"]);
    mappedManagerClass=ASCTestManager.class;
    ASCTestOptionalSession *optional=[ASCTestOptionalSession new];
    CHECK(diagnosticBool(optional,"isRecording")==-1);CHECK(diagnosticBool(optional,"isPlaying")==1);
    requestDump(nullptr,nullptr,nullptr,nullptr,nullptr);flushDiagnostics();
    NSString *path=jbroot(@"/tmp/AudioCoexistServer.sessions");
    CHECK([[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] containsString:@"rawStyle=0x8"]);
    struct stat info;CHECK(stat(path.fileSystemRepresentation,&info)==0);CHECK((info.st_mode&0777)==0600);
    flushDiagnostics();path=jbroot(@"/tmp/AudioCoexistServer.runtime");
    CHECK(stat(path.fileSystemRepresentation,&info)==0);CHECK((info.st_mode&0777)==0600);
    logBudget.store(0);std::atomic_uint tokens(0);std::vector<std::thread> workers;
    for(int i=0;i<8;i++)workers.emplace_back([&]{for(int j=0;j<1000;j++)if(takeLogToken())tokens.fetch_add(1);});
    for(auto &worker:workers)worker.join();CHECK(tokens.load()==16);CHECK(logBudget.load()==16);
    NSString *victim=jbroot(@"/tmp/victim"),*link=jbroot(@"/tmp/link");
    CHECK([@"unchanged" writeToFile:victim atomically:YES encoding:NSUTF8StringEncoding error:nil]);
    CHECK(symlink(victim.fileSystemRepresentation,link.fileSystemRepresentation)==0);
    CHECK(ASCOpenRegular(link,O_WRONLY|O_APPEND,0600)==-1);
    CHECK(ASCWriteAtomic(link,[@"snapshot" dataUsingEncoding:NSUTF8StringEncoding],0600));
    CHECK([[NSString stringWithContentsOfFile:victim encoding:NSUTF8StringEncoding error:nil] isEqual:@"unchanged"]);
    NSString *fifo=jbroot(@"/tmp/fifo");CHECK(mkfifo(fifo.fileSystemRepresentation,0600)==0);
    CHECK(ASCOpenRegular(fifo,O_RDWR,0600)==-1);
    CHECK(!ASCWriteAtomic(jbroot(@"/missing/snapshot"),[@"test" dataUsingEncoding:NSUTF8StringEncoding],0600));
}

int main(int argc,char **argv){@autoreleasepool{
    ASCTestRoot=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    for(NSString *path in @[@"/tmp",ASCSettingsPath.stringByDeletingLastPathComponent])
        CHECK([NSFileManager.defaultManager createDirectoryAtPath:jbroot(path) withIntermediateDirectories:YES attributes:nil error:nil]);
    mappedCoreClass=ASCTestSession.class;mappedManagerClass=ASCTestManager.class;
    probe=[ASCTestSession new];probe.audioCategory=@"MediaPlayback";probe.audioMode=@"Default";
    probe.displayID=@"test.client";probe.interruptionStyle=0x8;
    bool failure=argc==2&&strcmp(argv[1],"--hook-failure")==0;
    if(failure)failHook=2;
    CHECK([sessionSnapshot() containsString:@"not ready"]);
    Class bad=objc_allocateClassPair(ASCTestSession.class,"ASCInvalidSessionABI",0);
    CHECK(class_addMethod(bad,@selector(audioCategory),(IMP)wrongCategory,"i@:"));objc_registerClassPair(bad);
    mappedCoreClass=bad;installServerHooks();CHECK(!initialized.load());CHECK(hookCalls==0);
    mappedCoreClass=ASCTestSession.class;installServerHooks();CHECK(hookCalls==3);
    installServerHooks();CHECK(hookCalls==3);
    for(int i=0;i<100;i++)imageAdded(nullptr,0);
    flushDiagnostics();CHECK(hookCalls==3);CHECK(!installPending.load());
    if(failure){CHECK(!initialized.load());CHECK(!probe.mixesWithEveryone);CHECK(probe.interruptionStyle==0x8);}
    else {CHECK(initialized.load());testPolicy(probe);testSettings();testDiagnostics(probe);}
    CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(),nullptr);
    flushDiagnostics();CHECK([NSFileManager.defaultManager removeItemAtPath:ASCTestRoot error:nil]);
    printf("PASS: %u production server assertions (%s)\n",checks.load(),failure?"partial hook failure":"policy, settings, diagnostics, concurrency");
}}
