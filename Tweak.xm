#import <CoreFoundation/CoreFoundation.h>
#import <CoreImage/CoreImage.h>
#import <CFNetwork/CFNetwork.h>
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <math.h>
#import <objc/message.h>
#import <objc/runtime.h>

static CFStringRef const kCCAPrefsDomain = CFSTR("com.futur3sn0w.ccaster.preferences");
static NSString *const kCCAReloadNotification = @"com.futur3sn0w.ccaster/ReloadPrefs";

static BOOL gEnabled = YES;
static BOOL gQuickAccessButtonsEnabled = YES;
static BOOL gPagingEnabled = YES;
// gPagingEnabled itself becomes the *effective* runtime value, recomputed
// on every paging layout pass (see normalizePagedLayoutForOverlay:) as
// (preference && !landscape). The user's actual preference is tracked
// separately here so recomputing doesn't lose it.
static BOOL gPagingPreferenceEnabled = YES;
static BOOL gBlankSpaceGestureEnabled = YES;
static BOOL gAddButtonEnabled = YES;
static BOOL gPowerButtonEnabled = YES;
static BOOL gRemovalButtonsEnabled = YES;
static BOOL gModuleBordersEnabled = YES;
static BOOL gBorderBreathingEnabled = YES;
static BOOL gHapticsEnabled = YES;
static BOOL const gCCAUseNativeOpeningCompensation = NO;
static CGFloat const kCCARestingModuleOffset = -8.0;
static CGFloat const kCCAEditingModuleOffset = -48.0;
static NSUInteger const kCCAMinimumGridRows = 8;
// CCUILayoutOptions is patched below so the real collection and every
// CCAster-owned grid use the same compact geometry.
static CGFloat kCCAGridCellSize = 67.0;
static CGFloat kCCAGridGap = 12.0;
static CGFloat const kCCAGridCellScale = 67.0 / 69.0;
static CGFloat const kCCAGridGapScale = 12.0 / 15.0;
#define kCCAGridStep (kCCAGridCellSize + kCCAGridGap)
#define kCCAPageSpan (kCCAMinimumGridRows * kCCAGridStep)
static CGFloat const kCCAPageIndicatorRestStep = 39.0;
static CGFloat const kCCAPageIndicatorScrubStep = 58.0;
static CGFloat const kCCAPageIndicatorRestHostWidth = 42.0;
static CGFloat const kCCAPageIndicatorScrubHostWidth = 58.0;
static CGFloat const kCCAPageIndicatorRestRightInset = -3.0;
static CGFloat const kCCAPageIndicatorScrubRightInset = -3.0;
static CGFloat const kCCAPageIndicatorMaxSlideOut = 24.0;
// The page remains obedient to indicator thresholds, but its small parallax
// offset trails the finger slightly. Velocity adds a deliberately tiny,
// direction-aware stretch to the single composited page.
static CGFloat const kCCAPagerViscosityResponse = 9.0;
static CGFloat const kCCAPagerJelloVelocityResponse = 11.0;
static CGFloat const kCCAPagerJelloVelocityToScale = 0.0030;
static CGFloat const kCCAPagerJelloTensionToScale = 0.022;
static CGFloat const kCCAPagerMaximumJelloScale = 0.025;
static CGFloat const kCCAEditScrubModuleWrapperCenteringX = 81.0;
static CGFloat const kCCAEditScrubModuleWrapperCenteringY = 118.0;
static NSUInteger const kCCAMaxPages = 9;

static NSHashTable<UIViewController *> *gOverlayControllers;
static BOOL gEditModeActive = NO;
static BOOL gCCAEditTransitionActive = NO;
static NSUInteger gCCAEditTransitionGeneration = 0;
static BOOL gCCAExpandedModuleOpen = NO;
static BOOL gCCAExpandedModuleClosingActive = NO;
static UIView *gCCAExpansionSourceSnapshot = nil;
static UIView *gCCAExpansionCompactMaterialTemplate = nil;
static UIImage *gCCAExpansionCompactForegroundImage = nil;
static UIImage *gCCAExpansionCompactImage = nil;
static UIView *gCCAExpansionDismissalSnapshot = nil;
static UIView *gCCAExpansionDismissalForegroundSnapshot = nil;
static UIView *gCCAExpansionExpandedSnapshot = nil;
static __weak UIWindow *gCCAExpansionTransitionWindow = nil;
static CGRect gCCAExpansionCompactDestinationWindowFrame = {{0.0, 0.0}, {0.0, 0.0}};
static CGPoint gCCAExpansionExpandedContentAnchorWindow = {0.0, 0.0};
static NSArray<UIView *> *gCCAExpansionHiddenLiveViews = nil;
static NSArray<NSNumber *> *gCCAExpansionHiddenLiveAlphas = nil;
static NSArray<NSNumber *> *gCCAExpansionHiddenLiveLayerOpacities = nil;
static BOOL gCCAExpansionDismissalAnimatorFinished = NO;
static BOOL gCCAExpansionDismissalDidClose = NO;
static NSUInteger gCCAExpansionDismissalGeneration = 0;
static CGFloat gCCAExpansionCompactCornerRadius = 0.0;
static BOOL gCCAConnectivityExpansionActive = NO;
static BOOL gCCAConnectivityProxyExpansionActive = NO;
static NSString *gCCAExpandedModuleIdentifier = nil;
static UIViewController *gCCAMediaCompactModule = nil;
static UIView *gCCAMediaCompactTransitionSnapshot = nil;
static UIView *gCCAMediaExpandedTransitionSnapshot = nil;
static __weak UIView *gCCAMediaHiddenExpandedView = nil;
static UIWindow *gCCAMediaTransitionWindow = nil;
static UIView *gCCAMediaTransitionHost = nil;
static CGRect gCCAMediaCompactDestinationScreenFrame = {{0.0, 0.0}, {0.0, 0.0}};
static CGRect gCCAMediaExpandedPresentationScreenFrame = {{0.0, 0.0}, {0.0, 0.0}};
static CFTimeInterval gCCAMediaCompactSnapshotRefreshTime = 0.0;
// Connectivity reuses the same live child hierarchy for its compact and
// expanded presentations.  UIKit therefore flies those children between two
// very different layouts.  Keep that hierarchy invisible during the native
// transition and composite stable snapshots above it instead.
static __weak UIViewController *gCCAConnectivityTransitionController = nil;
static __weak UIViewController *gCCAConnectivityCompactController = nil;
static __weak UIPresentationController *gCCAConnectivityTransitionPresentationController = nil;
static UIWindow *gCCAConnectivityTransitionWindow = nil;
static UIView *gCCAConnectivityTransitionHost = nil;
static UIView *gCCAConnectivityCompactTransitionSnapshot = nil;
static UIView *gCCAConnectivityExpandedTransitionSnapshot = nil;
static UIView *gCCAConnectivityTransitionSurface = nil;
static UIImage *gCCAConnectivityCachedCompactImage = nil;
static __weak UIWindow *gCCAConnectivityCompactWindow = nil;
static __weak UIView *gCCAConnectivityProxySourceView = nil;
static CGRect gCCAConnectivityProxySourceWindowFrame = {{0.0, 0.0}, {0.0, 0.0}};
static CGFloat gCCAConnectivityProxySourceCornerRadius = 32.0;
static BOOL gCCAConnectivityHasProxySourceFrame = NO;
static NSString *gCCAConnectivityPendingDetailIdentifier = nil;
static UIView *gCCAConnectivityDetachedLiveView = nil;
static __weak UIView *gCCAConnectivityDetachedOriginalSuperview = nil;
static CGRect gCCAConnectivityDetachedOriginalFrame = {{0.0, 0.0}, {0.0, 0.0}};
static CGRect gCCAConnectivityDetachedOriginalBounds = {{0.0, 0.0}, {0.0, 0.0}};
static NSUInteger gCCAConnectivityDetachedOriginalIndex = NSNotFound;
static CGRect gCCAConnectivityCompactWindowFrame = {{0.0, 0.0}, {0.0, 0.0}};
static CGFloat gCCAConnectivityCompactCornerRadius = 32.0;
static BOOL gCCAConnectivityHasCompactWindowFrame = NO;
static BOOL gCCAConnectivityOpeningRevealStarted = NO;
static BOOL gCCAConnectivityClosingTransitionActive = NO;
static BOOL gCCAConnectivityClosingFinishScheduled = NO;
static CFTimeInterval gCCAConnectivityClosingTransitionDeadline = 0.0;
static BOOL gCCAConnectivitySnapshotCaptureActive = NO;
static NSUInteger gCCAConnectivityTransitionGeneration = 0;
static BOOL gCCAControlCenterPresented = NO;
static NSUInteger gCCAControlCenterPresentationState = 0;
static CFTimeInterval gCCAControlCenterPresentationStateChangedTime = 0.0;
static NSUInteger gCCAPresentationChromeGeneration = 0;
static BOOL gCCAPagerTransitionActive = NO;
static BOOL gCCAEditChromeSuppressedForPaging = NO;
static CADisplayLink *gCCAEditChromeDisplayLink = nil;
static __weak UIPanGestureRecognizer *gCCAPresentationPanGesture = nil;
static __weak id gCCAPresentationController = nil;
static __weak id gCCASBControlCenterController = nil;
static CADisplayLink *gCCAPresentationPanDisplayLink = nil;
static CADisplayLink *gCCAPresentationPanDiscoveryDisplayLink = nil;
static CADisplayLink *gCCAOwnedDuplicateHostDisplayLink = nil;
static CFTimeInterval gCCAOwnedDuplicateHostSyncUntil = 0.0;
static BOOL gCCAOwnedDuplicateHostSyncPresented = NO;
static __weak UIViewController *gCCAPresentationPanDiscoveryOverlay = nil;
static __weak id gCCAPresentationPanDiscoveryController = nil;
static CFTimeInterval gCCAPresentationPanDiscoveryDeadline = 0.0;
static BOOL gCCAPresentationPageHandoffActive = NO;
static BOOL gCCAPresentationNativeSettlePending = NO;
static BOOL gCCAPresentationReleasedWhileSettling = NO;
static BOOL gCCAPresentationHandoffArmed = NO;
static BOOL gCCAPagerScrubbingActive = NO;
static BOOL gCCAAddSheetPresentationActive = NO;
static CGFloat gCCAPresentationPendingProgress = 0.0;
static CGFloat gCCAPresentationPendingTouchY = 0.0;
static NSInteger const kCCAEditShieldTag = 181017;
static NSInteger const kCCARemoveButtonTag = 181018;
static NSInteger const kCCAPowerMaterialTag = 181019;
static NSInteger const kCCAEditGridTag = 181020;
static NSInteger const kCCAEditTouchShieldTag = 181021;
static NSInteger const kCCAResizeButtonTag = 181022;
static NSInteger const kCCAResizePresentationTag = 181023;
// A drop that never became a drag and released within this distance of the
// module's top-left corner (where the remove bubble sits) is treated as a
// removal. Lets the remove bubble be a purely visual affordance so the whole
// tile — critically the tiny 1x1s — stays grabbable for dragging.
static CGFloat const kCCARemoveTapCornerRadius = 30.0;
static NSInteger const kCCAResizeMaterialTag = 181024;
static NSInteger const kCCAResizeBlurSnapshotTag = 181025;
static NSInteger const kCCAResizePresentationGlyphTag = 181036;
static NSInteger const kCCAExtendedHitBridgeTag = 181026;
static NSInteger const kCCAAddControlButtonTag = 181027;
static NSInteger const kCCASliderColorGlyphTag = 181028;
static NSInteger const kCCASliderOutgoingGlyphTag = 181029;
static NSInteger const kCCAPageIndicatorHostTag = 181030;
static NSInteger const kCCATopFadeTag = 181031;
static NSInteger const kCCAConnectivityMiniClusterTag = 181032;
static NSInteger const kCCAConnectivityExpandButtonTag = 181033;
static NSInteger const kCCAConnectivityCompactAirDropTag = 181034;
static NSInteger const kCCAConnectivityCompactBluetoothTag = 181035;
static NSInteger const kCCAQuickAccessDismissalProxyTag = 181039;
static NSInteger const kCCAConnectivityTileActionProxyTag = 181049;
static NSInteger const kCCAConnectivitySelectedSurfaceTag = 181050;
static NSInteger const kCCAConnectivityBluetoothPackageGlyphTag = 181051;
static NSInteger const kCCAOwnedDuplicateHostTag = 181052;
static NSInteger const kCCAConnectivityExpandedCardBaseTag = 181040;
static NSInteger const kCCAConnectivityExpandedVPNTag = 181048;
static CGFloat const kCCARemoveHitSize = 44.0;
static CGFloat const kCCARemoveVisualCenterOffset = 8.0;
static const void *kCCAOwnGestureKey = &kCCAOwnGestureKey;

// A dangling (non-retaining, non-zeroing) associated-object pointer to a
// view crashes the whole process the moment anything touches it after that
// view is deallocated. This tiny box lets us keep a *retained* association
// (so it's never dangling) while the reference it carries is itself __weak
// (so it can't create a retain cycle when the referenced view is an
// ancestor of the view holding the box).
@interface CCAWeakViewBox : NSObject
@property (nonatomic, weak) UIView *view;
@end
@implementation CCAWeakViewBox
@end

static const void *kCCAConnectivityForwardControlKey = &kCCAConnectivityForwardControlKey;
static const void *kCCAConnectivityIdentifierKey = &kCCAConnectivityIdentifierKey;
static const void *kCCAConnectivitySelectedStateKey = &kCCAConnectivitySelectedStateKey;
static const void *kCCAConnectivitySuppressedSurfaceKey = &kCCAConnectivitySuppressedSurfaceKey;
static const void *kCCAConnectivityProxyPreparedKey = &kCCAConnectivityProxyPreparedKey;
static const void *kCCAConnectivityProxyRefreshScheduledKey = &kCCAConnectivityProxyRefreshScheduledKey;
static const void *kCCAConnectivityExpandedCardKey = &kCCAConnectivityExpandedCardKey;
static const void *kCCAConnectivityExpandedSurfaceKey = &kCCAConnectivityExpandedSurfaceKey;
static const void *kCCAConnectivityExpandedGridGlyphKey = &kCCAConnectivityExpandedGridGlyphKey;
static const void *kCCAConnectivityForceFiredKey = &kCCAConnectivityForceFiredKey;
static const void *kCCADisabledGesturesKey = &kCCADisabledGesturesKey;
static const void *kCCAOriginalCornerRadiusKey = &kCCAOriginalCornerRadiusKey;
static const void *kCCAOriginalMasksToBoundsKey = &kCCAOriginalMasksToBoundsKey;
static const void *kCCAOriginalTransformKey = &kCCAOriginalTransformKey;
static const void *kCCAOriginalSublayerTransformKey = &kCCAOriginalSublayerTransformKey;
static const void *kCCAOriginalAlphaKey = &kCCAOriginalAlphaKey;
static const void *kCCAEditScrubWrapperBaseTransformKey = &kCCAEditScrubWrapperBaseTransformKey;
static const void *kCCAScrubCollectionBoundsKey = &kCCAScrubCollectionBoundsKey;
static const void *kCCAScrubCollectionPositionKey = &kCCAScrubCollectionPositionKey;
static const void *kCCADragStartFrameKey = &kCCADragStartFrameKey;
static const void *kCCADragStartPointKey = &kCCADragStartPointKey;
static const void *kCCAEditGridKey = &kCCAEditGridKey;
static const void *kCCAEditPageGridsKey = &kCCAEditPageGridsKey;
static const void *kCCAEditGridStackKey = &kCCAEditGridStackKey;
static const void *kCCAEditGridBaseOriginKey = &kCCAEditGridBaseOriginKey;
static const void *kCCARemoveButtonKey = &kCCARemoveButtonKey;
static const void *kCCARemoveModuleViewKey = &kCCARemoveModuleViewKey;
static const void *kCCADragPreviewTargetKey = &kCCADragPreviewTargetKey;
static const void *kCCADragProxyKey = &kCCADragProxyKey;
static const void *kCCADragBaseOrderKey = &kCCADragBaseOrderKey;
static const void *kCCADragPreviewTargetIDKey = &kCCADragPreviewTargetIDKey;
static const void *kCCADragProxyStartFrameKey = &kCCADragProxyStartFrameKey;
static const void *kCCADragBaseFramesKey = &kCCADragBaseFramesKey;
static const void *kCCADragPendingTargetIDKey = &kCCADragPendingTargetIDKey;
static const void *kCCADragPreviewLockedKey = &kCCADragPreviewLockedKey;
static const void *kCCADragGrabOffsetKey = &kCCADragGrabOffsetKey;
static const void *kCCADragMovedKey = &kCCADragMovedKey;
static const void *kCCADragLandingOriginKey = &kCCADragLandingOriginKey;
static const void *kCCADragStartPageKey = &kCCADragStartPageKey;
static const void *kCCADragEdgeDwellKey = &kCCADragEdgeDwellKey;
static const void *kCCADragEdgeDwellDirectionKey = &kCCADragEdgeDwellDirectionKey;
static const void *kCCASmallModuleChromeKey = &kCCASmallModuleChromeKey;
static const void *kCCADragHiddenChromeKey = &kCCADragHiddenChromeKey;
static const void *kCCAResizeButtonKey = &kCCAResizeButtonKey;
static const void *kCCAOwnedDuplicateContainerKey = &kCCAOwnedDuplicateContainerKey;
static const void *kCCAOwnedDuplicatePresentationKey = &kCCAOwnedDuplicatePresentationKey;
static const void *kCCAResizeStartSizeKey = &kCCAResizeStartSizeKey;
static const void *kCCAResizeCandidateSizeKey = &kCCAResizeCandidateSizeKey;
static const void *kCCAResizePreviewKey = &kCCAResizePreviewKey;
static const void *kCCAResizePreviewStartFrameKey = &kCCAResizePreviewStartFrameKey;
static const void *kCCAResizePresentationTransitionKey = &kCCAResizePresentationTransitionKey;
static const void *kCCAResizePresentationLayoutKey = &kCCAResizePresentationLayoutKey;
static const void *kCCAResizePresentationSizeOverrideKey = &kCCAResizePresentationSizeOverrideKey;
static const void *kCCAResizeGlyphHandoffViewKey = &kCCAResizeGlyphHandoffViewKey;
static const void *kCCAResizeGlyphHandoffHostsKey = &kCCAResizeGlyphHandoffHostsKey;
static const void *kCCAResizeSuppressedGesturesKey = &kCCAResizeSuppressedGesturesKey;
static const void *kCCAQuickAccessAnimationTokenKey = &kCCAQuickAccessAnimationTokenKey;
static const void *kCCAAddSheetModuleKey = &kCCAAddSheetModuleKey;
static const void *kCCAAddSheetControllerKey = &kCCAAddSheetControllerKey;
static const void *kCCAAddSheetContextKey = &kCCAAddSheetContextKey;
static const void *kCCASliderGlyphColoredKey = &kCCASliderGlyphColoredKey;
static const void *kCCASliderGlyphOriginalImageKey = &kCCASliderGlyphOriginalImageKey;
static const void *kCCASliderGlyphOriginalTintKey = &kCCASliderGlyphOriginalTintKey;
static const void *kCCASliderClassificationKey = &kCCASliderClassificationKey;
static const void *kCCASliderLastAppliedColorKey = &kCCASliderLastAppliedColorKey;
static const void *kCCASliderGlyphOriginalAlphaKey = &kCCASliderGlyphOriginalAlphaKey;
static const void *kCCASliderGlyphOriginalHiddenKey = &kCCASliderGlyphOriginalHiddenKey;
static const void *kCCASliderGlyphSymbolStateKey = &kCCASliderGlyphSymbolStateKey;
static const void *kCCASliderOverscrollBaseTransformKey = &kCCASliderOverscrollBaseTransformKey;
static const void *kCCASliderOverscrollStartValueKey = &kCCASliderOverscrollStartValueKey;
static const void *kCCASliderOverscrollAmountKey = &kCCASliderOverscrollAmountKey;
static const void *kCCASliderOverscrollTargetKey = &kCCASliderOverscrollTargetKey;
static const void *kCCANowPlayingLayoutModeKey = &kCCANowPlayingLayoutModeKey;
static const void *kCCAMediaRouteGlyphShrinkKey = &kCCAMediaRouteGlyphShrinkKey;
static const void *kCCAPagerGestureKey = &kCCAPagerGestureKey;
static const void *kCCAPagerModulePanDependencyKey = &kCCAPagerModulePanDependencyKey;
static const void *kCCAEditDismissPanKey = &kCCAEditDismissPanKey;
static const void *kCCAPageIndicatorPanKey = &kCCAPageIndicatorPanKey;
static const void *kCCAPageIndicatorCountKey = &kCCAPageIndicatorCountKey;
static const void *kCCAPageIndicatorDraggingKey = &kCCAPageIndicatorDraggingKey;
static const void *kCCAPagerStartPageKey = &kCCAPagerStartPageKey;
static const void *kCCAPagerSuppressedGesturesKey = &kCCAPagerSuppressedGesturesKey;
static const void *kCCAPagerNativeScrollViewKey = &kCCAPagerNativeScrollViewKey;
static const void *kCCAPagerNativeOffsetKey = &kCCAPagerNativeOffsetKey;
static const void *kCCANativeScrollBaseSublayerTransformKey = &kCCANativeScrollBaseSublayerTransformKey;
static const void *kCCANativeScrollOpeningCompensationKey = &kCCANativeScrollOpeningCompensationKey;
static const void *kCCANativeScrollBaselineKey = &kCCANativeScrollBaselineKey;
static const void *kCCANativeScrollBoundsOriginBaselineKey = &kCCANativeScrollBoundsOriginBaselineKey;
static const void *kCCANativeScrollContentInsetBaselineKey = &kCCANativeScrollContentInsetBaselineKey;
static const void *kCCAPageHiddenKey = &kCCAPageHiddenKey;
static const void *kCCAPageAnimationTokenKey = &kCCAPageAnimationTokenKey;
static const void *kCCAPagerVisualLayerTransformKey = &kCCAPagerVisualLayerTransformKey;
static const void *kCCAPagerVisualLayerOpacityKey = &kCCAPagerVisualLayerOpacityKey;
static const void *kCCAPagerVisualLayerFiltersKey = &kCCAPagerVisualLayerFiltersKey;
static const void *kCCAPagerVisualBlurFilterKey = &kCCAPagerVisualBlurFilterKey;
static const void *kCCAExpansionPageGeometrySyncKey = &kCCAExpansionPageGeometrySyncKey;
static const void *kCCAExpansionCollectionLayerPositionKey = &kCCAExpansionCollectionLayerPositionKey;
static const void *kCCAExpansionGeometryHoldTokenKey = &kCCAExpansionGeometryHoldTokenKey;

typedef struct CCUILayoutSize { NSUInteger width; NSUInteger height; } CCUILayoutSize;
typedef struct CCUILayoutPoint { NSUInteger x; NSUInteger y; } CCUILayoutPoint;
typedef struct CCUILayoutRect { CCUILayoutPoint origin; CCUILayoutSize size; } CCUILayoutRect;
static NSUInteger CCAPageForRect(CCUILayoutRect rect);
static UIView *CCACompositedSnapshotView(UIView *view);
static UIView *CCAWindowCropSnapshotView(UIView *view);
static UIView *CCAWindowCropSnapshotForWindowRect(UIWindow *window, CGRect crop);
static UIView *CCAFindSubviewWithClassName(UIView *root, NSString *className);
static NSArray<NSString *> *gCCAProviderOrder;
static NSDictionary<NSString *, NSValue *> *gCCAProviderSizes;
static BOOL gCCADragInProgress = NO;
static __weak UIView *gCCAActiveDragModuleView = nil;
static NSString *gCCAActiveDragModuleIdentifier = nil;
static BOOL gCCAResizeInProgress = NO;
static __weak UIView *gCCAActiveResizeModuleView = nil;
// One physical home press/swipe can reach both CCAster's bottom-zone pan and
// the native dismissal seams. Whichever exits edit mode first opens this
// window so the sibling request from the same gesture cannot also close CC.
static CFTimeInterval gCCAEditExitConsumedUntil = 0;
static CFTimeInterval gCCAExpandedChromeRevealUntil = 0;
static NSUInteger gCCACurrentPage = 0;
static NSUInteger gCCAPageCount = 1;
static NSUInteger gCCAOccupiedPageCount = 1;
static CGFloat gCCAPagerInteractiveTranslation = 0.0;
static NSUInteger gCCAPagerInteractiveStartPage = 0;
static CGFloat gCCAPagerInteractiveProgress = 0.0;
static CFTimeInterval gCCAPagerInteractiveBeganTime = 0.0;
static CGFloat gCCAPagerHeldScale = 1.0;
static CGFloat gCCAPagerHeldAlphaFactor = 1.0;
static CGFloat gCCAPagerViscousProgress = 0.0;
static CGFloat gCCAPagerPreviousRawProgress = 0.0;
static CGFloat gCCAPagerFilteredVelocity = 0.0;
static CGFloat gCCAPagerJelloScaleX = 1.0;
static CGFloat gCCAPagerJelloScaleY = 1.0;
static CFTimeInterval gCCAPagerLastSampleTime = 0.0;
static NSUInteger gCCAPendingPageAfterRebuild = NSNotFound;

static BOOL CCAModuleViewIsPageHidden(UIView *view) {
    return [objc_getAssociatedObject(view, kCCAPageHiddenKey) boolValue];
}

static BOOL CCAIsActiveDragModuleIdentifier(NSString *identifier) {
    return gCCADragInProgress && identifier.length && gCCAActiveDragModuleIdentifier.length && [identifier isEqualToString:gCCAActiveDragModuleIdentifier];
}

static CGFloat CCAGridVisibleWidth(void) {
    return kCCAGridCellSize * 4.0 + kCCAGridGap * 3.0;
}

static CGFloat CCAGridHorizontalCenteringCompensationForFrame(CGRect frame, CCUILayoutRect layoutRect, CGFloat containerWidth) {
    if (containerWidth < 1.0) containerWidth = CGRectGetWidth(UIScreen.mainScreen.bounds);
    CGFloat nativeBase = CGRectGetMinX(frame) - (CGFloat)layoutRect.origin.x * kCCAGridStep;
    CGFloat nativeFootprint = nativeBase * 2.0 + CCAGridVisibleWidth();
    return MAX(0.0, containerWidth - nativeFootprint) * 0.5;
}

static NSUInteger CCAVisualPageSpacerRows(void) {
    CGFloat screenHeight = CGRectGetHeight(UIScreen.mainScreen.bounds);
    CGFloat extraHeight = screenHeight - kCCAPageSpan;
    if (extraHeight <= kCCAGridStep * 0.35) return 0;
    return (NSUInteger)ceil(extraHeight / kCCAGridStep);
}

static CGFloat CCAVisualPageSpan(void) {
    return (CGFloat)(kCCAMinimumGridRows + CCAVisualPageSpacerRows()) * kCCAGridStep;
}

static BOOL CCAInteractivePagingGeometryActive(void) {
    return gCCAPresentationNativeSettlePending ||
        gCCAPresentationPageHandoffActive ||
        gCCAPagerTransitionActive ||
        gCCAPagerScrubbingActive ||
        fabs(gCCAPagerInteractiveTranslation) > 0.01;
}

static void CCAApplyCompactGridSpacingToLayoutOptions(id layoutOptions) {
    if (!gEnabled || !layoutOptions) return;
    Ivar spacingIvar = class_getInstanceVariable(object_getClass(layoutOptions), "_itemSpacing");
    if (!spacingIvar) spacingIvar = class_getInstanceVariable([layoutOptions class], "_itemSpacing");
    uint8_t *bytes = (uint8_t *)(__bridge void *)layoutOptions;
    Ivar edgeIvar = class_getInstanceVariable([layoutOptions class], "_itemEdgeSize");
    CGFloat nativeGap = spacingIvar ? *((CGFloat *)(bytes + ivar_getOffset(spacingIvar))) : 0.0;
    CGFloat nativeCell = edgeIvar ? *((CGFloat *)(bytes + ivar_getOffset(edgeIvar))) : 0.0;
    BOOL alreadyCompact = nativeCell > 0.0 && nativeGap > 0.0 &&
        fabs(nativeCell - kCCAGridCellSize) < 0.5 &&
        fabs(nativeGap - kCCAGridGap) < 0.5;
    if (!alreadyCompact) {
        if (nativeCell > 1.0) kCCAGridCellSize = round(nativeCell * kCCAGridCellScale);
        if (nativeGap > 1.0) kCCAGridGap = round(nativeGap * kCCAGridGapScale);
    }
    if (spacingIvar) *((CGFloat *)(bytes + ivar_getOffset(spacingIvar))) = kCCAGridGap;
    if (edgeIvar) *((CGFloat *)(bytes + ivar_getOffset(edgeIvar))) = kCCAGridCellSize;
}

static NSArray<UIViewController *> *CCACollectModuleControllers(UIViewController *root);
static CGRect CCAVisibleModuleFrame(UIViewController *module, UIViewController *overlay);
static UIViewController *CCAConnectivityChild(UIViewController *controller, NSString *className);
static BOOL CCAIsLandscapeOrientation(UIView *view);
static void CCARefreshSettledCompactMediaSnapshot(UIViewController *overlay);
static void CCABeginConnectivityOpeningTransition(UIViewController *controller);
static void CCAStartConnectivityOpeningReveal(UIPresentationController *presentationController);
static void CCABeginConnectivityClosingTransition(UIPresentationController *presentationController);
static void CCAFinishConnectivityClosingTransition(UIViewController *controller);
static void CCAConfigureConnectivityLayout(UIViewController *controller);
static UIView *CCANewConnectivityMaterialView(UIView *root);
static void CCAConfigureNowPlayingLayout(UIView *nowPlayingView);
static CGRect CCAExpandedConnectivityFrameForClass(NSString *className, CGSize containerSize);
static CGRect CCAConnectivityScreenFrameForView(UIView *view);
static void CCAOpenPendingConnectivityDetailFromPresentation(UIPresentationController *presentationController);
static void CCAInstallStandaloneConnectivityDetailMethod(void);
static void CCAStopConnectivitySubviewAnimations(UIView *view, BOOL includeRoot);
static BOOL CCAIsConnectivityTransitionLeafController(UIViewController *controller);
static void CCASetConnectivityProxyPressed(UIControl *sender, BOOL pressed);

static UIPanGestureRecognizer *CCAFindActiveControlCenterPresentationPan(UIView *root) {
    if (!root) return nil;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:root];
    UIPanGestureRecognizer *fallback = nil;
    while (queue.count) {
        UIView *view = queue.firstObject;
        [queue removeObjectAtIndex:0];
        for (UIGestureRecognizer *gesture in view.gestureRecognizers) {
            if (![gesture isKindOfClass:[UIPanGestureRecognizer class]] ||
                [objc_getAssociatedObject(gesture, kCCAOwnGestureKey) boolValue] ||
                gesture.numberOfTouches == 0 ||
                (gesture.state != UIGestureRecognizerStateBegan && gesture.state != UIGestureRecognizerStateChanged)) continue;
            UIPanGestureRecognizer *pan = (UIPanGestureRecognizer *)gesture;
            CGPoint location = [pan locationInView:root];
            CGPoint velocity = [pan velocityInView:root];
            BOOL plausiblePull = location.x >= CGRectGetWidth(root.bounds) * 0.45 &&
                location.y <= CGRectGetHeight(root.bounds) * 0.72 && velocity.y > -40.0;
            if (!plausiblePull) continue;
            NSString *name = NSStringFromClass(pan.class);
            if ([name containsString:@"PanSystemGestureRecognizer"] ||
                [name containsString:@"ControlCenter"] || [name containsString:@"StatusBar"]) return pan;
            if (!fallback) fallback = pan;
        }
        [queue addObjectsFromArray:view.subviews];
    }
    return fallback;
}

static NSString *CCAThemedPageIndicatorSymbolForPage(NSUInteger page);

static NSString *CCAPageIndicatorSymbolForPage(NSUInteger page) {
    if (page == 0) return @"heart.fill";
    if (page >= gCCAOccupiedPageCount) return @"circle";
    return CCAThemedPageIndicatorSymbolForPage(page) ?: @"circle.fill";
}

static CGFloat CCAPageIndicatorBasePointSizeForPage(NSUInteger page) {
    return page == 0 ? 16.0 : 12.0;
}

static CGFloat CCAPageProgressForScrubY(CGFloat y, CGFloat step, NSUInteger pageCount) {
    if (pageCount <= 1 || step <= 0.0) return 0.0;
    return (y - step * 0.5) / step;
}

static UIScrollView *CCANativeScrollViewForOverlay(UIViewController *overlay) {
    if (!overlay) return nil;
    @try {
        id scrollView = [(id)overlay valueForKey:@"overlayScrollView"];
        return [scrollView isKindOfClass:[UIScrollView class]] ? scrollView : nil;
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static NSValue *CCAEnsureNativeScrollBaseline(UIViewController *overlay) {
    NSValue *baseline = objc_getAssociatedObject(overlay, kCCANativeScrollBaselineKey);
    if (baseline) return baseline;
    UIScrollView *scrollView = CCANativeScrollViewForOverlay(overlay);
    if (!scrollView) return nil;
    baseline = [NSValue valueWithCGPoint:scrollView.contentOffset];
    objc_setAssociatedObject(overlay, kCCANativeScrollBaselineKey, baseline, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(overlay, kCCANativeScrollBoundsOriginBaselineKey, [NSValue valueWithCGPoint:scrollView.bounds.origin], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(overlay, kCCANativeScrollContentInsetBaselineKey, [NSValue valueWithUIEdgeInsets:scrollView.contentInset], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return baseline;
}

static BOOL CCAViewTreeContainsClassName(UIView *root, NSString *className) {
    if (!root || !className.length) return NO;
    if ([NSStringFromClass(root.class) isEqualToString:className]) return YES;
    for (UIView *subview in root.subviews) {
        if (CCAViewTreeContainsClassName(subview, className)) return YES;
    }
    return NO;
}

static void CCASuppressNativeOverflowMaterialForOverlay(UIViewController *overlay) {
    UIScrollView *scrollView = CCANativeScrollViewForOverlay(overlay);
    if (!scrollView || gCCAExpandedModuleOpen) return;
    CGSize overlaySize = overlay.view.bounds.size;
    for (UIView *child in scrollView.subviews) {
        if (CCAViewTreeContainsClassName(child, @"CCUIModuleCollectionView")) continue;
        if (CCAViewTreeContainsClassName(child, @"CCUIHeaderPocketView")) continue;
        BOOL hostsSensorHeader = CCAViewTreeContainsClassName(child, @"CCUISensorAttributionPrivacyHeaderView");
        BOOL fullScreenSurface = fabs(CGRectGetWidth(child.bounds) - overlaySize.width) < 8.0 &&
                                 fabs(CGRectGetHeight(child.bounds) - overlaySize.height) < 8.0;
        if (!hostsSensorHeader || !fullScreenSurface) continue;
        for (UIView *surface in child.subviews) {
            NSString *name = NSStringFromClass(surface.class);
            if ([name isEqualToString:@"MTMaterialView"] || [name containsString:@"VisualEffect"] || [name containsString:@"Backdrop"]) {
                surface.hidden = YES;
                surface.alpha = 0.0;
                surface.layer.opacity = 0.0;
            }
        }
    }
}

static void CCASuppressHeaderPocketMaterialForOverlay(UIViewController *overlay) {
    if (!overlay.view || gCCAExpandedModuleOpen) return;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:overlay.view];
    while (queue.count) {
        UIView *candidate = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([NSStringFromClass(candidate.class) isEqualToString:@"CCUIHeaderPocketView"]) {
            CGFloat pocketHeight = CGRectGetHeight(candidate.bounds);
            for (UIView *child in candidate.subviews) {
                if ([NSStringFromClass(child.class) isEqualToString:@"MTMaterialView"]) {
                    child.hidden = YES;
                    child.alpha = 0.0;
                    child.layer.opacity = 0.0;
                    continue;
                }
                BOOL bottomHairline = CGRectGetWidth(child.bounds) > CGRectGetWidth(candidate.bounds) * 0.5 &&
                                      CGRectGetHeight(child.bounds) <= 2.5 &&
                                      fabs(CGRectGetMaxY(child.frame) - pocketHeight) <= 3.0;
                if (bottomHairline) {
                    child.hidden = YES;
                    child.alpha = 0.0;
                    child.layer.opacity = 0.0;
                }
            }
            for (CALayer *layer in candidate.layer.sublayers) {
                BOOL bottomHairline = CGRectGetWidth(layer.bounds) > CGRectGetWidth(candidate.bounds) * 0.5 &&
                                      CGRectGetHeight(layer.bounds) <= 2.5 &&
                                      fabs(CGRectGetMaxY(layer.frame) - pocketHeight) <= 3.0;
                if (bottomHairline) {
                    layer.hidden = YES;
                    layer.opacity = 0.0;
                }
            }
            continue;
        }
        [queue addObjectsFromArray:candidate.subviews];
    }
}

static void CCAClampNativeScrollViewForOverlay(UIViewController *overlay) {
    UIScrollView *scrollView = CCANativeScrollViewForOverlay(overlay);
    if (!scrollView) return;
    CCASuppressNativeOverflowMaterialForOverlay(overlay);
    CCASuppressHeaderPocketMaterialForOverlay(overlay);
    CGSize viewportSize = scrollView.bounds.size;
    scrollView.alwaysBounceVertical = NO;
    scrollView.alwaysBounceHorizontal = NO;
    scrollView.bounces = NO;
    scrollView.showsVerticalScrollIndicator = NO;
    scrollView.showsHorizontalScrollIndicator = NO;
    NSValue *contentInsetValue = objc_getAssociatedObject(overlay, kCCANativeScrollContentInsetBaselineKey);
    UIEdgeInsets contentInset = contentInsetValue ? contentInsetValue.UIEdgeInsetsValue : scrollView.contentInset;
    if (!contentInsetValue) {
        NSValue *boundsOriginValue = objc_getAssociatedObject(overlay, kCCANativeScrollBoundsOriginBaselineKey);
        CGPoint boundsOrigin = boundsOriginValue ? boundsOriginValue.CGPointValue : scrollView.bounds.origin;
        if (contentInset.top < 1.0 && boundsOrigin.y < -1.0) contentInset.top = -boundsOrigin.y;
        objc_setAssociatedObject(overlay, kCCANativeScrollContentInsetBaselineKey, [NSValue valueWithUIEdgeInsets:contentInset], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    scrollView.contentInset = contentInset;
    scrollView.scrollIndicatorInsets = UIEdgeInsetsZero;
    scrollView.contentSize = viewportSize;
    NSValue *boundsOriginValue = objc_getAssociatedObject(overlay, kCCANativeScrollBoundsOriginBaselineKey);
    CGPoint boundsOrigin = boundsOriginValue ? boundsOriginValue.CGPointValue : scrollView.bounds.origin;
    if (!boundsOriginValue) {
        objc_setAssociatedObject(overlay, kCCANativeScrollBoundsOriginBaselineKey, [NSValue valueWithCGPoint:boundsOrigin], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    CGRect bounds = scrollView.bounds;
    if (fabs(bounds.origin.x - boundsOrigin.x) > 0.25 || fabs(bounds.origin.y - boundsOrigin.y) > 0.25) {
        bounds.origin = boundsOrigin;
        scrollView.bounds = bounds;
    }
    NSValue *offsetValue = objc_getAssociatedObject(overlay, kCCANativeScrollBaselineKey);
    CGPoint offset = offsetValue ? offsetValue.CGPointValue : scrollView.contentOffset;
    if (!offsetValue) {
        objc_setAssociatedObject(overlay, kCCANativeScrollBaselineKey, [NSValue valueWithCGPoint:offset], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (fabs(scrollView.contentOffset.x - offset.x) > 0.25 || fabs(scrollView.contentOffset.y - offset.y) > 0.25) {
        [scrollView setContentOffset:offset animated:NO];
    }
    if (gCCAExpandedModuleOpen) return;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:overlay.view];
    while (queue.count) {
        UIView *candidate = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if (candidate != scrollView && [candidate isKindOfClass:[UIScrollView class]]) {
            NSString *className = NSStringFromClass(candidate.class);
            BOOL nativePager = [className isEqualToString:@"CCUIModuleCollectionView"] || [className isEqualToString:@"FCUIActivityListView"];
            UIScrollView *internal = (UIScrollView *)candidate;
            if (nativePager) {
                internal.alwaysBounceVertical = NO;
                internal.alwaysBounceHorizontal = NO;
                internal.bounces = NO;
                internal.showsVerticalScrollIndicator = NO;
                internal.showsHorizontalScrollIndicator = NO;
                internal.scrollIndicatorInsets = UIEdgeInsetsZero;
                if ([className isEqualToString:@"FCUIActivityListView"]) internal.scrollEnabled = NO;
                if ([className isEqualToString:@"CCUIModuleCollectionView"]) [internal setContentOffset:CGPointZero animated:NO];
            } else {
                internal.alwaysBounceVertical = NO;
                internal.alwaysBounceHorizontal = NO;
                internal.bounces = NO;
                internal.showsVerticalScrollIndicator = NO;
                internal.showsHorizontalScrollIndicator = NO;
                internal.scrollIndicatorInsets = UIEdgeInsetsZero;
                internal.scrollEnabled = NO;
                CGSize size = internal.contentSize;
                BOOL smallerThanViewport = size.height <= CGRectGetHeight(internal.bounds) + 2.0 &&
                                           size.width <= CGRectGetWidth(internal.bounds) + 2.0;
                if (smallerThanViewport) internal.contentSize = internal.bounds.size;
                BOOL genericScroll = [className isEqualToString:@"UIScrollView"];
                BOOL nearOverlayHeight = CGRectGetHeight(internal.bounds) >= CGRectGetHeight(overlay.view.bounds) - 12.0;
                BOOL oversizedInBothAxes = size.height > CGRectGetHeight(internal.bounds) + 48.0 &&
                                           size.width > CGRectGetWidth(internal.bounds) + 48.0;
                if (genericScroll && nearOverlayHeight && oversizedInBothAxes) {
                    internal.contentInset = UIEdgeInsetsZero;
                    internal.contentSize = internal.bounds.size;
                    [internal setContentOffset:CGPointZero animated:NO];
                    internal.clipsToBounds = YES;
                }
            }
        }
        [queue addObjectsFromArray:candidate.subviews];
    }
}

static void CCAReassertNativeScrollClampForOverlay(UIViewController *overlay) {
    if (!overlay || gCCAExpandedModuleOpen) return;
    CCAClampNativeScrollViewForOverlay(overlay);
    for (NSNumber *delay in @[@0.016, @0.050, @0.120, @0.240]) {
        __weak UIViewController *weakOverlay = overlay;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIViewController *strongOverlay = weakOverlay;
            if (strongOverlay && !gCCAExpandedModuleOpen) CCAClampNativeScrollViewForOverlay(strongOverlay);
        });
    }
}

static void CCARestoreNativeScrollBaseline(UIViewController *overlay) {
    UIScrollView *scrollView = CCANativeScrollViewForOverlay(overlay);
    NSValue *baseline = CCAEnsureNativeScrollBaseline(overlay);
    if (!scrollView || !baseline) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    CCAClampNativeScrollViewForOverlay(overlay);
    CGPoint target = baseline.CGPointValue;
    CGPoint current = scrollView.contentOffset;
    if (fabs(current.x - target.x) > 0.25 || fabs(current.y - target.y) > 0.25) {
        [scrollView setContentOffset:target animated:NO];
    }
    [CATransaction commit];
}

static CGFloat CCANativeScrollOpeningCompensation(UIViewController *overlay) {
    if (!gCCAUseNativeOpeningCompensation) return 0.0;
    UIScrollView *scrollView = CCANativeScrollViewForOverlay(overlay);
    NSValue *baselineValue = objc_getAssociatedObject(overlay, kCCANativeScrollBoundsOriginBaselineKey);
    if (!scrollView || !baselineValue) return 0.0;
    if (gCCAControlCenterPresentationState != 1 && gCCAControlCenterPresentationState != 2) {
        objc_setAssociatedObject(overlay, kCCANativeScrollOpeningCompensationKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return 0.0;
    }
    CALayer *presentation = (CALayer *)scrollView.layer.presentationLayer;
    CGPoint visibleOrigin = presentation ? presentation.bounds.origin : scrollView.bounds.origin;
    CGFloat compensation = MIN(160.0, MAX(-160.0, visibleOrigin.y - baselineValue.CGPointValue.y));
    objc_setAssociatedObject(overlay, kCCANativeScrollOpeningCompensationKey, @(compensation), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return compensation;
}

static void CCAStabilizeNativeScrollPresentationForOverlay(UIViewController *overlay) {
    UIScrollView *scrollView = CCANativeScrollViewForOverlay(overlay);
    if (!scrollView) return;
    NSValue *baseValue = objc_getAssociatedObject(scrollView, kCCANativeScrollBaseSublayerTransformKey);
    if (!baseValue) {
        baseValue = [NSValue valueWithCATransform3D:scrollView.layer.sublayerTransform];
        objc_setAssociatedObject(scrollView, kCCANativeScrollBaseSublayerTransformKey, baseValue, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    CATransform3D base = baseValue.CATransform3DValue;
    if (gCCAControlCenterPresentationState == 1) {
        NSValue *boundsBaselineValue = objc_getAssociatedObject(overlay, kCCANativeScrollBoundsOriginBaselineKey);
        NSValue *offsetBaselineValue = objc_getAssociatedObject(overlay, kCCANativeScrollBaselineKey);
        [scrollView.layer removeAnimationForKey:@"bounds"];
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        if (boundsBaselineValue) {
            CGRect bounds = scrollView.layer.bounds;
            bounds.origin = boundsBaselineValue.CGPointValue;
            scrollView.layer.bounds = bounds;
        }
        if (offsetBaselineValue) {
            [scrollView setContentOffset:offsetBaselineValue.CGPointValue animated:NO];
        }
        [CATransaction commit];
    }
    CGFloat compensation = CCANativeScrollOpeningCompensation(overlay);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    scrollView.layer.sublayerTransform = CATransform3DTranslate(base, 0.0, compensation, 0.0);
    [CATransaction commit];
}

static void CCAFinishNativeScrollOpeningStabilization(UIViewController *overlay) {
    UIScrollView *scrollView = CCANativeScrollViewForOverlay(overlay);
    UIView *duplicateHost = [overlay.view viewWithTag:kCCAOwnedDuplicateHostTag];
    NSValue *baseValue = objc_getAssociatedObject(scrollView, kCCANativeScrollBaseSublayerTransformKey);
    CATransform3D base = baseValue ? baseValue.CATransform3DValue : CATransform3DIdentity;
    objc_setAssociatedObject(overlay, kCCANativeScrollOpeningCompensationKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    // State 2 means CCUI's bounds presentation has reached its resting value.
    // Drop the inverse correction's stale presentation tree immediately; a
    // model-only reset leaves the previous +114pt frame visible once more.
    [scrollView.layer removeAllAnimations];
    [duplicateHost.layer removeAllAnimations];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    scrollView.layer.sublayerTransform = base;
    duplicateHost.transform = CGAffineTransformIdentity;
    [CATransaction commit];
    [CATransaction flush];
}

// Directly regenerating iOS 16's live provider can desynchronize its parallel
// identifier/size state, producing stretched sliders and compact-view labels.
// Keep provider mutation disabled until CCAster owns an independent preview map.
static BOOL const gCCAUseNativeLiveReflow = NO;
static NSMutableDictionary<NSString *, NSValue *> *gCCANativeLayoutRects;
static NSMutableDictionary<NSString *, NSArray<NSNumber *> *> *gCCACustomOrigins;
static NSMutableDictionary<NSString *, NSValue *> *gCCABaseLayoutSizes;
static NSMutableDictionary<NSString *, NSArray<NSNumber *> *> *gCCACustomSizes;
static NSMutableDictionary<NSString *, NSString *> *gCCADuplicateFamilies;
static NSMutableDictionary<NSString *, NSNumber *> *gCCAConnectivityOptimisticStates;
static UIImage *gCCASheetScreenImage;
static NSDictionary<NSString *, NSValue *> *gCCASheetModuleFrames;

static CGRect CCARemoveButtonFrameForModuleFrame(CGRect moduleFrame) {
    CGFloat originOffset = kCCARemoveVisualCenterOffset - kCCARemoveHitSize * 0.5;
    return CGRectMake(CGRectGetMinX(moduleFrame) + originOffset,
                      CGRectGetMinY(moduleFrame) + originOffset,
                      kCCARemoveHitSize, kCCARemoveHitSize);
}

static void CCANormalizePreviewCornerRadii(UIView *root, CGSize moduleSize, CGFloat radius) {
    if (!root) return;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:root];
    while (queue.count) {
        UIView *candidate = queue.firstObject;
        [queue removeObjectAtIndex:0];
        BOOL fillsModule = fabs(CGRectGetWidth(candidate.bounds) - moduleSize.width) <= 4.0 &&
                           fabs(CGRectGetHeight(candidate.bounds) - moduleSize.height) <= 4.0;
        if (fillsModule) {
            candidate.layer.cornerRadius = radius;
            candidate.layer.cornerCurve = kCACornerCurveContinuous;
            candidate.layer.masksToBounds = YES;
            candidate.layer.borderWidth = 0.0;
        }
        [queue addObjectsFromArray:candidate.subviews];
    }
}


@interface CCALowBlurView : UIView
@end

@implementation CCALowBlurView

+ (Class)layerClass {
    return NSClassFromString(@"CABackdropLayer") ?: CALayer.class;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.userInteractionEnabled = NO;
    self.backgroundColor = UIColor.clearColor;
    self.opaque = NO;
    [self cca_configureLowBlur];
    return self;
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self cca_configureLowBlur];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self cca_configureLowBlur];
}

- (void)cca_configureLowBlur {
    Class backdropClass = NSClassFromString(@"CABackdropLayer");
    if (!backdropClass || ![self.layer isKindOfClass:backdropClass]) return;
    @try {
        [self.layer setValue:@NO forKey:@"layerUsesCoreImageFilters"];
        [self.layer setValue:@YES forKey:@"windowServerAware"];
        if (![self.layer valueForKey:@"groupName"]) [self.layer setValue:NSUUID.UUID.UUIDString forKey:@"groupName"];
        Class filterClass = NSClassFromString(@"CAFilter");
        SEL selector = NSSelectorFromString(@"filterWithName:");
        id blur = nil;
        if (filterClass && [filterClass respondsToSelector:selector]) {
            blur = ((id (*)(Class, SEL, NSString *))objc_msgSend)(filterClass, selector, @"gaussianBlur");
        }
        if (blur) {
            [blur setValue:@3.0 forKey:@"inputRadius"];
            [blur setValue:@YES forKey:@"inputNormalizeEdges"];
            self.layer.filters = @[ blur ];
        }
    } @catch (__unused NSException *exception) {}
}

@end

@interface CCATopFadeView : UIView
@end

@implementation CCATopFadeView {
    UIView *_blurView;
    CAGradientLayer *_maskLayer;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.userInteractionEnabled = NO;
    self.backgroundColor = UIColor.clearColor;
    self.opaque = NO;

    _blurView = [[CCALowBlurView alloc] initWithFrame:self.bounds];
    _blurView.userInteractionEnabled = NO;
    [self addSubview:_blurView];

    _maskLayer = [CAGradientLayer layer];
    _maskLayer.colors = @[
        (__bridge id)UIColor.blackColor.CGColor,
        (__bridge id)[UIColor.blackColor colorWithAlphaComponent:0.96].CGColor,
        (__bridge id)[UIColor.blackColor colorWithAlphaComponent:0.78].CGColor,
        (__bridge id)[UIColor.blackColor colorWithAlphaComponent:0.34].CGColor,
        (__bridge id)[UIColor.blackColor colorWithAlphaComponent:0.10].CGColor,
        (__bridge id)UIColor.clearColor.CGColor,
    ];
    _maskLayer.locations = @[ @0.0, @0.34, @0.62, @0.82, @0.94, @1.0 ];
    _maskLayer.startPoint = CGPointMake(0.5, 0.0);
    _maskLayer.endPoint = CGPointMake(0.5, 1.0);
    _blurView.layer.mask = _maskLayer;

    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _blurView.frame = self.bounds;
    _maskLayer.frame = _blurView.bounds;
    [CATransaction commit];
}

@end

static BOOL CCARectArraysNearlyEqual(NSArray<NSValue *> *a, NSArray<NSValue *> *b) {
    if (a == b) return YES;
    if (a.count != b.count) return NO;
    for (NSUInteger i = 0; i < a.count; i++) {
        CGRect ra = a[i].CGRectValue;
        CGRect rb = b[i].CGRectValue;
        if (fabs(CGRectGetMinX(ra) - CGRectGetMinX(rb)) > 0.25 ||
            fabs(CGRectGetMinY(ra) - CGRectGetMinY(rb)) > 0.25 ||
            fabs(CGRectGetWidth(ra) - CGRectGetWidth(rb)) > 0.25 ||
            fabs(CGRectGetHeight(ra) - CGRectGetHeight(rb)) > 0.25) return NO;
    }
    return YES;
}

@interface CCAEditGridView : UIView
@property (nonatomic, copy) NSArray<NSValue *> *slotRects;
@property (nonatomic, copy) NSArray<NSValue *> *occupiedRects;
@property (nonatomic, copy) NSArray<NSValue *> *landingRects;
@property (nonatomic, strong) NSMutableArray<CAShapeLayer *> *circleLayers;
@property (nonatomic, strong) CAShapeLayer *landingLayer;
@property (nonatomic) CGFloat landingCornerRadius;
@property (nonatomic) NSUInteger columns;
@property (nonatomic) NSUInteger rows;
@end

@implementation CCAEditGridView
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.clearColor;
        self.userInteractionEnabled = NO;
        self.opaque = NO;
        self.circleLayers = [NSMutableArray array];
        self.landingLayer = [CAShapeLayer layer];
        self.landingLayer.fillColor = [UIColor.whiteColor colorWithAlphaComponent:0.08].CGColor;
        self.landingLayer.strokeColor = [UIColor.whiteColor colorWithAlphaComponent:0.48].CGColor;
        self.landingLayer.lineWidth = 2.0;
        self.landingLayer.opacity = 0.0;
        [self.layer addSublayer:self.landingLayer];
    }
    return self;
}
- (BOOL)rect:(CGRect)slot overlapsAny:(NSArray<NSValue *> *)rects {
    CGPoint center = CGPointMake(CGRectGetMidX(slot), CGRectGetMidY(slot));
    for (NSValue *value in rects) if (CGRectContainsPoint(CGRectInset(value.CGRectValue, -2.0, -2.0), center)) return YES;
    return NO;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    self.landingLayer.frame = self.bounds;
}
- (void)setSlotRects:(NSArray<NSValue *> *)slotRects {
    if (CCARectArraysNearlyEqual(_slotRects, slotRects)) return;
    _slotRects = [slotRects copy];
    for (CAShapeLayer *layer in self.circleLayers) [layer removeFromSuperlayer];
    [self.circleLayers removeAllObjects];
    for (NSValue *value in _slotRects) {
        CGRect slot = value.CGRectValue;
        CGFloat diameter = MIN(CGRectGetWidth(slot), CGRectGetHeight(slot)) * 0.92;
        CGRect circle = CGRectMake(CGRectGetMidX(slot) - diameter * 0.5, CGRectGetMidY(slot) - diameter * 0.5, diameter, diameter);
        CAShapeLayer *layer = [CAShapeLayer layer];
        layer.path = [UIBezierPath bezierPathWithOvalInRect:circle].CGPath;
        layer.fillColor = [UIColor.whiteColor colorWithAlphaComponent:0.06].CGColor;
        [self.layer addSublayer:layer];
        [self.circleLayers addObject:layer];
    }
    [self updateCircleVisibilityAnimated:NO];
}
- (void)setOccupiedRects:(NSArray<NSValue *> *)occupiedRects {
    if (CCARectArraysNearlyEqual(_occupiedRects, occupiedRects)) return;
    _occupiedRects = [occupiedRects copy];
    [self updateCircleVisibilityAnimated:YES];
}
- (void)setLandingRects:(NSArray<NSValue *> *)landingRects {
    if (CCARectArraysNearlyEqual(_landingRects, landingRects)) return;
    _landingRects = [landingRects copy];
    // The footprint is only state for fading the background cells. Drawing a
    // second rounded outline reads as a module left behind and also exposes any
    // transient disagreement between the visual grid and the native layout.
    self.landingLayer.path = nil;
    self.landingLayer.opacity = 0.0f;
    [self updateCircleVisibilityAnimated:!gCCADragInProgress];
}
- (void)updateCircleVisibilityAnimated:(BOOL)animated {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (NSUInteger index = 0; index < self.circleLayers.count && index < self.slotRects.count; index++) {
        CAShapeLayer *layer = self.circleLayers[index];
        CGRect slot = self.slotRects[index].CGRectValue;
        float target = ([self rect:slot overlapsAny:self.occupiedRects] || [self rect:slot overlapsAny:self.landingRects]) ? 0.0f : 1.0f;
        if (animated && fabs(layer.opacity - target) > 0.01) {
            CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
            fade.fromValue = @(layer.presentationLayer ? ((CALayer *)layer.presentationLayer).opacity : layer.opacity);
            fade.toValue = @(target);
            fade.duration = 0.12;
            fade.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
            [layer addAnimation:fade forKey:@"CCAsterCellFade"];
        }
        layer.opacity = target;
    }
    [CATransaction commit];
}
@end

@interface CCAEditTouchShield : UIView
@property (nonatomic, weak) UIView *passthroughView;
@end

@interface CCAExpandedHitButton : UIButton
@end

@interface CCAConnectivityForceButton : UIButton
@end

@interface CCAQuickAccessHostView : UIView
@end

@implementation CCAExpandedHitButton
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.hidden || !self.userInteractionEnabled || self.alpha <= 0.01) return NO;
    // 1x1 modules have almost no surface left once generous chrome zones are
    // carved out — shrink their acceptance so the module stays draggable.
    BOOL small = [objc_getAssociatedObject(self, kCCASmallModuleChromeKey) boolValue];
    if (self.tag == kCCAResizeButtonTag) {
        // Corner-based grabber for every size. Previously large modules accepted
        // a 16pt-expanded (74pt) square that swallowed most of the tile; now the
        // handle only claims a small square hugging the bottom-right corner, so
        // the rest of the module — even a 1x1 — is free to start a drag.
        CGFloat cornerSize = small ? 26.0 : 34.0;
        CGRect corner = CGRectMake(CGRectGetWidth(self.bounds) - cornerSize,
                                   CGRectGetHeight(self.bounds) - cornerSize,
                                   cornerSize,
                                   cornerSize);
        return CGRectContainsPoint(corner, point);
    }
    CGFloat expansion = self.tag == kCCARemoveButtonTag ? 8.0 :
        (self.tag == kCCAAddControlButtonTag ? 12.0 : 0.0);
    return CGRectContainsPoint(CGRectInset(self.bounds, -expansion, -expansion), point);
}
@end

@implementation CCAConnectivityForceButton
- (void)cca_checkForceTouches:(NSSet<UITouch *> *)touches event:(UIEvent *)event {
    if ([objc_getAssociatedObject(self, kCCAConnectivityForceFiredKey) boolValue]) return;
    UITouch *touch = touches.anyObject;
    if (!touch || touch.maximumPossibleForce <= 0.0) return;
    CGFloat pressure = touch.force / touch.maximumPossibleForce;
    if (pressure < 0.54 && touch.force < 2.0) return;
    objc_setAssociatedObject(self, kCCAConnectivityForceFiredKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    CCASetConnectivityProxyPressed(self, NO);
    id coordinator = ((id (*)(id, SEL))objc_msgSend)(NSClassFromString(@"CCAsterCoordinator"), @selector(shared));
    SEL action = @selector(connectivityTileProxyForcePressed:);
    if (coordinator && [coordinator respondsToSelector:action]) ((void (*)(id, SEL, id))objc_msgSend)(coordinator, action, self);
    [self cancelTrackingWithEvent:event];
}
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    objc_setAssociatedObject(self, kCCAConnectivityForceFiredKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [super touchesBegan:touches withEvent:event];
    [self cca_checkForceTouches:touches event:event];
}
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesMoved:touches withEvent:event];
    [self cca_checkForceTouches:touches event:event];
}
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    BOOL fired = [objc_getAssociatedObject(self, kCCAConnectivityForceFiredKey) boolValue];
    if (!fired) [super touchesEnded:touches withEvent:event];
    objc_setAssociatedObject(self, kCCAConnectivityForceFiredKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesCancelled:touches withEvent:event];
    objc_setAssociatedObject(self, kCCAConnectivityForceFiredKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
@end

@implementation CCAEditTouchShield

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.clearColor;
        self.opaque = NO;
    }
    return self;
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.hidden || !self.userInteractionEnabled || self.alpha <= 0.01) return nil;
    UIViewController *overlay = nil;
    for (UIViewController *candidate in gOverlayControllers.allObjects) {
        if (candidate.view == self.superview) { overlay = candidate; break; }
    }
    if (!overlay) return [super hitTest:point withEvent:event];
    CGPoint overlayPoint = [self convertPoint:point toView:overlay.view];
    NSArray<UIViewController *> *modules = CCACollectModuleControllers(overlay);
    // Pass 1: edit chrome always wins. Checking every module's buttons before
    // any module surface prevents iteration order (or a stale button frame)
    // from letting a neighboring module claim the touch, which previously fed
    // remove-button taps to the overlay drag recognizer instead.
    for (UIViewController *module in modules) {
        if (module.view.hidden || module.view.alpha <= 0.01 || CCAModuleViewIsPageHidden(module.view)) continue;
        UIButton *remove = objc_getAssociatedObject(module.view, kCCARemoveButtonKey);
        UIButton *resize = objc_getAssociatedObject(module.view, kCCAResizeButtonKey);
        if (remove && !remove.hidden && remove.alpha > 0.01 && remove.userInteractionEnabled) {
            CGRect removeFrame = [remove.superview convertRect:remove.frame toView:overlay.view];
            CGRect removeHitFrame = CGRectInset(removeFrame, -14.0, -14.0);
            if (CGRectContainsPoint(removeHitFrame, overlayPoint)) return self;
        }
        if (resize && !resize.hidden && resize.alpha > 0.01 && resize.userInteractionEnabled) {
            BOOL small = [objc_getAssociatedObject(resize, kCCASmallModuleChromeKey) boolValue];
            CGRect resizeFrame = [resize.superview convertRect:resize.frame toView:overlay.view];
            CGRect resizeHitFrame = small ? CGRectMake(CGRectGetMaxX(resizeFrame) - 30.0,
                                                       CGRectGetMaxY(resizeFrame) - 30.0,
                                                       30.0,
                                                       30.0) : CGRectInset(resizeFrame, -16.0, -16.0);
            if (CGRectContainsPoint(resizeHitFrame, overlayPoint)) return resize;
        }
        for (UIButton *button in @[remove ?: (UIButton *)NSNull.null, resize ?: (UIButton *)NSNull.null]) {
            if ((id)button == NSNull.null || button.hidden || button.alpha <= 0.01 || !button.userInteractionEnabled) continue;
            CGPoint buttonPoint = [self convertPoint:point toView:button];
            UIView *buttonHit = [button hitTest:buttonPoint withEvent:event];
            if (buttonHit) return buttonHit;
            if (button.tag == kCCAResizeButtonTag) {
                BOOL small = [objc_getAssociatedObject(button, kCCASmallModuleChromeKey) boolValue];
                CGRect resizeHit = small ? CGRectMake(CGRectGetWidth(button.bounds) - 30.0,
                                                      CGRectGetHeight(button.bounds) - 30.0,
                                                      30.0,
                                                      30.0) : CGRectInset(button.bounds, -16.0, -16.0);
                if (CGRectContainsPoint(resizeHit, buttonPoint)) return button;
            }
        }
    }
    // Pass 2: module surfaces (drag/rearrange territory).
    for (UIViewController *module in modules) {
        if (module.view.hidden || module.view.alpha <= 0.01 || CCAModuleViewIsPageHidden(module.view)) continue;
        if (CGRectContainsPoint(CGRectInset(CCAVisibleModuleFrame(module, overlay), -2.0, -2.0), overlayPoint)) {
            return self;
        }
    }
    UIView *passthrough = self.passthroughView;
    if (passthrough && !passthrough.hidden && passthrough.alpha > 0.01 && passthrough.userInteractionEnabled) {
        CGPoint passthroughPoint = [self convertPoint:point toView:passthrough];
        UIView *hit = [passthrough hitTest:passthroughPoint withEvent:event];
        if (hit) return hit;
    }
    return nil;
}

@end

@implementation CCAQuickAccessHostView
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.hidden || !self.userInteractionEnabled || self.alpha <= 0.01) return NO;
    if (CGRectContainsPoint(self.bounds, point)) return YES;
    for (UIView *subview in self.subviews) {
        if (subview.hidden || subview.alpha <= 0.01 || !subview.userInteractionEnabled) continue;
        CGPoint childPoint = [self convertPoint:point toView:subview];
        if ([subview pointInside:childPoint withEvent:event]) return YES;
    }
    return NO;
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (![self pointInside:point withEvent:event]) return nil;
    for (UIView *subview in self.subviews.reverseObjectEnumerator) {
        if (subview.hidden || subview.alpha <= 0.01 || !subview.userInteractionEnabled) continue;
        CGPoint childPoint = [self convertPoint:point toView:subview];
        UIView *hit = [subview hitTest:childPoint withEvent:event];
        if (hit) return hit;
    }
    return [super hitTest:point withEvent:event];
}
@end

@interface CCAOwnedDuplicateHostView : UIView
@end

@implementation CCAOwnedDuplicateHostView
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.hidden || self.alpha <= 0.01) return NO;
    for (UIView *subview in self.subviews.reverseObjectEnumerator) {
        if (subview.hidden || subview.alpha <= 0.01 || !subview.userInteractionEnabled) continue;
        CGPoint childPoint = [self convertPoint:point toView:subview];
        if ([subview pointInside:childPoint withEvent:event]) return YES;
    }
    return NO;
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (![self pointInside:point withEvent:event]) return nil;
    for (UIView *subview in self.subviews.reverseObjectEnumerator) {
        if (subview.hidden || subview.alpha <= 0.01 || !subview.userInteractionEnabled) continue;
        CGPoint childPoint = [self convertPoint:point toView:subview];
        UIView *hit = [subview hitTest:childPoint withEvent:event];
        if (hit) return hit;
    }
    return nil;
}
@end

@interface CCABrightnessGlyphView : UIView
@property (nonatomic, strong) CAShapeLayer *diskLayer;
@property (nonatomic, strong) CAShapeLayer *rayLayer;
- (void)setLevel:(CGFloat)level color:(UIColor *)color animated:(BOOL)animated;
@end

@implementation CCABrightnessGlyphView
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.userInteractionEnabled = NO;
        self.backgroundColor = UIColor.clearColor;
        _diskLayer = [CAShapeLayer layer];
        _rayLayer = [CAShapeLayer layer];
        _rayLayer.fillColor = nil;
        _rayLayer.lineWidth = 2.2;
        _rayLayer.lineCap = kCALineCapRound;
        [self.layer addSublayer:_rayLayer];
        [self.layer addSublayer:_diskLayer];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.diskLayer.frame = self.bounds;
    self.rayLayer.frame = self.bounds;
}

- (void)setLevel:(CGFloat)level color:(UIColor *)color animated:(BOOL)animated {
    level = MIN(1.0, MAX(0.0, level));
    CGPoint center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
    CGFloat diskRadius = level <= 0.25 ? 5.1 : 6.1;
    CGFloat innerRadius = 9.5;
    // At the floor each ray is only a rounded capsule; at full brightness it
    // extends a little beyond the stock sun.max silhouette, matching iOS 18's
    // more expressive low-to-high ray travel.
    CGFloat outerRadius = 11.0 + 6.0 * level;
    UIBezierPath *disk = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(center.x - diskRadius,
                                                                           center.y - diskRadius,
                                                                           diskRadius * 2.0,
                                                                           diskRadius * 2.0)];
    UIBezierPath *rays = [UIBezierPath bezierPath];
    for (NSUInteger index = 0; index < 8; index++) {
        CGFloat angle = (CGFloat)index * (CGFloat)M_PI_4;
        [rays moveToPoint:CGPointMake(center.x + cos(angle) * innerRadius,
                                      center.y + sin(angle) * innerRadius)];
        [rays addLineToPoint:CGPointMake(center.x + cos(angle) * outerRadius,
                                         center.y + sin(angle) * outerRadius)];
    }

    if (animated) {
        CGPathRef currentDiskPath = ((CAShapeLayer *)self.diskLayer.presentationLayer).path ?: self.diskLayer.path;
        if (currentDiskPath) {
            CABasicAnimation *diskAnimation = [CABasicAnimation animationWithKeyPath:@"path"];
            diskAnimation.fromValue = (__bridge id)currentDiskPath;
            diskAnimation.toValue = (__bridge id)disk.CGPath;
            diskAnimation.duration = 0.12;
            diskAnimation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
            [self.diskLayer addAnimation:diskAnimation forKey:@"CCAsterBrightnessDisk"];
        }
        CGPathRef currentRayPath = ((CAShapeLayer *)self.rayLayer.presentationLayer).path ?: self.rayLayer.path;
        if (currentRayPath) {
            CABasicAnimation *pathAnimation = [CABasicAnimation animationWithKeyPath:@"path"];
            pathAnimation.fromValue = (__bridge id)currentRayPath;
            pathAnimation.toValue = (__bridge id)rays.CGPath;
            pathAnimation.duration = 0.09;
            pathAnimation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
            [self.rayLayer addAnimation:pathAnimation forKey:@"CCAsterBrightnessRays"];
        }
        CGColorRef currentColor = ((CAShapeLayer *)self.diskLayer.presentationLayer).fillColor ?: self.diskLayer.fillColor;
        if (currentColor && !CGColorEqualToColor(currentColor, color.CGColor)) {
            for (CAShapeLayer *layer in @[self.diskLayer, self.rayLayer]) {
                NSString *keyPath = layer == self.diskLayer ? @"fillColor" : @"strokeColor";
                CGColorRef fromColor = layer == self.diskLayer ?
                    (((CAShapeLayer *)layer.presentationLayer).fillColor ?: layer.fillColor) :
                    (((CAShapeLayer *)layer.presentationLayer).strokeColor ?: layer.strokeColor);
                CABasicAnimation *colorAnimation = [CABasicAnimation animationWithKeyPath:keyPath];
                colorAnimation.fromValue = (__bridge id)fromColor;
                colorAnimation.toValue = (__bridge id)color.CGColor;
                colorAnimation.duration = 0.13;
                [layer addAnimation:colorAnimation forKey:@"CCAsterBrightnessColor"];
            }
        }
    }
    self.diskLayer.path = disk.CGPath;
    self.rayLayer.path = rays.CGPath;
    self.diskLayer.fillColor = color.CGColor;
    self.rayLayer.strokeColor = color.CGColor;
}
@end

@interface SBUIPowerDownViewControllerFactory : NSObject
+ (UIViewController *)newPowerDownViewController;
@end

@interface SBUIPowerDownViewController : UIViewController
@end

@interface CCAOwnedDuplicateModuleViewController : UIViewController
@property (nonatomic, copy) NSString *moduleIdentifier;
@property (nonatomic, copy) NSString *baseModuleIdentifier;
@end

@implementation CCAOwnedDuplicateModuleViewController
@synthesize moduleIdentifier = _moduleIdentifier;
@synthesize baseModuleIdentifier = _baseModuleIdentifier;

- (instancetype)initWithModuleIdentifier:(NSString *)moduleIdentifier baseIdentifier:(NSString *)baseIdentifier {
    self = [super initWithNibName:nil bundle:nil];
    if (!self) return nil;
    _moduleIdentifier = [moduleIdentifier copy];
    _baseModuleIdentifier = [baseIdentifier copy];
    return self;
}

- (void)loadView {
    UIView *view = [[UIView alloc] initWithFrame:CGRectZero];
    view.backgroundColor = UIColor.clearColor;
    view.opaque = NO;
    view.clipsToBounds = YES;
    view.layer.cornerCurve = kCACornerCurveContinuous;
    self.view = view;
}

@end

static BOOL CCAPreferenceBool(NSString *key, BOOL fallback) {
    Boolean valid = false;
    Boolean value = CFPreferencesGetAppBooleanValue((__bridge CFStringRef)key, kCCAPrefsDomain, &valid);
    return valid ? (BOOL)value : fallback;
}

static void CCALoadPrefs(void) {
    CFPreferencesAppSynchronize(kCCAPrefsDomain);
    gEnabled = CCAPreferenceBool(@"Enabled", YES);
    gQuickAccessButtonsEnabled = CCAPreferenceBool(@"QuickAccessButtonsEnabled", YES);
    gPagingPreferenceEnabled = CCAPreferenceBool(@"PagingEnabled", YES);
    gPagingEnabled = gPagingPreferenceEnabled;
    gBlankSpaceGestureEnabled = CCAPreferenceBool(@"BlankSpaceGestureEnabled", YES);
    gAddButtonEnabled = CCAPreferenceBool(@"AddButtonEnabled", YES);
    gPowerButtonEnabled = CCAPreferenceBool(@"PowerButtonEnabled", YES);
    gRemovalButtonsEnabled = CCAPreferenceBool(@"RemovalButtonsEnabled", YES);
    gModuleBordersEnabled = CCAPreferenceBool(@"ModuleBordersEnabled", YES);
    gBorderBreathingEnabled = CCAPreferenceBool(@"BorderBreathingEnabled", YES);
    gHapticsEnabled = CCAPreferenceBool(@"HapticsEnabled", YES);
}

static BOOL CCAIsOverlayController(UIViewController *controller) {
    NSString *name = NSStringFromClass(controller.class);
    return [name containsString:@"ControlCenterOverlayViewController"] ||
           [name isEqualToString:@"CCUIModularControlCenterOverlayViewController"];
}

static UIViewController *CCAFindOverlayController(UIViewController *root) {
    if (!root) return nil;
    NSMutableArray<UIViewController *> *queue = [NSMutableArray arrayWithObject:root];
    while (queue.count) {
        UIViewController *candidate = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if (CCAIsOverlayController(candidate)) return candidate;
        [queue addObjectsFromArray:candidate.childViewControllers];
        if (candidate.presentedViewController) [queue addObject:candidate.presentedViewController];
    }
    return nil;
}

static BOOL CCAIsModuleController(UIViewController *controller) {
    return [controller isKindOfClass:[CCAOwnedDuplicateModuleViewController class]] ||
           [NSStringFromClass(controller.class) containsString:@"ContentModuleContainerViewController"];
}

static BOOL CCAIsOwnedDuplicateModuleController(UIViewController *controller) {
    return [controller isKindOfClass:[CCAOwnedDuplicateModuleViewController class]];
}

static UIView *CCAPresentationWrapperForModuleController(UIViewController *controller) {
    UIView *candidate = controller.view.superview;
    for (NSUInteger depth = 0; candidate && candidate.superview && depth < 6; depth++) {
        if ([NSStringFromClass(candidate.superview.class) containsString:@"ContentModuleContainerView"]) {
            return candidate;
        }
        candidate = candidate.superview;
    }
    return controller.view.superview;
}


static void CCAHaptic(void) {
    if (!gHapticsEnabled) return;
    UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [generator prepare];
    [generator impactOccurred];
}

static NSString *CCAModuleIdentifier(UIViewController *controller) {
    NSArray<NSString *> *keys = @[@"moduleIdentifier", @"_moduleIdentifier"];
    for (NSString *key in keys) {
        @try {
            id value = [controller valueForKey:key];
            if ([value isKindOfClass:[NSString class]] && [value length]) return value;
        } @catch (__unused NSException *exception) {}
    }
    @try {
        id module = [controller valueForKey:@"module"];
        id context = [module valueForKey:@"contentModuleContext"];
        id value = [context valueForKey:@"moduleIdentifier"];
        if ([value isKindOfClass:[NSString class]]) return value;
    } @catch (__unused NSException *exception) {}
    return nil;
}

static UIViewController *CCAModuleControllerForView(UIView *view) {
    UIResponder *responder = view;
    while (responder) {
        if ([responder isKindOfClass:[UIViewController class]] && CCAIsModuleController((UIViewController *)responder)) {
            return (UIViewController *)responder;
        }
        responder = responder.nextResponder;
    }
    for (UIViewController *overlay in gOverlayControllers.allObjects) {
        for (UIViewController *module in CCACollectModuleControllers(overlay)) {
            if (view == module.view || [view isDescendantOfView:module.view]) return module;
        }
    }
    return nil;
}

static NSString *CCAIdentifierFromObject(id object) {
    if (!object) return nil;
    if ([object isKindOfClass:[UIViewController class]]) {
        NSString *identifier = CCAModuleIdentifier((UIViewController *)object);
        if (identifier.length) return identifier;
    }
    for (NSString *key in @[@"moduleIdentifier", @"_moduleIdentifier"]) {
        @try {
            id value = [object valueForKey:key];
            if ([value isKindOfClass:[NSString class]] && [value length]) return value;
        } @catch (__unused NSException *exception) {}
    }
    @try {
        id context = [object valueForKey:@"contentModuleContext"];
        id value = [context valueForKey:@"moduleIdentifier"];
        if ([value isKindOfClass:[NSString class]] && [value length]) return value;
    } @catch (__unused NSException *exception) {}
    return nil;
}

static BOOL CCADuplicateIdentifierIsNumbered(NSString *identifier) {
    if (![identifier isKindOfClass:[NSString class]]) return NO;
    NSRange range = [identifier rangeOfString:@"#" options:NSBackwardsSearch];
    if (range.location == NSNotFound || range.location == 0 || range.location + 1 >= identifier.length) return NO;
    NSString *suffix = [identifier substringFromIndex:range.location + 1];
    if (!suffix.length) return NO;
    return [suffix rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location == NSNotFound && suffix.integerValue > 1;
}

static NSString *CCADuplicateFamilyIdentifierForIdentifier(NSString *identifier) {
    NSString *registered = gCCADuplicateFamilies[identifier];
    if (registered.length) return registered;
    if (CCADuplicateIdentifierIsNumbered(identifier)) {
        NSRange range = [identifier rangeOfString:@"#" options:NSBackwardsSearch];
        return [identifier substringToIndex:range.location];
    }
    return identifier;
}

static BOOL CCAModuleIdentifierSupportsOwnedDuplicates(NSString *identifier) {
    NSString *familyIdentifier = CCADuplicateFamilyIdentifierForIdentifier(identifier).lowercaseString;
    return [familyIdentifier containsString:@"ccaster.connectivity"];
}

static BOOL CCAIdentifierIsLegacyPhysicalDuplicate(NSString *identifier) {
    if (![identifier isKindOfClass:[NSString class]]) return NO;
    NSString *lower = identifier.lowercaseString;
    return [lower containsString:@".instance."] || [lower containsString:@"moduleinstance"];
}

static void CCASaveDuplicateFamilies(void) {
    CFPreferencesSetAppValue(CFSTR("COSMICDuplicateFamilies"), (__bridge CFPropertyListRef)[gCCADuplicateFamilies copy], kCCAPrefsDomain);
    CFPreferencesAppSynchronize(kCCAPrefsDomain);
}

static void CCASaveGridPreferences(void) {
    CFPreferencesSetAppValue(CFSTR("ModuleGridOrigins"), (__bridge CFPropertyListRef)[gCCACustomOrigins copy], kCCAPrefsDomain);
    CFPreferencesSetAppValue(CFSTR("ModuleGridSizes"), (__bridge CFPropertyListRef)[gCCACustomSizes copy], kCCAPrefsDomain);
    CFPreferencesAppSynchronize(kCCAPrefsDomain);
}

static NSString *CCANextDuplicateIdentifierForFamily(NSString *familyIdentifier, NSSet<NSString *> *present) {
    if (!familyIdentifier.length) return nil;
    NSMutableSet<NSString *> *used = [NSMutableSet setWithArray:gCCADuplicateFamilies.allKeys ?: @[]];
    for (NSString *identifier in present) if ([identifier isKindOfClass:[NSString class]]) [used addObject:identifier];
    for (NSUInteger index = 2; index < 100; index++) {
        NSString *candidate = [NSString stringWithFormat:@"%@#%lu", familyIdentifier, (unsigned long)index];
        if (![used containsObject:candidate]) return candidate;
    }
    return nil;
}

static NSUInteger CCADuplicateCountForFamily(NSString *familyIdentifier, NSSet<NSString *> *present) {
    if (!familyIdentifier.length) return 0;
    NSUInteger count = [present containsObject:familyIdentifier] ? 1 : 0;
    for (NSString *identifier in gCCADuplicateFamilies) {
        if ([gCCADuplicateFamilies[identifier] isEqualToString:familyIdentifier]) count++;
    }
    return count;
}

static NSString *CCAPrettyNameForIdentifier(NSString *identifier) {
    NSString *last = [identifier componentsSeparatedByString:@"."].lastObject ?: identifier;
    last = [last stringByReplacingOccurrencesOfString:@"Module" withString:@""];
    if (!last.length) return identifier;
    NSMutableString *result = [NSMutableString string];
    for (NSUInteger index = 0; index < last.length; index++) {
        unichar character = [last characterAtIndex:index];
        if (index > 0 && [[NSCharacterSet uppercaseLetterCharacterSet] characterIsMember:character]) [result appendString:@" "];
        [result appendFormat:@"%C", character];
    }
    return result.length ? [result capitalizedString] : identifier;
}

static NSString *CCAFriendlyNameForIdentifier(NSString *identifier) {
    NSString *lower = identifier.lowercaseString;
    // Needles verified against /System/Library/ControlCenter/Bundles on iOS 16.
    NSDictionary<NSString *, NSString *> *known = @{
        @"ccaster.connectivity.airplane": @"Airplane Mode",
        @"ccaster.connectivity.wifi": @"Wi-Fi",
        @"ccaster.connectivity.airdrop": @"AirDrop",
        @"ccaster.connectivity.cellular": @"Cellular Data",
        @"ccaster.connectivity.bluetooth": @"Bluetooth",
        @"ccaster.connectivity.hotspot": @"Personal Hotspot",
        @"ccaster.connectivity.vpn": @"VPN",
        @"orientationlock": @"Orientation",
        @"focusui": @"Focus",
        @"nowplaying": @"Now Playing",
        @"controlcenter.audio": @"Volume",
        @"displaymodule": @"Brightness",
        @"connectivitymodule": @"Connectivity",
        @"appearancemodule": @"Dark Mode",
        @"lowpowermodule": @"Low Power Mode",
        @"qrcodemodule": @"Code Scanner",
        @"controlcenter.timer": @"Timer",
        @"flashlightmodule": @"Flashlight",
        @"control-center.stopwatch": @"Stopwatch",
        @"autobrightness": @"Auto-Brightness",
        @"accessibility.controlcenter.general": @"Accessibility Shortcuts",
        @"accessibility.controlcenter.guidedaccess": @"Guided Access",
        @"accessibility.controlcenter.sounddetection": @"Sound Recognition",
        @"accessibility.controlcenter.text.size": @"Text Size",
        @"accessibility.controlcenter.hearingdevices": @"Hearing",
        @"controlcenter.screencapture": @"Screen Recording",
        @"shazamkit": @"Music Recognition",
        @"airplaymirroring": @"Screen Mirroring",
        @"spokennotifications": @"Announce Notifications",
        @"silencecalls": @"Silence Calls",
        @"nfccontrolcenter": @"NFC Tag Reader",
        @"keyboardbrightness": @"Keyboard Brightness",
        @"systempapercontrolcenter": @"Notes",
        @"control-center.quicknote": @"Quick Note",
        @"home.compactcontrolcenter": @"Home",
        @"home.controlcenter": @"Home Controls",
        @"appletvremote": @"Apple TV Remote",
        @"voicememos": @"Voice Memos",
        @"walletmodule": @"Wallet",
        @"feedbackassistant": @"Feedback Assistant",
        @"mutemodule": @"Silent Mode",
    };
    for (NSString *needle in known) {
        if ([lower containsString:needle]) return known[needle];
    }
    return nil;
}

static id CCADynamicSharedInstance(NSString *className) {
    Class cls = NSClassFromString(className);
    return [cls respondsToSelector:@selector(sharedInstance)] ? ((id (*)(id, SEL))objc_msgSend)(cls, @selector(sharedInstance)) : nil;
}

static id CCADynamicValue(id target, NSArray<NSString *> *selectors) {
    for (NSString *selectorName in selectors) {
        SEL selector = NSSelectorFromString(selectorName);
        if ([target respondsToSelector:selector]) return ((id (*)(id, SEL))objc_msgSend)(target, selector);
    }
    return nil;
}

static BOOL CCADynamicBool(id target, NSArray<NSString *> *selectors, BOOL fallback) {
    for (NSString *selectorName in selectors) {
        SEL selector = NSSelectorFromString(selectorName);
        if ([target respondsToSelector:selector]) return ((BOOL (*)(id, SEL))objc_msgSend)(target, selector);
    }
    return fallback;
}

static BOOL CCADynamicSetBool(id target, NSArray<NSString *> *selectors, BOOL value) {
    for (NSString *selectorName in selectors) {
        SEL selector = NSSelectorFromString(selectorName);
        if (![target respondsToSelector:selector]) continue;
        NSMethodSignature *signature = [target methodSignatureForSelector:selector];
        const char *returnType = signature.methodReturnType;
        if (returnType && (returnType[0] == @encode(BOOL)[0] || returnType[0] == @encode(bool)[0])) {
            BOOL accepted = ((BOOL (*)(id, SEL, BOOL))objc_msgSend)(target, selector, value);
            if (accepted) return YES;
            continue;
        }
        ((void (*)(id, SEL, BOOL))objc_msgSend)(target, selector, value);
        return YES;
    }
    return NO;
}

static BOOL CCASetBluetoothEnabled(BOOL enabled) {
    id manager = CCADynamicSharedInstance(@"BluetoothManager");
    BOOL changed = NO;
    for (NSString *selectorName in @[@"setPowered:", @"setEnabled:"]) {
        SEL selector = NSSelectorFromString(selectorName);
        if (![manager respondsToSelector:selector]) continue;
        BOOL accepted = ((BOOL (*)(id, SEL, BOOL))objc_msgSend)(manager, selector, enabled);
        changed = changed || accepted;
    }
    return changed;
}

static BOOL CCAConnectivitySelectedForIdentifier(NSString *identifier);
static BOOL CCAConnectivityActiveForIdentifier(NSString *identifier);

static NSString *CCAConnectivityStatusForIdentifier(NSString *identifier) {
    NSString *lower = identifier.lowercaseString;
    if (![lower containsString:@"ccaster.connectivity"]) return nil;
    if ([lower containsString:@".wifi"]) {
        id manager = CCADynamicSharedInstance(@"SBWiFiManager") ?: CCADynamicSharedInstance(@"WiFiManager");
        id name = CCADynamicValue(manager, @[@"currentNetworkName", @"networkName"]);
        if ([name isKindOfClass:[NSString class]] && [name length]) return name;
        BOOL enabled = CCADynamicBool(manager, @[@"wiFiEnabled", @"isWiFiEnabled", @"enabled", @"isEnabled", @"powered"], NO);
        return enabled ? @"On" : @"Off";
    }
    if ([lower containsString:@".bluetooth"]) {
        id manager = CCADynamicSharedInstance(@"BluetoothManager");
        NSArray *devices = nil;
        @try { devices = CCADynamicValue(manager, @[@"connectedDevices"]); } @catch (__unused NSException *exception) {}
        for (id device in devices) {
            id name = CCADynamicValue(device, @[@"name"]);
            if ([name isKindOfClass:[NSString class]] && [name length]) return name;
        }
        BOOL enabled = CCADynamicBool(manager, @[@"enabled", @"powered"], NO);
        return enabled ? @"On" : @"Off";
    }
    if ([lower containsString:@".airdrop"]) {
        NSString *value = (__bridge_transfer NSString *)CFPreferencesCopyAppValue(CFSTR("DiscoverableMode"), CFSTR("com.apple.sharingd"));
        if ([value isEqualToString:@"Everyone"]) return @"Everyone";
        if ([value isEqualToString:@"Contacts Only"] || [value isEqualToString:@"Contacts"]) return @"Contacts";
        return @"Off";
    }
    if ([lower containsString:@".airplane"]) {
        id radios = [NSClassFromString(@"RadiosPreferences") new];
        BOOL enabled = CCADynamicBool(radios, @[@"airplaneMode", @"isAirplaneMode"], NO);
        return enabled ? @"On" : @"Off";
    }
    if ([lower containsString:@".cellular"]) return CCAConnectivitySelectedForIdentifier(identifier) ? @"On" : @"Off";
    if ([lower containsString:@".hotspot"]) return CCADynamicBool(CCADynamicSharedInstance(@"SBTetheringController"), @[@"isPersonalHotspotEnabled", @"personalHotspotEnabled", @"tetheringEnabled"], NO) ? @"On" : @"Off";
    if ([lower containsString:@".vpn"]) return CCAConnectivitySelectedForIdentifier(identifier) ? @"On" : @"Off";
    return nil;
}

static BOOL CCAConnectivitySelectedForIdentifier(NSString *identifier) {
    NSString *lower = identifier.lowercaseString;
    if (![lower containsString:@"ccaster.connectivity"]) return NO;
    NSNumber *optimistic = identifier.length ? gCCAConnectivityOptimisticStates[identifier] : nil;
    if (optimistic) return optimistic.boolValue;
    if ([lower containsString:@".wifi"]) {
        id manager = CCADynamicSharedInstance(@"SBWiFiManager") ?: CCADynamicSharedInstance(@"WiFiManager");
        id name = CCADynamicValue(manager, @[@"currentNetworkName", @"networkName"]);
        if ([name isKindOfClass:[NSString class]] && [name length]) return YES;
        return CCADynamicBool(manager, @[@"wiFiEnabled", @"isWiFiEnabled", @"enabled", @"isEnabled", @"powered"], NO);
    }
    if ([lower containsString:@".bluetooth"]) {
        id manager = CCADynamicSharedInstance(@"BluetoothManager");
        id devices = nil;
        @try { devices = CCADynamicValue(manager, @[@"connectedDevices"]); } @catch (__unused NSException *exception) {}
        BOOL hasDevice = [devices respondsToSelector:@selector(count)] ? [devices count] > 0 : devices != nil;
        return CCADynamicBool(manager, @[@"enabled", @"powered"], NO) || hasDevice;
    }
    if ([lower containsString:@".airdrop"]) return ![CCAConnectivityStatusForIdentifier(identifier) isEqualToString:@"Off"];
    if ([lower containsString:@".airplane"]) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{ dlopen("/System/Library/PrivateFrameworks/Preferences.framework/Preferences", RTLD_LAZY); });
        id radios = [NSClassFromString(@"RadiosPreferences") new];
        return CCADynamicBool(radios, @[@"airplaneMode", @"isAirplaneMode"], NO);
    }
    if ([lower containsString:@".cellular"]) {
        id manager = CCADynamicSharedInstance(@"CoreTelephonyClient");
        return CCADynamicBool(manager, @[@"cellularDataEnabled", @"isCellularDataEnabled"], NO);
    }
    if ([lower containsString:@".hotspot"]) return CCADynamicBool(CCADynamicSharedInstance(@"SBTetheringController"), @[@"isPersonalHotspotEnabled", @"personalHotspotEnabled", @"tetheringEnabled"], NO);
    if ([lower containsString:@".vpn"]) {
        NSDictionary *settings = (__bridge_transfer NSDictionary *)CFNetworkCopySystemProxySettings();
        NSArray *scoped = settings[@"__SCOPED__"] ? [settings[@"__SCOPED__"] allKeys] : nil;
        for (NSString *key in scoped) {
            NSString *name = key.lowercaseString;
            if ([name containsString:@"tap"] || [name containsString:@"tun"] || [name containsString:@"ipsec"] || [name containsString:@"ppp"]) return YES;
        }
        return NO;
    }
    return NO;
}

static BOOL CCAConnectivityActiveForIdentifier(NSString *identifier) {
    NSString *lower = identifier.lowercaseString;
    if (![lower containsString:@"ccaster.connectivity"]) return NO;
    if ([lower containsString:@".wifi"]) {
        id manager = CCADynamicSharedInstance(@"SBWiFiManager") ?: CCADynamicSharedInstance(@"WiFiManager");
        id name = CCADynamicValue(manager, @[@"currentNetworkName", @"networkName"]);
        return [name isKindOfClass:[NSString class]] && [name length] > 0;
    }
    if ([lower containsString:@".bluetooth"]) {
        id manager = CCADynamicSharedInstance(@"BluetoothManager");
        id devices = nil;
        @try { devices = CCADynamicValue(manager, @[@"connectedDevices"]); } @catch (__unused NSException *exception) {}
        return [devices respondsToSelector:@selector(count)] ? [devices count] > 0 : devices != nil;
    }
    return CCAConnectivitySelectedForIdentifier(identifier);
}

static BOOL CCAConnectivityAvailableForIdentifier(NSString *identifier) {
    NSString *lower = identifier.lowercaseString;
    if (![lower containsString:@"ccaster.connectivity"]) return YES;
    if ([lower containsString:@".wifi"]) return CCADynamicSharedInstance(@"SBWiFiManager") != nil || CCADynamicSharedInstance(@"WiFiManager") != nil;
    if ([lower containsString:@".bluetooth"]) return CCADynamicSharedInstance(@"BluetoothManager") != nil;
    if ([lower containsString:@".airplane"]) return NSClassFromString(@"RadiosPreferences") != nil;
    if ([lower containsString:@".cellular"]) {
        id manager = CCADynamicSharedInstance(@"CoreTelephonyClient");
        return manager && CCADynamicBool(manager, @[@"supportsCellular"], NO);
    }
    if ([lower containsString:@".hotspot"]) return CCADynamicSharedInstance(@"SBTetheringController") != nil;
    if ([lower containsString:@".vpn"]) return CCAConnectivitySelectedForIdentifier(identifier);
    return YES;
}

static BOOL CCAConnectivitySetIdentifier(NSString *identifier, BOOL enabled) {
    NSString *lower = identifier.lowercaseString;
    if (![lower containsString:@"ccaster.connectivity"]) return NO;
    if ([lower containsString:@".wifi"]) {
        id manager = CCADynamicSharedInstance(@"SBWiFiManager") ?: CCADynamicSharedInstance(@"WiFiManager");
        return CCADynamicSetBool(manager, @[@"setWiFiEnabled:", @"setEnabled:", @"setPowered:"], enabled);
    }
    if ([lower containsString:@".bluetooth"]) {
        return CCASetBluetoothEnabled(enabled);
    }
    if ([lower containsString:@".airplane"]) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{ dlopen("/System/Library/PrivateFrameworks/Preferences.framework/Preferences", RTLD_LAZY); });
        id radios = [NSClassFromString(@"RadiosPreferences") new];
        return CCADynamicSetBool(radios, @[@"setAirplaneMode:"], enabled);
    }
    if ([lower containsString:@".cellular"]) {
        return CCADynamicSetBool(CCADynamicSharedInstance(@"CoreTelephonyClient"), @[@"setCellularDataEnabled:"], enabled);
    }
    if ([lower containsString:@".hotspot"]) {
        return CCADynamicSetBool(CCADynamicSharedInstance(@"SBTetheringController"), @[@"setPersonalHotspotEnabled:", @"setTetheringEnabled:"], enabled);
    }
    return NO;
}

static NSString *CCACategoryForIdentifier(NSString *identifier) {
    NSString *lower = identifier.lowercaseString;
    NSArray<NSArray *> *categories = @[
        @[@"Accessibility", @[@"accessibility.controlcenter", @"magnifier", @"spokennotifications", @"assistivetouch", @"voicecontrol"]],
        @[@"Capture", @[@"cameramodule", @"qrcodemodule", @"screencapture", @"nfccontrolcenter", @"flashlightmodule"]],
        @[@"Clock", @[@"controlcenter.timer", @"control-center.stopwatch", @"alarmmodule"]],
        @[@"Connectivity", @[@"connectivitymodule", @"ccaster.connectivity"]],
        @[@"Display", @[@"displaymodule", @"appearancemodule", @"orientationlock", @"autobrightness", @"truetone", @"nightshift", @"keyboardbrightness"]],
        @[@"Focus", @[@"focusui", @"donotdisturb", @"sleep", @"silencecalls"]],
        @[@"Home", @[@"apple.home"]],
        @[@"Media", @[@"nowplaying", @"controlcenter.audio", @"mutemodule", @"airplaymirroring", @"shazam"]],
        @[@"Notes", @[@"systempapercontrolcenter", @"quicknote"]],
        @[@"Voice Memos", @[@"voicememos"]],
        @[@"Wallet", @[@"walletmodule"]],
    ];
    for (NSArray *pair in categories) {
        for (NSString *needle in pair[1]) {
            if ([lower containsString:needle]) return pair[0];
        }
    }
    return @"Utilities";
}

static NSString *CCAFallbackSymbolForIdentifier(NSString *identifier) {
    NSString *lower = identifier.lowercaseString;
    NSDictionary<NSString *, NSString *> *symbols = @{
        @"ccaster.connectivity.airplane": @"airplane",
        @"ccaster.connectivity.wifi": @"wifi",
        @"ccaster.connectivity.airdrop": @"airdrop",
        @"ccaster.connectivity.cellular": @"antenna.radiowaves.left.and.right",
        @"ccaster.connectivity.bluetooth": @"bluetooth",
        @"ccaster.connectivity.hotspot": @"personalhotspot",
        @"ccaster.connectivity.vpn": @"network",
        @"cameramodule": @"camera.fill",
        @"alarmmodule": @"alarm.fill",
        @"flashlightmodule": @"flashlight.off.fill",
        @"control-center.stopwatch": @"stopwatch",
        @"controlcenter.timer": @"timer",
        @"hearingdevices": @"ear",
        @"magnifiermodule": @"plus.magnifyingglass",
        @"appearancemodule": @"circle.lefthalf.filled",
        @"qrcodemodule": @"qrcode.viewfinder",
        @"controlcenter.screencapture": @"record.circle",
        @"nfccontrolcenter": @"wave.3.right",
        @"appletvremote": @"appletvremote.gen4.fill",
        @"walletmodule": @"wallet.pass.fill",
        @"voicememos": @"waveform",
        @"systempapercontrolcenter": @"note.text",
        @"control-center.quicknote": @"note.text.badge.plus",
        @"lowpowermodule": @"battery.25",
        @"feedbackassistant": @"exclamationmark.bubble.fill",
        @"keyboardbrightness": @"keyboard",
        @"apple.home": @"house.fill",
        @"silencecalls": @"bell.slash.fill",
        @"calculatormodule": @"calculator",
        @"accessibility.controlcenter.general": @"accessibility",
        @"guidedaccess": @"lock.square",
        @"mutemodule": @"bell.fill",
        @"orientationlock": @"lock.rotation",
    };
    for (NSString *needle in symbols) {
        if ([lower containsString:needle]) return symbols[needle];
    }
    return nil;
}

static UIImage *CCACurrentOutputDeviceGlyph(NSString **stateIdentifier) {
    Class controllerClass = NSClassFromString(@"MRUSystemOutputDeviceRouteController");
    if (!controllerClass) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            dlopen("/System/Library/PrivateFrameworks/MediaControls.framework/MediaControls", RTLD_LAZY | RTLD_LOCAL);
        });
        controllerClass = NSClassFromString(@"MRUSystemOutputDeviceRouteController");
    }
    if (!controllerClass || ![controllerClass respondsToSelector:@selector(sharedController)]) return nil;

    id controller = ((id (*)(id, SEL))objc_msgSend)(controllerClass, @selector(sharedController));
    if (![controller respondsToSelector:@selector(systemOutputDeviceAsset)]) return nil;
    id asset = ((id (*)(id, SEL))objc_msgSend)(controller, @selector(systemOutputDeviceAsset));
    if (!asset) return nil;

    Class assetClass = NSClassFromString(@"MRUOutputDeviceAsset");
    id speakerAsset = [assetClass respondsToSelector:@selector(speakerAsset)] ?
        ((id (*)(id, SEL))objc_msgSend)(assetClass, @selector(speakerAsset)) : nil;
    if (speakerAsset && [asset isEqual:speakerAsset]) return nil;

    UIImage *icon = [asset respondsToSelector:@selector(icon)] ?
        ((id (*)(id, SEL))objc_msgSend)(asset, @selector(icon)) : nil;
    if (![icon isKindOfClass:[UIImage class]]) return nil;

    NSString *title = [asset respondsToSelector:@selector(localizedDisplayTitle)] ?
        ((id (*)(id, SEL))objc_msgSend)(asset, @selector(localizedDisplayTitle)) : nil;
    NSInteger type = [asset respondsToSelector:@selector(type)] ?
        ((NSInteger (*)(id, SEL))objc_msgSend)(asset, @selector(type)) : NSNotFound;
    NSInteger kind = [asset respondsToSelector:@selector(kind)] ?
        ((NSInteger (*)(id, SEL))objc_msgSend)(asset, @selector(kind)) : NSNotFound;
    if (stateIdentifier) {
        *stateIdentifier = [NSString stringWithFormat:@"route.%ld.%ld.%@", (long)type, (long)kind, title ?: @""];
    }
    return icon;
}

static void CCAUpdateSliderGlyphColor(UIView *slider, float value, BOOL animate) {
    if (!slider) return;
    // This function runs on every touch-move during a drag (it's called
    // from 5 different hook points: setValue:, layoutSubviews,
    // _setActiveGlyphView:, _applyGlyphState:performConfiguration:, and
    // setGlyphVisible:), so anything here that doesn't depend on `value`
    // must only run ONCE per slider, not on every single call — a given
    // CCUIBaseSliderView instance is a fixed, non-reused view for the
    // lifetime of Control Center (brightness/volume sliders aren't
    // recycled the way table/collection view cells are), so its role
    // never changes after we first figure it out.
    // Cached values: 0 = not a brightness/volume slider (skip forever),
    // 1 = brightness, 2 = volume.
    NSNumber *cachedClassification = objc_getAssociatedObject(slider, kCCASliderClassificationKey);
    BOOL isBrightness = NO, isVolume = NO;
    if (cachedClassification) {
        NSInteger classification = cachedClassification.integerValue;
        if (classification == 0) return;
        isBrightness = (classification == 1);
        isVolume = (classification == 2);
    } else {
        NSMutableString *identity = [NSMutableString string];
        for (UIView *ancestor = slider; ancestor; ancestor = ancestor.superview) {
            if (ancestor.accessibilityLabel.length) [identity appendFormat:@" %@", ancestor.accessibilityLabel.lowercaseString];
        }
        // The flashlight intensity slider is accessibility-labelled "Brightness";
        // never hand it the display slider's sun glyph or yellow theme.
        BOOL isFlashlight = [identity containsString:@"flashlight"];
        if (!isFlashlight) {
            for (UIResponder *responder = slider.nextResponder; responder; responder = responder.nextResponder) {
                if (![responder isKindOfClass:[UIViewController class]]) continue;
                if ([CCAIdentifierFromObject(responder).lowercaseString containsString:@"flashlight"]) { isFlashlight = YES; break; }
            }
        }
        if (!isFlashlight) {
            isBrightness = [identity containsString:@"brightness"];
            isVolume = [identity containsString:@"volume"];
            if (!isBrightness && !isVolume) {
                UIResponder *responder = slider.nextResponder;
                while (responder) {
                    if ([responder isKindOfClass:[UIViewController class]]) {
                        NSString *identifier = CCAIdentifierFromObject(responder).lowercaseString;
                        if ([identifier containsString:@"displaymodule"]) isBrightness = YES;
                        else if ([identifier containsString:@"controlcenter.audio"] || [identifier containsString:@"volumemodule"]) isVolume = YES;
                        if (isBrightness || isVolume) break;
                    }
                    responder = responder.nextResponder;
                }
            }
        }
        NSInteger classification = isFlashlight ? 0 : (isBrightness ? 1 : (isVolume ? 2 : 0));
        objc_setAssociatedObject(slider, kCCASliderClassificationKey, @(classification), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (classification == 0) return;
    }
    if (!isBrightness && !isVolume) return;

    BOOL colored = value >= 0.20f;
    NSNumber *previousState = objc_getAssociatedObject(slider, kCCASliderGlyphColoredKey);
    BOOL stateChanged = previousState && previousState.boolValue != colored;
    UIColor *activeColor = isBrightness ? UIColor.systemYellowColor : [UIColor colorWithRed:0.25 green:0.74 blue:1.0 alpha:1.0];
    UIColor *displayColor = colored ? activeColor : UIColor.whiteColor;
    NSMutableArray<UIView *> *glyphHosts = [NSMutableArray array];
    for (NSString *key in @[@"_activeGlyphView", @"_glyphImageView", @"_glyphPackageView", @"_compensatingGlyphView"]) {
        @try {
            id candidate = [(id)slider valueForKey:key];
            if ([candidate isKindOfClass:[UIView class]] && ![glyphHosts containsObject:candidate]) [glyphHosts addObject:candidate];
        } @catch (__unused NSException *exception) {}
    }
    if (!glyphHosts.count) {
        NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithArray:slider.subviews];
        while (queue.count) {
            UIView *candidate = queue.firstObject;
            [queue removeObjectAtIndex:0];
            NSString *className = NSStringFromClass(candidate.class);
            if (([candidate isKindOfClass:[UIImageView class]] || [className isEqualToString:@"CCUICAPackageView"]) &&
                CGRectGetWidth(candidate.bounds) <= 64.0 && CGRectGetHeight(candidate.bounds) <= 64.0) [glyphHosts addObject:candidate];
            [queue addObjectsFromArray:candidate.subviews];
        }
    }

    for (UIView *host in glyphHosts) {
        if (!objc_getAssociatedObject(host, kCCASliderGlyphOriginalTintKey)) {
            objc_setAssociatedObject(host, kCCASliderGlyphOriginalTintKey, host.tintColor ?: UIColor.whiteColor, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(host, kCCASliderGlyphOriginalAlphaKey, @(host.alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(host, kCCASliderGlyphOriginalHiddenKey, @(host.hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        UIImageView *imageView = [host isKindOfClass:[UIImageView class]] ? (UIImageView *)host : nil;
        if (imageView.image && (!previousState || !previousState.boolValue)) {
            objc_setAssociatedObject(host, kCCASliderGlyphOriginalImageKey, imageView.image, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        void (^changes)(void) = ^{
            host.tintColor = displayColor;
            // The native iOS 16 glyph is a gray punch-out. Keep it hidden at
            // every value and use the same SF-symbol overlay for both sides
            // of the 20% threshold so the inactive state is genuinely white.
            host.alpha = 0.0;
            host.hidden = YES;
            if (imageView) {
                // imageByApplyingSymbolConfiguration: re-renders the symbol
                // and is genuinely expensive. This block runs on every
                // touch-move during a drag, but displayColor only ever
                // flips between two values (active/inactive), so skip the
                // re-render entirely once the image already reflects the
                // current color.
                UIColor *lastAppliedColor = objc_getAssociatedObject(host, kCCASliderLastAppliedColorKey);
                if (![lastAppliedColor isEqual:displayColor]) {
                    UIImage *baseImage = objc_getAssociatedObject(host, kCCASliderGlyphOriginalImageKey) ?: imageView.image;
                    if (baseImage) {
                        UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithHierarchicalColor:displayColor];
                        UIImage *configured = [baseImage imageByApplyingSymbolConfiguration:configuration];
                        imageView.image = configured ?: [baseImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
                        objc_setAssociatedObject(host, kCCASliderLastAppliedColorKey, displayColor, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    }
                }
                imageView.tintColor = displayColor;
            }
        };
        if (animate && stateChanged) {
            [UIView transitionWithView:host duration:0.11 options:UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowAnimatedContent animations:changes completion:nil];
        } else {
            changes();
        }
    }

    if (isBrightness) {
        UIView *existingGlyph = [slider viewWithTag:kCCASliderColorGlyphTag];
        if (existingGlyph && ![existingGlyph isKindOfClass:[CCABrightnessGlyphView class]]) {
            [existingGlyph removeFromSuperview];
            existingGlyph = nil;
        }
        CCABrightnessGlyphView *brightnessGlyph = (CCABrightnessGlyphView *)existingGlyph;
        if (!brightnessGlyph) {
            brightnessGlyph = [[CCABrightnessGlyphView alloc] initWithFrame:CGRectMake(0.0, 0.0, 44.0, 44.0)];
            brightnessGlyph.tag = kCCASliderColorGlyphTag;
            [slider addSubview:brightnessGlyph];
        }
        CGPoint center = ((CGPoint (*)(id, SEL))objc_msgSend)((id)slider, @selector(glyphCenter));
        brightnessGlyph.center = center;
        brightnessGlyph.alpha = 1.0;
        [brightnessGlyph setLevel:value color:displayColor animated:animate];
        [slider bringSubviewToFront:brightnessGlyph];
        objc_setAssociatedObject(slider, kCCASliderGlyphSymbolStateKey, @"brightness.rays", OBJC_ASSOCIATION_COPY_NONATOMIC);
        objc_setAssociatedObject(slider, kCCASliderGlyphColoredKey, @(colored), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }

    // iOS 16 normally renders these glyphs as punch-outs, so changing the
    // backing host's tint does not necessarily alter the composited pixels.
    // Own one SF-symbol layer and drive its variable value directly. This is
    // what gives the sun rays and speaker waves continuous level feedback,
    // instead of snapping among a handful of unrelated static images.
    UIImageSymbolConfiguration *symbolConfiguration =
        [UIImageSymbolConfiguration configurationWithPointSize:24.0 weight:UIImageSymbolWeightRegular];
    CGFloat variableValue = MIN(1.0, MAX(0.0, value));
    BOOL isMutedVolume = isVolume && value <= 0.001f;
    NSString *symbolState = nil;
    UIImage *nativeGlyph = nil;
    NSString *routeState = nil;
    UIImage *routeGlyph = isVolume ? CCACurrentOutputDeviceGlyph(&routeState) : nil;
    if (routeGlyph) {
        symbolState = routeState ?: @"volume.externalRoute";
        UIImageSymbolConfiguration *routeConfiguration =
            [UIImageSymbolConfiguration configurationWithPointSize:26.0 weight:UIImageSymbolWeightRegular];
        nativeGlyph = [routeGlyph imageByApplyingSymbolConfiguration:routeConfiguration] ?: routeGlyph;
    } else if (isMutedVolume) {
        symbolState = @"volume.muted";
        nativeGlyph = [UIImage systemImageNamed:@"speaker.slash.fill" withConfiguration:symbolConfiguration];
    } else if (isVolume) {
        NSUInteger waveCount = value >= 0.66f ? 3 : (value >= 0.33f ? 2 : 1);
        symbolState = [NSString stringWithFormat:@"volume.wave%lu", (unsigned long)waveCount];
        NSString *symbolName = [NSString stringWithFormat:@"speaker.wave.%lu.fill", (unsigned long)waveCount];
        nativeGlyph = [UIImage systemImageNamed:symbolName withConfiguration:symbolConfiguration];
    } else {
        symbolState = @"brightness.variable";
        if (@available(iOS 16.0, *)) {
            nativeGlyph = [UIImage systemImageNamed:@"sun.max.fill"
                                       variableValue:variableValue
                                    withConfiguration:symbolConfiguration];
        }
    }
    if (!nativeGlyph) {
        NSString *fallbackName = isBrightness ? @"sun.max.fill" :
            (isMutedVolume ? @"speaker.slash.fill" :
             (value >= 0.66f ? @"speaker.wave.3.fill" :
              (value >= 0.33f ? @"speaker.wave.2.fill" : @"speaker.wave.1.fill")));
        nativeGlyph = [UIImage systemImageNamed:fallbackName withConfiguration:symbolConfiguration];
    }
    UIImageView *colorGlyph = (UIImageView *)[slider viewWithTag:kCCASliderColorGlyphTag];
    if (nativeGlyph) {
        if (!colorGlyph) {
            colorGlyph = [[UIImageView alloc] initWithFrame:CGRectMake(0.0, 0.0, 44.0, 44.0)];
            colorGlyph.tag = kCCASliderColorGlyphTag;
            colorGlyph.userInteractionEnabled = NO;
            colorGlyph.contentMode = UIViewContentModeCenter;
            colorGlyph.alpha = 1.0;
            [slider addSubview:colorGlyph];
        }
        CGPoint center = ((CGPoint (*)(id, SEL))objc_msgSend)((id)slider, @selector(glyphCenter));
        colorGlyph.center = center;
        [slider bringSubviewToFront:colorGlyph];
        UIImageSymbolConfiguration *colorConfiguration = [UIImageSymbolConfiguration configurationWithHierarchicalColor:displayColor];
        UIImage *configured = [nativeGlyph imageByApplyingSymbolConfiguration:colorConfiguration];
        UIImage *nextImage = configured ?: [nativeGlyph imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        NSString *previousSymbolState = objc_getAssociatedObject(slider, kCCASliderGlyphSymbolStateKey);
        BOOL symbolStateChanged = previousSymbolState.length && ![previousSymbolState isEqualToString:symbolState];

        if (animate && symbolStateChanged && colorGlyph.image) {
            // SymbolEffect.replace is not exposed by iOS 16. Recreate its
            // compact replacement motion with independent outgoing/incoming
            // symbol layers, while shared variable symbols continue tracking
            // the slider without spawning animations on every touch sample.
            for (UIView *view in [slider.subviews copy]) {
                if (view.tag == kCCASliderOutgoingGlyphTag) [view removeFromSuperview];
            }
            UIImageView *outgoing = [[UIImageView alloc] initWithFrame:colorGlyph.frame];
            outgoing.tag = kCCASliderOutgoingGlyphTag;
            outgoing.userInteractionEnabled = NO;
            outgoing.contentMode = colorGlyph.contentMode;
            outgoing.image = colorGlyph.image;
            outgoing.tintColor = colorGlyph.tintColor;
            outgoing.alpha = colorGlyph.alpha;
            [slider insertSubview:outgoing belowSubview:colorGlyph];

            colorGlyph.image = nextImage;
            colorGlyph.tintColor = displayColor;
            colorGlyph.alpha = 0.0;
            colorGlyph.transform = CGAffineTransformMakeScale(0.72, 0.72);
            [UIView animateWithDuration:0.18 delay:0.0
                                options:UIViewAnimationOptionCurveEaseInOut |
                                        UIViewAnimationOptionBeginFromCurrentState |
                                        UIViewAnimationOptionAllowUserInteraction
                             animations:^{
                outgoing.alpha = 0.0;
                outgoing.transform = CGAffineTransformMakeScale(0.72, 0.72);
                colorGlyph.alpha = 1.0;
                colorGlyph.transform = CGAffineTransformIdentity;
            } completion:^(__unused BOOL finished) {
                [outgoing removeFromSuperview];
            }];
        } else if (animate && stateChanged && colorGlyph.image) {
            [UIView transitionWithView:colorGlyph duration:0.13
                               options:UIViewAnimationOptionTransitionCrossDissolve |
                                       UIViewAnimationOptionBeginFromCurrentState |
                                       UIViewAnimationOptionAllowAnimatedContent |
                                       UIViewAnimationOptionAllowUserInteraction
                            animations:^{
                colorGlyph.image = nextImage;
                colorGlyph.tintColor = displayColor;
                colorGlyph.alpha = 1.0;
            } completion:nil];
        } else {
            colorGlyph.image = nextImage;
            colorGlyph.tintColor = displayColor;
            colorGlyph.alpha = 1.0;
            colorGlyph.transform = CGAffineTransformIdentity;
        }
        objc_setAssociatedObject(slider, kCCASliderGlyphSymbolStateKey, symbolState, OBJC_ASSOCIATION_COPY_NONATOMIC);
    } else if (colorGlyph) {
        colorGlyph.alpha = 0.0;
    }
    objc_setAssociatedObject(slider, kCCASliderGlyphColoredKey, @(colored), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void CCAUpdateSliderOverscroll(UIView *slider, UIPanGestureRecognizer *gesture) {
    if (!slider || !gesture || !gEnabled || gEditModeActive) return;
    UIGestureRecognizerState state = gesture.state;
    if (state == UIGestureRecognizerStateBegan) {
        UIView *target = nil;
        for (UIViewController *overlay in gOverlayControllers.allObjects) {
            for (UIViewController *module in CCACollectModuleControllers(overlay)) {
                if (slider == module.view || [slider isDescendantOfView:module.view]) {
                    target = module.view;
                    break;
                }
            }
            if (target) break;
        }
        if (!target) target = slider;
        [target.layer removeAllAnimations];
        objc_setAssociatedObject(slider,
                                 kCCASliderOverscrollTargetKey,
                                 [NSValue valueWithNonretainedObject:target],
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(slider,
                                 kCCASliderOverscrollBaseTransformKey,
                                 [NSValue valueWithCGAffineTransform:target.transform],
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        float value = [slider respondsToSelector:@selector(value)] ?
            ((float (*)(id, SEL))objc_msgSend)((id)slider, @selector(value)) : 0.0f;
        objc_setAssociatedObject(slider, kCCASliderOverscrollStartValueKey, @(value), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(slider, kCCASliderOverscrollAmountKey, @0.0, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    NSValue *baseValue = objc_getAssociatedObject(slider, kCCASliderOverscrollBaseTransformKey);
    if (!baseValue) return;
    UIView *target = [objc_getAssociatedObject(slider, kCCASliderOverscrollTargetKey) nonretainedObjectValue] ?: slider;
    CGAffineTransform baseTransform = baseValue.CGAffineTransformValue;
    if (state == UIGestureRecognizerStateEnded || state == UIGestureRecognizerStateCancelled || state == UIGestureRecognizerStateFailed) {
        CGFloat tension = [objc_getAssociatedObject(slider, kCCASliderOverscrollAmountKey) doubleValue];
        CGFloat velocityY = [gesture velocityInView:slider.window].y;
        CGFloat displacementY = target.transform.ty - baseTransform.ty;
        BOOL flingingOutward = tension > 0.10 && displacementY * velocityY > 0.0;
        CGFloat springVelocity = flingingOutward ? -MIN(2.2, fabs(velocityY) / 520.0) * tension : 0.0;
        NSTimeInterval duration = 0.20 + 0.30 * tension;
        CGFloat damping = 0.88 - 0.32 * tension;
        [UIView animateWithDuration:duration
                              delay:0.0
             usingSpringWithDamping:damping
              initialSpringVelocity:springVelocity
                            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                         animations:^{ target.transform = baseTransform; }
                         completion:^(__unused BOOL finished) {
            objc_setAssociatedObject(slider, kCCASliderOverscrollBaseTransformKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(slider, kCCASliderOverscrollStartValueKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(slider, kCCASliderOverscrollAmountKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(slider, kCCASliderOverscrollTargetKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }];
        return;
    }
    if (state != UIGestureRecognizerStateBegan && state != UIGestureRecognizerStateChanged) return;

    // Brightness and volume use the tall continuous-slider presentation. Use
    // window-space translation so deforming the slider cannot feed back into
    // the gesture's own coordinate system.
    if (CGRectGetHeight(slider.bounds) <= CGRectGetWidth(slider.bounds) * 1.15) return;
    CGFloat startValue = [objc_getAssociatedObject(slider, kCCASliderOverscrollStartValueKey) doubleValue];
    CGFloat translationY = [gesture translationInView:slider.window].y;
    CGFloat rawValue = startValue - translationY / MAX(1.0, CGRectGetHeight(slider.bounds));
    CGFloat overshoot = rawValue > 1.0 ? rawValue - 1.0 : (rawValue < 0.0 ? -rawValue : 0.0);
    // Rational resistance has no abrupt ceiling: every extra point still
    // yields a little motion, but progressively less than the one before it.
    CGFloat pull = overshoot * 6.0;
    CGFloat resisted = pull / (1.0 + pull);
    BOOL pullingTop = rawValue > 1.0;
    CGFloat travelY = (pullingTop ? -1.0 : 1.0) * 9.0 * resisted;
    CGFloat scaleX = 1.0 - 0.045 * resisted;
    CGFloat scaleY = 1.0 + 0.040 * resisted;
    CGAffineTransform transformed = CGAffineTransformTranslate(baseTransform, 0.0, travelY);
    transformed = CGAffineTransformScale(transformed, scaleX, scaleY);
    [UIView performWithoutAnimation:^{ target.transform = transformed; }];
    objc_setAssociatedObject(slider, kCCASliderOverscrollAmountKey, @(resisted), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static NSArray<UIViewController *> *CCACollectModuleControllers(UIViewController *root) {
    if (!root) return @[];
    NSMutableArray *result = [NSMutableArray array];
    NSMutableArray *queue = [NSMutableArray arrayWithObject:root];
    while (queue.count) {
        UIViewController *candidate = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if (candidate != root && CCAIsModuleController(candidate)) [result addObject:candidate];
        [queue addObjectsFromArray:candidate.childViewControllers];
    }
    return result;
}

static UIViewController *CCAModuleControllerMatchingObject(UIViewController *overlay, id object) {
    NSString *identifier = CCAIdentifierFromObject(object);
    for (UIViewController *candidate in CCACollectModuleControllers(overlay)) {
        if (identifier.length && [CCAModuleIdentifier(candidate) isEqualToString:identifier]) return candidate;
        @try {
            if ([candidate valueForKey:@"module"] == object) return candidate;
        } @catch (__unused NSException *exception) {}
    }
    return nil;
}

static CGRect CCAVisibleModuleFrame(UIViewController *module, UIViewController *overlay) {
    // convertRect already walks the transformed wrapper hierarchy. Applying
    // the edit translation again displaced hit testing and landing by 48pt.
    return [module.view convertRect:module.view.bounds toView:overlay.view];
}

static BOOL CCAExpandedChromeRevealActive(void) {
    return CACurrentMediaTime() < gCCAExpandedChromeRevealUntil;
}

static void CCAApplyExpansionPageGeometrySync(UIViewController *overlay) {
    if (!overlay || gCCACurrentPage == 0) return;
    if (objc_getAssociatedObject(overlay, kCCAExpansionPageGeometrySyncKey)) return;
    id coordinator = ((id (*)(id, SEL))objc_msgSend)(NSClassFromString(@"CCAsterCoordinator"), @selector(shared));
    UIViewController *collection = ((id (*)(id, SEL, id))objc_msgSend)(coordinator, NSSelectorFromString(@"moduleCollectionControllerInOverlay:"), overlay);
    if (!collection.view) return;
    ((void (*)(id, SEL, id))objc_msgSend)(coordinator, NSSelectorFromString(@"capturePresentationStateForView:"), collection.view);
    CGAffineTransform currentTransform = collection.view.transform;
    CATransform3D currentSublayerTransform = collection.view.layer.sublayerTransform;
    objc_setAssociatedObject(collection.view, kCCAExpansionCollectionLayerPositionKey,
                             [NSValue valueWithCGPoint:collection.view.layer.position], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    CGAffineTransform base = [objc_getAssociatedObject(collection.view, kCCAOriginalTransformKey) CGAffineTransformValue];
    CATransform3D sublayerBase = [objc_getAssociatedObject(collection.view, kCCAOriginalSublayerTransformKey) CATransform3DValue];
    CGFloat editOffset = gEditModeActive ? 0.0 : kCCARestingModuleOffset;
    CGFloat pageOffset = -(CGFloat)gCCACurrentPage * CCAVisualPageSpan();
    NSDictionary *record = @{
        @"collection": collection.view,
        @"transform": [NSValue valueWithCGAffineTransform:currentTransform],
        @"sublayerTransform": [NSValue valueWithCATransform3D:currentSublayerTransform],
    };
    objc_setAssociatedObject(overlay, kCCAExpansionPageGeometrySyncKey, record, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [UIView performWithoutAnimation:^{
        [collection.view.layer removeAnimationForKey:@"CCAsterPageStackSlide"];
        collection.view.transform = CGAffineTransformTranslate(base, 0.0, editOffset + pageOffset);
        collection.view.layer.sublayerTransform = sublayerBase;
    }];
}

static void CCARestoreExpansionPageGeometrySync(UIViewController *overlay) {
    NSDictionary *record = objc_getAssociatedObject(overlay, kCCAExpansionPageGeometrySyncKey);
    if (!record) return;
    objc_setAssociatedObject(overlay, kCCAExpansionPageGeometrySyncKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIView *collectionView = record[@"collection"];
    if (![collectionView isKindOfClass:[UIView class]]) return;
    NSValue *transformValue = record[@"transform"];
    NSValue *sublayerValue = record[@"sublayerTransform"];
    [UIView performWithoutAnimation:^{
        [collectionView.layer removeAnimationForKey:@"CCAsterPageStackSlide"];
        if ([transformValue isKindOfClass:[NSValue class]]) collectionView.transform = transformValue.CGAffineTransformValue;
        if ([sublayerValue isKindOfClass:[NSValue class]]) collectionView.layer.sublayerTransform = sublayerValue.CATransform3DValue;
        NSArray<NSDictionary *> *wrapperRecords = record[@"wrappers"];
        for (NSDictionary *wrapperRecord in wrapperRecords) {
            UIView *wrapper = wrapperRecord[@"wrapper"];
            NSValue *wrapperTransformValue = wrapperRecord[@"transform"];
            if (![wrapper isKindOfClass:[UIView class]] || ![wrapperTransformValue isKindOfClass:[NSValue class]]) continue;
            wrapper.transform = wrapperTransformValue.CGAffineTransformValue;
        }
    }];
}

static void CCAReassertExpansionPageGeometry(UIViewController *overlay) {
    if (!overlay || gCCACurrentPage == 0) return;
    NSDictionary *record = objc_getAssociatedObject(overlay, kCCAExpansionPageGeometrySyncKey);
    UIView *collectionView = record[@"collection"];
    if (![collectionView isKindOfClass:[UIView class]]) return;
    CGAffineTransform base = [objc_getAssociatedObject(collectionView, kCCAOriginalTransformKey) CGAffineTransformValue];
    CATransform3D sublayerBase = [objc_getAssociatedObject(collectionView, kCCAOriginalSublayerTransformKey) CATransform3DValue];
    NSValue *positionValue = objc_getAssociatedObject(collectionView, kCCAExpansionCollectionLayerPositionKey);
    CGFloat editOffset = gEditModeActive ? 0.0 : kCCARestingModuleOffset;
    CGFloat pageOffset = -(CGFloat)gCCACurrentPage * CCAVisualPageSpan();
    [collectionView.layer removeAnimationForKey:@"CCAsterPageStackSlide"];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (positionValue) collectionView.layer.position = positionValue.CGPointValue;
    collectionView.transform = CGAffineTransformTranslate(base, 0.0, editOffset + pageOffset);
    collectionView.layer.sublayerTransform = sublayerBase;
    [CATransaction commit];
}

static void CCAHoldExpansionPageGeometryDuringDismissal(UIViewController *overlay) {
    if (!overlay || gCCACurrentPage == 0) return;
    id token = [NSObject new];
    objc_setAssociatedObject(overlay, kCCAExpansionGeometryHoldTokenKey, token, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    for (NSUInteger frame = 0; frame <= 42; frame++) {
        NSTimeInterval delay = (NSTimeInterval)frame / 60.0;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (objc_getAssociatedObject(overlay, kCCAExpansionGeometryHoldTokenKey) != token) return;
            if (!gCCAExpandedModuleClosingActive) return;
            CCAReassertExpansionPageGeometry(overlay);
        });
    }
}

static void CCADiscardExpansionSourceSnapshot(void) {
    [gCCAExpansionSourceSnapshot removeFromSuperview];
    gCCAExpansionSourceSnapshot = nil;
}

static void CCADiscardExpansionDismissalSnapshot(void) {
    [gCCAExpansionDismissalSnapshot removeFromSuperview];
    gCCAExpansionDismissalSnapshot = nil;
    [gCCAExpansionDismissalForegroundSnapshot removeFromSuperview];
    gCCAExpansionDismissalForegroundSnapshot = nil;
}

static BOOL CCAExpansionIdentifierUsesLiveTransition(NSString *identifier) {
    NSString *lower = identifier.lowercaseString;
    return [lower containsString:@"connectivity"] ||
        [lower isEqualToString:@"com.apple.control-center.displaymodule"] ||
        [lower hasPrefix:@"com.apple.mediaremote.controlcenter."];
}

static BOOL CCAViewTreeContainsLiveExpansionContent(UIView *root) {
    if (!root) return NO;
    NSString *className = NSStringFromClass(root.class);
    if ([className isEqualToString:@"CCUIBaseSliderView"] ||
        [className isEqualToString:@"CCUIContinuousSliderView"] ||
        [className containsString:@"MRUNowPlaying"] ||
        [className containsString:@"MRUControlCenter"]) return YES;
    for (UIView *subview in root.subviews) {
        if (CCAViewTreeContainsLiveExpansionContent(subview)) return YES;
    }
    return NO;
}

static BOOL CCAUsesSpecializedExpansionTransition(UIViewController *presented) {
    return gCCAConnectivityExpansionActive ||
        CCAExpansionIdentifierUsesLiveTransition(gCCAExpandedModuleIdentifier) ||
        CCAViewTreeContainsLiveExpansionContent(presented.view);
}

static void CCARestoreHiddenExpansionLiveViews(void) {
    [UIView performWithoutAnimation:^{
        [gCCAExpansionHiddenLiveViews enumerateObjectsUsingBlock:^(UIView *liveView, NSUInteger index, __unused BOOL *stop) {
            if (index < gCCAExpansionHiddenLiveAlphas.count) {
                liveView.alpha = gCCAExpansionHiddenLiveAlphas[index].doubleValue;
            }
            if (index < gCCAExpansionHiddenLiveLayerOpacities.count) {
                liveView.layer.opacity = gCCAExpansionHiddenLiveLayerOpacities[index].floatValue;
            }
        }];
    }];
    gCCAExpansionHiddenLiveViews = nil;
    gCCAExpansionHiddenLiveAlphas = nil;
    gCCAExpansionHiddenLiveLayerOpacities = nil;
}

static void CCADiscardExpandedDismissalSnapshot(void) {
    [gCCAExpansionExpandedSnapshot removeFromSuperview];
    gCCAExpansionExpandedSnapshot = nil;
}

static void CCADiscardExpansionCompactTransitionAssets(void) {
    [gCCAExpansionCompactMaterialTemplate removeFromSuperview];
    gCCAExpansionCompactMaterialTemplate = nil;
    gCCAExpansionCompactForegroundImage = nil;
    gCCAExpansionCompactImage = nil;
    gCCAExpansionTransitionWindow = nil;
    gCCAExpansionCompactDestinationWindowFrame = CGRectZero;
    gCCAExpansionExpandedContentAnchorWindow = CGPointZero;
}

static void CCAResetGenericExpansionDismissal(void) {
    gCCAExpansionDismissalGeneration++;
    CCARestoreHiddenExpansionLiveViews();
    CCADiscardExpandedDismissalSnapshot();
    CCADiscardExpansionDismissalSnapshot();
    gCCAExpansionDismissalAnimatorFinished = NO;
    gCCAExpansionDismissalDidClose = NO;
}

static void CCACompleteGenericExpansionDismissalIfReady(void) {
    if (!gCCAExpansionDismissalAnimatorFinished || !gCCAExpansionDismissalDidClose) return;
    for (UIView *liveView in gCCAExpansionHiddenLiveViews) {
        [liveView.superview layoutIfNeeded];
        [liveView layoutIfNeeded];
    }
    [UIView performWithoutAnimation:^{
        [gCCAExpansionHiddenLiveViews enumerateObjectsUsingBlock:^(UIView *liveView, NSUInteger index, __unused BOOL *stop) {
            if (index < gCCAExpansionHiddenLiveAlphas.count) {
                liveView.alpha = gCCAExpansionHiddenLiveAlphas[index].doubleValue;
            }
            if (index < gCCAExpansionHiddenLiveLayerOpacities.count) {
                liveView.layer.opacity = gCCAExpansionHiddenLiveLayerOpacities[index].floatValue;
            }
        }];
        [gCCAExpansionExpandedSnapshot removeFromSuperview];
        [gCCAExpansionDismissalSnapshot removeFromSuperview];
        [gCCAExpansionDismissalForegroundSnapshot removeFromSuperview];
    }];
    gCCAExpansionHiddenLiveViews = nil;
    gCCAExpansionHiddenLiveAlphas = nil;
    gCCAExpansionHiddenLiveLayerOpacities = nil;
    gCCAExpansionExpandedSnapshot = nil;
    gCCAExpansionDismissalSnapshot = nil;
    gCCAExpansionDismissalForegroundSnapshot = nil;
    CCADiscardExpansionCompactTransitionAssets();
    gCCAExpansionDismissalAnimatorFinished = NO;
    gCCAExpansionDismissalDidClose = NO;
}

static void CCAFreezeExpandedModuleForDismissal(UIViewController *presented) {
    CCADiscardExpandedDismissalSnapshot();
    if (!presented.view || !presented.view.superview || CGRectIsEmpty(presented.view.bounds)) return;
    [presented.view.superview layoutIfNeeded];
    [presented.view layoutIfNeeded];

    UIView *expandedBackground = CCAFindSubviewWithClassName(presented.view, @"CCUIContentModuleBackgroundView");
    UIView *contentContainer = CCAFindSubviewWithClassName(presented.view, @"CCUIContentModuleContentContainerView");
    UIView *expandedSurface = contentContainer ?: expandedBackground;
    UIView *snapshot = expandedSurface ? CCAWindowCropSnapshotView(expandedSurface) : nil;
    CGRect snapshotFrame = expandedSurface
        ? [expandedSurface convertRect:expandedSurface.bounds toView:presented.view.superview]
        : presented.view.frame;
    if (snapshot) {
        snapshot.layer.cornerRadius = expandedSurface.layer.cornerRadius;
        snapshot.layer.cornerCurve = kCACornerCurveContinuous;
        snapshot.layer.masksToBounds = YES;
    }
    if (!snapshot) snapshot = CCACompositedSnapshotView(presented.view);
    if (!snapshot) snapshot = CCAWindowCropSnapshotView(presented.view);
    if (!snapshot) return;
    UIWindow *window = expandedSurface.window ?: presented.view.window;
    if (window && expandedSurface) {
        snapshotFrame = [expandedSurface convertRect:expandedSurface.bounds toView:window];
    } else if (window) {
        snapshotFrame = [presented.view convertRect:presented.view.bounds toView:window];
    }
    snapshot.frame = snapshotFrame;
    snapshot.userInteractionEnabled = NO;
    if (window) [window addSubview:snapshot];
    else [presented.view.superview insertSubview:snapshot aboveSubview:presented.view];
    gCCAExpansionExpandedSnapshot = snapshot;

    if (window && contentContainer) {
        CGRect contentFrame = [contentContainer convertRect:contentContainer.bounds toView:window];
        gCCAExpansionExpandedContentAnchorWindow = CGPointMake(CGRectGetMidX(contentFrame), CGRectGetMidY(contentFrame));
    } else {
        gCCAExpansionExpandedContentAnchorWindow = CGPointMake(CGRectGetMidX(snapshotFrame), CGRectGetMidY(snapshotFrame));
    }
    NSMutableArray<UIView *> *liveViews = [NSMutableArray array];
    if (expandedSurface) [liveViews addObject:expandedSurface];
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithArray:presented.view.subviews];
    while (queue.count) {
        UIView *candidate = queue.firstObject;
        [queue removeObjectAtIndex:0];
        BOOL alreadyCovered = expandedSurface && [candidate isDescendantOfView:expandedSurface];
        NSString *className = NSStringFromClass(candidate.class);
        NSString *text = nil;
        SEL textSelector = NSSelectorFromString(@"text");
        if ([candidate respondsToSelector:textSelector]) {
            @try {
                id value = ((id (*)(id, SEL))objc_msgSend)(candidate, textSelector);
                if ([value isKindOfClass:[NSString class]]) text = value;
            } @catch (__unused NSException *exception) {}
        }
        BOOL textSurface = text.length || [className containsString:@"Label"] || [className containsString:@"Header"];
        if (textSurface && candidate.window == window) {
            CGRect candidateFrame = [candidate convertRect:candidate.bounds toView:window];
            BOOL intersects = CGRectIntersectsRect(candidateFrame, snapshotFrame) ||
                CGRectIntersectsRect(candidateFrame, gCCAExpansionCompactDestinationWindowFrame);
            CGFloat candidateArea = CGRectGetWidth(candidateFrame) * CGRectGetHeight(candidateFrame);
            CGFloat platterArea = CGRectGetWidth(snapshotFrame) * CGRectGetHeight(snapshotFrame);
            BOOL select = !alreadyCovered && intersects && candidateArea > 0.0 && candidateArea < platterArea * 0.6;
            if (select && ![liveViews containsObject:candidate]) [liveViews addObject:candidate];
        }
        [queue addObjectsFromArray:candidate.subviews];
    }
    if (!liveViews.count) {
        CCADiscardExpandedDismissalSnapshot();
        return;
    }
    NSMutableArray<NSNumber *> *alphas = [NSMutableArray arrayWithCapacity:liveViews.count];
    NSMutableArray<NSNumber *> *layerOpacities = [NSMutableArray arrayWithCapacity:liveViews.count];
    for (UIView *liveView in liveViews) {
        [alphas addObject:@(liveView.alpha)];
        [layerOpacities addObject:@(liveView.layer.opacity)];
    }
    gCCAExpansionHiddenLiveViews = liveViews;
    gCCAExpansionHiddenLiveAlphas = alphas;
    gCCAExpansionHiddenLiveLayerOpacities = layerOpacities;
    [UIView performWithoutAnimation:^{
        for (UIView *liveView in liveViews) {
            liveView.alpha = 0.0;
            liveView.layer.opacity = 0.0;
        }
    }];
}

static void CCAInstallExpansionDismissalSnapshot(id clickAssistant) {
    (void)clickAssistant;
    CCADiscardExpansionDismissalSnapshot();
    UIWindow *window = gCCAExpansionExpandedSnapshot.window ?: gCCAExpansionTransitionWindow;
    CGRect startFrame = gCCAExpansionExpandedSnapshot.frame;
    if (!window || CGRectIsEmpty(startFrame) || CGRectIsEmpty(gCCAExpansionCompactDestinationWindowFrame)) return;
    UIView *proxy = [[UIView alloc] initWithFrame:startFrame];
    proxy.backgroundColor = UIColor.clearColor;
    proxy.userInteractionEnabled = NO;
    proxy.alpha = 0.0;
    proxy.layer.cornerRadius = gCCAExpansionExpandedSnapshot.layer.cornerRadius;
    proxy.layer.cornerCurve = kCACornerCurveContinuous;
    proxy.layer.masksToBounds = YES;
    UIView *material = gCCAExpansionCompactMaterialTemplate;
    if (material) {
        material.frame = proxy.bounds;
        material.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        material.userInteractionEnabled = NO;
        [proxy addSubview:material];
    }
    if (gCCAExpansionExpandedSnapshot.superview == window) {
        [window insertSubview:proxy belowSubview:gCCAExpansionExpandedSnapshot];
    } else {
        [window addSubview:proxy];
    }
    UIImage *foregroundImage = gCCAExpansionCompactForegroundImage ?: gCCAExpansionCompactImage;
    if (foregroundImage) {
        UIImageView *foreground = [[UIImageView alloc] initWithImage:foregroundImage];
        foreground.bounds = (CGRect){CGPointZero, gCCAExpansionCompactDestinationWindowFrame.size};
        foreground.center = gCCAExpansionExpandedContentAnchorWindow;
        foreground.contentMode = UIViewContentModeScaleToFill;
        foreground.userInteractionEnabled = NO;
        foreground.alpha = 0.0;
        if (gCCAExpansionExpandedSnapshot.superview == window) {
            [window insertSubview:foreground belowSubview:gCCAExpansionExpandedSnapshot];
        } else {
            [window addSubview:foreground];
        }
        gCCAExpansionDismissalForegroundSnapshot = foreground;
    }
    gCCAExpansionDismissalSnapshot = proxy;
}

static UIViewPropertyAnimator *CCAExpansionPropertyAnimator(id clickAssistant) {
    SEL selector = NSSelectorFromString(@"presentationAnimator");
    if ([clickAssistant respondsToSelector:selector]) {
        id animator = ((id (*)(id, SEL))objc_msgSend)(clickAssistant, selector);
        if ([animator isKindOfClass:[UIViewPropertyAnimator class]]) return animator;
    }
    Ivar animatorIvar = class_getInstanceVariable([clickAssistant class], "_presentationAnimator");
    id animator = animatorIvar ? object_getIvar(clickAssistant, animatorIvar) : nil;
    return [animator isKindOfClass:[UIViewPropertyAnimator class]] ? animator : nil;
}

static UIView *CCACreateQuickAccessDismissalProxy(UIViewController *overlay, UIView *quickAccess) {
    if (!overlay.view || !quickAccess || gEditModeActive || !gQuickAccessButtonsEnabled) return nil;
    [[overlay.view viewWithTag:kCCAQuickAccessDismissalProxyTag] removeFromSuperview];
    UIView *proxy = [[UIView alloc] initWithFrame:overlay.view.bounds];
    proxy.tag = kCCAQuickAccessDismissalProxyTag;
    proxy.backgroundColor = UIColor.clearColor;
    proxy.userInteractionEnabled = NO;
    proxy.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    BOOL originalHidden = quickAccess.hidden;
    CGFloat originalAlpha = quickAccess.alpha;
    CGAffineTransform originalTransform = quickAccess.transform;
    [UIView performWithoutAnimation:^{
        quickAccess.hidden = NO;
        quickAccess.alpha = 1.0;
        quickAccess.transform = CGAffineTransformIdentity;
        [quickAccess.superview layoutIfNeeded];
        [quickAccess layoutIfNeeded];
    }];

    for (UIView *subview in quickAccess.subviews) {
        if (subview.hidden || subview.alpha <= 0.01) continue;
        CGRect frame = [subview.superview convertRect:subview.frame toView:overlay.view];
        if (CGRectIsEmpty(frame) || CGRectGetMaxY(frame) < -80.0 || CGRectGetMinY(frame) > CGRectGetHeight(overlay.view.bounds) + 80.0) continue;
        NSString *symbol = subview.tag == 181001 ? @"plus" : (subview.tag == 181002 ? @"power" : nil);
        UIView *snapshot = nil;
        if (symbol.length) {
            CGRect localBounds = CGRectMake(0.0, 0.0, CGRectGetWidth(frame), CGRectGetHeight(frame));
            snapshot = [[UIView alloc] initWithFrame:localBounds];
            snapshot.backgroundColor = UIColor.clearColor;
            UIView *sourceMaterial = [subview viewWithTag:kCCAPowerMaterialTag];
            UIView *material = nil;
            if (sourceMaterial && [sourceMaterial conformsToProtocol:@protocol(NSCopying)]) {
                @try { material = [sourceMaterial copy]; } @catch (__unused NSException *exception) {}
            }
            if (!material && sourceMaterial && [sourceMaterial respondsToSelector:NSSelectorFromString(@"recipe")]) {
                Class materialClass = NSClassFromString(@"MTMaterialView");
                SEL factory = NSSelectorFromString(@"materialViewWithRecipe:");
                if ([materialClass respondsToSelector:factory]) {
                    long long recipe = ((long long (*)(id, SEL))objc_msgSend)(sourceMaterial, NSSelectorFromString(@"recipe"));
                    material = ((id (*)(id, SEL, long long))objc_msgSend)(materialClass, factory, recipe);
                }
            }
            if (!material) {
                UIVisualEffectView *fallback = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialDark]];
                fallback.contentView.backgroundColor = [UIColor.whiteColor colorWithAlphaComponent:0.055];
                material = fallback;
            }
            material.tag = kCCAPowerMaterialTag;
            material.frame = CGRectMake(5.0, 5.0, 30.0, 30.0);
            material.autoresizingMask = UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleBottomMargin;
            material.transform = CGAffineTransformIdentity;
            material.hidden = NO;
            material.alpha = 1.0;
            material.backgroundColor = UIColor.clearColor;
            material.userInteractionEnabled = NO;
            material.layer.cornerRadius = 15.0;
            material.layer.cornerCurve = kCACornerCurveContinuous;
            material.clipsToBounds = YES;
            material.layer.masksToBounds = YES;
            [snapshot addSubview:material];
            UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:15.0 weight:UIImageSymbolWeightSemibold];
            UIImage *image = [[UIImage systemImageNamed:symbol withConfiguration:configuration] imageWithTintColor:[UIColor colorWithWhite:1.0 alpha:0.97]
                                                                                                      renderingMode:UIImageRenderingModeAlwaysOriginal];
            UIImageView *glyph = [[UIImageView alloc] initWithImage:image];
            glyph.contentMode = UIViewContentModeCenter;
            glyph.frame = localBounds;
            glyph.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            [snapshot addSubview:glyph];
        } else {
            snapshot = [subview snapshotViewAfterScreenUpdates:NO];
        }
        if (!snapshot) continue;
        snapshot.frame = frame;
        snapshot.userInteractionEnabled = NO;
        [proxy addSubview:snapshot];
    }

    [UIView performWithoutAnimation:^{
        quickAccess.hidden = originalHidden;
        quickAccess.alpha = originalAlpha;
        quickAccess.transform = originalTransform;
    }];
    if (!proxy.subviews.count) return nil;
    proxy.alpha = 0.0;
    proxy.transform = CGAffineTransformMakeTranslation(0.0, -9.0);
    [overlay.view addSubview:proxy];
    return proxy;
}

static void CCASetQuickAccessMaterialsHidden(UIView *quickAccess, BOOL hidden) {
    for (UIView *button in quickAccess.subviews) {
        UIView *material = [button viewWithTag:kCCAPowerMaterialTag];
        if (!material) continue;
        material.hidden = hidden;
        material.alpha = hidden ? 0.0 : 1.0;
    }
}

static void CCAPrepareOverlayChromeForExpandedDismissal(UIViewController *overlay) {
    if (!overlay.view || !gCCAControlCenterPresented) return;
    gCCAExpandedChromeRevealUntil = CACurrentMediaTime() + 0.65;
    id coordinator = ((id (*)(id, SEL))objc_msgSend)(NSClassFromString(@"CCAsterCoordinator"), @selector(shared));
    ((void (*)(id, SEL, id))objc_msgSend)(coordinator, NSSelectorFromString(@"installQuickAccessHostOnOverlay:"), overlay);
    ((void (*)(id, SEL, id))objc_msgSend)(coordinator, NSSelectorFromString(@"updatePageIndicatorsForOverlay:"), overlay);
    UIView *quickAccess = [overlay.view viewWithTag:181000];
    UIView *pageIndicators = [overlay.view viewWithTag:kCCAPageIndicatorHostTag];
    UIView *quickAccessProxy = CCACreateQuickAccessDismissalProxy(overlay, quickAccess);
    NSMutableArray<UIView *> *targets = [NSMutableArray array];
    if (quickAccessProxy) {
        [overlay.view bringSubviewToFront:quickAccessProxy];
        [targets addObject:quickAccessProxy];
    }
    if (pageIndicators && gCCAPageCount > 1) {
        if (pageIndicators.superview) [pageIndicators.superview bringSubviewToFront:pageIndicators];
        pageIndicators.hidden = NO;
        pageIndicators.alpha = 0.0;
        [targets addObject:pageIndicators];
    }
    if (!targets.count) return;
    [UIView animateWithDuration:0.34 delay:0.02
                        options:UIViewAnimationOptionCurveEaseInOut |
                                UIViewAnimationOptionBeginFromCurrentState |
                                UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        quickAccessProxy.alpha = quickAccessProxy ? 1.0 : 0.0;
        quickAccessProxy.transform = CGAffineTransformIdentity;
        pageIndicators.alpha = pageIndicators ? 1.0 : 0.0;
    } completion:^(__unused BOOL finished) {
        if (!quickAccessProxy) return;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.46 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIView *liveQuickAccess = [overlay.view viewWithTag:181000];
            if (liveQuickAccess && !gEditModeActive && gQuickAccessButtonsEnabled && gCCAControlCenterPresented) {
                [UIView performWithoutAnimation:^{
                    liveQuickAccess.hidden = NO;
                    liveQuickAccess.alpha = 1.0;
                    liveQuickAccess.transform = CGAffineTransformIdentity;
                    CCASetQuickAccessMaterialsHidden(liveQuickAccess, YES);
                    for (UIView *button in liveQuickAccess.subviews) {
                        for (UIView *child in button.subviews) if (child.tag != kCCAPowerMaterialTag) child.alpha = 0.0;
                    }
                }];
            }
            [UIView animateWithDuration:0.12 delay:0.0
                                options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                             animations:^{
                for (UIView *button in quickAccessProxy.subviews) {
                    for (UIView *child in button.subviews) if (child.tag != kCCAPowerMaterialTag) child.alpha = 0.0;
                }
                if (liveQuickAccess) {
                    for (UIView *button in liveQuickAccess.subviews) {
                        for (UIView *child in button.subviews) if (child.tag != kCCAPowerMaterialTag) child.alpha = 1.0;
                    }
                }
            }
                             completion:^(__unused BOOL done) {
                if (liveQuickAccess && !gEditModeActive && gQuickAccessButtonsEnabled && gCCAControlCenterPresented) {
                    [UIView performWithoutAnimation:^{
                        CCASetQuickAccessMaterialsHidden(liveQuickAccess, NO);
                        liveQuickAccess.alpha = 1.0;
                        liveQuickAccess.transform = CGAffineTransformIdentity;
                    }];
                }
                [quickAccessProxy removeFromSuperview];
            }];
        });
    }];
}

static UIView *CCAFindSubviewWithClassName(UIView *root, NSString *className) {
    if (!root) return nil;
    if ([NSStringFromClass(root.class) isEqualToString:className]) return root;
    for (UIView *subview in root.subviews) {
        UIView *match = CCAFindSubviewWithClassName(subview, className);
        if (match) return match;
    }
    return nil;
}

static UIView *CCAFindAncestorOrSubviewWithClassName(UIView *view, NSString *className) {
    for (UIView *ancestor = view; ancestor; ancestor = ancestor.superview) {
        if ([NSStringFromClass(ancestor.class) isEqualToString:className]) return ancestor;
    }
    return CCAFindSubviewWithClassName(view, className);
}

static void CCASetContinuousCornerRadiusIvar(id object, NSString *ivarName, CGFloat value) {
    if (!object || !ivarName.length) return;
    Ivar ivar = class_getInstanceVariable([object class], ivarName.UTF8String);
    if (!ivar) return;
    const char *encoding = ivar_getTypeEncoding(ivar);
    ptrdiff_t offset = ivar_getOffset(ivar);
    uint8_t *bytes = (uint8_t *)(__bridge void *)object;
    if (encoding && encoding[0] == 'd') {
        *((double *)(bytes + offset)) = (double)value;
    } else {
        *((float *)(bytes + offset)) = (float)value;
    }
}

static UIImageView *CCAEnsureResizePresentationGlyph(UIView *presentation, NSString *symbolName) {
    UIImageView *glyph = (UIImageView *)[presentation viewWithTag:kCCAResizePresentationGlyphTag];
    if (!glyph) {
        glyph = [[UIImageView alloc] initWithFrame:CGRectZero];
        glyph.tag = kCCAResizePresentationGlyphTag;
        glyph.userInteractionEnabled = NO;
        glyph.contentMode = UIViewContentModeCenter;
        glyph.tintColor = UIColor.whiteColor;
        [presentation addSubview:glyph];
    }
    CGFloat pointSize = 27.0;
    if ([symbolName isEqualToString:@"wifi"]) pointSize = 30.0;
    else if ([symbolName isEqualToString:@"airdrop"]) pointSize = 29.0;
    else if ([symbolName isEqualToString:@"airplane"]) pointSize = 31.0;
    else if ([symbolName isEqualToString:@"antenna.radiowaves.left.and.right"]) pointSize = 29.0;
    else if ([symbolName isEqualToString:@"personalhotspot"]) pointSize = 30.0;
    else if ([symbolName isEqualToString:@"network"]) pointSize = 30.0;
    UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:pointSize weight:UIImageSymbolWeightSemibold];
    UIImage *image = [UIImage systemImageNamed:symbolName withConfiguration:configuration];
    glyph.image = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    glyph.frame = CGRectMake(0.0, 0.0, kCCAGridCellSize, kCCAGridCellSize);
    glyph.hidden = NO;
    glyph.alpha = 1.0;
    return glyph;
}

static void CCARestoreTextSizeNativeViews(UIView *root) {
    if (!root) return;
    for (NSString *className in @[@"CCUISteppedSliderView", @"AXCCIconImageView"]) {
        NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:root];
        while (queue.count) {
            UIView *candidate = queue.firstObject;
            [queue removeObjectAtIndex:0];
            if ([NSStringFromClass(candidate.class) isEqualToString:className]) {
                [candidate.layer removeAllAnimations];
                candidate.hidden = NO;
                candidate.alpha = 1.0;
                candidate.layer.opacity = 1.0;
            }
            [queue addObjectsFromArray:candidate.subviews];
        }
    }
}

static BOOL CCAModuleLooksExpandedNow(UIViewController *module) {
    if (!module.view || !gCCAExpandedModuleOpen) return NO;
    NSString *identifier = CCAModuleIdentifier(module);
    if (identifier.length && [identifier isEqualToString:gCCAExpandedModuleIdentifier]) return YES;
    if (!gCCAExpandedModuleIdentifier.length) {
        @try {
            UIView *container = CCAFindAncestorOrSubviewWithClassName(module.view, @"CCUIContentModuleContentContainerView");
            if ([[container valueForKey:@"_expanded"] boolValue]) return YES;
        } @catch (__unused NSException *exception) {}
    }
    return CGRectGetWidth(module.view.bounds) > 190.0 || CGRectGetHeight(module.view.bounds) > 190.0;
}

static void CCAHideNativeTextSizeCompactViews(UIView *root) {
    if (!root) return;
    for (NSString *className in @[@"CCUISteppedSliderView", @"AXCCIconImageView"]) {
        NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:root];
        while (queue.count) {
            UIView *candidate = queue.firstObject;
            [queue removeObjectAtIndex:0];
            if ([NSStringFromClass(candidate.class) isEqualToString:className]) {
                [candidate.layer removeAllAnimations];
                candidate.hidden = YES;
                candidate.alpha = 0.0;
                candidate.layer.opacity = 0.0;
            }
            [queue addObjectsFromArray:candidate.subviews];
        }
    }
}

static void CCAHideNativeConnectivityCompactViews(UIView *root) {
    if (!root) return;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:root];
    while (queue.count) {
        UIView *candidate = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([NSStringFromClass(candidate.class) isEqualToString:@"CCUILabeledRoundButton"]) {
            [candidate.layer removeAllAnimations];
            candidate.hidden = YES;
            candidate.alpha = 0.0;
            candidate.layer.opacity = 0.0;
        }
        [queue addObjectsFromArray:candidate.subviews];
    }
}

static UIControl *CCAFirstConnectivityRoundButton(UIView *root) {
    if (!root) return nil;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:root];
    while (queue.count) {
        UIView *candidate = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([candidate isKindOfClass:[UIControl class]] &&
            [NSStringFromClass(candidate.class) isEqualToString:@"CCUIRoundButton"]) {
            return (UIControl *)candidate;
        }
        [queue addObjectsFromArray:candidate.subviews];
    }
    return nil;
}

static UIImage *CCAConnectivityNativeGlyphImage(UIView *root) {
    UIControl *button = CCAFirstConnectivityRoundButton(root);
    if (!button) return nil;
    UIImageView *best = nil;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:(UIView *)button];
    while (queue.count) {
        UIView *candidate = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([candidate isKindOfClass:[UIImageView class]]) {
            UIImageView *imageView = (UIImageView *)candidate;
            if (imageView.image && imageView.alpha > 0.01 && !imageView.hidden) {
                best = imageView;
                break;
            }
            if (!best && imageView.image) best = imageView;
        }
        [queue addObjectsFromArray:candidate.subviews];
    }
    return best.image;
}

// The real glyph shipped inside ConnectivityModule.bundle's asset catalog.
// Unlike Bluetooth/WiFi (which have animatable CAPackages — Bluetooth.ca /
// WiFi.ca), AirDrop has no package and is absent from the compact grid, so the
// live-view proxy below never finds it. The named asset is the reliable source.
static UIImage *CCAConnectivityBundleGlyphImage(NSString *identifier) {
    NSString *lower = identifier.lowercaseString;
    NSString *assetName = nil;
    if ([lower containsString:@".airdrop"]) assetName = @"AirDropGlyph";
    if (!assetName) return nil;
    static NSBundle *connectivityBundle = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        connectivityBundle = [NSBundle bundleWithPath:@"/System/Library/ControlCenter/Bundles/ConnectivityModule.bundle"];
    });
    if (!connectivityBundle) return nil;
    return [UIImage imageNamed:assetName inBundle:connectivityBundle compatibleWithTraitCollection:nil];
}

static UIImage *CCAConnectivityStockProxyGlyphImage(NSString *identifier) {
    NSString *lower = identifier.lowercaseString;
    NSInteger tag = 0;
    if ([lower containsString:@".airdrop"]) tag = kCCAConnectivityCompactAirDropTag;
    if (tag) {
        for (UIViewController *overlay in gOverlayControllers.allObjects) {
            for (UIViewController *module in CCACollectModuleControllers(overlay)) {
                if (![CCAModuleIdentifier(module) isEqualToString:@"com.apple.control-center.ConnectivityModule"]) continue;
                UIView *proxy = [module.view viewWithTag:tag];
                NSMutableArray<UIView *> *queue = proxy ? [NSMutableArray arrayWithObject:proxy] : nil;
                while (queue.count) {
                    UIView *candidate = queue.firstObject;
                    [queue removeObjectAtIndex:0];
                    if ([candidate isKindOfClass:[UIImageView class]] && ((UIImageView *)candidate).image) return ((UIImageView *)candidate).image;
                    [queue addObjectsFromArray:candidate.subviews];
                }
            }
        }
    }
    // Fall back to the real asset-catalog glyph (fixes AirDrop, which otherwise
    // dropped to the generic fallback symbol).
    return CCAConnectivityBundleGlyphImage(identifier);
}

static UIView *CCAFirstModuleMaterialSurface(UIView *root) {
    if (!root) return nil;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:root];
    while (queue.count) {
        UIView *candidate = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([NSStringFromClass(candidate.class) isEqualToString:@"MTMaterialView"]) {
            CGFloat widthDelta = fabs(CGRectGetWidth(candidate.bounds) - CGRectGetWidth(root.bounds));
            CGFloat heightDelta = fabs(CGRectGetHeight(candidate.bounds) - CGRectGetHeight(root.bounds));
            if (widthDelta < 4.0 && heightDelta < 4.0) return candidate;
        }
        [queue addObjectsFromArray:candidate.subviews];
    }
    return nil;
}

static UIColor *CCAConnectivityAccentColorForIdentifier(NSString *identifier) {
    NSString *lower = identifier.lowercaseString;
    if ([lower containsString:@".airplane"]) return [UIColor colorWithRed:1.0 green:0.58 blue:0.0 alpha:1.0];
    if ([lower containsString:@".airdrop"]) return [UIColor colorWithRed:0.61 green:0.14 blue:0.96 alpha:1.0];
    if ([lower containsString:@".cellular"]) return [UIColor colorWithRed:0.20 green:0.78 blue:0.35 alpha:1.0];
    if ([lower containsString:@".hotspot"]) return [UIColor colorWithRed:0.20 green:0.78 blue:0.35 alpha:1.0];
    if ([lower containsString:@".bluetooth"]) return [UIColor colorWithRed:0.36 green:0.20 blue:1.0 alpha:1.0];
    return [UIColor colorWithRed:0.0 green:0.48 blue:1.0 alpha:1.0];
}

static BOOL CCAConnectivityIdentifierHasExpandedMenu(NSString *identifier) {
    NSString *lower = identifier.lowercaseString;
    return [lower containsString:@".wifi"] || [lower containsString:@".bluetooth"] || [lower containsString:@".airdrop"];
}

static void CCARecolorBluetoothPackageLayer(CALayer *layer, CGColorRef color) {
    if (!layer || !color) return;
    if ([layer respondsToSelector:@selector(setFillColor:)] && [layer respondsToSelector:@selector(fillColor)]) {
        CGColorRef fill = ((CGColorRef (*)(id, SEL))objc_msgSend)((id)layer, @selector(fillColor));
        if (fill && CGColorGetAlpha(fill) > 0.01) ((void (*)(id, SEL, CGColorRef))objc_msgSend)((id)layer, @selector(setFillColor:), color);
    }
    if ([layer respondsToSelector:@selector(setStrokeColor:)] && [layer respondsToSelector:@selector(strokeColor)]) {
        CGColorRef stroke = ((CGColorRef (*)(id, SEL))objc_msgSend)((id)layer, @selector(strokeColor));
        if (stroke && CGColorGetAlpha(stroke) > 0.01) ((void (*)(id, SEL, CGColorRef))objc_msgSend)((id)layer, @selector(setStrokeColor:), color);
    }
    for (CALayer *child in layer.sublayers) CCARecolorBluetoothPackageLayer(child, color);
}

static void CCARecolorBluetoothPackageView(UIView *packageView, UIColor *color) {
    if (!packageView || !color) return;
    CCARecolorBluetoothPackageLayer(packageView.layer, color.CGColor);
    for (UIView *subview in packageView.subviews) CCARecolorBluetoothPackageView(subview, color);
}

static UIView *CCAEnsureConnectivityBluetoothPackageGlyph(UIView *presentation, BOOL selected) {
    if (!presentation) return nil;
    UIView *packageView = [presentation viewWithTag:kCCAConnectivityBluetoothPackageGlyphTag];
    Class packageViewClass = NSClassFromString(@"CCUICAPackageView");
    Class descriptionClass = NSClassFromString(@"CCUICAPackageDescription");
    NSBundle *bundle = [NSBundle bundleWithPath:@"/System/Library/ControlCenter/Bundles/ConnectivityModule.bundle"];
    if (!packageViewClass || !descriptionClass || !bundle) return nil;
    CGFloat packageSide = 42.0;
    CGFloat packageScale = 1.0;
    if (!packageView) {
        packageView = [[packageViewClass alloc] initWithFrame:CGRectMake((kCCAGridCellSize - packageSide) * 0.5, (kCCAGridCellSize - packageSide) * 0.5, packageSide, packageSide)];
        packageView.tag = kCCAConnectivityBluetoothPackageGlyphTag;
        packageView.userInteractionEnabled = NO;
        packageView.contentMode = UIViewContentModeCenter;
        packageView.tintColor = UIColor.whiteColor;
        [presentation addSubview:packageView];
        id packageDescription = nil;
        SEL factory = NSSelectorFromString(@"descriptionForPackageNamed:inBundle:");
        if ([descriptionClass respondsToSelector:factory]) {
            packageDescription = ((id (*)(id, SEL, id, id))objc_msgSend)(descriptionClass, factory, @"Bluetooth", bundle);
        }
        if (!packageDescription) {
            SEL init = NSSelectorFromString(@"initWithPackageName:inBundle:");
            if ([descriptionClass instancesRespondToSelector:init]) {
                packageDescription = ((id (*)(id, SEL, id, id))objc_msgSend)([descriptionClass alloc], init, @"Bluetooth", bundle);
            }
        }
        SEL setPackageDescription = NSSelectorFromString(@"setPackageDescription:");
        if (packageDescription && [packageView respondsToSelector:setPackageDescription]) {
            ((void (*)(id, SEL, id))objc_msgSend)(packageView, setPackageDescription, packageDescription);
        }
        SEL setScale = NSSelectorFromString(@"setScale:");
        if ([packageView respondsToSelector:setScale]) {
            ((void (*)(id, SEL, double))objc_msgSend)(packageView, setScale, packageScale);
        }
    }
    packageView.frame = CGRectMake((kCCAGridCellSize - packageSide) * 0.5, (kCCAGridCellSize - packageSide) * 0.5, packageSide, packageSide);
    SEL setScale = NSSelectorFromString(@"setScale:");
    if ([packageView respondsToSelector:setScale]) {
        ((void (*)(id, SEL, double))objc_msgSend)(packageView, setScale, packageScale);
    }
    packageView.hidden = NO;
    packageView.alpha = 1.0;
    SEL stateSelector = NSSelectorFromString(@"setStateName:");
    if ([packageView respondsToSelector:stateSelector]) {
        ((void (*)(id, SEL, id))objc_msgSend)(packageView, stateSelector, selected ? @"poweron" : @"poweroff");
    }
    return packageView;
}

static void CCASetConnectivitySelectedSurface(UIViewController *module, BOOL selected, BOOL available, BOOL animated) {
    UIView *moduleView = module.view;
    if (!moduleView) return;
    UIView *surface = [moduleView viewWithTag:kCCAConnectivitySelectedSurfaceTag];
    if (!surface) {
        surface = [[UIView alloc] initWithFrame:moduleView.bounds];
        surface.tag = kCCAConnectivitySelectedSurfaceTag;
        surface.userInteractionEnabled = NO;
        surface.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        surface.layer.cornerCurve = kCACornerCurveContinuous;
        [moduleView addSubview:surface];
    }
    surface.frame = moduleView.bounds;
    surface.layer.cornerRadius = moduleView.layer.cornerRadius;
    surface.backgroundColor = [UIColor colorWithWhite:0.96 alpha:0.92];
    UIView *material = CCAFirstModuleMaterialSurface(moduleView);
    void (^changes)(void) = ^{
        surface.hidden = NO;
        surface.alpha = selected ? (available ? 1.0 : 0.42) : 0.0;
        material.alpha = selected ? 0.0 : (available ? 1.0 : 0.52);
        material.layer.opacity = material.alpha;
    };
    void (^completion)(BOOL) = ^(__unused BOOL finished) {
        surface.hidden = !selected;
    };
    if (animated) {
        [UIView animateWithDuration:0.24 delay:0.0 options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:changes completion:completion];
    } else {
        changes();
        completion(YES);
    }
}

static CCUILayoutSize CCAEffectiveCustomSizeForModule(UIViewController *module, NSString *identifier) {
    CCUILayoutSize size = {1, 1};
    NSArray<NSNumber *> *customSize = gCCACustomSizes[identifier];
    if (customSize.count >= 2) {
        size.width = MAX((NSUInteger)1, customSize[0].unsignedIntegerValue);
        size.height = MAX((NSUInteger)1, customSize[1].unsignedIntegerValue);
        return size;
    }
    NSValue *baseValue = gCCABaseLayoutSizes[identifier];
    if (baseValue) {
        [baseValue getValue:&size];
        size.width = MAX((NSUInteger)1, size.width);
        size.height = MAX((NSUInteger)1, size.height);
        return size;
    }
    CGFloat width = CGRectGetWidth(module.view.bounds);
    CGFloat height = CGRectGetHeight(module.view.bounds);
    size.width = MAX((NSUInteger)1, (NSUInteger)llround((width + kCCAGridGap) / kCCAGridStep));
    size.height = MAX((NSUInteger)1, (NSUInteger)llround((height + kCCAGridGap) / kCCAGridStep));
    return size;
}

static NSString *CCATextSizeCompactValue(UIView *root) {
    if (!root) return nil;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:root];
    while (queue.count) {
        UIView *candidate = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([NSStringFromClass(candidate.class) isEqualToString:@"CCUISteppedSliderView"]) {
            NSString *accessibilityValue = candidate.accessibilityValue;
            if (accessibilityValue.length &&
                ![accessibilityValue isEqualToString:@"0"] &&
                ![accessibilityValue isEqualToString:@"1"]) return accessibilityValue;
            if ([candidate respondsToSelector:@selector(value)]) {
                float value = ((float (*)(id, SEL))objc_msgSend)((id)candidate, @selector(value));
                if (isfinite(value)) return [NSString stringWithFormat:@"%ld%%", (long)llroundf(value * 100.0f)];
            }
        }
        [queue addObjectsFromArray:candidate.subviews];
    }
    return nil;
}

static UIView *CCAEnsureOwnedCompactPresentation(UIView *host) {
    UIView *presentation = [host viewWithTag:kCCAResizePresentationTag];
    if (!presentation) {
        presentation = [[UIView alloc] initWithFrame:host.bounds];
        presentation.tag = kCCAResizePresentationTag;
        presentation.userInteractionEnabled = NO;
        presentation.backgroundColor = UIColor.clearColor;
        presentation.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        presentation.clipsToBounds = YES;
        UILabel *title = [[UILabel alloc] initWithFrame:CGRectZero];
        title.tag = 1;
        title.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightSemibold];
        title.numberOfLines = 2;
        title.lineBreakMode = NSLineBreakByTruncatingTail;
        [presentation addSubview:title];
        UILabel *status = [[UILabel alloc] initWithFrame:CGRectZero];
        status.tag = 2;
        status.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightRegular];
        status.adjustsFontSizeToFitWidth = YES;
        status.minimumScaleFactor = 0.78;
        [presentation addSubview:status];
        [host addSubview:presentation];
    }
    presentation.hidden = NO;
    presentation.alpha = 1.0;
    return presentation;
}

static void CCALayoutOwnedCompactPresentation(UIView *presentation, NSString *symbolName, NSString *titleText, NSString *statusText, CCUILayoutSize gridSize) {
    if (!presentation) return;
    CGFloat logicalWidth = gridSize.width * kCCAGridCellSize + (gridSize.width > 1 ? (gridSize.width - 1) * kCCAGridGap : 0.0);
    CGFloat logicalHeight = gridSize.height * kCCAGridCellSize + (gridSize.height > 1 ? (gridSize.height - 1) * kCCAGridGap : 0.0);
    if (logicalWidth < 1.0) logicalWidth = CGRectGetWidth(presentation.superview.bounds);
    if (logicalHeight < 1.0) logicalHeight = CGRectGetHeight(presentation.superview.bounds);
    UILabel *title = (UILabel *)[presentation viewWithTag:1];
    UILabel *status = (UILabel *)[presentation viewWithTag:2];
    UIImageView *glyph = CCAEnsureResizePresentationGlyph(presentation, symbolName);
    BOOL showTitle = titleText.length && (gridSize.width > 1 || gridSize.height > 1);
    BOOL showStatus = showTitle && statusText.length;
    title.text = titleText;
    title.textColor = UIColor.whiteColor;
    status.text = statusText;
    status.textColor = [UIColor.whiteColor colorWithAlphaComponent:0.62];
    CGFloat lineHeight = 14.3333;
    CGFloat measuredTextX = gridSize.width > 1 && gridSize.height == 1 ? 71.0 : (gridSize.width > 1 ? 21.0 : 10.0);
    CGFloat measuredTextWidth = gridSize.width > 1 && gridSize.height == 1 ? MAX(0.0, logicalWidth - 83.0) :
        MAX(0.0, logicalWidth - measuredTextX - (gridSize.width > 1 ? 24.0 : 10.0));
    CGRect measuredTitle = [titleText boundingRectWithSize:CGSizeMake(measuredTextWidth, lineHeight * 2.0)
                                                   options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                                attributes:@{NSFontAttributeName: title.font}
                                                   context:nil];
    CGFloat titleHeight = measuredTitle.size.height > lineHeight + 1.0 ? lineHeight * 2.0 : lineHeight;
    [UIView performWithoutAnimation:^{
        presentation.frame = CGRectMake(0.0, 0.0, logicalWidth, logicalHeight);
        glyph.frame = CGRectMake(0.0, 0.0, kCCAGridCellSize, kCCAGridCellSize);
        glyph.hidden = NO;
        glyph.alpha = 1.0;
        if (gridSize.width > 1 && gridSize.height == 1) {
            CGFloat textX = 71.0;
            CGFloat textWidth = MAX(0.0, logicalWidth - 83.0);
            CGFloat groupHeight = titleHeight + (showStatus ? lineHeight : 0.0);
            CGFloat top = (logicalHeight - groupHeight) * 0.5;
            title.frame = CGRectMake(textX, top, textWidth, titleHeight);
            status.frame = CGRectMake(textX, top + titleHeight, textWidth, lineHeight);
        } else {
            CGFloat textX = gridSize.width > 1 ? 21.0 : 10.0;
            CGFloat textWidth = MAX(0.0, logicalWidth - textX - (gridSize.width > 1 ? 24.0 : 10.0));
            CGFloat groupHeight = titleHeight + (showStatus ? lineHeight : 0.0);
            CGFloat top = MAX(kCCAGridCellSize + 7.0, logicalHeight - 17.3333 - groupHeight);
            title.frame = CGRectMake(textX, top, textWidth, titleHeight);
            status.frame = CGRectMake(textX, top + titleHeight, textWidth, lineHeight);
        }
        title.hidden = !showTitle;
        status.hidden = !showStatus;
        title.alpha = showTitle ? 1.0 : 0.0;
        status.alpha = showStatus ? 1.0 : 0.0;
        title.textAlignment = NSTextAlignmentLeft;
        status.textAlignment = NSTextAlignmentLeft;
        [presentation bringSubviewToFront:glyph];
    }];
}

static void CCAApplyOwnedCompactPresentationState(UIView *presentation, BOOL selected, BOOL active, UIColor *accentColor, BOOL animated) {
    if (!presentation) return;
    UILabel *title = (UILabel *)[presentation viewWithTag:1];
    UILabel *status = (UILabel *)[presentation viewWithTag:2];
    UIImageView *glyph = (UIImageView *)[presentation viewWithTag:kCCAResizePresentationGlyphTag];
    UIView *packageGlyph = [presentation viewWithTag:kCCAConnectivityBluetoothPackageGlyphTag];
    UIColor *glyphColor = selected ? (active ? (accentColor ?: [UIColor colorWithRed:0.0 green:0.48 blue:1.0 alpha:1.0])
                                             : [UIColor colorWithWhite:0.35 alpha:1.0])
                                   : UIColor.whiteColor;
    void (^changes)(void) = ^{
        title.textColor = selected ? [UIColor colorWithWhite:0.08 alpha:0.94] : UIColor.whiteColor;
        status.textColor = selected ? [UIColor colorWithWhite:0.18 alpha:0.72] : [UIColor.whiteColor colorWithAlphaComponent:0.62];
        glyph.tintColor = glyphColor;
        packageGlyph.tintColor = glyphColor;
        if (!animated) CCARecolorBluetoothPackageView(packageGlyph, glyphColor);
    };
    if (animated) {
        [UIView transitionWithView:presentation duration:0.18 options:UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowAnimatedContent animations:changes completion:^(__unused BOOL finished) {
            CCARecolorBluetoothPackageView(packageGlyph, glyphColor);
        }];
    } else {
        changes();
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((animated ? 0.28 : 0.06) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        CCARecolorBluetoothPackageView(packageGlyph, glyphColor);
    });
}

static void CCAApplyOwnedCompactPresentationAvailability(UIView *presentation, BOOL available) {
    if (!presentation) return;
    presentation.alpha = available ? 1.0 : 0.44;
    for (UIView *subview in presentation.subviews) subview.alpha = available ? 1.0 : 0.72;
}

static void CCASetConnectivityProxyPressed(UIControl *sender, BOOL pressed) {
    if (!sender || gEditModeActive || gCCAExpandedModuleOpen) return;
    UIView *moduleView = sender.superview;
    NSString *identifier = objc_getAssociatedObject(sender, kCCAConnectivityIdentifierKey);
    if (!moduleView || ![identifier.lowercaseString containsString:@"ccaster.connectivity"]) return;
    BOOL selected = CCAConnectivitySelectedForIdentifier(identifier);
    BOOL available = CCAConnectivityAvailableForIdentifier(identifier);
    UIView *presentation = [moduleView viewWithTag:kCCAResizePresentationTag];
    UIView *surface = [moduleView viewWithTag:kCCAConnectivitySelectedSurfaceTag];
    UIView *material = CCAFirstModuleMaterialSurface(moduleView);
    CGFloat selectedSurfaceAlpha = selected ? (available ? 1.0 : 0.42) : 0.0;
    CGFloat materialRestAlpha = selected ? 0.0 : (available ? 1.0 : 0.52);
    BOOL brightenForEnable = pressed && !selected && available;
    [UIView animateWithDuration:pressed ? 0.10 : 0.26
                          delay:0.0
         usingSpringWithDamping:pressed ? 1.0 : 0.74
          initialSpringVelocity:0.0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        moduleView.transform = CGAffineTransformIdentity;
        presentation.alpha = available ? 1.0 : 0.44;
        surface.hidden = NO;
        if (selected) surface.alpha = selectedSurfaceAlpha;
        else surface.alpha = brightenForEnable ? 0.18 : 0.0;
        if (!selected && material) {
            material.alpha = brightenForEnable ? MIN(1.0, materialRestAlpha + 0.16) : materialRestAlpha;
            material.layer.opacity = material.alpha;
        }
    } completion:^(__unused BOOL finished) {
        if (!selected && !brightenForEnable) surface.hidden = YES;
    }];
}

static void CCAConfigureOddResizedModuleLayout(UIViewController *module) {
    NSString *identifier = CCAModuleIdentifier(module);
    NSArray<NSNumber *> *customSize = gCCACustomSizes[identifier];
    BOOL resized = customSize.count >= 2 && (customSize[0].unsignedIntegerValue > 1 || customSize[1].unsignedIntegerValue > 1);
    UIView *oddPresentation = [module.view viewWithTag:kCCAResizePresentationTag];
    BOOL isTextSize = [identifier isEqualToString:@"com.apple.accessibility.controlcenter.text.size"];
    BOOL expandedNow = CCAModuleLooksExpandedNow(module);
    BOOL isCCAConnectivityModule = [identifier.lowercaseString containsString:@"ccaster.connectivity"];
    if (isCCAConnectivityModule) {
        CCAInstallStandaloneConnectivityDetailMethod();
        if (expandedNow) {
            oddPresentation.hidden = YES;
            oddPresentation.alpha = 0.0;
            return;
        }
        CCAHideNativeConnectivityCompactViews(module.view);
        oddPresentation = CCAEnsureOwnedCompactPresentation(module.view);
        CCUILayoutSize size = CCAEffectiveCustomSizeForModule(module, identifier);
        NSString *title = CCAFriendlyNameForIdentifier(identifier) ?: CCAPrettyNameForIdentifier(identifier);
        NSString *status = CCAConnectivityStatusForIdentifier(identifier);
        NSString *symbol = CCAFallbackSymbolForIdentifier(identifier) ?: @"switch.2";
        CCALayoutOwnedCompactPresentation(oddPresentation, symbol, title, status, size);
        BOOL usesBluetoothPackageGlyph = [identifier.lowercaseString containsString:@".bluetooth"];
        UIImage *nativeGlyph = usesBluetoothPackageGlyph ? CCAConnectivityStockProxyGlyphImage(identifier) : (CCAConnectivityStockProxyGlyphImage(identifier) ?: CCAConnectivityNativeGlyphImage(module.view));
        UIImageView *ownedGlyph = (UIImageView *)[oddPresentation viewWithTag:kCCAResizePresentationGlyphTag];
        if (nativeGlyph && ownedGlyph) ownedGlyph.image = [nativeGlyph imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        BOOL selected = CCAConnectivitySelectedForIdentifier(identifier);
        BOOL active = CCAConnectivityActiveForIdentifier(identifier);
        BOOL available = CCAConnectivityAvailableForIdentifier(identifier);
        if (usesBluetoothPackageGlyph) {
            UIView *packageGlyph = CCAEnsureConnectivityBluetoothPackageGlyph(oddPresentation, selected);
            if (ownedGlyph) {
                ownedGlyph.hidden = packageGlyph != nil;
                ownedGlyph.alpha = packageGlyph ? 0.0 : 1.0;
            }
            if (packageGlyph) [oddPresentation bringSubviewToFront:packageGlyph];
        } else {
            UIView *packageGlyph = [oddPresentation viewWithTag:kCCAConnectivityBluetoothPackageGlyphTag];
            packageGlyph.hidden = YES;
            packageGlyph.alpha = 0.0;
            if (ownedGlyph) {
                ownedGlyph.hidden = NO;
                ownedGlyph.alpha = 1.0;
            }
        }
        NSNumber *previousSelected = objc_getAssociatedObject(module.view, kCCAConnectivitySelectedStateKey);
        BOOL animateState = previousSelected && previousSelected.boolValue != selected;
        objc_setAssociatedObject(module.view, kCCAConnectivitySelectedStateKey, @(selected), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        CCAApplyOwnedCompactPresentationState(oddPresentation, selected, active, CCAConnectivityAccentColorForIdentifier(identifier), animateState);
        CCAApplyOwnedCompactPresentationAvailability(oddPresentation, available);
        CCASetConnectivitySelectedSurface(module, selected, available, animateState);
        [module.view bringSubviewToFront:oddPresentation];
        UIControl *nativeControl = CCAFirstConnectivityRoundButton(module.view);
        UIButton *proxy = (UIButton *)[module.view viewWithTag:kCCAConnectivityTileActionProxyTag];
        if (!proxy) {
            proxy = [CCAConnectivityForceButton buttonWithType:UIButtonTypeCustom];
            proxy.tag = kCCAConnectivityTileActionProxyTag;
            proxy.backgroundColor = UIColor.clearColor;
            proxy.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            id coordinator = ((id (*)(id, SEL))objc_msgSend)(NSClassFromString(@"CCAsterCoordinator"), @selector(shared));
            [proxy addTarget:coordinator action:@selector(connectivityTileProxyTapped:) forControlEvents:UIControlEventTouchUpInside];
            [proxy addTarget:coordinator action:@selector(connectivityTileProxyTouchDown:) forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
            [proxy addTarget:coordinator action:@selector(connectivityTileProxyTouchUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel | UIControlEventTouchDragExit];
            UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc] initWithTarget:coordinator action:@selector(connectivityTileProxyHeld:)];
            hold.minimumPressDuration = 0.45;
            [proxy addGestureRecognizer:hold];
            [module.view addSubview:proxy];
        }
        proxy.frame = module.view.bounds;
        proxy.hidden = gEditModeActive || gCCAExpandedModuleOpen;
        proxy.enabled = !gEditModeActive && !gCCAExpandedModuleOpen;
        objc_setAssociatedObject(proxy, kCCAConnectivityForwardControlKey, nativeControl, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(proxy, kCCAConnectivityIdentifierKey, identifier, OBJC_ASSOCIATION_COPY_NONATOMIC);
        objc_setAssociatedObject(proxy, @selector(connectivityTileProxyTapped:), @(available), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [module.view bringSubviewToFront:proxy];
    } else if (isTextSize) {
        if (expandedNow) {
            oddPresentation.hidden = YES;
            oddPresentation.alpha = 0.0;
            CCARestoreTextSizeNativeViews(module.view);
            return;
        }
        CCAHideNativeTextSizeCompactViews(module.view);
        oddPresentation = CCAEnsureOwnedCompactPresentation(module.view);
        CCUILayoutSize size = CCAEffectiveCustomSizeForModule(module, identifier);
        NSString *value = CCATextSizeCompactValue(module.view);
        CCALayoutOwnedCompactPresentation(oddPresentation, @"textformat.size", @"Text Size", value, size);
        [module.view bringSubviewToFront:oddPresentation];
    } else if ([identifier isEqualToString:@"com.mtac.ccpowermenu"]) {
        NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:module.view];
        while (queue.count) {
            UIView *candidate = queue.firstObject;
            [queue removeObjectAtIndex:0];
            if ([candidate isKindOfClass:[UIActivityIndicatorView class]]) {
                candidate.hidden = YES;
                candidate.alpha = 0.0;
            }
            [queue addObjectsFromArray:candidate.subviews];
        }
    } else if (!resized) {
        if (oddPresentation && !CCAFindSubviewWithClassName(module.view, @"CCUIButtonModuleView")) [oddPresentation removeFromSuperview];
    }
}

static NSArray<UIView *> *CCACompactGlyphHosts(UIView *buttonView) {
    if (!buttonView) return @[];
    NSMutableArray<UIView *> *glyphHosts = [NSMutableArray array];
    for (NSString *key in @[@"glyphImageView", @"_glyphImageView", @"glyphPackageView", @"_glyphPackageView"]) {
        @try {
            id candidate = [(id)buttonView valueForKey:key];
            if ([candidate isKindOfClass:[UIView class]] && ![glyphHosts containsObject:candidate]) [glyphHosts addObject:candidate];
        } @catch (__unused NSException *exception) {}
    }
    for (UIView *candidate in buttonView.subviews) {
        NSString *className = NSStringFromClass(candidate.class);
        if (([className isEqualToString:@"CCUICAPackageView"] || [candidate isKindOfClass:[UIImageView class]]) && ![glyphHosts containsObject:candidate]) {
            [glyphHosts addObject:candidate];
        }
    }
    return glyphHosts;
}

static void CCABeginResizeGlyphHandoff(UIView *moduleView, UIView *buttonView, UIView *stableHost) {
    if (!moduleView || !buttonView || !stableHost || objc_getAssociatedObject(moduleView, kCCAResizeGlyphHandoffViewKey)) return;
    NSArray<UIView *> *glyphHosts = CCACompactGlyphHosts(buttonView);
    if (!glyphHosts.count) return;

    UIView *handoff = [[UIView alloc] initWithFrame:stableHost.bounds];
    handoff.userInteractionEnabled = NO;
    handoff.backgroundColor = UIColor.clearColor;
    handoff.clipsToBounds = NO;
    NSMutableArray<NSDictionary *> *hostStates = [NSMutableArray array];
    for (UIView *glyph in glyphHosts) {
        [hostStates addObject:@{@"view": glyph, @"hidden": @(glyph.hidden)}];
        if (!glyph.hidden && glyph.alpha > 0.01 && glyph.window) {
            UIView *snapshot = [glyph snapshotViewAfterScreenUpdates:NO];
            if (snapshot) {
                snapshot.frame = [glyph convertRect:glyph.bounds toView:stableHost];
                [handoff addSubview:snapshot];
            }
        }
    }
    if (!handoff.subviews.count) return;

    [stableHost addSubview:handoff];
    objc_setAssociatedObject(moduleView, kCCAResizeGlyphHandoffViewKey, handoff, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(moduleView, kCCAResizeGlyphHandoffHostsKey, hostStates, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [UIView performWithoutAnimation:^{
        for (NSDictionary *state in hostStates) ((UIView *)state[@"view"]).hidden = YES;
    }];
}

static void CCAEndResizeGlyphHandoff(UIView *moduleView) {
    if (!moduleView) return;
    UIView *handoff = objc_getAssociatedObject(moduleView, kCCAResizeGlyphHandoffViewKey);
    NSArray<NSDictionary *> *hostStates = objc_getAssociatedObject(moduleView, kCCAResizeGlyphHandoffHostsKey);
    [UIView performWithoutAnimation:^{
        for (NSDictionary *state in hostStates) ((UIView *)state[@"view"]).hidden = [state[@"hidden"] boolValue];
        [handoff removeFromSuperview];
    }];
    objc_setAssociatedObject(moduleView, kCCAResizeGlyphHandoffViewKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(moduleView, kCCAResizeGlyphHandoffHostsKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static BOOL CCALogicalRectsOverlap(CCUILayoutRect a, CCUILayoutRect b) {
    BOOL xOverlap = a.origin.x < b.origin.x + b.size.width && b.origin.x < a.origin.x + a.size.width;
    BOOL yOverlap = a.origin.y < b.origin.y + b.size.height && b.origin.y < a.origin.y + a.size.height;
    return xOverlap && yOverlap;
}

static BOOL CCALogicalRectRespectsColumnBands(CCUILayoutRect rect) {
    // iOS 18's grid behaves like two visual lanes: columns 1-2 and 3-4. Small
    // modules may live in either lane, but a two-wide module must not straddle
    // the gutter between columns 2 and 3. Full-width layouts are exempt.
    if (rect.size.width > 2) return rect.origin.x == 0 && rect.size.width <= 4;
    return !(rect.origin.x < 2 && rect.origin.x + rect.size.width > 2);
}

static BOOL CCAPagedRectIsValid(CCUILayoutRect rect) {
    if (!rect.size.width || !rect.size.height || rect.origin.x + rect.size.width > 4 || rect.size.height > kCCAMinimumGridRows) return NO;
    if (!CCALogicalRectRespectsColumnBands(rect)) return NO;
    NSUInteger localRow = rect.origin.y % kCCAMinimumGridRows;
    return localRow + rect.size.height <= kCCAMinimumGridRows;
}

static BOOL CCAPagedRectFits(NSString *identifier, CCUILayoutRect rect, NSDictionary<NSString *, NSValue *> *layout) {
    if (!CCAPagedRectIsValid(rect)) return NO;
    for (NSString *otherIdentifier in layout) {
        if ([otherIdentifier isEqualToString:identifier]) continue;
        CCUILayoutRect other = {};
        [layout[otherIdentifier] getValue:&other];
        if (CCALogicalRectsOverlap(rect, other)) return NO;
    }
    return YES;
}

static BOOL CCAFindPagedSlot(NSString *identifier, CCUILayoutSize size, NSUInteger startPage, NSDictionary<NSString *, NSValue *> *layout, CCUILayoutPoint *destination) {
    NSUInteger pageLimit = MIN(kCCAMaxPages, MAX(startPage + 2, layout.count + 2));
    for (NSUInteger page = startPage; page < pageLimit; page++) {
        NSUInteger pageStart = page * kCCAMinimumGridRows;
        for (NSUInteger localRow = 0; localRow + size.height <= kCCAMinimumGridRows; localRow++) {
            for (NSUInteger column = 0; column + size.width <= 4; column++) {
                CCUILayoutRect candidate = {(CCUILayoutPoint){column, pageStart + localRow}, size};
                if (CCAPagedRectFits(identifier, candidate, layout)) {
                    if (destination) *destination = candidate.origin;
                    return YES;
                }
            }
        }
    }
    return NO;
}

static NSUInteger CCAPageForRect(CCUILayoutRect rect) {
    return rect.origin.y / kCCAMinimumGridRows;
}

// Like CCAFindPagedSlot, but guaranteed to return a destination. A module must
// never be dropped from the layout just because its preferred neighbourhood is
// full: an unplaced control silently vanishes from every page and leaves its
// stale rect free to collide with whatever lands on top of it. When no clean
// slot exists near startPage we widen the search to every page, then fall back
// to a fresh page. A rare, self-healing extra page is always preferable to a
// disappeared control (and to the inconsistent layout that can abort a present).
static BOOL CCAGuaranteedPagedSlot(NSString *identifier, CCUILayoutSize size, NSUInteger startPage, NSDictionary<NSString *, NSValue *> *layout, CCUILayoutPoint *destination) {
    CCUILayoutSize clamped = size;
    if (clamped.width == 0) clamped.width = 1;
    if (clamped.height == 0) clamped.height = 1;
    if (clamped.width > 4) clamped.width = 4;
    if (clamped.height > kCCAMinimumGridRows) clamped.height = kCCAMinimumGridRows;
    if (CCAFindPagedSlot(identifier, clamped, startPage, layout, destination)) return YES;
    if (startPage != 0 && CCAFindPagedSlot(identifier, clamped, 0, layout, destination)) return YES;
    NSUInteger highestOccupiedPage = 0;
    for (NSString *other in layout) {
        if ([other isEqualToString:identifier]) continue;
        CCUILayoutRect rect = {};
        [layout[other] getValue:&rect];
        highestOccupiedPage = MAX(highestOccupiedPage, CCAPageForRect(rect));
    }
    for (NSUInteger page = highestOccupiedPage + 1; page < kCCAMaxPages; page++) {
        if (CCAFindPagedSlot(identifier, clamped, page, layout, destination)) return YES;
    }
    // Absolute last resort: the top-left of the final page. Only reachable if
    // every one of the ~288 cells is occupied, which the page cap makes
    // impossible in practice; kept so the function is total by construction.
    if (destination) *destination = (CCUILayoutPoint){0, (kCCAMaxPages - 1) * kCCAMinimumGridRows};
    return YES;
}

// A page owned by a single module gets a themed scrubber indicator (music
// note for now playing, cellular glyph for connectivity). Returns nil when
// the page holds anything else so the caller falls back to the plain dot.
static NSString *CCAThemedPageIndicatorSymbolForPage(NSUInteger page) {
    UIViewController *overlay = gOverlayControllers.allObjects.firstObject;
    if (!overlay) return nil;
    NSString *soleIdentifier = nil;
    NSUInteger moduleCount = 0;
    for (UIViewController *module in CCACollectModuleControllers(overlay)) {
        NSString *identifier = CCAModuleIdentifier(module);
        NSValue *value = identifier.length ? gCCANativeLayoutRects[identifier] : nil;
        if (!value) continue;
        CCUILayoutRect rect = {};
        [value getValue:&rect];
        NSArray<NSNumber *> *origin = gCCACustomOrigins[identifier];
        if (origin.count >= 2) rect.origin = (CCUILayoutPoint){origin[0].unsignedIntegerValue, origin[1].unsignedIntegerValue};
        NSArray<NSNumber *> *size = gCCACustomSizes[identifier];
        if (size.count >= 2) rect.size = (CCUILayoutSize){size[0].unsignedIntegerValue, size[1].unsignedIntegerValue};
        if (!CCAPagedRectIsValid(rect) || CCAPageForRect(rect) != page) continue;
        moduleCount++;
        if (moduleCount > 1) return nil;
        soleIdentifier = identifier;
    }
    if (moduleCount != 1) return nil;
    if ([soleIdentifier isEqualToString:@"com.apple.mediaremote.controlcenter.nowplaying"]) return @"music.note";
    if ([soleIdentifier isEqualToString:@"com.apple.control-center.ConnectivityModule"]) return @"antenna.radiowaves.left.and.right";
    return nil;
}

static BOOL CCALogicalRectFits(NSString *identifier, CCUILayoutRect rect, NSDictionary<NSString *, NSValue *> *layout, NSUInteger maxRows) {
    if (rect.size.width == 0 || rect.size.height == 0 || rect.origin.x + rect.size.width > 4 || rect.origin.y + rect.size.height > maxRows) return NO;
    if (!CCALogicalRectRespectsColumnBands(rect)) return NO;
    for (NSString *otherIdentifier in layout) {
        if ([otherIdentifier isEqualToString:identifier]) continue;
        CCUILayoutRect other = {};
        [layout[otherIdentifier] getValue:&other];
        if (CCALogicalRectsOverlap(rect, other)) return NO;
    }
    return YES;
}

static BOOL CCALogicalLayoutIsLegal(NSDictionary<NSString *, NSValue *> *layout, NSUInteger maxRows) {
    NSArray<NSString *> *identifiers = layout.allKeys;
    for (NSUInteger first = 0; first < identifiers.count; first++) {
        CCUILayoutRect a = {};
        [layout[identifiers[first]] getValue:&a];
        if (a.size.width == 0 || a.size.height == 0 || a.origin.x + a.size.width > 4 || a.origin.y + a.size.height > maxRows) return NO;
        if (!CCALogicalRectRespectsColumnBands(a)) return NO;
        for (NSUInteger second = first + 1; second < identifiers.count; second++) {
            CCUILayoutRect b = {};
            [layout[identifiers[second]] getValue:&b];
            if (CCALogicalRectsOverlap(a, b)) return NO;
        }
    }
    return YES;
}

static NSMutableDictionary<NSString *, NSValue *> *CCALayoutForPage(UIViewController *overlay, NSUInteger page, NSUInteger maxRows) {
    NSMutableDictionary<NSString *, NSValue *> *layout = [NSMutableDictionary dictionary];
    NSUInteger pageStart = page * kCCAMinimumGridRows;
    for (UIViewController *module in CCACollectModuleControllers(overlay)) {
        NSString *identifier = CCAModuleIdentifier(module);
        NSValue *nativeValue = identifier.length ? gCCANativeLayoutRects[identifier] : nil;
        if (!nativeValue) continue;
        CCUILayoutRect rect = {};
        [nativeValue getValue:&rect];
        NSArray<NSNumber *> *origin = gCCACustomOrigins[identifier];
        if (origin.count >= 2) rect.origin = (CCUILayoutPoint){origin[0].unsignedIntegerValue, origin[1].unsignedIntegerValue};
        NSArray<NSNumber *> *size = gCCACustomSizes[identifier];
        if (size.count >= 2) rect.size = (CCUILayoutSize){size[0].unsignedIntegerValue, size[1].unsignedIntegerValue};
        if (rect.origin.y < pageStart || rect.origin.y >= pageStart + maxRows) continue;
        rect.origin.y -= pageStart;
        if (rect.origin.x + rect.size.width > 4 || rect.origin.y + rect.size.height > maxRows) continue;
        layout[identifier] = [NSValue value:&rect withObjCType:@encode(CCUILayoutRect)];
    }
    return layout;
}

static NSMutableDictionary<NSString *, NSValue *> *CCACurrentPageLayout(UIViewController *overlay, NSUInteger maxRows) {
    return CCALayoutForPage(overlay, gCCACurrentPage, maxRows);
}

static NSUInteger CCADerivedVisiblePageForOverlay(UIViewController *overlay) {
    if (!overlay.view) return MIN(gCCACurrentPage, MAX((NSUInteger)1, gCCAPageCount) - 1);
    NSMutableDictionary<NSNumber *, NSNumber *> *scores = [NSMutableDictionary dictionary];
    CGRect overlayBounds = overlay.view.bounds;
    for (UIViewController *module in CCACollectModuleControllers(overlay)) {
        if (!module.view || module.view.hidden || module.view.alpha <= 0.01 || CCAModuleViewIsPageHidden(module.view)) continue;
        NSString *identifier = CCAModuleIdentifier(module);
        NSValue *nativeValue = identifier.length ? gCCANativeLayoutRects[identifier] : nil;
        if (!nativeValue) continue;
        CCUILayoutRect rect = {};
        [nativeValue getValue:&rect];
        NSArray<NSNumber *> *origin = gCCACustomOrigins[identifier];
        if (origin.count >= 2) rect.origin = (CCUILayoutPoint){origin[0].unsignedIntegerValue, origin[1].unsignedIntegerValue};
        NSUInteger page = CCAPageForRect(rect);
        CGRect visibleFrame = [module.view convertRect:module.view.bounds toView:overlay.view];
        if (CGRectIsEmpty(CGRectIntersection(visibleFrame, overlayBounds))) continue;
        NSNumber *key = @(page);
        scores[key] = @([scores[key] unsignedIntegerValue] + 1);
    }
    NSNumber *bestPage = nil;
    NSUInteger bestScore = 0;
    for (NSNumber *page in scores) {
        NSUInteger score = scores[page].unsignedIntegerValue;
        if (!bestPage || score > bestScore) {
            bestPage = page;
            bestScore = score;
        }
    }
    if (bestPage) return MIN(bestPage.unsignedIntegerValue, MAX((NSUInteger)1, gCCAPageCount) - 1);
    return MIN(gCCACurrentPage, MAX((NSUInteger)1, gCCAPageCount) - 1);
}

@interface CCAExtendedModuleHitBridge : UIView
@property (nonatomic, weak) UIViewController *overlay;
@end

@implementation CCAExtendedModuleHitBridge
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (!gEnabled || !gCCAControlCenterPresented || gEditModeActive || gCCAExpandedModuleOpen || !self.overlay) return nil;
    UIView *quickAccessHost = [self.overlay.view viewWithTag:181000];
    if (quickAccessHost && !quickAccessHost.hidden && quickAccessHost.alpha > 0.05) {
        for (UIView *candidate in quickAccessHost.subviews) {
            if (![candidate isKindOfClass:[UIControl class]] || candidate.hidden || candidate.alpha <= 0.05) continue;
            CGRect frame = [candidate convertRect:candidate.bounds toView:self];
            if (!CGRectContainsPoint(frame, point)) continue;
            CGPoint controlPoint = [self convertPoint:point toView:candidate];
            return [candidate hitTest:controlPoint withEvent:event] ?: candidate;
        }
    }
    for (UIViewController *module in CCACollectModuleControllers(self.overlay)) {
        if (module.view.hidden || module.view.alpha <= 0.01 || CCAModuleViewIsPageHidden(module.view)) continue;
        CGRect frame = CCAVisibleModuleFrame(module, self.overlay);
        if (!CGRectContainsPoint(frame, point)) continue;
        CGPoint modulePoint = [self convertPoint:point toView:module.view];
        return [module.view hitTest:modulePoint withEvent:event] ?: module.view;
    }
    return nil;
}
@end


@interface CCAsterCoordinator : NSObject <UIGestureRecognizerDelegate>
+ (instancetype)shared;
- (void)installOnOverlay:(UIViewController *)controller;
- (void)installPagingOnOverlay:(UIViewController *)overlay;
- (void)normalizePagedLayoutForOverlay:(UIViewController *)overlay;
- (void)applyPageTransformToOverlay:(UIViewController *)overlay animated:(BOOL)animated;
- (void)animatePageSettleForOverlay:(UIViewController *)overlay
                          duration:(NSTimeInterval)duration
                    timingFunction:(CAMediaTimingFunction *)timingFunction
                      modelChanges:(dispatch_block_t)modelChanges
                        completion:(dispatch_block_t)completion;
- (void)setCurrentPage:(NSUInteger)page forOverlay:(UIViewController *)overlay animated:(BOOL)animated;
- (void)updatePageIndicatorsForOverlay:(UIViewController *)overlay;
- (void)installTopFadeForOverlay:(UIViewController *)overlay;
- (void)updateTopFadeForOverlay:(UIViewController *)overlay presentationAlpha:(CGFloat)alpha;
- (void)updateOwnedDuplicateHostForOverlay:(UIViewController *)overlay presentationAlpha:(CGFloat)alpha;
- (void)animateOwnedDuplicateHostForOverlay:(UIViewController *)overlay presented:(BOOL)presented;
- (void)beginOwnedDuplicateHostPresentationSync;
- (void)ownedDuplicateHostDisplayLinkFired:(CADisplayLink *)displayLink;
- (void)setHeaderChromeHiddenForScrubbing:(BOOL)hidden overlay:(UIViewController *)overlay animated:(BOOL)animated;
- (void)pageIndicatorTouchDown:(UIButton *)sender;
- (void)pageIndicatorPanned:(UIPanGestureRecognizer *)gesture;
- (void)editDismissPanned:(UIPanGestureRecognizer *)gesture;
- (void)editShieldTapped:(UITapGestureRecognizer *)gesture;
- (void)beginInteractivePageTransitionForOverlay:(UIViewController *)overlay startPage:(NSUInteger)startPage;
- (void)updateInteractivePageTransitionForOverlay:(UIViewController *)overlay progress:(CGFloat)progress touchY:(CGFloat)touchY;
- (void)finishInteractivePageTransitionForOverlay:(UIViewController *)overlay targetPage:(NSUInteger)targetPage;
- (void)trackControlCenterPresentationGesture:(UIPanGestureRecognizer *)gesture overlay:(UIViewController *)overlay controller:(id)controller;
- (void)presentationPanDisplayLinkFired:(CADisplayLink *)displayLink;
- (void)beginPresentationPanDiscoveryForOverlay:(UIViewController *)overlay controller:(id)controller;
- (void)presentationPanDiscoveryDisplayLinkFired:(CADisplayLink *)displayLink;
- (void)updatePagedModuleVisibilityForOverlay:(UIViewController *)overlay showAdjacent:(BOOL)showAdjacent;
- (void)settlePagedModuleVisibilityForOverlay:(UIViewController *)overlay animated:(BOOL)animated token:(id)token;
- (void)setEditControlsSuppressedForPaging:(BOOL)suppressed overlay:(UIViewController *)overlay animated:(BOOL)animated;
- (void)setEditing:(BOOL)editing;
- (void)dismissEditingImmediately;
- (void)setEditPresentation:(BOOL)editing forOverlay:(UIViewController *)overlay animated:(BOOL)animated;
- (void)applyRestingModuleOffsetToOverlay:(UIViewController *)overlay;
- (void)setQuickAccessButtonsHidden:(BOOL)hidden forOverlay:(UIViewController *)overlay animated:(BOOL)animated;
- (void)hideOwnedChromeForExpandedPlatterInOverlay:(UIViewController *)overlay;
- (void)expandConnectivityFromMiniCluster:(UIButton *)sender;
- (void)openVPNSettings:(UIControl *)sender;
- (void)connectivityProxyTapped:(UIControl *)sender;
- (void)connectivityTileProxyTapped:(UIControl *)sender;
- (void)connectivityTileProxyTouchDown:(UIControl *)sender;
- (void)connectivityTileProxyTouchUp:(UIControl *)sender;
- (void)connectivityTileProxyHeld:(UILongPressGestureRecognizer *)gesture;
- (void)connectivityTileProxyForcePressed:(UIControl *)sender;
- (void)applyResizedPresentationToModule:(UIViewController *)module;
- (void)updateEditControlFramesForOverlay:(UIViewController *)overlay;
- (UIView *)editChromeHostForModuleView:(UIView *)moduleView overlay:(UIViewController *)overlay;
- (BOOL)pointHitsEditChrome:(CGPoint)point overlay:(UIViewController *)overlay generous:(BOOL)generous;
- (void)positionEditControlsForModuleView:(UIView *)moduleView overlay:(UIViewController *)overlay overlayFrame:(CGRect)overlayFrame;
- (UIButton *)removeButtonAtPoint:(CGPoint)point overlay:(UIViewController *)overlay;
- (void)updateEditPageGridTransformsForOverlay:(UIViewController *)overlay;
- (CCAEditGridView *)prepareGridForOverlay:(UIViewController *)overlay collection:(UIViewController *)collection;
- (CCAEditGridView *)editGridForPage:(NSUInteger)page overlay:(UIViewController *)overlay;
- (void)clearEditGridLandingRectsForOverlay:(UIViewController *)overlay;
- (void)setEditGridLandingRects:(NSArray<NSValue *> *)rects forPage:(NSUInteger)page overlay:(UIViewController *)overlay;
- (void)updateEditingChromeForPresentationProgress:(CGFloat)progress overlay:(UIViewController *)overlay;
- (void)applyTransitionRadiusToModule:(UIViewController *)module;
- (void)applyClosingCompactRadiusToModule:(UIViewController *)module overlay:(UIViewController *)overlay sourceObject:(id)object;
- (BOOL)applyExplicitGridMoveFrom:(NSString *)sourceID toOrigin:(CCUILayoutPoint)destination onPage:(NSUInteger)page overlay:(UIViewController *)overlay;
- (BOOL)applyExplicitGridInsertionFrom:(NSString *)sourceID toOrigin:(CCUILayoutPoint)destination onPage:(NSUInteger)page maxRows:(NSUInteger)maxRows overlay:(UIViewController *)overlay;
- (CGFloat)refinedCornerRadiusForSize:(CGSize)size;
- (void)applyRefinedLookToModule:(UIViewController *)module;
- (void)installQuickAccessHostOnOverlay:(UIViewController *)controller;
- (void)syncOwnedDuplicateModulesForOverlay:(UIViewController *)overlay;
- (void)layoutOwnedDuplicateModulesForOverlay:(UIViewController *)overlay;
- (BOOL)addOwnedDuplicateForIdentifier:(NSString *)identifier;
- (NSArray<NSString *> *)enabledModuleIdentifiers;
- (NSArray<NSString *> *)fixedModuleIdentifiers;
- (NSArray<NSDictionary *> *)availableControlCatalog;
- (CCUILayoutSize)catalogLayoutSizeForIdentifier:(NSString *)identifier;
- (CGSize)catalogPointSizeForLayoutSize:(CCUILayoutSize)size;
- (NSArray<NSDictionary *> *)temporarilyRevealModuleForSheetSnapshot:(UIView *)moduleView;
- (void)restoreModuleSheetSnapshotState:(NSArray<NSDictionary *> *)records;
- (UIView *)previewViewForCatalogEntry:(NSDictionary *)entry;
- (void)addControlSheetDidSelectIdentifier:(NSString *)identifier fromSheet:(UIViewController *)sheet;
@end

@interface CCAAddControlSheetViewController : UIViewController <UISearchBarDelegate>
@property (nonatomic, copy) NSArray<NSDictionary *> *catalog;
@property (nonatomic) BOOL builtGrid;
@property (nonatomic, copy) NSString *query;
@property (nonatomic, strong) NSMutableDictionary<NSString *, UIView *> *previewCache;
@end

@implementation CCAsterCoordinator

+ (instancetype)shared {
    static CCAsterCoordinator *shared;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ shared = [self new]; });
    return shared;
}

- (UIImage *)symbol:(NSString *)name size:(CGFloat)size {
    UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:size weight:UIImageSymbolWeightSemibold];
    return [UIImage systemImageNamed:name withConfiguration:configuration];
}

- (UIButton *)cornerButtonWithSymbol:(NSString *)symbol action:(SEL)action tag:(NSInteger)tag materialRoot:(UIView *)materialRoot {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.tag = tag;
    button.tintColor = [UIColor colorWithWhite:1.0 alpha:0.97];
    UIView *material = CCANewConnectivityMaterialView(materialRoot ?: button);
    material.tag = kCCAPowerMaterialTag;
    material.frame = CGRectMake(5.0, 5.0, 30.0, 30.0);
    material.layer.cornerRadius = 15.0;
    material.layer.cornerCurve = kCACornerCurveContinuous;
    material.clipsToBounds = YES;
    material.layer.masksToBounds = YES;
    material.alpha = 1.0;
    material.userInteractionEnabled = NO;
    [button insertSubview:material atIndex:0];
    UIImage *image = [[self symbol:symbol size:15.0] imageWithTintColor:[UIColor colorWithWhite:1.0 alpha:0.97]
                                                             renderingMode:UIImageRenderingModeAlwaysOriginal];
    [button setImage:nil forState:UIControlStateNormal];
    UIImageView *glyphView = [[UIImageView alloc] initWithImage:image];
    glyphView.userInteractionEnabled = NO;
    glyphView.contentMode = UIViewContentModeCenter;
    glyphView.translatesAutoresizingMaskIntoConstraints = NO;
    [button addSubview:glyphView];
    [NSLayoutConstraint activateConstraints:@[
        [glyphView.centerXAnchor constraintEqualToAnchor:button.centerXAnchor],
        [glyphView.centerYAnchor constraintEqualToAnchor:button.centerYAnchor],
        [glyphView.widthAnchor constraintEqualToConstant:30.0],
        [glyphView.heightAnchor constraintEqualToConstant:30.0],
    ]];
    [button bringSubviewToFront:glyphView];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.accessibilityIdentifier = tag == 181001 ? @"CCAsterAddButton" : @"CCAsterPowerButton";
    return button;
}

- (void)setQuickAccessButtonsHidden:(BOOL)hidden forOverlay:(UIViewController *)overlay animated:(BOOL)animated {
    UIView *host = [overlay.view viewWithTag:181000];
    if (!host) return;
    BOOL shouldHide = hidden || !gQuickAccessButtonsEnabled;
    host.userInteractionEnabled = !shouldHide;
    if (!shouldHide && host.superview) [host.superview bringSubviewToFront:host];
    NSObject *token = [NSObject new];
    objc_setAssociatedObject(host, kCCAQuickAccessAnimationTokenKey, token, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIView *dismissalProxy = [overlay.view viewWithTag:kCCAQuickAccessDismissalProxyTag];
    if (!shouldHide && dismissalProxy && CCAExpandedChromeRevealActive()) {
        [UIView performWithoutAnimation:^{
            host.hidden = NO;
            host.alpha = 0.0;
            host.transform = CGAffineTransformIdentity;
        }];
        return;
    }
    if (!shouldHide && CCAExpandedChromeRevealActive() &&
        (!host.hidden || host.alpha > 0.05 || host.layer.animationKeys.count > 0)) {
        host.hidden = NO;
        return;
    }
    if (!shouldHide) host.hidden = NO;
    void (^changes)(void) = ^{
        host.alpha = shouldHide ? 0.0 : 1.0;
        host.transform = shouldHide ? CGAffineTransformMakeTranslation(0.0, -9.0) : CGAffineTransformIdentity;
        if (!shouldHide) CCASetQuickAccessMaterialsHidden(host, NO);
    };
    void (^completion)(BOOL) = ^(__unused BOOL finished) {
        // Expansion and presentation-state callbacks can overlap. Never let an
        // obsolete hide completion make the newly revealed chrome disappear.
        if (objc_getAssociatedObject(host, kCCAQuickAccessAnimationTokenKey) != token) return;
        host.hidden = shouldHide;
    };
    if (animated) {
        [UIView animateWithDuration:0.28 delay:0.0 options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionBeginFromCurrentState animations:changes completion:completion];
    } else {
        changes();
        completion(YES);
    }
}

- (void)hideOwnedChromeForExpandedPlatterInOverlay:(UIViewController *)overlay {
    if (!overlay.view) return;
    UIView *quickAccess = [overlay.view viewWithTag:181000];
    quickAccess.hidden = YES;
    quickAccess.alpha = 0.0;
    UIView *topFade = [overlay.view viewWithTag:kCCATopFadeTag];
    topFade.hidden = YES;
    topFade.alpha = 0.0;
    UIView *pageIndicators = [overlay.view viewWithTag:kCCAPageIndicatorHostTag];
    pageIndicators.hidden = YES;
    pageIndicators.alpha = 0.0;
    UIView *duplicateHost = [overlay.view viewWithTag:kCCAOwnedDuplicateHostTag];
    duplicateHost.hidden = YES;
    duplicateHost.alpha = 0.0;
    for (UIView *subview in overlay.view.subviews) {
        if (subview.tag == kCCAEditGridTag || subview.tag == kCCAEditTouchShieldTag ||
            subview.tag == kCCAAddControlButtonTag || subview.tag == kCCARemoveButtonTag ||
            subview.tag == kCCAResizeButtonTag || subview.tag == kCCAResizeBlurSnapshotTag) {
            subview.hidden = YES;
            subview.alpha = 0.0;
        }
    }
    for (UIViewController *module in CCACollectModuleControllers(overlay)) {
        UIVisualEffectView *border = objc_getAssociatedObject(module.view, @selector(applyEditingToModule:editing:));
        border.hidden = YES;
        border.alpha = 0.0;
        UIButton *remove = objc_getAssociatedObject(module.view, kCCARemoveButtonKey);
        UIButton *resize = objc_getAssociatedObject(module.view, kCCAResizeButtonKey);
        remove.hidden = YES;
        remove.alpha = 0.0;
        resize.hidden = YES;
        resize.alpha = 0.0;
        // Hide the resized-presentation overlay only for the module actually
        // expanding: identifier match, or (for identifier-less expansions) the
        // module whose container is flagged expanded. Hiding all of them left
        // every resizable module label-less afterwards.
        BOOL moduleIsExpanding = [CCAModuleIdentifier(module) isEqualToString:gCCAExpandedModuleIdentifier];
        if (!moduleIsExpanding && !gCCAExpandedModuleIdentifier.length) {
            @try {
                UIView *container = module.view;
                while (container && ![NSStringFromClass(container.class) isEqualToString:@"CCUIContentModuleContentContainerView"]) container = container.superview;
                moduleIsExpanding = [[container valueForKey:@"_expanded"] boolValue];
            } @catch (__unused NSException *exception) {}
        }
        if (moduleIsExpanding) {
            UIView *buttonView = CCAFindSubviewWithClassName(module.view, @"CCUIButtonModuleView");
            UIView *presentation = [buttonView viewWithTag:kCCAResizePresentationTag] ?: [module.view viewWithTag:kCCAResizePresentationTag];
            presentation.hidden = YES;
            presentation.alpha = 0.0;
        }
    }
}

- (UIViewController *)moduleCollectionControllerInOverlay:(UIViewController *)overlay {
    NSMutableArray *queue = [NSMutableArray arrayWithObject:overlay];
    while (queue.count) {
        UIViewController *candidate = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([NSStringFromClass(candidate.class) containsString:@"ModuleCollectionViewController"]) return candidate;
        [queue addObjectsFromArray:candidate.childViewControllers];
    }
    return nil;
}

- (UIView *)ownedDuplicateHostForOverlay:(UIViewController *)overlay {
    if (!overlay.view) return nil;
    UIView *host = [overlay.view viewWithTag:kCCAOwnedDuplicateHostTag];
    if (!host) {
        host = [[CCAOwnedDuplicateHostView alloc] initWithFrame:overlay.view.bounds];
        host.tag = kCCAOwnedDuplicateHostTag;
        host.backgroundColor = UIColor.clearColor;
        host.opaque = NO;
        host.clipsToBounds = NO;
        host.userInteractionEnabled = YES;
        host.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        UIViewController *collection = [self moduleCollectionControllerInOverlay:overlay];
        if (collection.view && collection.view.superview == overlay.view) [overlay.view insertSubview:host aboveSubview:collection.view];
        else [overlay.view addSubview:host];
        host.hidden = YES;
        host.alpha = 0.0;
    } else if (host.superview != overlay.view) {
        [host removeFromSuperview];
        UIViewController *collection = [self moduleCollectionControllerInOverlay:overlay];
        if (collection.view && collection.view.superview == overlay.view) [overlay.view insertSubview:host aboveSubview:collection.view];
        else [overlay.view addSubview:host];
    }
    host.frame = overlay.view.bounds;
    return host;
}

- (CGPoint)gridBaseOriginForOverlay:(UIViewController *)overlay {
    CGPoint fallback = CGPointMake(CGFLOAT_MAX, CGFLOAT_MAX);
    CGFloat span = CCAVisualPageSpan();
    for (UIViewController *module in CCACollectModuleControllers(overlay)) {
        if ([module isKindOfClass:[CCAOwnedDuplicateModuleViewController class]]) continue;
        NSString *identifier = CCAModuleIdentifier(module);
        NSValue *nativeValue = identifier.length ? gCCANativeLayoutRects[identifier] : nil;
        if (!nativeValue || !module.view) continue;
        CCUILayoutRect logical = {};
        [nativeValue getValue:&logical];
        NSArray<NSNumber *> *origin = gCCACustomOrigins[identifier];
        if (origin.count >= 2) logical.origin = (CCUILayoutPoint){origin[0].unsignedIntegerValue, origin[1].unsignedIntegerValue};
        NSArray<NSNumber *> *size = gCCACustomSizes[identifier];
        if (size.count >= 2) logical.size = (CCUILayoutSize){size[0].unsignedIntegerValue, size[1].unsignedIntegerValue};
        if (!logical.size.width || !logical.size.height) continue;
        UIView *presentationWrapper = CCAPresentationWrapperForModuleController(module);
        UIView *container = presentationWrapper.superview;
        CGRect frame = CGRectZero;
        if (container && [NSStringFromClass(container.class) containsString:@"ContentModuleContainerView"] && container.superview) {
            // Native presentation drives each container from a translated and
            // scaled closed state. Deriving the grid origin from convertRect:
            // therefore changed the duplicate layout base during the opening
            // animation. Recover the container's untransformed model rect from
            // its position/bounds so the base is the final grid origin from the
            // first frame onward.
            CGSize size = container.bounds.size;
            CGPoint anchor = container.layer.anchorPoint;
            CGPoint position = container.layer.position;
            CGRect untransformed = CGRectMake(position.x - anchor.x * size.width,
                                               position.y - anchor.y * size.height,
                                               size.width, size.height);
            frame = [container.superview convertRect:untransformed toView:overlay.view];
        } else {
            frame = [module.view convertRect:module.view.bounds toView:overlay.view];
        }
        if (CGRectIsEmpty(frame)) continue;
        NSUInteger page = CCAPageForRect(logical);
        NSUInteger localRow = logical.origin.y % kCCAMinimumGridRows;
        CGFloat baseX = CGRectGetMinX(frame) - logical.origin.x * kCCAGridStep;
        CGFloat baseY = CGRectGetMinY(frame) - localRow * kCCAGridStep - ((CGFloat)((NSInteger)page - (NSInteger)gCCACurrentPage) * span) - gCCAPagerInteractiveTranslation;
        fallback.x = MIN(fallback.x, baseX);
        fallback.y = MIN(fallback.y, baseY);
    }
    if (fallback.x == CGFLOAT_MAX || fallback.y == CGFLOAT_MAX) {
        CGFloat width = overlay.view ? CGRectGetWidth(overlay.view.bounds) : CGRectGetWidth(UIScreen.mainScreen.bounds);
        return CGPointMake((width - CCAGridVisibleWidth()) * 0.5, 125.0);
    }
    return fallback;
}

- (void)syncOwnedDuplicateModulesForOverlay:(UIViewController *)overlay {
    if (!overlay.view) return;
    UIView *host = [self ownedDuplicateHostForOverlay:overlay];
    NSMutableDictionary<NSString *, CCAOwnedDuplicateModuleViewController *> *existing = [NSMutableDictionary dictionary];
    for (UIViewController *child in overlay.childViewControllers) {
        if (![child isKindOfClass:[CCAOwnedDuplicateModuleViewController class]]) continue;
        CCAOwnedDuplicateModuleViewController *duplicate = (CCAOwnedDuplicateModuleViewController *)child;
        if (duplicate.moduleIdentifier.length) existing[duplicate.moduleIdentifier] = duplicate;
    }
    for (NSString *identifier in existing.allKeys) {
        if (gCCADuplicateFamilies[identifier]) continue;
        UIViewController *stale = existing[identifier];
        UIView *container = objc_getAssociatedObject(stale, kCCAOwnedDuplicateContainerKey);
        [stale willMoveToParentViewController:nil];
        [container removeFromSuperview];
        if (!container) [stale.view removeFromSuperview];
        [stale removeFromParentViewController];
        [existing removeObjectForKey:identifier];
    }
    for (NSString *identifier in gCCADuplicateFamilies) {
        NSString *baseIdentifier = gCCADuplicateFamilies[identifier];
        if (!identifier.length || !baseIdentifier.length) continue;
        CCAOwnedDuplicateModuleViewController *duplicate = existing[identifier];
        BOOL createdDuplicate = NO;
        if (!duplicate) {
            duplicate = [[CCAOwnedDuplicateModuleViewController alloc] initWithModuleIdentifier:identifier baseIdentifier:baseIdentifier];
            [overlay addChildViewController:duplicate];
            UIView *container = [[UIView alloc] initWithFrame:CGRectZero];
            container.backgroundColor = UIColor.clearColor;
            container.opaque = NO;
            container.clipsToBounds = NO;
            UIView *presentation = [[UIView alloc] initWithFrame:CGRectZero];
            presentation.backgroundColor = UIColor.clearColor;
            presentation.opaque = NO;
            presentation.clipsToBounds = NO;
            [container addSubview:presentation];
            [presentation addSubview:duplicate.view];
            [host addSubview:container];
            objc_setAssociatedObject(duplicate, kCCAOwnedDuplicateContainerKey, container, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(duplicate, kCCAOwnedDuplicatePresentationKey, presentation, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [duplicate didMoveToParentViewController:overlay];
            existing[identifier] = duplicate;
            createdDuplicate = YES;
        } else {
            UIView *container = objc_getAssociatedObject(duplicate, kCCAOwnedDuplicateContainerKey);
            UIView *presentation = objc_getAssociatedObject(duplicate, kCCAOwnedDuplicatePresentationKey);
            if (!container || !presentation) {
                [duplicate.view removeFromSuperview];
                container = [[UIView alloc] initWithFrame:CGRectZero];
                container.backgroundColor = UIColor.clearColor;
                container.opaque = NO;
                container.clipsToBounds = NO;
                presentation = [[UIView alloc] initWithFrame:CGRectZero];
                presentation.backgroundColor = UIColor.clearColor;
                presentation.opaque = NO;
                presentation.clipsToBounds = NO;
                [container addSubview:presentation];
                [presentation addSubview:duplicate.view];
                objc_setAssociatedObject(duplicate, kCCAOwnedDuplicateContainerKey, container, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                objc_setAssociatedObject(duplicate, kCCAOwnedDuplicatePresentationKey, presentation, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            if (container.superview != host) {
                [container removeFromSuperview];
                [host addSubview:container];
            }
        }
        NSValue *baseSize = gCCABaseLayoutSizes[baseIdentifier] ?: gCCAProviderSizes[baseIdentifier];
        CCUILayoutSize size = {1, 1};
        if (baseSize) [baseSize getValue:&size];
        if (!size.width) size.width = 1;
        if (!size.height) size.height = 1;
        gCCABaseLayoutSizes[identifier] = [NSValue value:&size withObjCType:@encode(CCUILayoutSize)];
        CCUILayoutRect rect = {(CCUILayoutPoint){0, 0}, size};
        NSValue *nativeValue = gCCANativeLayoutRects[identifier];
        if (nativeValue) [nativeValue getValue:&rect];
        rect.size = size;
        gCCANativeLayoutRects[identifier] = [NSValue value:&rect withObjCType:@encode(CCUILayoutRect)];
        if (createdDuplicate || ![duplicate.view viewWithTag:kCCAResizePresentationTag]) {
            [self applyRefinedLookToModule:duplicate];
        }
    }
    [self layoutOwnedDuplicateModulesForOverlay:overlay];
}

- (void)layoutOwnedDuplicateModulesForOverlay:(UIViewController *)overlay {
    UIView *host = [overlay.view viewWithTag:kCCAOwnedDuplicateHostTag];
    if (!host) return;
    if (host.superview != overlay.view) {
        [host removeFromSuperview];
        UIViewController *collection = [self moduleCollectionControllerInOverlay:overlay];
        if (collection.view && collection.view.superview == overlay.view) [overlay.view insertSubview:host aboveSubview:collection.view];
        else [overlay.view addSubview:host];
    }
    host.frame = overlay.view.bounds;
    CGPoint base = [self gridBaseOriginForOverlay:overlay];
    CGFloat span = CCAVisualPageSpan();
    CGFloat scrubScaleX = gCCAPagerHeldScale * gCCAPagerJelloScaleX;
    CGFloat scrubScaleY = gCCAPagerHeldScale * gCCAPagerJelloScaleY;
    CGPoint scrubCenter = CGPointMake(CGRectGetMidX(overlay.view.bounds), CGRectGetMidY(overlay.view.bounds));
    for (UIViewController *child in overlay.childViewControllers) {
        if (![child isKindOfClass:[CCAOwnedDuplicateModuleViewController class]]) continue;
        NSString *identifier = CCAModuleIdentifier(child);
        NSValue *nativeValue = identifier.length ? gCCANativeLayoutRects[identifier] : nil;
        if (!nativeValue) continue;
        CCUILayoutRect rect = {};
        [nativeValue getValue:&rect];
        NSArray<NSNumber *> *origin = gCCACustomOrigins[identifier];
        if (origin.count >= 2) rect.origin = (CCUILayoutPoint){origin[0].unsignedIntegerValue, origin[1].unsignedIntegerValue};
        NSArray<NSNumber *> *size = gCCACustomSizes[identifier];
        if (size.count >= 2) rect.size = (CCUILayoutSize){size[0].unsignedIntegerValue, size[1].unsignedIntegerValue};
        if (!rect.size.width) rect.size.width = 1;
        if (!rect.size.height) rect.size.height = 1;
        NSUInteger page = CCAPageForRect(rect);
        NSUInteger localRow = rect.origin.y % kCCAMinimumGridRows;
        CGSize pointSize = [self catalogPointSizeForLayoutSize:rect.size];
        CGRect frame = CGRectMake(base.x + rect.origin.x * kCCAGridStep,
                                  base.y + localRow * kCCAGridStep + ((CGFloat)((NSInteger)page - (NSInteger)gCCACurrentPage) * span) + gCCAPagerInteractiveTranslation,
                                  pointSize.width,
                                  pointSize.height);
        UIView *container = objc_getAssociatedObject(child, kCCAOwnedDuplicateContainerKey);
        UIView *presentation = objc_getAssociatedObject(child, kCCAOwnedDuplicatePresentationKey);
        if (!container || !presentation) continue;
        CGPoint frameCenter = CGPointMake(CGRectGetMidX(frame), CGRectGetMidY(frame));
        if (gCCAPagerScrubbingActive) {
            frameCenter.x = scrubCenter.x + (frameCenter.x - scrubCenter.x) * scrubScaleX;
            frameCenter.y = scrubCenter.y + (frameCenter.y - scrubCenter.y) * scrubScaleY;
        }
        container.bounds = (CGRect){CGPointZero, pointSize};
        container.center = frameCenter;
        presentation.bounds = (CGRect){CGPointZero, pointSize};
        presentation.center = CGPointMake(pointSize.width * 0.5, pointSize.height * 0.5);
        child.view.bounds = (CGRect){CGPointZero, pointSize};
        child.view.center = CGPointMake(pointSize.width * 0.5, pointSize.height * 0.5);
        child.view.layer.cornerRadius = [self refinedCornerRadiusForSize:pointSize];
        child.view.layer.cornerCurve = kCACornerCurveContinuous;
        child.view.layer.masksToBounds = YES;
        if (gEditModeActive) {
            BOOL activeDragSource = CCAIsActiveDragModuleIdentifier(identifier);
            CGRect viewport = CGRectInset(overlay.view.bounds, -24.0, -24.0);
            CGRect overlayFrame = [child.view convertRect:child.view.bounds toView:overlay.view];
            BOOL ownerVisible = !activeDragSource && !CCAModuleViewIsPageHidden(child.view) && CGRectIntersectsRect(overlayFrame, viewport);
            UIVisualEffectView *border = objc_getAssociatedObject(child.view, @selector(applyEditingToModule:editing:));
            UIButton *remove = objc_getAssociatedObject(child.view, kCCARemoveButtonKey);
            UIButton *resize = objc_getAssociatedObject(child.view, kCCAResizeButtonKey);
            if (border && !gCCAResizeInProgress) {
                CGRect presentationFrame = CGRectMake(CGRectGetMinX(child.view.frame), CGRectGetMinY(child.view.frame),
                                                      CGRectGetWidth(child.view.bounds), CGRectGetHeight(child.view.bounds));
                [self configureEditingBorder:border moduleFrame:presentationFrame];
                border.hidden = !ownerVisible || !gModuleBordersEnabled;
                border.alpha = ownerVisible && gModuleBordersEnabled ? 1.0 : 0.0;
            }
            if (remove) {
                remove.hidden = !ownerVisible || !gRemovalButtonsEnabled;
                remove.alpha = ownerVisible && gRemovalButtonsEnabled ? 1.0 : 0.0;
            }
            BOOL supportsResize = [self moduleIdentifierSupportsResizing:identifier];
            if (resize) {
                resize.hidden = !ownerVisible || !supportsResize;
                resize.alpha = ownerVisible && supportsResize ? 1.0 : 0.0;
            }
            [self positionEditControlsForModuleView:child.view overlay:overlay overlayFrame:overlayFrame];
            if (remove && !remove.hidden) [remove.superview bringSubviewToFront:remove];
            if (resize && !resize.hidden) [resize.superview bringSubviewToFront:resize];
        }
    }
    UIView *hitBridge = [overlay.view viewWithTag:kCCAExtendedHitBridgeTag];
    if (hitBridge) [overlay.view bringSubviewToFront:hitBridge];
    UIView *addControl = [overlay.view viewWithTag:kCCAAddControlButtonTag];
    if (addControl && !addControl.hidden) [overlay.view bringSubviewToFront:addControl];
    if (gCCAControlCenterPresented && !gCCAOwnedDuplicateHostDisplayLink && !gCCAExpandedModuleOpen) {
        host.transform = CGAffineTransformIdentity;
        host.alpha = gCCAPagerScrubbingActive ? gCCAPagerHeldAlphaFactor : 1.0;
        for (UIViewController *child in overlay.childViewControllers) {
            if (![child isKindOfClass:[CCAOwnedDuplicateModuleViewController class]]) continue;
            UIView *container = objc_getAssociatedObject(child, kCCAOwnedDuplicateContainerKey);
            UIView *presentation = objc_getAssociatedObject(child, kCCAOwnedDuplicatePresentationKey);
            container.transform = CGAffineTransformIdentity;
            presentation.transform = gCCAPagerScrubbingActive ?
                CGAffineTransformMakeScale(scrubScaleX, scrubScaleY) :
                CGAffineTransformIdentity;
            presentation.layer.opacity = 1.0;
            child.view.alpha = 1.0;
        }
    }
}

- (void)installQuickAccessHostOnOverlay:(UIViewController *)controller {
    if (!gEnabled || !controller.view) return;
    UIView *existingHost = [controller.view viewWithTag:181000];
    if (existingHost) {
        existingHost.userInteractionEnabled = gQuickAccessButtonsEnabled;
        return;
    }
    // Keep this strictly inside the overlay. The system status-bar superview is
    // owned above Control Center and survives dismissal, which leaks buttons
    // onto the Home Screen. Header pocket is overlay-scoped and still carries
    // the native top-chrome presentation transform.
    UIView *animationHost = CCAFindSubviewWithClassName(controller.view, @"CCUIHeaderPocketView");
    if (!animationHost) {
        @try {
            id candidate = [(id)controller valueForKey:@"overlayHeaderView"];
            if ([candidate isKindOfClass:[UIView class]]) animationHost = candidate;
        } @catch (__unused NSException *exception) {}
    }
    if (!animationHost) animationHost = controller.view;
    UIView *host = [[CCAQuickAccessHostView alloc] initWithFrame:CGRectZero];
    host.tag = 181000;
    host.backgroundColor = UIColor.clearColor;
    host.userInteractionEnabled = YES;
    host.translatesAutoresizingMaskIntoConstraints = NO;
    [animationHost addSubview:host];
    animationHost.clipsToBounds = NO;
    CGRect hostFrameInOverlay = [animationHost convertRect:animationHost.bounds toView:controller.view];
    CGFloat hostOriginY = MAX(CGRectGetMinY(animationHost.frame), CGRectGetMinY(hostFrameInOverlay));
    CGFloat hostOriginX = MAX(CGRectGetMinX(animationHost.frame), CGRectGetMinX(hostFrameInOverlay));
    [NSLayoutConstraint activateConstraints:@[
        [host.topAnchor constraintEqualToAnchor:animationHost.topAnchor constant:-hostOriginY],
        [host.leadingAnchor constraintEqualToAnchor:animationHost.leadingAnchor constant:-hostOriginX],
        [host.widthAnchor constraintEqualToConstant:CGRectGetWidth(controller.view.bounds)],
        [host.heightAnchor constraintEqualToConstant:76.0]
    ]];

    UIView *materialRoot = controller.view;
    for (UIViewController *module in CCACollectModuleControllers(controller)) {
        if (!module.view || module.view.hidden || module.view.alpha <= 0.01 || CCAModuleViewIsPageHidden(module.view)) continue;
        materialRoot = module.view;
        break;
    }

    if (gAddButtonEnabled) {
        UIButton *add = [self cornerButtonWithSymbol:@"plus" action:@selector(addTapped:) tag:181001 materialRoot:materialRoot];
        [host addSubview:add];
        [NSLayoutConstraint activateConstraints:@[[add.leadingAnchor constraintEqualToAnchor:host.leadingAnchor constant:22.0], [add.topAnchor constraintEqualToAnchor:host.topAnchor constant:-48.0], [add.widthAnchor constraintEqualToConstant:40.0], [add.heightAnchor constraintEqualToConstant:40.0]]];
    }
    if (gPowerButtonEnabled) {
        UIButton *power = [self cornerButtonWithSymbol:@"power" action:@selector(ignoreTap:) tag:181002 materialRoot:materialRoot];
        power.backgroundColor = UIColor.clearColor;
        UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(powerHeld:)];
        hold.minimumPressDuration = 0.75;
        [power addGestureRecognizer:hold];
        [host addSubview:power];
        [NSLayoutConstraint activateConstraints:@[[power.trailingAnchor constraintEqualToAnchor:host.trailingAnchor constant:-22.0], [power.topAnchor constraintEqualToAnchor:host.topAnchor constant:-48.0], [power.widthAnchor constraintEqualToConstant:40.0], [power.heightAnchor constraintEqualToConstant:40.0]]];
    }
    // The provider-driven collection rebuild replaces the header pocket, so
    // this host can be re-created mid-session. When Control Center is already
    // presented, reveal immediately instead of waiting for the state callback.
    BOOL revealed = gCCAControlCenterPresented && gQuickAccessButtonsEnabled;
    host.alpha = revealed ? 1.0 : 0.0;
    host.hidden = !revealed;
    host.userInteractionEnabled = revealed;
}

- (void)normalizePagedLayoutForOverlay:(UIViewController *)overlay {
    if (!overlay) return;
    // The whole grid/paging system was built assuming portrait dimensions —
    // there's no landscape-aware layout path. Rather than show a garbled
    // mix of portrait-computed frames on a landscape screen, fall back to
    // paging-disabled (a real, already-supported, user-toggleable mode)
    // whenever the overlay is currently landscape. Recomputed here since
    // this function already runs on every meaningful paging-layout trigger.
    gPagingEnabled = gPagingPreferenceEnabled && !CCAIsLandscapeOrientation(overlay.view);
    [self syncOwnedDuplicateModulesForOverlay:overlay];
    NSArray<UIViewController *> *modules = CCACollectModuleControllers(overlay);
    if (!modules.count) return;

    NSMutableDictionary<NSString *, UIViewController *> *moduleByIdentifier = [NSMutableDictionary dictionary];
    for (UIViewController *module in modules) {
        NSString *identifier = CCAModuleIdentifier(module);
        if (identifier.length) moduleByIdentifier[identifier] = module;
    }
    NSMutableArray<NSString *> *order = [NSMutableArray array];
    for (NSString *identifier in gCCAProviderOrder) if (moduleByIdentifier[identifier]) [order addObject:identifier];
    for (NSString *identifier in moduleByIdentifier) if (![order containsObject:identifier]) [order addObject:identifier];

    NSMutableDictionary<NSString *, NSValue *> *placed = [NSMutableDictionary dictionary];
    BOOL changed = NO;
    NSUInteger highestPage = 0;

    // Drop saved origins/sizes for controls that are no longer part of the
    // layout. These process-wide dictionaries outlive provider rebuilds, so a
    // removed or disabled module otherwise leaves a stale rect behind that can
    // inflate the page count or, when the identifier reappears, resurrect an
    // overlap. Only prune identifiers that are neither currently collected nor
    // still enabled, and only once a plausible full module set is present, so a
    // transient partial rebuild can never clear live positions.
    if (moduleByIdentifier.count >= 2) {
        NSArray<NSString *> *enabledForPrune = [self enabledModuleIdentifiers];
        for (NSString *staleID in gCCACustomOrigins.allKeys) {
            if (!moduleByIdentifier[staleID] && ![enabledForPrune containsObject:staleID]) {
                [gCCACustomOrigins removeObjectForKey:staleID];
                changed = YES;
            }
        }
        for (NSString *staleID in gCCACustomSizes.allKeys) {
            if (!moduleByIdentifier[staleID] && ![enabledForPrune containsObject:staleID]) {
                [gCCACustomSizes removeObjectForKey:staleID];
            }
        }
    }

    for (NSString *identifier in order) {
        CCUILayoutRect desired = {};
        NSValue *nativeValue = gCCANativeLayoutRects[identifier];
        if (nativeValue) [nativeValue getValue:&desired];
        NSValue *baseValue = gCCABaseLayoutSizes[identifier] ?: gCCAProviderSizes[identifier];
        if ((!desired.size.width || !desired.size.height) && baseValue) [baseValue getValue:&desired.size];
        NSArray<NSNumber *> *savedSize = gCCACustomSizes[identifier];
        if (savedSize.count >= 2) desired.size = (CCUILayoutSize){savedSize[0].unsignedIntegerValue, savedSize[1].unsignedIntegerValue};
        // Clamp rather than skip. A missing or out-of-range logical size used to
        // drop the control from the layout entirely (it vanished); a control
        // that is present on screen must always be given a placeable footprint.
        if (!desired.size.width) desired.size.width = 1;
        if (!desired.size.height) desired.size.height = 1;
        if (desired.size.width > 4) desired.size.width = 4;
        if (desired.size.height > kCCAMinimumGridRows) desired.size.height = kCCAMinimumGridRows;

        NSArray<NSNumber *> *savedOrigin = gCCACustomOrigins[identifier];
        BOOL hadSavedOrigin = savedOrigin.count >= 2;
        if (hadSavedOrigin) desired.origin = (CCUILayoutPoint){savedOrigin[0].unsignedIntegerValue, savedOrigin[1].unsignedIntegerValue};
        BOOL crossesBoundary = (desired.origin.y % kCCAMinimumGridRows) + desired.size.height > kCCAMinimumGridRows;
        if (!hadSavedOrigin && !nativeValue) desired.origin = (CCUILayoutPoint){0, 0};

        if (!CCAPagedRectFits(identifier, desired, placed)) {
            NSUInteger startPage = desired.origin.y / kCCAMinimumGridRows;
            if (crossesBoundary) startPage++;
            CCUILayoutPoint destination = {};
            // Guaranteed to succeed: reflow the control to the nearest free slot
            // instead of leaving it unplaced (and therefore invisible) when its
            // saved neighbourhood is full.
            CCAGuaranteedPagedSlot(identifier, desired.size, startPage, placed, &destination);
            desired.origin = destination;
        }
        placed[identifier] = [NSValue value:&desired withObjCType:@encode(CCUILayoutRect)];
        highestPage = MAX(highestPage, CCAPageForRect(desired));
        if (!hadSavedOrigin || savedOrigin[0].unsignedIntegerValue != desired.origin.x || savedOrigin[1].unsignedIntegerValue != desired.origin.y) {
            gCCACustomOrigins[identifier] = @[@(desired.origin.x), @(desired.origin.y)];
            changed = YES;
        }
    }

    gCCAOccupiedPageCount = MAX((NSUInteger)1, highestPage + 1);
    gCCAPageCount = MIN(kCCAMaxPages, gCCAOccupiedPageCount + (gEditModeActive && gCCAOccupiedPageCount < kCCAMaxPages ? 1 : 0));
    if (gCCAPendingPageAfterRebuild != NSNotFound) {
        gCCACurrentPage = MIN(gCCAPendingPageAfterRebuild, gCCAPageCount - 1);
        gCCAPendingPageAfterRebuild = NSNotFound;
    } else {
        gCCACurrentPage = MIN(gCCACurrentPage, gCCAPageCount - 1);
    }
    if (changed) {
        CFPreferencesSetAppValue(CFSTR("ModuleGridOrigins"), (__bridge CFPropertyListRef)[gCCACustomOrigins copy], kCCAPrefsDomain);
        CFPreferencesAppSynchronize(kCCAPrefsDomain);
        UIViewController *collection = [self moduleCollectionControllerInOverlay:overlay];
        [collection.view setNeedsLayout];
    }
    [self updatePageIndicatorsForOverlay:overlay];
    [self layoutOwnedDuplicateModulesForOverlay:overlay];
}

- (void)setEditControlsSuppressedForPaging:(BOOL)suppressed overlay:(UIViewController *)overlay animated:(BOOL)animated {
    // Remove/resize chrome used to float on overlay.view, so paging had to
    // suppress it while pages slid underneath.  The chrome now lives with the
    // module wrapper (like the border), so hiding it during paging just creates
    // the old disappear/reappear flash. Keep the method as a compatibility
    // synchronization point for existing callers, but do not enter the global
    // suppression state.
    gCCAEditChromeSuppressedForPaging = NO;
    if (!overlay || !gEditModeActive) return;
    for (UIViewController *module in CCACollectModuleControllers(overlay)) {
        UIButton *remove = objc_getAssociatedObject(module.view, kCCARemoveButtonKey);
        UIButton *resize = objc_getAssociatedObject(module.view, kCCAResizeButtonKey);
        if (!remove.hidden) [remove.superview bringSubviewToFront:remove];
        if (!resize.hidden) [resize.superview bringSubviewToFront:resize];
    }
}

- (void)updatePagedModuleVisibilityForOverlay:(UIViewController *)overlay showAdjacent:(BOOL)showAdjacent {
    if (!overlay || gCCAExpandedModuleOpen) return;
    [self layoutOwnedDuplicateModulesForOverlay:overlay];
    for (UIViewController *module in CCACollectModuleControllers(overlay)) {
        NSString *identifier = CCAModuleIdentifier(module);
        NSValue *nativeValue = identifier.length ? gCCANativeLayoutRects[identifier] : nil;
        if (!nativeValue) continue;
        CCUILayoutRect rect = {};
        [nativeValue getValue:&rect];
        NSArray<NSNumber *> *origin = gCCACustomOrigins[identifier];
        if (origin.count >= 2) rect.origin = (CCUILayoutPoint){origin[0].unsignedIntegerValue, origin[1].unsignedIntegerValue};
        BOOL pageVisible = showAdjacent || CCAPageForRect(rect) == gCCACurrentPage;
        // Keep UIView visibility and layout entirely under Control Center's
        // ownership. Mutating alpha plus setNeedsLayout here fed back through
        // the private module layout hooks while edit chrome's display link was
        // active, eventually watchdog-stalling SpringBoard. Layer opacity is a
        // compositor-only page clip and does not invalidate module layout.
        BOOL activeDragSource = CCAIsActiveDragModuleIdentifier(identifier);
        BOOL pageHidden = (!pageVisible && !(gCCADragInProgress && module.view == gCCAActiveDragModuleView)) || activeDragSource;
        objc_setAssociatedObject(module.view, kCCAPageHiddenKey, @(pageHidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        module.view.layer.opacity = pageHidden ? 0.0f : 1.0f;
        [CATransaction commit];
        UIVisualEffectView *border = objc_getAssociatedObject(module.view, @selector(applyEditingToModule:editing:));
        UIButton *remove = objc_getAssociatedObject(module.view, kCCARemoveButtonKey);
        UIButton *resize = objc_getAssociatedObject(module.view, kCCAResizeButtonKey);
        if (!pageVisible || activeDragSource) {
            border.hidden = YES;
            border.alpha = 0.0;
            remove.hidden = YES;
            remove.alpha = 0.0;
            resize.hidden = YES;
            resize.alpha = 0.0;
        } else if (gEditModeActive) {
            border.hidden = !gModuleBordersEnabled;
            border.alpha = 1.0;
            remove.hidden = gCCAEditChromeSuppressedForPaging || !gRemovalButtonsEnabled;
            remove.alpha = gCCAEditChromeSuppressedForPaging ? 0.0 : 1.0;
            resize.hidden = gCCAEditChromeSuppressedForPaging || ![self moduleIdentifierSupportsResizing:identifier];
            resize.alpha = gCCAEditChromeSuppressedForPaging ? 0.0 : 1.0;
        }
    }
}

- (void)installTopFadeForOverlay:(UIViewController *)overlay {
    if (!overlay.view) return;
    UIViewController *collection = [self moduleCollectionControllerInOverlay:overlay];
    UIView *fade = [overlay.view viewWithTag:kCCATopFadeTag];
    if (!fade) {
        fade = [[CCATopFadeView alloc] initWithFrame:CGRectZero];
        fade.tag = kCCATopFadeTag;
        fade.userInteractionEnabled = NO;
        fade.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleBottomMargin;
        [overlay.view addSubview:fade];
    }
    if (collection.view && collection.view.superview == overlay.view) {
        [overlay.view insertSubview:fade aboveSubview:collection.view];
    }
    CGFloat height = MAX(112.0, overlay.view.safeAreaInsets.top + 76.0);
    fade.frame = CGRectMake(0.0, 0.0, CGRectGetWidth(overlay.view.bounds), height);
    BOOL active = gCCAControlCenterPresented && !gCCAExpandedModuleOpen &&
        (gCCAPagerScrubbingActive || gCCAPagerTransitionActive || fabs(gCCAPagerInteractiveTranslation) > 0.5);
    fade.hidden = !active;
    fade.alpha = active ? 1.0 : 0.0;

    UIView *quickAccess = [overlay.view viewWithTag:181000];
    if (quickAccess && !quickAccess.hidden) [overlay.view bringSubviewToFront:quickAccess];
    for (UIViewController *child in overlay.childViewControllers) {
        NSString *name = NSStringFromClass(child.class);
        if (([name containsString:@"SensorAttribution"] || [name containsString:@"HeaderPocket"]) && child.view) {
            [overlay.view bringSubviewToFront:child.view];
        }
    }
    for (UIView *subview in overlay.view.subviews) {
        NSString *name = NSStringFromClass(subview.class);
        if ([name containsString:@"HeaderPocket"]) [overlay.view bringSubviewToFront:subview];
    }
    UIView *pageIndicators = [overlay.view viewWithTag:kCCAPageIndicatorHostTag];
    if (pageIndicators && !pageIndicators.hidden) [overlay.view bringSubviewToFront:pageIndicators];
}

- (void)updateTopFadeForOverlay:(UIViewController *)overlay presentationAlpha:(CGFloat)alpha {
    UIView *fade = [overlay.view viewWithTag:kCCATopFadeTag];
    if (!fade) {
        [self installTopFadeForOverlay:overlay];
        fade = [overlay.view viewWithTag:kCCATopFadeTag];
    }
    if (!fade) return;
    BOOL active = !gCCAExpandedModuleOpen &&
        (gCCAPagerScrubbingActive || gCCAPagerTransitionActive || fabs(gCCAPagerInteractiveTranslation) > 0.5);
    CGFloat target = active ? MIN(1.0, MAX(0.0, alpha)) : 0.0;
    fade.hidden = target <= 0.001;
    fade.alpha = target;
    CGFloat height = MAX(112.0, overlay.view.safeAreaInsets.top + 76.0);
    fade.frame = CGRectMake(0.0, 0.0, CGRectGetWidth(overlay.view.bounds), height);
}

- (void)updateOwnedDuplicateHostForOverlay:(UIViewController *)overlay presentationAlpha:(CGFloat)alpha {
    if (!overlay.view) return;
    UIView *host = [overlay.view viewWithTag:kCCAOwnedDuplicateHostTag];
    if (!host) return;
    CGFloat clamped = MIN(1.0, MAX(0.0, alpha));
    BOOL hidden = clamped <= 0.001 || (gCCAExpandedModuleOpen && !gCCAExpandedModuleClosingActive);
    if (hidden) {
        host.hidden = YES;
        if (gCCAExpandedModuleOpen || clamped <= 0.001) host.alpha = 0.0;
        host.transform = CGAffineTransformIdentity;
        for (UIViewController *child in overlay.childViewControllers) {
            if (![child isKindOfClass:[CCAOwnedDuplicateModuleViewController class]]) continue;
            UIView *container = objc_getAssociatedObject(child, kCCAOwnedDuplicateContainerKey);
            UIView *presentation = objc_getAssociatedObject(child, kCCAOwnedDuplicatePresentationKey);
            container.transform = CGAffineTransformIdentity;
            presentation.transform = CGAffineTransformIdentity;
            presentation.layer.opacity = 0.0;
        }
        return;
    }
    host.hidden = NO;
    host.alpha = 1.0;
    host.layer.opacity = 1.0;
    host.transform = gCCAUseNativeOpeningCompensation ?
        CGAffineTransformMakeTranslation(0.0, CCANativeScrollOpeningCompensation(overlay)) :
        CGAffineTransformIdentity;

    NSArray<UIViewController *> *modules = CCACollectModuleControllers(overlay);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (UIViewController *child in overlay.childViewControllers) {
        if (![child isKindOfClass:[CCAOwnedDuplicateModuleViewController class]]) continue;
        CCAOwnedDuplicateModuleViewController *duplicate = (CCAOwnedDuplicateModuleViewController *)child;
        UIView *duplicateContainer = objc_getAssociatedObject(child, kCCAOwnedDuplicateContainerKey);
        UIView *duplicatePresentation = objc_getAssociatedObject(child, kCCAOwnedDuplicatePresentationKey);
        if (!duplicateContainer || !duplicatePresentation) continue;

        UIViewController *source = nil;
        for (UIViewController *candidate in modules) {
            if (CCAIsOwnedDuplicateModuleController(candidate)) continue;
            if ([CCAModuleIdentifier(candidate) isEqualToString:duplicate.baseModuleIdentifier]) {
                source = candidate;
                break;
            }
        }
        if (!source) {
            for (UIViewController *candidate in modules) {
                if (CCAIsOwnedDuplicateModuleController(candidate) || candidate.view.hidden ||
                    candidate.view.alpha <= 0.01 || CCAModuleViewIsPageHidden(candidate.view)) continue;
                source = candidate;
                break;
            }
        }

        UIView *sourcePresentation = CCAPresentationWrapperForModuleController(source);
        UIView *sourceContainer = sourcePresentation.superview;
        CALayer *sourcePresentationLayer = (CALayer *)sourcePresentation.layer.presentationLayer;
        CALayer *sourceContainerLayer = (CALayer *)sourceContainer.layer.presentationLayer;
        if (sourcePresentationLayer && sourceContainerLayer) {
            duplicateContainer.transform = sourceContainerLayer.affineTransform;
            duplicatePresentation.transform = sourcePresentationLayer.affineTransform;
            duplicatePresentation.layer.opacity = sourcePresentationLayer.opacity;
        } else {
            CGFloat scale = 0.80 + 0.20 * clamped;
            duplicateContainer.transform = CGAffineTransformMakeTranslation(0.0, -70.0 * (1.0 - clamped));
            duplicatePresentation.transform = CGAffineTransformMakeScale(scale, scale);
            duplicatePresentation.layer.opacity = clamped;
        }
        child.view.alpha = 1.0;
        child.view.layer.opacity = 1.0;
    }
    [CATransaction commit];
}

- (void)animateOwnedDuplicateHostForOverlay:(UIViewController *)overlay presented:(BOOL)presented {
    if (!overlay.view) return;
    UIView *host = [overlay.view viewWithTag:kCCAOwnedDuplicateHostTag];
    if (!host) return;
    gCCAOwnedDuplicateHostSyncPresented = presented;
    if (gCCAExpandedModuleOpen && !gCCAExpandedModuleClosingActive) {
        host.hidden = YES;
        host.alpha = 0.0;
        host.transform = CGAffineTransformIdentity;
        return;
    }
    if (presented) {
        host.hidden = NO;
        if (host.alpha <= 0.001) host.alpha = 0.0;
    }
    if (gCCAOwnedDuplicateHostDisplayLink) {
        return;
    }
    CGFloat targetOpacity = presented ? 1.0 : 0.0;
    CGAffineTransform targetContainerTransform = presented ? CGAffineTransformIdentity : CGAffineTransformMakeTranslation(0.0, -70.0);
    CGAffineTransform targetPresentationTransform = presented ? CGAffineTransformIdentity : CGAffineTransformMakeScale(0.80, 0.80);
    NSTimeInterval duration = presented ? 0.20 : 0.18;
    [UIView animateWithDuration:duration
                          delay:0.0
                        options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        for (UIViewController *child in overlay.childViewControllers) {
            if (![child isKindOfClass:[CCAOwnedDuplicateModuleViewController class]]) continue;
            UIView *container = objc_getAssociatedObject(child, kCCAOwnedDuplicateContainerKey);
            UIView *presentation = objc_getAssociatedObject(child, kCCAOwnedDuplicatePresentationKey);
            container.transform = targetContainerTransform;
            presentation.transform = targetPresentationTransform;
            presentation.layer.opacity = targetOpacity;
        }
    } completion:^(__unused BOOL finished) {
        if (!presented && !gCCAControlCenterPresented && !gCCAOwnedDuplicateHostDisplayLink) {
            host.hidden = YES;
        }
    }];
}

- (void)beginOwnedDuplicateHostPresentationSync {
    gCCAOwnedDuplicateHostSyncUntil = CACurrentMediaTime() + 0.85;
    if (!gCCAOwnedDuplicateHostDisplayLink) {
        gCCAOwnedDuplicateHostDisplayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(ownedDuplicateHostDisplayLinkFired:)];
        [gCCAOwnedDuplicateHostDisplayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    }
}

- (void)ownedDuplicateHostDisplayLinkFired:(__unused CADisplayLink *)displayLink {
    BOOL presentationTransitionActive = gCCAControlCenterPresentationState == 1 ||
                                        gCCAControlCenterPresentationState == 3;
    for (UIViewController *overlay in gOverlayControllers.allObjects) {
        if (!overlay.view.window) continue;
        [self updateOwnedDuplicateHostForOverlay:overlay presentationAlpha:1.0];
        if (gCCAUseNativeOpeningCompensation &&
            (gCCAControlCenterPresentationState == 1 || gCCAControlCenterPresentationState == 2) &&
            fabs(CCANativeScrollOpeningCompensation(overlay)) <= 0.5) {
            CCAFinishNativeScrollOpeningStabilization(overlay);
        }

    }
    if (gCCAUseNativeOpeningCompensation &&
        (gCCAControlCenterPresentationState == 1 || gCCAControlCenterPresentationState == 2)) {
        // The native scroll presentation bounds and our inverse sublayer
        // offset must reach the render server in the same frame. Letting the
        // latter wait for the run-loop's normal commit leaves a one-frame
        // mismatch precisely when CCUI drops its opening bounds animation.
        [CATransaction flush];
    }

    if (presentationTransitionActive) gCCAOwnedDuplicateHostSyncUntil = CACurrentMediaTime() + 0.10;
    if (CACurrentMediaTime() > gCCAOwnedDuplicateHostSyncUntil) {
        [gCCAOwnedDuplicateHostDisplayLink invalidate];
        gCCAOwnedDuplicateHostDisplayLink = nil;
        if (!gCCAOwnedDuplicateHostSyncPresented && !gCCAControlCenterPresented) {
            for (UIViewController *overlay in gOverlayControllers.allObjects) {
                UIView *host = [overlay.view viewWithTag:kCCAOwnedDuplicateHostTag];
                if (!host) continue;
                host.hidden = YES;
                host.alpha = 0.0;
                host.transform = CGAffineTransformIdentity;
            }
        }
    }
}

- (void)settlePagedModuleVisibilityForOverlay:(UIViewController *)overlay animated:(BOOL)animated token:(id)token {
    if (!overlay || gCCAExpandedModuleOpen) return;
    NSTimeInterval duration = animated ? (gEditModeActive ? 0.12 : 0.07) : 0.0;
    for (UIViewController *module in CCACollectModuleControllers(overlay)) {
        NSString *identifier = CCAModuleIdentifier(module);
        NSValue *nativeValue = identifier.length ? gCCANativeLayoutRects[identifier] : nil;
        if (!nativeValue) continue;
        CCUILayoutRect rect = {};
        [nativeValue getValue:&rect];
        NSArray<NSNumber *> *origin = gCCACustomOrigins[identifier];
        if (origin.count >= 2) rect.origin = (CCUILayoutPoint){origin[0].unsignedIntegerValue, origin[1].unsignedIntegerValue};
        BOOL selected = CCAPageForRect(rect) == gCCACurrentPage;
        UIVisualEffectView *border = objc_getAssociatedObject(module.view, @selector(applyEditingToModule:editing:));
        UIButton *remove = objc_getAssociatedObject(module.view, kCCARemoveButtonKey);
        UIButton *resize = objc_getAssociatedObject(module.view, kCCAResizeButtonKey);

        objc_setAssociatedObject(module.view, kCCAPageHiddenKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (gEditModeActive) {
            border.hidden = selected ? !gModuleBordersEnabled : NO;
            remove.hidden = gCCAEditChromeSuppressedForPaging || (selected ? !gRemovalButtonsEnabled : NO);
            resize.hidden = gCCAEditChromeSuppressedForPaging || (selected ? ![self moduleIdentifierSupportsResizing:identifier] : NO);
        } else {
            border.hidden = YES;
            remove.hidden = YES;
            resize.hidden = YES;
        }
        [border.layer removeAnimationForKey:@"CCAsterBreathing"];

        float targetOpacity = selected ? 1.0f : 0.0f;
        if (animated) {
            float startingOpacity = module.view.layer.presentationLayer ? ((CALayer *)module.view.layer.presentationLayer).opacity : module.view.layer.opacity;
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            module.view.layer.opacity = targetOpacity;
            [CATransaction commit];
            CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
            fade.fromValue = @(startingOpacity);
            fade.toValue = @(targetOpacity);
            fade.duration = duration;
            fade.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
            [module.view.layer addAnimation:fade forKey:@"CCAsterPageSettleFade"];
            [UIView animateWithDuration:duration delay:0.0 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState animations:^{
                border.alpha = gEditModeActive && selected ? 1.0 : 0.0;
                remove.alpha = gEditModeActive && selected && !gCCAEditChromeSuppressedForPaging ? 1.0 : 0.0;
                resize.alpha = gEditModeActive && selected && !gCCAEditChromeSuppressedForPaging ? 1.0 : 0.0;
            } completion:nil];
        } else {
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            module.view.layer.opacity = targetOpacity;
            [CATransaction commit];
            border.alpha = gEditModeActive && selected ? 1.0 : 0.0;
            remove.alpha = gEditModeActive && selected && !gCCAEditChromeSuppressedForPaging ? 1.0 : 0.0;
            resize.alpha = gEditModeActive && selected && !gCCAEditChromeSuppressedForPaging ? 1.0 : 0.0;
        }
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (token && objc_getAssociatedObject(overlay, kCCAPageAnimationTokenKey) != token) return;
        [self updatePagedModuleVisibilityForOverlay:overlay showAdjacent:NO];
        if (gEditModeActive) {
            for (UIViewController *module in CCACollectModuleControllers(overlay)) {
                NSString *identifier = CCAModuleIdentifier(module);
                NSValue *nativeValue = identifier.length ? gCCANativeLayoutRects[identifier] : nil;
                if (!nativeValue) continue;
                CCUILayoutRect rect = {};
                [nativeValue getValue:&rect];
                NSArray<NSNumber *> *origin = gCCACustomOrigins[identifier];
                if (origin.count >= 2) rect.origin = (CCUILayoutPoint){origin[0].unsignedIntegerValue, origin[1].unsignedIntegerValue};
                if (CCAPageForRect(rect) == gCCACurrentPage) [self applyEditingToModule:module editing:YES];
            }
            // applyEditingToModule owns creation/configuration and therefore
            // briefly restores alpha. Re-apply the page clip before revealing
            // only the destination page's overlay controls.
            [self updatePagedModuleVisibilityForOverlay:overlay showAdjacent:NO];
            [self updateEditControlFramesForOverlay:overlay];
            [self setEditControlsSuppressedForPaging:NO overlay:overlay animated:YES];
        }
    });
}

- (void)applyPageTransformToOverlay:(UIViewController *)overlay animated:(BOOL)animated {
    UIViewController *collection = [self moduleCollectionControllerInOverlay:overlay];
    if (!collection.view) return;
    if (gCCAPagerScrubbingActive) {
        NSValue *boundsValue = objc_getAssociatedObject(collection.view, kCCAScrubCollectionBoundsKey);
        NSValue *positionValue = objc_getAssociatedObject(collection.view, kCCAScrubCollectionPositionKey);
        if (boundsValue && positionValue) {
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            collection.view.layer.bounds = boundsValue.CGRectValue;
            collection.view.layer.position = positionValue.CGPointValue;
            [CATransaction commit];
        }
    }
    BOOL atomicPresentationReconcile = !animated &&
        !gCCAPagerTransitionActive &&
        !gCCAPagerScrubbingActive &&
        fabs(gCCAPagerInteractiveTranslation) < 0.01 &&
        (gCCAControlCenterPresentationState == 0 || gCCAControlCenterPresentationState == 2);
    if (atomicPresentationReconcile) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
    }
    [self layoutOwnedDuplicateModulesForOverlay:overlay];
    CCARestoreNativeScrollBaseline(overlay);
    if (gCCAUseNativeOpeningCompensation) CCAStabilizeNativeScrollPresentationForOverlay(overlay);
    [self capturePresentationStateForView:collection.view];
    CGAffineTransform base = [objc_getAssociatedObject(collection.view, kCCAOriginalTransformKey) CGAffineTransformValue];
    CATransform3D sublayerBase = [objc_getAssociatedObject(collection.view, kCCAOriginalSublayerTransformKey) CATransform3DValue];
    CGFloat editOffset = gEditModeActive ? 0.0 : kCCARestingModuleOffset;
    CGFloat pageOffset = -(CGFloat)gCCACurrentPage * CCAVisualPageSpan() + gCCAPagerInteractiveTranslation;
    // While a module is expanded, CCUI's expand/collapse animation reads the
    // module's frame in window coordinates. UIView coordinate conversion honors
    // view.transform but NOT layer.sublayerTransform, so if the page offset
    // lives on the sublayer the module reports its untranslated model row (a
    // full page below the screen) and the platter flies to/from off the bottom.
    // Carry the page offset on the view transform (and neutralise the sublayer)
    // for the duration of the expansion so the source frame is correct. This
    // matches CCAApplyExpansionPageGeometrySync and stops overriding it.
    BOOL flattenForExpansion = gCCAExpandedModuleOpen && !gEditModeActive && !gCCAPagerScrubbingActive;
    CGFloat viewTransformOffset = editOffset + (flattenForExpansion ? pageOffset : 0.0);
    CATransform3D targetSublayerTransform = flattenForExpansion ? sublayerBase : CATransform3DTranslate(sublayerBase, 0.0, pageOffset, 0.0);
    void (^changes)(void) = ^{
        // Keep page motion on one compositor property in both presentation
        // modes. Moving it between UIView.transform at rest and
        // sublayerTransform while editing allowed CCUI's edit-exit layout to
        // preserve one side of the handoff and either lose or double the page
        // offset. The view transform now owns only the small chrome spacing.
        collection.view.layer.transform = CATransform3DIdentity;
        if (gCCAPagerScrubbingActive) {
            CGPoint overlayCenter = CGPointMake(CGRectGetMidX(overlay.view.bounds), CGRectGetMidY(overlay.view.bounds));
            CGPoint collectionCenterInOverlay = [collection.view.superview convertPoint:collection.view.center toView:overlay.view];
            CGFloat scaleX = gCCAPagerHeldScale * gCCAPagerJelloScaleX;
            CGFloat scaleY = gCCAPagerHeldScale * gCCAPagerJelloScaleY;
            CGFloat compensationX = (overlayCenter.x - collectionCenterInOverlay.x) * (1.0 - scaleX);
            CGFloat compensationY = (overlayCenter.y - collectionCenterInOverlay.y) * (1.0 - scaleY);
            CGAffineTransform heldTransform = CGAffineTransformTranslate(base, compensationX,
                                                                          editOffset + compensationY);
            collection.view.transform = CGAffineTransformScale(heldTransform, scaleX, scaleY);
        } else {
            collection.view.transform = CGAffineTransformTranslate(base, 0.0, viewTransformOffset);
        }
        collection.view.layer.sublayerTransform = targetSublayerTransform;
        [self layoutOwnedDuplicateModulesForOverlay:overlay];
        [self updateEditPageGridTransformsForOverlay:overlay];
    };
    if (animated) {
        id token = [NSObject new];
        objc_setAssociatedObject(overlay, kCCAPageAnimationTokenKey, token, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        NSTimeInterval duration = 0.52;
        CATransform3D fromSublayerTransform = (gEditModeActive && gCCAPagerTransitionActive) ?
            collection.view.layer.sublayerTransform :
            (collection.view.layer.presentationLayer ? ((CALayer *)collection.view.layer.presentationLayer).sublayerTransform : collection.view.layer.sublayerTransform);
        [collection.view.layer removeAnimationForKey:@"CCAsterPageStackSlide"];
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        changes();
        [CATransaction commit];
        CABasicAnimation *slide = [CABasicAnimation animationWithKeyPath:@"sublayerTransform"];
        slide.fromValue = [NSValue valueWithCATransform3D:fromSublayerTransform];
        slide.toValue = [NSValue valueWithCATransform3D:targetSublayerTransform];
        slide.duration = duration;
        slide.timingFunction = [CAMediaTimingFunction functionWithControlPoints:0.18 :0.88 :0.20 :1.0];
        [collection.view.layer addAnimation:slide forKey:@"CCAsterPageStackSlide"];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (objc_getAssociatedObject(overlay, kCCAPageAnimationTokenKey) != token) return;
            gCCAPagerTransitionActive = NO;
            [self layoutOwnedDuplicateModulesForOverlay:overlay];
            [self settlePagedModuleVisibilityForOverlay:overlay animated:gEditModeActive token:token];
            [self updateTopFadeForOverlay:overlay presentationAlpha:0.0];
            if (gEditModeActive) {
                [self prepareGridForOverlay:overlay collection:collection];
                [self updateEditControlFramesForOverlay:overlay];
                CCAEditTouchShield *shield = (CCAEditTouchShield *)[overlay.view viewWithTag:kCCAEditTouchShieldTag];
                UIButton *addControl = (UIButton *)[overlay.view viewWithTag:kCCAAddControlButtonTag];
                if (shield) [overlay.view bringSubviewToFront:shield];
                if (addControl) [overlay.view bringSubviewToFront:addControl];
                for (UIViewController *module in CCACollectModuleControllers(overlay)) {
                    UIButton *remove = objc_getAssociatedObject(module.view, kCCARemoveButtonKey);
                    UIButton *resize = objc_getAssociatedObject(module.view, kCCAResizeButtonKey);
                    if (remove && !remove.hidden) [remove.superview bringSubviewToFront:remove];
                    if (resize && !resize.hidden) [resize.superview bringSubviewToFront:resize];
                }
                UIView *pageIndicators = [overlay.view viewWithTag:kCCAPageIndicatorHostTag];
                if (pageIndicators && !pageIndicators.hidden) [overlay.view bringSubviewToFront:pageIndicators];
            }
        });
    } else {
        [collection.view.layer removeAnimationForKey:@"CCAsterPageStackSlide"];
        if (!atomicPresentationReconcile) {
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
        }
        changes();
        [CATransaction commit];
        if (!gCCAPagerTransitionActive && fabs(gCCAPagerInteractiveTranslation) < 0.01) [self updatePagedModuleVisibilityForOverlay:overlay showAdjacent:NO];
    }
}

- (void)animatePageSettleForOverlay:(UIViewController *)overlay
                          duration:(NSTimeInterval)duration
                    timingFunction:(CAMediaTimingFunction *)timingFunction
                      modelChanges:(dispatch_block_t)modelChanges
                        completion:(dispatch_block_t)completion {
    UIViewController *collection = [self moduleCollectionControllerInOverlay:overlay];
    if (!collection.view) {
        if (modelChanges) modelChanges();
        if (completion) completion();
        return;
    }

    NSMutableArray<CALayer *> *layers = [NSMutableArray arrayWithObject:collection.view.layer];
    UIView *gridStack = objc_getAssociatedObject(overlay, kCCAEditGridStackKey);
    if (gridStack.layer) [layers addObject:gridStack.layer];

    NSMutableArray<NSDictionary *> *starts = [NSMutableArray arrayWithCapacity:layers.count];
    for (CALayer *layer in layers) {
        CALayer *presentation = (CALayer *)layer.presentationLayer;
        CALayer *visible = presentation ?: layer;
        [starts addObject:@{
            @"transform": [NSValue valueWithCATransform3D:visible.transform],
            @"sublayerTransform": [NSValue valueWithCATransform3D:visible.sublayerTransform],
            @"bounds": [NSValue valueWithCGRect:visible.bounds],
            @"opacity": @(visible.opacity)
        }];
        [layer removeAnimationForKey:@"CCAsterPageSettleTransform"];
        [layer removeAnimationForKey:@"CCAsterPageSettleSublayerTransform"];
        [layer removeAnimationForKey:@"CCAsterPageSettleBounds"];
        [layer removeAnimationForKey:@"CCAsterPageSettleOpacity"];
    }

    if (modelChanges) modelChanges();

    CAMediaTimingFunction *curve = timingFunction ?: [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
    [layers enumerateObjectsUsingBlock:^(CALayer *layer, NSUInteger index, __unused BOOL *stop) {
        NSDictionary *start = starts[index];
        CABasicAnimation *transform = [CABasicAnimation animationWithKeyPath:@"transform"];
        transform.fromValue = start[@"transform"];
        transform.toValue = [NSValue valueWithCATransform3D:layer.transform];
        transform.duration = duration;
        transform.timingFunction = curve;
        [layer addAnimation:transform forKey:@"CCAsterPageSettleTransform"];

        CABasicAnimation *sublayerTransform = [CABasicAnimation animationWithKeyPath:@"sublayerTransform"];
        sublayerTransform.fromValue = start[@"sublayerTransform"];
        sublayerTransform.toValue = [NSValue valueWithCATransform3D:layer.sublayerTransform];
        sublayerTransform.duration = duration;
        sublayerTransform.timingFunction = curve;
        [layer addAnimation:sublayerTransform forKey:@"CCAsterPageSettleSublayerTransform"];

        CABasicAnimation *bounds = [CABasicAnimation animationWithKeyPath:@"bounds"];
        bounds.fromValue = start[@"bounds"];
        bounds.toValue = [NSValue valueWithCGRect:layer.bounds];
        bounds.duration = duration;
        bounds.timingFunction = curve;
        [layer addAnimation:bounds forKey:@"CCAsterPageSettleBounds"];

        CABasicAnimation *opacity = [CABasicAnimation animationWithKeyPath:@"opacity"];
        opacity.fromValue = start[@"opacity"];
        opacity.toValue = @(layer.opacity);
        opacity.duration = duration;
        opacity.timingFunction = curve;
        [layer addAnimation:opacity forKey:@"CCAsterPageSettleOpacity"];
    }];

    id token = [NSObject new];
    objc_setAssociatedObject(overlay, kCCAPageAnimationTokenKey, token, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (objc_getAssociatedObject(overlay, kCCAPageAnimationTokenKey) != token) return;
        for (CALayer *layer in layers) {
            [layer removeAnimationForKey:@"CCAsterPageSettleTransform"];
            [layer removeAnimationForKey:@"CCAsterPageSettleSublayerTransform"];
            [layer removeAnimationForKey:@"CCAsterPageSettleBounds"];
            [layer removeAnimationForKey:@"CCAsterPageSettleOpacity"];
        }
        if (completion) completion();
    });
}

- (void)setCurrentPage:(NSUInteger)page forOverlay:(UIViewController *)overlay animated:(BOOL)animated {
    if (!overlay || !gCCAPageCount) return;
    if (!gPagingEnabled) {
        page = 0;
        animated = NO;
    }
    gCCAPagerScrubbingActive = NO;
    if (animated) {
        gCCAPagerTransitionActive = YES;
        if (gEditModeActive) [self setEditControlsSuppressedForPaging:YES overlay:overlay animated:YES];
        [self updatePagedModuleVisibilityForOverlay:overlay showAdjacent:YES];
    } else {
        gCCAPagerTransitionActive = NO;
    }
    gCCAPagerHeldScale = 1.0;
    gCCAPagerHeldAlphaFactor = 1.0;
    gCCAPagerJelloScaleX = 1.0;
    gCCAPagerJelloScaleY = 1.0;
    gCCACurrentPage = MIN(page, gCCAPageCount - 1);
    gCCAPagerInteractiveTranslation = 0.0;
    [self updatePageIndicatorsForOverlay:overlay];
    [self applyPageTransformToOverlay:overlay animated:animated];
    if (gPagingEnabled && gCCAControlCenterPresented && gCCAControlCenterPresentationState == 2) {
        for (NSNumber *delay in @[@0.0, @0.12, @0.42]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (!gPagingEnabled || !gCCAControlCenterPresented ||
                    gCCAControlCenterPresentationState != 2 ||
                    fabs(gCCAPagerInteractiveTranslation) >= 0.01) return;
                CCARestoreNativeScrollBaseline(overlay);
            });
        }
    }
}

- (void)pageIndicatorTapped:(UIButton *)sender {
    UIViewController *overlay = gOverlayControllers.allObjects.firstObject;
    NSNumber *page = objc_getAssociatedObject(sender, @selector(pageIndicatorTapped:));
    if (!gPagingEnabled || !overlay || !page || gCCAExpandedModuleOpen) return;
    UIView *host = [overlay.view viewWithTag:kCCAPageIndicatorHostTag];
    if ([objc_getAssociatedObject(host, kCCAPageIndicatorDraggingKey) boolValue]) return;
    CCAHaptic();
    if (gCCAPagerScrubbingActive || gCCAPagerTransitionActive) {
        [self updateInteractivePageTransitionForOverlay:overlay
                                               progress:(CGFloat)page.unsignedIntegerValue
                                                 touchY:CGRectGetMidY(sender.frame)];
        [self finishInteractivePageTransitionForOverlay:overlay targetPage:page.unsignedIntegerValue];
    } else {
        [self setCurrentPage:page.unsignedIntegerValue forOverlay:overlay animated:YES];
    }
}

- (void)pageIndicatorTouchDown:(UIButton *)sender {
    UIViewController *overlay = gOverlayControllers.allObjects.firstObject;
    NSNumber *page = objc_getAssociatedObject(sender, @selector(pageIndicatorTapped:));
    if (!gPagingEnabled || !overlay || !page || gCCAExpandedModuleOpen || gCCAPagerTransitionActive) return;
    if (gEditModeActive) return;
    CCAReassertNativeScrollClampForOverlay(overlay);
    [self beginInteractivePageTransitionForOverlay:overlay startPage:gCCACurrentPage];
    [self updateInteractivePageTransitionForOverlay:overlay
                                           progress:(CGFloat)page.unsignedIntegerValue
                                             touchY:CGRectGetMidY(sender.frame)];
}

- (void)beginInteractivePageTransitionForOverlay:(UIViewController *)overlay startPage:(NSUInteger)startPage {
    if (!gPagingEnabled || !overlay || gCCAPageCount <= 1 || gCCAPagerTransitionActive) return;
    gCCAPagerTransitionActive = YES;
    gCCAPagerInteractiveStartPage = MIN(startPage, gCCAPageCount - 1);
    gCCAPagerInteractiveProgress = gCCAPagerInteractiveStartPage;
    gCCACurrentPage = gCCAPagerInteractiveStartPage;
    gCCAPagerInteractiveTranslation = 0.0;
    gCCAPagerInteractiveBeganTime = CACurrentMediaTime();
    gCCAPagerScrubbingActive = YES;
    gCCAPagerHeldScale = 1.0;
    gCCAPagerHeldAlphaFactor = 1.0;
    gCCAPagerViscousProgress = (CGFloat)gCCAPagerInteractiveStartPage;
    gCCAPagerPreviousRawProgress = (CGFloat)gCCAPagerInteractiveStartPage;
    gCCAPagerFilteredVelocity = 0.0;
    gCCAPagerJelloScaleX = 1.0;
    gCCAPagerJelloScaleY = 1.0;
    gCCAPagerLastSampleTime = CACurrentMediaTime();
    CCAReassertNativeScrollClampForOverlay(overlay);
    if (gEditModeActive) [self setEditControlsSuppressedForPaging:YES overlay:overlay animated:YES];
    UIView *host = [overlay.view viewWithTag:kCCAPageIndicatorHostTag];
    [host.layer removeAllAnimations];
    for (UIView *button in host.subviews) {
        [button.layer removeAllAnimations];
        button.transform = CGAffineTransformIdentity;
    }
    [self updateTopFadeForOverlay:overlay presentationAlpha:1.0];
    [self setHeaderChromeHiddenForScrubbing:YES overlay:overlay animated:YES];
    // Scrubbing is a discrete page picker, not a scrolling stack. Keep only
    // the selected page composited; crossing an indicator swaps that page in
    // place through the pop animation below.
    [self updatePagedModuleVisibilityForOverlay:overlay showAdjacent:NO];

    UIViewController *collection = [self moduleCollectionControllerInOverlay:overlay];
    [self capturePresentationStateForView:collection.view];
    if (collection.view) {
        objc_setAssociatedObject(collection.view, kCCAScrubCollectionBoundsKey,
                                 [NSValue valueWithCGRect:collection.view.layer.bounds],
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(collection.view, kCCAScrubCollectionPositionKey,
                                 [NSValue valueWithCGPoint:collection.view.layer.position],
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (gEditModeActive) {
        NSMutableSet<NSValue *> *seenWrappers = [NSMutableSet set];
        for (UIViewController *module in CCACollectModuleControllers(overlay)) {
            UIView *wrapper = module.view.superview;
            if (!wrapper || wrapper == collection.view) continue;
            NSValue *key = [NSValue valueWithNonretainedObject:wrapper];
            if ([seenWrappers containsObject:key]) continue;
            [seenWrappers addObject:key];
            [wrapper.layer removeAllAnimations];
            objc_setAssociatedObject(wrapper,
                                     kCCAEditScrubWrapperBaseTransformKey,
                                     [NSValue valueWithCGAffineTransform:wrapper.transform],
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
}

- (void)updateInteractivePageTransitionForOverlay:(UIViewController *)overlay progress:(CGFloat)progress touchY:(CGFloat)touchY {
    if (!overlay || !gCCAPagerTransitionActive) return;
    CCAClampNativeScrollViewForOverlay(overlay);
    CGFloat maxProgress = (CGFloat)gCCAPageCount - 1.0;
    CGFloat clamped = MIN(maxProgress, MAX(0.0, progress));
    // Selection is bounded, while physics is allowed to continue past either
    // endpoint through a logarithmic resistance curve. This keeps viscosity
    // and jello alive above the first icon and below the last without letting
    // an extreme pull accumulate an enormous delayed catch-up distance.
    CGFloat physicsProgress = progress;
    if (progress < 0.0) physicsProgress = -log1p(-progress);
    else if (progress > maxProgress) physicsProgress = maxProgress + log1p(progress - maxProgress);
    NSUInteger previousCandidate = gCCACurrentPage;

    CFTimeInterval now = CACurrentMediaTime();
    CGFloat dt = gCCAPagerLastSampleTime > 0.0 ? (CGFloat)(now - gCCAPagerLastSampleTime) : (1.0 / 60.0);
    dt = MIN(0.050, MAX(1.0 / 120.0, dt));
    CGFloat rawVelocity = (physicsProgress - gCCAPagerPreviousRawProgress) / dt;
    rawVelocity = MIN(8.0, MAX(-8.0, rawVelocity));
    CGFloat velocityResponse = 1.0 - exp(-dt * kCCAPagerJelloVelocityResponse);
    gCCAPagerFilteredVelocity += (rawVelocity - gCCAPagerFilteredVelocity) * velocityResponse;
    // Keep the icons under the finger, but let the visible page trail the raw
    // scrub position by a few frames. Filtering the full progress (rather than
    // only its within-page offset) carries the glue feeling cleanly across a
    // page threshold as well.
    CGFloat dragResponse = 1.0 - exp(-dt * kCCAPagerViscosityResponse);
    gCCAPagerViscousProgress += (physicsProgress - gCCAPagerViscousProgress) * dragResponse;
    CGFloat visualProgress = gCCAPagerViscousProgress;
    NSUInteger candidate = (NSUInteger)llround(MIN(maxProgress, MAX(0.0, visualProgress)));
    BOOL changedPage = candidate != previousCandidate;
    if (changedPage) CCAHaptic();
    CGFloat pageTension = physicsProgress - visualProgress;
    gCCAPagerPreviousRawProgress = physicsProgress;
    gCCAPagerLastSampleTime = now;
    gCCAPagerInteractiveProgress = clamped;
    gCCACurrentPage = candidate;
    // Keep the selected page centered. A small opposing parallax (at most
    // roughly half a module gap) preserves the feeling that the finger is
    // still pulling without exposing an adjacent page.
    CGFloat overlayHeight = CGRectGetHeight(overlay.view.bounds);
    CGFloat scrubHostHeight = kCCAPageIndicatorScrubStep * gCCAPageCount;
    CGFloat scrubHostMinY = floor((overlayHeight - scrubHostHeight) * 0.5);
    CGFloat fingerY = scrubHostMinY + touchY;
    CGFloat translationTarget = 0.0;
    BOOL endpointPull = NO;
    if (progress < 0.0) {
        CGFloat firstIconY = scrubHostMinY + kCCAPageIndicatorScrubStep * 0.5;
        CGFloat upperLimitY = overlayHeight * 0.10;
        CGFloat pull = MIN(1.0, MAX(0.0, (firstIconY - fingerY) / MAX(1.0, firstIconY - upperLimitY)));
        CGFloat eased = 1.0 - pow(1.0 - pull, 1.35);
        translationTarget = -MIN(100.0, overlayHeight * 0.12) * eased;
        endpointPull = YES;
    } else if (progress > maxProgress) {
        CGFloat lastIconY = scrubHostMinY + ((CGFloat)gCCAPageCount - 0.5) * kCCAPageIndicatorScrubStep;
        CGFloat lowerLimitY = overlayHeight * 0.90;
        CGFloat pull = MIN(1.0, MAX(0.0, (fingerY - lastIconY) / MAX(1.0, lowerLimitY - lastIconY)));
        CGFloat eased = 1.0 - pow(1.0 - pull, 1.35);
        translationTarget = MIN(100.0, overlayHeight * 0.12) * eased;
        endpointPull = YES;
    } else {
        translationTarget = (visualProgress - (CGFloat)candidate) * 22.0;
    }
    if (endpointPull) {
        gCCAPagerInteractiveTranslation += (translationTarget - gCCAPagerInteractiveTranslation) * dragResponse;
    } else {
        gCCAPagerInteractiveTranslation = translationTarget;
    }
    // Ease the whole page inward around the collection's center as the scrub
    // handoff begins. Reapplying this after the page translation keeps the
    // interactive paging coordinate system unchanged while giving the held
    // page the compact, suspended iOS 18 presentation.
    CGFloat entrance = gCCAPagerInteractiveBeganTime > 0.0 ?
        MIN(1.0, MAX(0.0, (CACurrentMediaTime() - gCCAPagerInteractiveBeganTime) / 0.26)) : 1.0;
    entrance = entrance * entrance * entrance * (entrance * (entrance * 6.0 - 15.0) + 10.0);
    CGFloat heldScale = 1.0 - 0.30 * entrance;
    gCCAPagerHeldScale = heldScale;
    gCCAPagerHeldAlphaFactor = 1.0 - 0.30 * entrance;
    CGFloat jelloInput = gCCAPagerFilteredVelocity * kCCAPagerJelloVelocityToScale +
                         pageTension * kCCAPagerJelloTensionToScale;
    CGFloat jello = MIN(kCCAPagerMaximumJelloScale,
                        MAX(-kCCAPagerMaximumJelloScale, jelloInput)) * entrance;
    gCCAPagerJelloScaleX = 1.0 - jello * 0.42;
    gCCAPagerJelloScaleY = 1.0 + jello;
    [self applyPageTransformToOverlay:overlay animated:NO];
    if (changedPage) [self updatePagedModuleVisibilityForOverlay:overlay showAdjacent:NO];

    UIViewController *collection = [self moduleCollectionControllerInOverlay:overlay];
    CGFloat baseAlpha = [objc_getAssociatedObject(collection.view, kCCAOriginalAlphaKey) doubleValue];
    collection.view.alpha = baseAlpha * gCCAPagerHeldAlphaFactor;
    if (gEditModeActive) {
        CGFloat wrapperProgress = (1.0 - heldScale) / 0.30;
        CGFloat wrapperX = kCCAEditScrubModuleWrapperCenteringX * wrapperProgress;
        CGFloat wrapperY = kCCAEditScrubModuleWrapperCenteringY * wrapperProgress;
        NSMutableSet<NSValue *> *seenWrappers = [NSMutableSet set];
        for (UIViewController *module in CCACollectModuleControllers(overlay)) {
            UIView *wrapper = module.view.superview;
            if (!wrapper || wrapper == collection.view) continue;
            NSValue *key = [NSValue valueWithNonretainedObject:wrapper];
            if ([seenWrappers containsObject:key]) continue;
            [seenWrappers addObject:key];
            NSValue *baseValue = objc_getAssociatedObject(wrapper, kCCAEditScrubWrapperBaseTransformKey);
            if (!baseValue) {
                baseValue = [NSValue valueWithCGAffineTransform:wrapper.transform];
                objc_setAssociatedObject(wrapper, kCCAEditScrubWrapperBaseTransformKey, baseValue, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            CGAffineTransform baseWrapper = baseValue.CGAffineTransformValue;
            wrapper.transform = CGAffineTransformTranslate(baseWrapper,
                                                           wrapperX,
                                                           wrapperY);
        }
    }

    if (changedPage) {
        // Pop the newly selected page in place. Animating module presentation
        // layers avoids changing private CCUI layout or leaving a second page
        // onscreen. Persistent Gaussian filters on oversized wrapper layers
        // caused the black rectangular intermediate surface, so this path is
        // deliberately bounded to transform + opacity.
        CCAEditGridView *grid = gEditModeActive ? [self editGridForPage:candidate overlay:overlay] : nil;
        if (grid) {
            [grid.layer removeAnimationForKey:@"CCAsterPagerPopScale"];
            [grid.layer removeAnimationForKey:@"CCAsterPagerPopFade"];
            CAKeyframeAnimation *gridScale = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale"];
            gridScale.values = @[@0.90, @1.025, @1.0];
            gridScale.keyTimes = @[@0.0, @0.68, @1.0];
            gridScale.duration = 0.20;
            gridScale.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
            [grid.layer addAnimation:gridScale forKey:@"CCAsterPagerPopScale"];
            CAKeyframeAnimation *gridFade = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
            gridFade.values = @[@0.08, @0.86, @1.0];
            gridFade.keyTimes = @[@0.0, @0.62, @1.0];
            gridFade.duration = 0.18;
            gridFade.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
            [grid.layer addAnimation:gridFade forKey:@"CCAsterPagerPopFade"];
        }
        for (UIViewController *module in CCACollectModuleControllers(overlay)) {
            NSString *identifier = CCAModuleIdentifier(module);
            NSValue *nativeValue = identifier.length ? gCCANativeLayoutRects[identifier] : nil;
            if (!nativeValue) continue;
            CCUILayoutRect rect = {};
            [nativeValue getValue:&rect];
            NSArray<NSNumber *> *origin = gCCACustomOrigins[identifier];
            if (origin.count >= 2) rect.origin = (CCUILayoutPoint){origin[0].unsignedIntegerValue, origin[1].unsignedIntegerValue};
            if (CCAPageForRect(rect) != candidate) continue;
            [module.view.layer removeAnimationForKey:@"CCAsterPagerPopScale"];
            [module.view.layer removeAnimationForKey:@"CCAsterPagerPopFade"];
            CAKeyframeAnimation *scale = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale"];
            scale.values = @[@0.90, @1.025, @1.0];
            scale.keyTimes = @[@0.0, @0.68, @1.0];
            scale.duration = 0.20;
            scale.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
            [module.view.layer addAnimation:scale forKey:@"CCAsterPagerPopScale"];
            CAKeyframeAnimation *fade = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
            fade.values = @[@0.08, @0.86, @1.0];
            fade.keyTimes = @[@0.0, @0.62, @1.0];
            fade.duration = 0.18;
            fade.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
            [module.view.layer addAnimation:fade forKey:@"CCAsterPagerPopFade"];
        }
    }

    UIView *host = [overlay.view viewWithTag:kCCAPageIndicatorHostTag];
    CGFloat itemHeight = kCCAPageIndicatorScrubStep;
    CGFloat hostHeight = itemHeight * gCCAPageCount;
    CGFloat hostMinY = scrubHostMinY;
    void (^layoutPager)(void) = ^{
        host.frame = CGRectMake(CGRectGetWidth(overlay.view.bounds) - kCCAPageIndicatorScrubHostWidth - kCCAPageIndicatorScrubRightInset,
                                hostMinY,
                                kCCAPageIndicatorScrubHostWidth,
                                hostHeight);
        [host.subviews enumerateObjectsUsingBlock:^(__kindof UIView *button, NSUInteger page, __unused BOOL *stop) {
        button.bounds = CGRectMake(0.0, 0.0, kCCAPageIndicatorScrubHostWidth, itemHeight);
        CGFloat centerY = ((CGFloat)page + 0.5) * itemHeight;
        BOOL selected = page == candidate;
        CGFloat proximity = MAX(0.0, 1.0 - fabs(touchY - centerY) / (gEditModeActive ? 92.0 : 78.0));
        if (gEditModeActive) proximity = selected ? MAX(0.72, proximity) : proximity * 0.58;
        CGFloat scale = 1.18 + 1.68 * proximity + (selected ? 0.18 : 0.0);
        CGFloat pointSize = MIN(38.0, CCAPageIndicatorBasePointSizeForPage(page) * scale);
        UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:pointSize weight:UIImageSymbolWeightSemibold];
        [(UIButton *)button setImage:[UIImage systemImageNamed:CCAPageIndicatorSymbolForPage(page) withConfiguration:configuration] forState:UIControlStateNormal];
        CGFloat slideOut = kCCAPageIndicatorMaxSlideOut * proximity;
        CGFloat targetAlpha = MIN(1.0, (selected ? 0.86 : 0.28) + 0.36 * proximity);
        CGFloat tintWhite = selected ? 1.0 : (0.12 + 0.72 * proximity);
        UIColor *targetTint = [UIColor colorWithWhite:tintWhite alpha:selected || proximity > 0.58 ? 1.0 : 0.88];
        button.alpha = targetAlpha;
        button.tintColor = targetTint;
        button.center = CGPointMake(kCCAPageIndicatorScrubHostWidth * 0.5 - slideOut, centerY);
        button.transform = CGAffineTransformIdentity;
    }];
    };
    if (gEditModeActive) {
        [UIView animateWithDuration:0.08 delay:0.0 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:layoutPager completion:nil];
    } else {
        layoutPager();
    }
    [self updateTopFadeForOverlay:overlay presentationAlpha:1.0];
}

- (void)finishInteractivePageTransitionForOverlay:(UIViewController *)overlay targetPage:(NSUInteger)targetPage {
    if (!overlay) return;
    CCAReassertNativeScrollClampForOverlay(overlay);
    gCCAPagerInteractiveBeganTime = 0.0;
    NSUInteger target = MIN(targetPage, gCCAPageCount - 1);
    UIViewController *collection = [self moduleCollectionControllerInOverlay:overlay];
    gCCACurrentPage = target;
    gCCAPagerInteractiveTranslation = 0.0;
    [self updatePagedModuleVisibilityForOverlay:overlay showAdjacent:YES];
    [self setHeaderChromeHiddenForScrubbing:NO overlay:overlay animated:YES];
    CGFloat baseAlpha = [objc_getAssociatedObject(collection.view, kCCAOriginalAlphaKey) doubleValue];
    void (^restoreWrapperBaseline)(BOOL clearBaseline) = ^(BOOL clearBaseline) {
        NSMutableSet<NSValue *> *seenWrappers = [NSMutableSet set];
        for (UIViewController *module in CCACollectModuleControllers(overlay)) {
            UIView *wrapper = module.view.superview;
            if (!wrapper || wrapper == collection.view) continue;
            NSValue *key = [NSValue valueWithNonretainedObject:wrapper];
            if ([seenWrappers containsObject:key]) continue;
            [seenWrappers addObject:key];
            NSValue *baseValue = objc_getAssociatedObject(wrapper, kCCAEditScrubWrapperBaseTransformKey);
            if (baseValue) wrapper.transform = baseValue.CGAffineTransformValue;
            if (clearBaseline) objc_setAssociatedObject(wrapper, kCCAEditScrubWrapperBaseTransformKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    };
    if (gEditModeActive) {
        [UIView performWithoutAnimation:^{
            restoreWrapperBaseline(NO);
        }];
    }
    [self animatePageSettleForOverlay:overlay
                            duration:0.30
                      timingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut]
                        modelChanges:^{
        CCAClampNativeScrollViewForOverlay(overlay);
        gCCAPagerHeldScale = 1.0;
        gCCAPagerHeldAlphaFactor = 1.0;
        gCCAPagerJelloScaleX = 1.0;
        gCCAPagerJelloScaleY = 1.0;
        [self applyPageTransformToOverlay:overlay animated:NO];
        collection.view.alpha = baseAlpha;
    } completion:^{
        for (UIViewController *module in CCACollectModuleControllers(overlay)) {
            [module.view.layer removeAnimationForKey:@"CCAsterPagerPopScale"];
            [module.view.layer removeAnimationForKey:@"CCAsterPagerPopFade"];
        }
        NSMutableDictionary<NSNumber *, CCAEditGridView *> *pageGrids = objc_getAssociatedObject(overlay, kCCAEditPageGridsKey);
        for (CCAEditGridView *grid in pageGrids.allValues) {
            [grid.layer removeAnimationForKey:@"CCAsterPagerPopScale"];
            [grid.layer removeAnimationForKey:@"CCAsterPagerPopFade"];
        }
        gCCAPagerScrubbingActive = NO;
        gCCAPagerTransitionActive = NO;
        objc_setAssociatedObject(collection.view, kCCAScrubCollectionBoundsKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(collection.view, kCCAScrubCollectionPositionKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        CCAReassertNativeScrollClampForOverlay(overlay);
        gCCAPagerViscousProgress = (CGFloat)target;
        gCCAPagerFilteredVelocity = 0.0;
        gCCAPagerLastSampleTime = 0.0;
        UIView *host = [overlay.view viewWithTag:kCCAPageIndicatorHostTag];
        objc_setAssociatedObject(host, kCCAPageIndicatorDraggingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [self applyPageTransformToOverlay:overlay animated:NO];
        [self updatePagedModuleVisibilityForOverlay:overlay showAdjacent:NO];
        [self updatePageIndicatorsForOverlay:overlay];
        [self updateTopFadeForOverlay:overlay presentationAlpha:0.0];
        if (gEditModeActive) {
            [UIView performWithoutAnimation:^{
                restoreWrapperBaseline(YES);
            }];
            [self prepareGridForOverlay:overlay collection:collection];
            [self updateEditControlFramesForOverlay:overlay];
            [self setEditControlsSuppressedForPaging:NO overlay:overlay animated:YES];
            UIView *pageIndicators = [overlay.view viewWithTag:kCCAPageIndicatorHostTag];
            if (pageIndicators && !pageIndicators.hidden) [overlay.view bringSubviewToFront:pageIndicators];
        }
    }];
}

- (void)pageIndicatorPanned:(UIPanGestureRecognizer *)gesture {
    UIView *host = gesture.view;
    UIViewController *overlay = gOverlayControllers.allObjects.firstObject;
    if (!gPagingEnabled || !overlay || !host || gCCAPageCount <= 1 ||
        gCCAExpandedModuleOpen || gCCADragInProgress) return;
    CGPoint location = [gesture locationInView:host];
    CGFloat step = gCCAPagerScrubbingActive ? kCCAPageIndicatorScrubStep : kCCAPageIndicatorRestStep;
    CGFloat progress = CCAPageProgressForScrubY(location.y, step, gCCAPageCount);
    if (gesture.state == UIGestureRecognizerStateBegan) {
        objc_setAssociatedObject(host, kCCAPageIndicatorDraggingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(gesture, kCCAPagerStartPageKey, @(gCCACurrentPage), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [self beginInteractivePageTransitionForOverlay:overlay startPage:gCCACurrentPage];
        location = [gesture locationInView:host];
        progress = CCAPageProgressForScrubY(location.y, kCCAPageIndicatorScrubStep, gCCAPageCount);
        [self updateInteractivePageTransitionForOverlay:overlay progress:progress touchY:location.y];
    } else if (gesture.state == UIGestureRecognizerStateChanged) {
        [self updateInteractivePageTransitionForOverlay:overlay progress:progress touchY:location.y];
    } else if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled || gesture.state == UIGestureRecognizerStateFailed) {
        NSUInteger startPage = [objc_getAssociatedObject(gesture, kCCAPagerStartPageKey) unsignedIntegerValue];
        NSUInteger target = gesture.state == UIGestureRecognizerStateEnded ? (NSUInteger)llround(MIN((CGFloat)gCCAPageCount - 1.0, MAX(0.0, progress))) : startPage;
        objc_setAssociatedObject(gesture, kCCAPagerStartPageKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [self finishInteractivePageTransitionForOverlay:overlay targetPage:target];
    }
}

- (void)trackControlCenterPresentationGesture:(UIPanGestureRecognizer *)gesture overlay:(UIViewController *)overlay controller:(id)controller {
    if (!gPagingEnabled || !gesture || gCCAExpandedModuleOpen || gCCADragInProgress) return;
    if (controller) gCCAPresentationController = controller;
    if (overlay) {
        // The pull gesture can begin before viewDidAppear/viewDidLayoutSubviews
        // has installed CCAster's pager.  Previously the tracker returned here,
        // so manually touching the pager was effectively required to prime the
        // next presentation. Bootstrap the persistent overlay on the first
        // pull callback instead.
        if (![gOverlayControllers containsObject:overlay]) {

            [self installOnOverlay:overlay];
        } else if (![overlay.view viewWithTag:kCCAPageIndicatorHostTag]) {

            [self installPagingOnOverlay:overlay];
        } else if (gCCAPageCount <= 1) {

            [self normalizePagedLayoutForOverlay:overlay];
        }
    }
    if (!overlay || gCCAPageCount <= 1) {

        return;
    }
    BOOL live = gesture.numberOfTouches > 0 &&
        (gesture.state == UIGestureRecognizerStateBegan || gesture.state == UIGestureRecognizerStateChanged);
    if (!live) {
        // The system recognizer can transition from its last Changed event to
        // Ended between display frames. Finish synchronously so a quick pull
        // cannot strand or skip the pager handoff.
        if (gCCAPresentationPanGesture == gesture) [self presentationPanDisplayLinkFired:nil];
        return;
    }
    if (gCCAPresentationPanGesture != gesture) {
        gCCAPresentationPanGesture = gesture;
    }
    [gCCAPresentationPanDiscoveryDisplayLink invalidate];
    gCCAPresentationPanDiscoveryDisplayLink = nil;
    gCCAPresentationPanDiscoveryOverlay = nil;
    gCCAPresentationPanDiscoveryController = nil;
    if (!gCCAPresentationPanDisplayLink) {
        gCCAPresentationPanDisplayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(presentationPanDisplayLinkFired:)];
        [gCCAPresentationPanDisplayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    }
    // Sample every private pull callback in addition to the display link.
    // This makes the vertical crossing deterministic even when a fast gesture
    // enters the pager band and releases inside a single refresh interval.
    [self presentationPanDisplayLinkFired:nil];
}

- (void)beginPresentationPanDiscoveryForOverlay:(UIViewController *)overlay controller:(id)controller {
    if (!gPagingEnabled || !overlay || gCCAPresentationPanGesture || gCCAPresentationNativeSettlePending || gCCAPresentationPageHandoffActive) return;
    gCCAPresentationPanDiscoveryOverlay = overlay;
    gCCAPresentationPanDiscoveryController = controller;
    gCCAPresentationPanDiscoveryDeadline = CACurrentMediaTime() + 0.75;
    if (!gCCAPresentationPanDiscoveryDisplayLink) {
        gCCAPresentationPanDiscoveryDisplayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(presentationPanDiscoveryDisplayLinkFired:)];
        [gCCAPresentationPanDiscoveryDisplayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    }
    [self presentationPanDiscoveryDisplayLinkFired:nil];
}

- (void)presentationPanDiscoveryDisplayLinkFired:(__unused CADisplayLink *)displayLink {
    UIViewController *overlay = gCCAPresentationPanDiscoveryOverlay;
    if (!gPagingEnabled || !overlay || gCCAPresentationPanGesture || CACurrentMediaTime() > gCCAPresentationPanDiscoveryDeadline) {
        [gCCAPresentationPanDiscoveryDisplayLink invalidate];
        gCCAPresentationPanDiscoveryDisplayLink = nil;
        gCCAPresentationPanDiscoveryOverlay = nil;
        gCCAPresentationPanDiscoveryController = nil;
        return;
    }
    UIView *root = overlay.view.window ?: overlay.view;
    UIPanGestureRecognizer *pan = nil;
    id controller = gCCAPresentationPanDiscoveryController;
    NSMutableArray *ownedRecognizers = [NSMutableArray array];
    for (NSString *selectorName in @[@"statusBarPullGestureRecognizer", @"indirectStatusBarPullGestureRecognizer", @"_presentGestureRecognizers"]) {
        SEL selector = NSSelectorFromString(selectorName);
        if (![controller respondsToSelector:selector]) continue;
        id value = ((id (*)(id, SEL))objc_msgSend)(controller, selector);
        if ([value isKindOfClass:[UIGestureRecognizer class]]) [ownedRecognizers addObject:value];
        else if ([value isKindOfClass:[NSArray class]]) [ownedRecognizers addObjectsFromArray:(NSArray *)value];
        else if ([value isKindOfClass:[NSSet class]]) [ownedRecognizers addObjectsFromArray:[(NSSet *)value allObjects]];
    }
    for (UIGestureRecognizer *gesture in ownedRecognizers) {
        if (![gesture isKindOfClass:[UIPanGestureRecognizer class]] || gesture.numberOfTouches == 0 ||
            (gesture.state != UIGestureRecognizerStateBegan && gesture.state != UIGestureRecognizerStateChanged)) continue;
        pan = (UIPanGestureRecognizer *)gesture;
        break;
    }
    if (!pan) pan = CCAFindActiveControlCenterPresentationPan(root);
    if (!pan) return;

    [self trackControlCenterPresentationGesture:pan overlay:overlay controller:controller];
}

- (void)presentationPanDisplayLinkFired:(__unused CADisplayLink *)displayLink {
    if (!gPagingEnabled) {
        [gCCAPresentationPanDisplayLink invalidate];
        gCCAPresentationPanDisplayLink = nil;
        gCCAPresentationPanGesture = nil;
        gCCAPresentationController = nil;
        gCCAPresentationNativeSettlePending = NO;
        gCCAPresentationReleasedWhileSettling = NO;
        gCCAPresentationPageHandoffActive = NO;
        gCCAPresentationHandoffArmed = NO;
        return;
    }
    UIViewController *overlay = gOverlayControllers.allObjects.firstObject;
    UIPanGestureRecognizer *pan = gCCAPresentationPanGesture;
    UIView *host = [overlay.view viewWithTag:kCCAPageIndicatorHostTag];
    if (overlay && !host) {
        [self updatePageIndicatorsForOverlay:overlay];
        host = [overlay.view viewWithTag:kCCAPageIndicatorHostTag];
    }
    // SBPanSystemGestureRecognizer can remain in Changed while SpringBoard
    // performs its post-release presentation animation. Touch count, unlike
    // state, drops to zero immediately and is the reliable handoff boundary.
    BOOL live = pan && pan.numberOfTouches > 0 &&
        (pan.state == UIGestureRecognizerStateBegan || pan.state == UIGestureRecognizerStateChanged);
    if (!overlay || !host || !live) {
        if (gCCAPresentationNativeSettlePending) {
            // A very fast pull can release during the single run-loop turn in
            // which the native reveal is being committed. Preserve that fact
            // so the deferred handoff can begin and settle to the sampled page
            // instead of discarding the crossing or exposing a half-open CC.
            gCCAPresentationReleasedWhileSettling = YES;
            return;
        }
        if (overlay && gCCAPresentationPageHandoffActive) {
            NSUInteger target = (NSUInteger)llround(MIN((CGFloat)gCCAPageCount - 1.0, MAX(0.0, gCCAPagerInteractiveProgress)));
            [self finishInteractivePageTransitionForOverlay:overlay targetPage:target];
        }
        if (overlay && gCCAPresentationHandoffArmed && !gCCAPresentationPageHandoffActive) {
            gCCAPresentationNativeSettlePending = YES;
            gCCAPresentationReleasedWhileSettling = YES;
            __weak UIViewController *weakOverlay = overlay;
            dispatch_async(dispatch_get_main_queue(), ^{
                UIViewController *settledOverlay = weakOverlay;
                id controller = gCCAPresentationController;
                if (!settledOverlay || !gCCAPresentationNativeSettlePending) return;
                if ([controller respondsToSelector:@selector(presentAnimated:)]) {
                    ((void (*)(id, SEL, BOOL))objc_msgSend)(controller, @selector(presentAnimated:), NO);
                }
                [settledOverlay.view.window layoutIfNeeded];
                [settledOverlay.view layoutIfNeeded];
                [CATransaction flush];
                dispatch_async(dispatch_get_main_queue(), ^{
                    UIViewController *committedOverlay = weakOverlay;
                    if (!committedOverlay || !gCCAPresentationNativeSettlePending) return;
                    [committedOverlay.view.window layoutIfNeeded];
                    [committedOverlay.view layoutIfNeeded];
                    [committedOverlay.view.layer removeAllAnimations];
                    UIViewController *collection = [self moduleCollectionControllerInOverlay:committedOverlay];
                    [collection.view.layer removeAllAnimations];
                    gCCAPagerTransitionActive = NO;
                    gCCAPagerScrubbingActive = NO;
                    gCCAPagerInteractiveTranslation = 0.0;
                    [self applyPageTransformToOverlay:committedOverlay animated:NO];
                    [self updatePagedModuleVisibilityForOverlay:committedOverlay showAdjacent:NO];
                    gCCAPresentationNativeSettlePending = NO;
                    gCCAPresentationPageHandoffActive = YES;
                    gCCAPresentationHandoffArmed = NO;
                    [self beginInteractivePageTransitionForOverlay:committedOverlay startPage:gCCACurrentPage];
                    [self updateInteractivePageTransitionForOverlay:committedOverlay progress:gCCAPresentationPendingProgress touchY:gCCAPresentationPendingTouchY];
                    NSUInteger target = (NSUInteger)llround(MIN((CGFloat)gCCAPageCount - 1.0, MAX(0.0, gCCAPagerInteractiveProgress)));
                    [self finishInteractivePageTransitionForOverlay:committedOverlay targetPage:target];
                    gCCAPresentationPageHandoffActive = NO;
                    gCCAPresentationReleasedWhileSettling = NO;
                    gCCAPresentationPanGesture = nil;
                    gCCAPresentationController = nil;
                    [gCCAPresentationPanDisplayLink invalidate];
                    gCCAPresentationPanDisplayLink = nil;
                });
            });
            return;
        }
        gCCAPresentationPageHandoffActive = NO;
        gCCAPresentationHandoffArmed = NO;
        gCCAPresentationPanGesture = nil;
        gCCAPresentationController = nil;
        [gCCAPresentationPanDisplayLink invalidate];
        gCCAPresentationPanDisplayLink = nil;
        return;
    }

    UIView *windowView = overlay.view.window ?: overlay.view;
    CGPoint windowLocation = [pan locationInView:windowView];
    // The iOS 16 delegate only reports "significant" presentation progress
    // at the settled boundary on this hardware. Crossing the pager's vertical
    // origin is therefore the handoff boundary regardless of horizontal touch
    // position; the gesture is already the dedicated top-right CC recognizer.
    CGFloat scrubHostHeight = kCCAPageIndicatorScrubStep * gCCAPageCount;
    CGFloat scrubHostMinY = floor((CGRectGetHeight(windowView.bounds) - scrubHostHeight) * 0.5);
    CGFloat scrubTouchY = windowLocation.y - scrubHostMinY;
    // Opening starts on page zero. Do not transfer ownership merely because
    // the finger entered the pager's enlarged hit region: wait until it
    // actually reaches the visible first page icon. Once claimed, the normal
    // expanded scrub geometry below remains in effect.
    CGFloat handoffY = scrubHostMinY + kCCAPageIndicatorScrubStep * 0.5;
    if (host.subviews.count) {
        UIView *firstIndicator = host.subviews.firstObject;
        CGPoint visibleIconCenter = [host convertPoint:firstIndicator.center toView:windowView];
        if (isfinite(visibleIconCenter.y) && visibleIconCenter.y > 0.0) handoffY = visibleIconCenter.y;
    }
    CGFloat armY = handoffY;
    CGFloat progress = CCAPageProgressForScrubY(scrubTouchY, kCCAPageIndicatorScrubStep, gCCAPageCount);
    gCCAPresentationPendingProgress = progress;
    gCCAPresentationPendingTouchY = scrubTouchY;
    if (!gCCAPresentationPageHandoffActive && !gCCAPresentationNativeSettlePending && windowLocation.y >= armY) {
        gCCAPresentationHandoffArmed = YES;
    }
    BOOL shouldStartHandoff = windowLocation.y >= handoffY;
    if (!gCCAPresentationPageHandoffActive && !gCCAPresentationNativeSettlePending && shouldStartHandoff) {

        // SpringBoard's pull recognizer leaves the modular overlay in an
        // interactive stretched presentation. Starting our compact pager in
        // that state makes its scale compose with a moving native transform,
        // which produces the jump/halfway state seen at the handoff. Claim the
        // gesture now, then finish the native reveal on the next main-loop turn
        // before applying any CCAster pager transforms.
        gCCAPresentationNativeSettlePending = YES;
        gCCAPresentationReleasedWhileSettling = NO;
        __weak UIViewController *weakOverlay = overlay;
        dispatch_async(dispatch_get_main_queue(), ^{
            UIViewController *settledOverlay = weakOverlay;
            id controller = gCCAPresentationController;
            if (!settledOverlay || !gCCAPresentationNativeSettlePending) return;
            if ([controller respondsToSelector:@selector(presentAnimated:)]) {
                ((void (*)(id, SEL, BOOL))objc_msgSend)(controller, @selector(presentAnimated:), NO);
            }
            [settledOverlay.view.window layoutIfNeeded];
            [settledOverlay.view layoutIfNeeded];
            [CATransaction flush];
            dispatch_async(dispatch_get_main_queue(), ^{
                UIViewController *committedOverlay = weakOverlay;
                if (!committedOverlay || !gCCAPresentationNativeSettlePending) return;
                [committedOverlay.view.window layoutIfNeeded];
                [committedOverlay.view layoutIfNeeded];
                [committedOverlay.view.layer removeAllAnimations];
                UIViewController *collection = [self moduleCollectionControllerInOverlay:committedOverlay];
                [collection.view.layer removeAllAnimations];
                gCCAPagerTransitionActive = NO;
                gCCAPagerScrubbingActive = NO;
                gCCAPagerInteractiveTranslation = 0.0;
                [self applyPageTransformToOverlay:committedOverlay animated:NO];
                [self updatePagedModuleVisibilityForOverlay:committedOverlay showAdjacent:NO];

                gCCAPresentationNativeSettlePending = NO;
                gCCAPresentationPageHandoffActive = YES;
                gCCAPresentationHandoffArmed = NO;
                [self beginInteractivePageTransitionForOverlay:committedOverlay startPage:gCCACurrentPage];
                [self updateInteractivePageTransitionForOverlay:committedOverlay
                                                       progress:gCCAPresentationPendingProgress
                                                         touchY:gCCAPresentationPendingTouchY];

                UIPanGestureRecognizer *currentPan = gCCAPresentationPanGesture;
                BOOL stillLive = currentPan && currentPan.numberOfTouches > 0 &&
                    (currentPan.state == UIGestureRecognizerStateBegan || currentPan.state == UIGestureRecognizerStateChanged);
                if (gCCAPresentationReleasedWhileSettling || !stillLive) {
                    NSUInteger target = (NSUInteger)llround(MIN((CGFloat)gCCAPageCount - 1.0, MAX(0.0, gCCAPagerInteractiveProgress)));
                    [self finishInteractivePageTransitionForOverlay:committedOverlay targetPage:target];
                    gCCAPresentationPageHandoffActive = NO;
                    gCCAPresentationHandoffArmed = NO;
                    gCCAPresentationReleasedWhileSettling = NO;
                    gCCAPresentationPanGesture = nil;
                    gCCAPresentationController = nil;
                    [gCCAPresentationPanDisplayLink invalidate];
                    gCCAPresentationPanDisplayLink = nil;
                }
            });
        });
        return;
    }
    if (gCCAPresentationPageHandoffActive) {
        [self updateInteractivePageTransitionForOverlay:overlay progress:progress touchY:scrubTouchY];
    }
}

- (void)updatePageIndicatorsForOverlay:(UIViewController *)overlay {
    if (!overlay.view) return;
    UIView *host = [overlay.view viewWithTag:kCCAPageIndicatorHostTag];
    if (!host) {
        host = [[UIView alloc] initWithFrame:CGRectZero];
        host.tag = kCCAPageIndicatorHostTag;
        host.backgroundColor = UIColor.clearColor;
        host.userInteractionEnabled = YES;
        [overlay.view addSubview:host];
    }
    UIPanGestureRecognizer *indicatorPan = objc_getAssociatedObject(host, kCCAPageIndicatorPanKey);
    if (!indicatorPan) {
        indicatorPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pageIndicatorPanned:)];
        indicatorPan.maximumNumberOfTouches = 1;
        indicatorPan.cancelsTouchesInView = YES;
        objc_setAssociatedObject(indicatorPan, kCCAOwnGestureKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(host, kCCAPageIndicatorPanKey, indicatorPan, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [host addGestureRecognizer:indicatorPan];
    }
    indicatorPan.enabled = gPagingEnabled;
    host.userInteractionEnabled = gPagingEnabled;
    if (!gPagingEnabled) {
        objc_setAssociatedObject(host, kCCAPageIndicatorDraggingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [host.layer removeAllAnimations];
        host.hidden = YES;
        host.alpha = 0.0;
        return;
    }
    if ([objc_getAssociatedObject(host, kCCAPageIndicatorDraggingKey) boolValue]) {
        host.hidden = gCCAPageCount <= 1 || !gCCAControlCenterPresented || (gCCAExpandedModuleOpen && !CCAExpandedChromeRevealActive());
        if (!host.hidden) [overlay.view bringSubviewToFront:host];
        return;
    }
    NSUInteger previousCount = [objc_getAssociatedObject(host, kCCAPageIndicatorCountKey) unsignedIntegerValue];
    BOOL countChanged = previousCount != gCCAPageCount;
    if (host.subviews.count > gCCAPageCount) {
        NSArray<UIView *> *extra = [host.subviews subarrayWithRange:NSMakeRange(gCCAPageCount, host.subviews.count - gCCAPageCount)];
        [UIView animateWithDuration:0.18 delay:0.0 options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionBeginFromCurrentState animations:^{
            for (UIView *view in extra) {
                view.alpha = 0.0;
                view.transform = CGAffineTransformMakeScale(0.72, 0.72);
            }
        } completion:^(__unused BOOL finished) {
            for (UIView *view in extra) [view removeFromSuperview];
        }];
    }
    while (host.subviews.count < gCCAPageCount) {
        NSUInteger page = host.subviews.count;
        CCAExpandedHitButton *button = [CCAExpandedHitButton buttonWithType:UIButtonTypeCustom];
        button.tintColor = UIColor.whiteColor;
        button.alpha = countChanged ? 0.0 : 1.0;
        button.transform = countChanged ? CGAffineTransformMakeScale(0.72, 0.72) : CGAffineTransformIdentity;
        [button addTarget:self action:@selector(pageIndicatorTouchDown:) forControlEvents:UIControlEventTouchDown];
        [button addTarget:self action:@selector(pageIndicatorTapped:) forControlEvents:UIControlEventTouchUpInside];
        [button addTarget:self action:@selector(pageIndicatorTapped:) forControlEvents:UIControlEventTouchUpOutside | UIControlEventTouchCancel];
        objc_setAssociatedObject(button, @selector(pageIndicatorTapped:), @(page), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [host addSubview:button];
    }
    objc_setAssociatedObject(host, kCCAPageIndicatorCountKey, @(gCCAPageCount), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    CGFloat itemHeight = gCCAPagerScrubbingActive ? kCCAPageIndicatorScrubStep : kCCAPageIndicatorRestStep;
    CGFloat hostHeight = itemHeight * gCCAPageCount;
    CGFloat hostWidth = gCCAPagerScrubbingActive ? kCCAPageIndicatorScrubHostWidth : kCCAPageIndicatorRestHostWidth;
    CGFloat rightInset = gCCAPagerScrubbingActive ? kCCAPageIndicatorScrubRightInset : kCCAPageIndicatorRestRightInset;
    // Rest in the native-looking edge gutter, then slide inward only while
    // scrubbing so the enlarged symbol remains visible under the finger.
    CGRect targetHostFrame = CGRectMake(CGRectGetWidth(overlay.view.bounds) - hostWidth - rightInset,
                                        floor((CGRectGetHeight(overlay.view.bounds) - hostHeight) * 0.5),
                                        hostWidth,
                                        hostHeight);
    void (^layoutIndicators)(void) = ^{
        host.frame = targetHostFrame;
        [host.subviews enumerateObjectsUsingBlock:^(__kindof UIView *button, NSUInteger page, __unused BOOL *stop) {
            button.frame = CGRectMake(0.0, page * itemHeight, hostWidth, itemHeight);
            UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:CCAPageIndicatorBasePointSizeForPage(page) weight:UIImageSymbolWeightSemibold];
            [(UIButton *)button setImage:[UIImage systemImageNamed:CCAPageIndicatorSymbolForPage(page) withConfiguration:configuration] forState:UIControlStateNormal];
            BOOL selected = page == gCCACurrentPage;
            button.alpha = selected ? 1.0 : 0.72;
            button.tintColor = selected ? UIColor.whiteColor : [UIColor colorWithWhite:0.12 alpha:0.88];
            button.transform = CGAffineTransformIdentity;
            objc_setAssociatedObject(button, @selector(pageIndicatorTapped:), @(page), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }];
    };
    if (countChanged && host.window) {
        [UIView animateWithDuration:0.24 delay:0.0 options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:layoutIndicators completion:nil];
    } else {
        [UIView animateWithDuration:0.22 delay:0.0 options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:layoutIndicators completion:nil];
    }
    BOOL revealActive = CCAExpandedChromeRevealActive();
    host.hidden = gCCAPageCount <= 1 || !gCCAControlCenterPresented || (gCCAExpandedModuleOpen && !revealActive);
    if (!host.hidden) {
        [overlay.view bringSubviewToFront:host];
        if (!revealActive) {
            [UIView animateWithDuration:0.20 delay:0.0
                                options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                             animations:^{ host.alpha = 1.0; }
                             completion:nil];
        }
    }
}

- (void)pagePanned:(UIPanGestureRecognizer *)gesture {
    UIViewController *overlay = nil;
    for (UIViewController *candidate in gOverlayControllers.allObjects) if (candidate.view == gesture.view) { overlay = candidate; break; }
    if (!gPagingEnabled || !overlay || gCCAPageCount <= 1 ||
        gCCAExpandedModuleOpen || gCCADragInProgress) return;
    if (gesture.state == UIGestureRecognizerStateBegan) {
        gCCAPagerTransitionActive = YES;
        if (gEditModeActive) [self setEditControlsSuppressedForPaging:YES overlay:overlay animated:YES];
        [self updateTopFadeForOverlay:overlay presentationAlpha:1.0];
        objc_setAssociatedObject(gesture, kCCAPagerStartPageKey, @(gCCACurrentPage), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        gCCAPagerInteractiveTranslation = 0.0;
        gCCAPagerHeldScale = 1.0;
        gCCAPagerHeldAlphaFactor = 1.0;
        [self updatePagedModuleVisibilityForOverlay:overlay showAdjacent:YES];
        UIScrollView *nativeScrollView = CCANativeScrollViewForOverlay(overlay);
        NSValue *nativeBaseline = CCAEnsureNativeScrollBaseline(overlay);
        if (nativeScrollView && nativeBaseline) {
            CCAClampNativeScrollViewForOverlay(overlay);
            objc_setAssociatedObject(gesture, kCCAPagerNativeScrollViewKey, nativeScrollView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(gesture, kCCAPagerNativeOffsetKey, nativeBaseline, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        NSMutableArray<UIGestureRecognizer *> *suppressed = [NSMutableArray array];
        NSMutableArray<UIView *> *viewQueue = [NSMutableArray arrayWithObject:overlay.view];
        while (viewQueue.count) {
            UIView *view = viewQueue.firstObject;
            [viewQueue removeObjectAtIndex:0];
            for (UIGestureRecognizer *other in view.gestureRecognizers) {
                if (other == gesture || [objc_getAssociatedObject(other, kCCAOwnGestureKey) boolValue]) continue;
                if ([other isKindOfClass:[UIPanGestureRecognizer class]] && other.enabled) {
                    other.enabled = NO;
                    [suppressed addObject:other];
                }
            }
            [viewQueue addObjectsFromArray:view.subviews];
        }
        objc_setAssociatedObject(gesture, kCCAPagerSuppressedGesturesKey, suppressed, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    NSUInteger startPage = [objc_getAssociatedObject(gesture, kCCAPagerStartPageKey) unsignedIntegerValue];
    CGPoint translation = [gesture translationInView:overlay.view];
    if ((startPage == 0 && translation.y > 0.0) || (startPage + 1 >= gCCAPageCount && translation.y < 0.0)) translation.y *= 0.24;
    if (gesture.state == UIGestureRecognizerStateChanged) {
        gCCACurrentPage = startPage;
        gCCAPagerInteractiveTranslation = translation.y;
        [self applyPageTransformToOverlay:overlay animated:NO];
        [self updateTopFadeForOverlay:overlay presentationAlpha:1.0];
        if (gEditModeActive) [self updateEditControlFramesForOverlay:overlay];
        return;
    }
    if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled || gesture.state == UIGestureRecognizerStateFailed) {
        CGPoint velocity = [gesture velocityInView:overlay.view];
        NSInteger target = (NSInteger)startPage;
        if (gesture.state == UIGestureRecognizerStateEnded) {
            CGFloat visualPageSpan = CCAVisualPageSpan();
            if (translation.y < -visualPageSpan * 0.16 || velocity.y < -520.0) target++;
            else if (translation.y > visualPageSpan * 0.16 || velocity.y > 520.0) target--;
        }
        target = MAX(0, MIN((NSInteger)gCCAPageCount - 1, target));
        UIScrollView *nativeScrollView = objc_getAssociatedObject(gesture, kCCAPagerNativeScrollViewKey);
        NSValue *nativeOffsetValue = objc_getAssociatedObject(gesture, kCCAPagerNativeOffsetKey);
        CGPoint nativeOffset = nativeOffsetValue ? nativeOffsetValue.CGPointValue : CGPointZero;
        if (nativeScrollView && nativeOffsetValue) {
            CCAClampNativeScrollViewForOverlay(overlay);
            [nativeScrollView setContentOffset:nativeOffset animated:NO];
        }
        NSArray<UIGestureRecognizer *> *suppressedGestures = objc_getAssociatedObject(gesture, kCCAPagerSuppressedGesturesKey);
        if (gEditModeActive) {
            [self updatePagedModuleVisibilityForOverlay:overlay showAdjacent:YES];
            NSInteger delta = (NSInteger)startPage - target;
            gCCACurrentPage = startPage;
            CGFloat finalTranslation = (CGFloat)delta * CCAVisualPageSpan();
            CGFloat remaining = fabs(finalTranslation - gCCAPagerInteractiveTranslation);
            CGFloat releaseVelocity = fabs(velocity.y);
            CGFloat distanceFactor = MIN(1.0, remaining / MAX(CCAVisualPageSpan(), 1.0));
            CGFloat velocityFactor = MIN(1.0, releaseVelocity / 1800.0);
            NSTimeInterval duration = MIN(0.62, MAX(0.18, 0.22 + distanceFactor * 0.34 - velocityFactor * 0.28));
            CAMediaTimingFunction *settleCurve = [CAMediaTimingFunction functionWithControlPoints:0.18 :0.88 :0.20 :1.0];
            [self animatePageSettleForOverlay:overlay duration:duration timingFunction:settleCurve modelChanges:^{
                gCCACurrentPage = (NSUInteger)target;
                gCCAPagerInteractiveTranslation = 0.0;
                [self applyPageTransformToOverlay:overlay animated:NO];
                [self updateTopFadeForOverlay:overlay presentationAlpha:1.0];
            } completion:^{
                gCCAPagerTransitionActive = NO;
                [self applyPageTransformToOverlay:overlay animated:NO];
                [self updatePagedModuleVisibilityForOverlay:overlay showAdjacent:NO];
                [self updatePageIndicatorsForOverlay:overlay];
                [self updateTopFadeForOverlay:overlay presentationAlpha:0.0];
                [self prepareGridForOverlay:overlay collection:[self moduleCollectionControllerInOverlay:overlay]];
                [self updateEditControlFramesForOverlay:overlay];
                [self setEditControlsSuppressedForPaging:NO overlay:overlay animated:YES];
                for (UIGestureRecognizer *suppressed in suppressedGestures) suppressed.enabled = YES;
                if (nativeScrollView && nativeOffsetValue) {
                    CCAClampNativeScrollViewForOverlay(overlay);
                    [nativeScrollView setContentOffset:nativeOffset animated:NO];
                }
            }];
        } else {
            for (UIGestureRecognizer *suppressed in suppressedGestures) suppressed.enabled = YES;
            // Velocity-aware settle (mirrors the edit-mode branch above). The old
            // path used a fixed-duration curve via setCurrentPage:, so a fast
            // flick to the last page crawled the final stretch into place — the
            // "jelly overstick". Hold the page and ride the interactive
            // translation to the target on a spring scaled by release velocity,
            // then rebase in the completion.
            gCCAPagerTransitionActive = YES;
            gCCAPagerScrubbingActive = NO;
            [self updatePagedModuleVisibilityForOverlay:overlay showAdjacent:YES];
            NSInteger delta = (NSInteger)startPage - target;
            gCCACurrentPage = startPage;
            CGFloat finalTranslation = (CGFloat)delta * CCAVisualPageSpan();
            CGFloat remaining = fabs(finalTranslation - gCCAPagerInteractiveTranslation);
            CGFloat releaseVelocity = fabs(velocity.y);
            CGFloat distanceFactor = MIN(1.0, remaining / MAX(CCAVisualPageSpan(), 1.0));
            CGFloat velocityFactor = MIN(1.0, releaseVelocity / 1800.0);
            NSTimeInterval duration = MIN(0.62, MAX(0.18, 0.22 + distanceFactor * 0.34 - velocityFactor * 0.28));
            UIScrollView *settleScrollView = nativeScrollView;
            NSValue *settleOffsetValue = nativeOffsetValue;
            CGPoint settleOffset = nativeOffset;
            CAMediaTimingFunction *settleCurve = [CAMediaTimingFunction functionWithControlPoints:0.18 :0.88 :0.20 :1.0];
            [self animatePageSettleForOverlay:overlay duration:duration timingFunction:settleCurve modelChanges:^{
                gCCACurrentPage = (NSUInteger)target;
                gCCAPagerInteractiveTranslation = 0.0;
                [self applyPageTransformToOverlay:overlay animated:NO];
                [self updateTopFadeForOverlay:overlay presentationAlpha:1.0];
            } completion:^{
                gCCAPagerTransitionActive = NO;
                [self applyPageTransformToOverlay:overlay animated:NO];
                [self updatePagedModuleVisibilityForOverlay:overlay showAdjacent:NO];
                [self updatePageIndicatorsForOverlay:overlay];
                [self updateTopFadeForOverlay:overlay presentationAlpha:0.0];
                if (settleScrollView && settleOffsetValue) {
                    CCAClampNativeScrollViewForOverlay(overlay);
                    [settleScrollView setContentOffset:settleOffset animated:NO];
                }
            }];
        }
        // The private scroll view can receive a final deferred offset write
        // after its pan is re-enabled. Reassert both native and CCAster settled
        // geometry across the short snap window so no page remains one span
        // above or below its selected indicator.
        if (!gEditModeActive) {
            for (NSNumber *delay in @[@0.0, @0.08, @0.24, @0.42]) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    if (nativeScrollView && nativeOffsetValue) {
                        CCAClampNativeScrollViewForOverlay(overlay);
                        [nativeScrollView setContentOffset:nativeOffset animated:NO];
                    }
                    if (delay.doubleValue >= 0.4 && fabs(gCCAPagerInteractiveTranslation) < 0.01) [self applyPageTransformToOverlay:overlay animated:NO];
                });
            }
        }
        objc_setAssociatedObject(gesture, kCCAPagerStartPageKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(gesture, kCCAPagerSuppressedGesturesKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(gesture, kCCAPagerNativeScrollViewKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(gesture, kCCAPagerNativeOffsetKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

- (void)installPagingOnOverlay:(UIViewController *)overlay {
    if (!gEnabled || !overlay.view) return;
    CCAEnsureNativeScrollBaseline(overlay);
    CCAClampNativeScrollViewForOverlay(overlay);
    CCARestoreNativeScrollBaseline(overlay);
    UIViewController *collection = [self moduleCollectionControllerInOverlay:overlay];
    collection.view.clipsToBounds = NO;
    UIView *nativeCollectionView = CCAFindSubviewWithClassName(collection.view, @"CCUIModuleCollectionView");
    nativeCollectionView.clipsToBounds = NO;
    for (UIView *ancestor = collection.view.superview; ancestor && ancestor != overlay.view; ancestor = ancestor.superview) ancestor.clipsToBounds = NO;
    UIPanGestureRecognizer *pager = nil;
    for (UIGestureRecognizer *gesture in overlay.view.gestureRecognizers) {
        if ([objc_getAssociatedObject(gesture, kCCAPagerGestureKey) boolValue]) { pager = (UIPanGestureRecognizer *)gesture; break; }
    }
    if (!pager) {
        pager = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pagePanned:)];
        pager.maximumNumberOfTouches = 1;
        pager.cancelsTouchesInView = NO;
        pager.delegate = self;
        objc_setAssociatedObject(pager, kCCAOwnGestureKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(pager, kCCAPagerGestureKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [overlay.view addGestureRecognizer:pager];
    }
    for (UIGestureRecognizer *gesture in overlay.view.gestureRecognizers) {
        if (![objc_getAssociatedObject(gesture, @selector(modulePanned:)) isEqual:@"overlayPan"]) continue;
        if (objc_getAssociatedObject(pager, kCCAPagerModulePanDependencyKey) != gesture) {
            [pager requireGestureRecognizerToFail:gesture];
            objc_setAssociatedObject(pager, kCCAPagerModulePanDependencyKey, gesture, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        break;
    }
    pager.enabled = gPagingEnabled;
    [self normalizePagedLayoutForOverlay:overlay];
    if (!gPagingEnabled) {
        gCCACurrentPage = 0;
        gCCAPagerTransitionActive = NO;
        gCCAPagerScrubbingActive = NO;
        gCCAPagerInteractiveTranslation = 0.0;
        gCCAPagerInteractiveProgress = 0.0;
        gCCAPagerInteractiveStartPage = 0;
        gCCAPresentationNativeSettlePending = NO;
        gCCAPresentationReleasedWhileSettling = NO;
        gCCAPresentationPageHandoffActive = NO;
        gCCAPresentationHandoffArmed = NO;
        gCCAPresentationPanGesture = nil;
        gCCAPresentationController = nil;
        [gCCAPresentationPanDisplayLink invalidate];
        gCCAPresentationPanDisplayLink = nil;
        [gCCAPresentationPanDiscoveryDisplayLink invalidate];
        gCCAPresentationPanDiscoveryDisplayLink = nil;
        gCCAPresentationPanDiscoveryOverlay = nil;
        gCCAPresentationPanDiscoveryController = nil;
        [self setHeaderChromeHiddenForScrubbing:NO overlay:overlay animated:NO];
        [self setEditControlsSuppressedForPaging:NO overlay:overlay animated:NO];
    }
    [self installTopFadeForOverlay:overlay];
    [self updatePageIndicatorsForOverlay:overlay];
    [self applyPageTransformToOverlay:overlay animated:NO];
    [self updatePagedModuleVisibilityForOverlay:overlay showAdjacent:NO];
}

- (void)installOnOverlay:(UIViewController *)controller {
    if (!gEnabled || !controller.view) return;
    [self installQuickAccessHostOnOverlay:controller];
    [self installTopFadeForOverlay:controller];
    if ([gOverlayControllers containsObject:controller]) return;
    if (gBlankSpaceGestureEnabled) {
        UILongPressGestureRecognizer *blankHold = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(blankHeld:)];
        blankHold.minimumPressDuration = 0.55;
        blankHold.delegate = self;
        objc_setAssociatedObject(blankHold, kCCAOwnGestureKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(blankHold, @selector(blankHeld:), @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [controller.view addGestureRecognizer:blankHold];
    }
    // Tapping blank space (outside modules / vacant grid cells) exits edit
    // mode; the delegate's tap branch rejects touches on modules and chrome.
    UITapGestureRecognizer *editExitTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(editExitTapped:)];
    editExitTap.cancelsTouchesInView = NO;
    editExitTap.delegate = self;
    objc_setAssociatedObject(editExitTap, kCCAOwnGestureKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [controller.view addGestureRecognizer:editExitTap];
    UIPanGestureRecognizer *editDismissPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(editDismissPanned:)];
    editDismissPan.maximumNumberOfTouches = 1;
    editDismissPan.cancelsTouchesInView = YES;
    editDismissPan.delegate = self;
    objc_setAssociatedObject(editDismissPan, kCCAOwnGestureKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(editDismissPan, kCCAEditDismissPanKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [controller.view addGestureRecognizer:editDismissPan];
    UILongPressGestureRecognizer *modulePan = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(modulePanned:)];
    modulePan.minimumPressDuration = 0.01;
    modulePan.allowableMovement = CGFLOAT_MAX;
    modulePan.cancelsTouchesInView = YES;
    modulePan.delaysTouchesBegan = NO;
    modulePan.delaysTouchesEnded = NO;
    modulePan.delegate = self;
    objc_setAssociatedObject(modulePan, kCCAOwnGestureKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(modulePan, @selector(modulePanned:), @"overlayPan", OBJC_ASSOCIATION_COPY_NONATOMIC);
    [controller.view addGestureRecognizer:modulePan];
    [editExitTap requireGestureRecognizerToFail:modulePan];
    [gOverlayControllers addObject:controller];
    CCAExtendedModuleHitBridge *hitBridge = [[CCAExtendedModuleHitBridge alloc] initWithFrame:controller.view.bounds];
    hitBridge.tag = kCCAExtendedHitBridgeTag;
    hitBridge.overlay = controller;
    hitBridge.backgroundColor = UIColor.clearColor;
    hitBridge.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [controller.view addSubview:hitBridge];
    [self syncOwnedDuplicateModulesForOverlay:controller];
    [self installPagingOnOverlay:controller];
    [self applyRestingModuleOffsetToOverlay:controller];
}

- (void)applyRestingModuleOffsetToOverlay:(UIViewController *)overlay {
    if (!overlay || gEditModeActive) return;
    UIViewController *collection = [self moduleCollectionControllerInOverlay:overlay];
    if (!collection.view) return;
    [self capturePresentationStateForView:collection.view];
    CGAffineTransform collectionBase = [objc_getAssociatedObject(collection.view, kCCAOriginalTransformKey) CGAffineTransformValue];
    CATransform3D sublayerBase = [objc_getAssociatedObject(collection.view, kCCAOriginalSublayerTransformKey) CATransform3DValue];
    collection.view.layer.sublayerTransform = CATransform3DTranslate(sublayerBase, 0.0, -(CGFloat)gCCACurrentPage * CCAVisualPageSpan(), 0.0);
    collection.view.transform = CGAffineTransformTranslate(collectionBase, 0.0, kCCARestingModuleOffset);

    // Keep module wrappers at their native transforms. Expansion transitions
    // temporarily own these wrappers; a persistent per-wrapper translation was
    // reapplied after dismissal and produced the visible upward landing hop.
    NSMutableSet<NSValue *> *seenWrappers = [NSMutableSet set];
    for (UIViewController *module in CCACollectModuleControllers(overlay)) {
        UIView *wrapper = module.view.superview;
        if (!wrapper || wrapper == collection.view) continue;
        NSValue *key = [NSValue valueWithNonretainedObject:wrapper];
        if ([seenWrappers containsObject:key]) continue;
        [seenWrappers addObject:key];
        [self capturePresentationStateForView:wrapper];
        CGAffineTransform base = [objc_getAssociatedObject(wrapper, kCCAOriginalTransformKey) CGAffineTransformValue];
        wrapper.transform = base;
    }
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture {
    if ([objc_getAssociatedObject(gesture, kCCAEditDismissPanKey) boolValue]) {
        if (!gEditModeActive || gCCAExpandedModuleOpen || gCCADragInProgress || gCCAResizeInProgress) return NO;
        CGPoint location = [gesture locationInView:gesture.view];
        if (location.y <= CGRectGetHeight(gesture.view.bounds) - MAX(92.0, gesture.view.safeAreaInsets.bottom + 68.0)) return NO;
        CGPoint velocity = [(UIPanGestureRecognizer *)gesture velocityInView:gesture.view];
        return velocity.y < -80.0 && fabs(velocity.y) > fabs(velocity.x);
    }
    if ([objc_getAssociatedObject(gesture, kCCAPagerGestureKey) boolValue]) {
        if (!gPagingEnabled || gCCAPageCount <= 1 || gCCAExpandedModuleOpen ||
            gCCADragInProgress || gCCAResizeInProgress) return NO;
        CGPoint velocity = [(UIPanGestureRecognizer *)gesture velocityInView:gesture.view];
        CGPoint location = [gesture locationInView:gesture.view];
        if (location.y > CGRectGetHeight(gesture.view.bounds) - MAX(92.0, gesture.view.safeAreaInsets.bottom + 68.0)) return NO;
        // At the bottom of the pager, preserve iOS 16's native upward Control
        // Center dismissal instead of trapping the user in a rubber band — but
        // never while a drag is in flight, or the held module dumps out of edit.
        if (!gCCADragInProgress && gCCACurrentPage + 1 >= gCCAPageCount && velocity.y < 0.0) return NO;
        return fabs(velocity.y) > fabs(velocity.x) * 1.12;
    }
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldReceiveTouch:(UITouch *)touch {
    if ([objc_getAssociatedObject(gesture, kCCAEditDismissPanKey) boolValue]) {
        if (!gEditModeActive || gCCAExpandedModuleOpen || gCCADragInProgress || gCCAResizeInProgress) return NO;
        CGPoint location = [touch locationInView:gesture.view];
        return location.y > CGRectGetHeight(gesture.view.bounds) - MAX(92.0, gesture.view.safeAreaInsets.bottom + 68.0);
    }
    if ([objc_getAssociatedObject(gesture, kCCAPagerGestureKey) boolValue]) {
        if (!gPagingEnabled || gCCAPageCount <= 1 || gCCAExpandedModuleOpen ||
            gCCADragInProgress || gCCAResizeInProgress) return NO;
        CGPoint location = [touch locationInView:gesture.view];
        if (location.y > CGRectGetHeight(gesture.view.bounds) - MAX(92.0, gesture.view.safeAreaInsets.bottom + 68.0)) return NO;
        UIView *candidate = touch.view;
        while (candidate) {
            if (candidate.tag == kCCAPageIndicatorHostTag || candidate.tag == kCCARemoveButtonTag ||
                candidate.tag == kCCAResizeButtonTag || candidate.tag == kCCAAddControlButtonTag || candidate.tag == 181000) return NO;
            NSString *name = NSStringFromClass(candidate.class);
            if ([name containsString:@"Slider"]) return NO;
            candidate = candidate.superview;
        }
        if (gEditModeActive) {
            UIViewController *overlay = gOverlayControllers.allObjects.firstObject;
            CGPoint point = [touch locationInView:overlay.view];
            for (UIViewController *module in CCACollectModuleControllers(overlay)) {
                if (module.view.hidden || module.view.alpha <= 0.01 || CCAModuleViewIsPageHidden(module.view)) continue;
                if (CGRectContainsPoint(CGRectInset(CCAVisibleModuleFrame(module, overlay), -8.0, -8.0), point)) return NO;
            }
        }
        return YES;
    }
    if ([objc_getAssociatedObject(gesture, @selector(blankHeld:)) boolValue]) {
        if (gEditModeActive || gCCAExpandedModuleOpen) return NO;
        UIViewController *overlay = gOverlayControllers.allObjects.firstObject;
        CGPoint point = [touch locationInView:overlay.view];
        for (UIViewController *module in CCACollectModuleControllers(overlay)) {
            if (module.view.hidden || module.view.alpha <= 0.01 || CCAModuleViewIsPageHidden(module.view)) continue;
            if (CGRectContainsPoint(CGRectInset(CCAVisibleModuleFrame(module, overlay), -2.0, -2.0), point)) return NO;
        }
    }
    if ([objc_getAssociatedObject(gesture, @selector(modulePanned:)) isEqual:@"overlayPan"]) {
        if (!gEditModeActive) return NO;
        CGPoint location = [touch locationInView:gesture.view];
        if (location.y > CGRectGetHeight(gesture.view.bounds) - MAX(92.0, gesture.view.safeAreaInsets.bottom + 68.0)) return NO;
        UIView *touchedView = touch.view;
        while (touchedView) {
            if (touchedView.tag == kCCAResizeButtonTag || touchedView.tag == kCCARemoveButtonTag) return NO;
            touchedView = touchedView.superview;
        }
        UIViewController *overlay = nil;
        UIResponder *responder = gesture.view;
        while (responder && ![responder isKindOfClass:[UIViewController class]]) responder = responder.nextResponder;
        if ([responder isKindOfClass:[UIViewController class]]) overlay = (UIViewController *)responder;
        CGPoint point = [touch locationInView:overlay.view];
        // Geometric chrome guard: the tag walk above depends on hit-testing
        // having routed the touch to the button. If any other view claimed it,
        // a touch inside a remove/resize footprint must still never start a
        // drag; it would cancel the button's tap and shrink the module.
        // Non-generous zones keep 1x1 modules grabbable next to their handle.
        if ([self pointHitsEditChrome:point overlay:overlay generous:NO]) return NO;
        for (UIViewController *module in CCACollectModuleControllers(overlay)) {
            if (module.view.hidden || module.view.alpha <= 0.01 || CCAModuleViewIsPageHidden(module.view)) continue;
            CGRect frame = CCAVisibleModuleFrame(module, overlay);
            if (CGRectContainsPoint(CGRectInset(frame, -14.0, -14.0), point)) return YES;
        }
        return NO;
    }
    if (gesture.view.tag == kCCAResizeButtonTag) {
        return gEditModeActive && !gCCAExpandedModuleOpen && !gCCADragInProgress;
    }
    if ([objc_getAssociatedObject(gesture, @selector(editShieldTapped:)) boolValue]) {
        if (!gEditModeActive || gCCAExpandedModuleOpen || gCCADragInProgress || gCCAResizeInProgress) return NO;
        UIViewController *overlay = gOverlayControllers.allObjects.firstObject;
        CGPoint location = [touch locationInView:overlay.view];
        return [self removeButtonAtPoint:location overlay:overlay] != nil;
    }
    UIView *view = touch.view;
    if ([gesture isKindOfClass:[UITapGestureRecognizer class]]) {
        if (!gEditModeActive) return NO;
        CGPoint overlayLocation = [touch locationInView:gesture.view];
        if (overlayLocation.y > CGRectGetHeight(gesture.view.bounds) - MAX(92.0, gesture.view.safeAreaInsets.bottom + 68.0)) return NO;
        if (view.tag == kCCAEditTouchShieldTag) {
            UIViewController *overlay = gOverlayControllers.allObjects.firstObject;
            CGPoint location = [touch locationInView:overlay.view];
            UIButton *addControl = (UIButton *)[overlay.view viewWithTag:kCCAAddControlButtonTag];
            if (addControl && !addControl.hidden && CGRectContainsPoint(CGRectInset(addControl.frame, -12.0, -12.0), location)) return NO;
            // A near-miss on the remove bubble or resize grabber must reach
            // the control (or do nothing) — never read as a blank-space tap
            // that exits edit mode.
            if ([self pointHitsEditChrome:location overlay:overlay generous:YES]) return NO;
            for (UIViewController *module in CCACollectModuleControllers(overlay)) {
                if (module.view.hidden || module.view.alpha <= 0.01 || CCAModuleViewIsPageHidden(module.view)) continue;
                CGRect frame = CCAVisibleModuleFrame(module, overlay);
                if (CGRectContainsPoint(CGRectInset(frame, -14.0, -14.0), location)) return NO;
            }
            return YES;
        }
        while (view) {
            if (view.tag == 181000 || view.tag == kCCARemoveButtonTag || view.tag == kCCAResizeButtonTag) return NO;
            if (view.tag == kCCAAddControlButtonTag) return NO;
            if (view.tag == kCCAEditShieldTag) return NO;
            view = view.superview;
        }
        return YES;
    }
    while (view) {
        if ([view isKindOfClass:[UIControl class]] || view.tag == 181000) return NO;
        view = view.superview;
    }
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGesture {
    if ([objc_getAssociatedObject(gesture, kCCAEditDismissPanKey) boolValue] || [objc_getAssociatedObject(otherGesture, kCCAEditDismissPanKey) boolValue]) return NO;
    if (gesture.view.tag == kCCAResizeButtonTag || otherGesture.view.tag == kCCAResizeButtonTag || gCCAResizeInProgress) return NO;
    BOOL gestureIsPager = [objc_getAssociatedObject(gesture, kCCAPagerGestureKey) boolValue];
    BOOL otherIsPager = [objc_getAssociatedObject(otherGesture, kCCAPagerGestureKey) boolValue];
    BOOL gestureIsModulePan = [objc_getAssociatedObject(gesture, @selector(modulePanned:)) isEqual:@"overlayPan"];
    BOOL otherIsModulePan = [objc_getAssociatedObject(otherGesture, @selector(modulePanned:)) isEqual:@"overlayPan"];
    if ((gestureIsPager && otherIsModulePan) || (otherIsPager && gestureIsModulePan) || gCCADragInProgress) return NO;
    if (gestureIsPager || otherIsPager) return YES;
    return NO;
}

- (void)addTapped:(__unused UIButton *)sender { if (!gEnabled || gCCAExpandedModuleOpen || (!gEditModeActive && CCAIsLandscapeOrientation(sender))) return; CCAHaptic(); [self setEditing:!gEditModeActive]; }
- (void)expandConnectivityFromMiniCluster:(UIButton *)sender {
    if (!gEnabled || gEditModeActive || gCCAExpandedModuleOpen) return;
    UIViewController *overlay = gOverlayControllers.allObjects.firstObject;
    UIViewController *collection = [self moduleCollectionControllerInOverlay:overlay];
    SEL expand = NSSelectorFromString(@"expandModuleWithIdentifier:");
    if (!collection || ![collection respondsToSelector:expand]) return;
    UIView *sourceView = sender.superview ?: sender;
    if (sourceView.window) {
        gCCAConnectivityProxySourceView = sourceView;
        gCCAConnectivityProxySourceWindowFrame = CCAConnectivityScreenFrameForView(sourceView);
        gCCAConnectivityProxySourceCornerRadius = sourceView.layer.cornerRadius > 1.0 ? sourceView.layer.cornerRadius : 32.0;
        gCCAConnectivityHasProxySourceFrame = CGRectGetWidth(gCCAConnectivityProxySourceWindowFrame) > 1.0 &&
                                             CGRectGetHeight(gCCAConnectivityProxySourceWindowFrame) > 1.0;
        gCCAConnectivityProxyExpansionActive = gCCAConnectivityHasProxySourceFrame;
    } else {
        gCCAConnectivityProxySourceView = nil;
        gCCAConnectivityProxySourceWindowFrame = CGRectZero;
        gCCAConnectivityProxySourceCornerRadius = 32.0;
        gCCAConnectivityHasProxySourceFrame = NO;
        gCCAConnectivityProxyExpansionActive = NO;
    }
    CCAHaptic();
    ((void (*)(id, SEL, id))objc_msgSend)((id)collection, expand, @"com.apple.control-center.ConnectivityModule");
}
- (void)openVPNSettings:(__unused UIControl *)sender {
    NSURL *url = [NSURL URLWithString:@"App-prefs:root=General&path=VPN"];
    if (!url) return;
    CCAHaptic();
    [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
}
- (void)connectivityProxyTapped:(UIControl *)sender {
    UIControl *nativeControl = objc_getAssociatedObject(sender, kCCAConnectivityForwardControlKey);
    if (!nativeControl) return;
    [nativeControl sendActionsForControlEvents:UIControlEventTouchUpInside];
}
- (void)connectivityTileProxyTouchDown:(UIControl *)sender {
    CCASetConnectivityProxyPressed(sender, YES);
}
- (void)connectivityTileProxyTouchUp:(UIControl *)sender {
    CCASetConnectivityProxyPressed(sender, NO);
}
- (void)connectivityTileProxyTapped:(UIControl *)sender {
    if (gEditModeActive || gCCAExpandedModuleOpen) return;
    if (![objc_getAssociatedObject(sender, @selector(connectivityTileProxyTapped:)) boolValue]) return;
    NSString *identifier = objc_getAssociatedObject(sender, kCCAConnectivityIdentifierKey);
    if ([identifier.lowercaseString containsString:@".airdrop"]) {
        CCASetConnectivityProxyPressed(sender, NO);
        [self expandConnectivityFromMiniCluster:(UIButton *)sender];
        return;
    }
    BOOL current = CCAConnectivitySelectedForIdentifier(identifier);
    BOOL target = !current;
    CCASetConnectivityProxyPressed(sender, NO);
    BOOL changed = NO;
    if (identifier.length) {
        changed = CCAConnectivitySetIdentifier(identifier, target);
    }
    UIControl *nativeControl = objc_getAssociatedObject(sender, kCCAConnectivityForwardControlKey);
    CCAHaptic();
    if (changed && identifier.length) {
        gCCAConnectivityOptimisticStates[identifier] = @(target);
        for (UIViewController *candidateOverlay in gOverlayControllers.allObjects) {
            for (UIViewController *module in CCACollectModuleControllers(candidateOverlay)) {
                if ([CCAModuleIdentifier(module) isEqualToString:identifier]) CCAConfigureOddResizedModuleLayout(module);
            }
        }
        for (NSNumber *delay in @[@0.22, @0.48, @0.82, @1.25]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (delay.doubleValue >= 1.2) [gCCAConnectivityOptimisticStates removeObjectForKey:identifier];
                for (UIViewController *candidateOverlay in gOverlayControllers.allObjects) {
                    for (UIViewController *module in CCACollectModuleControllers(candidateOverlay)) {
                        if ([CCAModuleIdentifier(module) isEqualToString:identifier]) CCAConfigureOddResizedModuleLayout(module);
                    }
                }
            });
        }
    } else {
        if (nativeControl) [nativeControl sendActionsForControlEvents:UIControlEventTouchUpInside];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.38 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            for (UIViewController *overlay in gOverlayControllers.allObjects) {
                for (UIViewController *module in CCACollectModuleControllers(overlay)) {
                    if ([CCAModuleIdentifier(module).lowercaseString containsString:@"ccaster.connectivity"]) {
                        CCAConfigureOddResizedModuleLayout(module);
                    }
                }
            }
        });
    }
}
- (void)connectivityTileProxyHeld:(UILongPressGestureRecognizer *)gesture {
    if (gesture && gesture.state != UIGestureRecognizerStateBegan) return;
    if (gEditModeActive || gCCAExpandedModuleOpen) return;
    UIControl *sender = [gesture.view isKindOfClass:[UIControl class]] ? (UIControl *)gesture.view : nil;
    NSString *identifier = sender ? objc_getAssociatedObject(sender, kCCAConnectivityIdentifierKey) : nil;
    if (CCAConnectivityIdentifierHasExpandedMenu(identifier)) {
        [self expandConnectivityFromMiniCluster:(UIButton *)sender];
        return;
    }
    CCAHaptic();
}
- (void)connectivityTileProxyForcePressed:(UIControl *)sender {
    if (gEditModeActive || gCCAExpandedModuleOpen) return;
    NSString *identifier = sender ? objc_getAssociatedObject(sender, kCCAConnectivityIdentifierKey) : nil;
    if (CCAConnectivityIdentifierHasExpandedMenu(identifier)) {
        gCCAConnectivityPendingDetailIdentifier = identifier.copy;
        [self expandConnectivityFromMiniCluster:(UIButton *)sender];
        return;
    }
    CCAHaptic();
}
- (void)ignoreTap:(__unused UIButton *)sender {}
- (void)blankHeld:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan && !gEditModeActive && !gCCAExpandedModuleOpen && !CCAIsLandscapeOrientation(gesture.view)) {
        CCAHaptic();
        [self setEditing:YES];
    }
}
- (void)editExitTapped:(UITapGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateRecognized && gEditModeActive) {
        CCAHaptic();
        [self setEditing:NO];
    }
}

- (void)editShieldTapped:(UITapGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateRecognized || !gEditModeActive || gCCAExpandedModuleOpen) return;
    UIViewController *overlay = gOverlayControllers.allObjects.firstObject;
    CGPoint point = [gesture locationInView:overlay.view];
    UIButton *remove = [self removeButtonAtPoint:point overlay:overlay];
    if (remove) [self removeTapped:remove];
}

- (void)editDismissPanned:(UIPanGestureRecognizer *)gesture {
    if (!gEditModeActive || gCCAExpandedModuleOpen) return;
    if (gesture.state == UIGestureRecognizerStateBegan) {
        CCAHaptic();
        gCCAEditExitConsumedUntil = CACurrentMediaTime() + 0.9;
        // The native home gesture races this pan and drives presentation
        // callbacks that clobber an animated exit; leave editing atomically.
        [self dismissEditingImmediately];
        gesture.enabled = NO;
        gesture.enabled = YES;
    }
}

- (void)powerHeld:(UILongPressGestureRecognizer *)gesture {
    UIButton *button = (UIButton *)gesture.view;
    UIView *material = [button viewWithTag:kCCAPowerMaterialTag];
    if (gesture.state == UIGestureRecognizerStateBegan) {
        CCAHaptic();
        [UIView animateWithDuration:0.55 delay:0.0 options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionBeginFromCurrentState animations:^{
            material.alpha = 1.0;
            button.transform = CGAffineTransformMakeScale(1.07, 1.07);
        } completion:^(__unused BOOL finished) {
            Class factoryClass = NSClassFromString(@"SBUIPowerDownViewControllerFactory");
            SEL factorySelector = NSSelectorFromString(@"newPowerDownViewController");
            UIViewController *powerController = nil;
            if ([factoryClass respondsToSelector:factorySelector]) {
                powerController = ((id (*)(id, SEL))objc_msgSend)(factoryClass, factorySelector);
            }
            UIViewController *presenter = gOverlayControllers.allObjects.firstObject;
            if (powerController && presenter && !presenter.presentedViewController) {
                powerController.modalPresentationStyle = UIModalPresentationFullScreen;
                [presenter presentViewController:powerController animated:YES completion:nil];
            }
        }];
    } else if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled || gesture.state == UIGestureRecognizerStateFailed) {
        [UIView animateWithDuration:0.2 delay:0.0 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState animations:^{
            material.alpha = 1.0;
            button.transform = CGAffineTransformIdentity;
        } completion:nil];
    }
}

- (id)moduleSettingsProvider {
    Class providerClass = NSClassFromString(@"CCSModuleSettingsProvider");
    SEL selector = NSSelectorFromString(@"sharedProvider");
    return [providerClass respondsToSelector:selector] ? ((id (*)(id, SEL))objc_msgSend)(providerClass, selector) : nil;
}

- (NSArray<NSString *> *)enabledModuleIdentifiers {
    id provider = [self moduleSettingsProvider];
    SEL selector = NSSelectorFromString(@"orderedUserEnabledModuleIdentifiers");
    return [provider respondsToSelector:selector] ? ((id (*)(id, SEL))objc_msgSend)(provider, selector) : @[];
}

- (void)saveEnabledModuleIdentifiers:(NSArray<NSString *> *)identifiers {
    id provider = [self moduleSettingsProvider];
    SEL selector = NSSelectorFromString(@"setAndSaveOrderedUserEnabledModuleIdentifiers:");
    if ([provider respondsToSelector:selector]) ((void (*)(id, SEL, id))objc_msgSend)(provider, selector, identifiers);
}

- (NSArray<NSString *> *)fixedModuleIdentifiers {
    id provider = [self moduleSettingsProvider];
    SEL selector = NSSelectorFromString(@"orderedFixedModuleIdentifiers");
    return [provider respondsToSelector:selector] ? ((id (*)(id, SEL))objc_msgSend)(provider, selector) : @[];
}

- (UIButton *)addControlButtonForOverlay:(UIViewController *)overlay {
    UIButton *button = (UIButton *)[overlay.view viewWithTag:kCCAAddControlButtonTag];
    if (button) return button;
    button = [CCAExpandedHitButton buttonWithType:UIButtonTypeCustom];
    button.tag = kCCAAddControlButtonTag;
    button.accessibilityIdentifier = @"CCAsterAddControlButton";
    button.backgroundColor = UIColor.clearColor;
    button.tintColor = UIColor.whiteColor;
    UIImageSymbolConfiguration *symbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:10.0 weight:UIImageSymbolWeightSemibold];
    UIButtonConfiguration *configuration = [UIButtonConfiguration plainButtonConfiguration];
    configuration.image = [UIImage systemImageNamed:@"plus.circle.fill" withConfiguration:symbolConfiguration];
    configuration.attributedTitle = [[NSAttributedString alloc] initWithString:@"Add a Control" attributes:@{
        NSFontAttributeName: [UIFont systemFontOfSize:12.5 weight:UIFontWeightSemibold],
        NSForegroundColorAttributeName: UIColor.whiteColor,
    }];
    configuration.baseForegroundColor = UIColor.whiteColor;
    configuration.imagePadding = 4.0;
    configuration.contentInsets = NSDirectionalEdgeInsetsMake(6.0, 10.0, 6.0, 14.0);
    button.configuration = configuration;
    [button addTarget:self action:@selector(addControlTapped:) forControlEvents:UIControlEventTouchUpInside];
    button.alpha = 0.0;
    button.hidden = YES;
    [overlay.view addSubview:button];
    return button;
}

- (void)captureSheetSourceSnapshotForOverlay:(UIViewController *)overlay {
    gCCASheetScreenImage = nil;
    gCCASheetModuleFrames = nil;
    if (!overlay.view.window) return;
    // Materials (platters, slider fills, tints) only exist composited in the
    // framebuffer — live snapshot views lose them across windows and
    // drawViewHierarchyInRect never renders them. Grab the real screen with
    // CCAster's edit chrome hidden for one committed frame, then crop modules.
    NSMutableArray<UIView *> *hiddenViews = [NSMutableArray array];
    NSMutableArray<NSDictionary *> *detachedBorders = [NSMutableArray array];
    void (^hideView)(UIView *) = ^(UIView *view) {
        if (view && !view.hidden) {
            view.hidden = YES;
            [hiddenViews addObject:view];
        }
    };
    NSMutableDictionary<NSNumber *, CCAEditGridView *> *pageGrids = objc_getAssociatedObject(overlay, kCCAEditPageGridsKey);
    for (CCAEditGridView *grid in pageGrids.allValues) hideView(grid);
    hideView(objc_getAssociatedObject(overlay, kCCAEditGridKey));
    hideView([overlay.view viewWithTag:kCCAAddControlButtonTag]);
    for (UIView *subview in overlay.view.subviews) {
        if (subview.tag == kCCARemoveButtonTag || subview.tag == kCCAResizeButtonTag) hideView(subview);
    }
    NSMutableDictionary<NSString *, NSValue *> *frames = [NSMutableDictionary dictionary];
    for (UIViewController *module in CCACollectModuleControllers(overlay)) {
        hideView(objc_getAssociatedObject(module.view, kCCARemoveButtonKey));
        hideView(objc_getAssociatedObject(module.view, kCCAResizeButtonKey));
        UIView *border = objc_getAssociatedObject(module.view, @selector(applyEditingToModule:editing:));
        UIView *borderParent = border.superview;
        if (borderParent) {
            NSUInteger borderIndex = [borderParent.subviews indexOfObjectIdenticalTo:border];
            [detachedBorders addObject:@{
                @"view": border,
                @"parent": borderParent,
                @"index": @(borderIndex == NSNotFound ? borderParent.subviews.count : borderIndex),
            }];
            // The breathing ring has an active presentation layer. Merely
            // hiding its model view can leave one composited frame in the
            // framebuffer crop, so detach it for the gallery snapshot.
            [border removeFromSuperview];
        }
        NSString *identifier = CCAModuleIdentifier(module);
        if (identifier.length && module.view.window && !CGRectIsEmpty(module.view.bounds)) {
            frames[identifier] = [NSValue valueWithCGRect:[module.view convertRect:module.view.bounds toView:nil]];
        }
    }
    [overlay.view.window layoutIfNeeded];
    [CATransaction flush];
    UIView *screenSnapshot = [UIScreen.mainScreen snapshotViewAfterScreenUpdates:YES];
    UIImage *screenImage = nil;
    if (screenSnapshot) {
        [overlay.view.window addSubview:screenSnapshot];
        @try {
            UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithBounds:screenSnapshot.bounds];
            screenImage = [renderer imageWithActions:^(__unused UIGraphicsImageRendererContext *context) {
                [screenSnapshot drawViewHierarchyInRect:screenSnapshot.bounds afterScreenUpdates:YES];
            }];
        } @catch (__unused NSException *exception) { screenImage = nil; }
        [screenSnapshot removeFromSuperview];
    }
    for (NSDictionary *record in detachedBorders) {
        UIView *view = record[@"view"];
        UIView *parent = record[@"parent"];
        NSUInteger index = MIN([record[@"index"] unsignedIntegerValue], parent.subviews.count);
        [parent insertSubview:view atIndex:index];
    }
    for (UIView *view in hiddenViews) view.hidden = NO;
    gCCASheetScreenImage = screenImage;
    gCCASheetModuleFrames = screenImage ? [frames copy] : nil;
}

- (void)addControlTapped:(UIButton *)sender {
    if (!gEnabled || !gEditModeActive) return;
    UIViewController *overlay = gOverlayControllers.allObjects.firstObject;
    if (!overlay || overlay.presentedViewController) return;
    CCAHaptic();
    sender.enabled = NO;
    dispatch_async(dispatch_get_main_queue(), ^{
        sender.enabled = YES;
        if (!gEnabled || !gEditModeActive || overlay.presentedViewController) return;
        CCAAddControlSheetViewController *sheet = [CCAAddControlSheetViewController new];
        sheet.catalog = [self availableControlCatalog];
        sheet.modalPresentationStyle = UIModalPresentationPageSheet;
        UISheetPresentationController *presentation = sheet.sheetPresentationController;
        presentation.detents = @[UISheetPresentationControllerDetent.largeDetent];
        presentation.prefersGrabberVisible = YES;
        presentation.preferredCornerRadius = 30.0;
        gCCAAddSheetPresentationActive = YES;
        [overlay presentViewController:sheet animated:YES completion:^{
            gCCAAddSheetPresentationActive = NO;
        }];
    });
}

- (NSArray<NSDictionary *> *)availableControlCatalog {
    NSArray<NSString *> *enabled = [self enabledModuleIdentifiers];
    NSMutableSet<NSString *> *present = [NSMutableSet setWithArray:enabled ?: @[]];
    [present addObjectsFromArray:[self fixedModuleIdentifiers]];
    UIViewController *overlay = gOverlayControllers.allObjects.firstObject;
    for (UIViewController *module in CCACollectModuleControllers(overlay)) {
        NSString *identifier = CCAModuleIdentifier(module);
        if (identifier.length) [present addObject:identifier];
    }

    NSMutableOrderedSet<NSString *> *identifiers = [NSMutableOrderedSet orderedSet];
    NSMutableDictionary<NSString *, NSURL *> *bundleURLs = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSString *> *names = [NSMutableDictionary dictionary];

    Class managerClass = NSClassFromString(@"CCUIModuleInstanceManager");
    SEL sharedSelector = NSSelectorFromString(@"sharedInstance");
    id manager = [managerClass respondsToSelector:sharedSelector] ? ((id (*)(id, SEL))objc_msgSend)(managerClass, sharedSelector) : nil;
    id repository = nil;
    for (NSString *key in @[@"_repository", @"repository", @"_moduleRepository", @"moduleRepository"]) {
        @try { repository = [manager valueForKey:key]; } @catch (__unused NSException *exception) {}
        if (repository) break;
    }
    NSArray *allMetadata = nil;
    for (NSString *key in @[@"allModuleMetadata", @"_allModuleMetadata", @"moduleMetadata", @"_moduleMetadata"]) {
        @try {
            id value = [repository valueForKey:key];
            if ([value isKindOfClass:[NSArray class]] && [(NSArray *)value count]) { allMetadata = value; break; }
        } @catch (__unused NSException *exception) {}
    }
    for (id metadata in allMetadata) {
        NSString *identifier = nil;
        for (NSString *key in @[@"moduleIdentifier", @"identifier"]) {
            @try {
                id value = [metadata valueForKey:key];
                if ([value isKindOfClass:[NSString class]] && [value length]) { identifier = value; break; }
            } @catch (__unused NSException *exception) {}
        }
        if (!identifier.length) continue;
        if (CCAIdentifierIsLegacyPhysicalDuplicate(identifier)) continue;
        [identifiers addObject:identifier];
        for (NSString *key in @[@"moduleBundleURL", @"bundleURL", @"URL", @"url"]) {
            @try {
                id value = [metadata valueForKey:key];
                if ([value isKindOfClass:[NSURL class]]) { bundleURLs[identifier] = value; break; }
            } @catch (__unused NSException *exception) {}
        }
        @try {
            id value = [metadata valueForKey:@"displayName"];
            if ([value isKindOfClass:[NSString class]] && [value length]) names[identifier] = value;
        } @catch (__unused NSException *exception) {}
    }
    // The live repository object only reliably exposes instantiated modules.
    // The authoritative catalog is the module bundles on disk, exactly what
    // Settings > Control Center offers.
    NSArray<NSString *> *bundleDirectories = @[
        @"/System/Library/ControlCenter/Bundles",
        @"/Library/ControlCenter/Bundles",
        @"/var/jb/Library/ControlCenter/Bundles",
    ];
    for (NSString *directory in bundleDirectories) {
        for (NSString *item in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:directory error:nil]) {
            if (![item.pathExtension isEqualToString:@"bundle"]) continue;
            NSBundle *bundle = [NSBundle bundleWithPath:[directory stringByAppendingPathComponent:item]];
            NSString *identifier = bundle.bundleIdentifier;
            if (!identifier.length) continue;
            if (CCAIdentifierIsLegacyPhysicalDuplicate(identifier)) continue;
            [identifiers addObject:identifier];
            if (!bundleURLs[identifier]) bundleURLs[identifier] = bundle.bundleURL;
            if (!names[identifier]) {
                // CFBundleName is the executable name ("OrientationLockModule")
                // and reads as junk; only the display name is trustworthy.
                id displayName = bundle.localizedInfoDictionary[@"CFBundleDisplayName"] ?: bundle.infoDictionary[@"CFBundleDisplayName"];
                if ([displayName isKindOfClass:[NSString class]] && [displayName length]) names[identifier] = displayName;
            }
        }
    }
    // The repository can omit fixed system modules; make sure everything that
    // is visibly part of Control Center still appears (dimmed) in the sheet.
    for (NSString *identifier in [self fixedModuleIdentifiers]) if (!CCAIdentifierIsLegacyPhysicalDuplicate(identifier)) [identifiers addObject:identifier];
    for (NSString *identifier in enabled) if (!CCAIdentifierIsLegacyPhysicalDuplicate(identifier)) [identifiers addObject:identifier];

    NSMutableArray<NSDictionary *> *catalog = [NSMutableArray array];
    for (NSString *identifier in identifiers) {
        // Call-managed conference modules appear and disappear with the call;
        // real iOS never offers them in the gallery either. ContinuousExpose
        // (iPad Stage Manager) and PerformanceTrace (internal) are noise here.
        if ([identifier localizedCaseInsensitiveContainsString:@"conference"] ||
            [identifier localizedCaseInsensitiveContainsString:@"continuousexpose"] ||
            [identifier localizedCaseInsensitiveContainsString:@"performancetrace"] ||
            CCAIdentifierIsLegacyPhysicalDuplicate(identifier)) continue;
        NSString *name = CCAFriendlyNameForIdentifier(identifier);
        if (!name.length) name = names[identifier];
        if (!name.length && overlay) {
            for (UIViewController *module in CCACollectModuleControllers(overlay)) {
                if (![CCAModuleIdentifier(module) isEqualToString:identifier]) continue;
                UIView *buttonView = CCAFindSubviewWithClassName(module.view, @"CCUIButtonModuleView");
                if (buttonView.accessibilityLabel.length) name = buttonView.accessibilityLabel;
                break;
            }
        }
        if (!name.length) name = CCAPrettyNameForIdentifier(identifier);
        // Unlocalized executable names still slip through repository metadata.
        if ([name hasSuffix:@"Module"] && ![name containsString:@" "]) name = CCAPrettyNameForIdentifier(identifier);
        NSString *bundlePath = bundleURLs[identifier].path ?: @"";
        BOOL isTweak = bundlePath.length && ![bundlePath hasPrefix:@"/System/"];
        NSString *category = CCACategoryForIdentifier(identifier);
        BOOL allowsMultiple = CCAModuleIdentifierSupportsOwnedDuplicates(identifier);
        NSUInteger instanceCount = allowsMultiple ? CCADuplicateCountForFamily(identifier, present) : 0;
        [catalog addObject:@{
            @"identifier": identifier,
            @"name": name,
            @"category": (isTweak && [category isEqualToString:@"Utilities"]) ? @"Tweaks" : category,
            @"added": @([present containsObject:identifier]),
            @"allowsMultiple": @(allowsMultiple),
            @"instanceCount": @(instanceCount),
            @"bundleURL": bundleURLs[identifier] ?: (id)NSNull.null,
        }];
    }
    // Stable alphabetical order — a module's position never changes based on
    // whether it is currently added.
    [catalog sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
        return [left[@"name"] localizedCaseInsensitiveCompare:right[@"name"]];
    }];
    return catalog;
}

- (CCUILayoutSize)catalogLayoutSizeForIdentifier:(NSString *)identifier {
    NSValue *baseValue = gCCABaseLayoutSizes[identifier];
    if (baseValue) {
        CCUILayoutSize base = {};
        [baseValue getValue:&base];
        if (base.width && base.height) return base;
    }
    NSDictionary<NSString *, NSArray<NSNumber *> *> *known = @{
        @"com.futur3sn0w.ccaster.connectivity.airplane": @[@1, @1],
        @"com.futur3sn0w.ccaster.connectivity.wifi": @[@1, @1],
        @"com.futur3sn0w.ccaster.connectivity.airdrop": @[@1, @1],
        @"com.futur3sn0w.ccaster.connectivity.cellular": @[@1, @1],
        @"com.futur3sn0w.ccaster.connectivity.bluetooth": @[@1, @1],
        @"com.futur3sn0w.ccaster.connectivity.hotspot": @[@1, @1],
        @"com.futur3sn0w.ccaster.connectivity.vpn": @[@1, @1],
        @"com.apple.control-center.ConnectivityModule": @[@2, @2],
        @"com.apple.mediaremote.controlcenter.nowplaying": @[@2, @2],
        @"com.apple.mediaremote.controlcenter.audio": @[@1, @2],
        @"com.apple.control-center.DisplayModule": @[@1, @2],
    };
    NSArray<NSNumber *> *dims = known[identifier];
    if (dims.count >= 2) return (CCUILayoutSize){dims[0].unsignedIntegerValue, dims[1].unsignedIntegerValue};
    return (CCUILayoutSize){1, 1};
}

- (CGSize)catalogPointSizeForLayoutSize:(CCUILayoutSize)size {
    CGFloat cell = kCCAGridCellSize, gap = kCCAGridGap;
    return CGSizeMake(cell * size.width + gap * (size.width - 1), cell * size.height + gap * (size.height - 1));
}

- (NSArray<NSDictionary *> *)temporarilyRevealModuleForSheetSnapshot:(UIView *)moduleView {
    if (!moduleView) return @[];
    NSMutableArray<NSDictionary *> *records = [NSMutableArray array];
    void (^captureView)(UIView *) = ^(UIView *view) {
        if (!view) return;
        id pageHidden = objc_getAssociatedObject(view, kCCAPageHiddenKey);
        [records addObject:@{
            @"view": view,
            @"hidden": @(view.hidden),
            @"alpha": @(view.alpha),
            @"opacity": @(view.layer.opacity),
            @"pageHidden": pageHidden ?: NSNull.null,
        }];
        view.hidden = NO;
        view.alpha = 1.0;
        view.layer.opacity = 1.0;
        if (pageHidden) objc_setAssociatedObject(view, kCCAPageHiddenKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    };
    captureView(moduleView.superview);
    captureView(moduleView);
    return records;
}

- (void)restoreModuleSheetSnapshotState:(NSArray<NSDictionary *> *)records {
    for (NSDictionary *record in records.reverseObjectEnumerator) {
        UIView *view = record[@"view"];
        if (![view isKindOfClass:[UIView class]]) continue;
        view.hidden = [record[@"hidden"] boolValue];
        view.alpha = [record[@"alpha"] doubleValue];
        view.layer.opacity = [record[@"opacity"] floatValue];
        id pageHidden = record[@"pageHidden"];
        objc_setAssociatedObject(view, kCCAPageHiddenKey, pageHidden == NSNull.null ? nil : pageHidden, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

- (UIView *)editChromeHostForModuleView:(UIView *)moduleView overlay:(UIViewController *)overlay {
    UIView *host = moduleView.superview ?: overlay.view;
    host.clipsToBounds = NO;
    return host;
}

- (void)positionEditControlsForModuleView:(UIView *)moduleView overlay:(UIViewController *)overlay overlayFrame:(CGRect)overlayFrame {
    if (!moduleView) return;
    UIButton *remove = objc_getAssociatedObject(moduleView, kCCARemoveButtonKey);
    UIButton *resize = objc_getAssociatedObject(moduleView, kCCAResizeButtonKey);
    if (remove) {
        UIView *removeHost = remove.superview ?: [self editChromeHostForModuleView:moduleView overlay:overlay];
        CGRect removeHostFrame = overlay.view ? [overlay.view convertRect:overlayFrame toView:removeHost] : [moduleView convertRect:moduleView.bounds toView:removeHost];
        remove.frame = CCARemoveButtonFrameForModuleFrame(removeHostFrame);
    }
    if (resize) {
        UIView *resizeHost = resize.superview ?: overlay.view ?: [self editChromeHostForModuleView:moduleView overlay:overlay];
        CGRect resizeHostFrame = overlay.view ? [overlay.view convertRect:overlayFrame toView:resizeHost] : [moduleView convertRect:moduleView.bounds toView:resizeHost];
        resize.frame = CGRectMake(CGRectGetMaxX(resizeHostFrame) - 42.0, CGRectGetMaxY(resizeHostFrame) - 42.0, 42.0, 42.0);
    }
}

// Shared chrome hit test: YES when the point lands inside a visible
// remove/resize control. `generous` pads the zones (used to keep taps from
// slipping past chrome and exiting edit mode); non-generous shrinks the
// resize zone on 1x1 modules so their tiny surface stays grabbable.
- (BOOL)pointHitsEditChrome:(CGPoint)point overlay:(UIViewController *)overlay generous:(BOOL)generous {
    for (UIViewController *module in CCACollectModuleControllers(overlay)) {
        if (module.view.hidden || module.view.alpha <= 0.01 || CCAModuleViewIsPageHidden(module.view)) continue;
        UIButton *removeChrome = objc_getAssociatedObject(module.view, kCCARemoveButtonKey);
        UIButton *resizeChrome = objc_getAssociatedObject(module.view, kCCAResizeButtonKey);
        // Resize grabber: a tight bottom-right corner that always keeps priority
        // over a drag (matches CCAExpandedHitButton's own corner acceptance).
        if (resizeChrome && !resizeChrome.hidden && resizeChrome.alpha > 0.01 && resizeChrome.userInteractionEnabled && resizeChrome.superview) {
            BOOL small = [objc_getAssociatedObject(resizeChrome, kCCASmallModuleChromeKey) boolValue];
            CGRect frame = [resizeChrome.superview convertRect:resizeChrome.frame toView:overlay.view];
            CGFloat cornerSize = small ? 26.0 : 34.0;
            CGRect hitFrame = CGRectMake(CGRectGetMaxX(frame) - cornerSize, CGRectGetMaxY(frame) - cornerSize, cornerSize, cornerSize);
            if (CGRectContainsPoint(hitFrame, point)) return YES;
        }
        // Remove bubble: a purely visual affordance now. It only participates in
        // the generous pass, whose sole job is to stop a near-corner tap from
        // reading as a blank-space tap that exits edit mode. In the non-generous
        // (drag) pass it never blocks, so the top-left stays grabbable and
        // removal is decided heuristically on drop.
        if (generous && removeChrome && !removeChrome.hidden && removeChrome.alpha > 0.01 && removeChrome.superview) {
            CGRect frame = [removeChrome.superview convertRect:removeChrome.frame toView:overlay.view];
            if (CGRectContainsPoint(CGRectInset(frame, -10.0, -10.0), point)) return YES;
        }
    }
    return NO;
}

- (UIButton *)removeButtonAtPoint:(CGPoint)point overlay:(UIViewController *)overlay {
    for (UIViewController *module in CCACollectModuleControllers(overlay)) {
        if (module.view.hidden || module.view.alpha <= 0.01 || CCAModuleViewIsPageHidden(module.view)) continue;
        UIButton *remove = objc_getAssociatedObject(module.view, kCCARemoveButtonKey);
        if (!remove || remove.hidden || remove.alpha <= 0.01 || !remove.userInteractionEnabled || !remove.superview) continue;
        CGRect frame = [remove.superview convertRect:remove.frame toView:overlay.view];
        if (CGRectContainsPoint(CGRectInset(frame, -14.0, -14.0), point)) return remove;
    }
    return nil;
}

- (UIView *)previewViewForCatalogEntry:(NSDictionary *)entry {
    NSString *identifier = entry[@"identifier"];
    CCUILayoutSize layoutSize = [self catalogLayoutSizeForIdentifier:identifier];
    // Third-party (CCSupport-style) modules often declare their size in the
    // bundle's Info.plist rather than through the live provider.
    id bundleProbe = entry[@"bundleURL"];
    if (layoutSize.width == 1 && layoutSize.height == 1 && [bundleProbe isKindOfClass:[NSURL class]]) {
        NSDictionary *info = [NSBundle bundleWithURL:bundleProbe].infoDictionary;
        for (NSString *key in @[@"CCSModuleSize", @"ModuleSize", @"CCModuleSize"]) {
            id value = info[key];
            if (![value isKindOfClass:[NSDictionary class]]) continue;
            id width = value[@"Width"] ?: value[@"width"];
            id height = value[@"Height"] ?: value[@"height"];
            if ([width respondsToSelector:@selector(unsignedIntegerValue)] && [height respondsToSelector:@selector(unsignedIntegerValue)] &&
                [width unsignedIntegerValue] >= 1 && [height unsignedIntegerValue] >= 1) {
                layoutSize = (CCUILayoutSize){MIN(4, (NSUInteger)[width unsignedIntegerValue]), MIN(4, (NSUInteger)[height unsignedIntegerValue])};
                break;
            }
        }
    }
    CGSize pointSize = [self catalogPointSizeForLayoutSize:layoutSize];
    CGFloat radius = [self refinedCornerRadiusForSize:pointSize];

    UIView *container = [[UIView alloc] initWithFrame:(CGRect){CGPointZero, pointSize}];
    container.userInteractionEnabled = NO;
    container.layer.cornerRadius = radius;
    container.layer.cornerCurve = kCACornerCurveContinuous;
    container.clipsToBounds = YES;
    UIVisualEffectView *material = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark]];
    material.frame = container.bounds;
    material.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    material.userInteractionEnabled = NO;
    [container addSubview:material];

    if ([identifier.lowercaseString containsString:@"ccaster.connectivity"]) {
        BOOL selected = CCAConnectivitySelectedForIdentifier(identifier);
        BOOL active = CCAConnectivityActiveForIdentifier(identifier);
        BOOL available = CCAConnectivityAvailableForIdentifier(identifier);
        material.alpha = selected ? 0.0 : (available ? 1.0 : 0.52);
        container.backgroundColor = selected ? [UIColor colorWithWhite:0.96 alpha:(available ? 0.92 : 0.42)] : UIColor.clearColor;
        NSString *title = CCAFriendlyNameForIdentifier(identifier) ?: CCAPrettyNameForIdentifier(identifier);
        NSString *status = CCAConnectivityStatusForIdentifier(identifier);
        NSString *symbol = CCAFallbackSymbolForIdentifier(identifier) ?: @"switch.2";
        UIView *presentation = CCAEnsureOwnedCompactPresentation(container);
        CCALayoutOwnedCompactPresentation(presentation, symbol, title, status, layoutSize);
        UIImage *nativeGlyph = CCAConnectivityStockProxyGlyphImage(identifier);
        UIImageView *ownedGlyph = (UIImageView *)[presentation viewWithTag:kCCAResizePresentationGlyphTag];
        if (nativeGlyph && ownedGlyph) ownedGlyph.image = [nativeGlyph imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        if ([identifier.lowercaseString containsString:@".bluetooth"]) {
            UIView *packageGlyph = CCAEnsureConnectivityBluetoothPackageGlyph(presentation, selected);
            if (ownedGlyph) {
                ownedGlyph.hidden = packageGlyph != nil;
                ownedGlyph.alpha = packageGlyph ? 0.0 : 1.0;
            }
            if (packageGlyph) [presentation bringSubviewToFront:packageGlyph];
        } else {
            UIView *packageGlyph = [presentation viewWithTag:kCCAConnectivityBluetoothPackageGlyphTag];
            packageGlyph.hidden = YES;
            packageGlyph.alpha = 0.0;
            if (ownedGlyph) {
                ownedGlyph.hidden = NO;
                ownedGlyph.alpha = 1.0;
            }
        }
        CCAApplyOwnedCompactPresentationState(presentation, selected, active, CCAConnectivityAccentColorForIdentifier(identifier), NO);
        CCAApplyOwnedCompactPresentationAvailability(presentation, available);
        [container bringSubviewToFront:presentation];
        return container;
    }

    // Not-yet-added modules have no live instance in iOS 16, so instantiate
    // the module bundle's principal class directly for a real, inert render.
    // Constructing a real CCUIContentModuleContext first (the way the instance
    // manager does) lets far more modules initialize with proper glyphs/state.
    UIView *content = nil;
    id bundleValue = entry[@"bundleURL"];
    if ([bundleValue isKindOfClass:[NSURL class]]) {
        @try {
            NSBundle *bundle = [NSBundle bundleWithURL:bundleValue];
            if (bundle && (bundle.isLoaded || [bundle load])) {
                Class principal = bundle.principalClass;
                id context = nil;
                Class contextClass = NSClassFromString(@"CCUIContentModuleContext");
                if (principal && contextClass) {
                    SEL contextInit = NSSelectorFromString(@"initWithModuleIdentifier:");
                    if ([contextClass instancesRespondToSelector:contextInit]) {
                        @try { context = ((id (*)(id, SEL, id))objc_msgSend)([contextClass alloc], contextInit, identifier); } @catch (__unused NSException *exception) { context = nil; }
                    }
                    if (!context) {
                        @try {
                            context = [contextClass new];
                            [context setValue:identifier forKey:@"moduleIdentifier"];
                        } @catch (__unused NSException *exception) { context = nil; }
                    }
                }
                id module = nil;
                SEL moduleContextInit = NSSelectorFromString(@"initWithContentModuleContext:");
                if (principal && context && [principal instancesRespondToSelector:moduleContextInit]) {
                    @try { module = ((id (*)(id, SEL, id))objc_msgSend)([principal alloc], moduleContextInit, context); } @catch (__unused NSException *exception) { module = nil; }
                }
                if (principal && !module) {
                    @try { module = [[principal alloc] init]; } @catch (__unused NSException *exception) { module = nil; }
                }
                if (module && context) {
                    @try {
                        SEL setContext = NSSelectorFromString(@"setContentModuleContext:");
                        if ([module respondsToSelector:setContext]) ((void (*)(id, SEL, id))objc_msgSend)(module, setContext, context);
                    } @catch (__unused NSException *exception) {}
                }
                UIViewController *contentController = nil;
                if ([module isKindOfClass:[UIViewController class]]) contentController = module;
                else if ([module respondsToSelector:NSSelectorFromString(@"contentViewController")]) {
                    @try { contentController = ((id (*)(id, SEL))objc_msgSend)(module, NSSelectorFromString(@"contentViewController")); } @catch (__unused NSException *exception) { contentController = nil; }
                }
                UIView *moduleContent = [contentController isKindOfClass:[UIViewController class]] ? contentController.view : nil;
                if (moduleContent) {
                    // Keep the module, controller, and context alive for the
                    // preview's lifetime.
                    objc_setAssociatedObject(container, kCCAAddSheetModuleKey, module, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    objc_setAssociatedObject(container, kCCAAddSheetControllerKey, contentController, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    objc_setAssociatedObject(container, kCCAAddSheetContextKey, context, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    moduleContent.frame = container.bounds;
                    moduleContent.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
                    moduleContent.userInteractionEnabled = NO;
                    [container addSubview:moduleContent];
                    @try {
                        [contentController beginAppearanceTransition:YES animated:NO];
                        [contentController endAppearanceTransition];
                    } @catch (__unused NSException *exception) {}
                    [moduleContent setNeedsLayout];
                    @try { [moduleContent layoutIfNeeded]; } @catch (__unused NSException *exception) {}
                    // Freshly instantiated content renders its accessory title
                    // label on top of the glyph (real CC positions it outside
                    // the platter). Hide any text; the sheet draws its own.
                    NSMutableArray<UIView *> *labelQueue = [NSMutableArray arrayWithObject:moduleContent];
                    while (labelQueue.count) {
                        UIView *candidate = labelQueue.firstObject;
                        [labelQueue removeObjectAtIndex:0];
                        if ([candidate isKindOfClass:[UILabel class]]) candidate.hidden = YES;
                        [labelQueue addObjectsFromArray:candidate.subviews];
                    }
                    // Detached module previews often carry a native 1x2/2x1
                    // material mask underneath CCAster's outer backing. Make
                    // every full-size surface share one continuous radius so
                    // no second rounded layer peeks around the perimeter.
                    CCANormalizePreviewCornerRadii(moduleContent, container.bounds.size, radius);
                    content = moduleContent;
                }
            }
        } @catch (__unused NSException *exception) { content = nil; }
    }
    if (!content) {
        // Curated SF Symbol stand-ins for modules that refuse to instantiate;
        // the generic grid glyph is a last resort only.
        NSString *symbolName = CCAFallbackSymbolForIdentifier(identifier) ?: @"square.grid.2x2";
        UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:26.0 weight:UIImageSymbolWeightMedium];
        UIImage *symbol = [UIImage systemImageNamed:symbolName withConfiguration:configuration] ?: [UIImage systemImageNamed:@"square.grid.2x2" withConfiguration:configuration];
        UIImageView *glyph = [[UIImageView alloc] initWithImage:symbol];
        glyph.tintColor = [UIColor.whiteColor colorWithAlphaComponent:0.9];
        glyph.contentMode = UIViewContentModeCenter;
        glyph.frame = container.bounds;
        glyph.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [container addSubview:glyph];
    }
    return container;
}

- (BOOL)addOwnedDuplicateForIdentifier:(NSString *)identifier {
    NSString *familyIdentifier = CCADuplicateFamilyIdentifierForIdentifier(identifier);
    if (!CCAModuleIdentifierSupportsOwnedDuplicates(familyIdentifier)) return NO;
    NSArray<NSString *> *enabled = [self enabledModuleIdentifiers];
    NSMutableSet<NSString *> *present = [NSMutableSet setWithArray:enabled ?: @[]];
    [present addObjectsFromArray:[self fixedModuleIdentifiers]];
    UIViewController *overlay = gOverlayControllers.allObjects.firstObject;
    for (UIViewController *module in CCACollectModuleControllers(overlay)) {
        NSString *moduleIdentifier = CCAModuleIdentifier(module);
        if (moduleIdentifier.length) [present addObject:moduleIdentifier];
    }
    if (![present containsObject:familyIdentifier]) return NO;
    NSString *duplicateIdentifier = CCANextDuplicateIdentifierForFamily(familyIdentifier, present);
    if (!duplicateIdentifier.length) return NO;

    CCUILayoutSize size = [self catalogLayoutSizeForIdentifier:familyIdentifier];
    NSMutableDictionary<NSString *, NSValue *> *layout = [NSMutableDictionary dictionary];
    NSMutableSet<NSString *> *occupied = [present mutableCopy];
    [occupied addObject:duplicateIdentifier];
    for (NSString *existing in gCCANativeLayoutRects) {
        if (![occupied containsObject:existing]) continue;
        CCUILayoutRect rect = {};
        [gCCANativeLayoutRects[existing] getValue:&rect];
        NSArray<NSNumber *> *origin = gCCACustomOrigins[existing];
        if (origin.count >= 2) rect.origin = (CCUILayoutPoint){origin[0].unsignedIntegerValue, origin[1].unsignedIntegerValue};
        NSArray<NSNumber *> *customSize = gCCACustomSizes[existing];
        if (customSize.count >= 2) rect.size = (CCUILayoutSize){customSize[0].unsignedIntegerValue, customSize[1].unsignedIntegerValue};
        layout[existing] = [NSValue value:&rect withObjCType:@encode(CCUILayoutRect)];
    }
    NSUInteger startPage = overlay ? CCADerivedVisiblePageForOverlay(overlay) : MIN(gCCACurrentPage, kCCAMaxPages - 1);
    CCUILayoutPoint destination = {0, 0};
    if (!CCAGuaranteedPagedSlot(duplicateIdentifier, size, startPage, layout, &destination)) return NO;

    gCCADuplicateFamilies[duplicateIdentifier] = familyIdentifier;
    gCCACustomOrigins[duplicateIdentifier] = @[@(destination.x), @(destination.y)];
    [gCCACustomSizes removeObjectForKey:duplicateIdentifier];
    gCCAPendingPageAfterRebuild = destination.y / kCCAMinimumGridRows;
    CCASaveDuplicateFamilies();
    CCASaveGridPreferences();
    if (overlay) {
        [self syncOwnedDuplicateModulesForOverlay:overlay];
        [self normalizePagedLayoutForOverlay:overlay];
        [self setCurrentPage:gCCAPendingPageAfterRebuild == NSNotFound ? gCCACurrentPage : MIN(gCCAPendingPageAfterRebuild, MAX((NSUInteger)1, gCCAPageCount) - 1) forOverlay:overlay animated:NO];
        gCCAPendingPageAfterRebuild = NSNotFound;
        if (gEditModeActive) [self setEditPresentation:YES forOverlay:overlay animated:NO];
    }
    return YES;
}

- (BOOL)addModuleIdentifierToControlCenter:(NSString *)identifier {
    if (!identifier.length) return NO;
    NSArray<NSString *> *enabled = [self enabledModuleIdentifiers];
    NSMutableSet<NSString *> *present = [NSMutableSet setWithArray:enabled ?: @[]];
    [present addObjectsFromArray:[self fixedModuleIdentifiers]];
    UIViewController *overlay = gOverlayControllers.allObjects.firstObject;
    for (UIViewController *module in CCACollectModuleControllers(overlay)) {
        NSString *moduleIdentifier = CCAModuleIdentifier(module);
        if (moduleIdentifier.length) [present addObject:moduleIdentifier];
    }
    if ([present containsObject:identifier]) {
        if ([self addOwnedDuplicateForIdentifier:identifier]) return YES;
        return NO;
    }

    CCUILayoutSize size = [self catalogLayoutSizeForIdentifier:identifier];
    NSMutableDictionary<NSString *, NSValue *> *layout = [NSMutableDictionary dictionary];
    for (NSString *existing in gCCANativeLayoutRects) {
        // Rects for previously removed modules linger in the native map; only
        // modules that are actually part of Control Center occupy cells.
        if (![present containsObject:existing]) continue;
        CCUILayoutRect rect = {};
        [gCCANativeLayoutRects[existing] getValue:&rect];
        NSArray<NSNumber *> *origin = gCCACustomOrigins[existing];
        if (origin.count >= 2) rect.origin = (CCUILayoutPoint){origin[0].unsignedIntegerValue, origin[1].unsignedIntegerValue};
        NSArray<NSNumber *> *customSize = gCCACustomSizes[existing];
        if (customSize.count >= 2) rect.size = (CCUILayoutSize){customSize[0].unsignedIntegerValue, customSize[1].unsignedIntegerValue};
        layout[existing] = [NSValue value:&rect withObjCType:@encode(CCUILayoutRect)];
    }
    CCUILayoutPoint destination = {0, 0};
    // Prefer the page the user is visibly editing. If it is full, the paged
    // allocator spills forward or opens a fresh page instead of silently
    // routing new controls through stale pager state.
    NSUInteger startPage = CCADerivedVisiblePageForOverlay(overlay);
    BOOL found = CCAGuaranteedPagedSlot(identifier, size, startPage, layout, &destination);
    if (!found) return NO;

    [gCCACustomSizes removeObjectForKey:identifier];
    gCCACustomOrigins[identifier] = @[@(destination.x), @(destination.y)];
    gCCAPendingPageAfterRebuild = destination.y / kCCAMinimumGridRows;
    CFPreferencesSetAppValue(CFSTR("ModuleGridOrigins"), (__bridge CFPropertyListRef)[gCCACustomOrigins copy], kCCAPrefsDomain);
    CFPreferencesSetAppValue(CFSTR("ModuleGridSizes"), (__bridge CFPropertyListRef)[gCCACustomSizes copy], kCCAPrefsDomain);
    CFPreferencesAppSynchronize(kCCAPrefsDomain);
    NSMutableArray<NSString *> *updated = [enabled mutableCopy] ?: [NSMutableArray array];
    [updated addObject:identifier];
    [self saveEnabledModuleIdentifiers:updated];
    return YES;
}

- (void)addControlSheetDidSelectIdentifier:(NSString *)identifier fromSheet:(UIViewController *)sheet {
    BOOL added = [self addModuleIdentifierToControlCenter:identifier];
    if (!added) {
        // No legal slot (or already present): leave the sheet as-is for now;
        // multi-page support will give this a real destination later.
        UINotificationFeedbackGenerator *feedback = [UINotificationFeedbackGenerator new];
        [feedback notificationOccurred:UINotificationFeedbackTypeWarning];
        return;
    }
    CCAHaptic();
    UIViewController *overlay = gOverlayControllers.allObjects.firstObject;
    [sheet.presentingViewController dismissViewControllerAnimated:YES completion:nil];
    (void)overlay;
    [self resettleAfterCollectionRebuild];
}

- (BOOL)persistStoredOrderBySwappingSource:(NSString *)sourceID target:(NSString *)targetID {
    NSString *configurationPath = @"/var/mobile/Library/ControlCenter/ModuleConfiguration.plist";
    NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:configurationPath];
    if (!settings) return NO;
    NSMutableArray *storedOrder = [settings[@"module-identifiers"] mutableCopy];
    NSUInteger sourceIndex = [storedOrder indexOfObject:sourceID];
    NSUInteger targetIndex = [storedOrder indexOfObject:targetID];
    if (sourceIndex == NSNotFound || targetIndex == NSNotFound || sourceIndex == targetIndex) {
        return NO;
    }
    [storedOrder exchangeObjectAtIndex:sourceIndex withObjectAtIndex:targetIndex];
    NSMutableDictionary *updatedSettings = [settings mutableCopy];
    updatedSettings[@"module-identifiers"] = storedOrder;
    // Persist the Settings ordering without invoking the live provider setter.
    // That setter rebuilds the complete CC collection and caused the whole
    // surface to jump immediately after our origin-only layout had settled.
    return [updatedSettings writeToFile:configurationPath atomically:YES];
}

- (void)removeTapped:(UIButton *)sender {
    CCAHaptic();
    NSString *identifier = objc_getAssociatedObject(sender, @selector(removeTapped:));
    if (!identifier.length) return;
    if (gCCADuplicateFamilies[identifier]) {
        [gCCADuplicateFamilies removeObjectForKey:identifier];
        [gCCACustomOrigins removeObjectForKey:identifier];
        [gCCACustomSizes removeObjectForKey:identifier];
        [gCCANativeLayoutRects removeObjectForKey:identifier];
        [gCCABaseLayoutSizes removeObjectForKey:identifier];
        CCASaveDuplicateFamilies();
        CFPreferencesSetAppValue(CFSTR("ModuleGridOrigins"), (__bridge CFPropertyListRef)[gCCACustomOrigins copy], kCCAPrefsDomain);
        CFPreferencesSetAppValue(CFSTR("ModuleGridSizes"), (__bridge CFPropertyListRef)[gCCACustomSizes copy], kCCAPrefsDomain);
        CFPreferencesAppSynchronize(kCCAPrefsDomain);
        UIView *moduleView = objc_getAssociatedObject(sender, kCCARemoveModuleViewKey);
        UIViewController *module = CCAModuleControllerForView(moduleView);
        UIVisualEffectView *border = objc_getAssociatedObject(moduleView, @selector(applyEditingToModule:editing:));
        UIButton *resizeButton = objc_getAssociatedObject(moduleView, kCCAResizeButtonKey);
        [UIView animateWithDuration:0.22 animations:^{
            moduleView.transform = CGAffineTransformMakeScale(0.86, 0.86);
            moduleView.alpha = 0.0;
            border.alpha = 0.0;
            sender.alpha = 0.0;
            resizeButton.alpha = 0.0;
        } completion:^(__unused BOOL finished) {
            [border removeFromSuperview];
            [sender removeFromSuperview];
            [resizeButton removeFromSuperview];
            [module willMoveToParentViewController:nil];
            [module.view removeFromSuperview];
            [module removeFromParentViewController];
            UIViewController *overlay = gOverlayControllers.allObjects.firstObject;
            if (overlay) {
                [self normalizePagedLayoutForOverlay:overlay];
                if (gEditModeActive) [self setEditPresentation:YES forOverlay:overlay animated:NO];
            }
        }];
        return;
    }
    NSArray *current = [self enabledModuleIdentifiers];
    NSMutableArray *updated = [current mutableCopy];
    [updated removeObject:identifier];
    UIView *moduleView = objc_getAssociatedObject(sender, kCCARemoveModuleViewKey);
    CGFloat removalRadius = moduleView.layer.cornerRadius > 1.0 ? moduleView.layer.cornerRadius : MIN(CGRectGetWidth(moduleView.bounds), CGRectGetHeight(moduleView.bounds)) * 0.28;
    moduleView.layer.cornerRadius = removalRadius;
    moduleView.layer.cornerCurve = kCACornerCurveContinuous;
    moduleView.layer.masksToBounds = YES;
    UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:nil];
    blur.frame = moduleView.bounds;
    blur.layer.cornerRadius = moduleView.layer.cornerRadius;
    blur.clipsToBounds = YES;
    blur.userInteractionEnabled = NO;
    [moduleView addSubview:blur];
    // The module's edit chrome is owned partly by the wrapper (border) and
    // partly by the overlay root (remove/resize). None of it belongs to the
    // rebuilt hierarchy, so it must leave with the module or it lingers.
    UIVisualEffectView *border = objc_getAssociatedObject(moduleView, @selector(applyEditingToModule:editing:));
    UIButton *resizeButton = objc_getAssociatedObject(moduleView, kCCAResizeButtonKey);
    [UIView animateWithDuration:0.28 animations:^{
        blur.effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial];
        moduleView.transform = CGAffineTransformMakeScale(0.88, 0.88);
        moduleView.alpha = 0.0;
        border.alpha = 0.0;
        sender.alpha = 0.0;
        resizeButton.alpha = 0.0;
    } completion:^(__unused BOOL finished) {
        [border.layer removeAllAnimations];
        [border removeFromSuperview];
        [sender removeFromSuperview];
        [resizeButton removeFromSuperview];
        objc_setAssociatedObject(moduleView, @selector(applyEditingToModule:editing:), nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(moduleView, kCCARemoveButtonKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(moduleView, kCCAResizeButtonKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [self saveEnabledModuleIdentifiers:updated];
        [self resettleAfterCollectionRebuild];
    }];
}

- (void)resettleAfterCollectionRebuild {
    // Saving through the settings provider rebuilds the whole collection
    // asynchronously: fresh wrappers arrive without the edit translation, the
    // header pocket (and quick-access host) is replaced, and overlay-rooted
    // controls for dead modules become orphans. Sweep repeatedly as the new
    // hierarchy settles.
    for (NSNumber *delay in @[@0.15, @0.35, @0.65]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIViewController *overlay = gOverlayControllers.allObjects.firstObject;
            if (!overlay) return;
            [self installQuickAccessHostOnOverlay:overlay];
            NSMutableSet<UIView *> *validControls = [NSMutableSet set];
            for (UIViewController *candidate in CCACollectModuleControllers(overlay)) {
                UIButton *candidateRemove = objc_getAssociatedObject(candidate.view, kCCARemoveButtonKey);
                UIButton *candidateResize = objc_getAssociatedObject(candidate.view, kCCAResizeButtonKey);
                if (candidateRemove) [validControls addObject:candidateRemove];
                if (candidateResize) [validControls addObject:candidateResize];
            }
            for (UIView *subview in [overlay.view.subviews copy]) {
                if ((subview.tag == kCCARemoveButtonTag || subview.tag == kCCAResizeButtonTag) && ![validControls containsObject:subview]) {
                    [subview removeFromSuperview];
                }
            }
            if (!gEditModeActive) return;
            for (UIViewController *candidate in CCACollectModuleControllers(overlay)) [self applyEditingToModule:candidate editing:YES];
            [self setEditPresentation:YES forOverlay:overlay animated:NO];
        });
    }
}

- (CGFloat)refinedCornerRadiusForSize:(CGSize)size {
    CGFloat width = size.width;
    CGFloat height = size.height;
    CGFloat minimum = MIN(width, height);
    if (minimum <= 0.0) return 0.0;
    BOOL isOneByOne = fabs(width - height) <= 3.0 && minimum <= 76.0;
    return isOneByOne ? minimum * 0.5 : MIN(32.0, MAX(22.0, minimum * 0.5 - 6.0));
}

- (CGFloat)refinedCornerRadiusForModuleView:(UIView *)view {
    return [self refinedCornerRadiusForSize:view.bounds.size];
}

- (CGFloat)editingModuleCornerRadiusForSize:(CGSize)size {
    CGFloat radius = [self refinedCornerRadiusForSize:size];
    CGFloat minimum = MIN(size.width, size.height);
    CGFloat maximum = MAX(size.width, size.height);
    BOOL isRectangularGridModule = minimum > 55.0 && minimum < 82.0 && maximum > 120.0 && maximum < 180.0;
    return isRectangularGridModule ? radius + 4.0 : radius;
}

- (void)configureEditingBorder:(UIVisualEffectView *)border moduleFrame:(CGRect)moduleFrame {
    if (!border) return;
    CGRect newFrame = CGRectInset(moduleFrame, -3.5, -3.5);
    // This gets called every frame during drag/resize for every visible
    // module, so skip all the path/mask work entirely when nothing about
    // this module's frame actually changed since the last call.
    if (CGRectEqualToRect(border.frame, newFrame)) return;
    border.frame = newFrame;
    CGFloat radius = [self refinedCornerRadiusForSize:moduleFrame.size];
    UIBezierPath *ring = [UIBezierPath bezierPathWithRoundedRect:border.bounds cornerRadius:radius + 3.5];
    [ring appendPath:[UIBezierPath bezierPathWithRoundedRect:CGRectInset(border.bounds, 3.5, 3.5) cornerRadius:radius]];
    // Reuse the same mask layer across calls instead of allocating a brand
    // new CAShapeLayer (and re-parenting it into the layer tree) every time.
    CAShapeLayer *mask = (CAShapeLayer *)border.layer.mask;
    if (![mask isKindOfClass:[CAShapeLayer class]]) {
        mask = [CAShapeLayer layer];
        mask.fillRule = kCAFillRuleEvenOdd;
        border.layer.mask = mask;
    }
    mask.path = ring.CGPath;
}

- (id)labelBlurFilterWithRadius:(CGFloat)radius {
    Class filterClass = NSClassFromString(@"CAFilter");
    SEL factory = NSSelectorFromString(@"filterWithName:");
    if (!filterClass || ![filterClass respondsToSelector:factory]) return nil;
    id filter = ((id (*)(id, SEL, id))objc_msgSend)(filterClass, factory, @"gaussianBlur");
    @try {
        [filter setValue:@"CCAsterLabelBlur" forKey:@"name"];
        [filter setValue:@(radius) forKey:@"inputRadius"];
        [filter setValue:@YES forKey:@"inputNormalizeEdges"];
    } @catch (__unused NSException *exception) { return nil; }
    return filter;
}

- (void)legacyTransitionResizedPresentation:(UIView *)presentation appearing:(BOOL)appearing completion:(void (^)(void))completion {
    if (!presentation) { if (completion) completion(); return; }
    objc_setAssociatedObject(presentation, kCCAResizePresentationTransitionKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [presentation.layer removeAnimationForKey:@"CCAsterLabelBlurRadius"];
    CGFloat startRadius = appearing ? 7.0 : 0.0;
    CGFloat endRadius = appearing ? 0.0 : 7.0;
    id filter = [self labelBlurFilterWithRadius:startRadius];
    presentation.layer.filters = filter ? @[filter] : nil;
    presentation.alpha = appearing ? 0.0 : 1.0;
    NSTimeInterval delay = appearing ? 0.12 : 0.0;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (filter) {
            CABasicAnimation *blur = [CABasicAnimation animationWithKeyPath:@"filters.CCAsterLabelBlur.inputRadius"];
            blur.fromValue = @(startRadius);
            blur.toValue = @(endRadius);
            blur.duration = 0.18;
            blur.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
            @try { [filter setValue:@(endRadius) forKey:@"inputRadius"]; } @catch (__unused NSException *exception) {}
            [presentation.layer addAnimation:blur forKey:@"CCAsterLabelBlurRadius"];
        }
        [UIView animateWithDuration:0.18 delay:0.0 options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionBeginFromCurrentState animations:^{
            presentation.alpha = appearing ? 1.0 : 0.0;
        } completion:^(__unused BOOL finished) {
            presentation.layer.filters = nil;
            objc_setAssociatedObject(presentation, kCCAResizePresentationTransitionKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            if (completion) completion();
        }];
    });
}

- (UIImage *)snapshotForPresentation:(UIView *)presentation {
    if (!presentation || CGRectIsEmpty(presentation.bounds)) return nil;
    CGFloat savedAlpha = presentation.alpha;
    [UIView performWithoutAnimation:^{ presentation.alpha = 1.0; }];
    UIGraphicsBeginImageContextWithOptions(presentation.bounds.size, NO, UIScreen.mainScreen.scale);
    [presentation.layer renderInContext:UIGraphicsGetCurrentContext()];
    UIImage *source = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    [UIView performWithoutAnimation:^{ presentation.alpha = savedAlpha; }];
    return source;
}

- (UIImage *)blurredImageFromImage:(UIImage *)source {
    if (!source.CGImage) return nil;
    CIImage *input = [[CIImage alloc] initWithCGImage:source.CGImage];
    CIFilter *blur = [CIFilter filterWithName:@"CIGaussianBlur"];
    [blur setValue:input forKey:kCIInputImageKey];
    [blur setValue:@3.25 forKey:kCIInputRadiusKey];
    CIImage *output = [blur.outputImage imageByCroppingToRect:input.extent];
    static CIContext *context;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ context = [CIContext contextWithOptions:@{kCIContextUseSoftwareRenderer: @NO}]; });
    CGImageRef imageRef = [context createCGImage:output fromRect:input.extent];
    if (!imageRef) return nil;
    UIImage *result = [UIImage imageWithCGImage:imageRef scale:source.scale orientation:UIImageOrientationUp];
    CGImageRelease(imageRef);
    return result;
}

- (UIImage *)blurredSnapshotForPresentation:(UIView *)presentation {
    return [self blurredImageFromImage:[self snapshotForPresentation:presentation]];
}

- (void)transitionResizedPresentation:(UIView *)presentation
                             appearing:(BOOL)appearing
                    outgoingSharpImage:(UIImage *)outgoingSharpImage
                         outgoingImage:(UIImage *)outgoingImage
                         outgoingFrame:(CGRect)outgoingFrame
                            completion:(void (^)(void))completion {
    if (!presentation || !presentation.superview) { if (completion) completion(); return; }
    (void)outgoingSharpImage;
    (void)outgoingImage;
    (void)outgoingFrame;
    NSObject *token = [NSObject new];
    objc_setAssociatedObject(presentation, kCCAResizePresentationTransitionKey, token, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    for (UIView *view in [presentation.superview.subviews copy]) if (view.tag == kCCAResizeBlurSnapshotTag) [view removeFromSuperview];

    // Snapshot crossfades briefly rendered both label endpoints. During live
    // resize that read as a third, floating label. Keep the content at its
    // snapped endpoint and animate only its visibility.
    [presentation.layer removeAllAnimations];
    presentation.alpha = appearing ? 0.0 : 1.0;
    [UIView animateWithDuration:0.16 delay:0.0 options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionBeginFromCurrentState animations:^{
        presentation.alpha = appearing ? 1.0 : 0.0;
    } completion:^(__unused BOOL finished) {
        if (objc_getAssociatedObject(presentation, kCCAResizePresentationTransitionKey) != token) return;
        objc_setAssociatedObject(presentation, kCCAResizePresentationTransitionKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (completion) completion();
    }];
}

- (void)applyResizedPresentationToModule:(UIViewController *)module {
    UIView *moduleView = module.view;
    NSString *identifier = CCAModuleIdentifier(module);
    if ([identifier.lowercaseString containsString:@"ccaster.connectivity"]) {
        CCAConfigureOddResizedModuleLayout(module);
        return;
    }
    NSArray<NSNumber *> *customSize = gCCACustomSizes[identifier];
    CCUILayoutSize base = {};
    [gCCABaseLayoutSizes[identifier] getValue:&base];
    UIView *buttonView = CCAFindSubviewWithClassName(moduleView, @"CCUIButtonModuleView");
    if (!buttonView) return;
    NSArray<NSNumber *> *previewSize = objc_getAssociatedObject(buttonView, kCCAResizePresentationSizeOverrideKey);
    NSArray<NSNumber *> *effectiveSize = previewSize.count >= 2 ? previewSize : customSize;
    BOOL isNativeCompactButton = base.width == 1 && base.height == 1;
    BOOL presentsAsWideButton = isNativeCompactButton && effectiveSize.count >= 2 && effectiveSize[0].unsignedIntegerValue == 2 && effectiveSize[1].unsignedIntegerValue == 1;
    BOOL presentsAsLargeButton = isNativeCompactButton && effectiveSize.count >= 2 && effectiveSize[0].unsignedIntegerValue == 2 && effectiveSize[1].unsignedIntegerValue == 2;
    BOOL presentsExpandedButton = presentsAsWideButton || presentsAsLargeButton;
    BOOL isPowerModule = [identifier isEqualToString:@"com.mtac.ccpowermenu"];

    UIView *presentation = [buttonView viewWithTag:kCCAResizePresentationTag];
    if (CCAModuleLooksExpandedNow(module)) {
        // The compact labels are CCAster-owned and must not be copied into the
        // system detail platter. Keep the source view intact, but suppress its
        // adornment for the live expanded hierarchy.
        presentation.hidden = YES;
        presentation.alpha = 0.0;
        return;
    }
    presentation.hidden = NO;
    // Un-hide path for overlays suppressed while their module was expanded;
    // skip while a fade transition owns the alpha.
    if (presentation && !gCCAExpandedModuleOpen && presentation.alpha < 0.999 &&
        !objc_getAssociatedObject(presentation, kCCAResizePresentationTransitionKey)) {
        presentation.alpha = 1.0;
    }
    if (isPowerModule) {
        for (UIView *glyph in CCACompactGlyphHosts(buttonView)) {
            glyph.hidden = YES;
            glyph.alpha = 0.0;
            glyph.layer.opacity = 0.0;
        }
        NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:moduleView];
        while (queue.count) {
            UIView *candidate = queue.firstObject;
            [queue removeObjectAtIndex:0];
            if ([candidate isKindOfClass:[UIActivityIndicatorView class]]) {
                candidate.hidden = YES;
                candidate.alpha = 0.0;
            }
            [queue addObjectsFromArray:candidate.subviews];
        }
        presentation = CCAEnsureOwnedCompactPresentation(buttonView);
        CCUILayoutSize size = CCAEffectiveCustomSizeForModule(module, identifier);
        CCALayoutOwnedCompactPresentation(presentation, @"power", @"Power", nil, size);
        [buttonView bringSubviewToFront:presentation];
        return;
    }
    if (isNativeCompactButton) {
        // Shortcut-style modules do not all use the same glyph class:
        // Calculator uses an image host, while Flashlight and several system
        // controls use a CAPackage host. Anchor whichever host is active to
        // the same visual point for every supported size.
        // Always merge direct hosts with the KVC-discovered host. Some modules
        // retain separate active/inactive image views; stopping after the first
        // match left the other view carrying the old -42pt translation.
        NSArray<UIView *> *glyphHosts = CCACompactGlyphHosts(buttonView);
        // The platter grows around the compact control; its glyph does not
        // travel between 1x1, 2x1, and 2x2 presentations.
        CGPoint target = CGPointMake(kCCAGridCellSize * 0.5, kCCAGridCellSize * 0.5);
        for (UIView *glyph in glyphHosts) {
            [UIView performWithoutAnimation:^{
                [CATransaction begin];
                [CATransaction setDisableActions:YES];
                if (gCCAResizeInProgress) {
                    [glyph.layer removeAnimationForKey:@"position"];
                    [glyph.layer removeAnimationForKey:@"bounds"];
                    [glyph.layer removeAnimationForKey:@"transform"];
                }
                // Several shortcut modules expose a module-sized image/package
                // container through the same KVC keys as their actual glyph.
                // Keep that container at the original compact footprint so its
                // own centered artwork remains at the 1x1 visual coordinate.
                if (CGRectGetWidth(glyph.bounds) > 72.0 || CGRectGetHeight(glyph.bounds) > 72.0) {
                    CGPoint compactOrigin = [buttonView convertPoint:CGPointZero toView:glyph.superview];
                    glyph.layer.transform = CATransform3DIdentity;
                    glyph.frame = (CGRect){compactOrigin, CGSizeMake(kCCAGridCellSize, kCCAGridCellSize)};
                } else {
                    // Centering and translating the same image host displaced it
                    // by a second 42pt step in older builds. One fixed center is
                    // the sole geometry writer for glyph-sized views.
                    glyph.layer.transform = CATransform3DIdentity;
                    glyph.center = [buttonView convertPoint:target toView:glyph.superview];
                }
                if (gCCAResizeInProgress) {
                    [glyph.layer removeAnimationForKey:@"position"];
                    [glyph.layer removeAnimationForKey:@"bounds"];
                    [glyph.layer removeAnimationForKey:@"transform"];
                }
                [CATransaction commit];
            }];
        }
    }
    if (!presentsExpandedButton) {
        if (presentation) objc_setAssociatedObject(presentation, kCCAResizePresentationLayoutKey, nil, OBJC_ASSOCIATION_COPY_NONATOMIC);
        if (presentation && !objc_getAssociatedObject(presentation, kCCAResizePresentationTransitionKey)) {
            [self transitionResizedPresentation:presentation appearing:NO outgoingSharpImage:nil outgoingImage:nil outgoingFrame:CGRectZero completion:^{ [presentation removeFromSuperview]; }];
        }
        return;
    }

    BOOL createdPresentation = NO;
    if (!presentation) {
        presentation = [[UIView alloc] initWithFrame:buttonView.bounds];
        presentation.tag = kCCAResizePresentationTag;
        // Never expose the newly created labels for a frame before their
        // blurred reveal owns the transition.
        presentation.alpha = 0.0;
        presentation.userInteractionEnabled = NO;
        presentation.backgroundColor = UIColor.clearColor;
        presentation.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        presentation.clipsToBounds = YES;

        UILabel *title = [[UILabel alloc] initWithFrame:CGRectZero];
        title.tag = 1;
        title.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightSemibold];
        title.numberOfLines = 2;
        title.lineBreakMode = NSLineBreakByTruncatingTail;
        [presentation addSubview:title];

        UILabel *status = [[UILabel alloc] initWithFrame:CGRectZero];
        status.tag = 2;
        status.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightRegular];
        status.adjustsFontSizeToFitWidth = YES;
        status.minimumScaleFactor = 0.78;
        [presentation addSubview:status];
        [buttonView addSubview:presentation];
        createdPresentation = YES;
    }
    UILabel *title = (UILabel *)[presentation viewWithTag:1];
    UILabel *status = (UILabel *)[presentation viewWithTag:2];
    UIImageView *ownedGlyph = (UIImageView *)[presentation viewWithTag:kCCAResizePresentationGlyphTag];
    NSString *layoutMode = presentsAsLargeButton ? @"large" : @"wide";
    NSString *previousLayoutMode = objc_getAssociatedObject(presentation, kCCAResizePresentationLayoutKey);
    BOOL snappedLayoutChanged = previousLayoutMode.length && ![previousLayoutMode isEqualToString:layoutMode];
    if (snappedLayoutChanged) [UIView performWithoutAnimation:^{ presentation.alpha = 0.0; }];

    NSString *moduleLabel = buttonView.accessibilityLabel;
    NSString *lowerIdentifier = identifier.lowercaseString;
    BOOL isMuteModule = [lowerIdentifier containsString:@"mutemodule"];
    BOOL isOrientationModule = [lowerIdentifier containsString:@"orientationlock"];
    BOOL isFlashlightModule = [lowerIdentifier containsString:@"flashlightmodule"];
    BOOL isCCAConnectivityModule = [lowerIdentifier containsString:@"ccaster.connectivity"];
    if (isMuteModule) moduleLabel = @"Silent Mode";
    else if (isOrientationModule) moduleLabel = @"Orientation";
    else if (isCCAConnectivityModule) moduleLabel = CCAFriendlyNameForIdentifier(identifier) ?: moduleLabel;
    BOOL hasGenericLabel = !moduleLabel.length ||
        [moduleLabel caseInsensitiveCompare:@"Control"] == NSOrderedSame ||
        [moduleLabel caseInsensitiveCompare:@"Button"] == NSOrderedSame;
    if (hasGenericLabel) {
        NSString *stableLabel = CCAFriendlyNameForIdentifier(identifier);
        if (!stableLabel.length && identifier.length) stableLabel = CCAPrettyNameForIdentifier(identifier);
        if (stableLabel.length) moduleLabel = stableLabel;
    }
    if (!moduleLabel.length) moduleLabel = @"Control";
    NSString *rawValue = buttonView.accessibilityValue;
    BOOL hasBooleanState = [rawValue isEqualToString:@"0"] || [rawValue isEqualToString:@"1"] ||
        isMuteModule || isOrientationModule || isFlashlightModule;
    BOOL enabled = hasBooleanState && [(UIControl *)buttonView isSelected];
    NSString *statusText = nil;
    if (isCCAConnectivityModule) statusText = CCAConnectivityStatusForIdentifier(identifier);
    else if (isMuteModule) statusText = enabled ? @"Vibrate" : @"Ring";
    else if (isOrientationModule) statusText = enabled ? @"Locked" : @"Unlocked";
    else if (hasBooleanState) statusText = enabled ? @"On" : @"Off";
    else if (rawValue.length &&
             [rawValue caseInsensitiveCompare:@"Ready"] != NSOrderedSame &&
             [rawValue caseInsensitiveCompare:@"Open"] != NSOrderedSame) statusText = rawValue;
    UIColor *primaryColor = enabled ? [UIColor colorWithWhite:0.08 alpha:0.92] : UIColor.whiteColor;
    UIColor *secondaryColor = enabled ? [UIColor colorWithWhite:0.18 alpha:0.72] : [UIColor.whiteColor colorWithAlphaComponent:0.62];
    title.text = moduleLabel;
    title.textColor = primaryColor;
    status.text = statusText;
    status.textColor = secondaryColor;
    CGFloat twoCellSize = kCCAGridCellSize * 2.0 + kCCAGridGap;
    CGSize logicalSize = presentsAsLargeButton ? CGSizeMake(twoCellSize, twoCellSize) : CGSizeMake(twoCellSize, kCCAGridCellSize);
    CGFloat textX = presentsAsLargeButton ? 21.0 : 71.0;
    CGFloat textWidth = presentsAsLargeButton ? MAX(0.0, logicalSize.width - textX - 24.0) : MAX(0.0, logicalSize.width - 83.0);
    CGFloat lineHeight = 14.3333;
    CGRect measuredTitle = [moduleLabel boundingRectWithSize:CGSizeMake(textWidth, lineHeight * 2.0)
                                                     options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                                  attributes:@{NSFontAttributeName: title.font}
                                                     context:nil];
    CGFloat titleHeight = measuredTitle.size.height > lineHeight + 1.0 ? lineHeight * 2.0 : lineHeight;
    BOOL showsStatus = statusText.length > 0;
    CGFloat groupHeight = titleHeight + (showsStatus ? lineHeight : 0.0);
    CGFloat groupTop = presentsAsLargeButton ? logicalSize.height - 17.3333 - groupHeight : (logicalSize.height - groupHeight) * 0.5;
    [UIView performWithoutAnimation:^{
        presentation.frame = (CGRect){CGPointZero, logicalSize};
        title.frame = CGRectMake(textX, groupTop, textWidth, titleHeight);
        status.frame = CGRectMake(textX, groupTop + titleHeight, textWidth, lineHeight);
        status.hidden = !showsStatus;
        title.textAlignment = NSTextAlignmentLeft;
        status.textAlignment = NSTextAlignmentLeft;
        if (isPowerModule) {
            UIImageView *glyph = CCAEnsureResizePresentationGlyph(presentation, @"power");
            glyph.frame = CGRectMake(0.0, 0.0, kCCAGridCellSize, kCCAGridCellSize);
            [presentation bringSubviewToFront:glyph];
        } else if (ownedGlyph) {
            ownedGlyph.hidden = YES;
        }
    }];
    objc_setAssociatedObject(presentation, kCCAResizePresentationLayoutKey, layoutMode, OBJC_ASSOCIATION_COPY_NONATOMIC);
    [buttonView bringSubviewToFront:presentation];
    if (createdPresentation || snappedLayoutChanged) {
        [self transitionResizedPresentation:presentation appearing:YES outgoingSharpImage:nil outgoingImage:nil outgoingFrame:CGRectZero completion:nil];
    }
}

- (void)applyRefinedLookToModule:(UIViewController *)module {
    UIView *view = module.view;
    if (!view) return;
    if (!objc_getAssociatedObject(view, kCCAOriginalCornerRadiusKey)) {
        objc_setAssociatedObject(view, kCCAOriginalCornerRadiusKey, @(view.layer.cornerRadius), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(view, kCCAOriginalMasksToBoundsKey, @(view.layer.masksToBounds), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (gEnabled) {
        view.layer.cornerRadius = [self refinedCornerRadiusForModuleView:view];
        view.layer.cornerCurve = kCACornerCurveContinuous;
        view.layer.masksToBounds = YES;
    } else {
        view.layer.cornerRadius = [objc_getAssociatedObject(view, kCCAOriginalCornerRadiusKey) doubleValue];
        view.layer.masksToBounds = [objc_getAssociatedObject(view, kCCAOriginalMasksToBoundsKey) boolValue];
    }
    [self applyResizedPresentationToModule:module];
    CCAConfigureOddResizedModuleLayout(module);
    // Connectivity's individual button controllers lay themselves out after
    // their container. Re-apply the compact iOS 18 arrangement from CCAster's
    // stable module refresh path as well as the controller hook below.
    UIViewController *connectivity = CCAConnectivityChild(module, @"CCUIConnectivityModuleViewController");
    if ([NSStringFromClass(module.class) isEqualToString:@"CCUIConnectivityModuleViewController"]) connectivity = module;
    if (connectivity) CCAConfigureConnectivityLayout(connectivity);
}

- (void)applyTransitionRadiusToModule:(UIViewController *)module {
    if (!gEnabled || !module.view) return;
    UIView *moduleView = module.view;
    CGFloat radius = [self refinedCornerRadiusForModuleView:moduleView];
    // The platter-return animation targets the container's stored compact
    // radius. Seed it with the refined value so modules come home at the
    // tweaked radius instead of settling native and snapping afterwards.
    UIView *contentContainer = CCAFindAncestorOrSubviewWithClassName(moduleView, @"CCUIContentModuleContentContainerView");
    CCASetContinuousCornerRadiusIvar(contentContainer, @"_compactContinuousCornerRadius", radius);
    CCASetContinuousCornerRadiusIvar(contentContainer, @"_expandedContinuousCornerRadius", radius);
    @try { [contentContainer setValue:@(radius) forKey:@"compactContinuousCornerRadius"]; } @catch (__unused NSException *exception) {}
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:moduleView];
    while (queue.count) {
        UIView *candidate = queue.firstObject;
        [queue removeObjectAtIndex:0];
        NSString *name = NSStringFromClass(candidate.class);
        BOOL buttonSurface = [name isEqualToString:@"CCUIButtonModuleView"];
        BOOL materialSurface = [name containsString:@"Material"] || [name containsString:@"VisualEffect"] || [name containsString:@"Platter"];
        BOOL fillsModule = fabs(CGRectGetWidth(candidate.bounds) - CGRectGetWidth(moduleView.bounds)) < 3.0 &&
                           fabs(CGRectGetHeight(candidate.bounds) - CGRectGetHeight(moduleView.bounds)) < 3.0;
        if (candidate == moduleView || buttonSurface || (materialSurface && fillsModule)) {
            candidate.layer.cornerRadius = radius;
            candidate.layer.cornerCurve = kCACornerCurveContinuous;
            if (candidate == moduleView) candidate.layer.masksToBounds = YES;
        }
        [queue addObjectsFromArray:candidate.subviews];
    }
}

- (void)applyClosingCompactRadiusToModule:(UIViewController *)module overlay:(UIViewController *)overlay sourceObject:(id)object {
    if (!gEnabled || !module.view) return;
    NSString *identifier = [CCAModuleIdentifier(module) copy] ?: [CCAIdentifierFromObject(object) copy];
    UIViewController *compactModule = nil;
    if (identifier.length) {
        for (UIViewController *candidate in CCACollectModuleControllers(overlay)) {
            if ([CCAModuleIdentifier(candidate) isEqualToString:identifier] &&
                CGRectGetWidth(candidate.view.bounds) < 190.0 &&
                CGRectGetHeight(candidate.view.bounds) < 190.0) {
                compactModule = candidate;
                break;
            }
        }
    }
    CCUILayoutSize layoutSize = identifier.length ? [self catalogLayoutSizeForIdentifier:identifier] : (CCUILayoutSize){1, 1};
    NSArray<NSNumber *> *customSize = identifier.length ? gCCACustomSizes[identifier] : nil;
    if (customSize.count >= 2) {
        layoutSize.width = MAX((NSUInteger)1, customSize[0].unsignedIntegerValue);
        layoutSize.height = MAX((NSUInteger)1, customSize[1].unsignedIntegerValue);
    }
    CGSize compactSize = compactModule ? compactModule.view.bounds.size : [self catalogPointSizeForLayoutSize:layoutSize];
    CGFloat radius = [self refinedCornerRadiusForSize:compactSize];
    UIView *root = module.view;
    UIView *contentContainer = CCAFindAncestorOrSubviewWithClassName(root, @"CCUIContentModuleContentContainerView");
    CCASetContinuousCornerRadiusIvar(contentContainer, @"_compactContinuousCornerRadius", radius);
    @try { [contentContainer setValue:@(radius) forKey:@"compactContinuousCornerRadius"]; } @catch (__unused NSException *exception) {}
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:root];
    while (queue.count) {
        UIView *candidate = queue.firstObject;
        [queue removeObjectAtIndex:0];
        NSString *name = NSStringFromClass(candidate.class);
        BOOL isTransitionSurface = candidate == root ||
            [name containsString:@"ContentModule"] ||
            [name containsString:@"Platter"] ||
            [name containsString:@"Material"] ||
            [name containsString:@"VisualEffect"];
        if (isTransitionSurface) {
            [candidate.layer removeAnimationForKey:@"cornerRadius"];
            candidate.layer.cornerRadius = radius;
            candidate.layer.cornerCurve = kCACornerCurveContinuous;
            if (candidate == root) candidate.layer.masksToBounds = YES;
        }
        [queue addObjectsFromArray:candidate.subviews];
    }
}

- (void)applyLivePreviewOrder:(NSArray<NSString *> *)order overlay:(UIViewController *)overlay {
    if (!gCCAUseNativeLiveReflow) return;
    if (!order.count || !overlay) return;
    UIViewController *collection = [self moduleCollectionControllerInOverlay:overlay];
    SEL providerSelector = NSSelectorFromString(@"_activePositionProvider");
    id provider = [collection respondsToSelector:providerSelector] ? ((id (*)(id, SEL))objc_msgSend)(collection, providerSelector) : nil;
    SEL regenerateSelector = NSSelectorFromString(@"regenerateRectsWithOrderedIdentifiers:orderedSizes:");
    if (!provider || ![provider respondsToSelector:regenerateSelector]) return;
    NSMutableArray<NSValue *> *sizes = [NSMutableArray arrayWithCapacity:order.count];
    for (NSString *identifier in order) {
        NSValue *sizeValue = gCCAProviderSizes[identifier];
        if (!sizeValue) {
            UIViewController *match = nil;
            for (UIViewController *candidate in CCACollectModuleControllers(overlay)) if ([CCAModuleIdentifier(candidate) isEqualToString:identifier]) { match = candidate; break; }
            CGFloat step = kCCAGridStep;
            CCUILayoutSize size = {
                MAX(1, (NSUInteger)llround((CGRectGetWidth(match.view.bounds) + kCCAGridGap) / step)),
                MAX(1, (NSUInteger)llround((CGRectGetHeight(match.view.bounds) + kCCAGridGap) / step))
            };
            sizeValue = [NSValue value:&size withObjCType:@encode(CCUILayoutSize)];
        }
        [sizes addObject:sizeValue];
    }
    ((void (*)(id, SEL, id, id))objc_msgSend)(provider, regenerateSelector, order, sizes);
    [collection.view setNeedsLayout];
    [UIView animateWithDuration:0.20 delay:0.0 options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionBeginFromCurrentState animations:^{
        [collection.view layoutIfNeeded];
    } completion:nil];
}

- (BOOL)layoutHasIllegalOverlapInOverlay:(UIViewController *)overlay {
    NSArray<UIViewController *> *modules = CCACollectModuleControllers(overlay);
    for (NSUInteger first = 0; first < modules.count; first++) {
        CGRect firstFrame = CCAVisibleModuleFrame(modules[first], overlay);
        if (CGRectIsEmpty(firstFrame)) continue;
        for (NSUInteger second = first + 1; second < modules.count; second++) {
            CGRect secondFrame = CCAVisibleModuleFrame(modules[second], overlay);
            CGRect intersection = CGRectIntersection(CGRectInset(firstFrame, 2.0, 2.0), CGRectInset(secondFrame, 2.0, 2.0));
            if (!CGRectIsNull(intersection) && CGRectGetWidth(intersection) > 4.0 && CGRectGetHeight(intersection) > 4.0) return YES;
        }
    }
    return NO;
}

- (BOOL)applyExplicitGridSwapFrom:(NSString *)sourceID to:(NSString *)targetID overlay:(UIViewController *)overlay {
    NSValue *sourceValue = gCCANativeLayoutRects[sourceID];
    NSValue *targetValue = gCCANativeLayoutRects[targetID];
    if (!sourceValue || !targetValue) return NO;
    CCUILayoutRect sourceRect = {}, targetRect = {};
    [sourceValue getValue:&sourceRect];
    [targetValue getValue:&targetRect];
    NSMutableDictionary<NSString *, NSValue *> *proposed = CCACurrentPageLayout(overlay, kCCAMinimumGridRows);
    for (NSString *identifier in proposed) {
        CCUILayoutRect rect = {}; [proposed[identifier] getValue:&rect];
        if ([identifier isEqualToString:sourceID]) sourceRect = rect;
        if ([identifier isEqualToString:targetID]) targetRect = rect;
    }
    if (!proposed[sourceID] || !proposed[targetID]) return NO;
    CCUILayoutPoint originalSourceOrigin = sourceRect.origin;
    sourceRect.origin = targetRect.origin;
    targetRect.origin = originalSourceOrigin;
    proposed[sourceID] = [NSValue value:&sourceRect withObjCType:@encode(CCUILayoutRect)];
    proposed[targetID] = [NSValue value:&targetRect withObjCType:@encode(CCUILayoutRect)];

    if (!CCALogicalLayoutIsLegal(proposed, kCCAMinimumGridRows)) return NO;

    NSArray<NSString *> *identifiers = proposed.allKeys;
    for (NSUInteger first = 0; first < identifiers.count; first++) {
        CCUILayoutRect a = {}; [proposed[identifiers[first]] getValue:&a];
        if (a.origin.x + a.size.width > 4) return NO;
        for (NSUInteger second = first + 1; second < identifiers.count; second++) {
            CCUILayoutRect b = {}; [proposed[identifiers[second]] getValue:&b];
            BOOL xOverlap = a.origin.x < b.origin.x + b.size.width && b.origin.x < a.origin.x + a.size.width;
            BOOL yOverlap = a.origin.y < b.origin.y + b.size.height && b.origin.y < a.origin.y + a.size.height;
            if (xOverlap && yOverlap) return NO;
        }
    }
    NSUInteger pageStart = gCCACurrentPage * kCCAMinimumGridRows;
    gCCACustomOrigins[sourceID] = @[@(sourceRect.origin.x), @(pageStart + sourceRect.origin.y)];
    gCCACustomOrigins[targetID] = @[@(targetRect.origin.x), @(pageStart + targetRect.origin.y)];
    CFPreferencesSetAppValue(CFSTR("ModuleGridOrigins"), (__bridge CFPropertyListRef)[gCCACustomOrigins copy], kCCAPrefsDomain);
    CFPreferencesAppSynchronize(kCCAPrefsDomain);
    UIViewController *collection = [self moduleCollectionControllerInOverlay:overlay];
    [collection.view setNeedsLayout];
    [UIView animateWithDuration:0.22 animations:^{ [collection.view layoutIfNeeded]; }];
    return YES;
}

- (BOOL)applyExplicitGridMoveFrom:(NSString *)sourceID toOrigin:(CCUILayoutPoint)destination overlay:(UIViewController *)overlay {
    return [self applyExplicitGridMoveFrom:sourceID toOrigin:destination onPage:gCCACurrentPage overlay:overlay];
}

- (BOOL)applyExplicitGridMoveFrom:(NSString *)sourceID toOrigin:(CCUILayoutPoint)destination onPage:(NSUInteger)page overlay:(UIViewController *)overlay {
    NSValue *sourceValue = gCCANativeLayoutRects[sourceID];
    if (!sourceValue) return NO;
    NSMutableDictionary<NSString *, NSValue *> *proposed = CCALayoutForPage(overlay, page, kCCAMinimumGridRows);
    CCUILayoutRect sourceRect = {};
    BOOL sourceWasOnTargetPage = proposed[sourceID] != nil;
    if (sourceWasOnTargetPage) [proposed[sourceID] getValue:&sourceRect];
    else {
        [sourceValue getValue:&sourceRect];
        NSArray<NSNumber *> *savedSize = gCCACustomSizes[sourceID];
        if (savedSize.count >= 2) sourceRect.size = (CCUILayoutSize){savedSize[0].unsignedIntegerValue, savedSize[1].unsignedIntegerValue};
    }
    if (sourceWasOnTargetPage && sourceRect.origin.x == destination.x && sourceRect.origin.y == destination.y) return NO;
    sourceRect.origin = destination;
    if (sourceRect.origin.x + sourceRect.size.width > 4 || sourceRect.origin.y + sourceRect.size.height > kCCAMinimumGridRows) return NO;
    proposed[sourceID] = [NSValue value:&sourceRect withObjCType:@encode(CCUILayoutRect)];

    if (!CCALogicalLayoutIsLegal(proposed, kCCAMinimumGridRows)) return NO;

    NSArray<NSString *> *identifiers = proposed.allKeys;
    for (NSUInteger first = 0; first < identifiers.count; first++) {
        CCUILayoutRect a = {};
        [proposed[identifiers[first]] getValue:&a];
        if (a.origin.x + a.size.width > 4) return NO;
        for (NSUInteger second = first + 1; second < identifiers.count; second++) {
            CCUILayoutRect b = {};
            [proposed[identifiers[second]] getValue:&b];
            BOOL xOverlap = a.origin.x < b.origin.x + b.size.width && b.origin.x < a.origin.x + a.size.width;
            BOOL yOverlap = a.origin.y < b.origin.y + b.size.height && b.origin.y < a.origin.y + a.size.height;
            if (xOverlap && yOverlap) return NO;
        }
    }
    NSUInteger pageStart = page * kCCAMinimumGridRows;
    gCCACustomOrigins[sourceID] = @[@(destination.x), @(pageStart + destination.y)];
    CFPreferencesSetAppValue(CFSTR("ModuleGridOrigins"), (__bridge CFPropertyListRef)[gCCACustomOrigins copy], kCCAPrefsDomain);
    CFPreferencesAppSynchronize(kCCAPrefsDomain);
    UIViewController *collection = [self moduleCollectionControllerInOverlay:overlay];
    [collection.view setNeedsLayout];
    [UIView animateWithDuration:0.22 animations:^{ [collection.view layoutIfNeeded]; }];
    return YES;
}

- (BOOL)applyExplicitGridInsertionFrom:(NSString *)sourceID toOrigin:(CCUILayoutPoint)destination maxRows:(NSUInteger)maxRows overlay:(UIViewController *)overlay {
    return [self applyExplicitGridInsertionFrom:sourceID toOrigin:destination onPage:gCCACurrentPage maxRows:maxRows overlay:overlay];
}

- (BOOL)applyExplicitGridInsertionFrom:(NSString *)sourceID toOrigin:(CCUILayoutPoint)destination onPage:(NSUInteger)page maxRows:(NSUInteger)maxRows overlay:(UIViewController *)overlay {
    NSValue *sourceValue = gCCANativeLayoutRects[sourceID];
    if (!sourceValue || maxRows == 0) return NO;
    NSMutableDictionary<NSString *, NSValue *> *initial = CCALayoutForPage(overlay, page, maxRows);
    NSMutableDictionary<NSString *, NSValue *> *proposed = [initial mutableCopy];
    CCUILayoutRect sourceRect = {};
    if (proposed[sourceID]) [proposed[sourceID] getValue:&sourceRect];
    else {
        [sourceValue getValue:&sourceRect];
        NSArray<NSNumber *> *savedSize = gCCACustomSizes[sourceID];
        if (savedSize.count >= 2) sourceRect.size = (CCUILayoutSize){savedSize[0].unsignedIntegerValue, savedSize[1].unsignedIntegerValue};
        sourceRect.origin = destination;
        initial[sourceID] = [NSValue value:&sourceRect withObjCType:@encode(CCUILayoutRect)];
    }
    sourceRect.origin = destination;
    if (sourceRect.origin.x + sourceRect.size.width > 4 || sourceRect.origin.y + sourceRect.size.height > maxRows) return NO;
    proposed[sourceID] = [NSValue value:&sourceRect withObjCType:@encode(CCUILayoutRect)];

    NSMutableArray<NSString *> *remaining = [proposed.allKeys mutableCopy];
    [remaining removeObject:sourceID];
    [remaining sortUsingComparator:^NSComparisonResult(NSString *left, NSString *right) {
        CCUILayoutRect a = {}, b = {};
        [proposed[left] getValue:&a]; [proposed[right] getValue:&b];
        if (a.origin.y != b.origin.y) return a.origin.y < b.origin.y ? NSOrderedAscending : NSOrderedDescending;
        if (a.origin.x != b.origin.x) return a.origin.x < b.origin.x ? NSOrderedAscending : NSOrderedDescending;
        return [left compare:right];
    }];
    NSMutableArray<NSString *> *placed = [NSMutableArray arrayWithObject:sourceID];
    BOOL displacedAny = NO;
    for (NSString *identifier in remaining) {
        CCUILayoutRect candidate = {};
        [proposed[identifier] getValue:&candidate];
        BOOL overlapsPlaced = NO;
        for (NSString *blockerID in placed) {
            CCUILayoutRect blocker = {};
            [proposed[blockerID] getValue:&blocker];
            if (CCALogicalRectsOverlap(candidate, blocker)) { overlapsPlaced = YES; break; }
        }
        if (overlapsPlaced && candidate.origin.y > 0) {
            for (NSInteger row = (NSInteger)candidate.origin.y - 1; row >= 0; row--) {
                CCUILayoutRect upward = candidate;
                upward.origin.y = (NSUInteger)row;
                if (CCALogicalRectFits(identifier, upward, proposed, maxRows)) {
                    candidate = upward;
                    proposed[identifier] = [NSValue value:&candidate withObjCType:@encode(CCUILayoutRect)];
                    displacedAny = YES;
                    overlapsPlaced = NO;
                    break;
                }
            }
        }
        BOOL adjusted = YES;
        while (overlapsPlaced && adjusted) {
            adjusted = NO;
            NSUInteger requiredY = candidate.origin.y;
            for (NSString *blockerID in placed) {
                CCUILayoutRect blocker = {};
                [proposed[blockerID] getValue:&blocker];
                BOOL xOverlap = candidate.origin.x < blocker.origin.x + blocker.size.width && blocker.origin.x < candidate.origin.x + candidate.size.width;
                BOOL yOverlap = candidate.origin.y < blocker.origin.y + blocker.size.height && blocker.origin.y < candidate.origin.y + candidate.size.height;
                if (xOverlap && yOverlap) requiredY = MAX(requiredY, blocker.origin.y + blocker.size.height);
            }
            if (requiredY != candidate.origin.y) {
                candidate.origin.y = requiredY;
                adjusted = YES;
                displacedAny = YES;
                if (candidate.origin.y + candidate.size.height > maxRows) return NO;
            }
        }
        proposed[identifier] = [NSValue value:&candidate withObjCType:@encode(CCUILayoutRect)];
        [placed addObject:identifier];
    }
    if (!displacedAny) return NO;
    if (!CCALogicalLayoutIsLegal(proposed, maxRows)) return NO;

    // Commit every changed origin together only after the complete cascade fits.
    NSUInteger sourcePageStart = page * kCCAMinimumGridRows;
    gCCACustomOrigins[sourceID] = @[@(destination.x), @(sourcePageStart + destination.y)];
    for (NSString *identifier in proposed) {
        CCUILayoutRect before = {}, after = {};
        [initial[identifier] getValue:&before]; [proposed[identifier] getValue:&after];
        if (before.origin.x != after.origin.x || before.origin.y != after.origin.y) {
            NSUInteger pageStart = page * kCCAMinimumGridRows;
            gCCACustomOrigins[identifier] = @[@(after.origin.x), @(pageStart + after.origin.y)];
        }
    }
    CFPreferencesSetAppValue(CFSTR("ModuleGridOrigins"), (__bridge CFPropertyListRef)[gCCACustomOrigins copy], kCCAPrefsDomain);
    CFPreferencesAppSynchronize(kCCAPrefsDomain);
    UIViewController *collection = [self moduleCollectionControllerInOverlay:overlay];
    [collection.view setNeedsLayout];
    [UIView animateWithDuration:0.22 animations:^{ [collection.view layoutIfNeeded]; }];
    return YES;
}

- (BOOL)moduleIdentifierSupportsResizing:(NSString *)identifier {
    if (!identifier.length || [identifier isEqualToString:@"com.apple.control-center.DisplayModule"] || [identifier isEqualToString:@"com.apple.mediaremote.controlcenter.audio"] || [identifier isEqualToString:@"com.apple.control-center.ConnectivityModule"]) return NO;
    if ([identifier.lowercaseString containsString:@"ccaster.connectivity"]) return YES;
    NSValue *baseValue = gCCABaseLayoutSizes[identifier];
    if (!baseValue) return NO;
    CCUILayoutSize base = {};
    [baseValue getValue:&base];
    return (base.width == 1 && base.height == 1) || (base.width == 2 && base.height == 2);
}

- (BOOL)applyGridResizeForIdentifier:(NSString *)sourceID size:(CCUILayoutSize)newSize overlay:(UIViewController *)overlay {
    NSValue *sourceValue = gCCANativeLayoutRects[sourceID];
    if (!sourceValue) return NO;
    NSUInteger pageStart = gCCACurrentPage * kCCAMinimumGridRows;
    // gCCANativeLayoutRects is process-wide and intentionally survives native
    // provider rebuilds. It can therefore contain controls that were removed,
    // disabled, or last lived beyond the current eight-row page. Including
    // those stale rects made the final legality check reject every resize --
    // even a shrink that could not collide with anything visible.
    NSMutableDictionary<NSString *, NSValue *> *initial = [NSMutableDictionary dictionary];
    for (UIViewController *module in CCACollectModuleControllers(overlay)) {
        NSString *identifier = CCAModuleIdentifier(module);
        NSValue *nativeRect = identifier.length ? gCCANativeLayoutRects[identifier] : nil;
        if (!identifier.length || !nativeRect) continue;
        CCUILayoutRect effectiveRect = {};
        [nativeRect getValue:&effectiveRect];
        NSArray<NSNumber *> *savedOrigin = gCCACustomOrigins[identifier];
        if (savedOrigin.count >= 2) effectiveRect.origin = (CCUILayoutPoint){savedOrigin[0].unsignedIntegerValue, savedOrigin[1].unsignedIntegerValue};
        NSArray<NSNumber *> *savedSize = gCCACustomSizes[identifier];
        if (savedSize.count >= 2) effectiveRect.size = (CCUILayoutSize){savedSize[0].unsignedIntegerValue, savedSize[1].unsignedIntegerValue};
        if (effectiveRect.origin.y < pageStart || effectiveRect.origin.y >= pageStart + kCCAMinimumGridRows) continue;
        effectiveRect.origin.y -= pageStart;
        if (effectiveRect.origin.x + effectiveRect.size.width > 4 || effectiveRect.origin.y + effectiveRect.size.height > kCCAMinimumGridRows) continue;
        initial[identifier] = [NSValue value:&effectiveRect withObjCType:@encode(CCUILayoutRect)];
    }
    if (!initial[sourceID]) return NO;
    NSMutableDictionary<NSString *, NSValue *> *proposed = [initial mutableCopy];
    CCUILayoutRect sourceRect = {};
    [proposed[sourceID] getValue:&sourceRect];
    sourceRect.size = newSize;
    if (sourceRect.origin.x + sourceRect.size.width > 4 || sourceRect.origin.y + sourceRect.size.height > kCCAMinimumGridRows) return NO;
    proposed[sourceID] = [NSValue value:&sourceRect withObjCType:@encode(CCUILayoutRect)];

    NSMutableArray<NSString *> *remaining = [proposed.allKeys mutableCopy];
    [remaining removeObject:sourceID];
    [remaining sortUsingComparator:^NSComparisonResult(NSString *left, NSString *right) {
        CCUILayoutRect a = {}, b = {};
        [proposed[left] getValue:&a]; [proposed[right] getValue:&b];
        if (a.origin.y != b.origin.y) return a.origin.y < b.origin.y ? NSOrderedAscending : NSOrderedDescending;
        if (a.origin.x != b.origin.x) return a.origin.x < b.origin.x ? NSOrderedAscending : NSOrderedDescending;
        return [left compare:right];
    }];
    // Keep the resized module fixed, preserve every unaffected module at its
    // current origin, and move only modules whose footprints now collide. The
    // old cascade could only push downward in the same columns, so it rejected
    // otherwise legal resizes whenever that path reached row eight.
    NSMutableArray<NSString *> *placed = [NSMutableArray arrayWithObject:sourceID];
    NSMutableDictionary<NSString *, NSArray<NSNumber *> *> *overflowOrigins = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSValue *> *globalOccupied = [NSMutableDictionary dictionary];
    for (UIViewController *module in CCACollectModuleControllers(overlay)) {
        NSString *identifier = CCAModuleIdentifier(module);
        NSValue *nativeRect = identifier.length ? gCCANativeLayoutRects[identifier] : nil;
        if (!nativeRect) continue;
        CCUILayoutRect rect = {};
        [nativeRect getValue:&rect];
        NSArray<NSNumber *> *origin = gCCACustomOrigins[identifier];
        if (origin.count >= 2) rect.origin = (CCUILayoutPoint){origin[0].unsignedIntegerValue, origin[1].unsignedIntegerValue};
        NSArray<NSNumber *> *size = gCCACustomSizes[identifier];
        if (size.count >= 2) rect.size = (CCUILayoutSize){size[0].unsignedIntegerValue, size[1].unsignedIntegerValue};
        if (CCAPagedRectIsValid(rect)) globalOccupied[identifier] = [NSValue value:&rect withObjCType:@encode(CCUILayoutRect)];
    }
    for (NSString *identifier in remaining) {
        CCUILayoutRect candidate = {};
        [proposed[identifier] getValue:&candidate];
        BOOL overlapsPlaced = NO;
        for (NSString *blockerID in placed) {
            CCUILayoutRect blocker = {};
            [proposed[blockerID] getValue:&blocker];
            if (CCALogicalRectsOverlap(candidate, blocker)) { overlapsPlaced = YES; break; }
        }
        if (overlapsPlaced) {
            CCUILayoutRect original = candidate;
            BOOL found = NO;
            NSUInteger bestDistance = NSUIntegerMax;
            CCUILayoutRect best = {};
            for (NSUInteger row = 0; row + candidate.size.height <= kCCAMinimumGridRows; row++) {
                for (NSUInteger column = 0; column + candidate.size.width <= 4; column++) {
                    CCUILayoutRect trial = candidate;
                    trial.origin = (CCUILayoutPoint){column, row};
                    BOOL fitsPlaced = YES;
                    for (NSString *blockerID in placed) {
                        CCUILayoutRect blocker = {};
                        [proposed[blockerID] getValue:&blocker];
                        if (CCALogicalRectsOverlap(trial, blocker)) { fitsPlaced = NO; break; }
                    }
                    if (!fitsPlaced) continue;
                    NSUInteger horizontal = column > original.origin.x ? column - original.origin.x : original.origin.x - column;
                    NSUInteger vertical = row > original.origin.y ? row - original.origin.y : original.origin.y - row;
                    NSUInteger distance = horizontal + vertical;
                    // Prefer the closest legal footprint. For an equal move,
                    // favor upward placement, then retain the original column.
                    BOOL betterTie = found && distance == bestDistance &&
                        (row < best.origin.y || (row == best.origin.y && horizontal < (best.origin.x > original.origin.x ? best.origin.x - original.origin.x : original.origin.x - best.origin.x)));
                    if (!found || distance < bestDistance || betterTie) {
                        found = YES;
                        bestDistance = distance;
                        best = trial;
                    }
                }
            }
            if (!found) {
                [globalOccupied removeObjectForKey:identifier];
                CCUILayoutPoint overflowDestination = {};
                if (!CCAFindPagedSlot(identifier, candidate.size, gCCACurrentPage + 1, globalOccupied, &overflowDestination)) return NO;
                overflowOrigins[identifier] = @[@(overflowDestination.x), @(overflowDestination.y)];
                CCUILayoutRect overflowRect = {overflowDestination, candidate.size};
                globalOccupied[identifier] = [NSValue value:&overflowRect withObjCType:@encode(CCUILayoutRect)];
                [proposed removeObjectForKey:identifier];
                continue;
            }
            candidate = best;
        }
        proposed[identifier] = [NSValue value:&candidate withObjCType:@encode(CCUILayoutRect)];
        [placed addObject:identifier];
    }

    // Nothing is committed unless the complete post-resize layout fits inside
    // the fixed 4x8 grid.  This also rejects unchanged modules that were pushed
    // or inherited into an illegal ninth row.
    if (!CCALogicalLayoutIsLegal(proposed, kCCAMinimumGridRows)) return NO;

    for (NSString *identifier in proposed) {
        CCUILayoutRect before = {}, after = {};
        [initial[identifier] getValue:&before]; [proposed[identifier] getValue:&after];
        if (before.origin.x != after.origin.x || before.origin.y != after.origin.y) gCCACustomOrigins[identifier] = @[@(after.origin.x), @(pageStart + after.origin.y)];
    }
    [gCCACustomOrigins addEntriesFromDictionary:overflowOrigins];
    gCCACustomSizes[sourceID] = @[@(newSize.width), @(newSize.height)];
    CFPreferencesSetAppValue(CFSTR("ModuleGridOrigins"), (__bridge CFPropertyListRef)[gCCACustomOrigins copy], kCCAPrefsDomain);
    CFPreferencesSetAppValue(CFSTR("ModuleGridSizes"), (__bridge CFPropertyListRef)[gCCACustomSizes copy], kCCAPrefsDomain);
    CFPreferencesAppSynchronize(kCCAPrefsDomain);

    UIViewController *matchingModule = nil;
    for (UIViewController *candidate in CCACollectModuleControllers(overlay)) if ([CCAModuleIdentifier(candidate) isEqualToString:sourceID]) { matchingModule = candidate; break; }
    id context = nil;
    @try {
        id contentModule = [matchingModule valueForKey:@"module"];
        context = [contentModule valueForKey:@"contentModuleContext"];
    } @catch (__unused NSException *exception) {}
    if ([context respondsToSelector:NSSelectorFromString(@"requestLayoutSizeUpdate")]) ((void (*)(id, SEL))objc_msgSend)(context, NSSelectorFromString(@"requestLayoutSizeUpdate"));
    UIViewController *collection = [self moduleCollectionControllerInOverlay:overlay];
    [collection.view setNeedsLayout];
    [UIView animateWithDuration:0.24 animations:^{ [collection.view layoutIfNeeded]; } completion:^(__unused BOOL finished) {
        for (UIViewController *candidate in CCACollectModuleControllers(overlay)) [self applyEditingToModule:candidate editing:YES];
        // The edit grid caches the module frames that hide its vacant-cell
        // circles. A resize changes the footprint without recreating edit mode,
        // so refresh that cache as soon as the native layout has settled.
        if (gEditModeActive) {
            [self prepareGridForOverlay:overlay collection:collection];
            NSMutableDictionary<NSNumber *, CCAEditGridView *> *pageGrids = objc_getAssociatedObject(overlay, kCCAEditPageGridsKey);
            for (CCAEditGridView *pageGrid in pageGrids.allValues) pageGrid.alpha = gCCAPagerScrubbingActive ? gCCAPagerHeldAlphaFactor : 1.0;
            CCAEditTouchShield *shield = (CCAEditTouchShield *)[overlay.view viewWithTag:kCCAEditTouchShieldTag];
            if (shield) [overlay.view bringSubviewToFront:shield];
            UIButton *settledAddControl = (UIButton *)[overlay.view viewWithTag:kCCAAddControlButtonTag];
            if (settledAddControl) [overlay.view bringSubviewToFront:settledAddControl];
            for (UIViewController *candidate in CCACollectModuleControllers(overlay)) {
                UIButton *remove = objc_getAssociatedObject(candidate.view, kCCARemoveButtonKey);
                UIButton *resize = objc_getAssociatedObject(candidate.view, kCCAResizeButtonKey);
                if (remove) [remove.superview bringSubviewToFront:remove];
                if (resize) [resize.superview bringSubviewToFront:resize];
            }
        }
    }];
    return YES;
}

- (CCUILayoutSize)currentResizeSizeForIdentifier:(NSString *)identifier base:(CCUILayoutSize)base {
    NSArray<NSNumber *> *saved = gCCACustomSizes[identifier];
    return saved.count >= 2 ? (CCUILayoutSize){saved[0].unsignedIntegerValue, saved[1].unsignedIntegerValue} : base;
}

- (CCUILayoutSize)resizeCandidateForIdentifier:(NSString *)identifier base:(CCUILayoutSize)base start:(CCUILayoutSize)start translation:(CGPoint)translation {
    BOOL isNowPlaying = [identifier isEqualToString:@"com.apple.mediaremote.controlcenter.nowplaying"];
    if (isNowPlaying && base.width == 2 && base.height == 2) {
        CGFloat desiredWidth = (CGFloat)start.width + translation.x / kCCAGridStep;
        CGFloat desiredHeight = (CGFloat)start.height + translation.y / kCCAGridStep;
        if (desiredWidth < 3.0) return (CCUILayoutSize){2, 2};
        if (desiredHeight < 1.5) return (CCUILayoutSize){4, 1};
        if (desiredHeight >= 3.0) return (CCUILayoutSize){4, 4};
        return (CCUILayoutSize){4, 2};
    }
    if (base.width == 1 && base.height == 1) {
        CGFloat desiredWidth = (CGFloat)start.width + translation.x / kCCAGridStep;
        CGFloat desiredHeight = (CGFloat)start.height + translation.y / kCCAGridStep;
        if (desiredHeight >= 1.5) return (CCUILayoutSize){2, 2};
        if (desiredWidth >= 1.5) return (CCUILayoutSize){2, 1};
        return (CCUILayoutSize){1, 1};
    }
    if (base.width == 2 && base.height == 2) {
        CGFloat desiredWidth = (CGFloat)start.width + translation.x / kCCAGridStep;
        return desiredWidth >= 3.0 ? (CCUILayoutSize){4, 2} : (CCUILayoutSize){2, 2};
    }
    return base;
}

- (CGRect)liveResizeFrameForIdentifier:(NSString *)identifier base:(CCUILayoutSize)base startSize:(CCUILayoutSize)start startFrame:(CGRect)startFrame translation:(CGPoint)translation {
    CGRect frame = startFrame;
    BOOL isNowPlaying = [identifier isEqualToString:@"com.apple.mediaremote.controlcenter.nowplaying"];
    if (isNowPlaying && base.width == 2 && base.height == 2) {
        CGFloat twoCellSize = kCCAGridCellSize * 2.0 + kCCAGridGap;
        CGFloat fourCellSize = kCCAGridCellSize * 4.0 + kCCAGridGap * 3.0;
        CGFloat width = MIN(fourCellSize, MAX(twoCellSize, CGRectGetWidth(startFrame) + translation.x));
        CGFloat minimumHeight = width >= (twoCellSize + fourCellSize) * 0.5 ? kCCAGridCellSize : twoCellSize;
        CGFloat height = MIN(fourCellSize, MAX(minimumHeight, CGRectGetHeight(startFrame) + translation.y));
        frame.size = CGSizeMake(width, height);
        return frame;
    }
    if (base.width == 1 && base.height == 1) {
        CGFloat twoCellSize = kCCAGridCellSize * 2.0 + kCCAGridGap;
        CGFloat width = MIN(twoCellSize, MAX(kCCAGridCellSize, CGRectGetWidth(startFrame) + translation.x));
        CGFloat height = MIN(twoCellSize, MAX(kCCAGridCellSize, CGRectGetHeight(startFrame) + translation.y));
        if (start.height == 1 && height > kCCAGridCellSize) width = MAX(width, height);
        if (start.width == 2 && height > kCCAGridCellSize) width = twoCellSize;
        frame.size = CGSizeMake(width, height);
    } else if (base.width == 2 && base.height == 2) {
        CGFloat twoCellSize = kCCAGridCellSize * 2.0 + kCCAGridGap;
        CGFloat fourCellSize = kCCAGridCellSize * 4.0 + kCCAGridGap * 3.0;
        frame.size = CGSizeMake(MIN(fourCellSize, MAX(twoCellSize, CGRectGetWidth(startFrame) + translation.x)), twoCellSize);
    }
    return frame;
}

- (void)resizePanned:(UIPanGestureRecognizer *)gesture {
    UIButton *handle = (UIButton *)gesture.view;
    NSString *identifier = objc_getAssociatedObject(handle, @selector(resizePanned:));
    NSValue *baseValue = gCCABaseLayoutSizes[identifier];
    if (![self moduleIdentifierSupportsResizing:identifier] || !baseValue) return;
    CCUILayoutSize base = {};
    [baseValue getValue:&base];
    UIViewController *overlay = gOverlayControllers.allObjects.firstObject;

    if (gesture.state == UIGestureRecognizerStateBegan) {
        CCUILayoutSize start = [self currentResizeSizeForIdentifier:identifier base:base];
        NSValue *startValue = [NSValue value:&start withObjCType:@encode(CCUILayoutSize)];
        objc_setAssociatedObject(gesture, kCCAResizeStartSizeKey, startValue, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(gesture, kCCAResizeCandidateSizeKey, startValue, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        UIView *moduleView = objc_getAssociatedObject(handle, kCCARemoveModuleViewKey);
        gCCAResizeInProgress = YES;
        gCCAActiveResizeModuleView = moduleView;
        if (overlay.view) {
            NSMutableArray<UIGestureRecognizer *> *suppressed = [NSMutableArray array];
            NSMutableArray<UIView *> *viewQueue = [NSMutableArray arrayWithObject:overlay.view];
            while (viewQueue.count) {
                UIView *view = viewQueue.firstObject;
                [viewQueue removeObjectAtIndex:0];
                for (UIGestureRecognizer *other in view.gestureRecognizers) {
                    if (other == gesture || !other.enabled) continue;
                    if ([other isKindOfClass:[UIPanGestureRecognizer class]]) {
                        other.enabled = NO;
                        [suppressed addObject:other];
                    }
                }
                [viewQueue addObjectsFromArray:view.subviews];
            }
            objc_setAssociatedObject(gesture, kCCAResizeSuppressedGesturesKey, suppressed, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if (moduleView) {
            CGRect startFrame = CGRectMake(CGRectGetMinX(moduleView.frame), CGRectGetMinY(moduleView.frame), CGRectGetWidth(moduleView.bounds), CGRectGetHeight(moduleView.bounds));
            objc_setAssociatedObject(gesture, kCCAResizePreviewStartFrameKey, [NSValue valueWithCGRect:startFrame], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            UIView *buttonView = CCAFindSubviewWithClassName(moduleView, @"CCUIButtonModuleView");
            // Modules without a button hierarchy (now playing) host the snap
            // preview override on the module view itself so descendant layout
            // (CCAResizedPreviewSizeForDescendant) tracks the candidate size.
            UIView *overrideHost = buttonView ?: moduleView;
            if (overrideHost) {
                objc_setAssociatedObject(overrideHost, kCCAResizePreviewKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                objc_setAssociatedObject(overrideHost, kCCAResizePresentationSizeOverrideKey, @[@(start.width), @(start.height)], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        }
        [UIView animateWithDuration:0.12 animations:^{ handle.transform = CGAffineTransformMakeScale(1.08, 1.08); handle.alpha = 1.0; }];
        CCAHaptic();
        return;
    }

    CCUILayoutSize start = {};
    [objc_getAssociatedObject(gesture, kCCAResizeStartSizeKey) getValue:&start];
    UIView *moduleView = objc_getAssociatedObject(handle, kCCARemoveModuleViewKey);
    CGRect startFrame = [objc_getAssociatedObject(gesture, kCCAResizePreviewStartFrameKey) CGRectValue];
    UIView *wrapper = moduleView.superview;
    CGPoint translation = [gesture translationInView:wrapper ?: handle.superview];
    CCUILayoutSize candidate = [self resizeCandidateForIdentifier:identifier base:base start:start translation:translation];
    if (moduleView && wrapper && !CGRectIsEmpty(startFrame)) {
        CGRect liveFrame = [self liveResizeFrameForIdentifier:identifier base:base startSize:start startFrame:startFrame translation:translation];
        [UIView performWithoutAnimation:^{
            moduleView.frame = liveFrame;
            moduleView.layer.cornerRadius = [self editingModuleCornerRadiusForSize:liveFrame.size];
            UIVisualEffectView *border = objc_getAssociatedObject(moduleView, @selector(applyEditingToModule:editing:));
            [self configureEditingBorder:border moduleFrame:liveFrame];
            if (overlay) {
                UIView *handleHost = handle.superview ?: overlay.view;
                CGRect handleFrame = handleHost == wrapper ? liveFrame : [wrapper convertRect:liveFrame toView:handleHost];
                handle.frame = CGRectMake(CGRectGetMaxX(handleFrame) - 42.0, CGRectGetMaxY(handleFrame) - 42.0, 42.0, 42.0);
                CGRect visibleFrame = [wrapper convertRect:liveFrame toView:overlay.view];
                // Treat the live resize footprint like a drag landing region so
                // newly covered vacant-cell circles fade before the snap commits.
                NSValue *layoutValue = gCCANativeLayoutRects[identifier];
                NSUInteger page = gCCACurrentPage;
                if (layoutValue) {
                    CCUILayoutRect rect = {};
                    [layoutValue getValue:&rect];
                    NSArray<NSNumber *> *origin = gCCACustomOrigins[identifier];
                    if (origin.count >= 2) rect.origin = (CCUILayoutPoint){origin[0].unsignedIntegerValue, origin[1].unsignedIntegerValue};
                    page = CCAPageForRect(rect);
                }
                [self setEditGridLandingRects:@[[NSValue valueWithCGRect:visibleFrame]] forPage:page overlay:overlay];
            }
        }];
    }
    NSValue *priorValue = objc_getAssociatedObject(gesture, kCCAResizeCandidateSizeKey);
    CCUILayoutSize prior = {};
    [priorValue getValue:&prior];
    if (candidate.width != prior.width || candidate.height != prior.height) {
        objc_setAssociatedObject(gesture, kCCAResizeCandidateSizeKey, [NSValue value:&candidate withObjCType:@encode(CCUILayoutSize)], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        UIView *buttonView = CCAFindSubviewWithClassName(moduleView, @"CCUIButtonModuleView");
        UIView *overrideHost = buttonView ?: moduleView;
        if (overrideHost) objc_setAssociatedObject(overrideHost, kCCAResizePresentationSizeOverrideKey, @[@(candidate.width), @(candidate.height)], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if ([identifier isEqualToString:@"com.apple.mediaremote.controlcenter.nowplaying"]) {
            for (UIView *view = moduleView; view; view = view.superview) [view setNeedsLayout];
            [moduleView layoutIfNeeded];
        }
        CCAHaptic();
    }

    if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled || gesture.state == UIGestureRecognizerStateFailed) {
        [UIView animateWithDuration:0.16 animations:^{ handle.transform = CGAffineTransformIdentity; handle.alpha = 1.0; }];
        BOOL committed = NO;
        UIView *buttonView = CCAFindSubviewWithClassName(moduleView, @"CCUIButtonModuleView");
        if (gesture.state == UIGestureRecognizerStateEnded && (candidate.width != start.width || candidate.height != start.height)) {
            // The private button hierarchy recenters one of its intermediate
            // glyph containers during the native resize. Preserve the exact
            // on-screen glyph above that moving hierarchy until it settles;
            // otherwise a correct endpoint correction appears as an opposite-
            // direction jump during the animation.
            if (base.width == 1 && base.height == 1 && overlay.view) {
                CCABeginResizeGlyphHandoff(moduleView, buttonView, overlay.view);
            }
            committed = [self applyGridResizeForIdentifier:identifier size:candidate overlay:overlay];
            if (!committed) {
                CCAEndResizeGlyphHandoff(moduleView);
                UINotificationFeedbackGenerator *feedback = [UINotificationFeedbackGenerator new];
                [feedback notificationOccurred:UINotificationFeedbackTypeWarning];
            }
        }
        if (committed) {
            // Native layout begins as soon as applyGridResize returns. Release
            // the preview suppression now so every layout frame during that
            // animation reapplies the invariant compact glyph anchor.
            UIView *commitOverrideHost = buttonView ?: moduleView;
            if (commitOverrideHost) {
                objc_setAssociatedObject(commitOverrideHost, kCCAResizePreviewKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                objc_setAssociatedObject(commitOverrideHost, kCCAResizePresentationSizeOverrideKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            CGRect endpointFrame = startFrame;
            endpointFrame.size = CGSizeMake(kCCAGridCellSize + (candidate.width - 1) * kCCAGridStep,
                                            kCCAGridCellSize + (candidate.height - 1) * kCCAGridStep);
            UIVisualEffectView *border = objc_getAssociatedObject(moduleView, @selector(applyEditingToModule:editing:));
            [UIView animateWithDuration:0.24 delay:0.0 options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionBeginFromCurrentState animations:^{
                moduleView.frame = endpointFrame;
                moduleView.layer.cornerRadius = [self editingModuleCornerRadiusForSize:endpointFrame.size];
                [self configureEditingBorder:border moduleFrame:endpointFrame];
                if (overlay && wrapper) {
                    UIView *handleHost = handle.superview ?: overlay.view;
                    CGRect handleFrame = handleHost == wrapper ? endpointFrame : [wrapper convertRect:endpointFrame toView:handleHost];
                    handle.frame = CGRectMake(CGRectGetMaxX(handleFrame) - 42.0, CGRectGetMaxY(handleFrame) - 42.0, 42.0, 42.0);
                }
            } completion:nil];
            for (UIViewController *module in CCACollectModuleControllers(overlay)) {
                if (module.view == moduleView) { [self applyResizedPresentationToModule:module]; break; }
            }
        }
        void (^finishPreview)(void) = ^{
            NSArray<UIGestureRecognizer *> *suppressedGestures = objc_getAssociatedObject(gesture, kCCAResizeSuppressedGesturesKey);
            for (UIGestureRecognizer *suppressed in suppressedGestures) suppressed.enabled = YES;
            objc_setAssociatedObject(gesture, kCCAResizeSuppressedGesturesKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            UIView *finishOverrideHost = buttonView ?: moduleView;
            if (finishOverrideHost) {
                objc_setAssociatedObject(finishOverrideHost, kCCAResizePreviewKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                objc_setAssociatedObject(finishOverrideHost, kCCAResizePresentationSizeOverrideKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            [self clearEditGridLandingRectsForOverlay:overlay];
            if (moduleView && !committed && !CGRectIsEmpty(startFrame)) {
                moduleView.frame = startFrame;
                moduleView.layer.cornerRadius = [self editingModuleCornerRadiusForSize:startFrame.size];
                UIVisualEffectView *border = objc_getAssociatedObject(moduleView, @selector(applyEditingToModule:editing:));
                [self configureEditingBorder:border moduleFrame:startFrame];
                if (overlay && wrapper) {
                    UIView *handleHost = handle.superview ?: overlay.view;
                    CGRect handleFrame = handleHost == wrapper ? startFrame : [wrapper convertRect:startFrame toView:handleHost];
                    handle.frame = CGRectMake(CGRectGetMaxX(handleFrame) - 42.0, CGRectGetMaxY(handleFrame) - 42.0, 42.0, 42.0);
                }
            }
            gCCAResizeInProgress = NO;
            gCCAActiveResizeModuleView = nil;
            for (UIViewController *module in CCACollectModuleControllers(overlay)) {
                if (module.view == moduleView) {
                    [self applyEditingToModule:module editing:gEditModeActive];
                    [self applyResizedPresentationToModule:module];
                    break;
                }
            }
            CCAEndResizeGlyphHandoff(moduleView);
        };
        if (committed) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.30 * NSEC_PER_SEC)), dispatch_get_main_queue(), finishPreview);
        else [UIView animateWithDuration:0.20 animations:finishPreview];
        objc_setAssociatedObject(gesture, kCCAResizeStartSizeKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(gesture, kCCAResizeCandidateSizeKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(gesture, kCCAResizePreviewStartFrameKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

- (void)modulePanned:(UIGestureRecognizer *)gesture {
    UIViewController *overlay = nil;
    UIResponder *responder = gesture.view;
    while (responder && ![responder isKindOfClass:[UIViewController class]]) responder = responder.nextResponder;
    if ([responder isKindOfClass:[UIViewController class]]) overlay = (UIViewController *)responder;
    if (!overlay) overlay = gOverlayControllers.allObjects.firstObject;
    UIView *moduleView = objc_getAssociatedObject(gesture, @selector(moduleControllerForShield:));
    NSString *sourceID = objc_getAssociatedObject(gesture, @selector(modulePanned:));
    CGPoint currentPoint = [gesture locationInView:overlay.view];
    CGPoint startPoint = [objc_getAssociatedObject(gesture, kCCADragStartPointKey) CGPointValue];
    CGPoint translation = CGPointMake(currentPoint.x - startPoint.x, currentPoint.y - startPoint.y);
    if (gesture.state == UIGestureRecognizerStateBegan) {
        if (gCCAPagerTransitionActive || gCCAPagerScrubbingActive || gCCAPresentationPageHandoffActive) {
            gesture.enabled = NO;
            gesture.enabled = YES;
            return;
        }
        CGPoint location = currentPoint;
        UIViewController *source = nil;
        CGFloat sourceDistance = CGFLOAT_MAX;
        for (UIViewController *candidate in CCACollectModuleControllers(overlay)) {
            CGRect frame = CCAVisibleModuleFrame(candidate, overlay);
            CGFloat distance = hypot(CGRectGetMidX(frame) - location.x, CGRectGetMidY(frame) - location.y);
            if (CGRectContainsPoint(CGRectInset(frame, -14.0, -14.0), location) && distance < sourceDistance) {
                source = candidate;
                sourceDistance = distance;
            }
        }
        moduleView = source.view;
        sourceID = CCAModuleIdentifier(source);
        if (!sourceID.length || !moduleView) { gesture.enabled = NO; gesture.enabled = YES; return; }
        gCCADragInProgress = YES;
        gCCAActiveDragModuleView = moduleView;
        gCCAActiveDragModuleIdentifier = [sourceID copy];
        objc_setAssociatedObject(gesture, @selector(moduleControllerForShield:), moduleView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(gesture, @selector(modulePanned:), sourceID, OBJC_ASSOCIATION_COPY_NONATOMIC);
        objc_setAssociatedObject(gesture, kCCADragStartPointKey, [NSValue valueWithCGPoint:location], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        CGRect visibleSourceFrame = CCAVisibleModuleFrame(source, overlay);
        CGPoint grabOffset = CGPointMake(location.x - CGRectGetMinX(visibleSourceFrame), location.y - CGRectGetMinY(visibleSourceFrame));
        objc_setAssociatedObject(gesture, kCCADragGrabOffsetKey, [NSValue valueWithCGPoint:grabOffset], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(gesture, kCCADragMovedKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        NSArray *baseOrder = gCCAProviderOrder.count ? gCCAProviderOrder : [self enabledModuleIdentifiers];
        objc_setAssociatedObject(gesture, kCCADragBaseOrderKey, [baseOrder copy], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        UIView *proxy = [[UIView alloc] initWithFrame:CCAVisibleModuleFrame(source, overlay)];
        proxy.bounds = (CGRect){CGPointZero, moduleView.bounds.size};
        proxy.layer.cornerRadius = moduleView.layer.cornerRadius;
        proxy.layer.cornerCurve = kCACornerCurveContinuous;
        proxy.clipsToBounds = NO;
        proxy.userInteractionEnabled = NO;
        UIView *buttonView = CCAFindSubviewWithClassName(moduleView, @"CCUIButtonModuleView");
        BOOL selectedButton = [buttonView isKindOfClass:[UIControl class]] && [(UIControl *)buttonView isSelected];
        UIView *proxyMaterial = nil;
        if (selectedButton) {
            proxyMaterial = [[UIView alloc] initWithFrame:proxy.bounds];
            proxyMaterial.backgroundColor = [UIColor colorWithWhite:0.96 alpha:0.92];
        } else {
            proxyMaterial = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark]];
            proxyMaterial.frame = proxy.bounds;
        }
        proxyMaterial.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        proxyMaterial.userInteractionEnabled = NO;
        proxyMaterial.layer.cornerRadius = moduleView.layer.cornerRadius;
        proxyMaterial.layer.cornerCurve = kCACornerCurveContinuous;
        proxyMaterial.clipsToBounds = YES;
        [proxy addSubview:proxyMaterial];
        // Material and the edit ring are already owned by the proxy. Capture
        // only module content so the wrapper's original border cannot become a
        // second ring or a stationary-looking ghost in the drag snapshot.
        UIView *proxyContent = [moduleView snapshotViewAfterScreenUpdates:YES];
        if (!proxyContent) proxyContent = [moduleView resizableSnapshotViewFromRect:moduleView.bounds afterScreenUpdates:YES withCapInsets:UIEdgeInsetsZero];
        proxyContent.frame = proxy.bounds;
        proxyContent.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        proxyContent.userInteractionEnabled = NO;
        proxyContent.layer.cornerRadius = moduleView.layer.cornerRadius;
        proxyContent.layer.cornerCurve = kCACornerCurveContinuous;
        proxyContent.clipsToBounds = YES;
        [proxy addSubview:proxyContent];
        UIVisualEffectView *proxyBorder = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialLight]];
        proxyBorder.frame = proxy.bounds;
        proxyBorder.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        proxyBorder.userInteractionEnabled = NO;
        CGFloat proxyRadius = moduleView.layer.cornerRadius;
        UIBezierPath *proxyRing = [UIBezierPath bezierPathWithRoundedRect:proxyBorder.bounds cornerRadius:proxyRadius];
        [proxyRing appendPath:[UIBezierPath bezierPathWithRoundedRect:CGRectInset(proxyBorder.bounds, 3.5, 3.5) cornerRadius:MAX(0.0, proxyRadius - 3.5)]];
        CAShapeLayer *proxyMask = [CAShapeLayer layer];
        proxyMask.path = proxyRing.CGPath;
        proxyMask.fillRule = kCAFillRuleEvenOdd;
        proxyBorder.layer.mask = proxyMask;
        [proxy addSubview:proxyBorder];
        UIButton *sourceRemove = objc_getAssociatedObject(moduleView, kCCARemoveButtonKey);
        UIButton *sourceResize = objc_getAssociatedObject(moduleView, kCCAResizeButtonKey);
        for (UIButton *chromeButton in @[sourceRemove ?: (UIButton *)NSNull.null, sourceResize ?: (UIButton *)NSNull.null]) {
            if ((id)chromeButton == NSNull.null || chromeButton.hidden || chromeButton.alpha <= 0.01) continue;
            UIView *chromeSnapshot = [[UIView alloc] initWithFrame:chromeButton.bounds];
            chromeSnapshot.backgroundColor = UIColor.clearColor;
            chromeSnapshot.opaque = NO;
            if (chromeButton.tag == kCCARemoveButtonTag) {
                UIVisualEffectView *bubble = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterialLight]];
                bubble.frame = CGRectMake(9.0, 9.0, 26.0, 26.0);
                bubble.layer.cornerRadius = 13.0;
                bubble.clipsToBounds = YES;
                bubble.userInteractionEnabled = NO;
                [chromeSnapshot addSubview:bubble];
                UIImageView *minusGlyph = [[UIImageView alloc] initWithImage:[[self symbol:@"minus" size:13.0] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
                minusGlyph.tintColor = UIColor.blackColor;
                minusGlyph.contentMode = UIViewContentModeCenter;
                minusGlyph.frame = CGRectMake(9.0, 9.0, 26.0, 26.0);
                minusGlyph.userInteractionEnabled = NO;
                [chromeSnapshot addSubview:minusGlyph];
            } else if (chromeButton.tag == kCCAResizeButtonTag) {
                UIBezierPath *cornerPath = [UIBezierPath bezierPath];
                [cornerPath moveToPoint:CGPointMake(20.29, 40.01)];
                [cornerPath addCurveToPoint:CGPointMake(40.01, 20.29)
                              controlPoint1:CGPointMake(31.20, 40.01)
                              controlPoint2:CGPointMake(40.01, 31.20)];
                UIVisualEffectView *grabberMaterial = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialLight]];
                grabberMaterial.frame = chromeSnapshot.bounds;
                grabberMaterial.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
                grabberMaterial.userInteractionEnabled = NO;
                CAShapeLayer *materialMask = [CAShapeLayer layer];
                materialMask.path = cornerPath.CGPath;
                materialMask.fillColor = UIColor.clearColor.CGColor;
                materialMask.strokeColor = UIColor.blackColor.CGColor;
                materialMask.lineWidth = 12.0;
                materialMask.lineCap = kCALineCapRound;
                materialMask.lineJoin = kCALineJoinRound;
                grabberMaterial.layer.mask = materialMask;
                [chromeSnapshot addSubview:grabberMaterial];
                CAShapeLayer *pill = [CAShapeLayer layer];
                pill.path = cornerPath.CGPath;
                pill.fillColor = UIColor.clearColor.CGColor;
                pill.strokeColor = [UIColor.whiteColor colorWithAlphaComponent:0.82].CGColor;
                pill.lineWidth = 12.5;
                pill.lineCap = kCALineCapRound;
                pill.lineJoin = kCALineJoinRound;
                [chromeSnapshot.layer addSublayer:pill];
            } else {
                UIView *fallbackSnapshot = [chromeButton snapshotViewAfterScreenUpdates:NO];
                if (!fallbackSnapshot) fallbackSnapshot = [chromeButton resizableSnapshotViewFromRect:chromeButton.bounds afterScreenUpdates:NO withCapInsets:UIEdgeInsetsZero];
                if (!fallbackSnapshot) continue;
                fallbackSnapshot.frame = chromeSnapshot.bounds;
                fallbackSnapshot.userInteractionEnabled = NO;
                [chromeSnapshot addSubview:fallbackSnapshot];
            }
            CGRect overlayChromeFrame = [chromeButton convertRect:chromeButton.bounds toView:overlay.view];
            chromeSnapshot.frame = [overlay.view convertRect:overlayChromeFrame toView:proxy];
            chromeSnapshot.autoresizingMask = UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleBottomMargin;
            chromeSnapshot.userInteractionEnabled = NO;
            [proxy addSubview:chromeSnapshot];
        }
        [overlay.view addSubview:proxy];
        objc_setAssociatedObject(gesture, kCCADragProxyKey, proxy, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(gesture, kCCADragProxyStartFrameKey, [NSValue valueWithCGRect:proxy.frame], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        NSMutableDictionary<NSString *, NSValue *> *baseFrames = [NSMutableDictionary dictionary];
        for (UIViewController *candidate in CCACollectModuleControllers(overlay)) {
            NSString *candidateID = CCAModuleIdentifier(candidate);
            if (candidateID.length) baseFrames[candidateID] = [NSValue valueWithCGRect:CCAVisibleModuleFrame(candidate, overlay)];
        }
        objc_setAssociatedObject(gesture, kCCADragBaseFramesKey, baseFrames, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        NSUInteger sourcePage = gCCACurrentPage;
        CCUILayoutRect sourceLogical = {};
        BOOL hasSourceLogical = NO;
        NSValue *layoutValue = gCCANativeLayoutRects[sourceID];
        if (layoutValue) {
            [layoutValue getValue:&sourceLogical];
            NSArray<NSNumber *> *origin = gCCACustomOrigins[sourceID];
            if (origin.count >= 2) sourceLogical.origin = (CCUILayoutPoint){origin[0].unsignedIntegerValue, origin[1].unsignedIntegerValue};
            NSArray<NSNumber *> *size = gCCACustomSizes[sourceID];
            if (size.count >= 2) sourceLogical.size = (CCUILayoutSize){size[0].unsignedIntegerValue, size[1].unsignedIntegerValue};
            sourcePage = CCAPageForRect(sourceLogical);
            hasSourceLogical = sourceLogical.size.width > 0 && sourceLogical.size.height > 0;
        }
        objc_setAssociatedObject(gesture, kCCADragStartPageKey, @(sourcePage), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        CCAEditGridView *grid = [self editGridForPage:sourcePage overlay:overlay];
        if (!grid) grid = objc_getAssociatedObject(overlay, kCCAEditGridKey);
        grid.landingCornerRadius = moduleView.layer.cornerRadius;
        CGRect startFrame = [moduleView convertRect:moduleView.bounds toView:grid];
        if (hasSourceLogical && grid.columns > 0) {
            NSUInteger localRow = sourceLogical.origin.y % kCCAMinimumGridRows;
            NSUInteger slotIndex = localRow * grid.columns + sourceLogical.origin.x;
            if (slotIndex < grid.slotRects.count) {
                CGRect slot = grid.slotRects[slotIndex].CGRectValue;
                startFrame = CGRectMake(CGRectGetMinX(slot),
                                        CGRectGetMinY(slot),
                                        kCCAGridCellSize + (sourceLogical.size.width - 1) * kCCAGridStep,
                                        kCCAGridCellSize + (sourceLogical.size.height - 1) * kCCAGridStep);
            }
        }
        objc_setAssociatedObject(gesture, kCCADragStartFrameKey, [NSValue valueWithCGRect:startFrame], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        NSMutableArray<NSValue *> *remainingOccupied = [NSMutableArray array];
        for (NSValue *value in grid.occupiedRects) if (!CGRectIntersectsRect(value.CGRectValue, startFrame)) [remainingOccupied addObject:value];
        grid.occupiedRects = remainingOccupied;
        [grid setNeedsDisplay];
        CCAHaptic();
        UIButton *remove = objc_getAssociatedObject(moduleView, kCCARemoveButtonKey);
        UIButton *resize = objc_getAssociatedObject(moduleView, kCCAResizeButtonKey);
        NSMutableArray<NSDictionary *> *hiddenChrome = [NSMutableArray array];
        for (UIView *chrome in @[remove ?: (UIButton *)NSNull.null, resize ?: (UIButton *)NSNull.null]) {
            if ((id)chrome == NSNull.null) continue;
            [hiddenChrome addObject:@{@"view": chrome, @"hidden": @(chrome.hidden), @"alpha": @(chrome.alpha)}];
            chrome.hidden = YES;
            chrome.alpha = 0.0;
        }
        objc_setAssociatedObject(gesture, kCCADragHiddenChromeKey, hiddenChrome, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        UIVisualEffectView *dragBorder = objc_getAssociatedObject(moduleView, @selector(applyEditingToModule:editing:));
        moduleView.alpha = 0.0;
        dragBorder.alpha = 0.0;
        dragBorder.hidden = YES;
        [overlay.view bringSubviewToFront:proxy];
        [UIView animateWithDuration:0.16 animations:^{ proxy.transform = CGAffineTransformMakeScale(1.04, 1.04); proxy.alpha = 0.92; }];
    } else if (gesture.state == UIGestureRecognizerStateChanged) {
        if (!moduleView) return;
        BOOL moved = hypot(translation.x, translation.y) >= 9.0;
        if (moved) objc_setAssociatedObject(gesture, kCCADragMovedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        UIView *proxy = objc_getAssociatedObject(gesture, kCCADragProxyKey);
        // Translate in overlay coordinates first, then retain the small lifted
        // scale around the proxy.  Reversing these transforms scales the drag
        // distance too, which makes the independently hosted corner controls
        // drift farther away the longer the module is moved.
        proxy.transform = CGAffineTransformConcat(CGAffineTransformMakeTranslation(translation.x, translation.y), CGAffineTransformMakeScale(1.04, 1.04));
        CGRect proxyStartFrame = [objc_getAssociatedObject(gesture, kCCADragProxyStartFrameKey) CGRectValue];
        CGRect draggedFrame = CGRectOffset(proxyStartFrame, translation.x, translation.y);
        NSUInteger dragPage = MIN(gCCACurrentPage, gCCAPageCount ? gCCAPageCount - 1 : 0);
        objc_setAssociatedObject(gesture, kCCADragStartPageKey, @(dragPage), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        CCAEditGridView *grid = [self editGridForPage:dragPage overlay:overlay];
        if (!grid) grid = objc_getAssociatedObject(overlay, kCCAEditGridKey);
        // Edge dwell auto-paging: the finger must sit beyond the actual
        // first/last grid row for a beat. A fixed screen band fired while a
        // module was merely high or low on the current page.
        if (gPagingEnabled && moved && grid.slotRects.count) {
            CGRect gridBounds = CGRectNull;
            for (NSValue *slotValue in grid.slotRects) {
                CGRect slot = slotValue.CGRectValue;
                gridBounds = CGRectIsNull(gridBounds) ? slot : CGRectUnion(gridBounds, slot);
            }
            CGPoint pointInGrid = [overlay.view convertPoint:currentPoint toView:grid];
            CGFloat dwellMargin = MAX(18.0, kCCAGridGap + 8.0);
            NSInteger dwellDirection = 0;
            if (pointInGrid.y < CGRectGetMinY(gridBounds) - dwellMargin && gCCACurrentPage > 0) dwellDirection = -1;
            else if (pointInGrid.y > CGRectGetMaxY(gridBounds) + dwellMargin && gCCACurrentPage + 1 < gCCAPageCount) dwellDirection = 1;
            if (dwellDirection != 0) {
                NSNumber *storedDirection = objc_getAssociatedObject(gesture, kCCADragEdgeDwellDirectionKey);
                NSNumber *dwellStart = objc_getAssociatedObject(gesture, kCCADragEdgeDwellKey);
                if (!dwellStart || storedDirection.integerValue != dwellDirection) {
                    objc_setAssociatedObject(gesture, kCCADragEdgeDwellKey, @(CACurrentMediaTime()), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    objc_setAssociatedObject(gesture, kCCADragEdgeDwellDirectionKey, @(dwellDirection), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                } else if (CACurrentMediaTime() - dwellStart.doubleValue > 0.72) {
                    objc_setAssociatedObject(gesture, kCCADragEdgeDwellKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    objc_setAssociatedObject(gesture, kCCADragEdgeDwellDirectionKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    NSUInteger targetPage = dwellDirection < 0 ? gCCACurrentPage - 1 : gCCACurrentPage + 1;
                    CCAHaptic();
                    [self clearEditGridLandingRectsForOverlay:overlay];
                    [self setCurrentPage:targetPage forOverlay:overlay animated:YES];
                    objc_setAssociatedObject(gesture, kCCADragStartPageKey, @(targetPage), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    objc_setAssociatedObject(gesture, kCCADragLandingOriginKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    objc_setAssociatedObject(gesture, kCCADragPreviewTargetIDKey, nil, OBJC_ASSOCIATION_COPY_NONATOMIC);
                    objc_setAssociatedObject(gesture, kCCADragPendingTargetIDKey, nil, OBJC_ASSOCIATION_COPY_NONATOMIC);
                }
            } else {
                objc_setAssociatedObject(gesture, kCCADragEdgeDwellKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                objc_setAssociatedObject(gesture, kCCADragEdgeDwellDirectionKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        } else {
            objc_setAssociatedObject(gesture, kCCADragEdgeDwellKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(gesture, kCCADragEdgeDwellDirectionKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        CGRect startFrame = [objc_getAssociatedObject(gesture, kCCADragStartFrameKey) CGRectValue];
        CGPoint grabOffset = [objc_getAssociatedObject(gesture, kCCADragGrabOffsetKey) CGPointValue];
        CGPoint proposedOriginOverlay = CGPointMake(currentPoint.x - grabOffset.x, currentPoint.y - grabOffset.y);
        CGPoint proposedOriginGrid = [overlay.view convertPoint:proposedOriginOverlay toView:grid];
        CGRect proposed = (CGRect){proposedOriginGrid, startFrame.size};
        // Snap the proposed top-left corner to the nearest logical grid slot.
        // This is the destination for true anywhere placement even when no
        // other module exists beneath the dragged footprint.
        NSUInteger nearestSlot = NSNotFound;
        CGFloat nearestSlotDistance = CGFLOAT_MAX;
        NSUInteger footprintColumns = MAX(1, (NSUInteger)llround((CGRectGetWidth(startFrame) + kCCAGridGap) / kCCAGridStep));
        NSUInteger footprintRows = MAX(1, (NSUInteger)llround((CGRectGetHeight(startFrame) + kCCAGridGap) / kCCAGridStep));
        for (NSUInteger index = 0; index < grid.slotRects.count; index++) {
            NSUInteger column = index % grid.columns;
            NSUInteger row = index / grid.columns;
            CCUILayoutRect candidateRect = {(CCUILayoutPoint){column, row}, (CCUILayoutSize){footprintColumns, footprintRows}};
            if (!CCALogicalRectRespectsColumnBands(candidateRect) || column + footprintColumns > grid.columns || row + footprintRows > grid.rows) continue;
            CGRect slot = grid.slotRects[index].CGRectValue;
            CGFloat distance = hypot(CGRectGetMinX(slot) - CGRectGetMinX(proposed), CGRectGetMinY(slot) - CGRectGetMinY(proposed));
            if (distance < nearestSlotDistance) { nearestSlotDistance = distance; nearestSlot = index; }
        }
        if (moved && nearestSlot != NSNotFound && grid.columns > 0) {
            NSUInteger landingColumn = nearestSlot % grid.columns;
            NSUInteger landingRow = nearestSlot / grid.columns;
            objc_setAssociatedObject(gesture, kCCADragLandingOriginKey, @[@(landingColumn), @(landingRow)], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            NSMutableArray<NSValue *> *snappedLanding = [NSMutableArray array];
            for (NSUInteger dy = 0; dy < footprintRows; dy++) {
                for (NSUInteger dx = 0; dx < footprintColumns; dx++) {
                    NSUInteger slotIndex = (landingRow + dy) * grid.columns + landingColumn + dx;
                    if (slotIndex < grid.slotRects.count) [snappedLanding addObject:grid.slotRects[slotIndex]];
                }
            }
            [self setEditGridLandingRects:snappedLanding forPage:dragPage overlay:overlay];
        } else {
            objc_setAssociatedObject(gesture, kCCADragLandingOriginKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [self clearEditGridLandingRectsForOverlay:overlay];
        }

        // The proxy is the one geometry guaranteed to match what is visibly
        // under the finger. Use its unscaled frame for target acquisition so
        // edit-mode collection/grid translations cannot bias the drop row.
        CGPoint previewCenter = CGPointMake(CGRectGetMidX(draggedFrame), CGRectGetMidY(draggedFrame));
        UIViewController *previewTargetController = nil;
        CGFloat bestOverlap = 0.0;
        CGFloat previewDistance = CGFLOAT_MAX;
        NSDictionary<NSString *, NSValue *> *baseFrames = objc_getAssociatedObject(gesture, kCCADragBaseFramesKey);
        for (UIViewController *candidate in CCACollectModuleControllers(overlay)) {
            NSString *candidateID = CCAModuleIdentifier(candidate);
            if ([candidateID isEqualToString:sourceID]) continue;
            CGRect candidateFrame = [baseFrames[candidateID] CGRectValue];
            if (CGRectIsEmpty(candidateFrame)) continue;
            CGRect intersection = CGRectIntersection(draggedFrame, candidateFrame);
            CGFloat overlap = CGRectIsNull(intersection) ? 0.0 : CGRectGetWidth(intersection) * CGRectGetHeight(intersection);
            CGFloat requiredOverlap = MIN(CGRectGetWidth(draggedFrame) * CGRectGetHeight(draggedFrame), CGRectGetWidth(candidateFrame) * CGRectGetHeight(candidateFrame)) * 0.18;
            CGFloat distance = hypot(CGRectGetMidX(candidateFrame) - previewCenter.x, CGRectGetMidY(candidateFrame) - previewCenter.y);
            if (moved && overlap >= requiredOverlap && (overlap > bestOverlap + 1.0 || (fabs(overlap - bestOverlap) <= 1.0 && distance < previewDistance))) {
                bestOverlap = overlap;
                previewDistance = distance;
                previewTargetController = candidate;
            }
        }
        NSString *previewTargetID = CCAModuleIdentifier(previewTargetController);
        NSString *previousTargetID = objc_getAssociatedObject(gesture, kCCADragPreviewTargetIDKey);
        NSString *pendingTargetID = objc_getAssociatedObject(gesture, kCCADragPendingTargetIDKey);
        BOOL previewLocked = [objc_getAssociatedObject(gesture, kCCADragPreviewLockedKey) boolValue];
        if (!previewTargetID.length) {
            objc_setAssociatedObject(gesture, kCCADragPendingTargetIDKey, nil, OBJC_ASSOCIATION_COPY_NONATOMIC);
            if (previousTargetID.length) {
                objc_setAssociatedObject(gesture, kCCADragPreviewTargetIDKey, nil, OBJC_ASSOCIATION_COPY_NONATOMIC);
            }
            if (!previewLocked && previousTargetID.length) {
                [self applyLivePreviewOrder:objc_getAssociatedObject(gesture, kCCADragBaseOrderKey) overlay:overlay];
            }
        }
        if (!previewLocked && previewTargetID.length && ![previewTargetID isEqualToString:previousTargetID] && ![previewTargetID isEqualToString:pendingTargetID]) {
            objc_setAssociatedObject(gesture, kCCADragPendingTargetIDKey, previewTargetID, OBJC_ASSOCIATION_COPY_NONATOMIC);
            NSString *candidateTargetID = [previewTargetID copy];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.06 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                NSString *stillPending = objc_getAssociatedObject(gesture, kCCADragPendingTargetIDKey);
                if (gesture.state != UIGestureRecognizerStateChanged || ![stillPending isEqualToString:candidateTargetID]) return;
                NSMutableArray *previewOrder = [objc_getAssociatedObject(gesture, kCCADragBaseOrderKey) mutableCopy];
                NSUInteger sourceIndex = [previewOrder indexOfObject:sourceID];
                NSUInteger targetIndex = [previewOrder indexOfObject:candidateTargetID];
                if (sourceIndex == NSNotFound || targetIndex == NSNotFound) return;
                [previewOrder exchangeObjectAtIndex:sourceIndex withObjectAtIndex:targetIndex];
                objc_setAssociatedObject(gesture, kCCADragPreviewTargetIDKey, candidateTargetID, OBJC_ASSOCIATION_COPY_NONATOMIC);
                objc_setAssociatedObject(gesture, kCCADragPreviewLockedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                [self applyLivePreviewOrder:previewOrder overlay:overlay];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.22 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    NSString *committedTarget = objc_getAssociatedObject(gesture, kCCADragPreviewTargetIDKey);
                    if (gesture.state == UIGestureRecognizerStateChanged && [committedTarget isEqualToString:candidateTargetID] && [self layoutHasIllegalOverlapInOverlay:overlay]) {
                        objc_setAssociatedObject(gesture, kCCADragPreviewTargetIDKey, nil, OBJC_ASSOCIATION_COPY_NONATOMIC);
                        objc_setAssociatedObject(gesture, kCCADragPendingTargetIDKey, nil, OBJC_ASSOCIATION_COPY_NONATOMIC);
                        [self applyLivePreviewOrder:objc_getAssociatedObject(gesture, kCCADragBaseOrderKey) overlay:overlay];
                        [self clearEditGridLandingRectsForOverlay:overlay];
                    }
                });
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.26 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    objc_setAssociatedObject(gesture, kCCADragPreviewLockedKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                });
            });
        }

    } else if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) {
        if (!moduleView || !sourceID.length) return;
        NSUInteger dragPage = MIN(gCCACurrentPage, gCCAPageCount ? gCCAPageCount - 1 : 0);
        CCAEditGridView *grid = [self editGridForPage:dragPage overlay:overlay];
        if (!grid) grid = objc_getAssociatedObject(overlay, kCCAEditGridKey);
        UIView *previewTarget = objc_getAssociatedObject(gesture, kCCADragPreviewTargetKey);
        BOOL moved = [objc_getAssociatedObject(gesture, kCCADragMovedKey) boolValue];
        // Heuristic removal: a press that never became a drag and lifted near the
        // module's top-left corner (the remove bubble) is read as a remove. The
        // module is otherwise restored in place by the normal (no-target) path
        // below; the actual removal is fired from the settle block so it reuses
        // all of that teardown instead of duplicating it.
        __block BOOL heuristicRemove = NO;
        UIButton *heuristicRemoveButton = nil;
        if (!moved && gesture.state == UIGestureRecognizerStateEnded && gRemovalButtonsEnabled) {
            UIButton *removeButton = objc_getAssociatedObject(moduleView, kCCARemoveButtonKey);
            if (removeButton) {
                CGPoint startPoint = [objc_getAssociatedObject(gesture, kCCADragStartPointKey) CGPointValue];
                CGRect sourceFrame = CGRectNull;
                for (UIViewController *candidate in CCACollectModuleControllers(overlay)) {
                    if ([CCAModuleIdentifier(candidate) isEqualToString:sourceID]) { sourceFrame = CCAVisibleModuleFrame(candidate, overlay); break; }
                }
                if (!CGRectIsNull(sourceFrame) && !CGRectIsEmpty(sourceFrame)) {
                    CGFloat cornerDistance = hypot(startPoint.x - CGRectGetMinX(sourceFrame), startPoint.y - CGRectGetMinY(sourceFrame));
                    if (cornerDistance <= kCCARemoveTapCornerRadius) { heuristicRemove = YES; heuristicRemoveButton = removeButton; }
                }
            }
        }
        NSString *targetID = nil;
        if (moved) {
            // A normal quick release can arrive before the short preview dwell
            // promotes the newest candidate. The pending ID is already derived
            // from the current visible overlap, so it is the authoritative
            // release target; the committed preview is only the fallback.
            targetID = objc_getAssociatedObject(gesture, kCCADragPendingTargetIDKey);
            if (!targetID.length) targetID = objc_getAssociatedObject(gesture, kCCADragPreviewTargetIDKey);
        }
        NSMutableArray *order = [objc_getAssociatedObject(gesture, kCCADragBaseOrderKey) mutableCopy];
        if (!order.count) order = [[self enabledModuleIdentifiers] mutableCopy];
        NSUInteger sourceIndex = [order indexOfObject:sourceID];
        NSUInteger targetIndex = [order indexOfObject:targetID];
        BOOL didSwap = sourceIndex != NSNotFound && targetIndex != NSNotFound && sourceIndex != targetIndex;
        NSArray<NSNumber *> *landingOrigin = moved ? objc_getAssociatedObject(gesture, kCCADragLandingOriginKey) : nil;
        BOOL didBlankMove = NO;
        if (landingOrigin.count >= 2) {
            didBlankMove = [self applyExplicitGridMoveFrom:sourceID
                                                  toOrigin:(CCUILayoutPoint){landingOrigin[0].unsignedIntegerValue, landingOrigin[1].unsignedIntegerValue}
                                                    onPage:dragPage
                                                   overlay:overlay];
            if (!didBlankMove) {
                didBlankMove = [self applyExplicitGridInsertionFrom:sourceID
                                                           toOrigin:(CCUILayoutPoint){landingOrigin[0].unsignedIntegerValue, landingOrigin[1].unsignedIntegerValue}
                                                             onPage:dragPage
                                                            maxRows:grid.rows
                                                            overlay:overlay];
            }
        }
        if (!didBlankMove && didSwap && [self layoutHasIllegalOverlapInOverlay:overlay]) {
            didSwap = NO;
            targetID = nil;
        }
        if (!didSwap) [self applyLivePreviewOrder:order overlay:overlay];
        if (!didBlankMove && didSwap) {
            BOOL appliedExplicitSwap = [self applyExplicitGridSwapFrom:sourceID to:targetID overlay:overlay];
            if (appliedExplicitSwap) {
                [self persistStoredOrderBySwappingSource:sourceID target:targetID];
            } else {
                // A rejected explicit footprint must return to its source. The
                // old ordered-provider fallback can repack differently sized
                // modules into an overlapping layout during a fast release.
                didSwap = NO;
                targetID = nil;
            }
        }
        if (didBlankMove) didSwap = YES;
        UIButton *remove = objc_getAssociatedObject(moduleView, kCCARemoveButtonKey);
        UIButton *resize = objc_getAssociatedObject(moduleView, kCCAResizeButtonKey);
        void (^restoreHiddenChrome)(void) = ^{
            NSArray<NSDictionary *> *hiddenChrome = objc_getAssociatedObject(gesture, kCCADragHiddenChromeKey);
            for (NSDictionary *record in hiddenChrome) {
                UIView *view = record[@"view"];
                if (![view isKindOfClass:[UIView class]]) continue;
                view.hidden = [record[@"hidden"] boolValue];
                view.alpha = [record[@"alpha"] doubleValue];
            }
        };
        void (^finishSource)(void) = ^{
            UIViewController *sourceController = nil;
            for (UIViewController *candidate in CCACollectModuleControllers(overlay)) {
                if (candidate.view == moduleView) { sourceController = candidate; break; }
            }
            CGRect moduleFrame = sourceController ? [sourceController.view convertRect:sourceController.view.bounds toView:overlay.view] : [moduleView convertRect:moduleView.bounds toView:overlay.view];
            [self positionEditControlsForModuleView:moduleView overlay:overlay overlayFrame:moduleFrame];
            restoreHiddenChrome();
            [UIView animateWithDuration:0.12 animations:^{ remove.alpha = 1.0; resize.alpha = 1.0; }];
        };
        if (didSwap) {
            // The settings provider immediately replaces/repositions the module
            // containers. Returning the outgoing view to its old frame with an
            // animation creates a visible fly-in from the drag destination.
            [UIView performWithoutAnimation:^{
                moduleView.transform = CGAffineTransformIdentity;
                moduleView.alpha = 0.0;
                UIVisualEffectView *dragBorder = objc_getAssociatedObject(moduleView, @selector(applyEditingToModule:editing:));
                dragBorder.transform = CGAffineTransformIdentity;
                dragBorder.alpha = 0.0;
                dragBorder.hidden = YES;
                previewTarget.transform = CGAffineTransformIdentity;
            }];
        } else {
            [UIView animateWithDuration:0.24 animations:^{
                moduleView.transform = CGAffineTransformIdentity;
                moduleView.alpha = 1.0;
                UIVisualEffectView *dragBorder = objc_getAssociatedObject(moduleView, @selector(applyEditingToModule:editing:));
                dragBorder.transform = CGAffineTransformIdentity;
                dragBorder.hidden = NO;
                previewTarget.transform = CGAffineTransformIdentity;
            } completion:^(__unused BOOL finished) { finishSource(); }];
        }
        UIView *dragProxy = objc_getAssociatedObject(gesture, kCCADragProxyKey);
        if (didSwap && dragProxy) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.08 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                UIViewController *settledSource = nil;
                for (UIViewController *candidate in CCACollectModuleControllers(overlay)) {
                    if ([CCAModuleIdentifier(candidate) isEqualToString:sourceID]) { settledSource = candidate; break; }
                }
                CGRect destination = settledSource ? CCAVisibleModuleFrame(settledSource, overlay) : dragProxy.frame;
                settledSource.view.alpha = 0.0;
                UIVisualEffectView *settledBorder = objc_getAssociatedObject(settledSource.view, @selector(applyEditingToModule:editing:));
                settledBorder.alpha = 0.0;
                settledBorder.hidden = YES;
                CGRect visibleProxyFrame = dragProxy.layer.presentationLayer ? ((CALayer *)dragProxy.layer.presentationLayer).frame : dragProxy.frame;
                [UIView performWithoutAnimation:^{ dragProxy.transform = CGAffineTransformIdentity; dragProxy.frame = visibleProxyFrame; }];
                [UIView animateWithDuration:0.20 delay:0.0 options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionBeginFromCurrentState animations:^{
                    dragProxy.frame = destination;
                    dragProxy.alpha = 0.88;
                } completion:^(__unused BOOL finished) {
                    settledSource.view.alpha = 1.0;
                    settledBorder.alpha = 1.0;
                    settledBorder.hidden = NO;
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.10 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        [UIView animateWithDuration:0.18 delay:0.0 options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionBeginFromCurrentState animations:^{
                            dragProxy.alpha = 0.0;
                        } completion:^(__unused BOOL finished) {
                            [dragProxy removeFromSuperview];
                        }];
                    });
                }];
            });
        } else if (dragProxy) {
            [UIView animateWithDuration:0.20 animations:^{ dragProxy.transform = CGAffineTransformIdentity; } completion:^(__unused BOOL finished) {
                moduleView.alpha = 1.0;
                UIVisualEffectView *dragBorder = objc_getAssociatedObject(moduleView, @selector(applyEditingToModule:editing:));
                dragBorder.alpha = 1.0;
                dragBorder.hidden = NO;
                restoreHiddenChrome();
                [dragProxy removeFromSuperview];
            }];
        }
        // The provider relays out both sides of a swap asynchronously. Removal
        // controls are now wrapper-hosted, so resynchronize every control as
        // those new module frames settle instead of updating only the source.
        for (NSNumber *delay in @[@0.02, @0.14, @0.30]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                NSMutableSet<UIButton *> *validButtons = [NSMutableSet set];
                for (UIViewController *candidate in CCACollectModuleControllers(overlay)) {
                    // Swaps may create replacement containers after their first
                    // layout pass. Reapply both the refined clipping radius and
                    // edit chrome to those new views before they become visible.
                    [self applyEditingToModule:candidate editing:YES];
                    UIButton *candidateRemove = objc_getAssociatedObject(candidate.view, kCCARemoveButtonKey);
                    if (candidateRemove) [validButtons addObject:candidateRemove];
                }
                for (UIView *subview in [overlay.view.subviews copy]) {
                    if (subview.tag == kCCARemoveButtonTag && ![validButtons containsObject:(UIButton *)subview]) [subview removeFromSuperview];
                }
                [UIView animateWithDuration:0.18 delay:0.0 options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionBeginFromCurrentState animations:^{
                    for (UIViewController *candidate in CCACollectModuleControllers(overlay)) {
                        UIButton *candidateRemove = objc_getAssociatedObject(candidate.view, kCCARemoveButtonKey);
                        if (!candidateRemove || candidateRemove.hidden) continue;
                        CGRect candidateFrame = [candidate.view convertRect:candidate.view.bounds toView:overlay.view];
                        [self positionEditControlsForModuleView:candidate.view overlay:overlay overlayFrame:candidateFrame];
                    }
                } completion:nil];
                UIViewController *collection = [self moduleCollectionControllerInOverlay:overlay];
                if (collection && gEditModeActive) {
                    [self prepareGridForOverlay:overlay collection:collection];
                    NSMutableDictionary<NSNumber *, CCAEditGridView *> *pageGrids = objc_getAssociatedObject(overlay, kCCAEditPageGridsKey);
                    for (CCAEditGridView *pageGrid in pageGrids.allValues) pageGrid.alpha = gCCAPagerScrubbingActive ? gCCAPagerHeldAlphaFactor : 1.0;
                    CCAEditTouchShield *shield = (CCAEditTouchShield *)[overlay.view viewWithTag:kCCAEditTouchShieldTag];
                    if (shield) [overlay.view bringSubviewToFront:shield];
                    UIButton *settledAddControl = (UIButton *)[overlay.view viewWithTag:kCCAAddControlButtonTag];
                    if (settledAddControl) [overlay.view bringSubviewToFront:settledAddControl];
                    for (UIViewController *candidate in CCACollectModuleControllers(overlay)) {
                        UIButton *candidateRemove = objc_getAssociatedObject(candidate.view, kCCARemoveButtonKey);
                        UIButton *candidateResize = objc_getAssociatedObject(candidate.view, kCCAResizeButtonKey);
                        if (candidateRemove) [candidateRemove.superview bringSubviewToFront:candidateRemove];
                        if (candidateResize) [candidateResize.superview bringSubviewToFront:candidateResize];
                    }
                }
            });
        }
        [self clearEditGridLandingRectsForOverlay:overlay];
        CGRect originalFrame = [objc_getAssociatedObject(gesture, kCCADragStartFrameKey) CGRectValue];
        if (!didSwap && !didBlankMove && !CGRectIsEmpty(originalFrame)) grid.occupiedRects = [grid.occupiedRects arrayByAddingObject:[NSValue valueWithCGRect:originalFrame]];
        [grid setNeedsDisplay];
        objc_setAssociatedObject(gesture, @selector(moduleControllerForShield:), nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(gesture, @selector(modulePanned:), @"overlayPan", OBJC_ASSOCIATION_COPY_NONATOMIC);
        objc_setAssociatedObject(gesture, kCCADragStartFrameKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(gesture, kCCADragStartPointKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(gesture, kCCADragPreviewTargetKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(gesture, kCCADragProxyKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(gesture, kCCADragBaseOrderKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(gesture, kCCADragPreviewTargetIDKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(gesture, kCCADragProxyStartFrameKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(gesture, kCCADragBaseFramesKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(gesture, kCCADragPendingTargetIDKey, nil, OBJC_ASSOCIATION_COPY_NONATOMIC);
        objc_setAssociatedObject(gesture, kCCADragPreviewLockedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(gesture, kCCADragGrabOffsetKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(gesture, kCCADragLandingOriginKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(gesture, kCCADragStartPageKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(gesture, kCCADragEdgeDwellKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(gesture, kCCADragEdgeDwellDirectionKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(gesture, kCCADragMovedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(gesture, kCCADragHiddenChromeKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        UIViewController *settleOverlay = overlay;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            gCCADragInProgress = NO;
            gCCAActiveDragModuleView = nil;
            gCCAActiveDragModuleIdentifier = nil;
            // A heuristic remove (tap near the top-left corner) reuses the normal
            // restore-in-place teardown above, then removes the module here so no
            // drag bookkeeping is duplicated.
            if (heuristicRemove && heuristicRemoveButton) [self removeTapped:heuristicRemoveButton];
            // Re-sanitise the whole layout once the drop has settled. Each commit
            // path (swap / move / insertion) only validates the page it touched;
            // this guarantees the persisted layout is globally consistent — every
            // control placed, nothing overlapping, no stale entries — before the
            // next Control Center presentation can read it.
            [self normalizePagedLayoutForOverlay:settleOverlay];
            [self updatePagedModuleVisibilityForOverlay:settleOverlay showAdjacent:NO];
            [self updateEditControlFramesForOverlay:settleOverlay];
        });
    }
}

- (void)applyEditingToModule:(UIViewController *)module editing:(BOOL)editing {
    UIView *view = module.view;
    if (!view) return;
    [self applyRefinedLookToModule:module];
    if (editing && gEnabled) {
        view.layer.cornerRadius = [self editingModuleCornerRadiusForSize:view.bounds.size];
    }
    UIVisualEffectView *border = objc_getAssociatedObject(view, @selector(applyEditingToModule:editing:));
    BOOL ownsLiveResize = gCCAResizeInProgress && view == gCCAActiveResizeModuleView;
    UIView *shield = [view viewWithTag:kCCAEditShieldTag];
    UIButton *remove = objc_getAssociatedObject(view, kCCARemoveButtonKey);
    UIButton *resize = objc_getAssociatedObject(view, kCCAResizeButtonKey);
    if (editing && gModuleBordersEnabled) {
        if (!border) {
            border = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialLight]];
            border.userInteractionEnabled = NO;
            objc_setAssociatedObject(view, @selector(applyEditingToModule:editing:), border, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        UIView *wrapper = view.superview;
        if (wrapper && border.superview != wrapper) {
            [border removeFromSuperview];
            [wrapper insertSubview:border belowSubview:view];
        }
        if (!ownsLiveResize) {
            CGRect stableModuleFrame = CGRectMake(CGRectGetMinX(view.frame), CGRectGetMinY(view.frame), CGRectGetWidth(view.bounds), CGRectGetHeight(view.bounds));
            [self configureEditingBorder:border moduleFrame:stableModuleFrame];
        }
        border.hidden = NO;
        border.alpha = 1.0;
        if (gBorderBreathingEnabled && ![border.layer animationForKey:@"CCAsterBreathing"]) {
            CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"opacity"];
            animation.fromValue = @0.24; animation.toValue = @1.0; animation.duration = 0.7;
            animation.autoreverses = YES; animation.repeatCount = HUGE_VALF;
            [border.layer addAnimation:animation forKey:@"CCAsterBreathing"];
        }
    } else if (border) { border.hidden = YES; [border.layer removeAllAnimations]; }

    if (editing && !shield) {
        shield = [[UIView alloc] initWithFrame:view.bounds];
        shield.tag = kCCAEditShieldTag;
        shield.backgroundColor = UIColor.clearColor;
        shield.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [view addSubview:shield];
    }
    shield.hidden = !editing;
    if (gEnabled) view.layer.masksToBounds = YES;

    NSString *moduleIdentifier = CCAModuleIdentifier(module);
    UIViewController *overlay = gOverlayControllers.allObjects.firstObject;
    UIView *chromeHost = [self editChromeHostForModuleView:view overlay:overlay];
    UIView *resizeHost = chromeHost ?: overlay.view;
    BOOL supportsResize = [self moduleIdentifierSupportsResizing:moduleIdentifier];
    if (CCAIsActiveDragModuleIdentifier(moduleIdentifier)) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        view.layer.opacity = 0.0f;
        [CATransaction commit];
        border.hidden = YES;
        border.alpha = 0.0;
        remove.hidden = YES;
        remove.alpha = 0.0;
        resize.hidden = YES;
        resize.alpha = 0.0;
        return;
    }
    if (editing && supportsResize) {
        if (!resize) {
            resize = [CCAExpandedHitButton buttonWithType:UIButtonTypeCustom];
            resize.tag = kCCAResizeButtonTag;
            resize.accessibilityIdentifier = @"CCAsterResizeHandle";
            resize.backgroundColor = UIColor.clearColor;
            resize.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleLeftMargin;
            resize.clipsToBounds = NO;
            UIBlurEffect *grabberBlur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialLight];
            UIVisualEffectView *grabberMaterial = [[UIVisualEffectView alloc] initWithEffect:grabberBlur];
            grabberMaterial.tag = kCCAResizeMaterialTag;
            grabberMaterial.frame = resize.bounds;
            grabberMaterial.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            grabberMaterial.userInteractionEnabled = NO;
            [resize addSubview:grabberMaterial];
            CAShapeLayer *pill = [CAShapeLayer layer];
            pill.name = @"CCAsterResizePill";
            pill.fillColor = UIColor.clearColor.CGColor;
            pill.strokeColor = [UIColor.whiteColor colorWithAlphaComponent:0.82].CGColor;
            pill.lineWidth = 12.5;
            pill.lineCap = kCALineCapRound;
            pill.lineJoin = kCALineJoinRound;
            [resize.layer addSublayer:pill];
            UIPanGestureRecognizer *resizePan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(resizePanned:)];
            resizePan.maximumNumberOfTouches = 1;
            resizePan.cancelsTouchesInView = YES;
            resizePan.delegate = self;
            [resize addGestureRecognizer:resizePan];
            objc_setAssociatedObject(resize, @selector(resizePanned:), moduleIdentifier, OBJC_ASSOCIATION_COPY_NONATOMIC);
            objc_setAssociatedObject(resize, kCCARemoveModuleViewKey, view, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(view, kCCAResizeButtonKey, resize, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [resizeHost addSubview:resize];
        }
        objc_setAssociatedObject(resize, @selector(resizePanned:), moduleIdentifier, OBJC_ASSOCIATION_COPY_NONATOMIC);
        resize.accessibilityLabel = [NSString stringWithFormat:@"Resize %@", moduleIdentifier.lastPathComponent ?: @"module"];
        resize.accessibilityHint = @"Drag to change the module size";
        if (resizeHost && resize.superview != resizeHost) {
            [resize removeFromSuperview];
            [resizeHost addSubview:resize];
        }
        CGRect moduleFrame = [view convertRect:view.bounds toView:overlay.view];
        [self positionEditControlsForModuleView:view overlay:overlay overlayFrame:moduleFrame];
        // A broad circular arc follows the module's continuous bottom-right
        // corner instead of forming a tight, unrelated elbow. Its centerline
        // sits on the edit border so the ring visually bisects the grabber.
        UIBezierPath *cornerPath = [UIBezierPath bezierPath];
        [cornerPath moveToPoint:CGPointMake(20.29, 40.01)];
        [cornerPath addCurveToPoint:CGPointMake(40.01, 20.29)
                      controlPoint1:CGPointMake(31.20, 40.01)
                      controlPoint2:CGPointMake(40.01, 31.20)];
        UIVisualEffectView *grabberMaterial = [resize viewWithTag:kCCAResizeMaterialTag];
        CAShapeLayer *materialMask = [CAShapeLayer layer];
        materialMask.path = cornerPath.CGPath;
        materialMask.fillColor = UIColor.clearColor.CGColor;
        materialMask.strokeColor = UIColor.blackColor.CGColor;
        // Keep the live material wholly beneath the translucent 12.5pt pill.
        // A wider mask leaked past the stroke over dark modules and read as a
        // one-sided outline even though the foreground shape had no border.
        materialMask.lineWidth = 12.0;
        materialMask.lineCap = kCALineCapRound;
        materialMask.lineJoin = kCALineJoinRound;
        grabberMaterial.layer.mask = materialMask;
        for (CALayer *layer in [resize.layer.sublayers copy]) {
            if ([layer.name isEqualToString:@"CCAsterResizeBacking"]) [layer removeFromSuperlayer];
            else if ([layer.name isEqualToString:@"CCAsterResizePill"] && [layer isKindOfClass:[CAShapeLayer class]]) ((CAShapeLayer *)layer).path = cornerPath.CGPath;
        }
        objc_setAssociatedObject(resize, kCCASmallModuleChromeKey,
            @(MIN(CGRectGetWidth(view.bounds), CGRectGetHeight(view.bounds)) < 100.0), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        resize.hidden = NO;
        resize.alpha = 1.0;
        [resize.superview bringSubviewToFront:resize];
    } else if (resize) {
        resize.hidden = YES;
    }

    if (editing && gRemovalButtonsEnabled) {
        NSString *identifier = moduleIdentifier;
        if (!remove && identifier.length) {
            remove = [CCAExpandedHitButton buttonWithType:UIButtonTypeCustom];
            remove.tag = kCCARemoveButtonTag;
            remove.backgroundColor = UIColor.clearColor;
            remove.tintColor = UIColor.blackColor;
            UIView *bubble = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterialLight]];
            bubble.frame = CGRectMake(9.0, 9.0, 26.0, 26.0);
            bubble.layer.cornerRadius = 13.0; bubble.clipsToBounds = YES; bubble.userInteractionEnabled = NO;
            [remove insertSubview:bubble atIndex:0];
            UIImageView *minusGlyph = [[UIImageView alloc] initWithImage:[[self symbol:@"minus" size:13.0] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
            minusGlyph.tintColor = UIColor.blackColor;
            minusGlyph.contentMode = UIViewContentModeCenter;
            minusGlyph.frame = CGRectMake(9.0, 9.0, 26.0, 26.0);
            minusGlyph.userInteractionEnabled = NO;
            [remove addSubview:minusGlyph];
            [remove addTarget:self action:@selector(removeTapped:) forControlEvents:UIControlEventTouchUpInside];
            objc_setAssociatedObject(remove, @selector(removeTapped:), identifier, OBJC_ASSOCIATION_COPY_NONATOMIC);
            objc_setAssociatedObject(remove, kCCARemoveModuleViewKey, view, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(view, kCCARemoveButtonKey, remove, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [chromeHost addSubview:remove];
        }
        if (chromeHost && remove.superview != chromeHost) {
            [remove removeFromSuperview];
            [chromeHost addSubview:remove];
        }
        if (identifier.length) objc_setAssociatedObject(remove, @selector(removeTapped:), identifier, OBJC_ASSOCIATION_COPY_NONATOMIC);
        objc_setAssociatedObject(remove, kCCARemoveModuleViewKey, view, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        // The remove bubble is now a visual affordance only; it must not swallow
        // touches or the module underneath it can't be picked up. Removal is
        // triggered heuristically from the drag recogniser on drop (a tap that
        // never moved, released near this top-left corner).
        remove.userInteractionEnabled = NO;
        CGRect moduleFrame = [view convertRect:view.bounds toView:overlay.view];
        [self positionEditControlsForModuleView:view overlay:overlay overlayFrame:moduleFrame];
        objc_setAssociatedObject(remove, kCCASmallModuleChromeKey,
            @(MIN(CGRectGetWidth(view.bounds), CGRectGetHeight(view.bounds)) < 100.0), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [remove.superview bringSubviewToFront:remove];
        remove.hidden = NO;
        remove.alpha = 1.0;
    } else { remove.hidden = YES; }
}

- (void)collectEnabledNativeEditingGesturesFromView:(UIView *)view into:(NSMutableArray<UIGestureRecognizer *> *)gestures {
    for (UIGestureRecognizer *gesture in view.gestureRecognizers) {
        NSString *gestureName = NSStringFromClass(gesture.class);
        BOOL blocksEditing = [gesture isKindOfClass:[UITapGestureRecognizer class]] ||
            [gesture isKindOfClass:[UILongPressGestureRecognizer class]] ||
            [gestureName localizedCaseInsensitiveContainsString:@"force"] ||
            [gestureName localizedCaseInsensitiveContainsString:@"click"] ||
            [gestureName localizedCaseInsensitiveContainsString:@"context"];
        if (blocksEditing && gesture.enabled && !objc_getAssociatedObject(gesture, kCCAOwnGestureKey)) {
            [gestures addObject:gesture];
        }
    }
    for (UIView *subview in view.subviews) [self collectEnabledNativeEditingGesturesFromView:subview into:gestures];
}

- (void)restoreCCAsterDisabledGesturesFromView:(UIView *)view {
    for (UIGestureRecognizer *gesture in view.gestureRecognizers) {
        if ([objc_getAssociatedObject(gesture, kCCADisabledGesturesKey) boolValue]) {
            gesture.enabled = YES;
            objc_setAssociatedObject(gesture, kCCADisabledGesturesKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
    for (UIView *subview in view.subviews) [self restoreCCAsterDisabledGesturesFromView:subview];
}

- (void)setNativeDismissTapGesturesEnabled:(BOOL)enabled forOverlay:(UIViewController *)overlay {
    if (!enabled) {
        NSMutableArray<UIGestureRecognizer *> *disabled = [NSMutableArray array];
        [self collectEnabledNativeEditingGesturesFromView:overlay.view into:disabled];
        for (UIGestureRecognizer *gesture in disabled) {
            objc_setAssociatedObject(gesture, kCCADisabledGesturesKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            gesture.enabled = NO;
        }
        objc_setAssociatedObject(overlay, kCCADisabledGesturesKey, disabled, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else {
        NSArray<UIGestureRecognizer *> *disabled = objc_getAssociatedObject(overlay, kCCADisabledGesturesKey);
        for (UIGestureRecognizer *gesture in disabled) gesture.enabled = YES;
        [self restoreCCAsterDisabledGesturesFromView:overlay.view];
        objc_setAssociatedObject(overlay, kCCADisabledGesturesKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

- (NSArray<UIView *> *)chromeViewsInOverlay:(UIViewController *)overlay excludingCollection:(UIViewController *)collection {
    NSMutableArray<UIView *> *views = [NSMutableArray array];
    UIView *host = [overlay.view viewWithTag:181000];
    // A host nested under native header chrome inherits that chrome's transform
    // and alpha. Only animate it directly on the compatibility fallback path.
    if (host && host.superview == overlay.view) [views addObject:host];
    UIView *topFade = [overlay.view viewWithTag:kCCATopFadeTag];
    if (topFade) [views addObject:topFade];
    for (UIViewController *child in overlay.childViewControllers) {
        if (child == collection) continue;
        NSString *name = NSStringFromClass(child.class);
        if ([name containsString:@"SensorAttribution"] || [name containsString:@"HeaderPocket"]) {
            if (child.view) [views addObject:child.view];
        }
    }
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithArray:overlay.view.subviews];
    while (queue.count) {
        UIView *view = queue.firstObject;
        [queue removeObjectAtIndex:0];
        NSString *name = NSStringFromClass(view.class);
        BOOL headerPocket = [name containsString:@"HeaderPocket"];
        if (headerPocket && view != collection.view && view != host) [views addObject:view];
        [queue addObjectsFromArray:view.subviews];
    }
    return [[NSOrderedSet orderedSetWithArray:views] array];
}

- (void)setHeaderChromeHiddenForScrubbing:(BOOL)hidden overlay:(UIViewController *)overlay animated:(BOOL)animated {
    if (!overlay) return;
    UIViewController *collection = [self moduleCollectionControllerInOverlay:overlay];
    NSMutableArray<UIView *> *headerViews = [[self chromeViewsInOverlay:overlay excludingCollection:collection] mutableCopy];
    [headerViews filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(UIView *view, __unused NSDictionary *bindings) {
        return view.tag != kCCATopFadeTag;
    }]];
    for (UIView *view in headerViews) [self capturePresentationStateForView:view];
    void (^changes)(void) = ^{
        for (UIView *view in headerViews) {
            CGFloat restingAlpha = [objc_getAssociatedObject(view, kCCAOriginalAlphaKey) doubleValue];
            view.alpha = hidden || gEditModeActive ? 0.0 : restingAlpha;
        }
    };
    if (animated) {
        [UIView animateWithDuration:hidden ? 0.16 : 0.26
                              delay:0.0
                            options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                         animations:changes
                         completion:nil];
    } else {
        changes();
    }
}

- (void)capturePresentationStateForView:(UIView *)view {
    if (!objc_getAssociatedObject(view, kCCAOriginalTransformKey)) {
        objc_setAssociatedObject(view, kCCAOriginalTransformKey, [NSValue valueWithCGAffineTransform:view.transform], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(view, kCCAOriginalAlphaKey, @(view.alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (!objc_getAssociatedObject(view, kCCAOriginalSublayerTransformKey)) {
        objc_setAssociatedObject(view, kCCAOriginalSublayerTransformKey, [NSValue valueWithCATransform3D:view.layer.sublayerTransform], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

- (CCAEditGridView *)editGridForPage:(NSUInteger)page overlay:(UIViewController *)overlay {
    NSMutableDictionary<NSNumber *, CCAEditGridView *> *pageGrids = objc_getAssociatedObject(overlay, kCCAEditPageGridsKey);
    CCAEditGridView *grid = pageGrids[@(page)];
    if (!grid && page == gCCACurrentPage) grid = objc_getAssociatedObject(overlay, kCCAEditGridKey);
    return grid;
}

- (void)clearEditGridLandingRectsForOverlay:(UIViewController *)overlay {
    NSMutableDictionary<NSNumber *, CCAEditGridView *> *pageGrids = objc_getAssociatedObject(overlay, kCCAEditPageGridsKey);
    for (CCAEditGridView *grid in pageGrids.allValues) grid.landingRects = @[];
    CCAEditGridView *currentGrid = objc_getAssociatedObject(overlay, kCCAEditGridKey);
    if (currentGrid && ![pageGrids.allValues containsObject:currentGrid]) currentGrid.landingRects = @[];
}

- (void)setEditGridLandingRects:(NSArray<NSValue *> *)rects forPage:(NSUInteger)page overlay:(UIViewController *)overlay {
    [self clearEditGridLandingRectsForOverlay:overlay];
    CCAEditGridView *grid = [self editGridForPage:page overlay:overlay];
    if (grid) grid.landingRects = rects ?: @[];
}

- (void)updateEditPageGridTransformsForOverlay:(UIViewController *)overlay {
    NSMutableDictionary<NSNumber *, CCAEditGridView *> *pageGrids = objc_getAssociatedObject(overlay, kCCAEditPageGridsKey);
    UIView *gridStack = objc_getAssociatedObject(overlay, kCCAEditGridStackKey);
    if (!pageGrids.count || !gridStack) return;
    CGFloat span = CCAVisualPageSpan();
    CGFloat scrollY = (CGFloat)gCCACurrentPage * span - gCCAPagerInteractiveTranslation;
    CGRect bounds = gridStack.bounds;
    bounds.origin = CGPointMake(0.0, scrollY);
    gridStack.bounds = bounds;
    gridStack.layer.transform = CATransform3DIdentity;
    gridStack.layer.sublayerTransform = CATransform3DIdentity;
    if (gCCAPagerScrubbingActive) {
        UIViewController *collection = [self moduleCollectionControllerInOverlay:overlay];
        CGPoint overlayCenter = CGPointMake(CGRectGetMidX(overlay.view.bounds), CGRectGetMidY(overlay.view.bounds));
        CGPoint scaleCenter = overlayCenter;
        if (collection.view && collection.view.superview) {
            scaleCenter = [collection.view.superview convertPoint:collection.view.center toView:overlay.view];
        }
        CGFloat scaleX = gCCAPagerHeldScale * gCCAPagerJelloScaleX;
        CGFloat scaleY = gCCAPagerHeldScale * gCCAPagerJelloScaleY;
        CGFloat compensationX = (overlayCenter.x - scaleCenter.x) * (1.0 - scaleX);
        CGFloat compensationY = (overlayCenter.y - scaleCenter.y) * (1.0 - scaleY);
        gridStack.transform = CGAffineTransformScale(CGAffineTransformMakeTranslation(compensationX, compensationY),
                                                     scaleX,
                                                     scaleY);
    } else {
        gridStack.transform = CGAffineTransformIdentity;
    }
    gridStack.alpha = gEditModeActive ? (gCCAPagerScrubbingActive ? gCCAPagerHeldAlphaFactor : 1.0) : 0.0;
    gridStack.hidden = !gEditModeActive || gCCAExpandedModuleOpen;
    for (NSNumber *pageKey in pageGrids) {
        CCAEditGridView *grid = pageGrids[pageKey];
        grid.transform = CGAffineTransformIdentity;
        grid.alpha = 1.0;
        grid.hidden = !gEditModeActive || gCCAExpandedModuleOpen;
    }
}

- (CCAEditGridView *)prepareGridForOverlay:(UIViewController *)overlay collection:(UIViewController *)collection {
    CGFloat span = CCAVisualPageSpan();
    NSMutableDictionary<NSNumber *, CCAEditGridView *> *pageGrids = objc_getAssociatedObject(overlay, kCCAEditPageGridsKey);
    if (!pageGrids) {
        pageGrids = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(overlay, kCCAEditPageGridsKey, pageGrids, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UIView *gridStack = objc_getAssociatedObject(overlay, kCCAEditGridStackKey);
    if (!gridStack) {
        gridStack = [[UIView alloc] initWithFrame:overlay.view.bounds];
        gridStack.tag = kCCAEditGridTag;
        gridStack.backgroundColor = UIColor.clearColor;
        gridStack.opaque = NO;
        gridStack.clipsToBounds = YES;
        gridStack.userInteractionEnabled = NO;
        gridStack.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        objc_setAssociatedObject(overlay, kCCAEditGridStackKey, gridStack, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (gridStack.superview != overlay.view) {
        [gridStack removeFromSuperview];
        [overlay.view insertSubview:gridStack aboveSubview:collection.view ?: overlay.view.subviews.firstObject];
    }
    gridStack.frame = overlay.view.bounds;
    gridStack.layer.transform = CATransform3DIdentity;
    gridStack.layer.sublayerTransform = CATransform3DIdentity;
    NSArray<UIViewController *> *modules = CCACollectModuleControllers(overlay);
    NSMutableDictionary<NSNumber *, NSMutableIndexSet *> *occupiedIndexesByPage = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSNumber *, NSValue *> *baseByPage = [NSMutableDictionary dictionary];
    CGPoint fallbackBase = CGPointMake(CGFLOAT_MAX, CGFLOAT_MAX);
    for (UIViewController *module in modules) {
        NSString *identifier = CCAModuleIdentifier(module);
        NSValue *nativeValue = identifier.length ? gCCANativeLayoutRects[identifier] : nil;
        if (!nativeValue) continue;
        CCUILayoutRect logical = {};
        [nativeValue getValue:&logical];
        NSArray<NSNumber *> *origin = gCCACustomOrigins[identifier];
        if (origin.count >= 2) logical.origin = (CCUILayoutPoint){origin[0].unsignedIntegerValue, origin[1].unsignedIntegerValue};
        NSArray<NSNumber *> *size = gCCACustomSizes[identifier];
        if (size.count >= 2) logical.size = (CCUILayoutSize){size[0].unsignedIntegerValue, size[1].unsignedIntegerValue};
        CGRect frame = [module.view convertRect:module.view.bounds toView:overlay.view];
        if (CGRectIsEmpty(frame)) continue;
        NSUInteger page = CCAPageForRect(logical);
        NSUInteger localRow = logical.origin.y % kCCAMinimumGridRows;
        CGFloat baseX = CGRectGetMinX(frame) - logical.origin.x * kCCAGridStep;
        CGFloat baseY = CGRectGetMinY(frame) - localRow * kCCAGridStep - ((CGFloat)((NSInteger)page - (NSInteger)gCCACurrentPage) * span) - gCCAPagerInteractiveTranslation;
        fallbackBase.x = MIN(fallbackBase.x, baseX);
        fallbackBase.y = MIN(fallbackBase.y, baseY);
        NSNumber *pageKey = @(page);
        CGPoint pageBase = baseByPage[pageKey] ? baseByPage[pageKey].CGPointValue : CGPointMake(CGFLOAT_MAX, CGFLOAT_MAX);
        pageBase.x = MIN(pageBase.x, baseX);
        pageBase.y = MIN(pageBase.y, baseY);
        baseByPage[pageKey] = [NSValue valueWithCGPoint:pageBase];
    }

    NSValue *cachedBaseValue = objc_getAssociatedObject(overlay, kCCAEditGridBaseOriginKey);
    CGPoint cachedBase = cachedBaseValue ? cachedBaseValue.CGPointValue : fallbackBase;
    if (cachedBase.x == CGFLOAT_MAX || cachedBase.y == CGFLOAT_MAX) cachedBase = CGPointMake(0.0, 0.0);

    NSValue *currentBaseValue = baseByPage[@(gCCACurrentPage)];
    if (currentBaseValue) {
        cachedBase = currentBaseValue.CGPointValue;
        objc_setAssociatedObject(overlay, kCCAEditGridBaseOriginKey, currentBaseValue, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else if (!cachedBaseValue && fallbackBase.x != CGFLOAT_MAX && fallbackBase.y != CGFLOAT_MAX) {
        cachedBase = fallbackBase;
        objc_setAssociatedObject(overlay, kCCAEditGridBaseOriginKey, [NSValue valueWithCGPoint:fallbackBase], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    CGFloat cell = kCCAGridCellSize;
    CGFloat step = kCCAGridStep;
    occupiedIndexesByPage = [NSMutableDictionary dictionary];
    NSMutableOrderedSet<NSString *> *occupancyIdentifiers = [NSMutableOrderedSet orderedSet];
    for (UIViewController *module in modules) {
        NSString *identifier = CCAModuleIdentifier(module);
        if (identifier.length) [occupancyIdentifiers addObject:identifier];
    }
    for (NSString *identifier in [self enabledModuleIdentifiers]) if (identifier.length) [occupancyIdentifiers addObject:identifier];
    if (!occupancyIdentifiers.count) for (NSString *identifier in gCCANativeLayoutRects.allKeys) if (identifier.length) [occupancyIdentifiers addObject:identifier];
    for (NSString *identifier in occupancyIdentifiers) {
        NSValue *nativeValue = identifier.length ? gCCANativeLayoutRects[identifier] : nil;
        if (!nativeValue) continue;
        CCUILayoutRect logical = {};
        [nativeValue getValue:&logical];
        NSArray<NSNumber *> *origin = gCCACustomOrigins[identifier];
        if (origin.count >= 2) logical.origin = (CCUILayoutPoint){origin[0].unsignedIntegerValue, origin[1].unsignedIntegerValue};
        NSArray<NSNumber *> *size = gCCACustomSizes[identifier];
        if (size.count >= 2) logical.size = (CCUILayoutSize){size[0].unsignedIntegerValue, size[1].unsignedIntegerValue};
        if (!logical.size.width || !logical.size.height) continue;
        NSUInteger page = CCAPageForRect(logical);
        NSUInteger localRow = logical.origin.y % kCCAMinimumGridRows;
        NSNumber *pageKey = @(page);
        NSMutableIndexSet *indexes = occupiedIndexesByPage[pageKey];
        if (!indexes) {
            indexes = [NSMutableIndexSet indexSet];
            occupiedIndexesByPage[pageKey] = indexes;
        }
        for (NSUInteger dy = 0; dy < logical.size.height; dy++) {
            NSUInteger row = localRow + dy;
            if (row >= kCCAMinimumGridRows) continue;
            for (NSUInteger dx = 0; dx < logical.size.width; dx++) {
                NSUInteger column = logical.origin.x + dx;
                if (column >= 4) continue;
                [indexes addIndex:row * 4 + column];
            }
        }
    }

    for (NSNumber *pageKey in [pageGrids.allKeys copy]) {
        if (pageKey.unsignedIntegerValue >= gCCAPageCount) {
            [pageGrids[pageKey] removeFromSuperview];
            [pageGrids removeObjectForKey:pageKey];
        }
    }

    CCAEditGridView *currentGrid = nil;
    for (NSUInteger page = 0; page < gCCAPageCount; page++) {
        NSNumber *pageKey = @(page);
        CCAEditGridView *grid = pageGrids[pageKey];
        if (!grid) {
            grid = [[CCAEditGridView alloc] initWithFrame:overlay.view.bounds];
            grid.tag = kCCAEditGridTag;
            grid.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            pageGrids[pageKey] = grid;
        }
        if (grid.superview != gridStack) {
            [grid removeFromSuperview];
            [gridStack addSubview:grid];
        }
        grid.frame = CGRectMake(0.0,
                                (CGFloat)page * span,
                                CGRectGetWidth(gridStack.bounds),
                                CGRectGetHeight(gridStack.bounds));
        CGPoint base = cachedBase;
        NSMutableArray<NSValue *> *slots = [NSMutableArray array];
        for (NSUInteger row = 0; row < kCCAMinimumGridRows; row++) {
            for (NSUInteger column = 0; column < 4; column++) {
                CGRect slot = CGRectMake(base.x + column * step, base.y + row * step, cell, cell);
                if (CGRectGetMaxX(slot) <= CGRectGetWidth(grid.bounds) + 1.0 && CGRectGetMaxY(slot) <= CGRectGetHeight(grid.bounds) + 1.0) [slots addObject:[NSValue valueWithCGRect:slot]];
            }
        }
        NSMutableArray<NSValue *> *occupied = [NSMutableArray array];
        NSMutableIndexSet *occupiedIndexes = occupiedIndexesByPage[pageKey];
        [occupiedIndexes enumerateIndexesUsingBlock:^(NSUInteger index, __unused BOOL *stop) {
            if (index < slots.count) [occupied addObject:slots[index]];
        }];
        grid.columns = 4;
        grid.rows = kCCAMinimumGridRows;
        grid.slotRects = slots;
        grid.occupiedRects = occupied;
        grid.alpha = 1.0;
        [grid setNeedsDisplay];
        if (page == gCCACurrentPage) currentGrid = grid;
    }
    if (!currentGrid) currentGrid = pageGrids[@0];
    objc_setAssociatedObject(overlay, kCCAEditGridKey, currentGrid, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self updateEditPageGridTransformsForOverlay:overlay];
    return currentGrid;
}

- (void)setEditPresentation:(BOOL)editing forOverlay:(UIViewController *)overlay animated:(BOOL)animated {
    UIViewController *collection = [self moduleCollectionControllerInOverlay:overlay];
    if (!collection.view) return;
    [self capturePresentationStateForView:collection.view];
    CCAEditGridView *grid = [self prepareGridForOverlay:overlay collection:collection];
    [self capturePresentationStateForView:grid];
    CCAEditTouchShield *touchShield = (CCAEditTouchShield *)[overlay.view viewWithTag:kCCAEditTouchShieldTag];
    if (!touchShield) {
        touchShield = [[CCAEditTouchShield alloc] initWithFrame:overlay.view.bounds];
        touchShield.tag = kCCAEditTouchShieldTag;
        touchShield.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        UITapGestureRecognizer *shieldTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(editShieldTapped:)];
        shieldTap.cancelsTouchesInView = YES;
        shieldTap.delegate = self;
        objc_setAssociatedObject(shieldTap, kCCAOwnGestureKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(shieldTap, @selector(editShieldTapped:), @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [touchShield addGestureRecognizer:shieldTap];
        [overlay.view addSubview:touchShield];
    }
    touchShield.frame = overlay.view.bounds;
    touchShield.hidden = !editing;
    if (editing) [overlay.view bringSubviewToFront:touchShield];
    UIButton *addControl = [self addControlButtonForOverlay:overlay];
    touchShield.passthroughView = addControl;
    if (editing) addControl.hidden = NO;
    NSMutableArray<UIView *> *moduleWrappers = [NSMutableArray array];
    for (UIViewController *module in CCACollectModuleControllers(overlay)) {
        if (CCAIsOwnedDuplicateModuleController(module)) continue;
        UIView *wrapper = module.view.superview;
        // Some sparse/late-created pages attach a module directly to the
        // collection view. Treating the collection itself as a per-module
        // wrapper overwrites the page transform with the edit-mode -48pt
        // wrapper offset, which makes every nonzero page disappear.
        if (wrapper == collection.view) continue;
        if (wrapper && ![moduleWrappers containsObject:wrapper]) {
            [moduleWrappers addObject:wrapper];
            [self capturePresentationStateForView:wrapper];
        }
    }
    NSArray<UIView *> *chromeViews = [self chromeViewsInOverlay:overlay excludingCollection:collection];
    for (UIView *view in chromeViews) [self capturePresentationStateForView:view];
    NSMutableDictionary<NSNumber *, CCAEditGridView *> *pageGrids = objc_getAssociatedObject(overlay, kCCAEditPageGridsKey);
    if (editing) for (CCAEditGridView *pageGrid in pageGrids.allValues) pageGrid.alpha = 0.0;
    void (^changes)(void) = ^{
        CGAffineTransform collectionBase = [objc_getAssociatedObject(collection.view, kCCAOriginalTransformKey) CGAffineTransformValue];
        CATransform3D sublayerBase = [objc_getAssociatedObject(collection.view, kCCAOriginalSublayerTransformKey) CATransform3DValue];
        CGFloat pageOffset = -(CGFloat)gCCACurrentPage * CCAVisualPageSpan();
        collection.view.transform = CGAffineTransformTranslate(collectionBase, 0.0, editing ? 0.0 : kCCARestingModuleOffset);
        collection.view.layer.sublayerTransform = CATransform3DTranslate(sublayerBase, 0.0, pageOffset, 0.0);
        for (UIView *wrapper in moduleWrappers) {
            CGAffineTransform base = [objc_getAssociatedObject(wrapper, kCCAOriginalTransformKey) CGAffineTransformValue];
            wrapper.transform = editing ? CGAffineTransformTranslate(base, 0.0, kCCAEditingModuleOffset) : base;
        }
        [self layoutOwnedDuplicateModulesForOverlay:overlay];
        [self updateEditControlFramesForOverlay:overlay];
        addControl.alpha = editing ? 1.0 : 0.0;
        [self updateEditPageGridTransformsForOverlay:overlay];
        for (CCAEditGridView *pageGrid in pageGrids.allValues) if (!editing) pageGrid.alpha = 0.0;
        for (UIView *view in chromeViews) {
            CGAffineTransform base = [objc_getAssociatedObject(view, kCCAOriginalTransformKey) CGAffineTransformValue];
            view.transform = editing ? CGAffineTransformTranslate(base, 0.0, -22.0) : base;
            view.alpha = editing ? 0.0 : [objc_getAssociatedObject(view, kCCAOriginalAlphaKey) doubleValue];
        }
    };
    void (^completion)(BOOL) = ^(__unused BOOL finished) {
        if (editing) {
            [self prepareGridForOverlay:overlay collection:collection];
            NSMutableDictionary<NSNumber *, CCAEditGridView *> *finalPageGrids = objc_getAssociatedObject(overlay, kCCAEditPageGridsKey);
            for (CCAEditGridView *pageGrid in finalPageGrids.allValues) pageGrid.alpha = 0.0;
            [UIView animateWithDuration:0.12 animations:^{ for (CCAEditGridView *pageGrid in finalPageGrids.allValues) pageGrid.alpha = 1.0; }];
            [overlay.view bringSubviewToFront:touchShield];
            [overlay.view bringSubviewToFront:addControl];
            for (UIViewController *module in CCACollectModuleControllers(overlay)) {
                UIButton *remove = objc_getAssociatedObject(module.view, kCCARemoveButtonKey);
                UIButton *resize = objc_getAssociatedObject(module.view, kCCAResizeButtonKey);
                if (remove) [remove.superview bringSubviewToFront:remove];
                if (resize) [resize.superview bringSubviewToFront:resize];
            }
            // The full-screen edit grid and touch shield are inserted after
            // the pager host. Keep the visible indicator gutter above both so
            // dense pages can scrub immediately, not only after one switch.
            UIView *pageIndicators = [overlay.view viewWithTag:kCCAPageIndicatorHostTag];
            if (pageIndicators && !pageIndicators.hidden) [overlay.view bringSubviewToFront:pageIndicators];
            // The wrapper translation is committed at the end of this block.
            // Re-read converted frames afterward so first-open controls do not
            // retain the pre-edit vertical coordinate until the next resize.
            [self updateEditControlFramesForOverlay:overlay];
            dispatch_async(dispatch_get_main_queue(), ^{ [self updateEditControlFramesForOverlay:overlay]; });
        } else {
            addControl.hidden = YES;
            NSMutableDictionary<NSNumber *, CCAEditGridView *> *oldPageGrids = objc_getAssociatedObject(overlay, kCCAEditPageGridsKey);
            for (CCAEditGridView *pageGrid in oldPageGrids.allValues) [pageGrid removeFromSuperview];
            [oldPageGrids removeAllObjects];
            UIView *oldGridStack = objc_getAssociatedObject(overlay, kCCAEditGridStackKey);
            [oldGridStack removeFromSuperview];
            objc_setAssociatedObject(overlay, kCCAEditGridStackKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(overlay, kCCAEditGridKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            // The private module collection performs one more layout pass as
            // edit mode finishes. On nonzero pages that pass can replace our
            // collection transform with its native identity transform, which
            // leaves the selected page one full span below the viewport. The
            // edit animation already targets this exact settled transform, so
            // reassert it at completion and once after the deferred layout.
            [self applyPageTransformToOverlay:overlay animated:NO];
            [self updatePagedModuleVisibilityForOverlay:overlay showAdjacent:NO];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.12 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (!gEditModeActive && fabs(gCCAPagerInteractiveTranslation) < 0.01) {
                    [self applyPageTransformToOverlay:overlay animated:NO];
                    [self updatePagedModuleVisibilityForOverlay:overlay showAdjacent:NO];
                }
            });
        }
    };
    if (animated) [UIView animateWithDuration:0.28 delay:0.0 options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionBeginFromCurrentState animations:changes completion:completion];
    else { changes(); completion(YES); }
}

- (void)updateEditControlFramesForOverlay:(UIViewController *)overlay {
    if (!overlay.view) return;
    if (gCCADragInProgress || gCCAPagerTransitionActive || gCCAPagerScrubbingActive) return;
    UIButton *addControl = (UIButton *)[overlay.view viewWithTag:kCCAAddControlButtonTag];
    if (addControl) {
        // Centered in the blank space between the last module row and the
        // bottom of the display, sitting just above the home indicator.
        [addControl sizeToFit];
        CGSize size = CGSizeMake(CGRectGetWidth(addControl.bounds), 30.0);
        CGRect bounds = overlay.view.bounds;
        CGFloat bottomInset = MAX(overlay.view.safeAreaInsets.bottom - 14.0, 16.0);
        addControl.frame = CGRectMake((CGRectGetWidth(bounds) - size.width) / 2.0, CGRectGetHeight(bounds) - bottomInset - size.height, size.width, size.height);
    }
    for (UIViewController *module in CCACollectModuleControllers(overlay)) {
        if ((gCCADragInProgress && module.view == gCCAActiveDragModuleView) ||
            (gCCAResizeInProgress && module.view == gCCAActiveResizeModuleView)) continue;
        UIButton *remove = objc_getAssociatedObject(module.view, kCCARemoveButtonKey);
        UIButton *resize = objc_getAssociatedObject(module.view, kCCAResizeButtonKey);
        CGRect moduleFrame = [module.view convertRect:module.view.bounds toView:overlay.view];
        // Borders live with their module wrapper and are naturally clipped by
        // the moving collection. Remove/resize controls live on overlay.view,
        // so explicitly cull them when their owner is outside the viewport;
        // otherwise chrome from the adjacent page floats over blank space.
        CGRect chromeViewport = CGRectInset(overlay.view.bounds, -24.0, -24.0);
        NSString *identifier = CCAModuleIdentifier(module);
        BOOL activeDragSource = CCAIsActiveDragModuleIdentifier(identifier);
        BOOL ownerVisible = gEditModeActive && !activeDragSource && !gCCAEditChromeSuppressedForPaging && !CCAModuleViewIsPageHidden(module.view) && CGRectIntersectsRect(moduleFrame, chromeViewport);
        UIVisualEffectView *border = objc_getAssociatedObject(module.view, @selector(applyEditingToModule:editing:));
        if (border && !gCCAResizeInProgress) {
            UIView *borderHost = border.superview ?: module.view.superview;
            CGRect borderFrame = borderHost ? [overlay.view convertRect:moduleFrame toView:borderHost] : CGRectMake(CGRectGetMinX(module.view.frame), CGRectGetMinY(module.view.frame), CGRectGetWidth(module.view.bounds), CGRectGetHeight(module.view.bounds));
            [self configureEditingBorder:border moduleFrame:borderFrame];
            border.hidden = !ownerVisible || !gModuleBordersEnabled;
            border.alpha = ownerVisible && gModuleBordersEnabled ? 1.0 : 0.0;
        }
        if (remove) remove.hidden = !ownerVisible || !gRemovalButtonsEnabled;
        if (resize) resize.hidden = !ownerVisible || ![self moduleIdentifierSupportsResizing:identifier];
        [self positionEditControlsForModuleView:module.view overlay:overlay overlayFrame:moduleFrame];
    }
}

- (void)editChromeDisplayLinkFired:(__unused CADisplayLink *)displayLink {
    if (!gEditModeActive) return;
    // Only pay the cost of a full module-tree walk + geometry recompute
    // while something is actually in motion. Drag, resize, page scrub/
    // transition, and the enter/exit edit animation all already call
    // updateEditControlFramesForOverlay directly from their own handlers,
    // so this display link is just a safety net — it doesn't need to run
    // 60 times a second while the grid is sitting idle.
    BOOL somethingIsMoving = gCCADragInProgress || gCCAResizeInProgress ||
        gCCAPagerScrubbingActive || gCCAPagerTransitionActive ||
        gCCAEditTransitionActive || fabs(gCCAPagerInteractiveTranslation) > 0.01;
    if (!somethingIsMoving) return;
    for (UIViewController *overlay in gOverlayControllers.allObjects) {
        if (overlay.view.window) [self updateEditControlFramesForOverlay:overlay];
    }
}

- (void)updateEditingChromeForPresentationProgress:(CGFloat)progress overlay:(UIViewController *)overlay {
    if (!overlay || !gEditModeActive) return;
    if (gCCAAddSheetPresentationActive || [overlay.presentedViewController isKindOfClass:[CCAAddControlSheetViewController class]]) return;
    CGFloat clamped = MIN(1.0, MAX(0.0, progress));
    [self updateEditControlFramesForOverlay:overlay];
    UIButton *addControl = (UIButton *)[overlay.view viewWithTag:kCCAAddControlButtonTag];
    NSMutableDictionary<NSNumber *, CCAEditGridView *> *pageGrids = objc_getAssociatedObject(overlay, kCCAEditPageGridsKey);
    UIView *gridStack = objc_getAssociatedObject(overlay, kCCAEditGridStackKey);
    CCAEditTouchShield *touchShield = (CCAEditTouchShield *)[overlay.view viewWithTag:kCCAEditTouchShieldTag];
    addControl.alpha = clamped;
    gridStack.alpha = clamped;
    for (CCAEditGridView *grid in pageGrids.allValues) grid.alpha = clamped;
    touchShield.userInteractionEnabled = clamped > 0.98;
    for (UIViewController *module in CCACollectModuleControllers(overlay)) {
        UIVisualEffectView *border = objc_getAssociatedObject(module.view, @selector(applyEditingToModule:editing:));
        UIButton *remove = objc_getAssociatedObject(module.view, kCCARemoveButtonKey);
        UIButton *resize = objc_getAssociatedObject(module.view, kCCAResizeButtonKey);
        if (clamped < 0.999) [border.layer removeAnimationForKey:@"CCAsterBreathing"];
        border.alpha = clamped;
        remove.alpha = clamped;
        resize.alpha = clamped;
    }
}

- (void)setEditing:(BOOL)editing {
    if (!gEnabled) editing = NO;
    if (editing && gCCAExpandedModuleOpen) return;
    NSUInteger editTransitionGeneration = ++gCCAEditTransitionGeneration;
    gCCAEditTransitionActive = YES;
    gCCAEditChromeSuppressedForPaging = NO;
    gEditModeActive = editing;
    if (editing && !gCCAEditChromeDisplayLink) {
        gCCAEditChromeDisplayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(editChromeDisplayLinkFired:)];
        [gCCAEditChromeDisplayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    } else if (!editing && gCCAEditChromeDisplayLink) {
        [gCCAEditChromeDisplayLink invalidate];
        gCCAEditChromeDisplayLink = nil;
    }
    for (UIViewController *overlay in gOverlayControllers.allObjects) {
        CCARestoreNativeScrollBaseline(overlay);
        [self normalizePagedLayoutForOverlay:overlay];
        if (editing) [self setNativeDismissTapGesturesEnabled:NO forOverlay:overlay];
        for (UIViewController *module in CCACollectModuleControllers(overlay)) [self applyEditingToModule:module editing:editing];
        [self setEditPresentation:editing forOverlay:overlay animated:YES];
        [self updatePageIndicatorsForOverlay:overlay];
        [self updatePagedModuleVisibilityForOverlay:overlay showAdjacent:NO];
        // Sheet presentation/dismissal can run the CC state callbacks while
        // editing is active, leaving the quick-access host hidden with nothing
        // to re-show it. Manage its visibility explicitly on edit transitions.
        [self setQuickAccessButtonsHidden:(editing || gCCAExpandedModuleOpen || !gCCAControlCenterPresented) forOverlay:overlay animated:YES];
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.32 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (editTransitionGeneration != gCCAEditTransitionGeneration || gEditModeActive != editing) return;
        gCCAEditTransitionActive = NO;
        if (!editing) {
            for (UIViewController *overlay in gOverlayControllers.allObjects) {
                [self setNativeDismissTapGesturesEnabled:YES forOverlay:overlay];
            }
        }
    });
}

- (void)dismissEditingImmediately {
    if (!gEditModeActive) return;
    ++gCCAEditTransitionGeneration;
    gCCAEditTransitionActive = NO;
    gEditModeActive = NO;
    gCCAEditChromeSuppressedForPaging = NO;
    [gCCAEditChromeDisplayLink invalidate];
    gCCAEditChromeDisplayLink = nil;
    for (UIViewController *overlay in gOverlayControllers.allObjects) {
        if ([overlay.presentedViewController isKindOfClass:[CCAAddControlSheetViewController class]]) {
            [overlay dismissViewControllerAnimated:NO completion:nil];
        }
        [self normalizePagedLayoutForOverlay:overlay];
        [self setNativeDismissTapGesturesEnabled:YES forOverlay:overlay];
        for (UIViewController *module in CCACollectModuleControllers(overlay)) {
            [self applyEditingToModule:module editing:NO];
        }
        [self setEditPresentation:NO forOverlay:overlay animated:NO];
        [self updatePageIndicatorsForOverlay:overlay];
        [self updatePagedModuleVisibilityForOverlay:overlay showAdjacent:NO];
        [self setQuickAccessButtonsHidden:!gCCAControlCenterPresented forOverlay:overlay animated:NO];
    }
}

@end

@implementation CCAAddControlSheetViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.previewCache = [NSMutableDictionary dictionary];
    // Control Center is a dark surface regardless of system appearance; an
    // opaque dark sheet keeps module platters and text readable in both modes.
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.view.backgroundColor = [UIColor colorWithRed:0.11 green:0.11 blue:0.12 alpha:1.0];

    UISearchBar *search = [[UISearchBar alloc] initWithFrame:CGRectZero];
    search.tag = 11;
    search.placeholder = @"Search Controls";
    search.searchBarStyle = UISearchBarStyleMinimal;
    search.barStyle = UIBarStyleBlack;
    search.tintColor = UIColor.whiteColor;
    search.delegate = self;
    search.searchTextField.textColor = UIColor.whiteColor;
    // Minimal style suppresses the field's own backing and quietly discards
    // backgroundColor set on the text field. A resizable background image is
    // the one supported path that reliably draws the pill.
    CGFloat fieldHeight = 42.0, fieldRadius = 12.0;
    UIGraphicsImageRenderer *fieldRenderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(fieldRadius * 2.0 + 2.0, fieldHeight)];
    UIImage *fieldImage = [fieldRenderer imageWithActions:^(__unused UIGraphicsImageRendererContext *context) {
        [[UIColor colorWithRed:0.46 green:0.46 blue:0.50 alpha:0.28] setFill];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0.0, 0.0, fieldRadius * 2.0 + 2.0, fieldHeight) cornerRadius:fieldRadius] fill];
    }];
    fieldImage = [fieldImage resizableImageWithCapInsets:UIEdgeInsetsMake(0.0, fieldRadius, 0.0, fieldRadius)];
    [search setSearchFieldBackgroundImage:fieldImage forState:UIControlStateNormal];
    [self.view addSubview:search];

    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:CGRectZero];
    scroll.tag = 12;
    scroll.alwaysBounceVertical = YES;
    scroll.showsVerticalScrollIndicator = YES;
    scroll.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    scroll.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.view addSubview:scroll];
    UIView *container = [[UIView alloc] initWithFrame:CGRectZero];
    container.tag = 50;
    [scroll addSubview:container];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    UISearchBar *search = (UISearchBar *)[self.view viewWithTag:11];
    UIScrollView *scroll = (UIScrollView *)[self.view viewWithTag:12];
    CGRect bounds = self.view.bounds;
    search.frame = CGRectMake(12.0, 18.0, CGRectGetWidth(bounds) - 24.0, 54.0);
    scroll.frame = CGRectMake(0.0, 82.0, CGRectGetWidth(bounds), CGRectGetHeight(bounds) - 82.0);
    if (!self.builtGrid && CGRectGetWidth(bounds) > 1.0) {
        self.builtGrid = YES;
        [self reloadGrid];
    }
}

- (NSArray<NSDictionary *> *)visibleSections {
    NSString *query = self.query ?: @"";
    NSMutableArray<NSDictionary *> *sections = [NSMutableArray array];
    if (!query.length) {
        // Suggested strip: headerless, directly below the search bar.
        NSArray<NSString *> *priority = @[@"flashlightmodule", @"controlcenter.timer", @"alarmmodule", @"calculatormodule", @"cameramodule", @"appearancemodule", @"qrcodemodule", @"magnifiermodule", @"lowpowermodule", @"hearingdevices", @"controlcenter.screencapture", @"nfccontrolcenter"];
        NSMutableArray *suggested = [NSMutableArray array];
        NSMutableSet<NSString *> *suggestedIdentifiers = [NSMutableSet set];
        for (NSString *needle in priority) {
            if (suggested.count >= 12) break;
            for (NSDictionary *entry in self.catalog) {
                if (![[entry[@"identifier"] lowercaseString] containsString:needle]) continue;
                CCUILayoutSize size = [[CCAsterCoordinator shared] catalogLayoutSizeForIdentifier:entry[@"identifier"]];
                if (size.width != 1 || size.height != 1) continue;
                if (![suggestedIdentifiers containsObject:entry[@"identifier"]]) {
                    [suggested addObject:entry];
                    [suggestedIdentifiers addObject:entry[@"identifier"]];
                }
                break;
            }
        }
        // Fill the rest of the three-row suggestion area by rotating through
        // categories. This keeps it varied as controls are added or removed
        // instead of turning the final rows into one alphabetical category.
        NSArray<NSString *> *suggestionCategories = @[@"Accessibility", @"Capture", @"Clock", @"Display", @"Focus", @"Home", @"Media", @"Notes", @"Voice Memos", @"Wallet", @"Utilities", @"Tweaks"];
        BOOL addedSuggestion = YES;
        while (suggested.count < 12 && addedSuggestion) {
            addedSuggestion = NO;
            for (NSString *category in suggestionCategories) {
                if (suggested.count >= 12) break;
                for (NSDictionary *entry in self.catalog) {
                    NSString *identifier = entry[@"identifier"];
                    if ([suggestedIdentifiers containsObject:identifier]) continue;
                    if (![(entry[@"category"] ?: @"Utilities") isEqualToString:category]) continue;
                    CCUILayoutSize size = [[CCAsterCoordinator shared] catalogLayoutSizeForIdentifier:identifier];
                    if (size.width != 1 || size.height != 1) continue;
                    [suggested addObject:entry];
                    [suggestedIdentifiers addObject:identifier];
                    addedSuggestion = YES;
                    break;
                }
            }
        }
        if (suggested.count) [sections addObject:@{@"title": @"", @"entries": suggested}];
    }
    NSArray<NSString *> *order = @[@"Accessibility", @"Capture", @"Clock", @"Connectivity", @"Display", @"Focus", @"Home", @"Media", @"Notes", @"Voice Memos", @"Wallet", @"Utilities", @"Tweaks"];
    NSMutableDictionary<NSString *, NSMutableArray *> *byCategory = [NSMutableDictionary dictionary];
    for (NSDictionary *entry in self.catalog) {
        if (query.length && ![entry[@"name"] localizedCaseInsensitiveContainsString:query]) continue;
        NSString *category = entry[@"category"] ?: @"Utilities";
        if (!byCategory[category]) byCategory[category] = [NSMutableArray array];
        [byCategory[category] addObject:entry];
    }
    for (NSString *category in order) {
        NSArray *entries = byCategory[category];
        if (entries.count) [sections addObject:@{@"title": category, @"entries": entries}];
    }
    return sections;
}

- (UIView *)previewForEntry:(NSDictionary *)entry usedIdentifiers:(NSMutableSet<NSString *> *)usedIdentifiers {
    NSString *identifier = entry[@"identifier"];
    // The same entry can appear in Suggested AND its category, but one view
    // instance can only live in one cell — duplicates get a fresh, uncached
    // preview instead of stealing the cached one.
    BOOL firstUse = identifier && ![usedIdentifiers containsObject:identifier];
    if (identifier) [usedIdentifiers addObject:identifier];
    UIView *preview = firstUse ? self.previewCache[identifier] : nil;
    if (!preview) {
        preview = [[CCAsterCoordinator shared] previewViewForCatalogEntry:entry];
        if (identifier && firstUse && preview) self.previewCache[identifier] = preview;
    }
    [preview removeFromSuperview];
    preview.transform = CGAffineTransformIdentity;
    return preview;
}

- (void)reloadGrid {
    UIScrollView *scroll = (UIScrollView *)[self.view viewWithTag:12];
    UIView *container = [scroll viewWithTag:50];
    for (UIView *subview in [container.subviews copy]) [subview removeFromSuperview];

    CGFloat width = CGRectGetWidth(self.view.bounds);
    CGFloat gap = kCCAGridGap;
    CGFloat contentWidth = 4.0 * kCCAGridCellSize + 3.0 * gap; // one Control Center page wide
    CGFloat margin = MAX(16.0, (width - contentWidth) / 2.0);
    CGFloat labelBand = 38.0;
    CGFloat y = 6.0;
    NSMutableSet<NSString *> *usedIdentifiers = [NSMutableSet set];

    for (NSDictionary *section in [self visibleSections]) {
        NSString *title = section[@"title"];
        if ([title length]) {
            // The hairline sits above the header so it caps the previous group.
            UIView *divider = [[UIView alloc] initWithFrame:CGRectMake(margin, y, contentWidth, 1.0 / UIScreen.mainScreen.scale)];
            divider.backgroundColor = [UIColor.whiteColor colorWithAlphaComponent:0.16];
            [container addSubview:divider];
            y += 13.0;
            UILabel *header = [[UILabel alloc] initWithFrame:CGRectMake(margin, y, contentWidth, 18.0)];
            header.text = title;
            header.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
            header.textColor = [UIColor.whiteColor colorWithAlphaComponent:0.55];
            [container addSubview:header];
            y += 28.0;
        }
        // Pack each category on a real four-column occupancy map. The preview
        // supplies the current footprint, so resized/live controls naturally
        // influence the arrangement the next time the sheet opens.
        NSMutableArray<NSDictionary *> *items = [NSMutableArray array];
        NSUInteger originalIndex = 0;
        for (NSDictionary *entry in section[@"entries"]) {
            UIView *preview = [self previewForEntry:entry usedIdentifiers:usedIdentifiers];
            CGSize size = preview.bounds.size;
            if (size.width < 1.0 || size.height < 1.0) size = CGSizeMake(kCCAGridCellSize, kCCAGridCellSize);
            NSUInteger columns = MAX(1, MIN(4, (NSUInteger)llround((size.width + gap) / kCCAGridStep)));
            NSUInteger rows = MAX(1, MIN(4, (NSUInteger)llround((size.height + gap) / kCCAGridStep)));
            [items addObject:@{@"entry": entry, @"preview": preview, @"size": [NSValue valueWithCGSize:size], @"columns": @(columns), @"rows": @(rows), @"index": @(originalIndex++)}];
        }
        [items sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
            NSUInteger leftArea = [left[@"columns"] unsignedIntegerValue] * [left[@"rows"] unsignedIntegerValue];
            NSUInteger rightArea = [right[@"columns"] unsignedIntegerValue] * [right[@"rows"] unsignedIntegerValue];
            if (leftArea != rightArea) return leftArea < rightArea ? NSOrderedAscending : NSOrderedDescending;
            NSUInteger leftRows = [left[@"rows"] unsignedIntegerValue], rightRows = [right[@"rows"] unsignedIntegerValue];
            if (leftRows != rightRows) return leftRows > rightRows ? NSOrderedAscending : NSOrderedDescending;
            return [left[@"index"] compare:right[@"index"]];
        }];

        CGFloat sectionTop = y;
        CGFloat rowPitch = kCCAGridCellSize + labelBand + 14.0;
        CGFloat sectionBottom = sectionTop;
        NSMutableArray<NSMutableArray<NSNumber *> *> *occupancy = [NSMutableArray array];
        void (^ensureRows)(NSUInteger) = ^(NSUInteger count) {
            while (occupancy.count < count) [occupancy addObject:[@[@NO, @NO, @NO, @NO] mutableCopy]];
        };
        for (NSDictionary *item in items) {
            NSDictionary *entry = item[@"entry"];
            UIView *preview = item[@"preview"];
            CGSize size = [item[@"size"] CGSizeValue];
            NSUInteger columns = [item[@"columns"] unsignedIntegerValue];
            NSUInteger rows = [item[@"rows"] unsignedIntegerValue];
            NSUInteger placedRow = 0, placedColumn = 0;
            BOOL found = NO;
            for (NSUInteger row = 0; !found && row < 64; row++) {
                ensureRows(row + rows);
                for (NSUInteger column = 0; !found && column + columns <= 4; column++) {
                    BOOL fits = YES;
                    for (NSUInteger testRow = row; fits && testRow < row + rows; testRow++) {
                        for (NSUInteger testColumn = column; testColumn < column + columns; testColumn++) {
                            if ([occupancy[testRow][testColumn] boolValue]) { fits = NO; break; }
                        }
                    }
                    if (fits) { placedRow = row; placedColumn = column; found = YES; }
                }
            }
            if (!found) continue;
            for (NSUInteger markRow = placedRow; markRow < placedRow + rows; markRow++) {
                for (NSUInteger markColumn = placedColumn; markColumn < placedColumn + columns; markColumn++) occupancy[markRow][markColumn] = @YES;
            }
            CGFloat x = margin + placedColumn * kCCAGridStep;
            CGFloat itemY = sectionTop + placedRow * rowPitch;
            CGFloat cellHeight = size.height + labelBand;
            UIView *cell = [[UIView alloc] initWithFrame:CGRectMake(x, itemY, size.width, cellHeight)];
            preview.frame = (CGRect){CGPointZero, size};
            [cell addSubview:preview];
            if ([entry[@"allowsMultiple"] boolValue] && [entry[@"instanceCount"] unsignedIntegerValue] > 0) {
                UILabel *badge = [[UILabel alloc] initWithFrame:CGRectMake(CGRectGetWidth(preview.bounds) - 24.0, -7.0, 31.0, 23.0)];
                badge.text = [NSString stringWithFormat:@"%lu", (unsigned long)[entry[@"instanceCount"] unsignedIntegerValue]];
                badge.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightBold];
                badge.textColor = UIColor.whiteColor;
                badge.textAlignment = NSTextAlignmentCenter;
                badge.backgroundColor = [UIColor colorWithRed:0.12 green:0.50 blue:1.0 alpha:0.96];
                badge.layer.cornerRadius = 11.5;
                badge.layer.cornerCurve = kCACornerCurveContinuous;
                badge.layer.masksToBounds = YES;
                badge.layer.borderWidth = 1.5;
                badge.layer.borderColor = [UIColor colorWithWhite:0.05 alpha:0.72].CGColor;
                badge.userInteractionEnabled = NO;
                [cell addSubview:badge];
            }
            UILabel *name = [[UILabel alloc] initWithFrame:CGRectMake(-gap / 2.0, size.height + 4.0, size.width + gap, labelBand - 8.0)];
            name.text = entry[@"name"];
            name.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightMedium];
            name.textColor = UIColor.whiteColor;
            name.textAlignment = NSTextAlignmentCenter;
            name.numberOfLines = 2;
            name.lineBreakMode = NSLineBreakByTruncatingTail;
            [cell addSubview:name];
            UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(cellTapped:)];
            [cell addGestureRecognizer:tap];
            objc_setAssociatedObject(cell, @selector(cellTapped:), entry[@"identifier"], OBJC_ASSOCIATION_COPY_NONATOMIC);
            [container addSubview:cell];
            sectionBottom = MAX(sectionBottom, itemY + cellHeight);
        }
        y = sectionBottom + 20.0;
    }
    container.frame = CGRectMake(0.0, 0.0, width, y);
    scroll.contentSize = CGSizeMake(width, y + 44.0);
    if (self.query.length && scroll.contentOffset.y > 0.0) [scroll setContentOffset:CGPointZero animated:NO];
}

- (void)searchBar:(__unused UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    self.query = searchText;
    [self reloadGrid];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

- (void)cellTapped:(UITapGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateRecognized) return;
    NSString *identifier = objc_getAssociatedObject(gesture.view, @selector(cellTapped:));
    if (!identifier.length) return;
    [UIView animateWithDuration:0.10 animations:^{ gesture.view.transform = CGAffineTransformMakeScale(0.94, 0.94); } completion:^(__unused BOOL finished) {
        [UIView animateWithDuration:0.14 animations:^{ gesture.view.transform = CGAffineTransformIdentity; }];
        [[CCAsterCoordinator shared] addControlSheetDidSelectIdentifier:identifier fromSheet:self];
    }];
}

@end

%hook CCUIModuleCollectionViewController

- (CCUILayoutSize)moduleLayoutSizeForContentModuleContext:(id)context forOrientation:(NSInteger)orientation {
    CCUILayoutSize size = %orig;
    NSString *identifier = [context respondsToSelector:@selector(moduleIdentifier)] ? ((id (*)(id, SEL))objc_msgSend)(context, @selector(moduleIdentifier)) : nil;
    if (identifier.length && !gCCABaseLayoutSizes[identifier]) gCCABaseLayoutSizes[identifier] = [NSValue value:&size withObjCType:@encode(CCUILayoutSize)];
    NSArray<NSNumber *> *custom = gCCACustomSizes[identifier];
    if (custom.count >= 2) size = (CCUILayoutSize){custom[0].unsignedIntegerValue, custom[1].unsignedIntegerValue};
    return size;
}

- (CCUILayoutRect)layoutView:(id)layoutView layoutRectForSubview:(UIView *)subview {
    CCUILayoutRect rect = %orig;
    NSDictionary *containers = nil;
    @try { containers = [(id)self valueForKey:@"moduleContainerViewByIdentifier"]; } @catch (__unused NSException *exception) {}
    __block NSString *identifier = nil;
    [containers enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
        UIView *candidateView = [value isKindOfClass:[UIView class]] ? value : ([value respondsToSelector:@selector(view)] ? [value view] : nil);
        if (candidateView == subview) { identifier = key; *stop = YES; }
    }];
    if (identifier.length) {
        if (!gCCABaseLayoutSizes[identifier]) gCCABaseLayoutSizes[identifier] = [NSValue value:&rect.size withObjCType:@encode(CCUILayoutSize)];
        gCCANativeLayoutRects[identifier] = [NSValue value:&rect withObjCType:@encode(CCUILayoutRect)];
        NSArray<NSNumber *> *customOrigin = gCCACustomOrigins[identifier];
        if (customOrigin.count >= 2) rect.origin = (CCUILayoutPoint){customOrigin[0].unsignedIntegerValue, customOrigin[1].unsignedIntegerValue};
        NSArray<NSNumber *> *customSize = gCCACustomSizes[identifier];
        if (customSize.count >= 2) rect.size = (CCUILayoutSize){customSize[0].unsignedIntegerValue, customSize[1].unsignedIntegerValue};
        if (gEnabled) {
            NSUInteger page = CCAPageForRect(rect);
            rect.origin.y += page * CCAVisualPageSpacerRows();
        }
    }
    if (gEnabled && gEditModeActive && gCCADragInProgress && rect.size.width == 1 && rect.size.height == 3) {
        rect.size.height = 2;
    }
    return rect;
}


%end

%hook MTMaterialView

- (void)didMoveToSuperview {
    %orig;
    if (!gEnabled) return;
    UIView *view = (UIView *)(id)self;
    UIView *parent = view.superview;
    if (![parent.superview isKindOfClass:[UIScrollView class]]) return;
    if (CCAViewTreeContainsClassName(parent, @"CCUIHeaderPocketView")) return;
    if (!CCAViewTreeContainsClassName(parent, @"CCUISensorAttributionPrivacyHeaderView")) return;
    CGSize screenSize = UIScreen.mainScreen.bounds.size;
    BOOL fullScreen = fabs(CGRectGetWidth(view.bounds) - screenSize.width) < 8.0 &&
                      fabs(CGRectGetHeight(view.bounds) - screenSize.height) < 8.0;
    if (!fullScreen) return;
    view.hidden = YES;
    view.alpha = 0.0;
    view.layer.opacity = 0.0;
}

- (void)layoutSubviews {
    %orig;
    if (!gEnabled) return;
    UIView *view = (UIView *)(id)self;
    UIView *parent = view.superview;
    if (![parent.superview isKindOfClass:[UIScrollView class]]) return;
    if (CCAViewTreeContainsClassName(parent, @"CCUIHeaderPocketView")) return;
    if (!CCAViewTreeContainsClassName(parent, @"CCUISensorAttributionPrivacyHeaderView")) return;
    CGSize screenSize = UIScreen.mainScreen.bounds.size;
    BOOL fullScreen = fabs(CGRectGetWidth(view.bounds) - screenSize.width) < 8.0 &&
                      fabs(CGRectGetHeight(view.bounds) - screenSize.height) < 8.0;
    if (!fullScreen) return;
    view.hidden = YES;
    view.alpha = 0.0;
    view.layer.opacity = 0.0;
}

%end

%hook CCUIModuleCollectionView

- (instancetype)initWithFrame:(CGRect)frame layoutOptions:(id)layoutOptions {
    CCAApplyCompactGridSpacingToLayoutOptions(layoutOptions);
    id result = %orig;
    @try { CCAApplyCompactGridSpacingToLayoutOptions([(id)result valueForKey:@"layoutOptions"]); } @catch (__unused NSException *exception) {}
    return result;
}

- (void)layoutSubviews {
    %orig;
    if (!gEnabled) return;
    UIScrollView *scrollView = (UIScrollView *)(id)self;
    scrollView.alwaysBounceVertical = NO;
    scrollView.alwaysBounceHorizontal = NO;
    scrollView.bounces = NO;
    scrollView.showsVerticalScrollIndicator = NO;
    scrollView.showsHorizontalScrollIndicator = NO;
    scrollView.scrollIndicatorInsets = UIEdgeInsetsZero;
    if (fabs(scrollView.contentOffset.x) > 0.25 || fabs(scrollView.contentOffset.y) > 0.25) {
        [scrollView setContentOffset:CGPointZero animated:NO];
    }
}

- (CGRect)frameForLayoutRect:(CCUILayoutRect)layoutRect {
    CGRect frame = %orig;
    if (gEnabled) {
        CGFloat containerWidth = CGRectGetWidth(((UIView *)(id)self).window.bounds);
        if (containerWidth < 1.0) containerWidth = CGRectGetWidth(UIScreen.mainScreen.bounds);
        frame.origin.x += CCAGridHorizontalCenteringCompensationForFrame(frame, layoutRect, containerWidth);
    }
    return frame;
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *nativeHit = %orig;
    if (nativeHit || !gEnabled) return nativeHit;

    UIView *collectionView = (UIView *)(id)self;
    for (UIViewController *overlay in gOverlayControllers.allObjects) {
        CGPoint overlayPoint = [collectionView convertPoint:point toView:overlay.view];
        for (UIViewController *module in CCACollectModuleControllers(overlay)) {
            if (module.view.hidden || module.view.alpha <= 0.01 || CCAModuleViewIsPageHidden(module.view)) continue;
            if (!CGRectContainsPoint(CCAVisibleModuleFrame(module, overlay), overlayPoint)) continue;
            CGPoint modulePoint = [collectionView convertPoint:point toView:module.view];
            UIView *moduleHit = [module.view hitTest:modulePoint withEvent:event];
            return moduleHit ?: module.view;
        }
    }
    return nil;
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    BOOL insideOriginal = %orig;
    if (insideOriginal) return YES;
    if (!gEnabled) return NO;

    // iOS 16 keeps the collection view's original six-row bounds even when
    // CCAster's position provider lays modules into rows seven and eight.
    // UIKit consequently rejects touches before they reach those visible
    // module wrappers. Extend hit testing to the actual laid-out descendants
    // without changing the collection frame or any grid geometry.
    UIView *collectionView = (UIView *)(id)self;
    CGRect interactiveBounds = collectionView.bounds;
    for (UIView *subview in collectionView.subviews) {
        if (subview.hidden || subview.alpha <= 0.01) continue;
        interactiveBounds = CGRectUnion(interactiveBounds, subview.frame);
    }
    return CGRectContainsPoint(interactiveBounds, point);
}

%end

%hook UIWindow

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (gEnabled && gCCAControlCenterPresented && !gEditModeActive && !gCCAExpandedModuleOpen) {
        for (UIViewController *overlay in gOverlayControllers.allObjects) {
            if (overlay.view.window != (UIWindow *)(id)self) continue;
            CGPoint overlayPoint = [(UIWindow *)(id)self convertPoint:point toView:overlay.view];
            for (UIViewController *module in CCACollectModuleControllers(overlay)) {
                if (module.view.hidden || module.view.alpha <= 0.01 || CCAModuleViewIsPageHidden(module.view)) continue;
                if (!CGRectContainsPoint(CCAVisibleModuleFrame(module, overlay), overlayPoint)) continue;
                CGPoint modulePoint = [(UIWindow *)(id)self convertPoint:point toView:module.view];
                UIView *moduleHit = [module.view hitTest:modulePoint withEvent:event];
                if (moduleHit) return moduleHit;
            }
        }
    }
    return %orig;
}

%end

%hook UIView

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (gEnabled && !gEditModeActive && !gCCAExpandedModuleOpen) {
        for (UIViewController *overlay in gOverlayControllers.allObjects) {
            if ((UIView *)(id)self != overlay.view) continue;
            for (UIViewController *module in CCACollectModuleControllers(overlay)) {
                if (module.view.hidden || module.view.alpha <= 0.01 || CCAModuleViewIsPageHidden(module.view)) continue;
                if (!CGRectContainsPoint(CCAVisibleModuleFrame(module, overlay), point)) continue;
                CGPoint modulePoint = [(UIView *)(id)self convertPoint:point toView:module.view];
                UIView *moduleHit = [module.view hitTest:modulePoint withEvent:event];
                if (moduleHit) return moduleHit;
            }
            break;
        }
    }
    return %orig;
}

%end

static NSArray<NSNumber *> *CCAResizedPreviewSizeForDescendant(UIView *view) {
    for (UIView *ancestor = view; ancestor; ancestor = ancestor.superview) {
        NSArray<NSNumber *> *size = objc_getAssociatedObject(ancestor, kCCAResizePresentationSizeOverrideKey);
        if (size.count >= 2) return size;
    }
    return nil;
}

static void CCAAnimateDiscreteMediaLayout(UIView *view) {
    Class filterClass = NSClassFromString(@"CAFilter");
    SEL factory = NSSelectorFromString(@"filterWithName:");
    id blur = filterClass && [filterClass respondsToSelector:factory] ?
        ((id (*)(id, SEL, id))objc_msgSend)(filterClass, factory, @"gaussianBlur") : nil;
    if (blur) {
        @try {
            [blur setValue:@"CCAsterMediaLayoutBlur" forKey:@"name"];
            [blur setValue:@6.0 forKey:@"inputRadius"];
            [blur setValue:@YES forKey:@"inputNormalizeEdges"];
            view.layer.filters = @[blur];
            CABasicAnimation *blurAnimation = [CABasicAnimation animationWithKeyPath:@"filters.CCAsterMediaLayoutBlur.inputRadius"];
            blurAnimation.fromValue = @6.0;
            blurAnimation.toValue = @0.0;
            blurAnimation.duration = 0.20;
            blurAnimation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
            [blur setValue:@0.0 forKey:@"inputRadius"];
            [view.layer addAnimation:blurAnimation forKey:@"CCAsterMediaLayoutBlur"];
        } @catch (__unused NSException *exception) { view.layer.filters = nil; }
    }
    view.layer.opacity = 1.0;
    CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
    fade.fromValue = @0.18;
    fade.toValue = @1.0;
    fade.duration = 0.20;
    fade.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [view.layer addAnimation:fade forKey:@"CCAsterMediaLayoutFade"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.22 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (![view.layer animationForKey:@"CCAsterMediaLayoutBlur"]) view.layer.filters = nil;
    });
}

// --- Media module internals (structure learned from CC26, credit
// therealhoodboy/CC26). The compact CC tile hosts MRUNowPlayingView with a
// `_layout` ivar (1/2 = expanded platter layouts, skip those), containing
// MRUNowPlayingControlsView -> _headerView (MRUNowPlayingHeaderView with
// _artworkView, native _routingButton, _labelView) + _transportControlsView
// (leftButton/middleButton/rightButton). ---

static BOOL CCAIsLandscapeOrientation(UIView *view) {
    CGSize size = view.bounds.size;
    return size.width > size.height;
}

static UIView *CCAIvarView(id object, const char *name) {
    if (!object) return nil;
    Ivar ivar = class_getInstanceVariable(object_getClass(object), name);
    if (!ivar) return nil;
    id value = object_getIvar(object, ivar);
    return [value isKindOfClass:[UIView class]] ? value : nil;
}

static UIView *CCAMediaAncestorOfClass(UIView *view, NSString *className) {
    for (UIView *ancestor = view; ancestor; ancestor = ancestor.superview) {
        if ([NSStringFromClass(ancestor.class) isEqualToString:className]) return ancestor;
    }
    return nil;
}

// YES only for media views living inside a Control Center module tile (not the
// lock screen player) while the tile is in its collapsed `_layout`.
static BOOL CCAMediaViewInsideControlCenterTile(UIView *view) {
    if (!gEnabled) return NO;
    UIView *container = CCAMediaAncestorOfClass(view, @"CCUIContentModuleContentContainerView");
    if (!container) return NO;
    // Only the media module's OWN expansion hands the layout back to the
    // system; other modules expanding must not eject the tile from its custom
    // layout (that left it mangled in native form behind the platter). The
    // container's stuck-prone `_expanded` flag is consulted only inside
    // CCAster's own expansion window.
    if (gCCAExpandedModuleOpen) {
        BOOL mediaExpanding = [gCCAExpandedModuleIdentifier isEqualToString:@"com.apple.mediaremote.controlcenter.nowplaying"];
        if (!mediaExpanding && !gCCAExpandedModuleIdentifier.length) {
            @try { mediaExpanding = [[container valueForKey:@"_expanded"] boolValue]; } @catch (__unused NSException *exception) {}
        }
        if (mediaExpanding) return NO;
    }
    UIView *npView = CCAMediaAncestorOfClass(view, @"MRUNowPlayingView");
    if (npView) {
        @try {
            NSInteger layout = [[npView valueForKey:@"_layout"] integerValue];
            if (layout == 1 || layout == 2) return NO;
        } @catch (__unused NSException *exception) {}
    }
    return YES;
}

static NSString *CCAMediaModeForNowPlayingView(UIView *npView) {
    NSArray<NSNumber *> *preview = CCAResizedPreviewSizeForDescendant(npView);
    CGSize size = npView.bounds.size;
    NSUInteger columns = preview.count >= 2 ? preview[0].unsignedIntegerValue : (size.width > 230.0 ? 4 : 2);
    NSUInteger rows = preview.count >= 2 ? preview[1].unsignedIntegerValue :
        (size.height < 100.0 ? 1 : (size.height > 230.0 ? 4 : 2));
    return columns < 4 ? @"compact" : [NSString stringWithFormat:@"wide%lu", (unsigned long)rows];
}

// Mode for any descendant of the now playing view; nil when CCAster should
// leave the native layout alone entirely.
static NSString *CCAActiveMediaMode(UIView *descendant) {
    UIView *npView = CCAMediaAncestorOfClass(descendant, @"MRUNowPlayingView");
    if (!npView || !CCAMediaViewInsideControlCenterTile(npView)) return nil;
    NSString *stored = objc_getAssociatedObject(npView, kCCANowPlayingLayoutModeKey);
    return stored ?: CCAMediaModeForNowPlayingView(npView);
}

static void CCAAdjustMediaLabelFonts(UIView *view, BOOL isTitle) {
    for (UIView *subview in view.subviews) {
        if ([subview isKindOfClass:[UILabel class]]) {
            UILabel *label = (UILabel *)subview;
            label.font = [UIFont systemFontOfSize:13.0 weight:isTitle ? UIFontWeightSemibold : UIFontWeightRegular];
            label.adjustsFontSizeToFitWidth = YES;
            label.minimumScaleFactor = 0.7;
            label.textAlignment = NSTextAlignmentLeft;
        } else {
            CCAAdjustMediaLabelFonts(subview, isTitle);
        }
    }
}

// The system dims/hides pieces of the compact label stack for its own layout;
// force children visible whenever CCAster owns the geometry.
static void CCAForceMediaSubviewAlphas(UIView *view) {
    for (UIView *subview in view.subviews) {
        if (!subview.hidden) subview.layer.opacity = 1.0;
    }
}

// Layout verified against the live iOS 16.5 hierarchy: every
// component is a direct child of MRUNowPlayingView — _artworkView (with its
// own placeholder system), _headerView (hosting _labelView + _routingButton),
// _timeControlsView, _transportControlsView, _volumeControlsView. The header
// is kept full-bleed so its children can be placed in tile coordinates; the
// sibling control strips are fronted above it for touch priority.
static void CCAConfigureNowPlayingLayout(UIView *nowPlayingView) {
    if (!nowPlayingView) return;
    if (!CCAMediaViewInsideControlCenterTile(nowPlayingView)) {
        // Leaving CCAster's tile modes (expansion, platter handoff): drop the
        // stored mode and give the wrapper its corner chrome back so the
        // native expanded layout isn't missing pieces.
        if (objc_getAssociatedObject(nowPlayingView, kCCANowPlayingLayoutModeKey)) {
            objc_setAssociatedObject(nowPlayingView, kCCANowPlayingLayoutModeKey, nil, OBJC_ASSOCIATION_COPY_NONATOMIC);
            UIView *wrapper = CCAMediaAncestorOfClass(nowPlayingView, @"MRUControlCenterView");
            UIView *cornerRouting = CCAIvarView(wrapper, "_routingButton");
            UIView *cornerMore = CCAIvarView(wrapper, "_moreButton");
            if (cornerRouting) { cornerRouting.hidden = NO; cornerRouting.alpha = 1.0; }
            if (cornerMore) { cornerMore.hidden = NO; cornerMore.alpha = 1.0; }
            // The expanded platter reuses these exact subviews (_layout flip),
            // so every tile-mode override must be handed back to the system:
            // forced hidden/alpha on time & volume strips, the hidden rewind
            // button, the header play/pause button, and artwork styling.
            UIView *artwork = CCAIvarView(nowPlayingView, "_artworkView");
            UIView *header = CCAIvarView(nowPlayingView, "_headerView");
            UIView *time = CCAIvarView(nowPlayingView, "_timeControlsView");
            UIView *transport = CCAIvarView(nowPlayingView, "_transportControlsView");
            UIView *volume = CCAIvarView(nowPlayingView, "_volumeControlsView");
            [UIView performWithoutAnimation:^{
                if (artwork) {
                    artwork.backgroundColor = UIColor.clearColor;
                    artwork.layer.cornerRadius = 0.0;
                    artwork.layer.masksToBounds = NO;
                }
                for (UIView *strip in @[time ?: (id)NSNull.null, volume ?: (id)NSNull.null]) {
                    if ((id)strip == NSNull.null) continue;
                    strip.hidden = NO;
                    @try {
                        NSString *flagKey = strip == time ? @"showTimeControlsView" : @"showVolumeControlsView";
                        strip.alpha = [[nowPlayingView valueForKey:flagKey] boolValue] ? 1.0 : 0.0;
                    } @catch (__unused NSException *exception) { strip.alpha = 1.0; }
                    strip.layer.opacity = strip.alpha;
                }
                UIView *leftButton = CCAIvarView(transport, "_leftButton");
                UIView *stripRouting = CCAIvarView(transport, "_routingButton");
                UIView *leadingButton = CCAIvarView(transport, "_leadingButton");
                if (leftButton) { leftButton.hidden = NO; leftButton.alpha = 1.0; }
                if (stripRouting) stripRouting.hidden = NO;
                if (leadingButton) leadingButton.hidden = NO;
                UIView *headerTransport = CCAIvarView(header, "_transportButton");
                if (headerTransport) headerTransport.hidden = NO;
            }];
            [nowPlayingView setNeedsLayout];
        }
        return;
    }
    NSString *mode = CCAMediaModeForNowPlayingView(nowPlayingView);
    NSString *previous = objc_getAssociatedObject(nowPlayingView, kCCANowPlayingLayoutModeKey);
    objc_setAssociatedObject(nowPlayingView, kCCANowPlayingLayoutModeKey, mode, OBJC_ASSOCIATION_COPY_NONATOMIC);

    UIView *artwork = CCAIvarView(nowPlayingView, "_artworkView");
    UIView *header = CCAIvarView(nowPlayingView, "_headerView");
    UIView *time = CCAIvarView(nowPlayingView, "_timeControlsView");
    UIView *transport = CCAIvarView(nowPlayingView, "_transportControlsView");
    UIView *volume = CCAIvarView(nowPlayingView, "_volumeControlsView");
    if (!header || !transport) return;

    BOOL wide1 = [mode isEqualToString:@"wide1"];
    BOOL wide2 = [mode isEqualToString:@"wide2"];
    BOOL wide4 = [mode isEqualToString:@"wide4"];
    BOOL showsTime = wide2 || wide4;
    BOOL showsVolume = wide4;
    CGFloat W = CGRectGetWidth(nowPlayingView.bounds);

    [UIView performWithoutAnimation:^{
        nowPlayingView.clipsToBounds = YES;
        header.frame = nowPlayingView.bounds;
        // The MRUControlCenterView wrapper draws its own corner routing
        // indicator and "more" button; CCAster's header routing button is the
        // sole routing control in every custom layout.
        UIView *wrapper = CCAMediaAncestorOfClass(nowPlayingView, @"MRUControlCenterView");
        UIView *cornerRouting = CCAIvarView(wrapper, "_routingButton");
        UIView *cornerMore = CCAIvarView(wrapper, "_moreButton");
        if (cornerRouting) { cornerRouting.hidden = YES; cornerRouting.alpha = 0.0; }
        if (cornerMore) { cornerMore.hidden = YES; cornerMore.alpha = 0.0; }

        CGRect artworkFrame, transportFrame, timeFrame = CGRectZero, volumeFrame = CGRectZero;
        if (wide1) {
            artworkFrame = CGRectMake(8.0, 8.0, 51.0, 51.0);
            transportFrame = CGRectMake(170.0, 11.5, 84.0, 44.0);
        } else if (wide2) {
            artworkFrame = CGRectMake(12.0, 12.0, 122.0, 122.0);
            transportFrame = CGRectMake(142.0, 54.0, 140.0, 44.0);
            timeFrame = CGRectMake(142.0, 96.0, W - 162.0, 44.0);
        } else if (wide4) {
            artworkFrame = CGRectMake(16.0, 16.0, 96.0, 96.0);
            timeFrame = CGRectMake(20.0, 116.0, W - 40.0, 44.0);
            transportFrame = CGRectMake(52.0, 162.0, W - 104.0, 44.0);
            volumeFrame = CGRectMake(20.0, 208.0, W - 40.0, 44.0);
        } else {
            artworkFrame = CGRectMake(11.0, 10.0, 50.0, 50.0);
            transportFrame = CGRectMake(18.0, 100.0, 110.0, 44.0);
        }

        transport.frame = transportFrame;
        transport.alpha = 1.0;
        transport.layer.opacity = 1.0;
        transport.hidden = NO;

        if (artwork) {
            artwork.frame = artworkFrame;
            artwork.hidden = NO;
            artwork.alpha = 1.0;
            artwork.layer.opacity = 1.0;
            // Blank rounded placeholder with a light shade when nothing is
            // playing; MRUArtworkView's own placeholder draws on top when the
            // system provides one.
            artwork.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.12];
            artwork.layer.cornerRadius = CGRectGetWidth(artworkFrame) * 0.22;
            artwork.layer.cornerCurve = kCACornerCurveContinuous;
            artwork.layer.masksToBounds = YES;
            @try {
                if (![[artwork valueForKey:@"showPlaceholder"] boolValue]) [artwork setValue:@YES forKey:@"showPlaceholder"];
            } @catch (__unused NSException *exception) {}
        }
        if (time) {
            time.hidden = !showsTime;
            time.alpha = showsTime ? 1.0 : 0.0;
            time.layer.opacity = time.alpha;
            if (showsTime) {
                time.frame = timeFrame;
                [time setNeedsLayout];
            }
        }
        if (volume) {
            volume.hidden = !showsVolume;
            volume.alpha = showsVolume ? 1.0 : 0.0;
            volume.layer.opacity = volume.alpha;
            if (showsVolume) {
                volume.frame = volumeFrame;
                [volume setNeedsLayout];
            }
        }
        [nowPlayingView bringSubviewToFront:transport];
        if (time && showsTime) [nowPlayingView bringSubviewToFront:time];
        if (volume && showsVolume) [nowPlayingView bringSubviewToFront:volume];
    }];
    if (previous.length && ![previous isEqualToString:mode]) CCAAnimateDiscreteMediaLayout(nowPlayingView);
    [header setNeedsLayout];
    [transport setNeedsLayout];
}

static UIViewController *CCAConnectivityChild(UIViewController *controller, NSString *className) {
    NSMutableArray<UIViewController *> *queue = [NSMutableArray arrayWithArray:controller.childViewControllers];
    while (queue.count) {
        UIViewController *candidate = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([NSStringFromClass(candidate.class) isEqualToString:className]) return candidate;
        [queue addObjectsFromArray:candidate.childViewControllers];
    }
    return nil;
}

static NSString *CCAConnectivityDetailChildClassForIdentifier(NSString *identifier) {
    NSString *lower = identifier.lowercaseString;
    if ([lower containsString:@".wifi"]) return @"CCUIConnectivityWifiViewController";
    if ([lower containsString:@".bluetooth"]) return @"CCUIConnectivityBluetoothViewController";
    if ([lower containsString:@".airdrop"]) return @"CCUIConnectivityAirDropViewController";
    return nil;
}

static UIViewController *CCAConnectivityDetailFromConnectivityController(UIViewController *connectivity, NSString *identifier, id interactionController) {
    NSString *childClass = CCAConnectivityDetailChildClassForIdentifier(identifier);
    if (!connectivity || !childClass.length) return nil;
    UIViewController *child = CCAConnectivityChild(connectivity, childClass);
    SEL detailSelector = NSSelectorFromString(@"presentedViewControllerForContentModuleDetailClickPresentationInteractionController:");
    if (!child || ![child respondsToSelector:detailSelector]) return nil;
    @try {
        return ((UIViewController *(*)(id, SEL, id))objc_msgSend)((id)child, detailSelector, interactionController);
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static UIViewController *CCAConnectivityDetailViewControllerForIdentifier(NSString *identifier, id interactionController) {
    if (!identifier.length) return nil;
    NSString *childClass = CCAConnectivityDetailChildClassForIdentifier(identifier);
    if (!childClass.length) return nil;
    for (UIViewController *overlay in gOverlayControllers.allObjects) {
        UIViewController *presentedRoot = overlay.presentedViewController;
        UIViewController *presentedConnectivity = CCAConnectivityChild(presentedRoot, @"CCUIConnectivityModuleViewController");
        if ([NSStringFromClass(presentedRoot.class) isEqualToString:@"CCUIConnectivityModuleViewController"]) presentedConnectivity = presentedRoot;
        UIViewController *detail = CCAConnectivityDetailFromConnectivityController(presentedConnectivity, identifier, interactionController);
        if (detail) return detail;
    }
    for (UIViewController *overlay in gOverlayControllers.allObjects) {
        for (UIViewController *module in CCACollectModuleControllers(overlay)) {
            if (![CCAModuleIdentifier(module) isEqualToString:@"com.apple.control-center.ConnectivityModule"]) continue;
            UIViewController *connectivity = CCAConnectivityChild(module, @"CCUIConnectivityModuleViewController");
            if ([NSStringFromClass(module.class) isEqualToString:@"CCUIConnectivityModuleViewController"]) connectivity = module;
            UIViewController *detail = CCAConnectivityDetailFromConnectivityController(connectivity, identifier, interactionController);
            if (detail) return detail;
        }
    }
    return nil;
}

static UIViewController *CCAStandaloneConnectivityDetailIMP(id self, SEL _cmd, id interactionController) {
    NSString *identifier = nil;
    if ([self isKindOfClass:[UIViewController class]]) identifier = ((UIViewController *)self).view.accessibilityIdentifier;
    return CCAConnectivityDetailViewControllerForIdentifier(identifier, interactionController);
}

static void CCAInstallStandaloneConnectivityDetailMethod(void) {
    static BOOL installed = NO;
    if (installed) return;
    Class cls = NSClassFromString(@"CCAConnectivityButtonViewController");
    if (!cls) return;
    SEL detailSelector = NSSelectorFromString(@"presentedViewControllerForContentModuleDetailClickPresentationInteractionController:");
    class_addMethod(cls, detailSelector, (IMP)CCAStandaloneConnectivityDetailIMP, "@@:@");
    installed = YES;
}

static void CCAOpenPendingConnectivityDetailFromPresentation(UIPresentationController *presentationController) {
    NSString *identifier = gCCAConnectivityPendingDetailIdentifier.copy;
    gCCAConnectivityPendingDetailIdentifier = nil;
    if (!identifier.length || !presentationController.presentedViewController) return;
    // The per-toggle menu returned by Apple's connectivity child is only the
    // content controller. The private click presentation interaction normally
    // wraps it in a CCUI detail container. Presenting it manually makes the
    // list fill the screen and leaves the first-level platter visible behind
    // it, so keep this path as a no-op fallback and let the native detail
    // selector hooks service real pressure interactions directly.
    (void)presentationController;
}

static void CCAResetConnectivityCompactTransforms(UIViewController *controller) {
    if (!controller) return;
    NSArray<NSString *> *classes = @[
        @"CCUIConnectivityAirplaneViewController", @"CCUIConnectivityCellularDataViewController",
        @"CCUIConnectivityWifiViewController", @"CCUIConnectivityBluetoothViewController",
        @"CCUIConnectivityAirDropViewController", @"CCUIConnectivityHotspotViewController"
    ];
    [UIView performWithoutAnimation:^{
        for (NSString *name in classes) {
            UIViewController *child = CCAConnectivityChild(controller, name);
            if (child) {
                child.view.transform = CGAffineTransformIdentity;
                UIView *roundButton = CCAFindSubviewWithClassName(child.view, @"CCUIRoundButton");
                objc_setAssociatedObject(roundButton, kCCAConnectivityExpandedCardKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                objc_setAssociatedObject(roundButton, kCCAConnectivityExpandedSurfaceKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                objc_setAssociatedObject(roundButton, kCCAConnectivityExpandedGridGlyphKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                for (UIView *glyph in CCACompactGlyphHosts(roundButton)) glyph.transform = CGAffineTransformIdentity;
            }
        }
        UIView *expand = [controller.view viewWithTag:kCCAConnectivityExpandButtonTag];
        UIView *vpn = [controller.view viewWithTag:kCCAConnectivityMiniClusterTag];
        UIView *airDropProxy = [controller.view viewWithTag:kCCAConnectivityCompactAirDropTag];
        UIView *bluetoothProxy = [controller.view viewWithTag:kCCAConnectivityCompactBluetoothTag];
        expand.hidden = YES;
        vpn.hidden = YES;
        airDropProxy.hidden = YES;
        bluetoothProxy.hidden = YES;
    }];
}

static void CCARestoreConnectivityContainerMaterial(UIView *root) {
    UIView *container = root.superview;
    while (container && ![NSStringFromClass(container.class) isEqualToString:@"CCUIContentModuleContentContainerView"]) container = container.superview;
    if (!container) return;
    for (UIView *child in container.subviews) {
        NSString *name = NSStringFromClass(child.class);
        if ([name containsString:@"Material"] || [child isKindOfClass:[UIVisualEffectView class]]) {
            child.hidden = NO;
            child.alpha = 1.0;
        }
    }
}

static void CCARestoreSuppressedMaterialsInTree(UIView *root) {
    if (!root) return;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:root];
    while (queue.count) {
        UIView *candidate = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([objc_getAssociatedObject(candidate, kCCAConnectivitySuppressedSurfaceKey) boolValue]) {
            objc_setAssociatedObject(candidate, kCCAConnectivitySuppressedSurfaceKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            candidate.hidden = NO;
            candidate.alpha = 1.0;
            candidate.layer.opacity = 1.0;
        }
        [queue addObjectsFromArray:candidate.subviews];
    }
}

// Watchdog: the connectivity expansion choreography (snapshot window, hidden
// live platter, suppressed materials) assumes the six-card platter completes
// its reveal. Detail expansions that merely route THROUGH the connectivity
// module (the Wi-Fi list) can strand that state, which then hides every later
// platter until respring. Reset everything whenever no expansion is open.
static void CCAResetConnectivityExpansionState(UIViewController *overlay) {
    gCCAConnectivityExpansionActive = NO;
    gCCAConnectivityProxyExpansionActive = NO;
    gCCAConnectivityClosingTransitionActive = NO;
    gCCAConnectivityClosingFinishScheduled = NO;
    gCCAConnectivitySnapshotCaptureActive = NO;
    gCCAConnectivityClosingTransitionDeadline = 0.0;
    gCCAConnectivityTransitionController = nil;
    gCCAConnectivityTransitionPresentationController = nil;
    gCCAConnectivityProxySourceView = nil;
    gCCAConnectivityProxySourceWindowFrame = CGRectZero;
    gCCAConnectivityProxySourceCornerRadius = 32.0;
    gCCAConnectivityHasProxySourceFrame = NO;
    gCCAConnectivityPendingDetailIdentifier = nil;
    gCCAConnectivityTransitionGeneration++;
    if (gCCAConnectivityTransitionSurface) {
        [gCCAConnectivityTransitionSurface removeFromSuperview];
        gCCAConnectivityTransitionSurface = nil;
    }
    if (gCCAConnectivityTransitionHost) {
        [gCCAConnectivityTransitionHost removeFromSuperview];
        gCCAConnectivityTransitionHost = nil;
    }
    if (gCCAConnectivityTransitionWindow) {
        gCCAConnectivityTransitionWindow.hidden = YES;
        gCCAConnectivityTransitionWindow = nil;
    }
    CCARestoreSuppressedMaterialsInTree(overlay.view);
    CCARestoreSuppressedMaterialsInTree(overlay.presentedViewController.presentationController.containerView);
}

static UIImage *CCAConnectivityControlSnapshot(UIViewController *child, CGSize targetSize) {
    if (!child.view || targetSize.width < 1.0 || targetSize.height < 1.0) return nil;
    if (![objc_getAssociatedObject(child, kCCAConnectivityProxyPreparedKey) boolValue]) {
        [child beginAppearanceTransition:YES animated:NO];
        [child endAppearanceTransition];
        objc_setAssociatedObject(child, kCCAConnectivityProxyPreparedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    BOOL childWasHidden = child.view.hidden;
    CGFloat childAlpha = child.view.alpha;
    child.view.hidden = NO;
    child.view.alpha = 1.0;
    [child.view setNeedsLayout];
    [child.view layoutIfNeeded];
    UIView *roundButton = CCAFindSubviewWithClassName(child.view, @"CCUIRoundButton");
    if (!roundButton) {
        child.view.hidden = childWasHidden;
        child.view.alpha = childAlpha;
        return nil;
    }
    CGSize sourceSize = roundButton.bounds.size;
    if (sourceSize.width < 1.0 || sourceSize.height < 1.0) sourceSize = roundButton.frame.size;
    if (sourceSize.width < 1.0 || sourceSize.height < 1.0) {
        child.view.hidden = childWasHidden;
        child.view.alpha = childAlpha;
        return nil;
    }
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.opaque = NO;
    format.scale = UIScreen.mainScreen.scale;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:targetSize format:format];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        CGContextSaveGState(context.CGContext);
        CGContextScaleCTM(context.CGContext, targetSize.width / sourceSize.width, targetSize.height / sourceSize.height);
        BOOL drawn = [roundButton drawViewHierarchyInRect:(CGRect){CGPointZero, sourceSize} afterScreenUpdates:YES];
        if (!drawn) [roundButton.layer renderInContext:context.CGContext];
        CGContextRestoreGState(context.CGContext);
    }];
    child.view.hidden = childWasHidden;
    child.view.alpha = childAlpha;
    return image;
}

static UIButton *CCAConnectivitySnapshotProxy(UIView *root, NSInteger tag, CGRect frame, UIViewController *child) {
    UIButton *proxy = (UIButton *)[root viewWithTag:tag];
    if (!proxy) {
        proxy = [UIButton buttonWithType:UIButtonTypeCustom];
        proxy.tag = tag;
        proxy.imageView.contentMode = UIViewContentModeScaleAspectFit;
        [proxy addTarget:[CCAsterCoordinator shared] action:@selector(connectivityProxyTapped:) forControlEvents:UIControlEventTouchUpInside];
        [root addSubview:proxy];
    }
    UIView *roundButton = CCAFindSubviewWithClassName(child.view, @"CCUIRoundButton");
    if ([roundButton isKindOfClass:[UIControl class]]) objc_setAssociatedObject(proxy, kCCAConnectivityForwardControlKey, roundButton, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    proxy.frame = frame;
    proxy.hidden = NO;
    proxy.clipsToBounds = NO;
    if (tag == kCCAConnectivityCompactAirDropTag) {
        CFPropertyListRef rawMode = CFPreferencesCopyAppValue(CFSTR("DiscoverableMode"), CFSTR("com.apple.sharingd"));
        NSString *mode = CFBridgingRelease(rawMode);
        BOOL receiving = mode.length && [mode rangeOfString:@"Off" options:NSCaseInsensitiveSearch].location == NSNotFound;
        proxy.backgroundColor = receiving ? [UIColor colorWithRed:0.61 green:0.14 blue:0.96 alpha:1.0]
                                          : [UIColor colorWithWhite:1.0 alpha:0.14];
        proxy.layer.cornerRadius = CGRectGetHeight(frame) * 0.5;
        proxy.layer.cornerCurve = kCACornerCurveContinuous;
        proxy.layer.masksToBounds = YES;
    }
    UIImage *snapshot = CCAConnectivityControlSnapshot(child, frame.size);
    if (snapshot) [proxy setImage:snapshot forState:UIControlStateNormal];
    if (tag == kCCAConnectivityCompactAirDropTag) {
        UIView *roundButton = CCAFindSubviewWithClassName(child.view, @"CCUIRoundButton");
        NSMutableArray<UIView *> *queue = roundButton ? [NSMutableArray arrayWithObject:roundButton] : [NSMutableArray array];
        UIImage *glyph = nil;
        while (queue.count && !glyph) {
            UIView *candidate = queue.firstObject;
            [queue removeObjectAtIndex:0];
            if ([candidate isKindOfClass:[UIImageView class]] && ((UIImageView *)candidate).image && candidate.alpha > 0.01 && !candidate.hidden) {
                glyph = ((UIImageView *)candidate).image;
                break;
            }
            [queue addObjectsFromArray:candidate.subviews];
        }
        if (glyph) {
            [proxy setImage:[glyph imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forState:UIControlStateNormal];
            proxy.tintColor = UIColor.whiteColor;
            proxy.imageView.contentMode = UIViewContentModeScaleAspectFit;
            proxy.imageView.transform = CGAffineTransformMakeScale(0.56, 0.56);
        }
    }
    return proxy;
}

typedef struct {
    CGFloat inset;
    CGFloat gap;
    CGFloat square;
    CGFloat barHeight;
    CGFloat contentHeight;
} CCAConnectivityExpandedMetrics;

typedef struct {
    CGFloat inset;
    CGFloat gap;
    CGFloat cell;
    CGRect topLeft;
    CGRect topRight;
    CGRect bottomLeft;
    CGRect bottomRight;
} CCAConnectivityCompactMetrics;

static CCAConnectivityCompactMetrics CCAConnectivityCompactMetricsForBounds(CGRect bounds) {
    CGFloat side = MIN(CGRectGetWidth(bounds), CGRectGetHeight(bounds));
    CGFloat inset = MAX(6.0, round(side * 0.103));
    CGFloat gap = MAX(4.0, round(side * 0.055));
    CGFloat cell = floor((side - inset * 2.0 - gap) * 0.5);
    CGFloat originX = round((CGRectGetWidth(bounds) - (cell * 2.0 + gap)) * 0.5);
    CGFloat originY = round((CGRectGetHeight(bounds) - (cell * 2.0 + gap)) * 0.5);
    CGRect topLeft = CGRectMake(originX, originY, cell, cell);
    CGRect topRight = CGRectMake(originX + cell + gap, originY, cell, cell);
    CGRect bottomLeft = CGRectMake(originX, originY + cell + gap, cell, cell);
    CGRect bottomRight = CGRectMake(originX + cell + gap, originY + cell + gap, cell, cell);
    return (CCAConnectivityCompactMetrics){inset, gap, cell, topLeft, topRight, bottomLeft, bottomRight};
}

static CCAConnectivityExpandedMetrics CCAConnectivityMetricsForWidth(CGFloat width) {
    // All expanded geometry is derived from the actual presentation width.
    // The ratios follow the later Control Center platter while preserving true
    // squares and equal icon inset on every supported screen size.
    CGFloat inset = MAX(12.0, round(width * 0.05));
    CGFloat gap = MAX(8.0, round(width * 0.031));
    CGFloat contentWidth = MAX(1.0, width - inset * 2.0);
    CGFloat square = floor((contentWidth - gap) * 0.5);
    CGFloat barHeight = MAX(52.0, round(square * 0.445));
    CGFloat contentHeight = inset * 2.0 + square * 2.0 + barHeight * 3.0 + gap * 4.0;
    return (CCAConnectivityExpandedMetrics){inset, gap, square, barHeight, contentHeight};
}

static BOOL CCAIsOwnedConnectivityMaterial(UIView *view) {
    if (!view) return NO;
    NSInteger tag = view.tag;
    return (tag >= kCCAConnectivityExpandedCardBaseTag && tag < kCCAConnectivityExpandedCardBaseTag + 6) ||
           tag == kCCAConnectivityExpandedVPNTag;
}

static UIView *CCAConnectivityNativeMaterialSource(UIView *root) {
    if (!root) return nil;
    UIView *container = root;
    while (container && ![NSStringFromClass(container.class) isEqualToString:@"CCUIContentModuleContentContainerView"]) {
        container = container.superview;
    }
    if (!container) container = root.superview ?: root;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:container];
    while (queue.count) {
        UIView *candidate = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if (candidate != root && !CCAIsOwnedConnectivityMaterial(candidate) &&
            [NSStringFromClass(candidate.class) isEqualToString:@"MTMaterialView"]) {
            return candidate;
        }
        if (!CCAIsOwnedConnectivityMaterial(candidate)) [queue addObjectsFromArray:candidate.subviews];
    }
    return nil;
}

static UIView *CCANewConnectivityMaterialView(UIView *root) {
    UIView *source = CCAConnectivityNativeMaterialSource(root);
    UIView *material = nil;
    if (source && [source conformsToProtocol:@protocol(NSCopying)]) {
        @try { material = [source copy]; } @catch (__unused NSException *exception) {}
    }
    if (!material && source && [source respondsToSelector:NSSelectorFromString(@"recipe")]) {
        Class materialClass = NSClassFromString(@"MTMaterialView");
        SEL factory = NSSelectorFromString(@"materialViewWithRecipe:");
        if ([materialClass respondsToSelector:factory]) {
            long long recipe = ((long long (*)(id, SEL))objc_msgSend)(source, NSSelectorFromString(@"recipe"));
            material = ((id (*)(id, SEL, long long))objc_msgSend)(materialClass, factory, recipe);
        }
    }
    if (!material) {
        UIVisualEffectView *fallback = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialDark]];
        fallback.contentView.backgroundColor = [UIColor.whiteColor colorWithAlphaComponent:0.055];
        material = fallback;
    }
    material.hidden = NO;
    material.alpha = 1.0;
    material.userInteractionEnabled = NO;
    material.backgroundColor = UIColor.clearColor;
    material.layer.cornerCurve = kCACornerCurveContinuous;
    return material;
}

static UIView *CCAConnectivityLabeledButton(UIViewController *child) {
    UIView *labeled = CCAFindSubviewWithClassName(child.view, @"CCUILabeledRoundButton");
    return labeled ?: child.view;
}

static UILabel *CCAConnectivityLabel(UIView *labeled, SEL selector) {
    if (![labeled respondsToSelector:selector]) return nil;
    id label = ((id (*)(id, SEL))objc_msgSend)(labeled, selector);
    return [label isKindOfClass:[UILabel class]] ? label : nil;
}

static void CCAApplyConnectivityCaret(UILabel *subtitle, NSString *text) {
    if (!subtitle || !text.length) return;
    UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:7.5 weight:UIImageSymbolWeightSemibold];
    UIImage *image = [[UIImage systemImageNamed:@"chevron.up.chevron.down" withConfiguration:configuration]
        imageWithTintColor:subtitle.textColor ?: [UIColor.whiteColor colorWithAlphaComponent:0.62]
        renderingMode:UIImageRenderingModeAlwaysOriginal];
    if (!image) { subtitle.text = text; return; }
    NSTextAttachment *attachment = [NSTextAttachment new];
    attachment.image = image;
    attachment.bounds = CGRectMake(0.0, -1.0, image.size.width, image.size.height);
    NSMutableAttributedString *value = [[NSMutableAttributedString alloc] initWithString:[text stringByAppendingString:@" "]
                                                                               attributes:@{NSFontAttributeName: subtitle.font,
                                                                                            NSForegroundColorAttributeName: subtitle.textColor}];
    [value appendAttributedString:[NSAttributedString attributedStringWithAttachment:attachment]];
    subtitle.attributedText = value;
}

static void CCAStyleExpandedConnectivityChild(UIViewController *child, UIView *card, CGRect frame) {
    if (!child.view || CGRectIsNull(frame)) return;
    UIView *labeled = CCAConnectivityLabeledButton(child);
    UIView *roundButton = CCAFindSubviewWithClassName(child.view, @"CCUIRoundButton");
    BOOL wide = CGRectGetHeight(frame) < CGRectGetWidth(frame) * 0.7;
    CGFloat iconSide = 38.0;
    CGFloat iconInset = wide ? round((CGRectGetHeight(frame) - iconSide) * 0.5) : 16.0;
    if (labeled != child.view) labeled.frame = child.view.bounds;
    if (roundButton) {
        roundButton.frame = CGRectMake(iconInset, iconInset, iconSide, iconSide);
        objc_setAssociatedObject(roundButton, kCCAConnectivityExpandedCardKey, card, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(roundButton, kCCAConnectivityExpandedSurfaceKey, ({
            CCAWeakViewBox *box = [CCAWeakViewBox new];
            box.view = child.view;
            box;
        }), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        // The system reuses these button instances when connectivity moves
        // between its compact and expanded controllers. Mark only the four
        // square-grid controls, and apply/reset the glyph transform at the same
        // moment as the expanded geometry so it cannot leak into compact mode.
        objc_setAssociatedObject(roundButton, kCCAConnectivityExpandedGridGlyphKey,
                                 wide ? nil : @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        for (UIView *glyph in CCACompactGlyphHosts(roundButton)) {
            glyph.transform = wide ? CGAffineTransformIdentity : CGAffineTransformMakeScale(0.86, 0.86);
        }
    }
    objc_setAssociatedObject(labeled, kCCAConnectivityExpandedCardKey, card, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UILabel *title = CCAConnectivityLabel(labeled, NSSelectorFromString(@"titleLabel"));
    UILabel *subtitle = CCAConnectivityLabel(labeled, NSSelectorFromString(@"subtitleLabel"));
    if (!title || !subtitle) {
        NSMutableArray<UILabel *> *labels = [NSMutableArray array];
        NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:labeled];
        while (queue.count) {
            UIView *candidate = queue.firstObject;
            [queue removeObjectAtIndex:0];
            if ([candidate isKindOfClass:[UILabel class]]) [labels addObject:(UILabel *)candidate];
            [queue addObjectsFromArray:candidate.subviews];
        }
        if (!title && labels.count) title = labels.firstObject;
        if (!subtitle && labels.count > 1) subtitle = labels[1];
    }
    if (subtitle) subtitle.textColor = [UIColor.whiteColor colorWithAlphaComponent:0.62];
    if (wide) {
        CGFloat labelX = iconInset * 2.0 + iconSide;
        CGFloat lineHeight = 17.0;
        CGFloat groupTop = round((CGRectGetHeight(frame) - lineHeight * 2.0) * 0.5);
        if (title) {
            title.textAlignment = NSTextAlignmentLeft;
            title.frame = CGRectMake(labelX, groupTop, CGRectGetWidth(frame) - labelX - iconInset, lineHeight);
        }
        if (subtitle) {
            subtitle.textAlignment = NSTextAlignmentLeft;
            subtitle.frame = CGRectMake(labelX, groupTop + lineHeight, CGRectGetWidth(frame) - labelX - iconInset, lineHeight);
        }
        return;
    }

    if (!title) return;

    CGFloat textX = 21.0;
    CGFloat textWidth = MAX(0.0, CGRectGetWidth(frame) - textX - 24.0);
    CGFloat lineHeight = 14.3333;
    title.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightSemibold];
    title.numberOfLines = 2;
    title.lineBreakMode = NSLineBreakByTruncatingTail;
    subtitle.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightRegular];
    subtitle.numberOfLines = 1;
    NSString *titleText = [labeled respondsToSelector:NSSelectorFromString(@"title")]
        ? ((id (*)(id, SEL))objc_msgSend)(labeled, NSSelectorFromString(@"title")) : title.text;
    NSString *subtitleText = [labeled respondsToSelector:NSSelectorFromString(@"subtitle")]
        ? ((id (*)(id, SEL))objc_msgSend)(labeled, NSSelectorFromString(@"subtitle")) : subtitle.text;
    titleText = titleText ?: @"";
    subtitleText = subtitleText ?: @"";
    CGRect measuredTitle = [titleText boundingRectWithSize:CGSizeMake(textWidth, lineHeight * 2.0)
                                                   options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                                attributes:@{NSFontAttributeName: title.font}
                                                   context:nil];
    CGFloat titleHeight = measuredTitle.size.height > lineHeight + 1.0 ? lineHeight * 2.0 : lineHeight;
    BOOL showsSubtitle = subtitleText.length > 0;
    CGFloat groupHeight = titleHeight + (showsSubtitle ? lineHeight : 0.0);
    CGFloat groupTop = CGRectGetHeight(frame) - 17.3333 - groupHeight;
    title.frame = CGRectMake(textX, groupTop, textWidth, titleHeight);
    subtitle.frame = CGRectMake(textX, groupTop + titleHeight, textWidth, lineHeight);
    subtitle.hidden = !showsSubtitle;
    title.textAlignment = NSTextAlignmentLeft;
    subtitle.textAlignment = NSTextAlignmentLeft;

    NSString *name = NSStringFromClass(child.class);
    BOOL hasSubmenu = [name containsString:@"Wifi"] || [name containsString:@"AirDrop"] || [name containsString:@"Bluetooth"];
    if (hasSubmenu && showsSubtitle) CCAApplyConnectivityCaret(subtitle, subtitleText);
    else subtitle.text = subtitleText;
}

static void CCAConfigureConnectivityLayout(UIViewController *controller) {
    if (!gEnabled || !controller.view) return;
    UIView *root = controller.view;
    NSArray<NSString *> *classes = @[
        @"CCUIConnectivityAirplaneViewController", @"CCUIConnectivityCellularDataViewController",
        @"CCUIConnectivityWifiViewController", @"CCUIConnectivityBluetoothViewController",
        @"CCUIConnectivityAirDropViewController", @"CCUIConnectivityHotspotViewController"
    ];
    NSMutableDictionary<NSString *, UIViewController *> *children = [NSMutableDictionary dictionary];
    for (NSString *name in classes) {
        UIViewController *child = CCAConnectivityChild(controller, name);
        if (child) children[name] = child;
    }
    BOOL compact = CGRectGetWidth(root.bounds) < 190.0 && CGRectGetHeight(root.bounds) < 190.0;
    UIButton *expand = (UIButton *)[root viewWithTag:kCCAConnectivityExpandButtonTag];
    UIView *miniCluster = [root viewWithTag:kCCAConnectivityMiniClusterTag];
    if (!compact) {
        CCAResetConnectivityCompactTransforms(controller);
        expand.hidden = YES;
        miniCluster.hidden = YES;
        BOOL expanded = gCCAExpandedModuleOpen && CGRectGetWidth(root.bounds) > 250.0 && CGRectGetHeight(root.bounds) > 300.0;
        UIScrollView *scroll = nil;
        for (UIView *candidate in root.subviews) if ([candidate isKindOfClass:[UIScrollView class]]) { scroll = (UIScrollView *)candidate; break; }
        for (NSInteger tag = kCCAConnectivityExpandedCardBaseTag; tag < kCCAConnectivityExpandedCardBaseTag + 6; tag++) {
            UIView *card = [root viewWithTag:tag];
            card.hidden = !expanded;
        }
        UIView *vpnCard = [root viewWithTag:kCCAConnectivityExpandedVPNTag];
        vpnCard.hidden = !expanded;
        if (expanded && scroll) {
            CGFloat width = CGRectGetWidth(root.bounds);
            CCAConnectivityExpandedMetrics metrics = CCAConnectivityMetricsForWidth(width);
            NSDictionary<NSString *, NSValue *> *frames = @{
                @"CCUIConnectivityAirplaneViewController": [NSValue valueWithCGRect:CCAExpandedConnectivityFrameForClass(@"CCUIConnectivityAirplaneViewController", root.bounds.size)],
                @"CCUIConnectivityWifiViewController": [NSValue valueWithCGRect:CCAExpandedConnectivityFrameForClass(@"CCUIConnectivityWifiViewController", root.bounds.size)],
                @"CCUIConnectivityAirDropViewController": [NSValue valueWithCGRect:CCAExpandedConnectivityFrameForClass(@"CCUIConnectivityAirDropViewController", root.bounds.size)],
                @"CCUIConnectivityCellularDataViewController": [NSValue valueWithCGRect:CCAExpandedConnectivityFrameForClass(@"CCUIConnectivityCellularDataViewController", root.bounds.size)],
                @"CCUIConnectivityBluetoothViewController": [NSValue valueWithCGRect:CCAExpandedConnectivityFrameForClass(@"CCUIConnectivityBluetoothViewController", root.bounds.size)],
                @"CCUIConnectivityHotspotViewController": [NSValue valueWithCGRect:CCAExpandedConnectivityFrameForClass(@"CCUIConnectivityHotspotViewController", root.bounds.size)],
            };
            NSArray<NSString *> *cardOrder = @[
                @"CCUIConnectivityAirplaneViewController", @"CCUIConnectivityWifiViewController",
                @"CCUIConnectivityAirDropViewController", @"CCUIConnectivityCellularDataViewController",
                @"CCUIConnectivityBluetoothViewController", @"CCUIConnectivityHotspotViewController"
            ];
            [UIView performWithoutAnimation:^{
                scroll.scrollEnabled = YES;
                scroll.frame = root.bounds;
                scroll.bounds = root.bounds;
                scroll.contentSize = CGSizeMake(width, MAX(CGRectGetHeight(root.bounds), metrics.contentHeight));
                [cardOrder enumerateObjectsUsingBlock:^(NSString *name, NSUInteger index, __unused BOOL *stop) {
                    UIViewController *child = children[name];
                    CGRect frame = [frames[name] CGRectValue];
                    if (!child) return;
                    UIView *card = [root viewWithTag:kCCAConnectivityExpandedCardBaseTag + (NSInteger)index];
                    if (!card) {
                        card = CCANewConnectivityMaterialView(root);
                        card.tag = kCCAConnectivityExpandedCardBaseTag + (NSInteger)index;
                        card.userInteractionEnabled = NO;
                        card.layer.cornerCurve = kCACornerCurveContinuous;
                        [scroll insertSubview:card atIndex:0];
                    }
                    card.hidden = NO;
                    card.frame = frame;
                    BOOL squareCard = fabs(CGRectGetWidth(frame) - CGRectGetHeight(frame)) < 2.0;
                    card.layer.cornerRadius = squareCard ? MIN(26.0, round(CGRectGetWidth(frame) * 0.17))
                                                        : MIN(22.0, round(CGRectGetHeight(frame) * 0.38));
                    card.layer.masksToBounds = YES;
                    child.view.transform = CGAffineTransformIdentity;
                    child.view.hidden = NO;
                    child.view.alpha = 1.0;
                    child.view.frame = frame;
                    CCAStyleExpandedConnectivityChild(child, card, frame);
                    [scroll bringSubviewToFront:child.view];
                }];
                UIControl *vpn = (UIControl *)[root viewWithTag:kCCAConnectivityExpandedVPNTag];
                CGRect hotspotFrame = [frames[@"CCUIConnectivityHotspotViewController"] CGRectValue];
                CGRect vpnFrame = CGRectMake(metrics.inset, CGRectGetMaxY(hotspotFrame) + metrics.gap, width - metrics.inset * 2.0, metrics.barHeight);
                if (!vpn) {
                    vpn = [[UIControl alloc] initWithFrame:vpnFrame];
                    vpn.tag = kCCAConnectivityExpandedVPNTag;
                    vpn.backgroundColor = UIColor.clearColor;
                    vpn.layer.cornerRadius = 20.0;
                    vpn.layer.cornerCurve = kCACornerCurveContinuous;
                    vpn.layer.masksToBounds = YES;
                    UIView *vpnMaterial = CCANewConnectivityMaterialView(root);
                    vpnMaterial.tag = 90;
                    vpnMaterial.frame = vpn.bounds;
                    vpnMaterial.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
                    vpnMaterial.userInteractionEnabled = NO;
                    [vpn addSubview:vpnMaterial];
                    [vpn addTarget:[CCAsterCoordinator shared] action:@selector(openVPNSettings:) forControlEvents:UIControlEventTouchUpInside];
                    UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:16.0 weight:UIImageSymbolWeightMedium];
                    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"network" withConfiguration:configuration]];
                    icon.tag = 1; icon.tintColor = [UIColor.whiteColor colorWithAlphaComponent:0.45]; icon.contentMode = UIViewContentModeCenter;
                    CGFloat iconSide = 38.0;
                    CGFloat iconInset = round((metrics.barHeight - iconSide) * 0.5);
                    icon.frame = CGRectMake(iconInset, iconInset, iconSide, iconSide); icon.backgroundColor = [UIColor.whiteColor colorWithAlphaComponent:0.08]; icon.layer.cornerRadius = iconSide * 0.5;
                    [vpn addSubview:icon];
                    CGFloat labelX = iconInset * 2.0 + iconSide;
                    CGFloat labelTop = round((metrics.barHeight - 34.0) * 0.5);
                    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(labelX, labelTop, CGRectGetWidth(vpnFrame) - labelX - iconInset, 17.0)];
                    title.text = @"VPN"; title.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold]; title.textColor = [UIColor.whiteColor colorWithAlphaComponent:0.58];
                    [vpn addSubview:title];
                    UILabel *status = [[UILabel alloc] initWithFrame:CGRectMake(labelX, labelTop + 17.0, CGRectGetWidth(vpnFrame) - labelX - iconInset, 17.0)];
                    status.text = @"Off"; status.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightRegular]; status.textColor = [UIColor.whiteColor colorWithAlphaComponent:0.38];
                    [vpn addSubview:status];
                    [scroll addSubview:vpn];
                }
                vpn.hidden = NO;
                vpn.frame = vpnFrame;
                [vpn viewWithTag:90].frame = vpn.bounds;
                [scroll bringSubviewToFront:vpn];
            }];
        }
        return;
    }

    // Expanded card backings live inside the connectivity scroll view. They
    // must be hidden explicitly when the same controller collapses back into
    // its 2x2 module; otherwise the wide/square cards remain visible behind
    // the compact controls until the controller is recreated.
    CCAResetConnectivityCompactTransforms(controller);
    for (NSInteger tag = kCCAConnectivityExpandedCardBaseTag; tag < kCCAConnectivityExpandedCardBaseTag + 6; tag++) {
        UIView *card = [root viewWithTag:tag];
        card.hidden = YES;
    }
    UIView *expandedVPN = [root viewWithTag:kCCAConnectivityExpandedVPNTag];
    expandedVPN.hidden = YES;
    CCARestoreConnectivityContainerMaterial(root);

    CCAConnectivityCompactMetrics compactMetrics = CCAConnectivityCompactMetricsForBounds(root.bounds);
    NSDictionary<NSString *, NSValue *> *largeFrames = @{
        @"CCUIConnectivityAirplaneViewController": [NSValue valueWithCGRect:compactMetrics.topLeft],
        @"CCUIConnectivityWifiViewController": [NSValue valueWithCGRect:compactMetrics.bottomLeft],
    };
    [UIView performWithoutAnimation:^{
        [largeFrames enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSValue *frameValue, __unused BOOL *stop) {
            UIView *view = children[name].view;
            view.transform = CGAffineTransformIdentity;
            view.frame = frameValue.CGRectValue;
            view.hidden = NO;
            view.alpha = 1.0;
            if (view.superview) [view.superview bringSubviewToFront:view];
        }];
        children[@"CCUIConnectivityCellularDataViewController"].view.hidden = YES;
        children[@"CCUIConnectivityHotspotViewController"].view.hidden = YES;
        children[@"CCUIConnectivityAirDropViewController"].view.hidden = YES;
        children[@"CCUIConnectivityBluetoothViewController"].view.hidden = YES;
    }];

    CGFloat naturalMiniCell = floor(compactMetrics.cell * 0.444);
    CGFloat naturalMiniGap = compactMetrics.cell - naturalMiniCell * 2.0;
    CGFloat requestedMiniGap = MAX(2.0, naturalMiniGap - 3.0);
    CGFloat miniCell = floor((compactMetrics.cell - requestedMiniGap) * 0.5);
    CGFloat miniGap = compactMetrics.cell - miniCell * 2.0;
    if (!miniCluster) {
        miniCluster = [[UIView alloc] initWithFrame:compactMetrics.bottomRight];
        miniCluster.tag = kCCAConnectivityMiniClusterTag;
        miniCluster.userInteractionEnabled = NO;
        NSArray<NSString *> *symbols = @[@"antenna.radiowaves.left.and.right", @"bluetooth", @"personalhotspot", @"network"];
        NSArray<UIColor *> *colors = @[
            [UIColor colorWithRed:0.26 green:0.66 blue:1.0 alpha:0.48],
            [UIColor colorWithRed:0.36 green:0.20 blue:1.0 alpha:1.0],
            [UIColor.whiteColor colorWithAlphaComponent:0.30],
            [UIColor.whiteColor colorWithAlphaComponent:0.30]
        ];
        for (NSUInteger index = 0; index < 4; index++) {
            CGFloat x = (index % 2) * (miniCell + miniGap), y = (index / 2) * (miniCell + miniGap);
            UIView *tile = [[UIView alloc] initWithFrame:CGRectMake(x, y, miniCell, miniCell)];
            tile.backgroundColor = [colors[index] colorWithAlphaComponent:index == 1 ? 0.85 : 0.18];
            tile.layer.cornerRadius = miniCell * 0.5;
            UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:9.0 weight:UIImageSymbolWeightSemibold];
            UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbols[index] withConfiguration:configuration]];
            icon.frame = tile.bounds; icon.contentMode = UIViewContentModeCenter; icon.tintColor = colors[index];
            [tile addSubview:icon];
            if (index == 1) tile.hidden = YES;
            [miniCluster addSubview:tile];
        }
        [root addSubview:miniCluster];
    }
    miniCluster.hidden = NO;
    miniCluster.frame = compactMetrics.bottomRight;
    [miniCluster.subviews enumerateObjectsUsingBlock:^(UIView *tile, NSUInteger index, __unused BOOL *stop) {
        CGFloat x = (index % 2) * (miniCell + miniGap), y = (index / 2) * (miniCell + miniGap);
        tile.frame = CGRectMake(x, y, miniCell, miniCell);
        tile.layer.cornerRadius = miniCell * 0.5;
        tile.subviews.firstObject.frame = tile.bounds;
    }];
    UIButton *airDropProxy = CCAConnectivitySnapshotProxy(root, kCCAConnectivityCompactAirDropTag, compactMetrics.topRight,
                                                          children[@"CCUIConnectivityAirDropViewController"]);
    CGRect bluetoothFrame = CGRectMake(CGRectGetMinX(compactMetrics.bottomRight) + miniCell + miniGap,
                                       CGRectGetMinY(compactMetrics.bottomRight), miniCell, miniCell);
    UIButton *bluetoothProxy = CCAConnectivitySnapshotProxy(root, kCCAConnectivityCompactBluetoothTag, bluetoothFrame,
                                                            children[@"CCUIConnectivityBluetoothViewController"]);
    if (![objc_getAssociatedObject(controller, kCCAConnectivityProxyRefreshScheduledKey) boolValue]) {
        objc_setAssociatedObject(controller, kCCAConnectivityProxyRefreshScheduledKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        __weak UIViewController *weakController = controller;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.55 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIViewController *strongController = weakController;
            if (!strongController) return;
            CCAConfigureConnectivityLayout(strongController);
        });
    }
    if (!expand) {
        expand = [UIButton buttonWithType:UIButtonTypeCustom];
        expand.tag = kCCAConnectivityExpandButtonTag;
        expand.accessibilityLabel = @"More Connectivity Controls";
        expand.accessibilityHint = @"Opens all connectivity controls";
        expand.isAccessibilityElement = YES;
        [expand addTarget:[CCAsterCoordinator shared] action:@selector(expandConnectivityFromMiniCluster:) forControlEvents:UIControlEventTouchUpInside];
        [root addSubview:expand];
    }
    expand.hidden = gEditModeActive;
    expand.userInteractionEnabled = !gEditModeActive;
    expand.frame = CGRectInset(compactMetrics.bottomRight, -compactMetrics.gap * 0.5, -compactMetrics.gap * 0.5);
    [root bringSubviewToFront:miniCluster];
    [root bringSubviewToFront:airDropProxy];
    [root bringSubviewToFront:bluetoothProxy];
    [root bringSubviewToFront:expand];
}

static CGRect CCAExpandedConnectivityFrameForClass(NSString *className, CGSize containerSize) {
    CCAConnectivityExpandedMetrics metrics = CCAConnectivityMetricsForWidth(containerSize.width);
    CGFloat contentWidth = containerSize.width - metrics.inset * 2.0;
    CGFloat rightX = metrics.inset + metrics.square + metrics.gap;
    CGFloat firstSquareY = metrics.inset + metrics.barHeight + metrics.gap;
    CGFloat secondSquareY = firstSquareY + metrics.square + metrics.gap;
    CGFloat hotspotY = secondSquareY + metrics.square + metrics.gap;
    if ([className isEqualToString:@"CCUIConnectivityAirplaneViewController"]) return CGRectMake(metrics.inset, metrics.inset, contentWidth, metrics.barHeight);
    if ([className isEqualToString:@"CCUIConnectivityWifiViewController"]) return CGRectMake(metrics.inset, firstSquareY, metrics.square, metrics.square);
    if ([className isEqualToString:@"CCUIConnectivityAirDropViewController"]) return CGRectMake(rightX, firstSquareY, metrics.square, metrics.square);
    if ([className isEqualToString:@"CCUIConnectivityCellularDataViewController"]) return CGRectMake(metrics.inset, secondSquareY, metrics.square, metrics.square);
    if ([className isEqualToString:@"CCUIConnectivityBluetoothViewController"]) return CGRectMake(rightX, secondSquareY, metrics.square, metrics.square);
    if ([className isEqualToString:@"CCUIConnectivityHotspotViewController"]) return CGRectMake(metrics.inset, hotspotY, contentWidth, metrics.barHeight);
    return CGRectNull;
}

static void CCAConfigureExpandedConnectivityChild(UIViewController *child) {
    if (!gEnabled || !gCCAExpandedModuleOpen || !child.view) return;
    UIViewController *parent = child.parentViewController;
    if (![NSStringFromClass(parent.class) isEqualToString:@"CCUIConnectivityModuleViewController"] || CGRectGetWidth(parent.view.bounds) < 250.0) return;
    CGRect frame = CCAExpandedConnectivityFrameForClass(NSStringFromClass(child.class), parent.view.bounds.size);
    if (CGRectIsNull(frame)) return;
    [UIView performWithoutAnimation:^{
        if (!CGRectEqualToRect(child.view.frame, frame)) child.view.frame = frame;
        NSArray<NSString *> *order = @[
            @"CCUIConnectivityAirplaneViewController", @"CCUIConnectivityWifiViewController",
            @"CCUIConnectivityAirDropViewController", @"CCUIConnectivityCellularDataViewController",
            @"CCUIConnectivityBluetoothViewController", @"CCUIConnectivityHotspotViewController"
        ];
        NSUInteger index = [order indexOfObject:NSStringFromClass(child.class)];
        UIView *card = index == NSNotFound ? nil : [parent.view viewWithTag:kCCAConnectivityExpandedCardBaseTag + (NSInteger)index];
        CCAStyleExpandedConnectivityChild(child, card, frame);
    }];
}

%hook MRUNowPlayingView

- (void)layoutSubviews {
    %orig;
    CCAConfigureNowPlayingLayout((UIView *)(id)self);
}

%end

// Per-class media layout (structure ported from CC26). Each private view
// re-lays its own children after its parent, so geometry must be reasserted
// at every level; translatesAutoresizingMaskIntoConstraints = YES keeps the
// frames from being reclaimed by autolayout.

%hook MRUNowPlayingHeaderView

- (void)layoutSubviews {
    %orig;
    UIView *view = (UIView *)(id)self;
    NSString *mode = CCAActiveMediaMode(view);
    if (!mode) return;
    // The header is kept full-bleed by CCAConfigureNowPlayingLayout, so these
    // child frames are tile coordinates. Artwork is NOT in the header on this
    // iOS — it's a sibling handled at the now-playing-view level.
    UIView *routing = CCAIvarView(self, "_routingButton");
    UIView *label = CCAIvarView(self, "_labelView");
    UIView *headerTransport = CCAIvarView(self, "_transportButton");
    if (!routing && !label) return;
    CGFloat W = CGRectGetWidth(view.bounds);
    [UIView performWithoutAnimation:^{
        view.clipsToBounds = NO;
        CGRect labelFrame, routingFrame;
        CGFloat routingSide;
        if ([mode isEqualToString:@"wide1"]) {
            routingSide = 38.0;
            routingFrame = CGRectMake(W - routingSide - 12.0, 14.5, routingSide, routingSide);
            labelFrame = CGRectMake(70.0, 18.0, 102.0, 31.0);
        } else if ([mode isEqualToString:@"wide2"]) {
            routingSide = 34.0;
            routingFrame = CGRectMake(W - routingSide - 12.0, 16.0, routingSide, routingSide);
            labelFrame = CGRectMake(150.0, 20.0, 104.0, 31.0);
        } else if ([mode isEqualToString:@"wide4"]) {
            routingSide = 38.0;
            routingFrame = CGRectMake((W - routingSide) / 2.0, 252.0, routingSide, routingSide);
            labelFrame = CGRectMake(128.0, 48.0, 150.0, 31.0);
        } else {
            routingSide = 40.0;
            routingFrame = CGRectMake(W - routingSide - 11.0, 14.0, routingSide, routingSide);
            labelFrame = CGRectMake(11.0, 62.0, W - 22.0, 34.0);
        }
        // The header's inline play/pause button overlaps our routing spot in
        // some native states; the transport strip owns playback controls.
        if (headerTransport) {
            headerTransport.hidden = YES;
            headerTransport.alpha = 0.0;
        }
        if (routing) {
            routing.translatesAutoresizingMaskIntoConstraints = YES;
            routing.frame = routingFrame;
            routing.alpha = 1.0;
            routing.hidden = NO;
            routing.backgroundColor = [UIColor colorWithWhite:0.8 alpha:0.25];
            routing.layer.cornerRadius = routingSide / 2.0;
            routing.layer.masksToBounds = YES;
            // Solid white output glyph. The shrink happens in the
            // MRUTransportButton layout hook (marked below) because the button
            // re-lays its image view after this header pass.
            routing.tintColor = UIColor.whiteColor;
            objc_setAssociatedObject(routing, kCCAMediaRouteGlyphShrinkKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            for (UIView *routingChild in routing.subviews) {
                if (![routingChild isKindOfClass:[UIImageView class]]) continue;
                UIImageView *glyph = (UIImageView *)routingChild;
                if (glyph.image && glyph.image.renderingMode != UIImageRenderingModeAlwaysTemplate) {
                    glyph.image = [glyph.image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
                }
                glyph.tintColor = UIColor.whiteColor;
            }
        }
        if (label) {
            label.translatesAutoresizingMaskIntoConstraints = YES;
            label.frame = labelFrame;
            label.alpha = 1.0;
            label.layer.opacity = 1.0;
            label.clipsToBounds = YES;
            CCAForceMediaSubviewAlphas(label);
        }
    }];
}

%end

%hook MRUNowPlayingLabelView

- (void)setAlpha:(CGFloat)alpha {
    if (CCAActiveMediaMode((UIView *)(id)self)) {
        %orig(1.0);
        ((UIView *)(id)self).layer.opacity = 1.0;
        CCAForceMediaSubviewAlphas((UIView *)(id)self);
        return;
    }
    %orig;
}

- (void)layoutSubviews {
    %orig;
    UIView *view = (UIView *)(id)self;
    NSString *mode = CCAActiveMediaMode(view);
    if (!mode) return;
    UIView *titleView = CCAIvarView(self, "_titleMarqueeView") ?: CCAIvarView(self, "_titleLabel");
    UIView *subtitleView = CCAIvarView(self, "_subtitleMarqueeView") ?: CCAIvarView(self, "_subtitleLabel");
    UIView *placeholderView = CCAIvarView(self, "_placeholderMarqueeView");
    UIView *routeLabel = CCAIvarView(self, "_routeLabel");
    if (routeLabel) routeLabel.hidden = YES;
    if (placeholderView && !placeholderView.hidden) {
        // "Not Playing" placeholder: center it in the label view's bounds.
        [UIView performWithoutAnimation:^{
            placeholderView.translatesAutoresizingMaskIntoConstraints = YES;
            placeholderView.frame = CGRectMake(0.0, (CGRectGetHeight(view.bounds) - 18.0) / 2.0, CGRectGetWidth(view.bounds), 18.0);
            placeholderView.layer.opacity = 1.0;
            CCAAdjustMediaLabelFonts(placeholderView, YES);
        }];
    }
    if (!titleView || !subtitleView) return;
    [UIView performWithoutAnimation:^{
        CGFloat W = CGRectGetWidth(view.bounds);
        CGFloat titleHeight = 16.0;
        CGFloat subtitleHeight = 14.0;
        CGFloat lineSpacing = 1.0;
        titleView.translatesAutoresizingMaskIntoConstraints = YES;
        subtitleView.translatesAutoresizingMaskIntoConstraints = YES;
        titleView.clipsToBounds = YES;
        subtitleView.clipsToBounds = YES;
        view.layer.opacity = 1.0;
        titleView.layer.opacity = 1.0;
        subtitleView.layer.opacity = 1.0;
        CCAForceMediaSubviewAlphas(titleView);
        CCAForceMediaSubviewAlphas(subtitleView);
        CGFloat totalHeight = titleHeight + lineSpacing + subtitleHeight;
        CGFloat startY = MAX(0.0, (CGRectGetHeight(view.bounds) - totalHeight) / 2.0);
        titleView.frame = CGRectMake(0.0, startY, W, titleHeight);
        subtitleView.frame = CGRectMake(0.0, startY + titleHeight + lineSpacing, W, subtitleHeight);
        CCAAdjustMediaLabelFonts(titleView, YES);
        CCAAdjustMediaLabelFonts(subtitleView, NO);
    }];
    // The system re-dims these asynchronously after layout; force once more.
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!CCAActiveMediaMode(view)) return;
        view.layer.opacity = 1.0;
        for (UIView *subview in view.subviews) {
            if (subview.hidden) continue;
            subview.layer.opacity = 1.0;
            for (UIView *inner in subview.subviews) inner.layer.opacity = 1.0;
        }
    });
}

%end

%hook MPUMarqueeView

- (void)setAlpha:(CGFloat)alpha {
    UIView *view = (UIView *)(id)self;
    if (CCAMediaAncestorOfClass(view, @"MRUNowPlayingLabelView") && CCAActiveMediaMode(view)) {
        %orig(1.0);
        view.layer.opacity = 1.0;
        CCAForceMediaSubviewAlphas(view);
        return;
    }
    %orig;
}

%end

%hook MRUTransportButton

- (void)layoutSubviews {
    %orig;
    if (![objc_getAssociatedObject(self, kCCAMediaRouteGlyphShrinkKey) boolValue]) return;
    UIView *view = (UIView *)(id)self;
    if (!CCAActiveMediaMode(view)) return;
    // CCAster's circled routing button: pull the glyph in so it doesn't crowd
    // the circle. Runs after the button's own image layout, so it sticks.
    [UIView performWithoutAnimation:^{
        for (UIView *child in view.subviews) {
            if (![child isKindOfClass:[UIImageView class]]) continue;
            UIImageView *glyph = (UIImageView *)child;
            if (glyph.hidden || !glyph.image) continue;
            glyph.contentMode = UIViewContentModeScaleAspectFit;
            glyph.frame = CGRectInset(view.bounds, 6.5, 6.5);
        }
    }];
}

%end

%hook MRUNowPlayingTransportControlsView

- (void)layoutSubviews {
    %orig;
    UIView *view = (UIView *)(id)self;
    NSString *mode = CCAActiveMediaMode(view);
    if (!mode) return;
    UIView *leftButton = CCAIvarView(self, "_leftButton");
    UIView *centerButton = CCAIvarView(self, "_centerButton");
    UIView *rightButton = CCAIvarView(self, "_rightButton");
    UIView *leadingButton = CCAIvarView(self, "_leadingButton");
    UIView *stripRouting = CCAIvarView(self, "_routingButton");
    if (!leftButton || !centerButton || !rightButton) return;
    CGFloat W = CGRectGetWidth(view.bounds);
    CGFloat centerY = CGRectGetHeight(view.bounds) / 2.0;
    [UIView performWithoutAnimation:^{
        // The header's routing button is the one CCAster styles and places;
        // the transport strip's trailing duplicate stays hidden. Same for the
        // leading (TV remote style) button.
        if (stripRouting) { stripRouting.hidden = YES; stripRouting.alpha = 0.0; }
        if (leadingButton) { leadingButton.hidden = YES; leadingButton.alpha = 0.0; }
        // The 4x1 strip only fits play + skip-forward (reference design);
        // every other mode centers the full three-button cluster.
        BOOL strip = [mode isEqualToString:@"wide1"];
        leftButton.hidden = strip;
        leftButton.alpha = strip ? 0.0 : 1.0;
        if (strip) {
            centerButton.center = CGPointMake(W * 0.22, centerY);
            rightButton.center = CGPointMake(W * 0.78, centerY);
        } else {
            CGFloat spacing = [mode isEqualToString:@"compact"] ? W * 0.32 : W * 0.28;
            centerButton.center = CGPointMake(W / 2.0, centerY);
            leftButton.center = CGPointMake(W / 2.0 - spacing, centerY);
            rightButton.center = CGPointMake(W / 2.0 + spacing, centerY);
        }
    }];
}

%end

%hook CCUIConnectivityModuleViewController

- (double)preferredExpandedContentHeight {
    if (!gEnabled) return %orig;
    CGFloat width = CGRectGetWidth(((UIViewController *)(id)self).view.bounds);
    SEL widthSelector = NSSelectorFromString(@"preferredExpandedContentWidth");
    if (width < 250.0 && [(id)self respondsToSelector:widthSelector]) width = ((double (*)(id, SEL))objc_msgSend)((id)self, widthSelector);
    if (width < 250.0) width = CGRectGetWidth(UIScreen.mainScreen.bounds) * 0.856;
    return CCAConnectivityMetricsForWidth(width).contentHeight;
}

- (void)viewDidLayoutSubviews {
    %orig;
    UIViewController *controller = (UIViewController *)(id)self;
    CCAConfigureConnectivityLayout(controller);
    // Several of the child connectivity controllers finish their own layout
    // after the parent callback. Coalesce one next-turn correction so their
    // stock frames cannot overwrite the compact cluster.
    static const void *kCCAConnectivityDeferredLayoutKey = &kCCAConnectivityDeferredLayoutKey;
    BOOL compact = CGRectGetWidth(controller.view.bounds) < 190.0 && CGRectGetHeight(controller.view.bounds) < 190.0 && !gCCAExpandedModuleOpen;
    if (compact && ![objc_getAssociatedObject(controller, kCCAConnectivityDeferredLayoutKey) boolValue]) {
        objc_setAssociatedObject(controller, kCCAConnectivityDeferredLayoutKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        __weak UIViewController *weakController = controller;
        dispatch_async(dispatch_get_main_queue(), ^{
            UIViewController *strongController = weakController;
            if (!strongController) return;
            objc_setAssociatedObject(strongController, kCCAConnectivityDeferredLayoutKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            CCAConfigureConnectivityLayout(strongController);
        });
    }
}

%end

%hook CCUIContentModuleContainerViewController

- (BOOL)clickPresentationInteractionShouldBegin:(id)interaction {
    if (gEnabled && (gEditModeActive || gCCAEditTransitionActive)) return NO;
    CCAApplyExpansionPageGeometrySync(gOverlayControllers.allObjects.firstObject);
    return %orig;
}

- (id)clickPresentationInteraction:(id)interaction previewForHighlightingAtLocation:(CGPoint)location {
    if (gEnabled && (gEditModeActive || gCCAEditTransitionActive)) {
        CCADiscardExpansionCompactTransitionAssets();
        return nil;
    }
    CCAApplyExpansionPageGeometrySync(gOverlayControllers.allObjects.firstObject);
    CCAResetGenericExpansionDismissal();
    UIView *sourceView = ((UIViewController *)(id)self).view;
    NSString *sourceIdentifier = CCAModuleIdentifier((UIViewController *)(id)self);
    if (CCAExpansionIdentifierUsesLiveTransition(sourceIdentifier) ||
        CCAViewTreeContainsLiveExpansionContent(sourceView)) {
        CCADiscardExpansionCompactTransitionAssets();
        return %orig;
    }
    UIView *sourceSuperview = sourceView.superview;
    [sourceView layoutIfNeeded];
    CCADiscardExpansionCompactTransitionAssets();
    UIWindow *sourceWindow = sourceView.window;
    gCCAExpansionTransitionWindow = sourceWindow;
    gCCAExpansionCompactDestinationWindowFrame = sourceWindow
        ? [sourceView convertRect:sourceView.bounds toView:sourceWindow]
        : CGRectZero;
    UIView *sourceMaterial = CCAFirstModuleMaterialSurface(sourceView);
    gCCAExpansionCompactMaterialTemplate = CCANewConnectivityMaterialView(sourceView);
    BOOL materialHidden = sourceMaterial.hidden;
    CGFloat materialAlpha = sourceMaterial.alpha;
    float materialLayerOpacity = sourceMaterial.layer.opacity;
    [UIView performWithoutAnimation:^{
        sourceMaterial.hidden = YES;
        sourceMaterial.alpha = 0.0;
        sourceMaterial.layer.opacity = 0.0;
    }];
    UIView *foregroundSnapshot = CCACompositedSnapshotView(sourceView);
    if ([foregroundSnapshot isKindOfClass:[UIImageView class]]) {
        gCCAExpansionCompactForegroundImage = ((UIImageView *)foregroundSnapshot).image;
    }
    [UIView performWithoutAnimation:^{
        sourceMaterial.hidden = materialHidden;
        sourceMaterial.alpha = materialAlpha;
        sourceMaterial.layer.opacity = materialLayerOpacity;
    }];
    UIView *snapshot = sourceSuperview ? CCAWindowCropSnapshotView(sourceView) : nil;
    if (!snapshot && sourceSuperview) snapshot = CCACompositedSnapshotView(sourceView);
    if (snapshot) {
        CCADiscardExpansionSourceSnapshot();
        CCADiscardExpansionDismissalSnapshot();
        snapshot.frame = sourceView.frame;
        snapshot.userInteractionEnabled = NO;
        UIView *material = CCAFirstModuleMaterialSurface(sourceView);
        CGFloat compactRadius = sourceView.layer.cornerRadius;
        if (compactRadius <= 1.0) compactRadius = material.layer.cornerRadius;
        if (compactRadius <= 1.0) compactRadius = 32.0;
        snapshot.layer.cornerRadius = compactRadius;
        snapshot.layer.cornerCurve = kCACornerCurveContinuous;
        snapshot.layer.masksToBounds = YES;
        [sourceSuperview insertSubview:snapshot aboveSubview:sourceView];
        gCCAExpansionSourceSnapshot = snapshot;
        if ([snapshot isKindOfClass:[UIImageView class]]) {
            gCCAExpansionCompactImage = ((UIImageView *)snapshot).image;
        }
        gCCAExpansionCompactCornerRadius = snapshot.layer.cornerRadius;
    }
    UITargetedPreview *nativePreview = %orig;
    if (!snapshot || !nativePreview) return nativePreview;
    return [[UITargetedPreview alloc] initWithView:snapshot
                                        parameters:nativePreview.parameters
                                            target:nativePreview.target];
}

- (void)clickPresentationInteractionEnded:(id)interaction wasCancelled:(BOOL)cancelled {
    %orig;
    if (cancelled) CCADiscardExpansionSourceSnapshot();
}

- (UIViewController *)presentedViewControllerForContentModuleDetailClickPresentationInteractionController:(id)interactionController {
    if (gEnabled && (gEditModeActive || gCCAEditTransitionActive)) return nil;
    NSString *identifier = CCAModuleIdentifier((UIViewController *)(id)self);
    if (gEnabled && [identifier.lowercaseString containsString:@"ccaster.connectivity"] &&
        CCAConnectivityIdentifierHasExpandedMenu(identifier)) {
        UIViewController *detail = CCAConnectivityDetailViewControllerForIdentifier(identifier, interactionController);
        if (detail) return detail;
    }
    return %orig;
}

- (double)preferredExpandedContentHeight {
    UIViewController *controller = (UIViewController *)(id)self;
    UIViewController *connectivity = CCAConnectivityChild(controller, @"CCUIConnectivityModuleViewController");
    if (!gEnabled || !connectivity) return %orig;
    CGFloat width = CGRectGetWidth(connectivity.view.bounds);
    SEL widthSelector = NSSelectorFromString(@"preferredExpandedContentWidth");
    if (width < 250.0 && [(id)connectivity respondsToSelector:widthSelector]) width = ((double (*)(id, SEL))objc_msgSend)((id)connectivity, widthSelector);
    if (width < 250.0) width = CGRectGetWidth(UIScreen.mainScreen.bounds) * 0.856;
    return CCAConnectivityMetricsForWidth(width).contentHeight;
}

%end

%hook CCUILabeledRoundButton

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *view = (UIView *)(id)self;
    if (gEnabled && gCCAExpandedModuleOpen && objc_getAssociatedObject(view, kCCAConnectivityExpandedCardKey) &&
        !view.hidden && view.alpha > 0.01 && CGRectContainsPoint(view.bounds, point)) {
        SEL selector = NSSelectorFromString(@"buttonView");
        UIView *button = [view respondsToSelector:selector] ? ((id (*)(id, SEL))objc_msgSend)(view, selector) : nil;
        if (button) return button;
    }
    return %orig;
}

- (void)layoutSubviews {
    %orig;
    UIResponder *responder = ((UIView *)(id)self).nextResponder;
    while (responder && ![responder isKindOfClass:[UIViewController class]]) responder = responder.nextResponder;
    if ([responder isKindOfClass:[UIViewController class]]) CCAConfigureExpandedConnectivityChild((UIViewController *)responder);
}

%end

%hook CCUIRoundButton

- (void)layoutSubviews {
    %orig;
    UIView *button = (UIView *)(id)self;
    if (!gEnabled || !gCCAExpandedModuleOpen ||
        ![objc_getAssociatedObject(button, kCCAConnectivityExpandedGridGlyphKey) boolValue]) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (UIView *glyph in CCACompactGlyphHosts(button)) glyph.transform = CGAffineTransformMakeScale(0.86, 0.86);
    [CATransaction commit];
}

- (void)setHighlighted:(BOOL)highlighted {
    %orig;
    UIView *button = (UIView *)(id)self;
    UIView *card = objc_getAssociatedObject(button, kCCAConnectivityExpandedCardKey);
    UIView *surface = ((CCAWeakViewBox *)objc_getAssociatedObject(button, kCCAConnectivityExpandedSurfaceKey)).view;
    if (!gEnabled || !gCCAExpandedModuleOpen || !card || !surface) return;
    [UIView animateWithDuration:highlighted ? 0.12 : 0.28
                          delay:0.0
         usingSpringWithDamping:highlighted ? 1.0 : 0.72
          initialSpringVelocity:0.0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        surface.transform = highlighted ? CGAffineTransformMakeScale(0.985, 0.985) : CGAffineTransformIdentity;
        card.alpha = highlighted ? 0.82 : 1.0;
    } completion:nil];
}

%end

%hook AXCCIconImageView

- (void)layoutSubviews {
    %orig;
    if (!gEnabled) return;
    UIView *view = (UIView *)(id)self;
    UIViewController *module = CCAModuleControllerForView(view);
    NSString *identifier = CCAModuleIdentifier(module);
    if (![identifier isEqualToString:@"com.apple.accessibility.controlcenter.text.size"]) return;
    NSArray<NSNumber *> *customSize = gCCACustomSizes[identifier];
    if (customSize.count < 2 || (customSize[0].unsignedIntegerValue <= 1 && customSize[1].unsignedIntegerValue <= 1)) return;
    [UIView performWithoutAnimation:^{
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        view.layer.transform = CATransform3DIdentity;
        view.frame = CGRectMake(0.0, 0.0, kCCAGridCellSize, kCCAGridCellSize);
        if ([view isKindOfClass:[UIImageView class]]) ((UIImageView *)view).contentMode = UIViewContentModeCenter;
        [CATransaction commit];
    }];
}

%end

%hook UIActivityIndicatorView

- (void)layoutSubviews {
    %orig;
    if (!gEnabled) return;
    UIView *view = (UIView *)(id)self;
    UIViewController *module = CCAModuleControllerForView(view);
    NSString *identifier = CCAModuleIdentifier(module);
    if (![identifier isEqualToString:@"com.mtac.ccpowermenu"]) return;
    NSArray<NSNumber *> *customSize = gCCACustomSizes[identifier];
    if (customSize.count < 2 || (customSize[0].unsignedIntegerValue <= 1 && customSize[1].unsignedIntegerValue <= 1)) return;
    view.hidden = YES;
    view.alpha = 0.0;
}

%end

%hook CCUIBaseSliderView

- (void)setValue:(float)value {
    %orig;
    if (gEnabled) CCAUpdateSliderGlyphColor((UIView *)(id)self, value, YES);
}

- (void)layoutSubviews {
    %orig;
    if (!gEnabled) return;
    float value = ((float (*)(id, SEL))objc_msgSend)((id)self, @selector(value));
    CCAUpdateSliderGlyphColor((UIView *)(id)self, value, NO);
}

- (void)_setActiveGlyphView:(id)view {
    %orig;
    if (!gEnabled) return;
    float value = ((float (*)(id, SEL))objc_msgSend)((id)self, @selector(value));
    CCAUpdateSliderGlyphColor((UIView *)(id)self, value, NO);
}

- (void)_applyGlyphState:(id)state performConfiguration:(BOOL)configuration {
    %orig;
    if (!gEnabled) return;
    float value = ((float (*)(id, SEL))objc_msgSend)((id)self, @selector(value));
    CCAUpdateSliderGlyphColor((UIView *)(id)self, value, NO);
}

- (void)setGlyphVisible:(BOOL)visible {
    %orig;
    if (!gEnabled) return;
    float value = ((float (*)(id, SEL))objc_msgSend)((id)self, @selector(value));
    CCAUpdateSliderGlyphColor((UIView *)(id)self, value, NO);
}

%end

%hook CCUIContinuousSliderView

- (void)_handleValueChangeGestureRecognizer:(UIPanGestureRecognizer *)gesture {
    %orig;
    CCAUpdateSliderOverscroll((UIView *)(id)self, gesture);
}

%end

%hook CCUICAPackageView

- (void)layoutSubviews {
    %orig;
    UIView *packageView = (UIView *)(id)self;
    UIView *buttonView = packageView;
    while (buttonView && ![NSStringFromClass(buttonView.class) isEqualToString:@"CCUIButtonModuleView"]) buttonView = buttonView.superview;
    // The glyph is invariant while the resize border follows the finger. Do
    // not let package layout reposition nested artwork during the preview.
    BOOL keepsLeadingAnchor = [buttonView viewWithTag:kCCAResizePresentationTag] || [objc_getAssociatedObject(buttonView, kCCAResizePreviewKey) boolValue];
    if (!buttonView || !keepsLeadingAnchor) return;
    if (CGRectGetWidth(packageView.bounds) <= 80.0 && CGRectGetHeight(packageView.bounds) <= 80.0 && packageView.superview) {
        [UIView performWithoutAnimation:^{
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            if (gCCAResizeInProgress) {
                [packageView.layer removeAnimationForKey:@"position"];
                [packageView.layer removeAnimationForKey:@"bounds"];
                [packageView.layer removeAnimationForKey:@"transform"];
            }
            packageView.layer.transform = CATransform3DIdentity;
            packageView.center = [buttonView convertPoint:CGPointMake(kCCAGridCellSize * 0.5, kCCAGridCellSize * 0.5) toView:packageView.superview];
            if (gCCAResizeInProgress) {
                [packageView.layer removeAnimationForKey:@"position"];
                [packageView.layer removeAnimationForKey:@"bounds"];
                [packageView.layer removeAnimationForKey:@"transform"];
            }
            [CATransaction commit];
        }];
    }
    for (UIView *content in packageView.subviews) {
        if (CGRectGetWidth(content.bounds) <= 60.0 && CGRectGetHeight(content.bounds) <= 60.0) {
            // Pin by visual center rather than intrinsic artwork size. Shortcut
            // modules such as Calculator use a smaller, nested package glyph;
            // a fixed origin therefore did not line up with Timer/toggles.
            [UIView performWithoutAnimation:^{
                [CATransaction begin];
                [CATransaction setDisableActions:YES];
                if (gCCAResizeInProgress) {
                    // UIKit lays out the package again during the native size
                    // transition. Remove only geometric interpolation so the
                    // package's own symbol/state animation remains available.
                    [content.layer removeAnimationForKey:@"position"];
                    [content.layer removeAnimationForKey:@"bounds"];
                    [content.layer removeAnimationForKey:@"transform"];
                }
                content.layer.transform = CATransform3DIdentity;
                content.center = [buttonView convertPoint:CGPointMake(kCCAGridCellSize * 0.5, kCCAGridCellSize * 0.5) toView:packageView];
                if (gCCAResizeInProgress) {
                    [content.layer removeAnimationForKey:@"position"];
                    [content.layer removeAnimationForKey:@"bounds"];
                    [content.layer removeAnimationForKey:@"transform"];
                }
                [CATransaction commit];
            }];
        }
    }
}

%end

%hook CCUIButtonModuleView

- (void)setSelected:(BOOL)selected {
    %orig;
    UIResponder *responder = (UIResponder *)(id)self;
    UIViewController *module = nil;
    while (responder) {
        if ([responder isKindOfClass:[UIViewController class]] && CCAIsModuleController((UIViewController *)responder)) {
            module = (UIViewController *)responder;
            break;
        }
        responder = responder.nextResponder;
    }
    if (module) {
        dispatch_async(dispatch_get_main_queue(), ^{ [[CCAsterCoordinator shared] applyResizedPresentationToModule:module]; });
    }
}

- (void)layoutSubviews {
    %orig;
    // resizePanned: applies the presentation exactly when the logical size
    // crosses a valid endpoint. Re-entering it for every intermediate layout
    // pass produces duplicate fades and visible flashing.
    UIResponder *responder = (UIResponder *)(id)self;
    UIViewController *module = nil;
    while (responder) {
        if ([responder isKindOfClass:[UIViewController class]] && CCAIsModuleController((UIViewController *)responder)) {
            module = (UIViewController *)responder;
            break;
        }
        responder = responder.nextResponder;
    }
    if (module) [[CCAsterCoordinator shared] applyResizedPresentationToModule:module];
}

%end

%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (gEnabled && CCAIsOverlayController(self)) [[CCAsterCoordinator shared] installOnOverlay:self];
}

- (void)viewDidLayoutSubviews {
    %orig;
    if (gEnabled && CCAIsOverlayController(self) && gCCAControlCenterPresented) {
        // Provider-driven rebuilds replace the header pocket at unpredictable
        // times; the overlay always lays out afterwards, so this is the one
        // reliable spot to put the quick-access host back.
        CCAsterCoordinator *coordinator = [CCAsterCoordinator shared];
        [coordinator installQuickAccessHostOnOverlay:self];
        BOOL hasPageIndicators = [self.view viewWithTag:kCCAPageIndicatorHostTag] != nil;
        BOOL hasPager = NO;
        for (UIGestureRecognizer *gesture in self.view.gestureRecognizers) {
            if ([objc_getAssociatedObject(gesture, kCCAPagerGestureKey) boolValue]) {
                hasPager = YES;
                break;
            }
        }
        // installPagingOnOverlay performs a complete grid normalization and
        // presentation reconcile. Re-running it for every native presentation
        // layout pass restarts compositor work at the end of open/close.
        if (!hasPageIndicators || !hasPager) {
            [coordinator installPagingOnOverlay:self];
        }
        CCASuppressNativeOverflowMaterialForOverlay(self);
        CCASuppressHeaderPocketMaterialForOverlay(self);
        __weak UIViewController *weakOverlay = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIViewController *overlay = weakOverlay;
            if (overlay && gCCAControlCenterPresented) {
                CCASuppressNativeOverflowMaterialForOverlay(overlay);
                CCASuppressHeaderPocketMaterialForOverlay(overlay);
            }
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.18 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIViewController *overlay = weakOverlay;
            if (overlay && gCCAControlCenterPresented) {
                CCASuppressNativeOverflowMaterialForOverlay(overlay);
                CCASuppressHeaderPocketMaterialForOverlay(overlay);
            }
        });
    }
    BOOL settledControlCenterState = gCCAControlCenterPresentationState == 0 ||
        gCCAControlCenterPresentationState == 2;
    BOOL presentationLayerSettling =
        CACurrentMediaTime() - gCCAControlCenterPresentationStateChangedTime < 0.18;
    if (gEnabled && CCAIsOverlayController(self) && !gEditModeActive &&
        ((settledControlCenterState && !presentationLayerSettling) ||
         CCAInteractivePagingGeometryActive())) {
        [[CCAsterCoordinator shared] applyRestingModuleOffsetToOverlay:self];
    }
    if (CCAIsModuleController(self) && !CCAIsOwnedDuplicateModuleController(self)) {
        CCAsterCoordinator *coordinator = [CCAsterCoordinator shared];
        [coordinator applyRefinedLookToModule:self];
        if (!gCCAExpandedModuleOpen) [coordinator applyTransitionRadiusToModule:self];
        if (gEditModeActive) {
            [coordinator applyEditingToModule:self editing:YES];
            UIViewController *overlay = gOverlayControllers.allObjects.firstObject;
            if (overlay) [coordinator setNativeDismissTapGesturesEnabled:NO forOverlay:overlay];
        }
    }
    // Connectivity's leaf controllers are reparented and laid out separately
    // by the stock expansion animator. Keep every live leaf suppressed while
    // our atomic pane snapshots own the transition; otherwise UIKit can expose
    // labels and glyphs outside their card backgrounds for a single frame.
    if (gEnabled && gCCAConnectivityTransitionWindow && gCCAConnectivityExpansionActive &&
        !gCCAConnectivitySnapshotCaptureActive && CCAIsConnectivityTransitionLeafController(self)) {
        [UIView performWithoutAnimation:^{
            CCAStopConnectivitySubviewAnimations(self.view, YES);
            self.view.hidden = YES;
            self.view.alpha = 0.0;
            self.view.layer.opacity = 0.0;
        }];
    }
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    if (CCAIsOverlayController(self)) {
        if (gEditModeActive) {
            [[CCAsterCoordinator shared] dismissEditingImmediately];
        } else if (gEnabled) {
            // Insurance: if a raced exit left edit presentation half-applied
            // (offset wrappers, borders, grids), scrub it while CC is away so
            // the next open and module expansions start from clean geometry.
            [[CCAsterCoordinator shared] setEditPresentation:NO forOverlay:self animated:NO];
        }
    }
}

%end

%hook SBUIPowerDownViewController

- (void)powerDownViewRequestCancel:(id)view {
    %orig;
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    if (self.presentingViewController) [self dismissViewControllerAnimated:NO completion:nil];
}

%end

%hook CCUIControlCenterPositionProvider

- (void)regenerateRectsWithOrderedIdentifiers:(NSArray *)identifiers orderedSizes:(NSArray *)sizes {
    gCCAProviderOrder = [identifiers copy];
    NSMutableDictionary *sizeMap = [NSMutableDictionary dictionary];
    for (NSUInteger index = 0; index < MIN(identifiers.count, sizes.count); index++) sizeMap[identifiers[index]] = sizes[index];
    gCCAProviderSizes = [sizeMap copy];
    %orig;
}

%end

%group CCAPresentationStateCallbacks

%hook SBControlCenterController

// Two-stage exit while editing: the first home button press (or home gesture
// dismissal request on notched devices) leaves edit mode and keeps Control
// Center presented; only the next one actually dismisses. Both funnel through
// these seams, and tapping anywhere else can no longer end editing.
- (BOOL)handleHomeButtonPress {
    if (gEnabled && gCCAControlCenterPresented && !gCCAExpandedModuleOpen) {
        if (gEditModeActive) {
            CCAHaptic();
            gCCAEditExitConsumedUntil = CACurrentMediaTime() + 0.9;
            [[CCAsterCoordinator shared] dismissEditingImmediately];
            return YES;
        }
        if (CACurrentMediaTime() < gCCAEditExitConsumedUntil) return YES;
    }
    return %orig;
}

- (void)dismissAnimated:(BOOL)animated {
    if (gEnabled && gCCAControlCenterPresented && !gCCAExpandedModuleOpen) {
        if (gEditModeActive) {
            CCAHaptic();
            gCCAEditExitConsumedUntil = CACurrentMediaTime() + 0.9;
            // Atomic, non-animated exit: the in-flight home gesture keeps
            // driving presentation callbacks that would strand an animated
            // exit halfway (stuck edit chrome, later expansion glitches).
            [[CCAsterCoordinator shared] dismissEditingImmediately];
            return;
        }
        if (CACurrentMediaTime() < gCCAEditExitConsumedUntil) return;
	    }
    UIViewController *overlay = gOverlayControllers.allObjects.firstObject;
    if (gEnabled && overlay && !gCCAExpandedModuleOpen) {
        gCCAOwnedDuplicateHostSyncPresented = NO;
        [[CCAsterCoordinator shared] beginOwnedDuplicateHostPresentationSync];
        [[CCAsterCoordinator shared] animateOwnedDuplicateHostForOverlay:overlay presented:NO];
    }
    %orig;
}

- (void)_handleStatusBarPullDownGesture:(id)gesture {
    gCCASBControlCenterController = self;
    if (![gesture isKindOfClass:[UIPanGestureRecognizer class]]) {
        %orig;
        return;
    }
    // Once the touch reaches the pager, the coordinator force-finishes the
    // native reveal and owns the remaining drag. Letting SpringBoard continue
    // its interactive stretch would overwrite our scale on every callback.
    BOOL pagerOwnsGesture = gPagingEnabled && (gCCAPresentationNativeSettlePending || gCCAPresentationPageHandoffActive);
    if (!pagerOwnsGesture) %orig;
    UIViewController *overlay = nil;
    @try {
        id candidate = [(id)self valueForKey:@"viewController"];
        if ([candidate isKindOfClass:[UIViewController class]]) {
            overlay = CCAFindOverlayController((UIViewController *)candidate);
        }
    } @catch (__unused NSException *exception) {}
    if (!overlay) overlay = gOverlayControllers.allObjects.firstObject;
    if (overlay && CCAInteractivePagingGeometryActive()) {
        [[CCAsterCoordinator shared] applyPageTransformToOverlay:overlay animated:NO];
    }
    if (gPagingEnabled) {
        [[CCAsterCoordinator shared] trackControlCenterPresentationGesture:(UIPanGestureRecognizer *)gesture overlay:overlay controller:self];
    }
    [[CCAsterCoordinator shared] beginOwnedDuplicateHostPresentationSync];
}

- (void)controlCenterViewController:(id)controller significantPresentationProgressChange:(double)progress {
    gCCASBControlCenterController = self;
    %orig;
    UIViewController *overlay = [controller isKindOfClass:[UIViewController class]] ? (UIViewController *)controller : gOverlayControllers.allObjects.firstObject;
    CGFloat clamped = MIN(1.0, MAX(0.0, (CGFloat)progress));
    if (overlay && CCAInteractivePagingGeometryActive()) {
        [[CCAsterCoordinator shared] applyPageTransformToOverlay:overlay animated:NO];
    }
    // A presentation dip mid-drag is a second-finger page (or an incidental
    // native callback), not an intent to leave edit mode with a module in hand.
    if (gEnabled && gEditModeActive && !gCCAExpandedModuleOpen && !gCCADragInProgress && clamped < 0.985) {
        CCAHaptic();
        gCCAEditExitConsumedUntil = CACurrentMediaTime() + 1.1;
        [[CCAsterCoordinator shared] dismissEditingImmediately];
        return;
    }
    if (gEditModeActive && !gCCAAddSheetPresentationActive && ![overlay.presentedViewController isKindOfClass:[CCAAddControlSheetViewController class]]) {
        [[CCAsterCoordinator shared] updateEditingChromeForPresentationProgress:clamped overlay:overlay];
    }
    [[CCAsterCoordinator shared] updateTopFadeForOverlay:overlay presentationAlpha:clamped];
    if (clamped > 0.001 && clamped < 0.999) {
        [[CCAsterCoordinator shared] updateOwnedDuplicateHostForOverlay:overlay presentationAlpha:clamped];
    } else {
        [[CCAsterCoordinator shared] animateOwnedDuplicateHostForOverlay:overlay presented:clamped >= 0.999];
    }
    [[CCAsterCoordinator shared] beginOwnedDuplicateHostPresentationSync];
    UIView *host = [overlay.view viewWithTag:181000];
    UIView *pageIndicators = [overlay.view viewWithTag:kCCAPageIndicatorHostTag];
    if (gPagingEnabled && pageIndicators && !gCCAExpandedModuleOpen && gCCAPageCount > 1) {
        pageIndicators.hidden = clamped <= 0.001;
        pageIndicators.alpha = clamped;
    }
    if (!host || gCCAExpandedModuleOpen || gEditModeActive || !gEnabled || !gQuickAccessButtonsEnabled) return;
    // Presentation state remains nonzero throughout dismissal. Follow the
    // actual interactive progress so this chrome leaves with Control Center.
    [host.layer removeAllAnimations];
    objc_setAssociatedObject(host, kCCAQuickAccessAnimationTokenKey, [NSObject new], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    host.hidden = clamped <= 0.001;
    host.alpha = clamped;
    host.transform = CGAffineTransformMakeTranslation(0.0, -12.0 * (1.0 - clamped));
}

- (void)controlCenterViewController:(id)controller didChangePresentationState:(NSUInteger)state {
    gCCASBControlCenterController = self;
    if (gCCAControlCenterPresentationState != state) {
        gCCAControlCenterPresentationStateChangedTime = CACurrentMediaTime();
    }
    NSUInteger chromeGeneration = ++gCCAPresentationChromeGeneration;
    gCCAControlCenterPresentationState = state;
    if (gEnabled && !gCCAExpandedModuleOpen) {
        if (state == 3 && gEditModeActive && !gCCADragInProgress) {
            CCAHaptic();
            gCCAEditExitConsumedUntil = CACurrentMediaTime() + 1.2;
            [[CCAsterCoordinator shared] dismissEditingImmediately];
            gCCAControlCenterPresented = YES;
            return;
        }
    }
    // SpringBoard's own -[SBControlCenterController _willPresent] is reached
    // through this %orig. If our paged layout ever hands it an inconsistent
    // state it throws, and an uncaught throw here takes down SpringBoard (the
    // observed crash). Contain it: a single bad presentation is downgraded to a
    // cosmetic glitch, the exception reason is recorded for field diagnosis, and
    // the layout is re-sanitised so the following present starts clean.
    @try {
        %orig;
    } @catch (NSException *presentationException) {
        dispatch_async(dispatch_get_main_queue(), ^{
            UIViewController *recoveryOverlay = gOverlayControllers.allObjects.firstObject;
            if (recoveryOverlay) [[CCAsterCoordinator shared] normalizePagedLayoutForOverlay:recoveryOverlay];
        });
    }
    gCCAControlCenterPresented = state != 0;
    [[CCAsterCoordinator shared] beginOwnedDuplicateHostPresentationSync];

    if (state == 0) {
        gCCAAddSheetPresentationActive = NO;
        gCCAPresentationNativeSettlePending = NO;
        gCCAPresentationReleasedWhileSettling = NO;
        gCCAPresentationPageHandoffActive = NO;
        gCCAPresentationHandoffArmed = NO;
        gCCAPresentationPanGesture = nil;
        gCCAPresentationController = nil;
        [gCCAPresentationPanDisplayLink invalidate];
        gCCAPresentationPanDisplayLink = nil;
        [gCCAPresentationPanDiscoveryDisplayLink invalidate];
        gCCAPresentationPanDiscoveryDisplayLink = nil;
        gCCAPresentationPanDiscoveryOverlay = nil;
        gCCAPresentationPanDiscoveryController = nil;
    }
    UIViewController *overlay = nil;
    if ([controller isKindOfClass:[UIViewController class]]) overlay = CCAFindOverlayController((UIViewController *)controller);
    if (!overlay) overlay = gOverlayControllers.allObjects.firstObject;
    if (overlay) {
        if (state != 0) {
            if (gPagingEnabled && !gCCAPresentationPanGesture) {
                [[CCAsterCoordinator shared] beginPresentationPanDiscoveryForOverlay:overlay controller:self];
            }
            UIPanGestureRecognizer *presentationPan = gCCAPresentationPanGesture;
            BOOL livePresentationPull = presentationPan && presentationPan.numberOfTouches > 0 &&
                (presentationPan.state == UIGestureRecognizerStateBegan || presentationPan.state == UIGestureRecognizerStateChanged);
            // didChangePresentationState can arrive in the middle of the
            // opening pull. Resetting these flags here used to cancel a valid
            // handoff based on callback timing, producing the intermittent
            // "works after manually scrubbing" behavior.
            if (!livePresentationPull && !gCCAPresentationNativeSettlePending && !gCCAPresentationPageHandoffActive) {
                gCCAPresentationReleasedWhileSettling = NO;
                gCCAPresentationHandoffArmed = NO;
                gCCAPresentationPendingProgress = (CGFloat)gCCACurrentPage;
                gCCAPresentationPendingTouchY = kCCAPageIndicatorScrubStep * ((CGFloat)gCCACurrentPage + 0.5);
                [gCCAPresentationPanDisplayLink invalidate];
                gCCAPresentationPanDisplayLink = nil;
            }
        }
        if (state == 0 && gPagingEnabled && gCCAPageCount > 1) {
            // A Control Center presentation is a fresh paging session. Reset
            // while the overlay is offscreen so the next pull always starts
            // on page one, matching iOS 18 and avoiding a pull-to-scrub
            // handoff inheriting the previous session's page transform.
            gCCAPagerTransitionActive = NO;
            gCCAPagerInteractiveTranslation = 0.0;
            gCCAPagerInteractiveProgress = 0.0;
            gCCAPagerInteractiveStartPage = 0;
            gCCAPagerInteractiveBeganTime = 0.0;
            gCCAPagerScrubbingActive = NO;
            BOOL needsPageReset = gCCACurrentPage != 0 ||
                fabs(gCCAPagerInteractiveTranslation) > 0.01;
            if (needsPageReset) {
                __weak UIViewController *weakOverlay = overlay;
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.18 * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                    if (gCCAControlCenterPresentationState != 0) return;
                    UIViewController *settledOverlay = weakOverlay;
                    if (settledOverlay) {
                        [[CCAsterCoordinator shared] setCurrentPage:0
                                                         forOverlay:settledOverlay
                                                           animated:NO];
                    }
                });
            }
        }
        UIView *hitBridge = [overlay.view viewWithTag:kCCAExtendedHitBridgeTag];
        if (state != 0 && hitBridge) [overlay.view bringSubviewToFront:hitBridge];
        BOOL hideQuickAccess = state == 0 || gCCAExpandedModuleOpen || gEditModeActive;
        [[CCAsterCoordinator shared] setQuickAccessButtonsHidden:hideQuickAccess forOverlay:overlay animated:state != 0];
        [[CCAsterCoordinator shared] updateTopFadeForOverlay:overlay presentationAlpha:state == 0 ? 0.0 : 1.0];
        [[CCAsterCoordinator shared] animateOwnedDuplicateHostForOverlay:overlay presented:state != 0];
        if (state != 0 && !gCCAExpandedModuleOpen) {
            // The source presentation layers already exist when this callback
            // returns. Copy them now so the first committed duplicate frame
            // cannot flash at its resting transform before the display link
            // begins following the native animation.
            [[CCAsterCoordinator shared] layoutOwnedDuplicateModulesForOverlay:overlay];
            [[CCAsterCoordinator shared] updateOwnedDuplicateHostForOverlay:overlay presentationAlpha:1.0];
        }
        if (gEditModeActive) {
            CGFloat chromeProgress = state == 0 ? 0.0 : 1.0;
            if (state == 0) {
                [UIView animateWithDuration:0.16 delay:0.0 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState animations:^{
                    [[CCAsterCoordinator shared] updateEditingChromeForPresentationProgress:chromeProgress overlay:overlay];
                } completion:nil];
            } else {
                [[CCAsterCoordinator shared] updateEditingChromeForPresentationProgress:chromeProgress overlay:overlay];
            }
        }
        UIView *pageIndicators = [overlay.view viewWithTag:kCCAPageIndicatorHostTag];
        if (pageIndicators) {
            [pageIndicators.layer removeAllAnimations];
            [UIView performWithoutAnimation:^{
                BOOL indicatorsVisible = gPagingEnabled && gCCAPageCount > 1 && state != 0 &&
                    (!gCCAExpandedModuleOpen || CCAExpandedChromeRevealActive());
                pageIndicators.hidden = !indicatorsVisible;
                pageIndicators.alpha = indicatorsVisible ? 1.0 : 0.0;
            }];
        }
        if (state == 0 || state == 2) {
            __weak UIViewController *weakOverlay = overlay;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.20 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                if (chromeGeneration != gCCAPresentationChromeGeneration ||
                    gCCAControlCenterPresentationState != state) return;
                UIViewController *settledOverlay = weakOverlay;
                if (settledOverlay) {
                    [[CCAsterCoordinator shared] updatePageIndicatorsForOverlay:settledOverlay];
                }
            });
            if (state == 2) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.38 * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                    if (chromeGeneration != gCCAPresentationChromeGeneration ||
                        gCCAControlCenterPresentationState != 2) return;
                    UIViewController *settledOverlay = weakOverlay;
                    if (settledOverlay) CCARefreshSettledCompactMediaSnapshot(settledOverlay);
                });
            }
        }
        if (state != 0 && gEditModeActive) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.08 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [[CCAsterCoordinator shared] updateEditControlFramesForOverlay:overlay];
            });
        }
    }
    // CCUI presentation state zero is fully dismissed.  The modular overlay
    // remains in SpringBoard's view hierarchy, so UIViewController appearance
    // callbacks are not reliable enough to remove overlay-hosted edit chrome.
    if (state == 0 && gEditModeActive) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.18 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (gEditModeActive) [[CCAsterCoordinator shared] dismissEditingImmediately];
        });
    }
    if (state == 0) {
        CCAResetGenericExpansionDismissal();
        CCADiscardExpansionCompactTransitionAssets();
    }
}

%end

%end

%group CCAExpandedModuleClickAssistant

%hook _UIClickPresentationAssistant

- (void)presentFromSourcePreview:(id)sourcePreview lifecycleCompletion:(id)completion {
    CCAApplyExpansionPageGeometrySync(gOverlayControllers.allObjects.firstObject);
    %orig;
}

- (void)_animatePresentation {
    CCAApplyExpansionPageGeometrySync(gOverlayControllers.allObjects.firstObject);
    %orig;
    UIView *snapshot = gCCAExpansionSourceSnapshot;
    UIViewPropertyAnimator *animator = CCAExpansionPropertyAnimator(self);
    if (snapshot && animator) {
        [animator addAnimations:^{ snapshot.alpha = 0.0; } delayFactor:0.18];
        [animator addCompletion:^(__unused UIViewAnimatingPosition finalPosition) {
            if (gCCAExpansionSourceSnapshot == snapshot) CCADiscardExpansionSourceSnapshot();
        }];
    }
}

- (void)_didTransitionToPresented {
    %orig;
    CCADiscardExpansionSourceSnapshot();
}

- (void)_animateDismissalIsInterruption:(BOOL)interruption {
    UIViewController *overlay = gOverlayControllers.allObjects.firstObject;
    UIViewController *presented = overlay.presentedViewController;
    BOOL usesGenericTransition = !CCAUsesSpecializedExpansionTransition(presented);
    NSUInteger transitionGeneration = 0;
    if (usesGenericTransition) {
        CCAResetGenericExpansionDismissal();
        transitionGeneration = gCCAExpansionDismissalGeneration;
        CCAFreezeExpandedModuleForDismissal(presented);
        CCAInstallExpansionDismissalSnapshot(self);
    }
    CCAReassertExpansionPageGeometry(overlay);
    %orig;
    UIViewPropertyAnimator *animator = CCAExpansionPropertyAnimator(self);
    UIView *expandedSnapshot = gCCAExpansionExpandedSnapshot;
    UIView *compactSnapshot = gCCAExpansionDismissalSnapshot;
    UIView *foregroundSnapshot = gCCAExpansionDismissalForegroundSnapshot;
    CGPoint compactCenter = CGPointMake(CGRectGetMidX(gCCAExpansionCompactDestinationWindowFrame),
                                        CGRectGetMidY(gCCAExpansionCompactDestinationWindowFrame));
    if (usesGenericTransition && expandedSnapshot && animator) {
        [animator addAnimations:^{
            expandedSnapshot.alpha = 0.0;
            compactSnapshot.alpha = 1.0;
            compactSnapshot.frame = gCCAExpansionCompactDestinationWindowFrame;
            compactSnapshot.layer.cornerRadius = gCCAExpansionCompactCornerRadius;
            foregroundSnapshot.alpha = 1.0;
            foregroundSnapshot.center = compactCenter;
        }];
    }
    CCAHoldExpansionPageGeometryDuringDismissal(overlay);
    if (usesGenericTransition && animator) {
        [animator addCompletion:^(UIViewAnimatingPosition finalPosition) {
            if (transitionGeneration != gCCAExpansionDismissalGeneration) return;
            gCCAExpansionDismissalAnimatorFinished = YES;
            if (finalPosition != UIViewAnimatingPositionEnd) {
                gCCAExpansionDismissalDidClose = YES;
            }
            CCACompleteGenericExpansionDismissalIfReady();
        }];
    } else if (usesGenericTransition) {
        [UIView animateWithDuration:0.2 animations:^{
            expandedSnapshot.alpha = 0.0;
            compactSnapshot.alpha = 1.0;
            compactSnapshot.frame = gCCAExpansionCompactDestinationWindowFrame;
            compactSnapshot.layer.cornerRadius = gCCAExpansionCompactCornerRadius;
            foregroundSnapshot.alpha = 1.0;
            foregroundSnapshot.center = compactCenter;
        } completion:^(__unused BOOL finished) {
            if (transitionGeneration != gCCAExpansionDismissalGeneration) return;
            gCCAExpansionDismissalAnimatorFinished = YES;
            CCACompleteGenericExpansionDismissalIfReady();
        }];
    }
}

- (void)_postInteractionCleanup {
    %orig;
    CCADiscardExpansionSourceSnapshot();
}

%end

%end

%group CCAExpandedPlatterRadius

static BOOL CCAIsConnectivityExpandedController(UIViewController *controller) {
    if (!controller) return [gCCAExpandedModuleIdentifier isEqualToString:@"com.apple.control-center.ConnectivityModule"];
    if ([NSStringFromClass(controller.class) isEqualToString:@"CCUIConnectivityModuleViewController"]) return YES;
    UIViewController *connectivity = CCAConnectivityChild(controller, @"CCUIConnectivityModuleViewController");
    if (connectivity) return YES;
    return NO;
}

static void CCASuppressConnectivityOuterMaterial(UIPresentationController *presentationController) {
    UIViewController *presentedController = presentationController.presentedViewController;
    if (!CCAIsConnectivityExpandedController(presentedController)) return;
    UIView *presentedView = presentationController.presentedView;
    UIView *contentView = presentedController.view;
    presentedView.backgroundColor = UIColor.clearColor;
    contentView.backgroundColor = UIColor.clearColor;
    UIView *containerView = presentationController.containerView;
    NSMutableArray<UIView *> *queue = [NSMutableArray array];
    if (containerView) [queue addObject:containerView];
    else if (presentedView) [queue addObject:presentedView];
    while (queue.count) {
        UIView *candidate = queue.firstObject;
        [queue removeObjectAtIndex:0];
        NSString *name = NSStringFromClass(candidate.class);
        BOOL effectSurface = [candidate isKindOfClass:[UIVisualEffectView class]] || [name containsString:@"Material"] || [name containsString:@"Backdrop"];
        CGRect converted = candidate.superview ? [candidate.superview convertRect:candidate.frame toView:presentedView] : candidate.bounds;
        BOOL platterSized = fabs(CGRectGetWidth(converted) - CGRectGetWidth(presentedView.bounds)) <= 8.0 &&
                            fabs(CGRectGetHeight(converted) - CGRectGetHeight(presentedView.bounds)) <= 8.0;
        BOOL belongsToCustomContent = candidate == contentView || [candidate isDescendantOfView:contentView];
        // Our six cards are deliberately smaller than the presentation host;
        // only the stock full-platter material is suppressed.
        if (effectSurface && platterSized && !belongsToCustomContent && !objc_getAssociatedObject(candidate, kCCAConnectivitySuppressedSurfaceKey)) {
            objc_setAssociatedObject(candidate, kCCAConnectivitySuppressedSurfaceKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            candidate.alpha = 0.0;
        }
        [queue addObjectsFromArray:candidate.subviews];
    }
}

static BOOL CCAConnectivityViewLivesInsideCustomCard(UIView *view, UIView *container) {
    for (UIView *ancestor = view; ancestor && ancestor != container; ancestor = ancestor.superview) {
        NSInteger tag = ancestor.tag;
        if ((tag >= kCCAConnectivityExpandedCardBaseTag && tag < kCCAConnectivityExpandedCardBaseTag + 6) ||
            tag == kCCAConnectivityExpandedVPNTag) return YES;
    }
    return NO;
}

static void CCASuppressConnectivityStockContainerMaterial(UIView *contentContainer) {
    if (!contentContainer) return;
    CGFloat containerWidth = CGRectGetWidth(contentContainer.bounds);
    CGFloat containerHeight = CGRectGetHeight(contentContainer.bounds);
    if (containerWidth < 1.0 || containerHeight < 1.0) return;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithArray:contentContainer.subviews];
    while (queue.count) {
        UIView *candidate = queue.firstObject;
        [queue removeObjectAtIndex:0];
        NSString *name = NSStringFromClass(candidate.class);
        BOOL material = [candidate isKindOfClass:[UIVisualEffectView class]] ||
                        [name containsString:@"Material"] || [name containsString:@"Backdrop"];
        if (material && !CCAConnectivityViewLivesInsideCustomCard(candidate, contentContainer)) {
            CGRect frame = [candidate convertRect:candidate.bounds toView:contentContainer];
            // The stock platter backing is the only material that occupies most
            // of the presentation container. During UIKit's reparenting pass it
            // briefly takes on crossed/stretched geometry, so suppress it by
            // coverage rather than by a device-specific frame or class name.
            BOOL outerBacking = CGRectGetWidth(frame) >= containerWidth * 0.68 &&
                                CGRectGetHeight(frame) >= containerHeight * 0.68;
            if (outerBacking) {
                objc_setAssociatedObject(candidate, kCCAConnectivitySuppressedSurfaceKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                [candidate.layer removeAllAnimations];
                candidate.hidden = YES;
                candidate.alpha = 0.0;
                candidate.layer.opacity = 0.0;
            }
        }
        [queue addObjectsFromArray:candidate.subviews];
    }
}

static void CCAConfigureConnectivityPresentationContainer(UIPresentationController *presentationController) {
    if (!gEnabled || !gCCAConnectivityExpansionActive || !presentationController.presentedViewController.view) return;
    UIView *presentedRoot = presentationController.presentedViewController.view;
    BOOL transitionOwnsVisibility = gCCAConnectivityTransitionHost != nil &&
        gCCAConnectivityExpansionActive && !gCCAConnectivityClosingTransitionActive &&
        !gCCAConnectivitySnapshotCaptureActive;
    if (transitionOwnsVisibility) {
        // Suppressing only the connectivity child is too late: Apple's detail
        // presentation briefly draws duplicated labels and toggles in wrapper
        // views while it reparents them. Keep the entire presented pane out of
        // the render tree until our settled composite is ready.
        UIView *presentedSurface = presentationController.presentedView;
        [UIView performWithoutAnimation:^{
            [presentedSurface.layer removeAllAnimations];
            presentedSurface.hidden = YES;
            presentedSurface.alpha = 0.0;
            presentedSurface.layer.opacity = 0.0;
        }];
    }
    UIView *contentContainer = CCAFindSubviewWithClassName(presentedRoot, @"CCUIContentModuleContentContainerView");
    if (!contentContainer) return;
    CCASuppressConnectivityStockContainerMaterial(contentContainer);
    CGFloat width = CGRectGetWidth(contentContainer.bounds);
    if (width < 250.0) width = CGRectGetWidth(contentContainer.frame);
    if (width < 250.0) return;
    CCAConnectivityExpandedMetrics metrics = CCAConnectivityMetricsForWidth(width);
    UIEdgeInsets safeInsets = presentedRoot.window.safeAreaInsets;
    CGFloat availableHeight = CGRectGetHeight(presentedRoot.bounds) - safeInsets.top - safeInsets.bottom - 32.0;
    CGFloat height = MIN(metrics.contentHeight, availableHeight);
    // UIKit's iOS 16 detail presentation is shorter than our rebuilt platter.
    // Remove clipping from the presentation chain before changing the content
    // frame, otherwise the first committed frame briefly cuts the VPN/bottom
    // bar off at the stock expanded height.
    presentationController.containerView.clipsToBounds = NO;
    presentationController.containerView.layer.masksToBounds = NO;
    for (UIView *ancestor = contentContainer; ancestor; ancestor = ancestor.superview) {
        ancestor.clipsToBounds = NO;
        ancestor.layer.masksToBounds = NO;
        if (ancestor == presentedRoot || ancestor == presentationController.containerView) break;
    }
    CGRect frame = contentContainer.frame;
    frame.size = CGSizeMake(width, height);
    frame.origin.x = round((CGRectGetWidth(presentedRoot.bounds) - width) * 0.5);
    frame.origin.y = round((CGRectGetHeight(presentedRoot.bounds) - height) * 0.5);
    contentContainer.frame = frame;
    contentContainer.bounds = CGRectMake(0.0, 0.0, width, height);
    contentContainer.clipsToBounds = NO;
    for (UIView *child in contentContainer.subviews) {
        NSString *name = NSStringFromClass(child.class);
        if ([name containsString:@"Material"] || [child isKindOfClass:[UIVisualEffectView class]]) {
            child.hidden = YES;
            child.alpha = 0.0;
        } else {
            child.frame = contentContainer.bounds;
            child.bounds = contentContainer.bounds;
        }
    }
    UIViewController *connectivity = CCAConnectivityChild(presentationController.presentedViewController, @"CCUIConnectivityModuleViewController");
    if ([NSStringFromClass(presentationController.presentedViewController.class) isEqualToString:@"CCUIConnectivityModuleViewController"]) {
        connectivity = presentationController.presentedViewController;
    }
    if (connectivity) {
        if (connectivity.view == gCCAConnectivityDetachedLiveView) {
            // During the opening blend the real content is deliberately
            // hosted at final screen coordinates. Do not let a presentation
            // layout pass put it back into content-container coordinates.
            return;
        }
        if (transitionOwnsVisibility) {
            // The expanded presentation may own a different connectivity
            // controller than the compact module. Hide this instance before
            // UIKit gets a chance to animate any of its children onscreen.
            [connectivity.view.layer removeAnimationForKey:@"opacity"];
            connectivity.view.layer.opacity = 0.0;
            connectivity.view.alpha = 0.0;
            connectivity.view.hidden = YES;
        }
        connectivity.view.frame = contentContainer.bounds;
        connectivity.view.bounds = contentContainer.bounds;
        CCAConfigureConnectivityLayout(connectivity);
        [connectivity.view setNeedsLayout];
        [connectivity.view layoutIfNeeded];
        // Child labeled buttons finish their own layout after the parent.  A
        // final explicit pass ensures the transition snapshot never captures
        // the blank/intermediate card geometry used by UIKit's animator.
        CCAConfigureConnectivityLayout(connectivity);
        if (transitionOwnsVisibility) {
            [connectivity.view.layer removeAnimationForKey:@"opacity"];
            connectivity.view.layer.opacity = 0.0;
            connectivity.view.alpha = 0.0;
            connectivity.view.hidden = YES;
        }
    }
    // A late native layout can recreate or resize the stock material after the
    // first suppression pass. Reassert after the final connectivity layout.
    CCASuppressConnectivityStockContainerMaterial(contentContainer);
}

static UIView *CCAConnectivityStaticSnapshot(UIView *view, BOOL afterScreenUpdates) {
    if (!view || CGRectGetWidth(view.bounds) < 1.0 || CGRectGetHeight(view.bounds) < 1.0) return nil;
    // This must be a true still image. snapshotViewAfterScreenUpdates: keeps a
    // live replica of the source layers; connectivity reparents those layers
    // during expansion, which made the frozen compact module mutate into the
    // expanded card geometry. Compact and settled-closing content has already
    // rendered. Compact content uses a no-flush bitmap so it cannot mutate
    // during UIKit's reparenting; the already-settled expanded hierarchy uses
    // a flush so MTMaterial/backdrop layers are included in the bitmap.
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.opaque = NO;
    format.scale = UIScreen.mainScreen.scale;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:view.bounds.size format:format];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        BOOL drawn = [view drawViewHierarchyInRect:(CGRect){CGPointZero, view.bounds.size}
                                afterScreenUpdates:afterScreenUpdates];
        if (!drawn) [view.layer renderInContext:context.CGContext];
    }];
    UIImageView *snapshot = [[UIImageView alloc] initWithImage:image];
    snapshot.contentMode = UIViewContentModeScaleToFill;
    snapshot.userInteractionEnabled = NO;
    return snapshot;
}

static void CCAStopConnectivitySubviewAnimations(UIView *view, BOOL includeRoot) {
    if (!view) return;
    if (includeRoot) [view.layer removeAllAnimations];
    for (UIView *subview in view.subviews) {
        [subview.layer removeAllAnimations];
        CCAStopConnectivitySubviewAnimations(subview, NO);
    }
}

static BOOL CCAIsConnectivityTransitionLeafController(UIViewController *controller) {
    NSString *name = NSStringFromClass(controller.class);
    return [name isEqualToString:@"CCUIConnectivityAirplaneViewController"] ||
           [name isEqualToString:@"CCUIConnectivityCellularDataViewController"] ||
           [name isEqualToString:@"CCUIConnectivityWifiViewController"] ||
           [name isEqualToString:@"CCUIConnectivityBluetoothViewController"] ||
           [name isEqualToString:@"CCUIConnectivityAirDropViewController"] ||
           [name isEqualToString:@"CCUIConnectivityHotspotViewController"];
}

static void CCASuppressConnectivityLiveChildren(UIViewController *controller) {
    if (!controller) return;
    NSMutableArray<UIViewController *> *queue = [NSMutableArray arrayWithArray:controller.childViewControllers];
    while (queue.count) {
        UIViewController *child = queue.firstObject;
        [queue removeObjectAtIndex:0];
        [queue addObjectsFromArray:child.childViewControllers];
        if (!CCAIsConnectivityTransitionLeafController(child)) continue;
        [UIView performWithoutAnimation:^{
            CCAStopConnectivitySubviewAnimations(child.view, YES);
            child.view.hidden = YES;
            child.view.alpha = 0.0;
            child.view.layer.opacity = 0.0;
        }];
    }
}

static void CCARestoreConnectivityDetachedLiveView(void) {
    UIView *view = gCCAConnectivityDetachedLiveView;
    UIView *superview = gCCAConnectivityDetachedOriginalSuperview;
    if (view && superview) {
        [UIView performWithoutAnimation:^{
            [view removeFromSuperview];
            view.layer.mask = nil;
            view.transform = CGAffineTransformIdentity;
            NSUInteger index = gCCAConnectivityDetachedOriginalIndex;
            if (index == NSNotFound || index > superview.subviews.count) index = superview.subviews.count;
            [superview insertSubview:view atIndex:index];
            view.frame = gCCAConnectivityDetachedOriginalFrame;
            view.bounds = gCCAConnectivityDetachedOriginalBounds;
        }];
    }
    gCCAConnectivityDetachedLiveView = nil;
    gCCAConnectivityDetachedOriginalSuperview = nil;
    gCCAConnectivityDetachedOriginalFrame = CGRectZero;
    gCCAConnectivityDetachedOriginalBounds = CGRectZero;
    gCCAConnectivityDetachedOriginalIndex = NSNotFound;
}

static void CCARemoveConnectivityTransitionVisuals(BOOL restoreLiveView) {
    [gCCAConnectivityTransitionHost.layer removeAllAnimations];
    [gCCAConnectivityCompactTransitionSnapshot.layer removeAllAnimations];
    [gCCAConnectivityExpandedTransitionSnapshot.layer removeAllAnimations];
    [gCCAConnectivityTransitionSurface.layer removeAllAnimations];
    CCARestoreConnectivityDetachedLiveView();
    [gCCAConnectivityTransitionHost removeFromSuperview];
    gCCAConnectivityTransitionHost = nil;
    gCCAConnectivityTransitionWindow.hidden = YES;
    gCCAConnectivityTransitionWindow.rootViewController = nil;
    gCCAConnectivityTransitionWindow = nil;
    gCCAConnectivityCompactTransitionSnapshot = nil;
    gCCAConnectivityExpandedTransitionSnapshot = nil;
    gCCAConnectivityTransitionSurface = nil;
    gCCAConnectivityOpeningRevealStarted = NO;
    gCCAConnectivityClosingTransitionActive = NO;
    gCCAConnectivityClosingFinishScheduled = NO;
    gCCAConnectivityClosingTransitionDeadline = 0.0;
    gCCAConnectivitySnapshotCaptureActive = NO;
    UIView *presentedSurface = gCCAConnectivityTransitionPresentationController.presentedView;
    if (restoreLiveView) {
        [UIView performWithoutAnimation:^{
            presentedSurface.hidden = NO;
            presentedSurface.alpha = 1.0;
            presentedSurface.layer.opacity = 1.0;
            if (gCCAConnectivityTransitionController.view) {
                gCCAConnectivityTransitionController.view.hidden = NO;
                gCCAConnectivityTransitionController.view.alpha = 1.0;
                gCCAConnectivityTransitionController.view.layer.opacity = 1.0;
            }
        }];
    }
    gCCAConnectivityTransitionPresentationController = nil;
}

static UIView *CCAConnectivityTransitionHostForWindow(UIWindow *window) {
    if (!window) return nil;
    // UIKit may move the expanded platter into a temporary window and destroy
    // that window before our closing animation completes. Use a short-lived,
    // noninteractive compositor window above both hierarchies so one atomic
    // transition survives the complete open/close handoff.
    if (gCCAConnectivityTransitionHost.superview) {
        gCCAConnectivityTransitionWindow.windowLevel = MAX(gCCAConnectivityTransitionWindow.windowLevel,
                                                            window.windowLevel + 100.0);
        gCCAConnectivityTransitionWindow.hidden = NO;
    } else {
        UIWindow *transitionWindow = nil;
        if (@available(iOS 13.0, *)) {
            if (window.windowScene) transitionWindow = [[UIWindow alloc] initWithWindowScene:window.windowScene];
        }
        if (!transitionWindow) transitionWindow = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
        transitionWindow.frame = UIScreen.mainScreen.bounds;
        transitionWindow.backgroundColor = UIColor.clearColor;
        transitionWindow.opaque = NO;
        transitionWindow.userInteractionEnabled = NO;
        transitionWindow.windowLevel = MAX(UIWindowLevelAlert + 100.0, window.windowLevel + 100.0);
        UIViewController *root = [UIViewController new];
        root.view.frame = transitionWindow.bounds;
        root.view.backgroundColor = UIColor.clearColor;
        root.view.opaque = NO;
        root.view.userInteractionEnabled = NO;
        root.view.clipsToBounds = NO;
        transitionWindow.rootViewController = root;
        transitionWindow.hidden = NO;
        gCCAConnectivityTransitionWindow = transitionWindow;
        gCCAConnectivityTransitionHost = root.view;
    }
    return gCCAConnectivityTransitionHost;
}

static CGRect CCAConnectivityScreenFrameForView(UIView *view) {
    if (!view.window) return CGRectNull;
    CGRect windowFrame = [view convertRect:view.bounds toView:view.window];
    return [view.window convertRect:windowFrame toCoordinateSpace:UIScreen.mainScreen.coordinateSpace];
}

static CGRect CCAConnectivityHostFrameForScreenRect(UIView *host, CGRect screenRect) {
    if (!host || CGRectIsNull(screenRect)) return CGRectNull;
    return [host convertRect:screenRect fromCoordinateSpace:UIScreen.mainScreen.coordinateSpace];
}

static UIImage *CCAConnectivityWindowImage(UIWindow *window) {
    if (!window || CGRectGetWidth(window.bounds) < 1.0 || CGRectGetHeight(window.bounds) < 1.0) return nil;
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.opaque = NO;
    format.scale = UIScreen.mainScreen.scale;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:window.bounds.size format:format];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        CGContextSaveGState(context.CGContext);
        CGContextTranslateCTM(context.CGContext, -CGRectGetMinX(window.bounds), -CGRectGetMinY(window.bounds));
        BOOL drawn = [window drawViewHierarchyInRect:window.bounds afterScreenUpdates:YES];
        if (!drawn) [window.layer renderInContext:context.CGContext];
        CGContextRestoreGState(context.CGContext);
    }];
}

static UIImage *CCAConnectivityCropImage(UIImage *image, CGRect rect) {
    if (!image.CGImage || CGRectGetWidth(rect) < 1.0 || CGRectGetHeight(rect) < 1.0) return nil;
    CGFloat scale = image.scale;
    CGRect pixels = CGRectMake(round(CGRectGetMinX(rect) * scale), round(CGRectGetMinY(rect) * scale),
                               round(CGRectGetWidth(rect) * scale), round(CGRectGetHeight(rect) * scale));
    CGRect imagePixels = CGRectMake(0.0, 0.0, CGImageGetWidth(image.CGImage), CGImageGetHeight(image.CGImage));
    pixels = CGRectIntersection(pixels, imagePixels);
    if (CGRectIsNull(pixels) || CGRectGetWidth(pixels) < 1.0 || CGRectGetHeight(pixels) < 1.0) return nil;
    CGImageRef cropped = CGImageCreateWithImageInRect(image.CGImage, pixels);
    if (!cropped) return nil;
    UIImage *result = [UIImage imageWithCGImage:cropped scale:scale orientation:UIImageOrientationUp];
    CGImageRelease(cropped);
    return result;
}

static UIView *CCAConnectivityExpandedCompositeSnapshot(UIViewController *controller, UIView *host) {
    if (!controller.view.window || !host) return nil;
    UIWindow *window = controller.view.window;
    UIImage *windowImage = CCAConnectivityWindowImage(window);
    if (!windowImage) return nil;

    NSMutableArray<UIView *> *cards = [NSMutableArray array];
    for (NSInteger tag = kCCAConnectivityExpandedCardBaseTag; tag < kCCAConnectivityExpandedCardBaseTag + 6; tag++) {
        UIView *card = [controller.view viewWithTag:tag];
        if (card && !card.hidden && card.alpha > 0.01) [cards addObject:card];
    }
    UIView *vpn = [controller.view viewWithTag:kCCAConnectivityExpandedVPNTag];
    if (vpn && !vpn.hidden && vpn.alpha > 0.01) [cards addObject:vpn];
    if (!cards.count) return nil;

    CGRect unionScreenFrame = CGRectNull;
    NSMutableArray<NSValue *> *screenFrames = [NSMutableArray arrayWithCapacity:cards.count];
    for (UIView *card in cards) {
        CGRect screenFrame = CCAConnectivityScreenFrameForView(card);
        [screenFrames addObject:[NSValue valueWithCGRect:screenFrame]];
        unionScreenFrame = CGRectIsNull(unionScreenFrame) ? screenFrame : CGRectUnion(unionScreenFrame, screenFrame);
    }
    if (CGRectIsNull(unionScreenFrame)) return nil;

    UIView *composite = [[UIView alloc] initWithFrame:CCAConnectivityHostFrameForScreenRect(host, unionScreenFrame)];
    composite.backgroundColor = UIColor.clearColor;
    composite.opaque = NO;
    composite.userInteractionEnabled = NO;
    composite.clipsToBounds = NO;

    [cards enumerateObjectsUsingBlock:^(UIView *card, NSUInteger index, __unused BOOL *stop) {
        CGRect screenFrame = screenFrames[index].CGRectValue;
        CGRect windowFrame = [card convertRect:card.bounds toView:window];
        UIImage *cardImage = CCAConnectivityCropImage(windowImage, windowFrame);
        if (!cardImage) return;
        CGRect relativeFrame = CGRectOffset(screenFrame, -CGRectGetMinX(unionScreenFrame), -CGRectGetMinY(unionScreenFrame));
        UIImageView *cardSnapshot = [[UIImageView alloc] initWithImage:cardImage];
        cardSnapshot.frame = relativeFrame;
        cardSnapshot.contentMode = UIViewContentModeScaleToFill;
        cardSnapshot.layer.cornerRadius = card.layer.cornerRadius;
        cardSnapshot.layer.cornerCurve = kCACornerCurveContinuous;
        cardSnapshot.layer.masksToBounds = YES;
        [composite addSubview:cardSnapshot];
    }];
    return composite.subviews.count ? composite : nil;
}

static NSTimeInterval CCAConnectivityTransitionDuration(UIViewController *controller) {
    id<UIViewControllerTransitionCoordinator> coordinator = controller.transitionCoordinator;
    NSTimeInterval duration = coordinator ? coordinator.transitionDuration : 0.36;
    return MIN(0.46, MAX(0.30, duration));
}

static void CCARestoreConnectivityPresentedSurface(UIPresentationController *presentationController, UIViewController *controller) {
    UIView *presentedSurface = presentationController.presentedView;
    [UIView performWithoutAnimation:^{
        presentedSurface.hidden = NO;
        presentedSurface.alpha = 1.0;
        presentedSurface.layer.opacity = 1.0;
        controller.view.hidden = NO;
        controller.view.alpha = 1.0;
        controller.view.layer.opacity = 1.0;
        controller.view.transform = CGAffineTransformIdentity;
        CCAConfigureConnectivityLayout(controller);
        [controller.view setNeedsLayout];
        [controller.view layoutIfNeeded];
        CCAConfigureConnectivityLayout(controller);
    }];
}

static void CCABeginConnectivityOpeningTransition(UIViewController *controller) {
    if (!controller.view.window || CGRectGetWidth(controller.view.bounds) < 1.0) return;
    CCARemoveConnectivityTransitionVisuals(YES);
    gCCAConnectivityTransitionGeneration++;
    gCCAConnectivityTransitionController = controller;
    gCCAConnectivityCompactController = controller;
    UIWindow *window = controller.view.window;
    // Remember the persistent Control Center window. The expanded platter can
    // be moved to a short-lived presentation window; hosting the return there
    // made the animation disappear whenever UIKit tore that window down first.
    gCCAConnectivityCompactWindow = window;
    UIView *host = CCAConnectivityTransitionHostForWindow(window);
    UIView *sourceView = (gCCAConnectivityHasProxySourceFrame && gCCAConnectivityProxySourceView.window) ? gCCAConnectivityProxySourceView : controller.view;
    UIView *snapshot = CCAConnectivityStaticSnapshot(sourceView, NO);
    if (!host || !snapshot) return;
    CGRect frame = gCCAConnectivityHasProxySourceFrame ? gCCAConnectivityProxySourceWindowFrame : CCAConnectivityScreenFrameForView(controller.view);
    gCCAConnectivityCompactWindowFrame = frame;
    gCCAConnectivityHasCompactWindowFrame = CGRectGetWidth(frame) > 1.0 && CGRectGetHeight(frame) > 1.0;
    snapshot.frame = CCAConnectivityHostFrameForScreenRect(host, frame);
    CGFloat sourceRadius = gCCAConnectivityHasProxySourceFrame ? gCCAConnectivityProxySourceCornerRadius : controller.view.layer.cornerRadius;
    gCCAConnectivityCompactCornerRadius = sourceRadius > 1.0 ? sourceRadius : 32.0;
    snapshot.layer.cornerRadius = gCCAConnectivityCompactCornerRadius;
    snapshot.layer.cornerCurve = kCACornerCurveContinuous;
    snapshot.layer.masksToBounds = YES;
    UIView *surface = CCANewConnectivityMaterialView(controller.view);
    surface.frame = snapshot.frame;
    surface.layer.cornerRadius = gCCAConnectivityCompactCornerRadius;
    surface.layer.cornerCurve = kCACornerCurveContinuous;
    surface.layer.masksToBounds = YES;
    surface.alpha = 1.0;
    [host addSubview:surface];
    gCCAConnectivityTransitionSurface = surface;
    [host addSubview:snapshot];
    gCCAConnectivityCompactTransitionSnapshot = snapshot;
    if ([snapshot isKindOfClass:[UIImageView class]]) {
        gCCAConnectivityCachedCompactImage = ((UIImageView *)snapshot).image;
    }
    [UIView performWithoutAnimation:^{
        controller.view.hidden = YES;
        controller.view.alpha = 0.0;
        controller.view.layer.opacity = 0.0;
    }];
}

static void CCAStartConnectivityOpeningReveal(UIPresentationController *presentationController) {
    if (!gCCAConnectivityExpansionActive || gCCAConnectivityOpeningRevealStarted || gCCAConnectivityClosingTransitionActive) return;
    UIViewController *presented = presentationController.presentedViewController;
    UIViewController *controller = CCAConnectivityChild(presented, @"CCUIConnectivityModuleViewController");
    if ([NSStringFromClass(presented.class) isEqualToString:@"CCUIConnectivityModuleViewController"]) controller = presented;
    if (!controller || !controller.view.window || !gCCAConnectivityTransitionHost) return;
    gCCAConnectivityOpeningRevealStarted = YES;
    gCCAConnectivityTransitionController = controller;
    gCCAConnectivityTransitionPresentationController = presentationController;
    NSUInteger generation = gCCAConnectivityTransitionGeneration;
    UIWindow *window = controller.view.window;
    UIView *host = gCCAConnectivityTransitionHost ?: CCAConnectivityTransitionHostForWindow(window);

    if (!host) {
        CCARemoveConnectivityTransitionVisuals(YES);
        return;
    }

    // Let the final expanded hierarchy settle invisibly, then flatten it once.
    // Animating this stable image prevents UIKit's child controllers from
    // reintroducing their stock fly-out animations midway through our blend.
    gCCAConnectivitySnapshotCaptureActive = YES;
    UIView *presentedSurface = presentationController.presentedView;
    [UIView performWithoutAnimation:^{
        presentedSurface.hidden = NO;
        presentedSurface.alpha = 1.0;
        presentedSurface.layer.opacity = 1.0;
        controller.view.hidden = NO;
        controller.view.alpha = 1.0;
        controller.view.layer.opacity = 1.0;
        controller.view.transform = CGAffineTransformIdentity;
        CCAConfigureConnectivityLayout(controller);
        [controller.view setNeedsLayout];
        [controller.view layoutIfNeeded];
        CCAConfigureConnectivityLayout(controller);
        CCAStopConnectivitySubviewAnimations(controller.view, YES);
    }];

    CGSize finalSize = controller.view.bounds.size;
    CGRect screenBounds = UIScreen.mainScreen.bounds;
    // convertRect: includes the presentation ancestor's in-flight transform at
    // this point and therefore reports a compact-origin frame. The expanded
    // platter is centered by its presentation controller; derive that final
    // frame directly from its settled bounds so the temporary host is immune
    // to the native transition's current progress on every screen size.
    CGRect finalScreenFrame = CGRectMake(round((CGRectGetWidth(screenBounds) - finalSize.width) * 0.5),
                                         round((CGRectGetHeight(screenBounds) - finalSize.height) * 0.5),
                                         finalSize.width,
                                         finalSize.height);
    CGRect finalHostFrame = CCAConnectivityHostFrameForScreenRect(host, finalScreenFrame);
    UIView *expandedSnapshot = CCAConnectivityExpandedCompositeSnapshot(controller, host);
    if (!expandedSnapshot) expandedSnapshot = CCAConnectivityStaticSnapshot(controller.view, YES);
    if (!expandedSnapshot || CGRectIsNull(finalHostFrame)) {
        CCARemoveConnectivityTransitionVisuals(YES);
        return;
    }
    if ([expandedSnapshot isKindOfClass:[UIImageView class]]) expandedSnapshot.frame = finalHostFrame;
    expandedSnapshot.alpha = 0.0;
    expandedSnapshot.transform = CGAffineTransformMakeTranslation(0.0, 12.0);
    [host addSubview:expandedSnapshot];
    gCCAConnectivityExpandedTransitionSnapshot = expandedSnapshot;
    gCCAConnectivitySnapshotCaptureActive = NO;
    [UIView performWithoutAnimation:^{
        presentedSurface.hidden = YES;
        presentedSurface.alpha = 0.0;
        presentedSurface.layer.opacity = 0.0;
        controller.view.hidden = YES;
        controller.view.alpha = 0.0;
        controller.view.layer.opacity = 0.0;
        controller.view.transform = CGAffineTransformIdentity;
    }];
    CCASuppressConnectivityLiveChildren(controller);

    // Compact and expanded connectivity are each flattened into one complete
    // pane. Their cards, labels, and glyphs therefore cannot separate or fly on
    // independent native child animations during the handoff.
    NSTimeInterval duration = MIN(0.70, MAX(0.64, CCAConnectivityTransitionDuration(presented) + 0.24));
    [UIView animateKeyframesWithDuration:duration delay:0.0
                                options:UIViewKeyframeAnimationOptionCalculationModeCubic | UIViewAnimationOptionCurveEaseInOut |
                                        UIViewAnimationOptionBeginFromCurrentState
                             animations:^{
        [UIView addKeyframeWithRelativeStartTime:0.02 relativeDuration:0.56 animations:^{
            gCCAConnectivityCompactTransitionSnapshot.alpha = 0.0;
        }];
        [UIView addKeyframeWithRelativeStartTime:0.0 relativeDuration:0.82 animations:^{
            gCCAConnectivityTransitionSurface.frame = finalHostFrame;
            gCCAConnectivityTransitionSurface.layer.cornerRadius = 38.0;
            gCCAConnectivityTransitionSurface.alpha = 0.18;
        }];
        [UIView addKeyframeWithRelativeStartTime:0.58 relativeDuration:0.42 animations:^{
            gCCAConnectivityTransitionSurface.alpha = 0.0;
        }];
        [UIView addKeyframeWithRelativeStartTime:0.20 relativeDuration:0.76 animations:^{
            expandedSnapshot.alpha = 1.0;
            expandedSnapshot.transform = CGAffineTransformIdentity;
        }];
    } completion:^(__unused BOOL finished) {
        if (generation != gCCAConnectivityTransitionGeneration || gCCAConnectivityClosingTransitionActive) {
            if (!gCCAConnectivityClosingTransitionActive && gCCAExpandedModuleOpen) {
                CCARestoreConnectivityPresentedSurface(presentationController, controller);
                CCARemoveConnectivityTransitionVisuals(NO);
            }
            return;
        }
        gCCAConnectivitySnapshotCaptureActive = NO;
        CCARestoreConnectivityPresentedSurface(presentationController, controller);
        CCARemoveConnectivityTransitionVisuals(NO);
    }];
    __weak UIPresentationController *weakPresentation = presentationController;
    __weak UIViewController *weakController = controller;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((duration + 0.18) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (generation != gCCAConnectivityTransitionGeneration || gCCAConnectivityClosingTransitionActive || !gCCAExpandedModuleOpen) return;
        if (weakPresentation && weakController) {
            CCARestoreConnectivityPresentedSurface(weakPresentation, weakController);
            CCARemoveConnectivityTransitionVisuals(NO);
        }
    });
}

static void CCABeginConnectivityClosingTransition(UIPresentationController *presentationController) {
    if (!gCCAConnectivityExpansionActive || gCCAConnectivityClosingTransitionActive) return;
    UIViewController *presented = presentationController.presentedViewController;
    UIViewController *controller = CCAConnectivityChild(presented, @"CCUIConnectivityModuleViewController");
    if ([NSStringFromClass(presented.class) isEqualToString:@"CCUIConnectivityModuleViewController"]) controller = presented;
    if (!controller || !controller.view.window) return;

    CCARemoveConnectivityTransitionVisuals(YES);
    gCCAConnectivityTransitionGeneration++;
    NSUInteger generation = gCCAConnectivityTransitionGeneration;
    gCCAConnectivityClosingTransitionActive = YES;
    gCCAConnectivityTransitionController = controller;
    gCCAConnectivityTransitionPresentationController = presentationController;
    UIWindow *window = gCCAConnectivityCompactWindow ?: controller.view.window;
    UIView *host = CCAConnectivityTransitionHostForWindow(window);
    gCCAConnectivitySnapshotCaptureActive = YES;
    // Capture the fully composited pixels of each custom card from the source
    // window. MTMaterial/backdrop layers do not reliably render when the
    // controller alone is flattened; card crops keep every background, label,
    // and glyph together under one parent transform.
    UIView *snapshot = CCAConnectivityExpandedCompositeSnapshot(controller, host);
    if (!snapshot) snapshot = CCAConnectivityStaticSnapshot(controller.view, YES);
    gCCAConnectivitySnapshotCaptureActive = NO;
    if (!host || !snapshot) {
        CCARemoveConnectivityTransitionVisuals(YES);
        return;
    }
    CGRect expandedWindowFrame = CCAConnectivityScreenFrameForView(controller.view);
    if ([snapshot isKindOfClass:[UIImageView class]]) {
        snapshot.frame = CCAConnectivityHostFrameForScreenRect(host, expandedWindowFrame);
    }
    UIView *surface = CCANewConnectivityMaterialView(controller.view);
    surface.frame = CCAConnectivityHostFrameForScreenRect(host, expandedWindowFrame);
    surface.layer.cornerRadius = 38.0;
    surface.layer.cornerCurve = kCACornerCurveContinuous;
    surface.layer.masksToBounds = YES;
    surface.alpha = 0.0;
    [host addSubview:surface];
    gCCAConnectivityTransitionSurface = surface;
    [host addSubview:snapshot];
    gCCAConnectivityExpandedTransitionSnapshot = snapshot;
    controller.view.hidden = YES;
    controller.view.alpha = 0.0;
    controller.view.layer.opacity = 0.0;
    CCASuppressConnectivityLiveChildren(controller);

    CGRect compactHostFrame = gCCAConnectivityHasCompactWindowFrame
        ? CCAConnectivityHostFrameForScreenRect(host, gCCAConnectivityCompactWindowFrame)
        : CGRectNull;
    CGRect surfaceTargetFrame = CGRectIsNull(compactHostFrame) ? surface.frame : compactHostFrame;
    if (gCCAConnectivityCachedCompactImage && !CGRectIsNull(compactHostFrame)) {
        UIImageView *compactSnapshot = [[UIImageView alloc] initWithImage:gCCAConnectivityCachedCompactImage];
        compactSnapshot.contentMode = UIViewContentModeScaleToFill;
        compactSnapshot.frame = compactHostFrame;
        compactSnapshot.layer.cornerRadius = 30.0;
        compactSnapshot.layer.cornerCurve = kCACornerCurveContinuous;
        compactSnapshot.layer.masksToBounds = YES;
        compactSnapshot.alpha = 0.0;
        compactSnapshot.userInteractionEnabled = NO;
        [host addSubview:compactSnapshot];
        gCCAConnectivityCompactTransitionSnapshot = compactSnapshot;
    }
    NSTimeInterval duration = MIN(0.62, MAX(0.56, CCAConnectivityTransitionDuration(presented) + 0.18));
    gCCAConnectivityClosingTransitionDeadline = CACurrentMediaTime() + duration;
    [UIView animateKeyframesWithDuration:duration delay:0.0
                                options:UIViewKeyframeAnimationOptionCalculationModeCubic | UIViewAnimationOptionCurveEaseInOut |
                                        UIViewAnimationOptionBeginFromCurrentState
                             animations:^{
        [UIView addKeyframeWithRelativeStartTime:0.0 relativeDuration:0.58 animations:^{
            snapshot.alpha = 0.0;
            // The expanded menu lifts very slightly as it fades, matching the
            // later Control Center transition instead of sinking downward.
            snapshot.transform = CGAffineTransformMakeTranslation(0.0, -10.0);
        }];
        [UIView addKeyframeWithRelativeStartTime:0.08 relativeDuration:0.24 animations:^{
            surface.alpha = 0.78;
        }];
        [UIView addKeyframeWithRelativeStartTime:0.12 relativeDuration:0.82 animations:^{
            surface.frame = surfaceTargetFrame;
            surface.layer.cornerRadius = gCCAConnectivityCompactCornerRadius;
            surface.alpha = 1.0;
        }];
        [UIView addKeyframeWithRelativeStartTime:0.48 relativeDuration:0.46 animations:^{
            gCCAConnectivityCompactTransitionSnapshot.alpha = 1.0;
        }];
    } completion:^(__unused BOOL finished) {
        if (generation != gCCAConnectivityTransitionGeneration) return;
        // didCloseExpandedModule performs the compact handoff.  Keep the
        // transparent transition host alive until then so UIKit's reused child
        // hierarchy never becomes visible in its intermediate frames.
    }];
}

static void CCAFinishConnectivityClosingTransition(UIViewController *controller) {
    UIViewController *target = gCCAConnectivityCompactController ?: controller ?: gCCAConnectivityTransitionController;
    CFTimeInterval remaining = gCCAConnectivityClosingTransitionDeadline - CACurrentMediaTime();
    if (gCCAConnectivityClosingTransitionActive && remaining > 0.01 && !gCCAConnectivityClosingFinishScheduled) {
        gCCAConnectivityClosingFinishScheduled = YES;
        __weak UIViewController *weakTarget = target;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(remaining * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            gCCAConnectivityClosingFinishScheduled = NO;
            CCAFinishConnectivityClosingTransition(weakTarget);
        });
        return;
    }
    if (!target || !target.view) {
        CCARemoveConnectivityTransitionVisuals(NO);
        gCCAConnectivityTransitionController = nil;
        gCCAConnectivityCompactController = nil;
        return;
    }
    [UIView performWithoutAnimation:^{
        target.view.hidden = YES;
        target.view.alpha = 0.0;
        target.view.layer.opacity = 0.0;
        CCAConfigureConnectivityLayout(target);
        [target.view setNeedsLayout];
        [target.view layoutIfNeeded];
        target.view.hidden = NO;
        target.view.alpha = 1.0;
        target.view.layer.opacity = 1.0;
    }];
    // Keep the populated compact still above the restored live module for a
    // few frames. This masks the final UIKit child reparent/layout pass and
    // turns the previous blank-frame -> full-opacity snap into a real handoff
    // between two identical populated states.
    UIView *compactSnapshot = gCCAConnectivityCompactTransitionSnapshot;
    if (compactSnapshot) {
        [UIView animateWithDuration:0.16 delay:0.02
                            options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState
                         animations:^{ compactSnapshot.alpha = 0.0; }
                         completion:^(__unused BOOL finished) {
            CCARemoveConnectivityTransitionVisuals(NO);
            gCCAConnectivityTransitionController = nil;
            gCCAConnectivityCompactController = nil;
        }];
    } else {
        CCARemoveConnectivityTransitionVisuals(NO);
        gCCAConnectivityTransitionController = nil;
        gCCAConnectivityCompactController = nil;
    }
}

static void CCAApplyExpandedPlatterRadius(UIPresentationController *presentationController) {
    UIViewController *anchor = nil;
    @try { anchor = [(id)presentationController valueForKey:@"anchoringViewController"]; } @catch (__unused NSException *exception) {}
    if (!anchor) {
        @try { anchor = [(id)presentationController valueForKey:@"_anchoringViewController"]; } @catch (__unused NSException *exception) {}
    }
    CGFloat radius = 0.0;
    if (gEnabled && anchor.view) {
        radius = [[CCAsterCoordinator shared] refinedCornerRadiusForSize:anchor.view.bounds.size];
        [[CCAsterCoordinator shared] applyTransitionRadiusToModule:anchor];
    }
    if (radius <= 1.0) radius = anchor.view.layer.cornerRadius;
    for (UIView *view = anchor.view.superview; radius <= 1.0 && view; view = view.superview) radius = view.layer.cornerRadius;
    if (radius <= 1.0) radius = 32.0;

    UIView *presentedView = presentationController.presentedView;
    UIView *contentView = presentationController.presentedViewController.view;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (UIView *target in @[presentedView ?: (id)NSNull.null, contentView ?: (id)NSNull.null]) {
        if (![target isKindOfClass:[UIView class]]) continue;
        target.layer.cornerRadius = radius;
        target.layer.cornerCurve = kCACornerCurveContinuous;
        // Expanded connectivity and menu content intentionally reaches beyond
        // intermediate controller bounds. Never clip those presentation hosts.
        target.layer.masksToBounds = NO;
    }

    // Round only matching material surfaces; these own the visible platter
    // fill and can safely mask their own effect without clipping child content.
    NSMutableArray<UIView *> *queue = [NSMutableArray array];
    if (contentView) [queue addObjectsFromArray:contentView.subviews];
    while (queue.count) {
        UIView *candidate = queue.firstObject;
        [queue removeObjectAtIndex:0];
        NSString *name = NSStringFromClass(candidate.class);
        BOOL material = [name containsString:@"Material"] || [name containsString:@"VisualEffect"] || [name containsString:@"Platter"];
        BOOL fillsContent = fabs(CGRectGetWidth(candidate.bounds) - CGRectGetWidth(contentView.bounds)) < 4.0 &&
                            fabs(CGRectGetHeight(candidate.bounds) - CGRectGetHeight(contentView.bounds)) < 4.0;
        if (material && fillsContent) {
            candidate.layer.cornerRadius = radius;
            candidate.layer.cornerCurve = kCACornerCurveContinuous;
            candidate.layer.masksToBounds = YES;
        }
        [queue addObjectsFromArray:candidate.subviews];
    }
    [CATransaction commit];
    CCASuppressConnectivityOuterMaterial(presentationController);
}

%hook CCUIContentModuleDetailPresentationController

- (double)_preferredExpandedContentHeightForViewController:(UIViewController *)viewController {
    double original = %orig;
    if (!gEnabled || !CCAIsConnectivityExpandedController(viewController)) return original;
    CGFloat width = CGRectGetWidth(viewController.view.bounds);
    SEL widthSelector = NSSelectorFromString(@"_preferredExpandedContentWidthForViewController:");
    if (width < 100.0 && [(id)self respondsToSelector:widthSelector]) {
        width = ((double (*)(id, SEL, id))objc_msgSend)((id)self, widthSelector, viewController);
    }
    if (width < 100.0) width = CGRectGetWidth(UIScreen.mainScreen.bounds) * 0.856;
    CCAConnectivityExpandedMetrics metrics = CCAConnectivityMetricsForWidth(width);
    UIEdgeInsets safeInsets = viewController.view.window.safeAreaInsets;
    CGFloat availableHeight = CGRectGetHeight(UIScreen.mainScreen.bounds) - safeInsets.top - safeInsets.bottom - 48.0;
    return MIN(metrics.contentHeight, availableHeight);
}

- (void)presentationTransitionWillBegin {
    CCAApplyExpansionPageGeometrySync(gOverlayControllers.allObjects.firstObject);
    %orig;
    CCAApplyExpandedPlatterRadius((UIPresentationController *)(id)self);
}

- (void)containerViewWillLayoutSubviews {
    %orig;
    CCAApplyExpandedPlatterRadius((UIPresentationController *)(id)self);
}

- (void)containerViewDidLayoutSubviews {
    %orig;
    CCAApplyExpandedPlatterRadius((UIPresentationController *)(id)self);
}

- (void)dismissalTransitionWillBegin {
    // Set the final continuous radius before UIKit captures the first collapse
    // frame; applying it only during layout caused the visible radius snap.
    CCAPrepareOverlayChromeForExpandedDismissal(gOverlayControllers.allObjects.firstObject);
    CCAApplyExpandedPlatterRadius((UIPresentationController *)(id)self);
    %orig;
    CCAApplyExpandedPlatterRadius((UIPresentationController *)(id)self);
}

%end


%hook CCUIContentModuleContainerPresentationController

- (void)containerViewWillLayoutSubviews {
    %orig;
    CCAConfigureConnectivityPresentationContainer((UIPresentationController *)(id)self);
}

- (void)containerViewDidLayoutSubviews {
    %orig;
    CCAConfigureConnectivityPresentationContainer((UIPresentationController *)(id)self);
}

- (void)presentationTransitionWillBegin {
    UIPresentationController *presentation = (UIPresentationController *)(id)self;
    CCAApplyExpansionPageGeometrySync(gOverlayControllers.allObjects.firstObject);
    // Preflight the custom height/masks before Apple's animator captures its
    // initial frame, then reassert after it installs the transition hierarchy.
    CCAConfigureConnectivityPresentationContainer(presentation);
    %orig;
    CCAConfigureConnectivityPresentationContainer(presentation);
}

- (void)presentationTransitionDidEnd:(BOOL)completed {
    %orig;
    UIPresentationController *presentation = (UIPresentationController *)(id)self;
    if (!completed || !gCCAConnectivityExpansionActive || gCCAConnectivityOpeningRevealStarted) return;
    // Apple's child controllers do not reach their final model frames until
    // the native presentation completes. Capturing earlier simply freezes the
    // fly-out geometry. Build our flattened card pane only from this settled
    // hierarchy, while the compact still continues to cover the native UI.
    CCAConfigureConnectivityPresentationContainer(presentation);
    CCAApplyExpandedPlatterRadius(presentation);
    if (gCCAConnectivityProxyExpansionActive) {
        UIViewController *connectivity = CCAConnectivityChild(presentation.presentedViewController, @"CCUIConnectivityModuleViewController");
        if ([NSStringFromClass(presentation.presentedViewController.class) isEqualToString:@"CCUIConnectivityModuleViewController"]) {
            connectivity = presentation.presentedViewController;
        }
        if (connectivity) CCARestoreConnectivityPresentedSurface(presentation, connectivity);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.08 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            CCAOpenPendingConnectivityDetailFromPresentation(presentation);
        });
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        CCAConfigureConnectivityPresentationContainer(presentation);
        CCAStartConnectivityOpeningReveal(presentation);
    });
}

    - (void)dismissalTransitionWillBegin {
        UIPresentationController *presentation = (UIPresentationController *)(id)self;
        CCAPrepareOverlayChromeForExpandedDismissal(gOverlayControllers.allObjects.firstObject);
        if (!gCCAConnectivityProxyExpansionActive) CCABeginConnectivityClosingTransition(presentation);
        %orig;
    }

%end

%end

%group CCAExpandedModuleCallbacks

static UIViewController *CCACompactMediaModuleForSource(UIViewController *overlay, id sourceObject) {
    NSString *identifier = [CCAIdentifierFromObject(sourceObject) copy];
    BOOL sourceIsMedia = [NSStringFromClass([sourceObject class]) isEqualToString:@"MediaControlsModule"];
    if (identifier.length &&
        ![identifier isEqualToString:@"com.apple.mediaremote.controlcenter.nowplaying"] &&
        !sourceIsMedia) return nil;

    UIViewController *module = nil;
    SEL contentControllerSelector = NSSelectorFromString(@"contentViewController");
    if (sourceIsMedia && [sourceObject respondsToSelector:contentControllerSelector]) {
        @try {
            id candidate = ((id (*)(id, SEL))objc_msgSend)(sourceObject, contentControllerSelector);
            if ([candidate isKindOfClass:[UIViewController class]]) module = candidate;
        } @catch (__unused NSException *exception) {}
    }
    if (!module) module = CCAModuleControllerMatchingObject(overlay, sourceObject);
    if (!module) {
        for (UIViewController *candidate in CCACollectModuleControllers(overlay)) {
            NSString *candidateIdentifier = CCAModuleIdentifier(candidate);
            if ((identifier.length && [candidateIdentifier isEqualToString:identifier]) ||
                (sourceIsMedia && [candidateIdentifier isEqualToString:@"com.apple.mediaremote.controlcenter.nowplaying"])) {
                module = candidate;
                break;
            }
        }
    }
    if (!module) return nil;
    if (!sourceIsMedia &&
        ![CCAModuleIdentifier(module) isEqualToString:@"com.apple.mediaremote.controlcenter.nowplaying"]) return nil;
    return module;
}


static void CCADiscardCompactMediaTransitionSnapshot(void) {
    [gCCAMediaCompactTransitionSnapshot.layer removeAllAnimations];
    [gCCAMediaExpandedTransitionSnapshot.layer removeAllAnimations];
    [gCCAMediaCompactTransitionSnapshot removeFromSuperview];
    [gCCAMediaExpandedTransitionSnapshot removeFromSuperview];
    [UIView performWithoutAnimation:^{
        gCCAMediaHiddenExpandedView.hidden = NO;
        gCCAMediaHiddenExpandedView.alpha = 1.0;
        gCCAMediaHiddenExpandedView.layer.opacity = 1.0;
    }];
    gCCAMediaCompactTransitionSnapshot = nil;
    gCCAMediaExpandedTransitionSnapshot = nil;
    gCCAMediaHiddenExpandedView = nil;
    gCCAMediaCompactModule = nil;
    gCCAMediaCompactDestinationScreenFrame = CGRectZero;
    gCCAMediaExpandedPresentationScreenFrame = CGRectZero;
    gCCAMediaTransitionWindow.hidden = YES;
    gCCAMediaTransitionWindow.rootViewController = nil;
    gCCAMediaTransitionWindow = nil;
    gCCAMediaTransitionHost = nil;
}

static UIView *CCAMediaTransitionHostForWindow(UIWindow *sourceWindow) {
    if (!sourceWindow) return nil;
    if (gCCAMediaTransitionHost.superview) {
        gCCAMediaTransitionWindow.windowLevel = MAX(gCCAMediaTransitionWindow.windowLevel,
                                                    sourceWindow.windowLevel + 100.0);
        gCCAMediaTransitionWindow.hidden = NO;
        return gCCAMediaTransitionHost;
    }
    UIWindow *window = nil;
    if (@available(iOS 13.0, *)) {
        if (sourceWindow.windowScene) window = [[UIWindow alloc] initWithWindowScene:sourceWindow.windowScene];
    }
    if (!window) window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    window.frame = UIScreen.mainScreen.bounds;
    window.backgroundColor = UIColor.clearColor;
    window.opaque = NO;
    window.userInteractionEnabled = NO;
    window.windowLevel = MAX(UIWindowLevelAlert + 100.0, sourceWindow.windowLevel + 100.0);
    UIViewController *root = [UIViewController new];
    root.view.frame = window.bounds;
    root.view.backgroundColor = UIColor.clearColor;
    root.view.opaque = NO;
    root.view.userInteractionEnabled = NO;
    root.view.clipsToBounds = NO;
    window.rootViewController = root;
    window.hidden = NO;
    gCCAMediaTransitionWindow = window;
    gCCAMediaTransitionHost = root.view;
    return root.view;
}

static UIView *CCACompositedSnapshotView(UIView *view) {
    if (!view || CGRectIsEmpty(view.bounds)) return nil;
    UIGraphicsBeginImageContextWithOptions(view.bounds.size, NO, UIScreen.mainScreen.scale);
    BOOL drewHierarchy = [view drawViewHierarchyInRect:view.bounds afterScreenUpdates:NO];
    if (!drewHierarchy) [view.layer renderInContext:UIGraphicsGetCurrentContext()];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (!image) return nil;
    UIImageView *snapshot = [[UIImageView alloc] initWithImage:image];
    snapshot.frame = view.bounds;
    snapshot.contentMode = UIViewContentModeScaleToFill;
    snapshot.userInteractionEnabled = NO;
    return snapshot;
}

static UIView *CCAWindowCropSnapshotView(UIView *view) {
    UIWindow *window = view.window;
    if (!window || CGRectIsEmpty(view.bounds)) return nil;
    CGRect crop = [view convertRect:view.bounds toView:window];
    UIView *snapshot = CCAWindowCropSnapshotForWindowRect(window, crop);
    snapshot.frame = view.bounds;
    return snapshot;
}

static UIView *CCAWindowCropSnapshotForWindowRect(UIWindow *window, CGRect crop) {
    if (!window || CGRectIsEmpty(crop)) return nil;
    UIGraphicsBeginImageContextWithOptions(crop.size, NO, UIScreen.mainScreen.scale);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextTranslateCTM(context, -crop.origin.x, -crop.origin.y);
    BOOL drewHierarchy = [window drawViewHierarchyInRect:window.bounds afterScreenUpdates:YES];
    if (!drewHierarchy) [window.layer renderInContext:context];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (!image) return nil;

    UIImageView *snapshot = [[UIImageView alloc] initWithImage:image];
    snapshot.frame = crop;
    snapshot.contentMode = UIViewContentModeScaleToFill;
    snapshot.userInteractionEnabled = NO;
    return snapshot;
}

static void CCARefreshSettledCompactMediaSnapshot(UIViewController *overlay) {
    if (!overlay || gCCAExpandedModuleOpen || gCCAExpandedModuleClosingActive || gEditModeActive) return;
    CFTimeInterval now = CACurrentMediaTime();
    if (now - gCCAMediaCompactSnapshotRefreshTime < 0.25) return;

    UIViewController *module = CCAConnectivityChild(overlay, @"MRUControlCenterViewController");
    UIView *compactSurface = module.view.superview ?: module.view;
    CGSize size = compactSurface.bounds.size;
    if (!module.view.window || size.width < 40.0 || size.height < 40.0 ||
        size.width > 350.0 || size.height > 300.0) return;

    [compactSurface layoutIfNeeded];
    UIView *snapshot = CCAWindowCropSnapshotView(compactSurface);
    if (!snapshot) snapshot = CCACompositedSnapshotView(compactSurface);
    if (!snapshot) snapshot = [compactSurface snapshotViewAfterScreenUpdates:YES];
    if (!snapshot) return;
    snapshot.userInteractionEnabled = NO;
    snapshot.layer.cornerRadius = compactSurface.layer.cornerRadius;
    snapshot.layer.cornerCurve = kCACornerCurveContinuous;
    snapshot.layer.masksToBounds = YES;

    [gCCAMediaCompactTransitionSnapshot removeFromSuperview];
    gCCAMediaCompactTransitionSnapshot = snapshot;
    gCCAMediaCompactModule = module;
    gCCAMediaCompactDestinationScreenFrame = [compactSurface convertRect:compactSurface.bounds toView:nil];
    gCCAMediaCompactSnapshotRefreshTime = now;
}

static void CCACaptureCompactMediaTransitionSnapshot(UIViewController *overlay, id sourceObject) {
    CCADiscardCompactMediaTransitionSnapshot();
    UIViewController *module = CCACompactMediaModuleForSource(overlay, sourceObject);
    if (!module.view || !module.view.window) return;
    UIView *compactSurface = module.view.superview ?: module.view;
    [compactSurface layoutIfNeeded];
    UIView *snapshot = CCACompositedSnapshotView(compactSurface);
    if (!snapshot) snapshot = [compactSurface snapshotViewAfterScreenUpdates:NO];
    if (!snapshot) {
        snapshot = [compactSurface resizableSnapshotViewFromRect:compactSurface.bounds
                                              afterScreenUpdates:NO
                                                   withCapInsets:UIEdgeInsetsZero];
    }
    if (!snapshot) return;
    snapshot.userInteractionEnabled = NO;
    snapshot.layer.cornerRadius = compactSurface.layer.cornerRadius;
    snapshot.layer.cornerCurve = kCACornerCurveContinuous;
    snapshot.layer.masksToBounds = YES;
    gCCAMediaCompactModule = module;
    gCCAMediaCompactTransitionSnapshot = snapshot;
    gCCAMediaCompactDestinationScreenFrame = [compactSurface convertRect:compactSurface.bounds toView:nil];
}

static void CCABeginCompactMediaDismissalProxy(UIViewController *overlay, id sourceObject) {
    UIViewController *module = gCCAMediaCompactModule ?: CCACompactMediaModuleForSource(overlay, sourceObject);
    if (module) gCCAMediaCompactModule = module;
    if (!overlay.view || !module) return;

    UIViewController *presented = overlay.presentedViewController;
    UIView *presentedView = presented.view;
    UIWindow *sourceWindow = presentedView.window ?: overlay.view.window;
    UIView *host = CCAMediaTransitionHostForWindow(sourceWindow);
    if (!host) return;
    CGRect currentDestinationScreenFrame = [module.view convertRect:module.view.bounds toView:nil];
    if (!CGRectIsEmpty(currentDestinationScreenFrame)) {
        gCCAMediaCompactDestinationScreenFrame = currentDestinationScreenFrame;
    }
    CGRect presentedScreenFrame = presentedView.window ?
        [presentedView convertRect:presentedView.bounds toView:nil] : gCCAMediaCompactDestinationScreenFrame;
    gCCAMediaExpandedPresentationScreenFrame = presentedScreenFrame;

    UIView *presentationSurface = presented.presentationController.containerView ?: presentedView;
    CGRect surfaceScreenFrame = presentationSurface.window ?
        [presentationSurface convertRect:presentationSurface.bounds toView:nil] : presentedScreenFrame;
    CGRect surfaceHostFrame = [host convertRect:surfaceScreenFrame fromView:nil];
    UIView *expandedSnapshot = [presentationSurface snapshotViewAfterScreenUpdates:NO];
    if (!expandedSnapshot) {
        expandedSnapshot = [presentationSurface resizableSnapshotViewFromRect:presentationSurface.bounds
                                                           afterScreenUpdates:NO
                                                                withCapInsets:UIEdgeInsetsZero];
    }
    if (expandedSnapshot) {
        expandedSnapshot.frame = surfaceHostFrame;
        expandedSnapshot.userInteractionEnabled = NO;
        [host addSubview:expandedSnapshot];
        gCCAMediaExpandedTransitionSnapshot = expandedSnapshot;
    }
}

static void CCAFadeExpandedMediaDismissalSnapshot(void) {
    UIView *expandedSnapshot = gCCAMediaExpandedTransitionSnapshot;
    UIView *compactSnapshot = gCCAMediaCompactTransitionSnapshot;
    if (!expandedSnapshot && !compactSnapshot) return;
    [UIView animateWithDuration:0.13 delay:0.0
                        options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
        expandedSnapshot.alpha = 0.0;
        compactSnapshot.alpha = 1.0;
    } completion:^(__unused BOOL finished) {
        [expandedSnapshot removeFromSuperview];
        if (gCCAMediaExpandedTransitionSnapshot == expandedSnapshot) {
            gCCAMediaExpandedTransitionSnapshot = nil;
        }
    }];
}

static void CCAAttachCompactMediaSnapshotToNativeTransition(void) {
    UIViewController *module = gCCAMediaCompactModule;
    UIView *snapshot = gCCAMediaCompactTransitionSnapshot;
    UIView *contentContainer = module.view.superview;
    if (!module.view || !snapshot || !contentContainer) return;

    [snapshot removeFromSuperview];
    snapshot.frame = contentContainer.bounds;
    snapshot.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    snapshot.alpha = 0.0;
    [contentContainer addSubview:snapshot];
    [contentContainer bringSubviewToFront:snapshot];
    [UIView performWithoutAnimation:^{
        module.view.alpha = 0.0;
        module.view.layer.opacity = 0.0;
    }];
}

static void CCARestoreCompactMediaLayout(UIViewController *overlay, id sourceObject, BOOL applyCCAsterLayout) {
    UIViewController *module = CCACompactMediaModuleForSource(overlay, sourceObject);
    if (!module) return;

    UIViewController *mediaController = CCAConnectivityChild(module, @"MRUControlCenterViewController");
    if (!mediaController && [NSStringFromClass(module.class) isEqualToString:@"MRUControlCenterViewController"]) {
        mediaController = module;
    }
    if (!mediaController) return;

    SEL transitionSelector = NSSelectorFromString(@"didTransitionToExpandedContentMode:");
    if ([mediaController respondsToSelector:transitionSelector]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)((id)mediaController, transitionSelector, NO);
    }
    SEL updateSelector = NSSelectorFromString(@"updateNowPlayingViewControllerLayout");
    if ([mediaController respondsToSelector:updateSelector]) {
        ((void (*)(id, SEL))objc_msgSend)((id)mediaController, updateSelector);
    }

    UIViewController *nowPlayingController = nil;
    @try {
        id candidate = [(id)mediaController valueForKey:@"nowPlayingViewController"];
        if ([candidate isKindOfClass:[UIViewController class]]) nowPlayingController = candidate;
    } @catch (__unused NSException *exception) {}
    SEL setLayoutSelector = NSSelectorFromString(@"setLayout:");
    if ([nowPlayingController respondsToSelector:setLayoutSelector]) {
        ((void (*)(id, SEL, NSInteger))objc_msgSend)((id)nowPlayingController, setLayoutSelector, 0);
    }
    SEL updateLayoutSelector = NSSelectorFromString(@"updateLayout");
    if ([nowPlayingController respondsToSelector:updateLayoutSelector]) {
        ((void (*)(id, SEL))objc_msgSend)((id)nowPlayingController, updateLayoutSelector);
    }

    [mediaController.view setNeedsLayout];
    [mediaController.view layoutIfNeeded];
    UIView *nowPlayingView = CCAFindSubviewWithClassName(mediaController.view, @"MRUNowPlayingView");
    if (nowPlayingView) {
        if ([nowPlayingView respondsToSelector:setLayoutSelector]) {
            ((void (*)(id, SEL, NSInteger))objc_msgSend)((id)nowPlayingView, setLayoutSelector, 0);
        }
        [nowPlayingView setNeedsLayout];
        [nowPlayingView layoutIfNeeded];
        if (!applyCCAsterLayout) {
            return;
        }
        objc_setAssociatedObject(nowPlayingView, kCCANowPlayingLayoutModeKey, nil, OBJC_ASSOCIATION_COPY_NONATOMIC);
        [nowPlayingView setNeedsLayout];
        [nowPlayingView layoutIfNeeded];
        CCAConfigureNowPlayingLayout(nowPlayingView);
    }
    if (applyCCAsterLayout) {
        UIView *snapshot = gCCAMediaCompactTransitionSnapshot.superview ?
            gCCAMediaCompactTransitionSnapshot : nil;
        CCAStopConnectivitySubviewAnimations(module.view, YES);
        [module.view setNeedsLayout];
        [module.view layoutIfNeeded];
        [UIView performWithoutAnimation:^{
            module.view.hidden = NO;
            module.view.alpha = 1.0;
            module.view.layer.opacity = 1.0;
        }];
        // MediaRemote finishes rebuilding several compact-only material and
        // control layers just after the container lands. Keep the already
        // landed compact proxy above it for two turns, then hand off in place.
        [UIView animateWithDuration:0.14 delay:0.08
                            options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState
                         animations:^{
            snapshot.alpha = 0.0;
        } completion:^(__unused BOOL finished) {
            CCADiscardCompactMediaTransitionSnapshot();
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                CCARefreshSettledCompactMediaSnapshot(overlay);
            });
        }];
    }
}

%hook CCUIModularControlCenterOverlayViewController

- (void)moduleCollectionViewController:(id)collection willOpenExpandedModule:(id)module {
    if (gEnabled && (gEditModeActive || gCCAEditTransitionActive)) {
        gCCAExpandedModuleOpen = NO;
        gCCAConnectivityExpansionActive = NO;
        gCCAExpandedModuleIdentifier = nil;
        CCAHaptic();
        return;
    }
    UIViewController *overlay = (UIViewController *)(id)self;
    // Never begin an expansion on top of stale transition state from an
    // earlier one that didn't finish its choreography.
    if (!gCCAExpandedModuleOpen &&
        (gCCAConnectivityTransitionWindow || gCCAConnectivityTransitionHost ||
         gCCAConnectivityClosingTransitionActive || gCCAConnectivityExpansionActive)) {
        CCAResetConnectivityExpansionState(overlay);
    }
    UIViewController *expandedController = CCAModuleControllerMatchingObject(overlay, module);
    if (!expandedController && [module isKindOfClass:[UIViewController class]]) expandedController = (UIViewController *)module;
    UIViewController *connectivity = expandedController ? CCAConnectivityChild(expandedController, @"CCUIConnectivityModuleViewController") : nil;
    if ([NSStringFromClass(expandedController.class) isEqualToString:@"CCUIConnectivityModuleViewController"]) connectivity = expandedController;
    NSString *openingIdentifier = [CCAModuleIdentifier(expandedController) copy] ?: [CCAIdentifierFromObject(module) copy];
    BOOL openingMedia = [openingIdentifier isEqualToString:@"com.apple.mediaremote.controlcenter.nowplaying"] ||
        [NSStringFromClass([module class]) isEqualToString:@"MediaControlsModule"];
    if (openingMedia) {
        if (!gCCAMediaCompactTransitionSnapshot || !gCCAMediaCompactModule ||
            gCCAMediaCompactTransitionSnapshot.superview) {
            CCACaptureCompactMediaTransitionSnapshot(overlay, module);
        }
    }
    // rangeOfString on a NIL identifier returns a zeroed range whose location
    // (0) is NOT NSNotFound — every identifier-less expansion (flashlight,
    // brightness, media, …) was misclassified as connectivity, inheriting the
    // six-card platter sizing (the chin) and its snapshot choreography that
    // hides platter materials until respring.
    BOOL openingConnectivity = connectivity != nil ||
        (openingIdentifier.length &&
         [openingIdentifier rangeOfString:@"Connectivity" options:NSCaseInsensitiveSearch].location != NSNotFound);
    CCAApplyExpansionPageGeometrySync(overlay);
    // Capture the settled compact hierarchy before resetting any of its proxy
    // controls.  The still image remains fixed while UIKit reparents and moves
    // the real child views invisibly underneath it.
    BOOL proxyConnectivityExpansion = openingConnectivity && gCCAConnectivityProxyExpansionActive && gCCAConnectivityHasProxySourceFrame;
    if (openingConnectivity && connectivity && !proxyConnectivityExpansion) CCABeginConnectivityOpeningTransition(connectivity);
    // Remove the compact mini-cluster transforms before Apple's expansion
    // transition asks the children for their new frames. UIKit otherwise lays
    // out through the 0.44 transform and produces oversized expanded controls.
    if (connectivity) CCAResetConnectivityCompactTransforms(connectivity);
    gCCAConnectivityExpansionActive = openingConnectivity;
    gCCAConnectivityProxyExpansionActive = proxyConnectivityExpansion;
    gCCAExpandedModuleClosingActive = NO;
    gCCAExpandedModuleOpen = YES;
    gCCAExpandedModuleIdentifier = openingIdentifier;
    if (openingConnectivity) {
        CGFloat expandedWidth = 0.0;
        SEL preferredWidthSelector = NSSelectorFromString(@"preferredExpandedContentWidth");
        if (connectivity && [(id)connectivity respondsToSelector:preferredWidthSelector]) {
            expandedWidth = ((double (*)(id, SEL))objc_msgSend)((id)connectivity, preferredWidthSelector);
        }
        if (expandedWidth < 250.0) expandedWidth = CGRectGetWidth(UIScreen.mainScreen.bounds) * 0.856;
        CGFloat expandedHeight = CCAConnectivityMetricsForWidth(expandedWidth).contentHeight;
        CGSize preferredSize = CGSizeMake(expandedWidth, expandedHeight);
        if (connectivity) {
            connectivity.preferredContentSize = preferredSize;
            for (UIViewController *candidate = connectivity.parentViewController; candidate; candidate = candidate.parentViewController) {
                candidate.preferredContentSize = preferredSize;
                if (candidate == expandedController) break;
            }
        }
        if (expandedController) expandedController.preferredContentSize = preferredSize;
        if ([module isKindOfClass:[UIViewController class]]) ((UIViewController *)module).preferredContentSize = preferredSize;

    }
    CCAsterCoordinator *coordinator = [CCAsterCoordinator shared];
    [coordinator hideOwnedChromeForExpandedPlatterInOverlay:overlay];
    if (gEditModeActive) [coordinator dismissEditingImmediately];
    if (expandedController) [coordinator applyResizedPresentationToModule:expandedController];
    [coordinator setQuickAccessButtonsHidden:YES forOverlay:overlay animated:YES];
    %orig;
    if (openingConnectivity) {
        __weak UIViewController *weakOverlay = overlay;
        void (^applyLivePresentation)(BOOL) = ^(BOOL beginReveal) {
            UIViewController *strongOverlay = weakOverlay;
            UIViewController *presented = strongOverlay.presentedViewController;
            if (!presented) return;
            UIPresentationController *presentation = presented.presentationController;
            CGFloat width = CGRectGetWidth(presented.view.bounds);
            if (width < 250.0) width = CGRectGetWidth(UIScreen.mainScreen.bounds) * 0.856;
            CGSize preferred = CGSizeMake(width, CCAConnectivityMetricsForWidth(width).contentHeight);
            presented.preferredContentSize = preferred;
            SEL changed = NSSelectorFromString(@"preferredContentSizeDidChangeForChildContentContainer:");
            if ([presentation respondsToSelector:changed]) ((void (*)(id, SEL, id))objc_msgSend)((id)presentation, changed, presented);
            [presentation.containerView setNeedsLayout];
            [presentation.containerView layoutIfNeeded];
            CCAConfigureConnectivityPresentationContainer(presentation);
            CCAApplyExpandedPlatterRadius(presentation);
            // The first pass establishes the final presentation geometry. Let
            // the child labeled controls complete another run-loop layout
            // before capturing the reveal image.
            if (beginReveal) CCAStartConnectivityOpeningReveal(presentation);

        };
        // The presentation controller is normally available synchronously
        // after %orig. Suppress its stock backing before Core Animation commits
        // the first expansion frame; the next-turn pass remains as a fallback
        // for the occasional lazily-created presentation hierarchy.
        applyLivePresentation(NO);
        dispatch_async(dispatch_get_main_queue(), ^{
            applyLivePresentation(NO);
            // Keep laying out invisibly while UIKit presents. The transition
            // controller's presentationTransitionDidEnd: callback performs the
            // actual capture only after every child has reached final geometry.
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.035 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ applyLivePresentation(NO); });
        });
    }
    // Expansion reparents portions of the module hierarchy during the opening
    // transition. Reassert on the next turn so no edit ring or preview backing
    // survives behind the platter after that reparenting completes.
    dispatch_async(dispatch_get_main_queue(), ^{
        [coordinator hideOwnedChromeForExpandedPlatterInOverlay:overlay];
    });
}

- (void)moduleCollectionViewController:(id)collection didCloseExpandedModule:(id)module {
    UIViewController *overlay = (UIViewController *)(id)self;
    %orig;
    // Restore the selected page before clearing expanded state or updating any
    // overlay chrome. Deferring this to the next run-loop turn let page-zero
    // geometry render for one frame after every later-page dismissal.
    CCARestoreExpansionPageGeometrySync(overlay);
    NSString *closingIdentifier = [CCAIdentifierFromObject(module) copy];
    BOOL closingMedia = [closingIdentifier isEqualToString:@"com.apple.mediaremote.controlcenter.nowplaying"] ||
        [NSStringFromClass([module class]) isEqualToString:@"MediaControlsModule"];
    UIViewController *closingConnectivity = gCCAConnectivityTransitionController;
    gCCAExpandedModuleOpen = NO;
    gCCAExpandedModuleClosingActive = NO;
    gCCAConnectivityExpansionActive = NO;
    gCCAExpandedModuleIdentifier = nil;
    if (closingConnectivity) CCAFinishConnectivityClosingTransition(closingConnectivity);
    CCAsterCoordinator *coordinator = [CCAsterCoordinator shared];
    UIView *pageIndicators = [overlay.view viewWithTag:kCCAPageIndicatorHostTag];
    if (pageIndicators) {
        objc_setAssociatedObject(pageIndicators, kCCAPageIndicatorDraggingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        BOOL revealActive = CCAExpandedChromeRevealActive();
        pageIndicators.hidden = gCCAPageCount <= 1 || !gCCAControlCenterPresented;
        if (!revealActive) pageIndicators.alpha = pageIndicators.hidden ? 0.0 : 1.0;
    }
    [coordinator setQuickAccessButtonsHidden:(gEditModeActive || !gCCAControlCenterPresented) forOverlay:overlay animated:!CCAExpandedChromeRevealActive()];
    [coordinator updateTopFadeForOverlay:overlay presentationAlpha:gCCAControlCenterPresented ? 1.0 : 0.0];
    [coordinator animateOwnedDuplicateHostForOverlay:overlay presented:gCCAControlCenterPresented];
    for (UIViewController *candidate in CCACollectModuleControllers(overlay)) {
        [coordinator applyRefinedLookToModule:candidate];
        [coordinator applyTransitionRadiusToModule:candidate];
    }
    [coordinator updatePageIndicatorsForOverlay:overlay];
    if (gCCAExpansionHiddenLiveViews.count || gCCAExpansionExpandedSnapshot) {
        gCCAExpansionDismissalDidClose = YES;
        CCACompleteGenericExpansionDismissalIfReady();
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        if (closingMedia) CCARestoreCompactMediaLayout(overlay, module, YES);
        [coordinator updatePageIndicatorsForOverlay:overlay];
    });
    // Give the legit closing choreography time to finish, then scrub any
    // leftover transition state so the next expansion starts clean.
    __weak UIViewController *weakOverlay = overlay;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!gCCAExpandedModuleOpen) CCAResetConnectivityExpansionState(weakOverlay);
    });
}

%end

%end

%group CCAExpandedModuleWillCloseCallback

%hook CCUIModuleCollectionViewController

- (void)contentModuleContainerViewController:(id)container willCloseExpandedModule:(id)module {
    UIViewController *overlay = ((UIViewController *)(id)self).parentViewController;
    while (overlay && !CCAIsOverlayController(overlay)) overlay = overlay.parentViewController;
    UIViewController *expandedController = overlay ? CCAModuleControllerMatchingObject(overlay, module) : nil;
    // This concrete collection callback is guaranteed on iOS 16 even though
    // the overlay delegate does not implement its optional will-close method.
    UIViewController *containerController = [container isKindOfClass:[UIViewController class]] ? (UIViewController *)container : expandedController;
    if (overlay) CCAApplyExpansionPageGeometrySync(overlay);
    gCCAExpandedModuleClosingActive = YES;
    if (overlay && !gCCAControlCenterPresented) {
        [[CCAsterCoordinator shared] animateOwnedDuplicateHostForOverlay:overlay presented:NO];
    } else if (overlay) {
        [[CCAsterCoordinator shared] animateOwnedDuplicateHostForOverlay:overlay presented:YES];
    }
    for (UIViewController *candidate in CCACollectModuleControllers(overlay)) {
        [[CCAsterCoordinator shared] applyRefinedLookToModule:candidate];
        [[CCAsterCoordinator shared] applyTransitionRadiusToModule:candidate];
    }
    if (expandedController) [[CCAsterCoordinator shared] applyTransitionRadiusToModule:expandedController];
    if (containerController) [[CCAsterCoordinator shared] applyTransitionRadiusToModule:containerController];
    if (expandedController) [[CCAsterCoordinator shared] applyClosingCompactRadiusToModule:expandedController overlay:overlay sourceObject:module];
    if (containerController) [[CCAsterCoordinator shared] applyClosingCompactRadiusToModule:containerController overlay:overlay sourceObject:module];
    if (overlay) [[CCAsterCoordinator shared] setQuickAccessButtonsHidden:YES forOverlay:overlay animated:YES];
    if (overlay) [[CCAsterCoordinator shared] updatePageIndicatorsForOverlay:overlay];
    BOOL closingMedia = [NSStringFromClass([module class]) isEqualToString:@"MediaControlsModule"] ||
        [[CCAIdentifierFromObject(module) copy] isEqualToString:@"com.apple.mediaremote.controlcenter.nowplaying"];
    if (closingMedia && overlay) {
        // Freeze the expanded presentation exactly where it is, then return
        // the live hierarchy to compact layout before Apple's own reverse
        // transition starts. CCUI's animator retains ownership of the
        // anchor-to-grid geometry for every supported module size.
        CCABeginCompactMediaDismissalProxy(overlay, module);
        CCARestoreCompactMediaLayout(overlay, module, NO);
        CCAAttachCompactMediaSnapshotToNativeTransition();
    }
    %orig;
    if (closingMedia && overlay) {
        CCAFadeExpandedMediaDismissalSnapshot();
    }
    CCAsterCoordinator *coordinator = [CCAsterCoordinator shared];
    NSString *closingIdentifier = [CCAModuleIdentifier(expandedController) copy] ?: [CCAIdentifierFromObject(module) copy];
    for (NSNumber *delay in @[@0.0, @0.04, @0.08, @0.14, @0.22, @0.34, @0.5, @0.7]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIViewController *settled = closingIdentifier.length ? nil : expandedController;
            for (UIViewController *candidate in CCACollectModuleControllers(overlay)) {
                if ([CCAModuleIdentifier(candidate) isEqualToString:closingIdentifier]) { settled = candidate; break; }
            }
            if (settled) {
                [coordinator applyRefinedLookToModule:settled];
                [coordinator applyTransitionRadiusToModule:settled];
                [coordinator applyClosingCompactRadiusToModule:settled overlay:overlay sourceObject:module];
            }
            if (containerController.view.window) {
                [coordinator applyTransitionRadiusToModule:containerController];
                [coordinator applyClosingCompactRadiusToModule:containerController overlay:overlay sourceObject:module];
            }
        });
    }
}

%end

%end

static void CCAPrefsChanged(__unused CFNotificationCenterRef center, __unused void *observer, __unused CFStringRef name, __unused const void *object, __unused CFDictionaryRef userInfo) {
    CCALoadPrefs();
    dispatch_async(dispatch_get_main_queue(), ^{
        CCAsterCoordinator *coordinator = [CCAsterCoordinator shared];
        [coordinator setEditing:NO];
        for (UIViewController *overlay in gOverlayControllers.allObjects) {
            [coordinator installQuickAccessHostOnOverlay:overlay];
            BOOL hideQuickAccess = !gEnabled || !gQuickAccessButtonsEnabled || !gCCAControlCenterPresented || gCCAExpandedModuleOpen;
            [coordinator setQuickAccessButtonsHidden:hideQuickAccess forOverlay:overlay animated:NO];
            [coordinator installPagingOnOverlay:overlay];
            for (UIViewController *module in CCACollectModuleControllers(overlay)) [coordinator applyRefinedLookToModule:module];
        }
    });
}

%ctor {
    @autoreleasepool {
        CCALoadPrefs();
        // Master switch — the definitive, future-proof disable. With CCAster
        // off we install no hooks, register no observers, and allocate nothing,
        // so SpringBoard behaves exactly as if the tweak were not present. Every
        // current and future feature is covered automatically because nothing
        // below this line runs. (Toggling the master switch needs a respring to
        // fully take effect, since hooks can't be uninstalled live.)
        if (!gEnabled) return;
        %init(_ungrouped);
        gOverlayControllers = [NSHashTable weakObjectsHashTable];
        gCCANativeLayoutRects = [NSMutableDictionary dictionary];
        gCCABaseLayoutSizes = [NSMutableDictionary dictionary];
        gCCAConnectivityOptimisticStates = [NSMutableDictionary dictionary];
        CFPropertyListRef savedOrigins = CFPreferencesCopyAppValue(CFSTR("ModuleGridOrigins"), kCCAPrefsDomain);
        gCCACustomOrigins = [(__bridge NSDictionary *)savedOrigins mutableCopy] ?: [NSMutableDictionary dictionary];
        if (savedOrigins) CFRelease(savedOrigins);
        CFPropertyListRef savedSizes = CFPreferencesCopyAppValue(CFSTR("ModuleGridSizes"), kCCAPrefsDomain);
        gCCACustomSizes = [(__bridge NSDictionary *)savedSizes mutableCopy] ?: [NSMutableDictionary dictionary];
        if (savedSizes) CFRelease(savedSizes);
        CFPropertyListRef savedDuplicates = CFPreferencesCopyAppValue(CFSTR("COSMICDuplicateFamilies"), kCCAPrefsDomain);
        gCCADuplicateFamilies = [(__bridge NSDictionary *)savedDuplicates mutableCopy] ?: [NSMutableDictionary dictionary];
        if (savedDuplicates) CFRelease(savedDuplicates);
        // Connectivity is fixed at Apple's native 2x2 size. Remove builds'
        // stale 4x2 override without disturbing the user's chosen grid origin.
        if (gCCACustomSizes[@"com.apple.control-center.ConnectivityModule"]) {
            [gCCACustomSizes removeObjectForKey:@"com.apple.control-center.ConnectivityModule"];
            CFPreferencesSetAppValue(CFSTR("ModuleGridSizes"), (__bridge CFPropertyListRef)[gCCACustomSizes copy], kCCAPrefsDomain);
            CFPreferencesAppSynchronize(kCCAPrefsDomain);
        }
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, CCAPrefsChanged, (__bridge CFStringRef)kCCAReloadNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        Class overlayClass = NSClassFromString(@"CCUIModularControlCenterOverlayViewController");
        SEL willOpen = NSSelectorFromString(@"moduleCollectionViewController:willOpenExpandedModule:");
        SEL didClose = NSSelectorFromString(@"moduleCollectionViewController:didCloseExpandedModule:");
        Class controlCenterClass = NSClassFromString(@"SBControlCenterController");
        SEL presentationStateChanged = NSSelectorFromString(@"controlCenterViewController:didChangePresentationState:");
        if (controlCenterClass && class_getInstanceMethod(controlCenterClass, presentationStateChanged)) {
            %init(CCAPresentationStateCallbacks);
        }
        if (overlayClass && class_getInstanceMethod(overlayClass, willOpen) && class_getInstanceMethod(overlayClass, didClose)) {
            %init(CCAExpandedModuleCallbacks);
        }
        Class collectionClass = NSClassFromString(@"CCUIModuleCollectionViewController");
        SEL collectionWillClose = NSSelectorFromString(@"contentModuleContainerViewController:willCloseExpandedModule:");
        if (collectionClass && class_getInstanceMethod(collectionClass, collectionWillClose)) {
            %init(CCAExpandedModuleWillCloseCallback);
        }
        Class detailPresentationClass = NSClassFromString(@"CCUIContentModuleDetailPresentationController");
        if (detailPresentationClass && class_getInstanceMethod(detailPresentationClass, @selector(containerViewWillLayoutSubviews))) {
            %init(CCAExpandedPlatterRadius);
        }
        Class clickAssistantClass = NSClassFromString(@"_UIClickPresentationAssistant");
        SEL dismissalSelector = NSSelectorFromString(@"_animateDismissalIsInterruption:");
        if (clickAssistantClass && class_getInstanceMethod(clickAssistantClass, dismissalSelector)) {
            %init(CCAExpandedModuleClickAssistant);
        }
    }
}
