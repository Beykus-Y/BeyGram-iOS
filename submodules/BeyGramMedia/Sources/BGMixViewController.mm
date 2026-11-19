#import "BeyGramMedia/BGMixViewController.h"
#import "BeyGramMedia/BGMixPlayer.h"

@interface BGMixViewController () <UIDocumentPickerDelegate, UITableViewDataSource>
@property (nonatomic, strong) BGMixPlayer *player;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *tracks; // {id: NSNumber, name: NSString}
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIBarButtonItem *playButton;
@property (nonatomic, strong) NSURL *mixDirectory;
@property (nonatomic) BOOL playing;
@end

BOOL BGMixFeatureEnabled(void) {
    return NO;
}

@implementation BGMixViewController

- (instancetype)init {
    self = [super init];
    if (self == nil) {
        return nil;
    }
    self.title = @"BG Mix";
    self.tracks = [NSMutableArray array];

    NSArray<NSURL *> *docs = [[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask];
    self.mixDirectory = [docs.firstObject URLByAppendingPathComponent:@"bgmix" isDirectory:YES];
    NSURL *cacheDir = [self.mixDirectory URLByAppendingPathComponent:@"cache" isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:cacheDir withIntermediateDirectories:YES attributes:nil error:nil];
    self.player = [[BGMixPlayer alloc] initWithCacheDirectory:cacheDir.path];
    return self;
}

- (void)dealloc {
    [self.player invalidate];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    [self.view addSubview:self.tableView];

    self.navigationItem.rightBarButtonItems = @[
        [[UIBarButtonItem alloc] initWithTitle:@"Add" style:UIBarButtonItemStylePlain target:self action:@selector(addTapped)],
    ];
    self.playButton = [[UIBarButtonItem alloc] initWithTitle:@"Play" style:UIBarButtonItemStylePlain target:self action:@selector(playTapped)];
    self.navigationItem.leftBarButtonItems = @[
        self.playButton,
        [[UIBarButtonItem alloc] initWithTitle:@"Next" style:UIBarButtonItemStylePlain target:self action:@selector(nextTapped)],
        [[UIBarButtonItem alloc] initWithTitle:@"Clear" style:UIBarButtonItemStylePlain target:self action:@selector(clearTapped)],
    ];
}

- (void)addTapped {
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.audio"] inMode:UIDocumentPickerModeImport];
    picker.allowsMultipleSelection = YES;
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

// Copies each picked file into the app's own folder, then queues the copy.
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSFileManager *fm = NSFileManager.defaultManager;
    [fm createDirectoryAtURL:self.mixDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    for (NSURL *source in urls) {
        BOOL scoped = [source startAccessingSecurityScopedResource];
        NSURL *target = [self.mixDirectory URLByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@", NSUUID.UUID.UUIDString, source.lastPathComponent]];
        NSError *error = nil;
        BOOL copied = [fm copyItemAtURL:source toURL:target error:&error];
        if (scoped) {
            [source stopAccessingSecurityScopedResource];
        }
        if (!copied) {
            continue;
        }
        uint64_t identifier = [self.player addTrackAtURL:target];
        if (identifier != 0) {
            [self.tracks addObject:@{@"id": @(identifier), @"name": source.lastPathComponent}];
        }
    }
    [self.tableView reloadData];
}

- (void)playTapped {
    if (self.playing) {
        [self.player pause];
        self.playing = NO;
        self.playButton.title = @"Play";
    } else {
        [self.player play];
        self.playing = YES;
        self.playButton.title = @"Pause";
    }
}

- (void)nextTapped {
    [self.player next];
}

- (void)clearTapped {
    [self.player stopAll];
    [self.player clearQueue];
    [self.tracks removeAllObjects];
    self.playing = NO;
    self.playButton.title = @"Play";
    [self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.tracks.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"track"];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"track"];
    }
    cell.textLabel.text = self.tracks[(NSUInteger)indexPath.row][@"name"];
    return cell;
}

@end
