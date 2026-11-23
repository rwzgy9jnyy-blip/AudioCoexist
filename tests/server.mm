#define ASC_HOST_TEST 1
#include "../Server.mm"
#include <cassert>
@interface TestSession : NSObject
@property(nonatomic,copy) NSString *audioCategory;
@property(nonatomic,copy) NSString *audioMode;
@property(nonatomic,copy) NSString *displayID;
@property(nonatomic) bool hasPhoneCallBehavior,isTheAssistant,isHardwareSafetySession,isCarSession,isSharePlayCallSession;
@property(nonatomic) int routeSharingPolicy;
@property(nonatomic) bool mixesWithEveryone,allowMixableAudioWhileRecording;
@property(nonatomic) unsigned int interruptionStyle;
@end
@implementation TestSession
@end
static unsigned checks;
#define CHECK(x) do{assert(x);checks++;}while(0)
static void hook(SEL sel,IMP replacement,IMP *orig){
    Method m=class_getInstanceMethod(TestSession.class,sel);CHECK(m!=nullptr);
    *orig=method_setImplementation(m,replacement);
}
int main(){@autoreleasepool{
    initialized.store(false);logBudget.store(0);preparing.clear();
    coreClass=TestSession.class;CHECK(prepareSelectors(coreClass));
    hook(@selector(mixesWithEveryone),(IMP)mixGetter,(IMP*)&originalMix);
    hook(@selector(interruptionStyle),(IMP)interruptionGetter,(IMP*)&originalInterruption);
    hook(@selector(allowMixableAudioWhileRecording),(IMP)allowRecordingGetter,(IMP*)&originalAllowRecording);
    TestSession *s=[TestSession new];s.displayID=@"com.soda.music";
    s.audioCategory=@"MediaPlayback";s.audioMode=@"Default";s.interruptionStyle=0x8;
    CHECK(s.mixesWithEveryone);CHECK(s.interruptionStyle==0x10);
    CHECK(!originalMix(s,@selector(mixesWithEveryone)));
    CHECK(originalInterruption(s,@selector(interruptionStyle))==0x8);
    s.audioMode=@"VoiceChat";CHECK(!s.mixesWithEveryone);CHECK(s.interruptionStyle==0x8);
    s.audioMode=@"VideoChat";CHECK(s.interruptionStyle==0x8);
    s.audioMode=@"Default";s.hasPhoneCallBehavior=true;CHECK(!s.mixesWithEveryone);CHECK(s.interruptionStyle==0x8);
    s.hasPhoneCallBehavior=false;s.isTheAssistant=true;CHECK(!s.mixesWithEveryone);
    s.isTheAssistant=false;s.isHardwareSafetySession=true;CHECK(!s.mixesWithEveryone);
    s.isHardwareSafetySession=false;s.isCarSession=true;CHECK(!s.mixesWithEveryone);
    s.isCarSession=false;s.isSharePlayCallSession=true;CHECK(!s.mixesWithEveryone);
    s.isSharePlayCallSession=false;s.routeSharingPolicy=1;CHECK(s.mixesWithEveryone);
    s.routeSharingPolicy=3;CHECK(s.mixesWithEveryone);
    s.routeSharingPolicy=2;CHECK(!s.mixesWithEveryone);
    s.routeSharingPolicy=0;s.audioMode=@"UnknownMode";CHECK(!s.mixesWithEveryone);
    s.audioMode=@"SpokenAudio";CHECK(s.mixesWithEveryone);
    s.audioMode=@"Default";
    for(NSString *category in @[@"Audio/Video",@"AmbientSound",@"SoloAmbientSound"]){
        s.audioCategory=category;CHECK(s.mixesWithEveryone);CHECK(s.interruptionStyle==0x10);
    }
    s.audioCategory=@"PhoneCall";s.audioMode=@"Default";CHECK(!s.mixesWithEveryone);
    s.audioCategory=@"MediaPlayback";s.interruptionStyle=0x20;CHECK(s.interruptionStyle==0x20);CHECK(!s.mixesWithEveryone);
    s.interruptionStyle=0x8;enabled.store(false);CHECK(s.interruptionStyle==0x8);CHECK(!s.mixesWithEveryone);
    enabled.store(true);s.displayID=@"com.apple.springboard";s.audioCategory=@"SystemSoundsAndHaptics";CHECK(s.interruptionStyle==0x8);
    s.displayID=@"com.apple.Music";s.audioCategory=@"MediaPlayback";CHECK(s.interruptionStyle==0x10);
    s.displayID=nil;CHECK(s.interruptionStyle==0x8);
    s.displayID=@"com.tencent.xin";s.audioCategory=@"PlayAndRecord_WithBluetooth";
    CHECK(s.allowMixableAudioWhileRecording);CHECK(s.interruptionStyle==0x10);
    s.audioMode=@"VoiceChat";CHECK(!s.allowMixableAudioWhileRecording);CHECK(s.interruptionStyle==0x8);
    s.audioMode=@"Default";recordingEnabled.store(false);CHECK(!s.allowMixableAudioWhileRecording);
    CHECK(s.interruptionStyle==0x8);recordingEnabled.store(true);
    // The hook never mutates stored session policy; disabling restores it immediately.
    enabled.store(false);CHECK(originalInterruption(s,@selector(interruptionStyle))==0x8);
    CHECK(!originalAllowRecording(s,@selector(allowMixableAudioWhileRecording)));
    for(int category=ASCUnsupported;category<=ASCRecord;category++)
      for(unsigned flags=0;flags<256;flags++){
        bool e=flags&1,r=flags&2,c=flags&4,p=flags&8,d=flags&16,m=flags&32,v=flags&64;
        bool actual=ASCEligible(e,r,c,p,d,m,v,(ASCCategory)category);
        if(!e||!c||p||!d||category==ASCUnsupported)CHECK(!actual);
        if(category==ASCRecord&&(!r||!m))CHECK(!actual);
      }
    printf("PASS: %u server policy/hook assertions; original state unchanged\n",checks);
}}
