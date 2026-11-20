#import "BGWaveListener/BGWaveListenerSession.h"

#import "BGWaveListener/BGWaveListenerOutput.h"

#import <QuartzCore/QuartzCore.h>

#include "BGWaveRuntime.hpp"

#include <memory>
#include <optional>
#include <string>

NSErrorDomain const BGWaveListenerSessionErrorDomain = @"BGWaveListenerSession";

static const NSInteger kInviteErrorCode = 1;
// The pipeline timer period. BGWaveSession::process wants 10 to 20 ms, off the audio thread.
static const uint64_t kProcessIntervalNs = 15 * NSEC_PER_MSEC;
static const uint64_t kProcessLeewayNs = 2 * NSEC_PER_MSEC;

static BGWaveListenerFailure BGWaveListenerFailureFrom(beygram::wave::WaveFailureKind kind) {
    switch (kind) {
        case beygram::wave::WaveFailureKind::LocalNetworkSuspected:
            return BGWaveListenerFailureLocalNetworkSuspected;
        case beygram::wave::WaveFailureKind::Other:
            return BGWaveListenerFailureOther;
        case beygram::wave::WaveFailureKind::None:
            break;
    }
    return BGWaveListenerFailureNone;
}

@interface BGWaveListenerSession () {
    // Owns the codec, the transport and BGWaveSession. Every call goes through `queue`, except the audio pull.
    std::unique_ptr<beygram::wave::BGWaveRuntime> _runtime;
}

@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, strong, nullable) dispatch_source_t timer;
@property (nonatomic, strong, nullable) BGWaveListenerOutput *output;

@end

@implementation BGWaveListenerSession

- (instancetype)init {
    self = [super init];
    if (self != nil) {
        beygram::wave::BGWaveRuntime::Options options;
        options.role = bgmedia::wave::WaveRole::Listener;
        _runtime = std::make_unique<beygram::wave::BGWaveRuntime>(options);
        _queue = dispatch_queue_create("org.beygram.wave.listener", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)dealloc {
    [self stop];
}

- (BOOL)acceptInviteLink:(NSString *)link
          nowUnixSeconds:(int64_t)nowUnixSeconds
                   error:(NSError **)error {
    const char *utf8 = link.UTF8String;
    if (utf8 == NULL) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:BGWaveListenerSessionErrorDomain code:kInviteErrorCode userInfo:nil];
        }
        return NO;
    }
    const std::string text(utf8);
    beygram::wave::BGWaveRuntime *runtime = _runtime.get();
    __block BOOL accepted = NO;
    dispatch_sync(self.queue, ^{
        accepted = runtime->acceptInvite(text, nowUnixSeconds, nullptr) ? YES : NO;
    });
    if (!accepted && error != NULL) {
        *error = [NSError errorWithDomain:BGWaveListenerSessionErrorDomain code:kInviteErrorCode userInfo:nil];
    }
    return accepted;
}

- (nullable NSString *)pollOutboundInvite {
    beygram::wave::BGWaveRuntime *runtime = _runtime.get();
    __block NSString *invite = nil;
    dispatch_sync(self.queue, ^{
        std::optional<std::string> next = runtime->pollOutboundInvite();
        if (next.has_value()) {
            invite = [NSString stringWithUTF8String:next->c_str()];
        }
    });
    return invite;
}

- (BOOL)startListeningWithError:(NSError **)error {
    if (self.output == nil) {
        // The pull block keeps the runtime pointer. dealloc stops the output before the runtime is destroyed.
        beygram::wave::BGWaveRuntime *runtime = _runtime.get();
        self.output = [[BGWaveListenerOutput alloc] initWithPullBlock:^NSUInteger(float *outInterleavedStereo,
                                                                                  NSUInteger frames,
                                                                                  uint32_t sampleRate) {
            return (NSUInteger)runtime->pullListenerPcm(outInterleavedStereo, frames, sampleRate);
        }];
    }
    if (![self.output startWithError:error]) {
        return NO;
    }
    [self startTimer];
    return YES;
}

- (void)stop {
    if (self.timer != nil) {
        dispatch_source_cancel(self.timer);
        self.timer = nil;
    }
    [self.output stop];
    // Captures the raw pointer, not self: stop runs from dealloc too.
    beygram::wave::BGWaveRuntime *runtime = _runtime.get();
    dispatch_sync(self.queue, ^{
        runtime->stop(true, 0);
    });
}

- (BGWaveListenerFailure)failure {
    beygram::wave::BGWaveRuntime *runtime = _runtime.get();
    __block beygram::wave::WaveFailureKind kind = beygram::wave::WaveFailureKind::None;
    dispatch_sync(self.queue, ^{
        kind = runtime->failureKind();
    });
    return BGWaveListenerFailureFrom(kind);
}

#pragma mark - Timer

- (void)startTimer {
    if (self.timer != nil) {
        return;
    }
    beygram::wave::BGWaveRuntime *runtime = _runtime.get();
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self.queue);
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 0), kProcessIntervalNs, kProcessLeewayNs);
    dispatch_source_set_event_handler(timer, ^{
        runtime->process(CACurrentMediaTime());
    });
    dispatch_resume(timer);
    self.timer = timer;
}

@end
