//
//  GMImagePickerController.m
//  GMPhotoPicker
//
//  Created by Guillermo Muntaner Perelló on 19/09/14.
//  Copyright (c) 2014 Guillermo Muntaner Perelló. All rights reserved.
//

#import <MobileCoreServices/MobileCoreServices.h>
#import "GMImagePickerController.h"
#import "GMAlbumsViewController.h"
#import "GMGridViewController.h"
#import "GMAlbumsViewCell.h"
#import "MKDropdownMenu.h"
@import Photos;

static inline void delay(NSTimeInterval delay, dispatch_block_t block) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), block);
}

@interface GMImagePickerController () <UINavigationControllerDelegate, UIImagePickerControllerDelegate, UIAlertViewDelegate, MKDropdownMenuDataSource, MKDropdownMenuDelegate, PHPhotoLibraryChangeObserver>
@property (strong, nonatomic) MKDropdownMenu *navBarMenu;
@property (strong) NSArray *collectionsFetchResults;
@property (strong,atomic) NSArray *collectionsFetchResultsAssets;
@property (strong,atomic) NSArray *collectionsFetchResultsTitles;
@property (strong) PHCachingImageManager *imageManager;
@property (assign) NSInteger selectedRow;

@end

@implementation GMImagePickerController

- (void)viewDidLoad
{
    [super viewDidLoad];
    [[PHPhotoLibrary sharedPhotoLibrary] registerChangeObserver:self];
    
    self.imageManager = [[PHCachingImageManager alloc] init];
    
}
- (void)dealloc
{
    [[PHPhotoLibrary sharedPhotoLibrary] unregisterChangeObserver:self];
}

- (id)init:(bool)allow_v withAssets: (NSArray*)preSelectedAssets delegate: (id<GMImagePickerControllerDelegate>) delegate
{
    if (self = [super init])
    {
        self.delegate = delegate;
        self.videoMaximumDuration = 15;
        _selectedAssets = [[NSMutableArray alloc] init];
        
        PHFetchResult *fetchResult = [PHAsset fetchAssetsWithLocalIdentifiers:preSelectedAssets options:nil];
        
        for (PHAsset *asset in fetchResult) {
            [_selectedAssets addObject: asset];
        }
        
        // _selectedAssets = [fetchResult copy];
        _allow_video = allow_v;
        
        _shouldCancelWhenBlur = YES;
        
        // Default values:
        _displaySelectionInfoToolbar = YES;
        _displayAlbumsNumberOfAssets = YES;
        _autoDisableDoneButton = YES;
        _allowsMultipleSelection = YES;
        _confirmSingleSelection = NO;
        _showCameraButton = NO;
        
        // Grid configuration:
        if([self.delegate respondsToSelector:@selector(assetsPickerControllerColumnInPortrait)] && [self.delegate respondsToSelector:@selector(assetsPickerControllerColumnInLandscape)]) {
            _colsInPortrait =  [self.delegate assetsPickerControllerColumnInPortrait];
            _colsInLandscape =  [self.delegate assetsPickerControllerColumnInLandscape];
        } else {
            NSOperatingSystemVersion ios10_0_1 = (NSOperatingSystemVersion){10, 0, 1};
            if([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad){
                if ([[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:ios10_0_1]) {
                    // iOS 8.0.1 and above logic
                    _colsInPortrait = 6;
                    _colsInLandscape = 10;
                } else {
                    // iOS 8.0.0 and below logic
                    _colsInPortrait = 4;
                    _colsInLandscape = 5;
                }
                
            }else{
                _colsInPortrait = 3;
                _colsInLandscape = 5;
            }
        }
        _minimumInteritemSpacing = 2.0;
        
        // Sample of how to select the collections you want to display:
        //        _customSmartCollections = @[@(PHAssetCollectionSubtypeSmartAlbumFavorites),
        //                                    @(PHAssetCollectionSubtypeSmartAlbumRecentlyAdded),
        //                                    @(PHAssetCollectionSubtypeSmartAlbumVideos),
        //                                    @(PHAssetCollectionSubtypeSmartAlbumSlomoVideos),
        //                                    @(PHAssetCollectionSubtypeSmartAlbumTimelapses),
        //                                    @(PHAssetCollectionSubtypeSmartAlbumBursts),
        //                                    @(PHAssetCollectionSubtypeSmartAlbumPanoramas)];
        _customSmartCollections = @[@(PHAssetCollectionSubtypeSmartAlbumFavorites),
                                    @(PHAssetCollectionSubtypeSmartAlbumRecentlyAdded),
                                    @(PHAssetCollectionSubtypeSmartAlbumPanoramas)];
        
        // If you don't want to show smart collections, just put _customSmartCollections to nil;
        //_customSmartCollections=nil;
        
        // Which media types will display
        //        _mediaTypes = @[@(PHAssetMediaTypeAudio),
        //                        @(PHAssetMediaTypeVideo),
        //                        @(PHAssetMediaTypeImage)];
        _mediaTypes = @[@(PHAssetMediaTypeImage)];
        self.preferredContentSize = kPopoverContentSize;
        
        // UI Customisation
        _pickerBackgroundColor = [UIColor whiteColor];
        _pickerTextColor = [UIColor darkTextColor];
        _pickerFontName = @"HelveticaNeue";
        _pickerBoldFontName = @"HelveticaNeue-Bold";
        _pickerFontNormalSize = 14.0f;
        _pickerFontHeaderSize = 17.0f;
        
        _navigationBarBackgroundColor = [UIColor whiteColor];
        _navigationBarTextColor = [UIColor darkTextColor];
        _navigationBarTintColor = [UIColor darkTextColor];
        
        _toolbarBarTintColor = [UIColor whiteColor];
        _toolbarTextColor = [UIColor darkTextColor];
        _toolbarTintColor = [UIColor darkTextColor];
        
        _pickerStatusBarStyle = UIStatusBarStyleDefault;
        _barStyle = UIBarStyleDefault;
        
    }
    return self;
}

- (id)init
{
    if (self = [super init]) {
        _selectedAssets = [[NSMutableArray alloc] init];
        
        // Default values:
        _displaySelectionInfoToolbar = YES;
        _displayAlbumsNumberOfAssets = YES;
        _autoDisableDoneButton = YES;
        _allowsMultipleSelection = YES;
        _confirmSingleSelection = NO;
        _showCameraButton = NO;
        
        // Grid configuration:
        if([self.delegate respondsToSelector:@selector(assetsPickerControllerColumnInPortrait)] && [self.delegate respondsToSelector:@selector(assetsPickerControllerColumnInLandscape)]) {
            _colsInPortrait =  [self.delegate assetsPickerControllerColumnInPortrait];
            _colsInLandscape =  [self.delegate assetsPickerControllerColumnInLandscape];
        } else {
            NSOperatingSystemVersion ios10_0_1 = (NSOperatingSystemVersion){10, 0, 1};
            if([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad){
                if ([[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:ios10_0_1]) {
                    // iOS 8.0.1 and above logic
                    _colsInPortrait = 6;
                    _colsInLandscape = 10;
                } else {
                    // iOS 8.0.0 and below logic
                    _colsInPortrait = 4;
                    _colsInLandscape = 5;
                }
                
            }else{
                _colsInPortrait = 3;
                _colsInLandscape = 5;
            }
        }
        
        _minimumInteritemSpacing = 2.0;
        
        // Sample of how to select the collections you want to display:
        _customSmartCollections = @[@(PHAssetCollectionSubtypeSmartAlbumFavorites),
                                    @(PHAssetCollectionSubtypeSmartAlbumRecentlyAdded),
                                    @(PHAssetCollectionSubtypeSmartAlbumVideos),
//                                    @(PHAssetCollectionSubtypeSmartAlbumSlomoVideos),
                                    @(PHAssetCollectionSubtypeSmartAlbumTimelapses),
                                    @(PHAssetCollectionSubtypeSmartAlbumBursts),
                                    @(PHAssetCollectionSubtypeSmartAlbumPanoramas)];
        // If you don't want to show smart collections, just put _customSmartCollections to nil;
        //_customSmartCollections=nil;
        
        // Which media types will display
        _mediaTypes = @[@(PHAssetMediaTypeAudio),
                        @(PHAssetMediaTypeVideo),
                        @(PHAssetMediaTypeImage)];
        
        self.preferredContentSize = kPopoverContentSize;
        
        // UI Customisation
        _pickerBackgroundColor = [UIColor whiteColor];
        _pickerTextColor = [UIColor darkTextColor];
        _pickerFontName = @"HelveticaNeue";
        _pickerBoldFontName = @"HelveticaNeue-Bold";
        _pickerFontNormalSize = 14.0f;
        _pickerFontHeaderSize = 17.0f;
        
        _navigationBarBackgroundColor = [UIColor whiteColor];
        _navigationBarTextColor = [UIColor darkTextColor];
        _navigationBarTintColor = [UIColor darkTextColor];
        
        _toolbarBarTintColor = [UIColor whiteColor];
        _toolbarTextColor = [UIColor darkTextColor];
        _toolbarTintColor = [UIColor darkTextColor];
        
        _pickerStatusBarStyle = UIStatusBarStyleDefault;
        _barStyle = UIBarStyleDefault;
        // Save to the album
        

        
        
    }
    return self;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    // Ensure nav and toolbar customisations are set. Defaults are in place, but the user may have changed them
    self.view.backgroundColor = _pickerBackgroundColor;
    
    _navigationController.toolbar.translucent = YES;
    _navigationController.toolbar.barTintColor = _toolbarBarTintColor;
    _navigationController.toolbar.tintColor = _toolbarTintColor;
    [(UIView*)[_navigationController.toolbar.subviews firstObject] setAlpha:0.75f];  // URGH - I know!
    
    _navigationController.navigationBar.backgroundColor = _navigationBarBackgroundColor;
    _navigationController.navigationBar.tintColor = _navigationBarTintColor;
    
    _navigationController.navigationBar.barStyle = _barStyle;
    _navigationController.navigationBar.barTintColor = _toolbarBarTintColor;
    
    NSDictionary *attributes;
    if (_useCustomFontForNavigationBar) {
        attributes = @{NSForegroundColorAttributeName : _navigationBarTextColor,
                       NSFontAttributeName : [UIFont fontWithName:_pickerBoldFontName size:_pickerFontHeaderSize]};
    } else {
        attributes = @{NSForegroundColorAttributeName : _navigationBarTextColor};
    }
    _navigationController.navigationBar.titleTextAttributes = attributes;
    
    [self updateToolbar];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return _pickerStatusBarStyle;
}


#pragma mark - Setup Navigation Controller

//- (void)setupNavigationController
//{
//    GMAlbumsViewController *albumsViewController = [[GMAlbumsViewController alloc] init];
//    _navigationController = [[UINavigationController alloc] initWithRootViewController:albumsViewController];
//    _navigationController.delegate = self;
//    
//    _navigationController.navigationBar.translucent = YES;
//    [_navigationController.navigationBar setBackgroundImage:[UIImage new] forBarMetrics:UIBarMetricsDefault];
//    _navigationController.navigationBar.shadowImage = [UIImage new];
//    
//    [_navigationController willMoveToParentViewController:self];
//    [_navigationController.view setFrame:self.view.frame];
//    [self.view addSubview:_navigationController.view];
//    [self addChildViewController:_navigationController];
//    [_navigationController didMoveToParentViewController:self];
//    
//    if([self.delegate respondsToSelector:@selector(shouldSelectAllAlbumCell)]){
//        if([self.delegate respondsToSelector:@selector(controllerTitle)])
//            self.title = [self.delegate controllerTitle];
//        
//        if([self.delegate respondsToSelector:@selector(controllerCustomDoneButtonTitle)])
//            self.customDoneButtonTitle = [self.delegate controllerCustomDoneButtonTitle];
//        
//        if([self.delegate respondsToSelector:@selector(controllerCustomCancelButtonTitle)])
//            self.customCancelButtonTitle = [self.delegate controllerCustomCancelButtonTitle];
//        
//        if([self.delegate respondsToSelector:@selector(controllerCustomNavigationBarPrompt)])
//            self.customNavigationBarPrompt = [self.delegate controllerCustomNavigationBarPrompt];
//        
//        //        PHAuthorizationStatus authStatus = [PHPhotoLibrary authorizationStatus];
//        //        // Check if the user has access to photos
//        //        if (authStatus == PHAuthorizationStatusAuthorized) {
//        //            if([self.delegate shouldSelectAllAlbumCell]){
//        //                [albumsViewController selectAllAlbumsCell];
//        //            }
//        //        }
//    }
//}
- (void)setupNavigationController
{
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:0 inSection:0];
    
//    GMAlbumsViewController *albumsViewController = [[GMAlbumsViewController alloc] init];
//    if([self.delegate respondsToSelector:@selector(controllerTitle)]){
//        albumsViewController.title = [self.delegate controllerTitle];
//    }
    GMGridViewController *gridViewController = [[GMGridViewController alloc] initWithPicker:self];
//    gridViewController.title = NSLocalizedStringFromTableInBundle(@"picker.table.all-photos-label",  @"GMImagePicker", [NSBundle bundleForClass:GMImagePickerController.class], @"All photos");
    
    //All album: Sorted by descending creation date.
//    NSMutableArray *allFetchResultArray = [[NSMutableArray alloc] init];
//    NSMutableArray *allFetchResultLabel = [[NSMutableArray alloc] init];
//    {
//        if(![self.mediaTypes isEqual:[NSNull null]] && self != nil){
//            PHFetchOptions *options = [[PHFetchOptions alloc] init];
//            if(_allow_video){
//                _mediaTypes = @[@(PHAssetMediaTypeImage),@(PHAssetMediaTypeVideo)];
//            }
//            options.predicate = [NSPredicate predicateWithFormat:@"(mediaType in %@) AND !((mediaSubtype & %d) == %d)", self.mediaTypes, PHAssetMediaSubtypeVideoHighFrameRate, PHAssetMediaSubtypeVideoHighFrameRate ];
//            options.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:NO]];
//            PHFetchResult *assetsFetchResult = [PHAsset fetchAssetsWithOptions:options];
//
//            [allFetchResultArray addObject:assetsFetchResult];
//            [allFetchResultLabel addObject:NSLocalizedStringFromTableInBundle(@"picker.table.all-photos-label",  @"GMImagePicker", [NSBundle bundleForClass:GMImagePickerController.class], @"All photos")];
//        }
//    }
    
//    self.collectionsFetchResultsAssets= @[allFetchResultArray];
//    self.collectionsFetchResultsTitles= @[allFetchResultLabel];
//
    [self updateFetchResults];
    gridViewController.assetsFetchResults = [self.collectionsFetchResultsAssets objectAtIndex:indexPath.section];
    
    
//    _navigationController = [[UINavigationController alloc] initWithRootViewController:albumsViewController];
    _navigationController = [[UINavigationController alloc] initWithRootViewController:gridViewController];
    _navigationController.delegate = self;
    
    
    //    _navigationController.navigationBar.translucent = YES;
    //    [_navigationController.navigationBar setBackgroundImage:[UIImage new] forBarMetrics:UIBarMetricsDefault];
    //    _navigationController.navigationBar.shadowImage = [UIImage new];
    
    [_navigationController willMoveToParentViewController:self];
    [_navigationController.view setFrame:self.view.frame];
    [self.view addSubview:_navigationController.view];
    [self addChildViewController:_navigationController];
    [_navigationController didMoveToParentViewController:self];
    
    
    // Push GMGridViewController
//    [_navigationController pushViewController:gridViewController animated:YES];
    
    self.navBarMenu = [[MKDropdownMenu alloc] initWithFrame:CGRectMake(0, 0, 200, 44)];
    self.navBarMenu.dataSource = self;
    self.navBarMenu.delegate = self;
    
    // Make background light instead of dark when presenting the dropdown
    self.navBarMenu.backgroundDimmingOpacity = -0.67;
    
    // Set custom disclosure indicator image
    UIImage *indicator = [UIImage imageNamed:@"indicator"];
    self.navBarMenu.disclosureIndicatorImage = indicator;
    
    // Add an arrow between the menu header and the dropdown
    UIImageView *spacer = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"triangle"]];
    
    // Prevent the arrow image from stretching
    spacer.contentMode = UIViewContentModeCenter;
    
    self.navBarMenu.spacerView = spacer;
    
    // Offset the arrow to align with the disclosure indicator
    self.navBarMenu.spacerViewOffset = UIOffsetMake(self.navBarMenu.bounds.size.width/2 - indicator.size.width/2 - 8, 1);
    
    // Hide top row separator to blend with the arrow
    self.navBarMenu.dropdownShowsTopRowSeparator = NO;
    
    self.navBarMenu.dropdownBouncesScroll = NO;
    
    self.navBarMenu.rowSeparatorColor = [UIColor colorWithWhite:1.0 alpha:0.2];
    self.navBarMenu.rowTextAlignment = NSTextAlignmentCenter;
    
    // Round all corners (by default only bottom corners are rounded)
    self.navBarMenu.dropdownRoundedCorners = UIRectCornerAllCorners;
    
    // Let the dropdown take the whole width of the screen with 10pt insets
    self.navBarMenu.useFullScreenWidth = YES;
    self.navBarMenu.fullScreenInsetLeft = 10;
    self.navBarMenu.fullScreenInsetRight = 10;
    gridViewController.navigationItem.titleView = self.navBarMenu;
}
#pragma mark - PHPhotoLibraryChangeObserver

- (void)photoLibraryDidChange:(PHChange *)changeInstance
{
    // Call might come on any background queue. Re-dispatch to the main queue to handle it.
    dispatch_async(dispatch_get_main_queue(), ^{
        
        NSMutableArray *updatedCollectionsFetchResults = nil;
        
        for (PHFetchResult *collectionsFetchResult in self.collectionsFetchResults) {
            PHFetchResultChangeDetails *changeDetails = [changeInstance changeDetailsForFetchResult:collectionsFetchResult];
            if (changeDetails) {
                if (!updatedCollectionsFetchResults) {
                    updatedCollectionsFetchResults = [self.collectionsFetchResults mutableCopy];
                }
                [updatedCollectionsFetchResults replaceObjectAtIndex:[self.collectionsFetchResults indexOfObject:collectionsFetchResult] withObject:[changeDetails fetchResultAfterChanges]];
            }
        }
        
        // This only affects to changes in albums level (add/remove/edit album)
        if (updatedCollectionsFetchResults) {
            self.collectionsFetchResults = updatedCollectionsFetchResults;
            [self updateFetchResults];
//            [self.tableView reloadData];
        }
        
        // However, we want to update if photos are added, so the counts of items & thumbnails are updated too.
        // Maybe some checks could be done here , but for now is OKey.
        
        
    });
}
-(void)updateFetchResults
{
    // Fetch PHAssetCollections:
    PHFetchResult *topLevelUserCollections = [PHCollectionList fetchTopLevelUserCollectionsWithOptions:nil];
    PHFetchResult *smartAlbums = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeSmartAlbum subtype:PHAssetCollectionSubtypeAlbumRegular options:nil];
    PHFetchResult *myPhotoStream = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeAlbum subtype:PHAssetCollectionSubtypeAlbumMyPhotoStream options:nil];
    PHFetchResult *cloudShared = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeAlbum subtype:PHAssetCollectionSubtypeAlbumCloudShared options:nil];
    PHFetchResult *syncedAlbums = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeAlbum subtype:PHAssetCollectionSubtypeAlbumSyncedAlbum options:nil];
    
    self.collectionsFetchResults = @[topLevelUserCollections, myPhotoStream, cloudShared, smartAlbums,  syncedAlbums];
    //What I do here is fetch both the albums list and the assets of each album.
    //This way I have acces to the number of items in each album, I can load the 3
    //thumbnails directly and I can pass the fetched result to the gridViewController.
    
    NSMutableArray *newCollectionsFetchResultsAssets = [NSMutableArray array];
    NSMutableArray *newCollectionsFetchResultsTitles = [NSMutableArray array];
    
    self.collectionsFetchResultsAssets = nil;
    self.collectionsFetchResultsTitles = nil;
    
    //Fetch PHAssetCollections:
    //    self.collectionsFetchResults = @[topLevelUserCollections, myPhotoStreamAlbums, cloudSharedAlbums, smartAlbums,  syncedAlbums];
//    PHFetchResult *topLevelUserCollections = [self.collectionsFetchResults objectAtIndex:0];
//    PHFetchResult *myPhotoStream = [self.collectionsFetchResults objectAtIndex:1];
//    PHFetchResult *cloudShared = [self.collectionsFetchResults objectAtIndex:2];
//    PHFetchResult *smartAlbums = [self.collectionsFetchResults objectAtIndex:3];
//    PHFetchResult *syncedAlbum = [self.collectionsFetchResults objectAtIndex:4 ];
//
    //All album: Sorted by descending creation date.
//    NSMutableArray *allFetchResultArray = [[NSMutableArray alloc] init];
//    NSMutableArray *allFetchResultLabel = [[NSMutableArray alloc] init];
    {
        if(![self.mediaTypes isEqual:[NSNull null]] ){
            PHFetchOptions *options = [[PHFetchOptions alloc] init];
            options.predicate = [NSPredicate predicateWithFormat:@"(mediaType in %@) AND !((mediaSubtype & %d) == %d)", self.mediaTypes, PHAssetMediaSubtypeVideoHighFrameRate, PHAssetMediaSubtypeVideoHighFrameRate ];
            options.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:NO]];
            PHFetchResult *assetsFetchResult = [PHAsset fetchAssetsWithOptions:options];
            [newCollectionsFetchResultsAssets addObject:assetsFetchResult];
            [newCollectionsFetchResultsTitles addObject:NSLocalizedStringFromTableInBundle(@"picker.table.all-photos-label",  @"GMImagePicker", [NSBundle bundleForClass:GMImagePickerController.class], @"All photos")];
        }
    }
    
    //User albums:
//    NSMutableArray *userFetchResultArray = [[NSMutableArray alloc] init];
//    NSMutableArray *userFetchResultLabel = [[NSMutableArray alloc] init];
    for(PHCollection *collection in topLevelUserCollections)
    {
        if ([collection isKindOfClass:[PHAssetCollection class]])
        {
            if(![self.mediaTypes isEqual:[NSNull null]] ){
                PHFetchOptions *options = [[PHFetchOptions alloc] init];
                options.predicate = [NSPredicate predicateWithFormat:@"(mediaType in %@) AND !((mediaSubtype & %d) == %d)", self.mediaTypes, PHAssetMediaSubtypeVideoHighFrameRate, PHAssetMediaSubtypeVideoHighFrameRate ];
                PHAssetCollection *assetCollection = (PHAssetCollection *)collection;
                
                //Albums collections are allways PHAssetCollectionType=1 & PHAssetCollectionSubtype=2
                
                PHFetchResult *assetsFetchResult = [PHAsset fetchAssetsInAssetCollection:assetCollection options:options];
                [newCollectionsFetchResultsAssets addObject:assetsFetchResult];
                [newCollectionsFetchResultsTitles addObject:collection.localizedTitle];
            }
        }
    }
    
//    NSMutableArray *myPhotoStreamFetchResultArray = [[NSMutableArray alloc] init];
//    NSMutableArray *myPhotoStreamFetchResultLabel = [[NSMutableArray alloc] init];
    for(PHCollection *collection in myPhotoStream)
    {
        if ([collection isKindOfClass:[PHAssetCollection class]])
        {
            PHAssetCollection *assetCollection = (PHAssetCollection *)collection;
            
            PHFetchOptions *options = [[PHFetchOptions alloc] init];
            
            options.predicate = [NSPredicate predicateWithFormat:@"mediaType in %@", @[@(PHAssetMediaTypeImage)]];
            options.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:NO]];
            
            PHFetchResult *assetsFetchResult = [PHAsset fetchAssetsInAssetCollection:assetCollection options:options];
            if(assetsFetchResult.count>0)
            {
                [newCollectionsFetchResultsAssets addObject:assetsFetchResult];
                [newCollectionsFetchResultsTitles addObject:collection.localizedTitle];
            }
            
        }
    }
    
    
    //Smart albums: Sorted by descending creation date.
//    NSMutableArray *smartFetchResultArray = [[NSMutableArray alloc] init];
//    NSMutableArray *smartFetchResultLabel = [[NSMutableArray alloc] init];
    for(PHCollection *collection in smartAlbums)
    {
        if ([collection isKindOfClass:[PHAssetCollection class]])
        {
            PHAssetCollection *assetCollection = (PHAssetCollection *)collection;
            if(![self.mediaTypes isEqual:[NSNull null]] ){
                //Smart collections are PHAssetCollectionType=2;
                if(self.customSmartCollections && [self.customSmartCollections containsObject:@(assetCollection.assetCollectionSubtype)])
                {
                    PHFetchOptions *options = [[PHFetchOptions alloc] init];
                    options.predicate = [NSPredicate predicateWithFormat:@"(mediaType in %@) AND !((mediaSubtype & %d) == %d)", self.mediaTypes, PHAssetMediaSubtypeVideoHighFrameRate, PHAssetMediaSubtypeVideoHighFrameRate ];
                    options.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:NO]];
                    
                    PHFetchResult *assetsFetchResult = [PHAsset fetchAssetsInAssetCollection:assetCollection options:options];
                    if(assetsFetchResult.count>0)
                    {
                        [newCollectionsFetchResultsAssets addObject:assetsFetchResult];
                        [newCollectionsFetchResultsTitles addObject:collection.localizedTitle];
                    }
                }
            }
        }
    }
    
//    NSMutableArray *cloudSharedFetchResultArray = [[NSMutableArray alloc] init];
//    NSMutableArray *cloudSharedFetchResultLabel = [[NSMutableArray alloc] init];
    for(PHCollection *collection in cloudShared)
    {
        if ([collection isKindOfClass:[PHAssetCollection class]])
        {
            PHAssetCollection *assetCollection = (PHAssetCollection *)collection;
            
            PHFetchOptions *options = [[PHFetchOptions alloc] init];
            
            options.predicate = [NSPredicate predicateWithFormat:@"mediaType in %@", @[@(PHAssetMediaTypeImage)]];
            options.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:NO]];
            
            PHFetchResult *assetsFetchResult = [PHAsset fetchAssetsInAssetCollection:assetCollection options:options];
            if(assetsFetchResult.count>0)
            {
                [newCollectionsFetchResultsAssets addObject:assetsFetchResult];
                [newCollectionsFetchResultsTitles addObject:collection.localizedTitle];
            }
            
        }
    }
    
    
//    NSMutableArray *syncedAlbumFetchResultArray = [[NSMutableArray alloc] init];
//    NSMutableArray *syncedAlbumFetchResultLabel = [[NSMutableArray alloc] init];
    for(PHCollection *collection in syncedAlbums)
    {
        if ([collection isKindOfClass:[PHAssetCollection class]])
        {
            PHAssetCollection *assetCollection = (PHAssetCollection *)collection;
            
            PHFetchOptions *options = [[PHFetchOptions alloc] init];
            
            options.predicate = [NSPredicate predicateWithFormat:@"mediaType in %@", @[@(PHAssetMediaTypeImage)]];
            options.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:NO]];
            
            PHFetchResult *assetsFetchResult = [PHAsset fetchAssetsInAssetCollection:assetCollection options:options];
            if(assetsFetchResult.count>0)
            {
                [newCollectionsFetchResultsAssets addObject:assetsFetchResult];
                [newCollectionsFetchResultsTitles addObject:collection.localizedTitle];
            }
            
        }
    }
//    if([allFetchResultArray count ]>0)[newCollectionsFetchResultsAssets addObject:allFetchResultArray];
//    if([myPhotoStreamFetchResultArray count ]>0)[newCollectionsFetchResultsAssets addObject:myPhotoStreamFetchResultArray];
//    if([smartFetchResultArray count ]>0)[newCollectionsFetchResultsAssets addObject:smartFetchResultArray];
//    if([cloudSharedFetchResultArray count ]>0)[newCollectionsFetchResultsAssets addObject:cloudSharedFetchResultArray];
//    if([userFetchResultArray count ]>0)[newCollectionsFetchResultsAssets addObject:userFetchResultArray];
//    if([syncedAlbumFetchResultArray count ]>0)[newCollectionsFetchResultsAssets addObject:syncedAlbumFetchResultArray];
    self.collectionsFetchResultsAssets = [NSArray arrayWithArray:newCollectionsFetchResultsAssets]; //@[allFetchResultArray,myPhotoStreamFetchResultArray,smartFetchResultArray,cloudSharedFetchResultArray,userFetchResultArray,syncedAlbumFetchResultArray];
    
//    if([allFetchResultLabel count ]>0)[newCollectionsFetchResultsTitles addObject:allFetchResultLabel];
//    if([myPhotoStreamFetchResultLabel count ]>0)[newCollectionsFetchResultsTitles addObject:myPhotoStreamFetchResultLabel];
//    if([smartFetchResultLabel count ]>0)[newCollectionsFetchResultsTitles addObject:smartFetchResultLabel];
//    if([cloudSharedFetchResultLabel count ]>0)[newCollectionsFetchResultsTitles addObject:cloudSharedFetchResultLabel];
//    if([userFetchResultLabel count ]>0)[newCollectionsFetchResultsTitles addObject:userFetchResultLabel];
//    if([syncedAlbumFetchResultLabel count ]>0)[newCollectionsFetchResultsTitles addObject:syncedAlbumFetchResultLabel];
    self.collectionsFetchResultsTitles = [NSArray arrayWithArray:newCollectionsFetchResultsTitles];//  @[allFetchResultLabel,myPhotoStreamFetchResultLabel,smartFetchResultLabel,cloudSharedFetchResultLabel,userFetchResultLabel,syncedAlbumFetchResultLabel];
}

#pragma mark - MKDropdownMenuDataSource

- (NSInteger)numberOfComponentsInDropdownMenu:(MKDropdownMenu *)dropdownMenu {
    return 1;//self.collectionsFetchResultsAssets.count;
}

- (NSInteger)dropdownMenu:(MKDropdownMenu *)dropdownMenu numberOfRowsInComponent:(NSInteger)component {
    return [self.collectionsFetchResultsAssets count];
}

#pragma mark - MKDropdownMenuDelegate

- (CGFloat)dropdownMenu:(MKDropdownMenu *)dropdownMenu rowHeightForComponent:(NSInteger)component {
    return kAlbumRowHeight;
}

- (NSAttributedString *)dropdownMenu:(MKDropdownMenu *)dropdownMenu attributedTitleForComponent:(NSInteger)component {
    return [[NSAttributedString alloc] initWithString: self.collectionsFetchResultsTitles[self.selectedRow]
                                           attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:18 weight:UIFontWeightLight],
                                                        NSForegroundColorAttributeName: [UIColor darkGrayColor]}];
}
- (NSAttributedString *)dropdownMenu:(MKDropdownMenu *)dropdownMenu attributedTitleForSelectedComponent:(NSInteger)component {
    return [[NSAttributedString alloc] initWithString: self.collectionsFetchResultsTitles[self.selectedRow]
                                           attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:16 weight:UIFontWeightRegular],
                                                        NSForegroundColorAttributeName: self.view.tintColor}];
    
}

- (UIView *)dropdownMenu:(MKDropdownMenu *)dropdownMenu viewForRow:(NSInteger)row forComponent:(NSInteger)component reusingView:(UIView *)view {
    static NSString *CellIdentifier = @"Cell";
    GMAlbumsViewCell *cell = (GMAlbumsViewCell*)view;
//    if (cell == nil || ![cell isKindOfClass:[GMAlbumsViewCell class]]) {
//        cell = [[GMAlbumsViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellIdentifier];
//        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
//    }
//    GMAlbumsViewCell *cell = [view dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        cell = [[GMAlbumsViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellIdentifier];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    
    // Increment the cell's tag
    NSInteger currentTag = cell.tag + 1;
    cell.tag = currentTag;
    
    // Set the label
    ((GMAlbumsViewCell*)cell).titleLabel.font = [UIFont fontWithName:self.pickerFontName size:self.pickerFontHeaderSize];
    ((GMAlbumsViewCell*)cell).titleLabel.text = self.collectionsFetchResultsTitles[row];
    ((GMAlbumsViewCell*)cell).titleLabel.textColor = self.pickerTextColor;
    
    // Retrieve the pre-fetched assets for this album:
    PHFetchResult *assetsFetchResult = (self.collectionsFetchResultsAssets[row]);
    
    // Display the number of assets
    if (self.displayAlbumsNumberOfAssets) {
        cell.infoLabel.font = [UIFont fontWithName:self.pickerFontName size:self.pickerFontNormalSize];
        cell.infoLabel.text = [NSString stringWithFormat:@"%ld", (long)[assetsFetchResult count]];
        cell.infoLabel.textColor = self.pickerTextColor;
    }
    
    // Set the 3 images (if exists):
    if ([assetsFetchResult count] > 0) {
        CGFloat scale = [UIScreen mainScreen].scale;
        
        //Compute the thumbnail pixel size:
        CGSize tableCellThumbnailSize1 = CGSizeMake(kAlbumThumbnailSize1.width*scale, kAlbumThumbnailSize1.height*scale);
        PHAsset *asset = assetsFetchResult[0];
        [cell setVideoLayout:(asset.mediaType==PHAssetMediaTypeVideo)];
        [self.imageManager requestImageForAsset:asset
                                     targetSize:tableCellThumbnailSize1
                                    contentMode:PHImageContentModeAspectFill
                                        options:nil
                                  resultHandler:^(UIImage *result, NSDictionary *info) {
                                      if (cell.tag == currentTag) {
                                          cell.imageView1.image = result;
                                      }
                                  }];
        
        // Second & third images:
        // TODO: Only preload the 3pixels height visible frame!
        if ([assetsFetchResult count] > 1) {
            //Compute the thumbnail pixel size:
            CGSize tableCellThumbnailSize2 = CGSizeMake(kAlbumThumbnailSize2.width*scale, kAlbumThumbnailSize2.height*scale);
            PHAsset *asset = assetsFetchResult[1];
            [self.imageManager requestImageForAsset:asset
                                         targetSize:tableCellThumbnailSize2
                                        contentMode:PHImageContentModeAspectFill
                                            options:nil
                                      resultHandler:^(UIImage *result, NSDictionary *info) {
                                          if (cell.tag == currentTag) {
                                              cell.imageView2.image = result;
                                          }
                                      }];
        } else {
            cell.imageView2.image = nil;
        }
        
        if ([assetsFetchResult count] > 2) {
            CGSize tableCellThumbnailSize3 = CGSizeMake(kAlbumThumbnailSize3.width*scale, kAlbumThumbnailSize3.height*scale);
            PHAsset *asset = assetsFetchResult[2];
            [self.imageManager requestImageForAsset:asset
                                         targetSize:tableCellThumbnailSize3
                                        contentMode:PHImageContentModeAspectFill
                                            options:nil
                                      resultHandler:^(UIImage *result, NSDictionary *info) {
                                          if (cell.tag == currentTag) {
                                              cell.imageView3.image = result;
                                          }
                                      }];
        } else {
            cell.imageView3.image = nil;
        }
    } else {
        [cell setVideoLayout:NO];
        cell.imageView3.image = [UIImage imageNamed:@"GMEmptyFolder"];
        cell.imageView2.image = [UIImage imageNamed:@"GMEmptyFolder"];
        cell.imageView1.image = [UIImage imageNamed:@"GMEmptyFolder"];
    }
    
    return cell;
}
//- (NSAttributedString *)dropdownMenu:(MKDropdownMenu *)dropdownMenu attributedTitleForRow:(NSInteger)row forComponent:(NSInteger)component {
//    NSMutableAttributedString *string =
//    [[NSMutableAttributedString alloc] initWithString: [NSString stringWithFormat:@"Color %zd: ", row + 1]
//                                           attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:20 weight:UIFontWeightLight],
//                                                        NSForegroundColorAttributeName: [UIColor darkGrayColor]}];
//    [string appendAttributedString:
//     [[NSAttributedString alloc] initWithString:@""
//                                     attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:20 weight:UIFontWeightMedium],
//                                                  NSForegroundColorAttributeName: [UIColor darkGrayColor]}]];
//    return string;
//}

//- (UIColor *)dropdownMenu:(MKDropdownMenu *)dropdownMenu backgroundColorForRow:(NSInteger)row forComponent:(NSInteger)component {
//    return UIColorWithHexString(self.colors[row]);
//}

- (UIColor *)dropdownMenu:(MKDropdownMenu *)dropdownMenu backgroundColorForHighlightedRowsInComponent:(NSInteger)component {
    return [UIColor colorWithWhite:0.0 alpha:0.5];
}


- (void)dropdownMenu:(MKDropdownMenu *)dropdownMenu didSelectRow:(NSInteger)row inComponent:(NSInteger)component {
//    NSString *colorString = self.colors[row];
//    self.textLabel.text = colorString;
//
//    UIColor *color = UIColorWithHexString(colorString);
//    self.view.backgroundColor = color;
//    self.childViewController.shapeView.strokeColor = color;
//
    
    
    GMGridViewController *gridViewController = (GMGridViewController *)self.navigationController.childViewControllers[0];
    gridViewController.assetsFetchResults = [self.collectionsFetchResultsAssets objectAtIndex:row];
    [gridViewController reloadData];
    self.selectedRow = row;
    delay(0.15, ^{
        [dropdownMenu closeAllComponentsAnimated:YES];
        [dropdownMenu reloadAllComponents];
    });
}

#pragma mark - UIAlertViewDelegate

-(void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex
{
    if (buttonIndex == 1) {
        // Only if OK was pressed do we want to completge the selection
        [self finishPickingAssets:self];
    }
}


#pragma mark - Select / Deselect Asset

- (void)selectAsset:(PHAsset *)asset
{
    [self.selectedAssets insertObject:asset atIndex:self.selectedAssets.count];
    [self updateDoneButton];
    
    if (!self.allowsMultipleSelection) {
        if (self.confirmSingleSelection) {
            NSString *message = self.confirmSingleSelectionPrompt ? self.confirmSingleSelectionPrompt : [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"picker.confirm.message",  @"GMImagePicker", [NSBundle bundleForClass:GMImagePickerController.class],  @"Do you want to select the image you tapped on?")];
            
            [[[UIAlertView alloc] initWithTitle:[NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"picker.confirm.title",  @"GMImagePicker", [NSBundle bundleForClass:GMImagePickerController.class],  @"Are You Sure?")]
                                        message:message
                                       delegate:self
                              cancelButtonTitle:[NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"picker.action.no",  @"GMImagePicker", [NSBundle bundleForClass:GMImagePickerController.class],  @"No")]
                              otherButtonTitles:[NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"picker.action.yes",  @"GMImagePicker", [NSBundle bundleForClass:GMImagePickerController.class],  @"Yes")], nil] show];
        } else {
            [self finishPickingAssets:self];
        }
    } else if (self.displaySelectionInfoToolbar || self.showCameraButton) {
        [self updateToolbar];
    }
}

- (void)deselectAsset:(PHAsset *)asset
{
    [self.selectedAssets removeObjectAtIndex:[self.selectedAssets indexOfObject:asset]];
    if (self.selectedAssets.count == 0) {
        [self updateDoneButton];
    }
    
    if (self.displaySelectionInfoToolbar || self.showCameraButton) {
        [self updateToolbar];
    }
}

- (void)updateDoneButton
{
    if (!self.allowsMultipleSelection || self.disableRightTopDoneButton) {
        return;
    }
    
    UINavigationController *nav = (UINavigationController *)self.childViewControllers[0];
    for (UIViewController *viewController in nav.viewControllers) {
        viewController.navigationItem.rightBarButtonItem.enabled = (self.autoDisableDoneButton ? self.selectedAssets.count > 0 : TRUE);
    }
}

- (void)updateToolbar
{
    if (!self.allowsMultipleSelection && !self.showCameraButton) {
        return;
    }
    
    UINavigationController *nav = (UINavigationController *)self.childViewControllers[0];
    for (UIViewController *viewController in nav.viewControllers) {
        NSUInteger index = 1;
        if (_showCameraButton) {
            index++;
        }
        [[viewController.toolbarItems objectAtIndex:index] setTitleTextAttributes:[self toolbarTitleTextAttributes] forState:UIControlStateNormal];
        [[viewController.toolbarItems objectAtIndex:index] setTitleTextAttributes:[self toolbarTitleTextAttributes] forState:UIControlStateDisabled];
        [[viewController.toolbarItems objectAtIndex:index] setTitle:[self toolbarTitle]];
        [viewController.navigationController setToolbarHidden:(self.selectedAssets.count == 0 && !self.showCameraButton) animated:YES];
    }
}


#pragma mark - User finish Actions

- (void)dismiss:(id)sender
{
    if ([self.delegate respondsToSelector:@selector(assetsPickerControllerDidCancel:)]) {
        [self.delegate assetsPickerControllerDidCancel:self];
    }
    
    [self.presentingViewController dismissViewControllerAnimated:YES completion:nil];
}


- (void)finishPickingAssets:(id)sender
{
    if ([self.delegate respondsToSelector:@selector(assetsPickerController:didFinishPickingAssets:)]) {
        [self.delegate assetsPickerController:self didFinishPickingAssets:self.selectedAssets];
    }
}


#pragma mark - Toolbar Title

- (NSPredicate *)predicateOfAssetType:(PHAssetMediaType)type
{
    return [NSPredicate predicateWithBlock:^BOOL(PHAsset *asset, NSDictionary *bindings) {
        return (asset.mediaType == type);
    }];
}

- (NSString *)toolbarTitle
{
    if (self.selectedAssets.count == 0) {
        return nil;
    }
    
    NSPredicate *photoPredicate = [self predicateOfAssetType:PHAssetMediaTypeImage];
    NSPredicate *videoPredicate = [self predicateOfAssetType:PHAssetMediaTypeVideo];
    
    NSInteger nImages = [self.selectedAssets filteredArrayUsingPredicate:photoPredicate].count;
    NSInteger nVideos = [self.selectedAssets filteredArrayUsingPredicate:videoPredicate].count;
    
    if (nImages > 0 && nVideos > 0) {
        return [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"picker.selection.multiple-items",  @"GMImagePicker", [NSBundle bundleForClass:GMImagePickerController.class],  @"%@ Items Selected" ), @(nImages + nVideos)];
    } else if (nImages > 1) {
        return [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"picker.selection.multiple-photos",  @"GMImagePicker", [NSBundle bundleForClass:GMImagePickerController.class],  @"%@ Photos Selected"), @(nImages)];
    } else if (nImages == 1) {
        return NSLocalizedStringFromTableInBundle(@"picker.selection.single-photo",  @"GMImagePicker", [NSBundle bundleForClass:GMImagePickerController.class],  @"1 Photo Selected" );
    } else if (nVideos > 1) {
        return [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"picker.selection.multiple-videos",  @"GMImagePicker", [NSBundle bundleForClass:GMImagePickerController.class],  @"%@ Videos Selected"), @(nVideos)];
    } else if (nVideos == 1) {
        return NSLocalizedStringFromTableInBundle(@"picker.selection.single-video",  @"GMImagePicker", [NSBundle bundleForClass:GMImagePickerController.class],  @"1 Video Selected");
    } else {
        return nil;
    }
}


#pragma mark - Toolbar Items

- (void)cameraButtonPressed:(UIBarButtonItem *)button
{
    if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) {
        
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"No Camera!"
                                                                       message:@"Sorry, this device does not have a camera."
                                                                preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction * okAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil)
                                                            style:UIAlertActionStyleDefault
                                                          handler:^(UIAlertAction * _Nonnull action) {
                                                              [alert dismissViewControllerAnimated:YES completion:nil];
                                                          }];
        [alert addAction:okAction];
        
        return;
    }
    
    // This allows the selection of the image taken to be better seen if the user is not already in that VC
    if (self.autoSelectCameraImages && [self.navigationController.topViewController isKindOfClass:[GMAlbumsViewController class]]) {
        [((GMAlbumsViewController *)self.navigationController.topViewController) selectAllAlbumsCell];
    }
    
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.sourceType = UIImagePickerControllerSourceTypeCamera;
//    picker.videoMaximumDuration = self.videoMaximumDuration;
    if(_allow_video){
        picker.mediaTypes = @[(NSString *)kUTTypeImage,(NSString *)kUTTypeMovie];
        picker.videoQuality = UIImagePickerControllerQualityTypeHigh;
    }else{
        picker.mediaTypes = @[(NSString *)kUTTypeImage];
    }
    picker.allowsEditing = self.allowsEditingCameraImages;

    picker.delegate = self;
    picker.modalPresentationStyle = UIModalPresentationPopover;
    
    UIPopoverPresentationController *popPC = picker.popoverPresentationController;
    popPC.permittedArrowDirections = UIPopoverArrowDirectionAny;
    popPC.barButtonItem = button;
    
    [self showViewController:picker sender:button];
}

- (NSDictionary *)toolbarTitleTextAttributes {
    return @{NSForegroundColorAttributeName : _toolbarTextColor,
             NSFontAttributeName : [UIFont fontWithName:_pickerFontName size:_pickerFontHeaderSize]};
}

- (UIBarButtonItem *)titleButtonItem
{
    UIBarButtonItem *title = [[UIBarButtonItem alloc] initWithTitle:self.toolbarTitle
                                                              style:UIBarButtonItemStylePlain
                                                             target:nil
                                                             action:nil];
    
    NSDictionary *attributes = [self toolbarTitleTextAttributes];
    [title setTitleTextAttributes:attributes forState:UIControlStateNormal];
    [title setTitleTextAttributes:attributes forState:UIControlStateDisabled];
    [title setEnabled:NO];
    
    return title;
}

- (UIBarButtonItem *)spaceButtonItem
{
    return [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
}

- (UIBarButtonItem *)cameraButtonItem
{
    return [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCamera target:self action:@selector(cameraButtonPressed:)];
}

- (UIBarButtonItem *)doneButtonItem
{
    return [[UIBarButtonItem alloc] initWithTitle:@"Done" style:UIBarButtonItemStyleDone target:self action:@selector(finishPickingAssets:)];
}

- (NSArray *)toolbarItems
{
    UIBarButtonItem *camera = [self cameraButtonItem];
    UIBarButtonItem *title  = [self titleButtonItem];
    UIBarButtonItem *space  = [self spaceButtonItem];
    UIBarButtonItem *done  = [self doneButtonItem];
    
    NSMutableArray *items = [[NSMutableArray alloc] init];
    
    if (_showCameraButton) {//&& ([[self.navigationController childViewControllers] count] > 1) ) {
        [items addObject:camera];
    }
    [items addObject:space];
    [items addObject:title];
    [items addObject:space];
    [items addObject:done];
    
    return [NSArray arrayWithArray:items];
}


#pragma mark - Camera Delegate

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<NSString *,id> *)info
{
    [picker.presentingViewController dismissViewControllerAnimated:YES completion:nil];
    
    NSString *mediaType = info[UIImagePickerControllerMediaType];
    if ([mediaType isEqualToString:(NSString *)kUTTypeImage]) {
        UIImage *image = info[UIImagePickerControllerEditedImage] ? : info[UIImagePickerControllerOriginalImage];
        UIImageWriteToSavedPhotosAlbum(image,
                                       self,
                                       @selector(image:finishedSavingWithError:contextInfo:),
                                       nil);
    }else if ([mediaType isEqualToString:(NSString *)kUTTypeMovie]) {
        __block NSURL *movieUrl = info[UIImagePickerControllerMediaURL];
        dispatch_semaphore_t sema = dispatch_semaphore_create(0);
        
        if ([PHObject class]) {
            __block PHAssetChangeRequest *assetRequest;
            __block PHObjectPlaceholder *placeholder;
            // Save to the album
            [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
                
                [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
                    
                    
                    assetRequest = [PHAssetChangeRequest creationRequestForAssetFromVideoAtFileURL:movieUrl];
                    placeholder = [assetRequest placeholderForCreatedAsset];
                } completionHandler:^(BOOL success, NSError *error) {
                    if (success) {
                        
                        NSLog(@"localIdentifier %@", placeholder.localIdentifier);
                        
                        dispatch_semaphore_signal(sema);
                    }
                    else {
                        NSLog(@"%@", error);
                        dispatch_semaphore_signal(sema);
                    }
                }];
                
            }];
        }
    }
}

-(void)imagePickerControllerDidCancel:(UIImagePickerController *)picker
{
    [picker.presentingViewController dismissViewControllerAnimated:YES completion:nil];
}

-(void)image:(UIImage *)image finishedSavingWithError:(NSError *)error contextInfo:(void *)contextInfo
{
    if (error) {

        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Image Not Saved"
                                                                       message:@"Sorry, this device does not have a camera."
                                                                preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction * okAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil)
                                                            style:UIAlertActionStyleDefault
                                                          handler:^(UIAlertAction * _Nonnull action) {
                                                              [alert dismissViewControllerAnimated:YES completion:nil];
                                                          }];
        [alert addAction:okAction];
    }
    
    // Note: The image view will auto refresh as the photo's are being observed in the other VCs
}


- (BOOL)shouldAutorotate
{
    if ([self.delegate respondsToSelector:@selector(shouldAutorotate)]) {
        return [self.delegate shouldAutorotate];
    }
    return NO;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    if ([self.delegate respondsToSelector:@selector(supportedInterfaceOrientations)]) {
        return [self.delegate supportedInterfaceOrientations];
    }
    return 1 << UIInterfaceOrientationPortrait;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    if ([self.delegate respondsToSelector:@selector(shouldAutorotateToInterfaceOrientation:)]) {
        return [self.delegate shouldAutorotateToInterfaceOrientation:interfaceOrientation];
    }
    return (interfaceOrientation == UIInterfaceOrientationPortrait);
    
}
@end
