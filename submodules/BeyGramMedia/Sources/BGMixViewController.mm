#import "BeyGramMedia/BGMixViewController.h"
#import "BeyGramMedia/BGMixPlayer.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

// Written by BeyGramSettings (BeyGramKit) as "beygram.feature." + BeyGramFeature.musicLibrary.rawValue.
static NSString *const BGMixFeatureKey = @"beygram.feature.musicLibrary";

@interface BGMixViewController () <UIDocumentPickerDelegate, UITableViewDataSource, BGMixPlayerObserver>
// The app's shared player. The screen observes it and never stops it: leaving the screen does not stop the mix.
@property (nonatomic, strong) BGMixPlayer *player;
// The latest state the player published while the screen was on screen. Nil before the first one.
@property (nonatomic, strong, nullable) BGMixSnapshot *latestSnapshot;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIToolbar *toolbar;
@property (nonatomic, strong) UIBarButtonItem *playButton;
@end

BOOL BGMixFeatureEnabled(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if ([defaults objectForKey:BGMixFeatureKey] == nil) {
        return NO;
    }
    return [defaults boolForKey:BGMixFeatureKey];
}

static NSString *BGMixTitleForTrackState(BGMixTrackState state) {
    switch (state) {
        case BGMixTrackStatePending: return @"waiting";
        case BGMixTrackStatePreparing: return @"preparing";
        case BGMixTrackStateReady: return @"ready";
        case BGMixTrackStatePlaying: return @"playing";
        case BGMixTrackStatePlayed: return @"played";
        case BGMixTrackStateFailed: return @"failed";
    }
    return @"";
}

@implementation BGMixViewController

- (instancetype)init {
    self = [super init];
    if (self == nil) {
        return nil;
    }
    self.title = @"BG Mix";
    self.player = [BGMixPlayer sharedPlayer];
    return self;
}

- (void)dealloc {
    [self.player removeObserver:self];
}

// The screen listens only while it is on screen. The player belongs to the app, so leaving the screen
// does not stop the mix.
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.player addObserver:self];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [self.player removeObserver:self];
}

// The screen is hosted inside a Telegram ViewController, which has its own navigation bar.
// UIKit navigationItem buttons would not show there, so the actions live in a bottom toolbar.
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    [self.view addSubview:self.tableView];

    self.playButton = [[UIBarButtonItem alloc] initWithTitle:@"Play" style:UIBarButtonItemStylePlain target:self action:@selector(playTapped)];
    self.toolbar = [[UIToolbar alloc] initWithFrame:CGRectZero];
    self.toolbar.translatesAutoresizingMaskIntoConstraints = NO;
    self.toolbar.items = @[
        [[UIBarButtonItem alloc] initWithTitle:@"Add" style:UIBarButtonItemStylePlain target:self action:@selector(addTapped)],
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil],
        self.playButton,
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil],
        [[UIBarButtonItem alloc] initWithTitle:@"Next" style:UIBarButtonItemStylePlain target:self action:@selector(nextTapped)],
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil],
        [[UIBarButtonItem alloc] initWithTitle:@"Clear" style:UIBarButtonItemStylePlain target:self action:@selector(clearTapped)],
    ];
    [self.view addSubview:self.toolbar];

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.toolbar.topAnchor],
        [self.toolbar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.toolbar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.toolbar.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
}

- (void)addTapped {
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeAudio] asCopy:YES];
    picker.allowsMultipleSelection = YES;
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

// Copies each picked file into the app's own folder, then queues the copy. The queue itself comes back
// through the observer.
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *mixDirectory = [BGMixPlayer mixDirectory];
    NSFileManager *fm = NSFileManager.defaultManager;
    for (NSURL *source in urls) {
        BOOL scoped = [source startAccessingSecurityScopedResource];
        NSURL *target = [mixDirectory URLByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@", NSUUID.UUID.UUIDString, source.lastPathComponent]];
        NSError *error = nil;
        BOOL copied = [fm copyItemAtURL:source toURL:target error:&error];
        if (scoped) {
            [source stopAccessingSecurityScopedResource];
        }
        if (copied) {
            [self.player addTrackAtURL:target];
        }
    }
}

- (void)playTapped {
    if (self.latestSnapshot.transport == BGMixTransportPlaying) {
        [self.player pause];
    } else {
        [self.player play];
    }
}

- (void)nextTapped {
    [self.player next];
}

- (void)clearTapped {
    [self.player stopAll];
    [self.player clearQueue];
}

#pragma mark - BGMixPlayerObserver

- (void)mixPlayer:(BGMixPlayer *)player didUpdateSnapshot:(BGMixSnapshot *)snapshot {
    // Rows are reloaded only when the queue changed, not on every transport update.
    const BOOL queueChanged = ![self.latestSnapshot.queue isEqualToArray:snapshot.queue];
    self.latestSnapshot = snapshot;
    self.playButton.title = snapshot.transport == BGMixTransportPlaying ? @"Pause" : @"Play";
    if (queueChanged) {
        [self.tableView reloadData];
    }
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.latestSnapshot.queue.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"track"];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"track"];
    }
    BGMixTrack *track = self.latestSnapshot.queue[(NSUInteger)indexPath.row];
    cell.textLabel.text = [NSString stringWithFormat:@"%@ (%@)", track.name, BGMixTitleForTrackState(track.state)];
    return cell;
}

@end
