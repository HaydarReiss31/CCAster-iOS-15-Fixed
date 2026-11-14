#!/usr/bin/env python3
# Usage: python3 patch_landscape.py Tweak.xm
import sys

path = sys.argv[1] if len(sys.argv) > 1 else "Tweak.xm"
src = open(path, encoding="utf-8").read()
if "CCASyncLandscapeState" in src:
    print("Zaten yamali.")
    sys.exit(0)


def rep(old, new):
    global src
    n = src.count(old)
    if n != 1:
        print("HATA: anchor %d kez bulundu:\n%s" % (n, old[:140]))
        sys.exit(1)
    src = src.replace(old, new)


# 1) Native scroll baseline: landscape'de yakalama / geri yukleme yapma
rep(r'''    UIScrollView *scrollView = CCANativeScrollViewForOverlay(overlay);
    if (!scrollView) return nil;
    baseline = [NSValue valueWithCGPoint:scrollView.contentOffset];''',
    r'''    UIScrollView *scrollView = CCANativeScrollViewForOverlay(overlay);
    if (!scrollView) return nil;
    if (overlay.view && CCAIsLandscapeOrientation(overlay.view)) return nil;
    baseline = [NSValue valueWithCGPoint:scrollView.contentOffset];''')

rep(r'''static void CCARestoreNativeScrollBaseline(UIViewController *overlay) {
    UIScrollView *scrollView = CCANativeScrollViewForOverlay(overlay);''',
    r'''static void CCARestoreNativeScrollBaseline(UIViewController *overlay) {
    if (overlay.view && CCAIsLandscapeOrientation(overlay.view)) return;
    UIScrollView *scrollView = CCANativeScrollViewForOverlay(overlay);''')

# 2) Compact grid ayarini landscape layout options'a uygulama
rep(r'''    if (!gEnabled || !layoutOptions) return;
    Ivar spacingIvar''',
    r'''    if (!gEnabled || !layoutOptions) return;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    if (UIInterfaceOrientationIsLandscape(UIApplication.sharedApplication.statusBarOrientation)) return;
#pragma clang diagnostic pop
    Ivar spacingIvar''')

# 3) normalize: landscape'de layout'a dokunma
rep(r'''    gPagingEnabled = gPagingPreferenceEnabled && !CCAIsLandscapeOrientation(overlay.view);
    [self syncOwnedDuplicateModulesForOverlay:overlay];''',
    r'''    BOOL cca_landscape = CCAIsLandscapeOrientation(overlay.view);
    gPagingEnabled = gPagingPreferenceEnabled && !cca_landscape;
    if (cca_landscape) {
        gCCACurrentPage = 0;
        [self updatePageIndicatorsForOverlay:overlay];
        return;
    }
    [self syncOwnedDuplicateModulesForOverlay:overlay];''')

# 4) Sayfa gorunurlugu: landscape'de tum moduller gorunsun
rep(r'''- (void)updatePagedModuleVisibilityForOverlay:(UIViewController *)overlay showAdjacent:(BOOL)showAdjacent {
    if (!overlay || gCCAExpandedModuleOpen) return;''',
    r'''- (void)updatePagedModuleVisibilityForOverlay:(UIViewController *)overlay showAdjacent:(BOOL)showAdjacent {
    if (!overlay || gCCAExpandedModuleOpen) return;
    if (CCAIsLandscapeOrientation(overlay.view)) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        for (UIViewController *module in CCACollectModuleControllers(overlay)) {
            objc_setAssociatedObject(module.view, kCCAPageHiddenKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            module.view.layer.opacity = 1.0f;
        }
        [CATransaction commit];
        return;
    }''')

rep(r'''- (void)settlePagedModuleVisibilityForOverlay:(UIViewController *)overlay animated:(BOOL)animated token:(id)token {
    if (!overlay || gCCAExpandedModuleOpen) return;''',
    r'''- (void)settlePagedModuleVisibilityForOverlay:(UIViewController *)overlay animated:(BOOL)animated token:(id)token {
    if (!overlay || gCCAExpandedModuleOpen) return;
    if (CCAIsLandscapeOrientation(overlay.view)) {
        [self updatePagedModuleVisibilityForOverlay:overlay showAdjacent:NO];
        return;
    }''')

# 5) Owned duplicate host: landscape'de gizle
rep(r'''- (void)layoutOwnedDuplicateModulesForOverlay:(UIViewController *)overlay {
    UIView *host = [overlay.view viewWithTag:kCCAOwnedDuplicateHostTag];
    if (!host) return;''',
    r'''- (void)layoutOwnedDuplicateModulesForOverlay:(UIViewController *)overlay {
    UIView *host = [overlay.view viewWithTag:kCCAOwnedDuplicateHostTag];
    if (!host) return;
    if (CCAIsLandscapeOrientation(overlay.view)) {
        host.hidden = YES;
        host.alpha = 0.0;
        return;
    }''')

rep(r'''    UIView *host = [overlay.view viewWithTag:kCCAOwnedDuplicateHostTag];
    if (!host) return;
    CGFloat clamped = MIN(1.0, MAX(0.0, alpha));''',
    r'''    UIView *host = [overlay.view viewWithTag:kCCAOwnedDuplicateHostTag];
    if (!host) return;
    if (CCAIsLandscapeOrientation(overlay.view)) {
        host.hidden = YES;
        host.alpha = 0.0;
        return;
    }
    CGFloat clamped = MIN(1.0, MAX(0.0, alpha));''')

# 6) Sayfa transform'u: landscape'de native transform'a don
rep(r'''- (void)applyPageTransformToOverlay:(UIViewController *)overlay animated:(BOOL)animated {
    UIViewController *collection = [self moduleCollectionControllerInOverlay:overlay];
    if (!collection.view) return;''',
    r'''- (void)applyPageTransformToOverlay:(UIViewController *)overlay animated:(BOOL)animated {
    UIViewController *collection = [self moduleCollectionControllerInOverlay:overlay];
    if (!collection.view) return;
    if (CCAIsLandscapeOrientation(overlay.view)) {
        [self capturePresentationStateForView:collection.view];
        CGAffineTransform nativeBase = [objc_getAssociatedObject(collection.view, kCCAOriginalTransformKey) CGAffineTransformValue];
        CATransform3D nativeSublayerBase = [objc_getAssociatedObject(collection.view, kCCAOriginalSublayerTransformKey) CATransform3DValue];
        [collection.view.layer removeAnimationForKey:@"CCAsterPageStackSlide"];
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        collection.view.transform = nativeBase;
        collection.view.layer.sublayerTransform = nativeSublayerBase;
        [CATransaction commit];
        return;
    }''')

rep(r'''- (void)applyRestingModuleOffsetToOverlay:(UIViewController *)overlay {
    if (!overlay || gEditModeActive) return;''',
    r'''- (void)applyRestingModuleOffsetToOverlay:(UIViewController *)overlay {
    if (!overlay || gEditModeActive) return;
    if (overlay.view && CCAIsLandscapeOrientation(overlay.view)) {
        [self applyPageTransformToOverlay:overlay animated:NO];
        return;
    }''')

# 7) Landscape durum degisimi senkronizasyonu
rep(r'''%hook CCUIModuleCollectionViewController

- (CCUILayoutSize)moduleLayoutSizeForContentModuleContext''',
    r'''static BOOL gCCALastLandscapeState = NO;

static void CCASyncLandscapeState(UIViewController *overlay) {
    if (!overlay.view) return;
    BOOL landscape = CCAIsLandscapeOrientation(overlay.view);
    gPagingEnabled = gPagingPreferenceEnabled && !landscape;
    if (landscape == gCCALastLandscapeState) return;
    gCCALastLandscapeState = landscape;
    CCAsterCoordinator *coordinator = [CCAsterCoordinator shared];
    if (landscape && gEditModeActive) [coordinator dismissEditingImmediately];
    // installPagingOnOverlay: landscape'de sayfayi 0'a ceker, transformu native'e
    // dondurur, tum modulleri gorunur yapar; portrait'e donuste paging'i geri kurar.
    [coordinator installPagingOnOverlay:overlay];
    [overlay.view setNeedsLayout];
}

%hook CCUIModuleCollectionViewController

- (CCUILayoutSize)moduleLayoutSizeForContentModuleContext''')

rep(r'''    if (identifier.length && !gCCABaseLayoutSizes[identifier]) gCCABaseLayoutSizes[identifier] = [NSValue value:&size withObjCType:@encode(CCUILayoutSize)];''',
    r'''    if (identifier.length && !gCCABaseLayoutSizes[identifier] && !UIInterfaceOrientationIsLandscape((UIInterfaceOrientation)orientation)) gCCABaseLayoutSizes[identifier] = [NSValue value:&size withObjCType:@encode(CCUILayoutSize)];''')

rep(r'''        if (!gCCABaseLayoutSizes[identifier]) gCCABaseLayoutSizes[identifier] = [NSValue value:&rect.size withObjCType:@encode(CCUILayoutSize)];
        gCCANativeLayoutRects[identifier] = [NSValue value:&rect withObjCType:@encode(CCUILayoutRect)];''',
    r'''        // Landscape'in native rect/size degerleri portrait grid state'ini bozmasin.
        if (!CCAIsLandscapeOrientation(subview)) {
            if (!gCCABaseLayoutSizes[identifier]) gCCABaseLayoutSizes[identifier] = [NSValue value:&rect.size withObjCType:@encode(CCUILayoutSize)];
            gCCANativeLayoutRects[identifier] = [NSValue value:&rect withObjCType:@encode(CCUILayoutRect)];
        }''')

# 8) Collection view: landscape'de native scroll'a karisma
rep(r'''    %orig;
    if (!gEnabled) return;
    UIScrollView *scrollView = (UIScrollView *)(id)self;''',
    r'''    %orig;
    if (!gEnabled || CCAIsLandscapeOrientation((UIView *)(id)self)) return;
    UIScrollView *scrollView = (UIScrollView *)(id)self;''')

rep(r'''    if (gEnabled) {
        CGFloat containerWidth = CGRectGetWidth(((UIView *)(id)self).window.bounds);''',
    r'''    if (gEnabled && !CCAIsLandscapeOrientation((UIView *)(id)self)) {
        CGFloat containerWidth = CGRectGetWidth(((UIView *)(id)self).window.bounds);''')

# 9) Overlay layout'unda landscape senkronu
rep(r'''- (void)viewDidLayoutSubviews {
    %orig;
    if (gEnabled && CCAIsOverlayController(self) && gCCAControlCenterPresented) {''',
    r'''- (void)viewDidLayoutSubviews {
    %orig;
    if (gEnabled && CCAIsOverlayController(self)) CCASyncLandscapeState(self);
    if (gEnabled && CCAIsOverlayController(self) && gCCAControlCenterPresented) {''')

# 10) Landscape'te CCUILayoutOptions'i native boyuta dondur, portrait'te compact'a geri al
rep(r"""static void CCAApplyCompactGridSpacingToLayoutOptions(id layoutOptions) {
    if (!gEnabled || !layoutOptions) return;""",
    r"""static CGFloat gCCANativeGridCell = 0.0;
static CGFloat gCCANativeGridGap = 0.0;

static void CCAApplyCompactGridSpacingToLayoutOptions(id layoutOptions) {
    if (!gEnabled || !layoutOptions) return;""")

rep(r"""    if (!alreadyCompact) {
        if (nativeCell > 1.0) kCCAGridCellSize = round(nativeCell * kCCAGridCellScale);""",
    r"""    if (!alreadyCompact) {
        if (nativeCell > 1.0) gCCANativeGridCell = nativeCell;
        if (nativeGap > 1.0) gCCANativeGridGap = nativeGap;
        if (nativeCell > 1.0) kCCAGridCellSize = round(nativeCell * kCCAGridCellScale);""")

rep(r"""%hook CCUIModuleCollectionView

- (instancetype)initWithFrame:(CGRect)frame layoutOptions:(id)layoutOptions {""",
    r"""// Landscape'te Apple'in kendi hucre/bosluk boyutlari, portrait'te CCAster'in compact boyutlari.
static void CCASyncGridSpacingForCollectionView(UIView *collectionView) {
    if (!gEnabled || !collectionView) return;
    id layoutOptions = nil;
    @try { layoutOptions = [(id)collectionView valueForKey:@"layoutOptions"]; } @catch (__unused NSException *exception) {}
    if (!layoutOptions) return;
    Ivar spacingIvar = class_getInstanceVariable([layoutOptions class], "_itemSpacing");
    Ivar edgeIvar = class_getInstanceVariable([layoutOptions class], "_itemEdgeSize");
    if (!spacingIvar || !edgeIvar) return;
    uint8_t *bytes = (uint8_t *)(__bridge void *)layoutOptions;
    CGFloat *gapPtr = (CGFloat *)(bytes + ivar_getOffset(spacingIvar));
    CGFloat *cellPtr = (CGFloat *)(bytes + ivar_getOffset(edgeIvar));
    BOOL landscape = CCAIsLandscapeOrientation(collectionView);
    CGFloat wantCell, wantGap;
    if (landscape) {
        if (gCCANativeGridCell <= 1.0 || gCCANativeGridGap <= 1.0) return;
        wantCell = gCCANativeGridCell;
        wantGap = gCCANativeGridGap;
    } else {
        wantCell = kCCAGridCellSize;
        wantGap = kCCAGridGap;
    }
    if (fabs(*cellPtr - wantCell) < 0.01 && fabs(*gapPtr - wantGap) < 0.01) return;
    *cellPtr = wantCell;
    *gapPtr = wantGap;
    [collectionView setNeedsLayout];
}

%hook CCUIModuleCollectionView

- (instancetype)initWithFrame:(CGRect)frame layoutOptions:(id)layoutOptions {""")

rep(r"""- (void)layoutSubviews {
    %orig;
    if (!gEnabled || CCAIsLandscapeOrientation((UIView *)(id)self)) return;
    UIScrollView *scrollView = (UIScrollView *)(id)self;""",
    r"""- (void)layoutSubviews {
    CCASyncGridSpacingForCollectionView((UIView *)(id)self);
    %orig;
    if (!gEnabled || CCAIsLandscapeOrientation((UIView *)(id)self)) return;
    UIScrollView *scrollView = (UIScrollView *)(id)self;""")

open(path, "w", encoding="utf-8").write(src)
print("Tamam: %s yamalandi." % path)
