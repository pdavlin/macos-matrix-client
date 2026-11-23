# Indigo visual flair: static analysis notes

## Target and method

- Path: `/Applications/Indigo.app`, bundle id `com.soapboxsoftware.indigo`, version 1.4.2 (build 513), LSMinimumSystemVersion 26.0.
- Main binary: `Contents/MacOS/Indigo`, SHA-256 `dca26db1f5b36238a9b29b9fca0d154ab01414b3a98d849ac0e012711d1175ef`.
- Helper: `Contents/PlugIns/IndigoAppKit.bundle/Contents/MacOS/IndigoAppKit`, SHA-256 `b2e48acb5f3f4da680e66b7c4c7344984382d8dcb6bdae164a57b4992e4625ff`.
- Date: 2026-11-18.
- Method: static only. Indigo was not launched. No debugger, no Frida, no screenshots.

### REA status and evidence sources

- REA `open_binary` on the main binary returned the SHA-256 above. Hopper then timed out after 120 s during its first analysis of the 69 MB binary. REA reported `cleanup_incomplete` and then refused all later calls (`inspect_macho`, `inspect_plist`, `inspect_asset_catalog`, `demangle_swift`). `close_binary` failed three times with the same error.
- Result: no REA Evidence IDs and no decompilation. Every claim below rests on these local tool outputs instead:
  - E1 `nm -u -arch arm64` imports, demangled with `swift-demangle --simplified`. Saved as `indigo-evidence/imports-demangled.tsv` (8374 symbols, 2112 SwiftUI).
  - E2 `strings -a -arch arm64` on the main binary (241,344 lines). Swift type names, field names (reflection strings) and ObjC selectors come from here.
  - E3 `indigo-evidence/indigo_types.txt`: 1174 type names that sit next to the `Indigo` module name in the type-descriptor string block.
  - E4 `xcrun assetutil --info Assets.car`, saved as `indigo-evidence/assets.json`.
  - E5 `otool -l` (LC_BUILD_VERSION) and `otool -L`, plus `Info.plist`.
- The binary is stripped (0 defined symbols). Procedure names and constants are not recoverable without a disassembler.

### The most important fact: Indigo is a Mac Catalyst app

- LC_BUILD_VERSION `platform 6` (MACCATALYST), minos 26.0, sdk 27.0 (E5). OBSERVED.
- Imports include `UIWindowSceneGeometryPreferencesMac`, `UICollectionViewCompositionalLayout`, `UIGlassEffect`, `UIScrollEdgeEffectStyle` (E1). OBSERVED.
- `IndigoAppKit.bundle` is a macOS-platform (`platform 1`) helper. It imports only `NSView`, `NSWindow`, `NSUserDefaults`, `NSNotificationCenter`. Its strings show `centerWindowButtonsOf:onX:`, `WindowButtonPin`, `performWindowDragWithEvent:`, `AppleActionOnDoubleClick`, `observeWindowLiveResize:`. It moves the traffic-light buttons, gives window drag on custom chrome, follows the system double-click setting, and watches live resize. It draws nothing. OBSERVED.
- Consequence for Mactrix: most of Indigo's look is UIKit plus SwiftUI on Catalyst. Mactrix is native AppKit plus SwiftUI. The techniques move over. The class names (UIGlassEffect, UICollectionView) do not.

### Attribution caveat

Swift packages are statically linked (CroissantComposer, CroissantPreferences, RicePaywallKit, RevenueCat, SDWebImage, Nuke, Highlightr, Sentry). An imported SwiftUI symbol proves that some code in the binary uses it. It does not prove that Indigo's own views use it. Where an Indigo-module type name or field name backs the use, the note says so.

## 1. Materials and glass

| Finding | Evidence | Confidence |
|---|---|---|
| SwiftUI Liquid Glass API set in use: `View.glassEffect(_:in:)`, `GlassEffectContainer(spacing:content:)`, `View.glassEffectID(_:in:)`, `View.glassEffectUnion(id:namespace:)`, `View.glassEffectTransition(_:)`, `GlassEffectTransition.matchedGeometry`, `Glass.regular`, `Glass.tint(_:)`, `Glass.interactive(_:)`, `DefaultGlassEffectShape` | E1 | OBSERVED |
| Glass button styles: `GlassButtonStyle`, `GlassProminentButtonStyle`, plus Indigo's own `GlassOrBorderedButtonStyle` and `PlatformAgnosticBorderedButtonStyle` (fallback to bordered) | E1, E3 | OBSERVED (imports), INFERRED (fallback purpose from name) |
| The main tab shell owns a glass namespace and spacing: fields `_glassNamespace`, `glassSpacing`, `bubbleSize`, `__haptics`, next to `unreadNotificationCount`, `unreadMessageCount`, `orderedTabs`. A second view has `__restingGlassCornerRadius`, `__highlightedTab`, `__lastDragChangeTime`, `tabBarDownwardOffset`, `_geometryNamespace`. This looks like a custom glass tab bar with morphing bubbles and drag-to-select tabs, built with `GlassEffectContainer` + `glassEffectID` | E2 | INFERRED |
| Glass in the composer and toolbar: `GlassComposeView`, `SeparateGlassToolbarItem`, `ToolbarItemsStayInPlace`, `TitlebarToolbarConfigurator` (Indigo module) | E3 | INFERRED (names) |
| UIKit glass: `UIGlassEffect`, `UIVisualEffectView`, `UIBlurEffect`, `effectWithStyle:`, `setEffect:` | E1, E2 | OBSERVED |
| SwiftUI materials: `Material.ultraThin`, `.regular`, `.thick`, `.bar` | E1 | OBSERVED (users not attributed) |
| Scroll edge effects: SwiftUI `scrollEdgeEffectStyle(_:for:)` with `ScrollEdgeEffectStyle.soft` and `.hard`, `scrollEdgeEffectHidden(_:for:)`; UIKit `UIScrollEdgeEffectStyle`, `topEdgeEffect`, `bottomEdgeEffect`. Indigo has its own `ScrollEdgePreference` and `PreferredScrollEdgeEffectStyle` types, so screens pass their wanted edge style up through a SwiftUI preference key | E1, E2, E3 | OBSERVED (API), INFERRED (preference-key design) |
| `toolbarBackground(_:for:)` and `toolbarBackgroundVisibility(_:for:)` | E1 | OBSERVED |
| `backgroundExtensionEffect` | not in E1 | NOT FOUND (could be inlined, but generic SwiftUI modifiers normally show up as imports) |
| `NSVisualEffectView`, `NSGlassEffectView` | not in E1 or the AppKit bundle | NOT FOUND (expected for Catalyst) |
| Ramped blur: `CroissantComposer.RampedBlurView` and `StripBlurBackdrop` (file `CroissantComposer/StripBlurBackdrop.swift`). Fields `rampHeight`, `gradientMask`, `Coordinator`, `UIViewType`. A `UIViewRepresentable` blur strip whose strength fades through a gradient mask. No private CAFilter `variableBlur` strings exist, so it is a normal blur view plus a gradient mask layer | E2 | INFERRED |
| Tab bar blur at the edge: `TabBarBlurEdgePeriod` near `PhoneBaseView` | E3 | INFERRED (iPhone layout) |
| Column chrome: `TopChrome`, `ColumnEdgeFade`, `MacColumnBarEdgeFade`, `ElevatedBackgroundFill`. Edges of timeline columns fade instead of a hard cut | E3 | INFERRED |
| Live-resize blur: field `liveResizeBlur` next to `baseBackground`, `topChrome`, `column`, `pagingPan`, `header`, `navigationBar`, `windowToolbar`; also `liveResizeAnchor`, `liveResizeRestoration`, `liveResizeSettle`. The AppKit helper has `observeWindowLiveResize:`. The column blurs while the window resizes, keeps a scroll anchor, and settles after the resize ends | E2 | INFERRED |

Where: glass and blur names cluster on tab bar, toolbar, composer and column chrome. The timeline cells (`UIKitTimelinePostCell` and friends) carry no glass names. Confidence: INFERRED.

## 2. Animation

| Finding | Evidence | Confidence |
|---|---|---|
| Springs: `Animation.spring(response:dampingFraction:blendDuration:)`, `Spring(duration:bounce:)`, and also `Spring.value(target:initialVelocity:time:)` and `Spring.settlingDuration(...)`. The last two mean code evaluates a spring by hand, frame by frame. With `CADisplayLink` and `setPreferredFrameRateRange:` in the same binary, this points to a hand-driven spring for paging or the drawer | E1, E2 | OBSERVED (API), INFERRED (frame driver) |
| UIKit springs: `animateWithDuration:delay:usingSpringWithDamping:initialSpringVelocity:options:animations:completion:` | E2 | OBSERVED |
| Other curves: `.easeInOut`, `.easeOut(duration:)`, `.linear`, `.default`, `Animation.delay`, `Animation.speed`; `withAnimation(_:completionCriteria:_:completion:)` with `.logicallyComplete`; `Transaction.disablesAnimations` | E1 | OBSERVED |
| Spring constants (response, damping, bounce values) | needs decompilation | UNKNOWN |
| `matchedGeometryEffect` (`_MatchedGeometryEffect`, `MatchedGeometryProperties.frame`) | E1 | OBSERVED |
| Zoom transitions: `NavigationTransition.zoom(sourceID:in:)`, `matchedTransitionSource(id:in:)`, `ZoomNavigationTransition`. Indigo types `CaptureTimelineZoomNamespace`, `MediaZoomSourceID`, `MediaWindowZoomableImage`: images zoom from the timeline into the viewer | E1, E3 | OBSERVED (API), INFERRED (use) |
| `contentTransition(.numericText(value:))` and `ContentTransition.identity` | E1 | OBSERVED (likely for counts, see 7) |
| Transitions: `.move(edge:)`, `.push(from:)`, `.opacity`, `.scale`, `.asymmetric`, `Transition.combined(with:)` | E1 | OBSERVED |
| `visualEffect { }` with `VisualEffect.offset` and `VisualEffect.scaleEffect`: geometry-driven scale and offset (for example, cards that shrink as they move) | E1 | OBSERVED |
| `TimelineView` (with `TimelineView.Context`) | E1 | OBSERVED (use unknown) |
| Book-style column paging: `BookPoseLayout`, `BookPoseDivision`, `PageDragOffset`, `PageCorners`, `CarouselScrollView`, `FeedsDrawerLiftingSnapshotView`. Column carousel with a page-turn pose and a drawer that lifts a snapshot of the current page | E3 | INFERRED |
| Paywall shimmer: `RicePaywallKit.MotionShimmerModifier` and `MotionShimmerSource` (uses CoreMotion tilt). Paywall only, not the feed | E2 | INFERRED |
| `PhaseAnimator`, `KeyframeAnimator`, `symbolEffect`, `SymbolEffect` | not in E1 | NOT FOUND |

## 3. Color and gradients

| Finding | Evidence | Confidence |
|---|---|---|
| Asset catalog has no semantic UI palette. Its 37 colors are app-icon layer colors (Black, Blue, Indigo, Purple, Pride, Trans, White icon variants) plus one brand color `mastodon.purple` | E4 | OBSERVED |
| `mastodon.purple` is the only color with a dark variant: any P3 (0.518, 0.329, 0.855), dark P3 (0.639, 0.435, 1.0). The dark variant is lighter and more saturated for contrast | E4 | OBSERVED |
| 11 named gradients, all for app-icon layers (two-stop, top to bottom). None for UI | E4 | OBSERVED |
| App icons ship as Icon Composer layered icons (`IconGroup`, `IconImageStack`) with 7 alternate icons, each with `system-dark` and `system-light` layers | E4 | OBSERVED |
| UI color is user-driven at run time. Preference keys: `appearance-color-scheme`, `appearance-color-palette`, `appearance-text-contrast`, `appearance-light-background`, `appearance-dark-background`, `appearance-tint-color`, with labels "Accent colour name", "Colour palette name", "Text contrast level", "Light mode background colour", "Dark mode background colour". `CroissantPreferences` has `UserTintKey`, `PreferredTint`, `Theme`, `ColorPalette`, `TextContrast`, `LightBackground`, `DarkBackground`, `TintColor` | E2 | OBSERVED (keys), INFERRED (meaning) |
| Tint plumbing: `View.tint(_:)`, `EnvironmentValues.tint`, `TintShapeStyle`, `ListItemTint.fixed`, UIKit `setTintColor:`; `TintedIcon` in Indigo | E1, E2, E3 | OBSERVED |
| `LinearGradient(gradient:startPoint:endPoint:)`, `Gradient(stops:)`, `Gradient.ColorSpace.perceptual` (perceptual interpolation for smoother gradients), `CAGradientLayer` with `setColors:`, `setLocations:`, `setStartPoint:`, `setEndPoint:`; Indigo `PinnedGradientView`, `GradientPoint` | E1, E2 | OBSERVED |
| `MeshGradient`, `AngularGradient`, `RadialGradient`, `Color.gradient` | not in E1 | NOT FOUND |
| `DominantColorView` and `EmbedSourceColor` / `EmbedSourceTheme` / `PostImageCardTheme`: colors taken from images or link sources to theme cards | E3 | INFERRED |
| Blend: `BlendMode.destinationOut` with `compositingGroup` (cut-out shapes, for example an avatar ring cut around a badge); `CALayer setCompositingFilter:`; CIFilter blend modes (most likely SDWebImage tint transformer) | E1, E2 | OBSERVED (API), INFERRED (use) |
| `ThreadPalette` near `ThreadCellDecorationView`: a palette for thread connector lines | E3 | INFERRED |

## 4. Shaders and custom drawing

| Finding | Evidence | Confidence |
|---|---|---|
| No Metal shaders. No `.metallib` in the bundle, no `ShaderLibrary`, `colorEffect`, `layerEffect`, `distortionEffect` imports, no `MTLDevice` or `newLibrary` strings. `libswiftMetal` is linked only by the toolchain (`__swift_FORCE_LOAD_$_swiftMetal`) | E1, E2, find | OBSERVED (absence over these searches) |
| SwiftUI `Canvas(opaque:colorMode:rendersAsynchronously:renderer:)` | E1 | OBSERVED (use unknown) |
| Core Animation: `CAShapeLayer` (`setPath:`, `setFillColor:`, `setLineWidth:`), `CAGradientLayer`, `CADisplayLink`, `CATransaction`; layer shadows with `setShadowPath:` (cheap shadows), `setCornerCurve:` (continuous corners) | E1, E2 | OBSERVED |
| `CAEmitterLayer`, particle effects | not in E1 | NOT FOUND |
| Custom shapes in Indigo: `AsymmetricalRoundedRectangle`, `FeedsDrawerCardShape`, `CropShape`, `AvatarCircle`. `DisplayCornerProbe`, `DisplayCornerProbeView`, `DisplayCornerRadii`: Indigo measures the window or screen corner radius so inner cards stay concentric with it | E3 | INFERRED |
| `drawingGroup` | not in E1 | NOT FOUND (could be inlined) |
| Core Image: `CIGaussianBlur`, `CIColorControls`, `CIColorClamp`, `CIStraightenFilter` (blur hashes, redaction, image edits); `blurhash` placeholders | E2 | OBSERVED |
| Mask helpers: `View.mask`, `_MaskEffect`, `_GrayscaleEffect`, `_ShadowEffect`, `_RotationEffect`, `_ScaleEffect` | E1 | OBSERVED |

## 5. Typography and symbols

| Finding | Evidence | Confidence |
|---|---|---|
| `fontDesign(_:)` on `View` and `Text`; `Font.Design.rounded`, `.monospaced`; `Font.width(_:)`; `Font.system(size:weight:design:)` | E1 | OBSERVED |
| UIKit: `UIFontDescriptorSystemDesignRounded`, `UIFontDescriptorFeatureSettingsAttribute` (OpenType features, for example tabular digits), `UIFontMetrics` (Dynamic Type scaling), all text styles Title1 to Caption2 | E1 | OBSERVED |
| User font size offset: `post-font-size-offset` preference; fields `bodyFontSize`, `fontWeightInt` | E2 | OBSERVED (keys) |
| Symbols: `SymbolRenderingMode.palette`, `UIImageSymbolConfiguration configurationWithPaletteColors:`, `configurationWithTextStyle:scale:`, `configurationWithPointSize:weight:` | E1, E2 | OBSERVED |
| 279 custom vector glyph renditions: brand and action symbols (`bluesky`, `mastodon.fill`, `threads`, `heart.double`, `heart.double.fill`, `repost.circle.fill`, `repost.slash`, `quote.circle.fill`, `bubble.badge`, `glass.icon`, more). Each ships in all 9 weights x 3 sizes, so they follow text weight like system SF Symbols | E4 | OBSERVED |
| Variable-value symbols | no evidence | UNKNOWN |

## 6. Interaction feedback

| Finding | Evidence | Confidence |
|---|---|---|
| SwiftUI `sensoryFeedback(_:trigger:)` and `sensoryFeedback(_:trigger:condition:)` with `.impact`, `.impact(flexibility: .rigid, intensity:)`, `.selection`, `.success` | E1 | OBSERVED |
| UIKit `UIImpactFeedbackGenerator` (`impactOccurredWithIntensity:`, `prepare`), `UISelectionFeedbackGenerator` (`selectionChanged`) | E1, E2 | OBSERVED |
| A haptics setting is read in many views: field `__haptics` in the tab shell, the post action bar (next to `isLiked`, `isReposted`, `tintColor`), notification rows and profile views. `PagingHaptics` in the column carousel ticks on page change | E2, E3 | INFERRED |
| Press states: custom `ButtonStyle` with `ButtonStyleConfiguration.isPressed`; Indigo `MenuRowButtonStyle`, `CatalystSwitchToggleStyle` | E1, E3 | OBSERVED (API) |
| Hover and pointer: no `onHover`, `hoverEffect`, `pointerStyle`, `UIHoverGestureRecognizer`, `UIPointerInteraction`, `NSCursor` | E1, E2 | NOT FOUND |
| `NSHapticFeedbackManager` | not in E1 | NOT FOUND (Catalyst maps UIKit generators) |

## 7. Timeline and feed

| Finding | Evidence | Confidence |
|---|---|---|
| The feed is UIKit: `UICollectionView` with `UICollectionViewCompositionalLayout` and `UICollectionViewListCell`; Indigo cell `UIKitTimelinePostCell` with `PostHeaderTextView`, `PostBannerUIView`, `PostActionBarUIView`, `PostLinkCardUIView`, `AvatarImageView`, `AvatarBadgeUIView`, `RemoteImageView`, `PostAudioMediaUIView`, `TimelineLoadMoreFooterView` | E1, E3 | OBSERVED (classes), INFERRED (composition) |
| Threads: `ThreadCellDecorationView` + `ThreadPalette` + `ThreadCellContext`: connector lines drawn as separate decoration views, colored from a palette | E3 | INFERRED |
| Like and repost: SwiftUI-side `LikeButton`, `RepostButton`, `ReplyButton`, with enum cases `Heart`, `Repost`; fields `isLiked`, `isReposted`, `tintColor`, `__haptics`. A like likely toggles the symbol, tints it, plays a haptic and rolls the count with `.numericText`. The exact animation (scale bounce, spring values) needs decompilation | E2, E3 | INFERRED; animation details UNKNOWN |
| Media grid: fields `imageViews`, `blurViews`, `gifBadges`, `altBadges`, `fullscreenBadges`, `isRedacted`; types `MediaRedactionBlur`, `ModerationBlurTarget`, `ContentBlurBehaviour`, `MediaOverlayBadge`, `AltTextBadge`, `GIFBadge`. Each image gets its own blur view for content warnings and small overlay badges | E2, E3 | INFERRED |
| HDR images: preference `show-hdr-images`, field `_showHDRImages`, selector `setPreferredImageDynamicRange:` | E2 | OBSERVED |
| Avatars: `AvatarCircle`, `AvatarBadge`, `AvatarBadgeDisplayMode` (preference `avatar-badge-display-mode`), `ProfileVerificationBadgeView`, `EmojiBadgeView`; `show-animated-avatars` preference; `AnimatedGIFView` | E2, E3 | OBSERVED (names) |
| Floating capsule over the feed: `TimelineCapsuleView`, `TimelineCapsuleMode`, `ContentFiltersCapsule` (for example a "new posts" pill) | E3 | INFERRED |
| Image loading: SDWebImage, SDWebImageSwiftUI (with `SDWebImageTransition` fades) and Nuke (`rounded_corners`, `gaussian_blur` processors) | E2 | OBSERVED |

## 8. Design system in Indigo's own types

- No single named design-system module (no "DS", "Tokens", "Theme kit") in the Indigo module. Confidence: INFERRED from E3.
- The theme is a set of user preferences in `CroissantPreferences` (`Appearance`, `Theme`, `ColorPalette`, `TextContrast`, `LightBackground`, `DarkBackground`, `TintColor`, `PreferredTint`) read through the environment (`_appearance`, `_postPrefs` fields in many views). OBSERVED (names).
- Layout adapts through an `Adaptive*` family: `AdaptiveSheet`, `AdaptiveStyle`, `AdaptiveScrollView`, `AdaptiveListView`, `AdaptiveNavigationView`, `AdaptiveModifier`, with `PinnedGradientView` and `BackgroundFill` in the same group (likely a small in-house UI package). INFERRED.
- Shared chrome primitives: `ElevatedBackgroundFill`, `TopChrome`, `ColumnEdgeFade`, `MacColumnBarEdgeFade`, `SheetCloseButton`, `GlassOrBorderedButtonStyle`, `DisplayCornerRadii`. INFERRED.

## Ideas for Mactrix

Rules: glass on the navigation layer only; the timeline is opaque; the timeline is AppKit `NSTableView` rows. Verify each AppKit API in `docs/skills/` and the macOS 26 SDK headers before use. These notes name techniques, not exact AppKit signatures.

1. Morphing glass for the composer action buttons. Put send, attach and emoji buttons in one `GlassEffectContainer(spacing:)`, give each a `glassEffectID(_:in:)`, and use `glassEffectUnion(id:namespace:)` to fuse idle buttons into one capsule. Use `.glassEffect(.regular.interactive())` for press response. Where: composer bar (navigation layer). Fits the rules.
2. Scroll edge effect instead of hand-made blur. Use the system scroll edge effect under the toolbar (`scrollEdgeEffectStyle(.soft, for: .top)` on SwiftUI scroll views such as the sidebar; the AppKit equivalent for the timeline `NSScrollView`). Pass the wanted style up from each pane with a preference key, as Indigo's `PreferredScrollEdgeEffectStyle` does. Where: sidebar and timeline top edge. Fits: the system effect belongs to the chrome, the rows stay opaque.
3. Rolling counts. Use `.contentTransition(.numericText(value:))` with a spring on unread badges in the sidebar. For reaction counts in AppKit rows, use a `CATransition` of type push on the count layer, or host a small SwiftUI count view in the row. Where: sidebar unread badges, reaction chips. Fits.
4. Haptic ticks with a user switch. Use `sensoryFeedback(.selection, trigger:)` in SwiftUI, and `NSHapticFeedbackManager.defaultPerformer` (`.alignment`, `.levelChange`) in AppKit. Fire on reaction toggle, on drag snap points, and on a room switch by keyboard. Add one "Haptics" setting, as Indigo reads `__haptics` everywhere. Mac haptics work only on Force Touch trackpads. Fits.
5. Bridge network badges as real SF Symbol templates. Make custom symbols (SF Symbols app, all weights) for Slack, Google Chat, GroupMe, and render them with `SymbolRenderingMode.palette`. Overlay them on the avatar corner with a `destinationOut` cut-out ring (`compositingGroup` + `blendMode(.destinationOut)`), as Indigo does for `AvatarBadge`. Add a "show network badge" setting. Where: room list avatars and sender avatars. Fits (in AppKit rows, draw the cut-out with a `CAShapeLayer` mask).
6. Concentric corners. Read the window corner radius once and derive inner radii (inner = outer minus padding), as `DisplayCornerRadii` does. Use continuous corners (`cornerCurve = .continuous` on layers, `RoundedRectangle(style: .continuous)` in SwiftUI). Where: sheets, popovers, image previews, link cards. Fits. Check the macOS 26 SDK for a system concentric shape before you build your own.
7. Hide re-layout during live resize. In the timeline view, override `viewWillStartLiveResize` / `viewDidEndLiveResize`, keep a scroll anchor row, and restore it after the resize settles (Indigo: `liveResizeAnchor`, `liveResizeRestoration`, `liveResizeSettle`). Indigo also blurs the column during the resize. POSSIBLE CONFLICT: a blur over the timeline is an effect on scrollable content. Prefer the anchor and settle steps only, or a short opacity dip, and do not add the blur.
8. Theme as preferences, not asset colors. Give the user an accent tint, a text-contrast level and a body-font size offset (scaled with Dynamic Type metrics). Keep only brand colors (bridge networks) in the asset catalog, each with a lighter, more saturated dark variant, as `mastodon.purple` does. Where: settings and timeline text. Fits.
9. HDR images in the timeline. Set `preferredImageDynamicRange` on the image views in media rows behind a "Show HDR images" setting, as Indigo's `show-hdr-images` does. Where: timeline image rows. Fits (no glass).
10. Zoom from thumbnail to viewer. Use `matchedGeometryEffect` (or the zoom navigation transition where the macOS SDK offers it; Indigo gets it through Catalyst) from the row thumbnail to the media viewer. Where: image open. CAUTION: the source is an AppKit row, so you need a snapshot-and-animate step from the row frame to the viewer window. This is extra work, but it does not break the rules.

## Open questions and not found

Bounded searches that returned nothing (E1 imports and E2 strings, case-insensitive grep):

- `MeshGradient`, `AngularGradient`, `RadialGradient`, `PhaseAnimator`, `KeyframeAnimator`, `symbolEffect`, `backgroundExtensionEffect`, `drawingGroup`, `onHover`, `hoverEffect`, `pointerStyle`, `NSCursor`, `NSHapticFeedbackManager`, `NSVisualEffectView`, `NSGlassEffectView`, `CAEmitterLayer`, `ShaderLibrary`, `colorEffect`, `layerEffect`, `distortionEffect`, `.metallib`, `MTLDevice`, private CAFilter `variableBlur`.
- A modifier that the compiler inlined does not show up as an import. Absence in E1 is strong but not final.

Open:

- Spring constants, the like animation sequence, and which views own each glass call. These need decompilation. Hopper timed out at 120 s on the 69 MB binary. To retry, raise `REA_HOPPER_STARTUP_TIMEOUT_MS` (for example to 20 to 30 minutes), or use a Ghidra provider, then decompile functions that reference `LikeButton`, `GlassComposeView`, `RampedBlurView` and `PagingHaptics`.
- The REA session is stuck in `cleanup_incomplete` with Hopper still running (PIDs 41550, 41600) and runtime dir `/tmp/rea-9q9ZVM`. Close the Hopper document by hand, then restart the REA MCP connection.
- Where `TimelineView` and `Canvas` are used (Indigo code or a package).
- Whether `contentTransition(.numericText)` is used on post counts or only in the paywall.

## REA follow-up, 2026-11-23

### Target and evidence

- Indigo updated on 2026-11-23 to version 1.5 (build 531). The binary is now universal (x86_64 and arm64), SHA-256 `2dc96a4f9e67ab890c7f443b90381c3604ddaf2fd19636f75af6405b690afa3c`. The arm64 slice starts at container offset 70205440. `LC_BUILD_VERSION` is still MACCATALYST, minos 26.0, sdk 27.0, Xcode 27.1 (27A9275). The 1.4.2 binary of the first pass is no longer on disk, so the answers below are for 1.5.
- REA records (session closed after use):
  - I-R1 `ev_a006e7d1663dc6eb9d8b4b1508ccb58c049147bc8ff50d0624adebeff82efba2`: `inspect_plist` (1.5, 531, `com.soapboxsoftware.indigo`, `LSMinimumSystemVersion` 26.0).
  - I-R2 `ev_a131bd3657c7c352b2bd694958911d05e96916a4d121bb76c2b1b19d2507175b`: `inspect_macho` of the arm64 slice (complete: 7614 imports, 90 dependencies, 109 load commands, section offsets). Summary view `ev_98f6ca8fc758f42237665130f9d2362cf6caccc9a4172299d920093949633b48`.
  - I-R3 `ev_9f256d92b4d2d5a9bdca6afa87a56967d0182f6cc97b27565830fb560330d60b`: build metadata view (MACCATALYST 26.0, sdk 27.0).
  - I-R4 `ev_34beae6b183dab07ffb4a97e03d3e27627cc918a9b869668ac99e6f881be255c`: `demangle_swift` of `glassEffectUnion(id:namespace:)`, `glassEffectTransition(_:)`, `Glass.tint(_:)`, `sensoryFeedback(_:trigger:)`, `numericText(value:)`, `Spring.value(target:initialVelocity:time:)`, `Spring.settlingDuration(target:initialVelocity:epsilon:)`, `Animation.spring(response:dampingFraction:blendDuration:)`.
- Local static steps on the arm64 slice (extracted with `lipo -thin arm64`, slice SHA-256 `9d5c5504df302f8baabb40debb47d2854d1e3decdbfaab32995618d8c451fe95`), anchored on the I-R2 section offsets. The steps are the same as M-L1 to M-L6 in `docs/research/mosaic-visual-flair.md`:
  - I-L2 field map from `__swift5_fieldmd` (25,889 rows).
  - I-L3 conformance witnesses from `__swift5_proto` (exact `body` addresses).
  - I-L4 `llvm-objdump` of named functions, stub calls named from the indirect symbol table.
  - I-L5 call-site scan of all of `__text` (340 calls to 20 glass, spring, haptic and transition stubs), with owners from the nearest preceding witness. The owner is INFERRED; an offset of a few hundred bytes is strong, a few KB is weak.
  - I-L6 spring arguments decoded at each call.
- Hopper was not used. The REA registration has no `REA_HOPPER_STARTUP_TIMEOUT_MS`, so the timeout is still the 120 s that failed in the first pass, the arm64 code is still 51 MB, and another agent shared the REA server. I-L3 and I-L4 replace the decompiler for the named functions.

### Answers to the open questions

Spring constants (I-L5, I-L6). OBSERVED values. 64 calls to `Animation.spring(response:dampingFraction:blendDuration:)`:

| response, damping, blend | Calls | Owners (INFERRED by proximity) |
|---|---|---|
| 0.5, 0.85, 0 | 41 | The house spring: `TabBar`, `TabButton` (4), `TabButton.ButtonLabel`, `CompactTabBar`, `AccountGroupSwitcherButton` (3), `InAppNotificationBannerContainer`, `RefreshableScrollView` (6), `PostTextView` (3), `URLPreview`, `NotificationsFilterMenu`, `SessionExpiryBannerView`, `TimelineQuickFiltersView.QuickFilterToggle`, `GroupedNotificationView.FollowRequestButtons`, `TabBarBlurEdgePeriod` (2), paywall (3), 11 more with weak owners (7 put on `IndigoShortcut`) |
| 0.15, 0.85, 0.25 | 8 | Gesture tracking (interactive-spring shape): `ZoomableModifier` (2), 6 with a weak owner (`IndigoShortcut`) |
| 0.5, 1.0, 0 | 6 | Critically damped paging: `BookPoseDivision` (5), `MacView` |
| 0.35, 1.0, 0 | 3 | `DockedKeyboardAvoidance` (2), `ProfileMenuPreview` |
| 0.3, 1.0, 0 | 2 | `PinnedAccountsSignInNotice` |
| 0.1, 0.85, 0 | 2 | `ZoomableModifier` (snap back) |
| 0.22, 0.85, 0 | 1 | `BlockquoteView` (quote expand and collapse) |
| 0.9, 0.85, 0 | 1 | `SettingsAboutDeveloperSection` |

- The hand-driven spring of the first pass is `TimelineColumnSlotViewController.TopChrome`: it builds `Spring(duration: 0.35, bounce: 0)` and calls `Spring.value(target:initialVelocity:time:)` frame by frame. OBSERVED (calls and the 0.35 and 0 arguments), INFERRED (frame driver). `ColumnIdentity` calls `Spring.settlingDuration`; its arguments were not resolved.
- Example check (I-L4): at `0x1002760a8` the code is `mov x8, #0x3333333333333333; movk x8, #0x3feb, lsl #48; fmov d1, x8; fmov d0, #0.5; movi v2, #0; bl Animation.spring`, which is (0.5, 0.85, 0).

Which views own each glass call (I-L5). 28 `glassEffect` calls, 6 `GlassEffectContainer`, 5 `glassEffectID`, 3 `glassEffectUnion`, 3 `glassEffectTransition`, 1 `Glass.tint`:

| Owner (INFERRED by proximity) | Glass use | Confidence |
|---|---|---|
| `TabButton` (+0x3bd0 to +0x5024 from its `body`) | `GlassEffectContainer`; 3 x `glassEffect(.regular.interactive())` + `glassEffectID` + `glassEffectTransition`; `sensoryFeedback` | OBSERVED (calls), INFERRED (owner) |
| `TabButton.ButtonLabel` (+0x40) | `glassEffectUnion(id:namespace:)` + `sensoryFeedback` | OBSERVED, owner strong |
| `AccountGroupSwitcherButton` | `glassEffectUnion` + `sensoryFeedback` (2) | INFERRED (owner weak, +0x5308) |
| `TimelineColumnView`, `TimelineColumnToolbar`, `ColumnTitleToolbar`, `FeedsPickerMenu` | `GlassEffectContainer`; `glassEffect(.regular.interactive())` on column toolbar buttons | OBSERVED (calls), INFERRED (owner) |
| `NetworkFilterChip` (+0x4) | `glassEffect(.regular.tint(color).interactive())`: the only `Glass.tint` call | OBSERVED, owner strong |
| `FilterChipLabel` (+0x4) | `glassEffect(.regular.interactive())` | OBSERVED, owner strong |
| `InAppNotificationBannerContainer` (+0x88) | `glassEffect(.regular.interactive())` for the in-app banner | OBSERVED, owner strong |
| `SearchCapsuleBackground` | `glassEffect(.regular)` and `GlassButtonStyle` | INFERRED (owner weak) |
| `ComposePostToolbarState` | `GlassEffectContainer`, `glassEffect(.regular)`, `GlassButtonStyle` for the compose toolbar | INFERRED (owner weak) |
| `GlassComposeView.UnresolvedMentionWarning` | `glassEffect(.regular)` | INFERRED |
| `OpenPostDialog` | `GlassEffectContainer`, `glassEffect(.regular)` | INFERRED |
| `PinnedAccountsSignInNotice` | `glassEffect(.regular.interactive())` + `glassEffectID` (2) | INFERRED |
| `ImageGallery.AltTextView` (+0x224) | `glassEffect(.regular)` + `GlassButtonStyle`: alt text over the image viewer | OBSERVED, owner strong |
| `GroupProfileColumn` (7), `ProfileMenuPreview`, `ProfileImageCropView` | `glassEffect(.regular.interactive())` buttons on profile headers and the crop view | INFERRED |

- No glass call is attributed to a post cell type (`UIKitTimelinePostCell` and friends) or to `Heart`, `LikeButton`, `RepostButton`. Glass stays on tab bar, toolbars, chips, banners and overlays. This upgrades the first-pass statement "timeline cells carry no glass names" from names to call sites. INFERRED (attribution), with OBSERVED call sites.
- `glassEffectUnion` and `glassEffectTransition` sit in the tab bar code. This confirms the first-pass reading of a custom glass tab bar whose bubbles merge and morph.

The like animation (I-L2, I-L3, I-L4):

- `Heart.body` (exact witness, `0x100c9f888`) is short: `Image(systemName: isLiked ? "heart.fill" : "heart")` with the foreground `tintColor` when liked, else `Color.secondary`. The two symbol names are built as immediates in the code. There is no scale, no spring and no symbol effect in it. OBSERVED.
- `LikeButton` fields: `wrapper`, `delegate`, `__haptics` (an `Int` setting), `_postPrefs`, `_appearance`. The action buttons fire `sensoryFeedback(SensoryFeedback.impact, trigger:)` with a trigger kept in state (closure after `Heart`, `0x100c9ff74`, 2 calls; `RepostButton` +0x40, 1 call). OBSERVED (calls), INFERRED (which button owns the closure).
- No `symbolEffect` import exists in 1.5 either (I-R2). The like is a symbol swap, a tint change and a haptic. Any motion in the UIKit post cell (`PostActionBarUIView`) would use UIKit animation calls through `objc_msgSend` and was not traced. UNKNOWN.

`numericText`: 3 call sites only: `NotificationsFilterMenu` (with the house spring) and `SessionExpiryBannerView` (2). No post cell or action button calls it. Post counts do not roll in 1.5. OBSERVED (call sites), INFERRED (owners).

`TimelineView` and `Canvas`: `TimelineView` is used near `ActivityEntry` and `ActivityStatusToast` (an activity toast, likely an elapsed-time or progress display). `Canvas` is the exact `body` of `Checkerboard` (a transparency checkerboard). OBSERVED (calls), INFERRED (purpose).

### New findings in 1.5

- `TimelineCapsuleView` fields: `showGlass`, `isColumnHeader`, `peeksFeedNameOnAppear`, `feedNamePeekDuration`, `__isPeekingFeedName`, `__feedNameTimer`, `undoDuration`, `__undoTimer`, `menuScale`. The column capsule shows the feed name for a short time when it appears, then collapses, and it carries an undo timer. OBSERVED (fields), INFERRED (behavior), durations UNKNOWN.
- Toast stack: `ToastManager`, `ToastType`, `ToastButton`, `ToastClearance` and `ToastClearanceModifier` (toasts keep clear of chrome), `InAppNotificationBanner`, `ActivityStatusToast`. OBSERVED (names).

### Status of the ideas above, and two new ones

- Done in Mactrix since 2026-11-18: idea 1 (MATRIX-195), idea 2 (MATRIX-196, sidebar), idea 3 (MATRIX-193), idea 5 (MATRIX-194), idea 7 (MATRIX-197). Open: ideas 4, 6, 8, 9, 10.
- Idea 10 caution: `NavigationTransition.zoom(sourceID:in:)` is `@available(macOS, unavailable)` in the macOS 27 SDK. On the Mac, a thumbnail-to-viewer zoom needs `matchedGeometryEffect` inside one window or a snapshot animation.
- Spring note: Mactrix's `MotionToken.pop` is (0.3, 0.62). Indigo never goes below damping 0.85, and Mosaic also settles at 0.85 or 1.0. A "settle" token near (0.25 to 0.5, 0.85) fits chrome that moves into place better than `pop`.
- New idea 11, active filter chip in tinted glass. When the chat list has a filter other than Inbox (Unread, People, Snoozed) or a label or space is selected, show a chip in the sidebar header with the filter name and a clear button, in `glassEffect(.regular.tint(color).interactive())` with the label or space color, as `NetworkFilterChip` does. Today the only sign is a filled filter icon. Where: sidebar header, not over the list. Fits. Size S.
- New idea 12, peek the rail item name. After ⌘1 to ⌘9 or ⇧⌘[ and ⇧⌘], show the selected rail item's name in a small capsule for about a second, then collapse it, as `TimelineCapsuleView` peeks the feed name. Rail items show only an icon today. Where: sidebar header or rail. Fits on the navigation layer if it does not float over the scrolling list. Size S.

### Still open

- The keyframes and durations of the capsule peek and undo timers.
- Motion in the UIKit post cell after a like (objc selector calls, not traced).
- `RampedBlurView` and `PagingHaptics` were not re-examined in 1.5.
