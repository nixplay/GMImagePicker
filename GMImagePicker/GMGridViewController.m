//
//  GMGridViewController.m
//  GMPhotoPicker
//
//  Created by Guillermo Muntaner Perelló on 19/09/14.
//  Copyright (c) 2014 Guillermo Muntaner Perelló. All rights reserved.
//

#import "GMGridViewController.h"
#import "GMImagePickerController.h"
#import "GMAlbumsViewController.h"
#import "GMGridViewCell.h"

#define SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(v)  ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] != NSOrderedAscending)

@import Photos;


//Helper methods
//@implementation NSIndexSet (Convenience)
//- (NSArray *)aapl_indexPathsFromIndexesWithSection:(NSUInteger)section {
//    NSMutableArray *indexPaths = [NSMutableArray arrayWithCapacity:self.count];
//    [self enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
//        [indexPaths addObject:[NSIndexPath indexPathForItem:idx inSection:section]];
//    }];
//    return indexPaths;
//}
//@end

@implementation UICollectionView (Convenience)
- (NSArray *)aapl_indexPathsForElementsInRect:(CGRect)rect {
    NSArray *allLayoutAttributes = [self.collectionViewLayout layoutAttributesForElementsInRect:rect];
    if (allLayoutAttributes.count == 0) { return nil; }
    NSMutableArray *indexPaths = [NSMutableArray arrayWithCapacity:allLayoutAttributes.count];
    for (UICollectionViewLayoutAttributes *layoutAttributes in allLayoutAttributes) {
        NSIndexPath *indexPath = layoutAttributes.indexPath;
        [indexPaths addObject:indexPath];
    }
    return indexPaths;
}
@end



@interface GMImagePickerController ()

- (void)finishPickingAssets:(id)sender;
- (void)dismiss:(id)sender;
- (NSString *)toolbarTitle;
- (UIView *)noAssetsView;

@end


@interface GMGridViewController () <PHPhotoLibraryChangeObserver>

@property (nonatomic, weak) GMImagePickerController *picker;
@property (nonatomic, weak) NSString *albumLabel;
@property (strong) PHCachingImageManager *imageManager;
@property (strong) PHImageRequestOptions *imageRequestOptions;
@property CGRect previousPreheatRect;
@property dispatch_semaphore_t phPhotoLibChageMutex;
@end

static CGSize AssetGridThumbnailSize;
NSString * const GMGridViewCellIdentifier = @"GMGridViewCellIdentifier";
NSString * const CameraCellIdentifier = @"CameraCellIdentifier";

@implementation GMGridViewController
{
    CGFloat screenWidth;
    CGFloat screenHeight;
    UICollectionViewFlowLayout *portraitLayout;
    UICollectionViewFlowLayout *landscapeLayout;
    // Store margins for current setup
    CGFloat _margin, _gutter, _marginL, _gutterL, _columns, _columnsL;
}

-(id)initWithPicker:(GMImagePickerController *)picker
{
    self.phPhotoLibChageMutex = dispatch_semaphore_create(1);
    _columns = 4, _columnsL = 4;
    _margin = 0, _gutter = 1;
    _marginL = 0, _gutterL = 1;
    
    // For pixel perfection...
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        // iPad
        _columns = 6, _columnsL = 8;
        _margin = 1, _gutter = 2;
        _marginL = 1, _gutterL = 2;
    } else if ([UIScreen mainScreen].bounds.size.height == 480) {
        // iPhone 3.5 inch
        _columns = 3, _columnsL = 4;
        _margin = 0, _gutter = 1;
        _marginL = 1, _gutterL = 2;
    } else {
        // iPhone 4 inch
        _columns = 3, _columnsL = 5;
        _margin = 0, _gutter = 1;
        _marginL = 0, _gutterL = 2;
    }
    
    //Custom init. The picker contains custom information to create the FlowLayout
    self.picker = picker;
    
    //Ipad popover is not affected by rotation!
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad)
    {
        screenWidth = CGRectGetWidth(picker.view.bounds);
        screenHeight = CGRectGetHeight(picker.view.bounds);
    }
    else
    {
        if(UIInterfaceOrientationIsLandscape([UIApplication sharedApplication].statusBarOrientation))
        {
            screenHeight = CGRectGetWidth(picker.view.bounds);
            screenWidth = CGRectGetHeight(picker.view.bounds);
        }
        else
        {
            screenWidth = CGRectGetWidth(picker.view.bounds);
            screenHeight = CGRectGetHeight(picker.view.bounds);
        }
    }
    
    
    UICollectionViewFlowLayout *layout = [self collectionViewFlowLayoutForOrientation:[UIApplication sharedApplication].statusBarOrientation];
    if (self = [super initWithCollectionViewLayout:layout])
    {
        //Compute the thumbnail pixel size:
        CGFloat scale = [UIScreen mainScreen].scale;
        //NSLog(@"This is @%fx scale device", scale);
        NSOperatingSystemVersion ios10_0_1 = (NSOperatingSystemVersion){10, 0, 1};
        if([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad){
            if ([[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:ios10_0_1]) {
                // iOS 8.0.1 and above logic
                AssetGridThumbnailSize = CGSizeMake(layout.itemSize.width * scale, layout.itemSize.height * scale);
            } else {
                // iOS 8.0.0 and below logic
                AssetGridThumbnailSize = CGSizeMake(layout.itemSize.width * scale*0.5, layout.itemSize.height * scale*0.5);
            }
            
        }else{
            AssetGridThumbnailSize = CGSizeMake(layout.itemSize.width * scale, layout.itemSize.height * scale);
        }
        
        self.collectionView.allowsMultipleSelection = picker.allowsMultipleSelection;
        
        [self.collectionView registerClass:[UICollectionViewCell class] forCellWithReuseIdentifier:CameraCellIdentifier];
        [self.collectionView registerClass:GMGridViewCell.class
                forCellWithReuseIdentifier:GMGridViewCellIdentifier];
        
        self.preferredContentSize = kPopoverContentSize;
    }
    
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self setupViews];
    
    // Navigation bar customization
    if (self.picker.customNavigationBarPrompt) {
        self.navigationItem.prompt = self.picker.customNavigationBarPrompt;
    }
    
    self.imageManager = [[PHCachingImageManager alloc] init];
    // This keeps memory usage to a sensible size when working with large photo collections.
    self.imageManager.allowsCachingHighQualityImages = NO;
    
    // The same applies to our PHImageRequestOptions.
    // PHImageRequestOptionsDeliveryModeOpportunistic is a good compromise: it provides a lower quality image quickly
    // and then a higher quality image later, without excessive memory usage.
    self.imageRequestOptions = [[PHImageRequestOptions alloc] init];
    self.imageRequestOptions.deliveryMode = PHImageRequestOptionsDeliveryModeOpportunistic;
    self.imageRequestOptions.resizeMode = PHImageRequestOptionsResizeModeFast;
    self.imageRequestOptions.synchronous = NO;
    self.imageRequestOptions.networkAccessAllowed = YES;
    
    
    [self resetCachedAssets];
    
    if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
    {
        self.edgesForExtendedLayout = UIRectEdgeNone;
    }

    self.albumLabel = NSLocalizedStringFromTableInBundle(@"picker.table.all-photos-label",  @"GMImagePicker", [NSBundle bundleForClass:GMImagePickerController.class], @"All photos");
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    [self setupButtons];
    [self setupToolbar];
    [[PHPhotoLibrary sharedPhotoLibrary] registerChangeObserver:self];
}
- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    
    [[PHPhotoLibrary sharedPhotoLibrary] unregisterChangeObserver:self];
}
- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [self updateCachedAssets];
}

- (void)dealloc
{
    [self resetCachedAssets];
    [[PHPhotoLibrary sharedPhotoLibrary] unregisterChangeObserver:self];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return self.picker.pickerStatusBarStyle;
}


#pragma mark - Rotation

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator
{
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        return;
    }
    
    UIInterfaceOrientation toInterfaceOrientation = (size.height > size.width ? UIInterfaceOrientationPortrait
                                                     : UIInterfaceOrientationLandscapeLeft);
    
    UICollectionViewFlowLayout *layout = [self collectionViewFlowLayoutForOrientation:toInterfaceOrientation];
    
    //Update the AssetGridThumbnailSize:
    CGFloat scale = [UIScreen mainScreen].scale;
    NSOperatingSystemVersion ios10_0_1 = (NSOperatingSystemVersion){10, 0, 1};
    if([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad){
        if ([[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:ios10_0_1]) {
            // iOS 8.0.1 and above logic
            AssetGridThumbnailSize = CGSizeMake(layout.itemSize.width * scale, layout.itemSize.height * scale);
        } else {
            // iOS 8.0.0 and below logic
            AssetGridThumbnailSize = CGSizeMake(layout.itemSize.width * scale*0.5, layout.itemSize.height * scale*0.5);
        }
        
    }else{
        AssetGridThumbnailSize = CGSizeMake(layout.itemSize.width * scale, layout.itemSize.height * scale);
    }
    
    [self resetCachedAssets];
    
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        //This is optional. Reload visible thumbnails:
        for (GMGridViewCell *cell in [self.collectionView visibleCells]) {
            NSInteger currentTag = cell.tag;
            
            
            PHImageRequestID requestID=  [self.imageManager requestImageForAsset:cell.asset
                                                                      targetSize:AssetGridThumbnailSize
                                                                     contentMode:PHImageContentModeAspectFill
                                                                         options:self.imageRequestOptions
                                                                   resultHandler:^(UIImage *result, NSDictionary *info) {
                                                                       // Only update the thumbnail if the cell tag hasn't changed. Otherwise, the cell has been re-used.
                                                                       dispatch_async(dispatch_get_main_queue(), ^{
                                                                           if (cell.tag == currentTag) {
                                                                               [cell.imageView setImage:result];
                                                                           }
                                                                       });

                                                                   }];
            if(requestID != cell.assetRequestID){
                if ([cell isKindOfClass:[GMGridViewCell class]]) {
                    [cell cancelImageRequest];
                }
                cell.assetRequestID = requestID;
            }
            
        }
        
        [self.collectionView setCollectionViewLayout:layout animated:NO];
    } completion:nil];
}

#pragma mark - Setup

- (void)setupViews
{
    self.collectionView.backgroundColor = [UIColor clearColor];
    self.view.backgroundColor = [self.picker pickerBackgroundColor];
}

- (void)setupButtons
{
    if (self.picker.allowsMultipleSelection) {
        NSString *doneTitle = self.picker.customDoneButtonTitle ? self.picker.customDoneButtonTitle : (
                                                                                                       self.picker.selectedAssets.count > 0 ?
                                                                                                       NSLocalizedStringFromTableInBundle(@"picker.navigation.done-button",  @"GMImagePicker", [NSBundle bundleForClass:GMImagePickerController.class], @"Done") :
                                                                                                       NSLocalizedStringFromTableInBundle(@"picker.navigation.cancel-button",  @"GMImagePicker", [NSBundle bundleForClass:GMImagePickerController.class], @"Cancel"));
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:doneTitle
                                                                                  style:UIBarButtonItemStyleDone
                                                                                 target:self.picker
                                                                                 action:@selector(finishPickingAssets:)];
        self.navigationItem.rightBarButtonItem.accessibilityIdentifier = @"done";
        self.navigationItem.rightBarButtonItem.enabled = (self.picker.autoDisableDoneButton ? self.picker.selectedAssets.count > 0 : TRUE);
    } else {
        NSString *cancelTitle = self.picker.customCancelButtonTitle ? self.picker.customCancelButtonTitle : NSLocalizedStringFromTableInBundle(@"picker.navigation.cancel-button",  @"GMImagePicker", [NSBundle bundleForClass:GMImagePickerController.class], @"Cancel");
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:cancelTitle
                                                                                  style:UIBarButtonItemStyleDone
                                                                                 target:self.picker
                                                                                 action:@selector(dismiss:)];
        self.navigationItem.rightBarButtonItem.accessibilityIdentifier = @"cancel";
    }
    if (self.picker.useCustomFontForNavigationBar) {
        if (self.picker.useCustomFontForNavigationBar) {
            NSDictionary* barButtonItemAttributes = @{NSFontAttributeName: [UIFont fontWithName:self.picker.pickerFontName size:self.picker.pickerFontHeaderSize]};
            [self.navigationItem.rightBarButtonItem setTitleTextAttributes:barButtonItemAttributes forState:UIControlStateNormal];
            [self.navigationItem.rightBarButtonItem setTitleTextAttributes:barButtonItemAttributes forState:UIControlStateSelected];
        }
    }
    
}

- (void)setupToolbar
{
    self.toolbarItems = self.picker.toolbarItems;
}


#pragma mark - Collection View Layout
- (void)viewSafeAreaInsetsDidChange {
    [super viewSafeAreaInsetsDidChange];
    UIEdgeInsets contentInset = self.collectionView.contentInset;
    contentInset.left = self.view.safeAreaInsets.left;
    contentInset.right = self.view.safeAreaInsets.right;
    self.collectionView.contentInset = contentInset;
}

- (UICollectionViewFlowLayout *)collectionViewFlowLayoutForOrientation:(UIInterfaceOrientation)orientation
{
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad)
    {
        if(!portraitLayout)
        {
            portraitLayout = [[UICollectionViewFlowLayout alloc] init];
            portraitLayout.minimumInteritemSpacing = self.picker.minimumInteritemSpacing;
            int cellTotalUsableWidth = screenWidth - (self.picker.colsInPortrait-1)*self.picker.minimumInteritemSpacing;
            portraitLayout.itemSize = CGSizeMake(cellTotalUsableWidth/self.picker.colsInPortrait, cellTotalUsableWidth/self.picker.colsInPortrait);
            double cellTotalUsedWidth = (double)portraitLayout.itemSize.width*self.picker.colsInPortrait;
            double spaceTotalWidth = (double)screenWidth-cellTotalUsedWidth;
            double spaceWidth = spaceTotalWidth/(double)(self.picker.colsInPortrait-1);
            portraitLayout.minimumLineSpacing = spaceWidth;
        }
        return portraitLayout;
    }
    else
    {
        if(UIInterfaceOrientationIsLandscape(orientation))
        {
            if(!landscapeLayout)
            {
                landscapeLayout = [[UICollectionViewFlowLayout alloc] init];
                landscapeLayout.minimumInteritemSpacing = self.picker.minimumInteritemSpacing;
                int cellTotalUsableWidth = screenHeight - (self.picker.colsInLandscape-1)*self.picker.minimumInteritemSpacing;
                landscapeLayout.itemSize = CGSizeMake(cellTotalUsableWidth/self.picker.colsInLandscape, cellTotalUsableWidth/self.picker.colsInLandscape);
                double cellTotalUsedWidth = (double)landscapeLayout.itemSize.width*self.picker.colsInLandscape;
                double spaceTotalWidth = (double)screenHeight-cellTotalUsedWidth;
                double spaceWidth = spaceTotalWidth/(double)(self.picker.colsInLandscape-1);
                landscapeLayout.minimumLineSpacing = spaceWidth;
            }
            return landscapeLayout;
        }
        else
        {
            if(!portraitLayout)
            {
                portraitLayout = [[UICollectionViewFlowLayout alloc] init];
                portraitLayout.minimumInteritemSpacing = self.picker.minimumInteritemSpacing;
                int cellTotalUsableWidth = screenWidth - (self.picker.colsInPortrait-1)*self.picker.minimumInteritemSpacing;
                portraitLayout.itemSize = CGSizeMake(cellTotalUsableWidth/self.picker.colsInPortrait, cellTotalUsableWidth/self.picker.colsInPortrait);
                double cellTotalUsedWidth = (double)portraitLayout.itemSize.width*self.picker.colsInPortrait;
                double spaceTotalWidth = (double)screenWidth-cellTotalUsedWidth;
                double spaceWidth = spaceTotalWidth/(double)(self.picker.colsInPortrait-1);
                portraitLayout.minimumLineSpacing = spaceWidth;
            }
            return portraitLayout;
        }
    }
}


#pragma mark - Collection View Data Source

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView
{
    return 1;
}


- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    if ([self.title isEqualToString:self.albumLabel] && self.picker.showCameraButton) {
        if (indexPath.row) {
            NSIndexPath *newIndexPath = [NSIndexPath indexPathForRow:indexPath.row-1 inSection:0];

            __block GMGridViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:GMGridViewCellIdentifier
                                                                                     forIndexPath:newIndexPath];

            // Increment the cell's tag
            NSInteger currentTag = cell.tag + 1;
            cell.tag = currentTag;

            PHAsset *asset = self.assetsFetchResults[newIndexPath.row];

            {
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
                    PHImageRequestID requestID=  [self.imageManager requestImageForAsset:asset
                                                                              targetSize:AssetGridThumbnailSize
                                                                             contentMode:PHImageContentModeAspectFill
                                                                                 options:self.imageRequestOptions
                                                                           resultHandler:^(UIImage *result, NSDictionary *info) {
                                                                               // Only update the thumbnail if the cell tag hasn't changed. Otherwise, the cell has been re-used.
                                                                               dispatch_async(dispatch_get_main_queue(), ^{
                                                                                   if (cell.tag == currentTag) {
                                                                                       [cell.imageView setImage:result];
                                                                                   }
                                                                               });

                                                                           }];
                    if(requestID != cell.assetRequestID){
                        if ([cell isKindOfClass:[GMGridViewCell class]]) {
                            [cell cancelImageRequest];
                        }
                        cell.assetRequestID = requestID;
                    }
                });
            }

            [cell bind:asset];

            cell.shouldShowSelection = self.picker.allowsMultipleSelection;

            // Optional protocol to determine if some kind of assets can't be selected (pej long videos, etc...)
            if ([self.picker.delegate respondsToSelector:@selector(assetsPickerController:shouldEnableAsset:)]) {
                cell.enabled = [self.picker.delegate assetsPickerController:self.picker shouldEnableAsset:asset];
            } else {
                cell.enabled = YES;
            }

            // Setting `selected` property blocks further deselection. Have to call selectItemAtIndexPath too. ( ref: http://stackoverflow.com/a/17812116/1648333 )
            if ([self.picker.selectedAssets containsObject:asset]) {
                cell.selected = YES;
                [collectionView selectItemAtIndexPath:indexPath animated:NO scrollPosition:UICollectionViewScrollPositionNone];
            } else {
                cell.selected = NO;
            }
            return cell;
        } else {
            UICollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:CameraCellIdentifier forIndexPath:indexPath];

            if ([cell subviews].count == 1) {
                cell.backgroundColor = [UIColor whiteColor];

                UIBarButtonItem *itemSpace = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
                UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCamera target:self action:@selector(launchCamera:)];

                int ypos = -12;
                if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"13.0")) {
                    ypos = -(cell.bounds.size.height/2)+12;
                }
                UIToolbar *toolBar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, ypos, cell.bounds.size.width, cell.bounds.size.height)];
                toolBar.barTintColor = [UIColor whiteColor];
                toolBar.backgroundColor = [UIColor whiteColor];
                [toolBar setItems:@[itemSpace, item, itemSpace]];
                [cell addSubview:toolBar];

                UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0, (cell.bounds.size.height/2), cell.bounds.size.width, 24)];
                label.font = [UIFont systemFontOfSize:12];
                label.textColor = [UIColor colorWithRed:0.0 green:122.0/255.0 blue:1.0 alpha:1.0];
                label.textAlignment = NSTextAlignmentCenter;
                label.contentMode = UIViewContentModeCenter;
                label.text = NSLocalizedStringFromTableInBundle(@"picker.navigation.camera-button",  @"GMImagePicker", [NSBundle bundleForClass:GMImagePickerController.class], @"Camera");

                [cell addSubview:label];
            }

            return cell;
        }
    } else {
        NSIndexPath *newIndexPath = [NSIndexPath indexPathForRow:indexPath.row inSection:0];

        __block GMGridViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:GMGridViewCellIdentifier
                                                                                 forIndexPath:newIndexPath];

        // Increment the cell's tag
        NSInteger currentTag = cell.tag + 1;
        cell.tag = currentTag;

        PHAsset *asset = self.assetsFetchResults[newIndexPath.row];

        {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
                PHImageRequestID requestID=  [self.imageManager requestImageForAsset:asset
                                                                          targetSize:AssetGridThumbnailSize
                                                                         contentMode:PHImageContentModeAspectFill
                                                                             options:self.imageRequestOptions
                                                                       resultHandler:^(UIImage *result, NSDictionary *info) {
                                                                           // Only update the thumbnail if the cell tag hasn't changed. Otherwise, the cell has been re-used.
                                                                           dispatch_async(dispatch_get_main_queue(), ^{
                                                                               if (cell.tag == currentTag) {
                                                                                   [cell.imageView setImage:result];
                                                                               }
                                                                           });

                                                                       }];
                if(requestID != cell.assetRequestID){
                    if ([cell isKindOfClass:[GMGridViewCell class]]) {
                        [cell cancelImageRequest];
                    }
                    cell.assetRequestID = requestID;
                }
            });
        }

        [cell bind:asset];

        cell.shouldShowSelection = self.picker.allowsMultipleSelection;

        // Optional protocol to determine if some kind of assets can't be selected (pej long videos, etc...)
        if ([self.picker.delegate respondsToSelector:@selector(assetsPickerController:shouldEnableAsset:)]) {
            cell.enabled = [self.picker.delegate assetsPickerController:self.picker shouldEnableAsset:asset];
        } else {
            cell.enabled = YES;
        }

        // Setting `selected` property blocks further deselection. Have to call selectItemAtIndexPath too. ( ref: http://stackoverflow.com/a/17812116/1648333 )
        if ([self.picker.selectedAssets containsObject:asset]) {
            cell.selected = YES;
            [collectionView selectItemAtIndexPath:indexPath animated:NO scrollPosition:UICollectionViewScrollPositionNone];
        } else {
            cell.selected = NO;
        }
        return cell;
    }

}

#pragma mark - Camera

- (void)launchCamera:(id)sender {
    [self.picker cameraButtonPressed:sender];
}

#pragma mark - Collection View Delegate

- (BOOL)collectionView:(UICollectionView *)collectionView shouldSelectItemAtIndexPath:(NSIndexPath *)indexPath
{
    if ([self.title isEqualToString:self.albumLabel]  && self.picker.showCameraButton ) {
        if (indexPath.row) {
            PHAsset *asset = self.assetsFetchResults[indexPath.row-1];

            GMGridViewCell *cell = (GMGridViewCell *)[collectionView cellForItemAtIndexPath:indexPath];

            if (!cell.isEnabled) {
                return NO;
            } else if ([self.picker.delegate respondsToSelector:@selector(assetsPickerController:shouldSelectAsset:)]) {
                return [self.picker.delegate assetsPickerController:self.picker shouldSelectAsset:asset];
            }
        }
    } else {
        PHAsset *asset = self.assetsFetchResults[indexPath.row];

        GMGridViewCell *cell = (GMGridViewCell *)[collectionView cellForItemAtIndexPath:indexPath];

        if (!cell.isEnabled) {
            return NO;
        } else if ([self.picker.delegate respondsToSelector:@selector(assetsPickerController:shouldSelectAsset:)]) {
            return [self.picker.delegate assetsPickerController:self.picker shouldSelectAsset:asset];
        }
    }
    return YES;
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath
{
    if ([self.title isEqualToString:self.albumLabel] && self.picker.showCameraButton) {
        if (indexPath.row) {
            PHAsset *asset = self.assetsFetchResults[indexPath.row-1];

            [self.picker selectAsset:asset];
            if ([self.picker.delegate respondsToSelector:@selector(assetsPickerController:didSelectAsset:)]) {
                [self.picker.delegate assetsPickerController:self.picker didSelectAsset:asset];
            }
        }
    } else {
        PHAsset *asset = self.assetsFetchResults[indexPath.row];

        [self.picker selectAsset:asset];
        if ([self.picker.delegate respondsToSelector:@selector(assetsPickerController:didSelectAsset:)]) {
            [self.picker.delegate assetsPickerController:self.picker didSelectAsset:asset];
        }
    }
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout*)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    CGFloat margin = [self getMargin];
    CGFloat gutter = [self getGutter];
    CGFloat columns = [self getColumns];
    
    if(@available(iOS 11, *)){
        CGFloat value = floorf((((self.view.bounds.size.width-self.view.safeAreaInsets.left-self.view.safeAreaInsets.right) - (columns - 1) * gutter - 2 * margin) / columns));
        return CGSizeMake(value, value);
    }else{
        CGFloat value = floorf(((self.view.bounds.size.width - (columns - 1) * gutter - 2 * margin) / columns));
        return CGSizeMake(value, value);
    }
}

- (CGFloat)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout*)collectionViewLayout minimumInteritemSpacingForSectionAtIndex:(NSInteger)section {
    return [self getGutter];
}

- (CGFloat)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout*)collectionViewLayout minimumLineSpacingForSectionAtIndex:(NSInteger)section {
    return [self getGutter];
}

- (UIEdgeInsets)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout*)collectionViewLayout insetForSectionAtIndex:(NSInteger)section {
    CGFloat margin = [self getMargin];
    return UIEdgeInsetsMake(margin, margin, margin, margin);
}



- (CGFloat)getMargin {
    if ((UIInterfaceOrientationIsPortrait([[UIApplication sharedApplication] statusBarOrientation]))) {
        return _margin;
    } else {
        return _marginL;
    }
}

- (CGFloat)getGutter {
    if ((UIInterfaceOrientationIsPortrait([[UIApplication sharedApplication] statusBarOrientation]))) {
        return _gutter;
    } else {
        return _gutterL;
    }
}

- (CGFloat)getColumns {
    if ((UIInterfaceOrientationIsPortrait([[UIApplication sharedApplication] statusBarOrientation]))) {
        return _columns;
    } else {
        return _columnsL;
    }
}

- (BOOL)collectionView:(UICollectionView *)collectionView shouldDeselectItemAtIndexPath:(NSIndexPath *)indexPath
{
    if ([self.title isEqualToString:self.albumLabel] && self.picker.showCameraButton) {
        if (indexPath.row) {
            PHAsset *asset = self.assetsFetchResults[indexPath.row-1];

            if ([self.picker.delegate respondsToSelector:@selector(assetsPickerController:shouldDeselectAsset:)]) {
                return [self.picker.delegate assetsPickerController:self.picker shouldDeselectAsset:asset];
            }
        }
    } else {
        PHAsset *asset = self.assetsFetchResults[indexPath.row];

        if ([self.picker.delegate respondsToSelector:@selector(assetsPickerController:shouldDeselectAsset:)]) {
            return [self.picker.delegate assetsPickerController:self.picker shouldDeselectAsset:asset];
        }
    }
    return YES;
}

- (void)collectionView:(UICollectionView *)collectionView didDeselectItemAtIndexPath:(NSIndexPath *)indexPath
{
    if ([self.title isEqualToString:self.albumLabel] && self.picker.showCameraButton) {
        if (indexPath.row) {
            PHAsset *asset = self.assetsFetchResults[indexPath.row-1];
            [self.picker deselectAsset:asset];
            if ([self.picker.delegate respondsToSelector:@selector(assetsPickerController:didDeselectAsset:)]) {
                [self.picker.delegate assetsPickerController:self.picker didDeselectAsset:asset];
            }
        }
    } else {
        PHAsset *asset = self.assetsFetchResults[indexPath.row];
        [self.picker deselectAsset:asset];
        if ([self.picker.delegate respondsToSelector:@selector(assetsPickerController:didDeselectAsset:)]) {
            [self.picker.delegate assetsPickerController:self.picker didDeselectAsset:asset];
        }
    }
}

- (BOOL)collectionView:(UICollectionView *)collectionView shouldHighlightItemAtIndexPath:(NSIndexPath *)indexPath
{
    if ([self.title isEqualToString:self.albumLabel] && self.picker.showCameraButton) {
        if (indexPath.row) {
            PHAsset *asset = self.assetsFetchResults[indexPath.row-1];
            // detect video assets
            if (asset.mediaType == PHAssetMediaTypeVideo) {
                [self.picker.delegate assetsPickerController:self.picker didSelectVideo:asset];
            }
            if ([self.picker.delegate respondsToSelector:@selector(assetsPickerController:shouldHighlightAsset:)]) {
                return [self.picker.delegate assetsPickerController:self.picker shouldHighlightAsset:asset];
            }
        }
    } else {
        PHAsset *asset = self.assetsFetchResults[indexPath.row];

        if ([self.picker.delegate respondsToSelector:@selector(assetsPickerController:shouldHighlightAsset:)]) {
            return [self.picker.delegate assetsPickerController:self.picker shouldHighlightAsset:asset];
        }
    }
    return YES;
}

- (void)collectionView:(UICollectionView *)collectionView didHighlightItemAtIndexPath:(NSIndexPath *)indexPath
{
    if ([self.title isEqualToString:self.albumLabel] && self.picker.showCameraButton) {
        if (indexPath.row) {
            PHAsset *asset = self.assetsFetchResults[indexPath.row-1];

            if ([self.picker.delegate respondsToSelector:@selector(assetsPickerController:didHighlightAsset:)]) {
                [self.picker.delegate assetsPickerController:self.picker didHighlightAsset:asset];
            }
        }
    } else {
        PHAsset *asset = self.assetsFetchResults[indexPath.row];

        if ([self.picker.delegate respondsToSelector:@selector(assetsPickerController:didHighlightAsset:)]) {
            [self.picker.delegate assetsPickerController:self.picker didHighlightAsset:asset];
        }
    }
}

- (void)collectionView:(UICollectionView *)collectionView didUnhighlightItemAtIndexPath:(NSIndexPath *)indexPath
{
    if ([self.title isEqualToString:self.albumLabel] && self.picker.showCameraButton) {
        if (indexPath.row) {
            PHAsset *asset = self.assetsFetchResults[indexPath.row-1];

            if ([self.picker.delegate respondsToSelector:@selector(assetsPickerController:didUnhighlightAsset:)]) {
                [self.picker.delegate assetsPickerController:self.picker didUnhighlightAsset:asset];
            }
        }
    } else {
        PHAsset *asset = self.assetsFetchResults[indexPath.row];

        if ([self.picker.delegate respondsToSelector:@selector(assetsPickerController:didUnhighlightAsset:)]) {
            [self.picker.delegate assetsPickerController:self.picker didUnhighlightAsset:asset];
        }
    }
}



#pragma mark - UICollectionViewDataSource

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    NSInteger count = self.assetsFetchResults.count + (([self.title isEqualToString:self.albumLabel]  && self.picker.showCameraButton) ? 1 : 0);
    return count;
}


#pragma mark - PHPhotoLibraryChangeObserver
//http://crashes.to/s/0483c5ef912
//ref : https://github.com/hackiftekhar/IQScreenRuler/blob/master/ScreenRuler/ViewControllers/Screenshot%20Picker%20Flow/SRScreenshotCollectionViewController.m
-(void)photoLibraryDidChange:(PHChange *)changeInstance
{
    PHFetchResultChangeDetails *changes = [changeInstance changeDetailsForFetchResult:self.assetsFetchResults];
    if (changes)
    {
        __weak typeof(self) weakSelf = self;
        
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            
            PHFetchResultChangeDetails *collectionChanges = [changeInstance changeDetailsForFetchResult:weakSelf.assetsFetchResults];
            if (collectionChanges) {
                
                weakSelf.assetsFetchResults = [collectionChanges fetchResultAfterChanges];
                
                UICollectionView *collectionView = weakSelf.collectionView;
                NSArray *removedPaths;
                NSArray *insertedPaths;
                NSArray *changedPaths;
                
                if ([collectionChanges hasIncrementalChanges]) {
                    NSIndexSet *removedIndexes = [collectionChanges removedIndexes];
                    removedPaths = [weakSelf indexPathsFromIndexSet:removedIndexes withSection:0];
                    
                    NSIndexSet *insertedIndexes = [collectionChanges insertedIndexes];
                    insertedPaths = [weakSelf indexPathsFromIndexSet:insertedIndexes withSection:0];
                    
                    NSIndexSet *changedIndexes = [collectionChanges changedIndexes];
                    changedPaths = [weakSelf indexPathsFromIndexSet:changedIndexes withSection:0];
                    
                    BOOL shouldReload = NO;
                    
                    if (changedPaths != nil && removedPaths != nil) {
                        for (NSIndexPath *changedPath in changedPaths) {
                            if ([removedPaths containsObject:changedPath]) {
                                shouldReload = YES;
                                break;
                            }
                        }
                    }
                    
                    if (removedPaths.lastObject && ((NSIndexPath *)removedPaths.lastObject).item >= weakSelf.assetsFetchResults.count) {
                        shouldReload = YES;
                    }
                    
                    if (shouldReload) {
                        [collectionView reloadData];
                    } else {
                        [collectionView performBatchUpdates:^{
                            weakSelf.assetsFetchResults = [collectionChanges fetchResultAfterChanges];
                            if (removedPaths != nil) {
                                [collectionView deleteItemsAtIndexPaths:removedPaths];
                            }
                            
                            if (insertedPaths != nil) {
                                [UIView setAnimationsEnabled:NO];
                                [collectionView insertItemsAtIndexPaths:insertedPaths];
                                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                                    if (weakSelf.picker.selectedAssets.count < weakSelf.picker.maxItems) {
                                        NSPredicate *videoPredicate = [weakSelf predicateOfAssetType:PHAssetMediaTypeVideo];
                                        NSInteger nVideos = [weakSelf.picker.selectedAssets filteredArrayUsingPredicate:videoPredicate].count;
                                        PHAsset *asset = weakSelf.assetsFetchResults[0];
                                        BOOL isSelected = false;
                                        // detect video assets
                                        if (asset.mediaType == PHAssetMediaTypeVideo) {
                                            if((nVideos) < weakSelf.picker.maxVideoCount){
                                                [weakSelf.picker.delegate assetsPickerController:weakSelf.picker didSelectVideo:asset];
                                                isSelected = true;
                                            }
                                        } else {
                                            isSelected = true;
                                        }
                                        if (isSelected) {
                                            [weakSelf collectionView:weakSelf.collectionView didSelectItemAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:0]];
                                            [collectionView reloadItemsAtIndexPaths: [collectionView indexPathsForVisibleItems]];
                                        }
                                    }
                                });
                            }
                            
                            if (changedPaths != nil) {
                                [UIView setAnimationsEnabled:YES];
                                if (changedPaths.count > 1) {
                                    [collectionView reloadData];
                                } else {
                                    [collectionView reloadItemsAtIndexPaths:changedPaths];
                                }
                            }
                            
                            if ([collectionChanges hasMoves]) {
                                [collectionChanges enumerateMovesWithBlock:^(NSUInteger fromIndex, NSUInteger toIndex) {
                                    NSIndexPath *fromIndexPath = [NSIndexPath indexPathForItem:fromIndex inSection:0];
                                    NSIndexPath *toIndexPath = [NSIndexPath indexPathForItem:toIndex inSection:0];
                                    [collectionView moveItemAtIndexPath:fromIndexPath toIndexPath:toIndexPath];
                                }];
                            }
                            
                        } completion:^(BOOL finished) {
                            if(finished){
                                [collectionView reloadItemsAtIndexPaths: [collectionView indexPathsForVisibleItems]];
                            }
                            [weakSelf updateCachedAssets];
                            dispatch_semaphore_signal(weakSelf.phPhotoLibChageMutex);
                        }];
                    }
                    
                    [weakSelf resetCachedAssets];
                } else {
                    [collectionView reloadData];
                }
            }
            
        }];
    }
    
}
/*- (void)photoLibraryDidChange:(PHChange *)changeInfo {
 // Photos may call this method on a background queue;
 // switch to the main queue to update the UI.
 
 dispatch_async(dispatch_get_main_queue(), ^{
 
 PHFetchResultChangeDetails *collectionChanges = [changeInfo changeDetailsForFetchResult:_assetsFetchResults];
 if (collectionChanges == nil) {
 return ;
 }
 // Get the new fetch result for future change tracking.
 _assetsFetchResults = collectionChanges.fetchResultAfterChanges;
 
 NSLog(@"photoLibraryDidChange _assetsFetchResults.count %lu",(unsigned long)_assetsFetchResults.count);
 // Check for changes to the displayed album itself
 // (its existence and metadata, not its member assets).
 
 // Check for changes to the list of assets (insertions, deletions, moves, or updates).
 
 
 // Get the new fetch result for future change tracking.
 
 
 if (collectionChanges.hasIncrementalChanges)  {
 // Tell the collection view to animate insertions/deletions/moves
 // and to refresh any cells that have changed content.
 
 [self.collectionView performBatchUpdates:^{
 
 NSIndexSet *removed = collectionChanges.removedIndexes;
 if (removed.count) {
 [self.collectionView deleteItemsAtIndexPaths:[self indexPathsFromIndexSet:removed withSection:0]];
 }
 NSIndexSet *inserted = collectionChanges.insertedIndexes;
 if (inserted.count) {
 [self.collectionView insertItemsAtIndexPaths:[self indexPathsFromIndexSet:inserted withSection:0]];
 //auto select
 if (self.picker.showCameraButton && self.picker.autoSelectCameraImages) {
 for (NSIndexPath *path in [inserted aapl_indexPathsFromIndexesWithSection:0]) {
 [self collectionView:self.collectionView didSelectItemAtIndexPath:path];
 }
 }
 }
 NSIndexSet *changed = collectionChanges.changedIndexes;
 if (changed.count) {
 [self.collectionView reloadItemsAtIndexPaths:[self indexPathsFromIndexSet:changed withSection:0]];
 }
 if (collectionChanges.hasMoves) {
 [collectionChanges enumerateMovesWithBlock:^(NSUInteger fromIndex, NSUInteger toIndex) {
 NSIndexPath *fromIndexPath = [NSIndexPath indexPathForItem:fromIndex inSection:0];
 NSIndexPath *toIndexPath = [NSIndexPath indexPathForItem:toIndex inSection:0];
 [self.collectionView moveItemAtIndexPath:fromIndexPath toIndexPath:toIndexPath];
 }];
 }
 } completion:nil];
 
 
 } else {
 // Detailed change information is not available;
 // repopulate the UI from the current fetch result.
 
 
 [self.collectionView reloadData];
 [self resetCachedAssets];
 }
 
 });
 }*/

- (NSArray *)indexPathsFromIndexSet:(NSIndexSet *)indexSet withSection:(int)section {
    if (indexSet == nil) {
        return nil;
    }
    NSMutableArray *indexPaths = [[NSMutableArray alloc] init];
    
    [indexSet enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        [indexPaths addObject:[NSIndexPath indexPathForItem:idx inSection:section]];
        
    }];
    
    return indexPaths;
}
//- (void)photoLibraryDidChange:(PHChange *)changeInstance
//{
//
//    [[PHPhotoLibrary sharedPhotoLibrary] unregisterChangeObserver:self];
//    // Call might come on any background queue. Re-dispatch to the main queue to handle it.
//    dispatch_async(dispatch_get_main_queue(), ^{
//
//        // check if there are changes to the assets (insertions, deletions, updates)
//        PHFetchResultChangeDetails *collectionChanges = [changeInstance changeDetailsForFetchResult:_assetsFetchResults];
//        if (collectionChanges) {
//
//            // get the new fetch result
//            _assetsFetchResults = [collectionChanges fetchResultAfterChanges];
//
//            UICollectionView *collectionView = self.collectionView;
//
//            if(collectionView != nil){
//                if (![collectionChanges hasIncrementalChanges] || [collectionChanges hasMoves]) {
//                    // we need to reload all if the incremental diffs are not available
//                    [collectionView reloadData];
//
//                } else {
//                    // if we have incremental diffs, tell the collection view to animate insertions and deletions
//                    [collectionView performBatchUpdates:^{
//                        NSIndexSet *removedIndexes = [collectionChanges removedIndexes];
//                        if ([removedIndexes count]) {
//                            [collectionView deleteItemsAtIndexPaths:[removedIndexes aapl_indexPathsFromIndexesWithSection:0]];
//                        }
//                        NSIndexSet *insertedIndexes = [collectionChanges insertedIndexes];
//                        if ([insertedIndexes count]) {
//                            [collectionView insertItemsAtIndexPaths:[insertedIndexes aapl_indexPathsFromIndexesWithSection:0]];
//                            if (self.picker.showCameraButton && self.picker.autoSelectCameraImages) {
//                                for (NSIndexPath *path in [insertedIndexes aapl_indexPathsFromIndexesWithSection:0]) {
//                                    [self collectionView:collectionView didSelectItemAtIndexPath:path];
//                                }
//                            }
//                        }
//                        NSIndexSet *changedIndexes = [collectionChanges changedIndexes];
//                        if ([changedIndexes count]) {
//                            [collectionView reloadItemsAtIndexPaths:[changedIndexes aapl_indexPathsFromIndexesWithSection:0]];
//                        }
//                    } completion:^(BOOL finished) {
//                        [[PHPhotoLibrary sharedPhotoLibrary] registerChangeObserver:self];
//                    }];
//                }
//            }
//            [self resetCachedAssets];
//        }else{
//            [[PHPhotoLibrary sharedPhotoLibrary] registerChangeObserver:self];
//        }
//    });
//}


#pragma mark - UIScrollViewDelegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    [self updateCachedAssets];
}

#pragma mark - Asset Caching

- (void)resetCachedAssets
{
    NSArray *visibleCells = self.collectionView.visibleCells;
    [visibleCells enumerateObjectsUsingBlock:^(GMGridViewCell *cell, NSUInteger idx, BOOL * _Nonnull stop) {
        if ([cell isKindOfClass:[GMGridViewCell class]]) {
            [cell cancelImageRequest];
        }
    }];
    
    [self.imageManager stopCachingImagesForAllAssets];
    self.previousPreheatRect = CGRectZero;
}

- (void)updateCachedAssets
{
    BOOL isViewVisible = [self isViewLoaded] && [[self view] window] != nil;
    if (!isViewVisible) { return; }
    
    // The preheat window is twice the height of the visible rect
    CGRect preheatRect = self.collectionView.bounds;
    preheatRect = CGRectInset(preheatRect, 0.0f, -0.5f * CGRectGetHeight(preheatRect));
    
    // If scrolled by a "reasonable" amount...
    CGFloat delta = ABS(CGRectGetMidY(preheatRect) - CGRectGetMidY(self.previousPreheatRect));
    if (delta > CGRectGetHeight(self.collectionView.bounds) / 3.0f) {
        
        // Compute the assets to start caching and to stop caching.
        NSMutableArray *addedIndexPaths = [NSMutableArray array];
        NSMutableArray *removedIndexPaths = [NSMutableArray array];
        
        [self computeDifferenceBetweenRect:self.previousPreheatRect
                                   andRect:preheatRect
                            removedHandler:^(CGRect removedRect) {
                                NSArray *indexPaths = [self.collectionView aapl_indexPathsForElementsInRect:removedRect];
                                [removedIndexPaths addObjectsFromArray:indexPaths];
                            } addedHandler:^(CGRect addedRect) {
                                NSArray *indexPaths = [self.collectionView aapl_indexPathsForElementsInRect:addedRect];
                                [addedIndexPaths addObjectsFromArray:indexPaths];
                            }];
        
        NSArray *assetsToStartCaching = [self assetsAtIndexPaths:addedIndexPaths];
        NSArray *assetsToStopCaching = [self assetsAtIndexPaths:removedIndexPaths];
        
        [self.imageManager startCachingImagesForAssets:assetsToStartCaching
                                            targetSize:AssetGridThumbnailSize
                                           contentMode:PHImageContentModeAspectFill
                                               options:nil];
        
        [self.imageManager stopCachingImagesForAssets:assetsToStopCaching
                                           targetSize:AssetGridThumbnailSize
                                          contentMode:PHImageContentModeAspectFill
                                              options:nil];
        
        self.previousPreheatRect = preheatRect;
    }
}

- (void)computeDifferenceBetweenRect:(CGRect)oldRect andRect:(CGRect)newRect removedHandler:(void (^)(CGRect removedRect))removedHandler addedHandler:(void (^)(CGRect addedRect))addedHandler
{
    if (CGRectIntersectsRect(newRect, oldRect)) {
        CGFloat oldMaxY = CGRectGetMaxY(oldRect);
        CGFloat oldMinY = CGRectGetMinY(oldRect);
        CGFloat newMaxY = CGRectGetMaxY(newRect);
        CGFloat newMinY = CGRectGetMinY(newRect);
        if (newMaxY > oldMaxY) {
            CGRect rectToAdd = CGRectMake(newRect.origin.x, oldMaxY, newRect.size.width, (newMaxY - oldMaxY));
            addedHandler(rectToAdd);
        }
        if (oldMinY > newMinY) {
            CGRect rectToAdd = CGRectMake(newRect.origin.x, newMinY, newRect.size.width, (oldMinY - newMinY));
            addedHandler(rectToAdd);
        }
        if (newMaxY < oldMaxY) {
            CGRect rectToRemove = CGRectMake(newRect.origin.x, newMaxY, newRect.size.width, (oldMaxY - newMaxY));
            removedHandler(rectToRemove);
        }
        if (oldMinY < newMinY) {
            CGRect rectToRemove = CGRectMake(newRect.origin.x, oldMinY, newRect.size.width, (newMinY - oldMinY));
            removedHandler(rectToRemove);
        }
    } else {
        addedHandler(newRect);
        removedHandler(oldRect);
    }
}

- (NSArray *)assetsAtIndexPaths:(NSArray *)indexPaths
{
    if (indexPaths.count == 0) { return nil; }
    
    NSMutableArray *assets = [NSMutableArray arrayWithCapacity:indexPaths.count];
    for (NSIndexPath *indexPath in indexPaths) {
        if ([self.title isEqualToString:self.albumLabel]) {
            if (indexPath.row) {
                PHAsset *asset = _assetsFetchResults[indexPath.row-1];
                [assets addObject:asset];
            }
        } else {
            PHAsset *asset = _assetsFetchResults[indexPath.row];
            [assets addObject:asset];
        }
    }
    return assets;
}

- (NSPredicate *)predicateOfAssetType:(PHAssetMediaType)type
{
    return [NSPredicate predicateWithBlock:^BOOL(PHAsset *asset, NSDictionary *bindings) {
        return (asset.mediaType == type);
    }];
}

@end
