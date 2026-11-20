#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// Feature gate for the BG Wave invite screen. Reads "beygram.feature.bgMedia" (BeyGramFeature.bgMedia).
// Off by default.
BOOL BGWaveFeatureEnabled(void);

// True when the text has the shape of a BG Wave invite link: bg://wave/v1/<payload> or the
// https form of the same link. Only the shape is checked. Nothing is joined.
BOOL BGWaveLinkLooksValid(NSString *link);

// BG Wave invite screen. Joining a session is not implemented on iOS yet: host audio capture and
// the WebRTC stack are not built for iOS (see issue #50). The screen only checks pasted links.
@interface BGWaveViewController : UIViewController

- (instancetype)init;

@end

NS_ASSUME_NONNULL_END
