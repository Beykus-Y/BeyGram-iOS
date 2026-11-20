#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// Feature gate for BG Mix. Off by default: nothing in the app shows the screen
// until this returns YES. No BeyGramKit flag exists in the repository yet.
BOOL BGMixFeatureEnabled(void);

// Minimal BG Mix screen: a queue of local audio files, play, next and clear.
// Files are copied into the app's Documents folder before they are queued,
// because the mixer reads them later on a worker thread.
@interface BGMixViewController : UIViewController

- (instancetype)init;

@end

NS_ASSUME_NONNULL_END
