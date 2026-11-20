#import "BeyGramMedia/BGWaveViewController.h"

// Written by BeyGramSettings (BeyGramKit) as "beygram.feature." + BeyGramFeature.bgMedia.rawValue.
static NSString *const BGWaveFeatureKey = @"beygram.feature.bgMedia";
static NSString *const BGWaveNativePrefix = @"bg://wave/v1/";
static NSString *const BGWaveHttpsPrefix = @"https://beygram.beykus.fun/#bgwave-v1.";
// Same limit as BgWaveLink.MAX_LINK_CHARS on Android.
static const NSUInteger BGWaveMaxLinkChars = 4096;

BOOL BGWaveFeatureEnabled(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if ([defaults objectForKey:BGWaveFeatureKey] == nil) {
        return NO;
    }
    return [defaults boolForKey:BGWaveFeatureKey];
}

BOOL BGWaveLinkLooksValid(NSString *link) {
    NSString *trimmed = [link stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0 || trimmed.length > BGWaveMaxLinkChars) {
        return NO;
    }
    NSString *payload = nil;
    if ([trimmed hasPrefix:BGWaveNativePrefix]) {
        payload = [trimmed substringFromIndex:BGWaveNativePrefix.length];
    } else if ([trimmed hasPrefix:BGWaveHttpsPrefix]) {
        payload = [trimmed substringFromIndex:BGWaveHttpsPrefix.length];
    }
    return payload.length > 0;
}

@interface BGWaveViewController ()
@property (nonatomic, strong) UITextField *linkField;
@property (nonatomic, strong) UILabel *resultLabel;
@end

@implementation BGWaveViewController

- (instancetype)init {
    self = [super init];
    if (self == nil) {
        return nil;
    }
    self.title = @"BG Wave";
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    UILabel *intro = [[UILabel alloc] init];
    intro.translatesAutoresizingMaskIntoConstraints = NO;
    intro.numberOfLines = 0;
    intro.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    intro.textColor = UIColor.secondaryLabelColor;
    intro.text = @"BG Wave on iOS: invite links can be checked here. Listening together is not available yet: host audio capture and the WebRTC stack are not built for iOS.";

    self.linkField = [[UITextField alloc] init];
    self.linkField.translatesAutoresizingMaskIntoConstraints = NO;
    self.linkField.borderStyle = UITextBorderStyleRoundedRect;
    self.linkField.placeholder = @"bg://wave/v1/...";
    self.linkField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.linkField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.linkField.clearButtonMode = UITextFieldViewModeWhileEditing;

    UIButton *checkButton = [UIButton buttonWithType:UIButtonTypeSystem];
    checkButton.translatesAutoresizingMaskIntoConstraints = NO;
    [checkButton setTitle:@"Check link" forState:UIControlStateNormal];
    [checkButton addTarget:self action:@selector(checkTapped) forControlEvents:UIControlEventTouchUpInside];

    self.resultLabel = [[UILabel alloc] init];
    self.resultLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.resultLabel.numberOfLines = 0;
    self.resultLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];

    [self.view addSubview:intro];
    [self.view addSubview:self.linkField];
    [self.view addSubview:checkButton];
    [self.view addSubview:self.resultLabel];

    UILayoutGuide *margins = self.view.layoutMarginsGuide;
    [NSLayoutConstraint activateConstraints:@[
        [intro.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:16.0],
        [intro.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
        [intro.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
        [self.linkField.topAnchor constraintEqualToAnchor:intro.bottomAnchor constant:16.0],
        [self.linkField.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
        [self.linkField.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
        [checkButton.topAnchor constraintEqualToAnchor:self.linkField.bottomAnchor constant:12.0],
        [checkButton.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
        [self.resultLabel.topAnchor constraintEqualToAnchor:checkButton.bottomAnchor constant:16.0],
        [self.resultLabel.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
        [self.resultLabel.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
    ]];
}

- (void)checkTapped {
    [self.linkField resignFirstResponder];
    if (BGWaveLinkLooksValid(self.linkField.text ?: @"")) {
        self.resultLabel.text = @"The link looks like a BG Wave invite. Joining is not implemented on iOS yet, so nothing was connected.";
    } else {
        self.resultLabel.text = @"This is not a BG Wave invite link.";
    }
}

@end
