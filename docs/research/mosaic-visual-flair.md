# Mosaic visual flair: static analysis notes

## Target and method

- Path: `/Applications/Mosaic.app`. This is a wrapper. The real bundle is `Wrapper/Mosaic.app` (the App Store layout for an iPhone or iPad app that runs on an Apple silicon Mac).
- Bundle id `com.jwein.mosaic`, display name "Mosaic", version 1.0.0 (build 178). Siri alternative names: "Baseball", "MLB", "Mosaic Baseball". It is a third-party baseball app: scores, Multiview video, Apple TV remote, standings, an "Ask MLB" chat (M-R1).
- Main binary: `Wrapper/Mosaic.app/Mosaic`, thin arm64, SHA-256 `70b8da6e3d51f735d97b3ada5a06d11c2fe29f579e507634136a48ca5427b1bc`, 75 MB, `__text` 53 MB (M-R5).
- Date: 2026-11-23.
- Method: static only. Mosaic was not launched. No debugger, no Frida, no UI capture.

### What kind of app it is

| Finding | Evidence | Confidence |
|---|---|---|
| An iOS app, not a Mac app and not Mac Catalyst. `LC_BUILD_VERSION` platform 2 (iOS), minos 18.0, sdk 27.1. `LSRequiresIPhoneOS` true, `CFBundleSupportedPlatforms` iPhoneOS, `UIDeviceFamily` [1, 2] | M-R3, M-R4, M-R1 | OBSERVED |
| It runs on the Mac as an iPad app ("Designed for iPad"): `UISupportedDevices` lists `MacFamily20,1` next to the iPad models | M-R1 | OBSERVED |
| Built with Xcode 27.1 (27A9269) against the iOS 27.1 SDK | M-R1 | OBSERVED |
| FairPlay covers one 4096-byte page only (`LC_ENCRYPTION_INFO_64` cryptoff 14970880, cryptsize 4096, cryptid 1). All Swift metadata, strings and almost all code are readable | M-R4 | OBSERVED |
| SwiftUI first: 2359 of 7030 imports are SwiftUI, 207 are UIKit. Also Charts, TipKit, ActivityKit, WidgetKit, FoundationModels (weak), CoreHaptics | M-R2 | OBSERVED |
| Consequence for Mactrix: Mosaic is an iOS 26 Liquid Glass app. Some of its APIs do not exist on macOS (see "Not portable"). The SwiftUI glass, motion and haptics APIs it uses do exist on macOS 26 | M-R2, S1 | OBSERVED |

### REA status and evidence sources

REA records (session closed after use):

- M-R1 `ev_6e829161979e22a739b13a7cd442a8c535f14875fd772c1eb9b65b7e8bbd82a1`: `inspect_plist` of `Wrapper/Mosaic.app/Info.plist`.
- M-R2 `ev_e341550cc9fd75b0a164afc3eb9ba43f85ea02e8b53b8994ed10fd7aef36a8a6`: `inspect_macho` (complete: 7030 imports, 98 dependencies, 118 load commands). Summary view `ev_c36b0726d4320a5cd7920b6319a610202aadcd5a0edeb33f4b16addb6bc11bb6`.
- M-R3 `ev_48443acfaaba9b9a53055a8f224cd524a990a5bd6f9391835ca5c5ead88d8dc4`: build metadata view.
- M-R4 `ev_f3180f07405c59a6e03c476df5626e863ff54b8b6ec73dff0830916b63380325`: load commands 5 to 18.
- M-R5 `ev_d750843eb1b3b914c5a3124ec89c736ecbb545f5a305a13b714e3e9f97ead015`: segments and section file offsets. The local steps below read the sections at these offsets.
- M-R6 `ev_8d56fde6026c5e54badc4a7716237ac0dcb8c1134500fbf4448eb4c82ab7580c`: `inspect_asset_catalog`, 678 records in 6 catalogs.
- M-R7 `ev_0b68a9e3b14ab8e13f01f391c82d45471a0aa0e5f441cbdaa8ef77951a46bccb`: `demangle_swift` of 23 key SwiftUI imports.

Local static steps on the same binary (SHA-256 above), anchored on the M-R5 section ranges:

- M-L1 Type names: printable strings in `__TEXT,__const` (6380 type-like names). C strings: `__TEXT,__cstring`.
- M-L2 Field map: a parse of `__swift5_fieldmd` that joins each Swift type to its stored property names (31,460 rows, 7068 types). Private types show no parent name.
- M-L3 Conformances: a parse of `__swift5_proto`. Each conformance to a SwiftUI protocol has resilient witnesses, so the `body` or `makeBody` function of a named type has an exact address.
- M-L4 Disassembly: `llvm-objdump` of single named functions. Stub calls carry their import names from the indirect symbol table (`llvm-objdump --macho --indirect-symbols`), demangled with `swift-demangle`.
- M-L5 Call-site scan: every `bl` in `__text` to a glass, spring, haptic or content-transition stub, mapped to its function start (`LC_FUNCTION_STARTS`). A call site is attributed to a type when its function is that type's witness (exact), else to the nearest witness before it (closure heuristic, INFERRED; weak for large offsets).
- M-L6 Spring arguments: the `d0` to `d2` values at each spring call, decoded from `fmov`, `mov`/`movk`, and literal loads.
- S1 macOS availability: `@available` lines in the Xcode-beta macOS SDK interfaces (`SwiftUI.swiftinterface`, `SwiftUICore.swiftinterface`).

Hopper was not used. Reasons: the REA registration sets no `REA_HOPPER_STARTUP_TIMEOUT_MS`, so the timeout is the same 120 s that failed on the 69 MB Indigo binary on 2026-11-18 and left REA in `cleanup_incomplete`. Mosaic is larger (53 MB of code). Another agent used the same REA server at the same time. M-L3 and M-L4 replace Hopper for the few functions that needed code.

## 1. Materials and glass

| Finding | Evidence | Confidence |
|---|---|---|
| Glass is everywhere: 586 calls to `View.glassEffect(_:in:)`, 579 `Glass.regular`, 302 `Glass.interactive(_:)`, 61 `Glass.tint(_:)`, 9 `Glass.clear`, 13 `GlassEffectContainer(spacing:content:)`, 1 `glassEffectID(_:in:)`, 11 `GlassProminentButtonStyle`, 8 `GlassButtonStyle` | M-R2, M-R7, M-L5 | OBSERVED (counts of call sites) |
| No `glassEffectUnion` and no `glassEffectTransition` imports. The glass does not morph between shapes the way Indigo's tab bar does | M-R2 | OBSERVED (absence in imports) |
| UIKit glass too: `UIGlassEffect`, `UIVisualEffectView`, `UIBlurEffect` | M-R2 | OBSERVED |
| Glass on content cards, not only on chrome. Most attributed call sites sit in score and game card code (`BaseDiamondMini`, `PostseasonSingleGameCard`, `SingleGamePitcherSeasonLine`, `StandingsCard`). This breaks Mactrix hard rule 2 and does not move over | M-L5 | INFERRED (closure attribution) |
| `Glass.clear` sits over video and camera: `QuickWatchLoadingChipContainer`, `StreamView.ContentTab`, `GazeCalibrationOverlay`, `PostseasonSingleGameCard` | M-L5 | INFERRED |
| Own glass wrappers: `MosaicGlassModifier` (field `shape`), `GlassPillBackground`, `LoadingChipGlass` (`overVideo`), `TransientPillGlass` (`style`), `StreamGlassCapsule` (`interactive`), `SingleGameControlGlass` (`prominent`), `RemoteGlassCluster` and `MosaicSurveyGlassContainer` (`spacing`, `content`: thin `GlassEffectContainer` wrappers), `GameLiveActivityToastGlass` (`tint`), `GlassyFooterButtonStyle` (`fullWidth`). With a minimum of iOS 18, these most likely choose glass on iOS 26 and a material below it | M-L1, M-L2 | OBSERVED (names, fields), INFERRED (fallback) |
| Glass entrance: `PremiumGlassAppearModifier` (fields `isVisible`, `delay`, `scale`, `yOffset`, `anchor`, `animation`, `_reduceMotion`). Its `body` sets opacity 0 or 1, a `scaleEffect` from `anchor`, and a y offset; the animation is the `animation` field plus `.delay(delay)`. With Reduce Motion on, scale stays 1, the offset stays 0, and the animation is `easeOut(duration: 0.01)` | M-L2, M-L3, M-L4 (body at `0x100eabe08`) | OBSERVED |
| Glass press: `PremiumGlassPressButtonStyle.makeBody` scales the label to 0.975 (anchor center) and sets a second value to 0.9 while pressed, both only when Reduce Motion is off. The animation is a static `Animation.spring(response: 0.16, dampingFraction: 1.0)`, kept in a lazy global | M-L3, M-L4 (`0x100eabf80`, initializer `0x100eabdb0`) | OBSERVED (values), INFERRED (0.9 is likely opacity) |
| Glass "bloom" for Multiview: `MultiviewGlassBloomAnimator` (enum `Operation` present or dismiss, `launchStyle`) and `MultiviewGlassBloomTransitionDelegate`: a UIKit custom presentation animator | M-L1, M-L2 | OBSERVED (names), INFERRED (behavior) |
| Glass zoom source: `AskMLBGlassZoomSource` (with `Coordinator`, `HostedFace`) next to imports of `matchedTransitionSource(id:in:)`, `NavigationTransition.zoom(sourceID:in:)` and `MatchedTransitionSourceConfiguration.clipShape(_:)`. A glass button that zooms into the Ask MLB sheet | M-R2, M-R7, M-L2 | OBSERVED (API), INFERRED (use) |
| Scroll edges: `scrollEdgeEffectStyle(_:for:)` with `.soft` and `.hard`, `scrollEdgeEffectHidden(_:for:)`; own `ScrollEdgeBlur` and `EdgeFadeScrollView` (field `atTrailingEdge`: a trailing fade until the end of a horizontal scroll) | M-R2, M-L2 | OBSERVED |
| Materials: `Material.ultraThin`, `.thin`, `.regular`, `.bar` | M-R2 | OBSERVED |
| Increase Contrast: `CardContrastOverlay` (fields `_extraContrastUI`, `_colorSchemeContrast`, `cornerRadius`, `strokeOpacityScale`, `cornerStyle`). Settings text: "Extra Contrast strengthens card edges while leaving chips untouched." | M-L1, M-L2 | OBSERVED |

## 2. Navigation chrome

| Finding | Evidence | Confidence |
|---|---|---|
| iOS 26 tab bar: `tabBarMinimizeBehavior(_:)` with `.onScrollDown` and `.never`, `tabViewBottomAccessory(isEnabled:content:)`, `SidebarAdaptableTabViewStyle`. Own `MinimizingTabBarOnScroll` (reads prefs), `FloatingTabBarClearanceModifier`, `BottomAccessoryResolver` (kinds `radio`, `startingRadio`, `appleTV`), `TabBarCustomizer.swift`. Setting "Minimize Tab Bar on Scroll" (`tabBarMinimizesOnScroll_v1`) | M-R2, M-R7, M-L1, M-L2 | OBSERVED |
| SDK 27 toolbar APIs: `toolbarMinimizationBehavior(_:for:)`, `toolbarVerticalBehavior(_:)`, `ToolbarContent.visibilityPriority(_:)`, `toolbar(removing:)`, `searchPresentationToolbarBehavior(.avoidHidingContent)` | M-R2, M-R7 | OBSERVED |
| `safeAreaBar(edge:alignment:spacing:content:)`: 2 call sites (`PostseasonWatchGuideSheet`, one other) | M-R7, M-L5 | OBSERVED (API), INFERRED (owners) |
| `MosaicPageHeader` with `MosaicPageHeadingConfig` (`title`, `showsTitle`, `showsInlineActions`, `actions`) and `MosaicPageHeaderCapsuleAction`: a custom page header with capsule action buttons. `CollapsedScoreBar` (`phase`: pregame, live, final, terminal) shows a condensed bar after the hero scrolls away | M-L2 | OBSERVED (fields), INFERRED (behavior) |
| `ChromeAutoHideController` (`idleDuration`, `scheduleHide`): video chrome hides after idle time | M-L2 | OBSERVED (fields) |

## 3. Animation

| Finding | Evidence | Confidence |
|---|---|---|
| 333 spring call sites. Most frequent `Animation.spring(response:dampingFraction:)` pairs: (0.22, 0.85) x42, (0.25, 0.85) x41, (0.24, 0.85) x21, (0.5, 0.85) x19, (0.3, 1.0) x18, (0.2, 0.85) x16, (0.18, 0.85) x15. `Spring(duration: 0.5, bounce: 0)` x8. House style: short responses near 0.2 to 0.25 s, damping 0.85, no blend | M-L5, M-L6 | OBSERVED |
| `keyframeAnimator` bodies: `ScoreChangePulseModifier` (fields `trigger: Int`, `isActive`, `_reduceMotion`) and `HomeRunCelebrationModifier` (same fields) are each exactly a `keyframeAnimator` call; `AskMLBFeedbackRow` has a third. The keyframe values sit in closures that were not read | M-L2, M-L3, M-L5 | OBSERVED (calls), UNKNOWN (keyframes) |
| `phaseAnimator`: `LiveBadgePulseModifier.body` is exactly one `phaseAnimator` call | M-L3, M-L5 | OBSERVED |
| `BreathingModifier` (`minOpacity`, `cycleDuration`, `_reduceMotion`, `__dim`): an opacity breath | M-L2 | OBSERVED (fields) |
| Shimmer: `ShimmerModifier` (`opacity`, `cornerRadius`, `bandWidthRatio`, `cycleDuration`, `_reduceMotion`, `__shimmer`, `__width`), `CatchUpShimmerModifier` (also pauses on `_scenePhase`), `CatchUpCTAShimmerModifier`, `AppleIntelligenceShimmerModifier` (`intensity`, `_sharedPhase`). Skeleton shapes: `CatchUpSkeletonRect`, `CatchUpSkeletonRegion` | M-L2 | OBSERVED (fields) |
| Glow: `AppleIntelligenceGlowModifier` (`isActive`, `shape`, `_sharedPhase`), `AppleIntelligenceGlowBurstModifier` (`__isBursting`, `__hasSeenAISource`), `AskMLBRotatingBorder` (`cornerRadius`, `isTurning`). With `AngularGradient`, `BlendMode.plusLighter`, `blur(radius:)` in the imports: a turning angular-gradient border, the Siri-style glow | M-R2, M-L2 | OBSERVED (names), INFERRED (drawing) |
| Scroll-driven: `scrollTransition(_:axis:transition:)` (4 call sites, one is `CatchUpScrollTransitionModifier.body`), `visualEffect` with blur, offset, opacity and scale, `onScrollGeometryChange`, `onScrollPhaseChange`, `onScrollVisibilityChange` | M-R2, M-L5 | OBSERVED |
| Content transitions: `numericText(countsDown:)` x110 (scores), `numericText(value:)` x8, `.opacity` x51, `symbolEffect(_:options:)` x14, `.interpolate` | M-L5 | OBSERVED |
| Symbol effects: `BounceSymbolEffect`, `BreatheSymbolEffect`, `PulseSymbolEffect`, `ReplaceSymbolEffect`, `RotateSymbolEffect`, `VariableColorSymbolEffect` (iterative, reversing), `SymbolEffectOptions.repeat`, `.speed` | M-R2 | OBSERVED |
| Morphing: `MorphingSelector` (`options`, `selection`, `label`, `_chevronSize`, `_reduceMotion`), `LiveStreamMorphSurface`, `StreamMorphHostModifier`, `AppleTVRemoteMorphSource`/`Destination`, `CatchUpMorphID` | M-L2 | OBSERVED (names), INFERRED (matched-geometry morphs) |
| Staggered list entrance: `StaggeredReveal` (`index`, `__revealed`, `_reduceMotion`) | M-L2 | OBSERVED (fields) |
| Reduce Motion is a house rule: 135 types store a `reduceMotion` environment value | M-L2 | OBSERVED |

## 4. Color, gradients, drawing

| Finding | Evidence | Confidence |
|---|---|---|
| Token system in a Swift package: `DesignTokens_DesignTokens.bundle` holds `brand-color-tokens.json` with 155 themes (`default`, `mlb`, `milb`, events, `team-<id>`), each with the same roles: `background` (main, support, inverse), `text`, `icon`, `border`, `decorative`, `surface`. Types `ColorToken`, `GradientToken`, `FontToken`, `InsetToken`, `ColorReference` (scales such as `neutral0`...`neutral1400`, `blue100`...`blue1000`), `BrandTokensStore`. One semantic palette, re-skinned per team | M-L1, M-L2, bundle file | OBSERVED |
| User theme: "Accent Theme updates control highlights across the app", "Dark appearance uses a pure black background", `accent_theme_changed`; `MosaicTeamColor`, `WidgetTeamTint` | M-L1 | OBSERVED (strings) |
| `MeshGradient(width:height:locations:colors:background:smoothsColors:colorSpace:)`: 3 call sites (`CatchUpPromoMeshBackground`, `TabSlotLabel`, one more). `CatchUpDriftingMesh` (`colors`, `__start`) and `CatchUpPromoMeshBackground` (`isDrifting`, `isFlattened`, `__isOnScreen`): a mesh that drifts over time and stops off screen | M-R7, M-L2, M-L5 | OBSERVED (calls, fields), INFERRED (drift by time) |
| `AngularGradient`, `RadialGradient`, `LinearGradient`, `Gradient.ColorSpace.perceptual`, `Color.gradient`, `BlendMode.plusLighter`, `compositingGroup`, `drawingGroup`, `Canvas`, `TimelineView` with `AnimationTimelineSchedule` | M-R2 | OBSERVED |
| No Metal shaders: no `ShaderLibrary`, `colorEffect`, `layerEffect`, `distortionEffect`, `MTLDevice` imports, no `.metallib` in the bundle | M-R2, bundle listing | OBSERVED (absence) |
| Asset catalog: no named colors. Images are team logos (light and `_on_dark` variants), ballparks, league marks, vector icons for Ask MLB | M-R6 | OBSERVED |

## 5. Typography

| Finding | Evidence | Confidence |
|---|---|---|
| Bundled fonts: HEX Franklin MLB (regular, narrow, wide, XX-condensed, 7 weights), Proxima Nova, Comic Neue | bundle listing, M-R1 (`UIAppFonts`) | OBSERVED |
| `Font.width(.compressed)`, `monospacedDigit()`, `tracking(_:)`, `LetterSpacing`, `ParagraphSpacing` tokens | M-R2, M-L1 | OBSERVED |

## 6. Interaction feedback

| Finding | Evidence | Confidence |
|---|---|---|
| `HapticEngine`: CoreHaptics (`CHHapticEngine`, patterns per `Variant`) with UIKit generator fallbacks (`impactLight`, `impactMedium`, `impactHeavy`, `selectionGen`, `notificationGen`) and a restart guard (`consecutiveStartFailures`, `coreHapticsBlocked`). Variants: light, medium, heavy, selection, success, warning, error, highlight, pop, openPanel, playbackOpen, playbackReady, acquisitionReveal, floatingButtonDrop, heartbeat, more | M-L2 | OBSERVED |
| `sensoryFeedback(_:trigger:)` x46, `SensoryFeedback.impact(weight:intensity:)`, `.selection` | M-R7, M-L5 | OBSERVED |
| `HapticPressButtonStyle`, `HapticCardPressButtonStyle` (`_reduceMotion`) | M-L2 | OBSERVED |
| One switch: "Disable Haptics silences Mosaic's in-app taps, confirmations, and notification haptics" (`disableHaptics_v1`) | M-L1 | OBSERVED |
| Pointer: `CardHoverModifier` (`cornerRadius`, `__isHovering`, `_reduceMotion`); `hoverEffect(_:isEnabled:)` with `CustomHoverEffect.highlight` | M-R2, M-L2 | OBSERVED |
| Undo: `TransientUndoPill` (`message`, `systemImage`, `style`, `onUndo`, `onDismiss`) on `TransientPillGlass`; text ". Undo available." | M-L1, M-L2 | OBSERVED |
| Spoilers: `SpoilerVeilModifier` (`isMasked`, `_reduceMotion`), `SpoilerRevealBanner` (`isMasked`, `onReveal`), `SpoilerAggregateOverlay` (`label`, `onReveal`, `content`), `SpoilerEngine` ("Spoiler Guard" hides scores) | M-L1, M-L2 | OBSERVED (names, fields), UNKNOWN (veil look) |

## Ideas for Mactrix

Rules: glass on the navigation layer only; the timeline is opaque AppKit `NSTableView` rows; timeline motion never changes a row height; Reduce Motion is honored (MotionToken). Already in Mactrix, so not proposed: composer glass with morphing buttons (MATRIX-195), rolling counts (MATRIX-193), sidebar scroll edge effect (MATRIX-196), network badge cut-out ring (MATRIX-194), live-resize anchor (MATRIX-197), floating glass composer (MATRIX-198), hover bar, chip press scale, jump flash, "New" divider glow, sticky day pill, the inbox Undo toast (MATRIX-206).

1. Unread badge pop. When a chat-list unread count goes up, play one short scale pulse on the badge, triggered by the count, as `ScoreChangePulseModifier` does with a `keyframeAnimator` on an `Int` trigger. Keep the MATRIX-193 digit roll. Under Reduce Motion, no pulse. Where: chat-list unread capsule and rail badges. Fits: no glass, no row height change. Size S.
2. Entrance motion for transient chrome. Copy the `PremiumGlassAppearModifier` recipe: opacity from 0, a small scale from an anchor, a small y offset, an optional delay; under Reduce Motion, a near-instant fade only. Where: the inbox Undo toast, the "2 scheduled" strip, the thread reply notice, the reply and edit bars of the composer. Fits (no new glass). Size S.
3. Loading shimmer. A `ShimmerModifier`-style band (band width as a ratio of the width, a cycle duration, paused when the scene is not active, off under Reduce Motion) on placeholder shapes. Where: the post peek popover while it loads, the Bookmarks list previews, the Threads pane. Not in timeline rows. Fits. Size S.
4. Drifting mesh for empty states. A `MeshGradient` whose points drift with a `TimelineView`, stopped when off screen and static under Reduce Motion (`CatchUpPromoMeshBackground`: `isDrifting`, `__isOnScreen`). Where: the "no chat selected" detail pane and the sign-in screen. Fits (no glass, nothing scrolls over it). Size S.
5. Increase Contrast edges. When `colorSchemeContrast == .increased`, add a hairline stroke to glass and opaque floating surfaces (composer field, day pill, scroll chip, toast), as `CardContrastOverlay` does. Where: chrome primitives. Fits; it is the contract's "glass degrades gracefully" line. Size S.
6. Spoiler veil. Draw an opaque veil over `data-mx-spoiler` ranges in message bodies, with click to reveal (`SpoilerVeilModifier`, `SpoilerRevealBanner`). Reuse the MATRIX-187 TextKit 1 line rects that draw the music link bar. Where: message body text, timeline rows. Fits: opaque, no glass, no height change. Size M.
7. Settle spring token. Mosaic and Indigo both settle with damping 0.85 (Mosaic mostly response 0.22 to 0.25 s). Mactrix has one timing curve and one bouncy `pop` spring (0.3, 0.62). Add a "settle" spring (about 0.25, 0.85) for chrome that moves into place. Size S.
8. One haptics switch. `sensoryFeedback(.selection)` or `.alignment` feedback on reaction toggle and rail switches, with one "Haptics" setting, as Mosaic's "Disable Haptics" does. Mac haptics work only on a Force Touch trackpad. Size S.

Not portable or out of scope:

- Glass on cards and on scrolling content (most of Mosaic's 586 glass calls): breaks hard rule 2.
- A glass Undo pill (`TransientPillGlass`): the Mactrix toast floats over the scrolling chat list, and the 2026-11-18 amendment (MATRIX-198) allows only the composer as a glass overlay over scrolling content. It needs a §11 amendment. Idea 2 takes the motion without the glass.
- Zoom from a glass button into a sheet: `NavigationTransition.zoom(sourceID:in:)` is `@available(macOS, unavailable)` in the macOS 27 SDK (S1).
- `CustomHoverEffect` and `hoverEffect(_:isEnabled:)`: unavailable on macOS (S1). Mactrix already uses `onHover`.
- Toolbar minimize on scroll: on macOS, `ToolbarMinimizationBehavior` has only `.automatic` (S1).
- `tabBarMinimizeBehavior` and `tabViewBottomAccessory`: tab-bar chrome that Mactrix does not have.
- The Siri-style glow (`AppleIntelligenceGlowModifier`): Mactrix has no AI feature in scope. Keep it for epic MATRIX-38 if on-device models arrive.
- The Multiview glass bloom: a UIKit presentation animator with no Mac window analog worth the cost.

## Open questions and not found

- Keyframe values of `ScoreChangePulseModifier` and `HomeRunCelebrationModifier`: in closures not read.
- Call-site owners come from the nearest preceding witness. For offsets above a few KB (for example 103 sites put on `BaseDiamondMini`) the owner is likely a private type with no conformance. Treat those owners as weak.
- The 0.9 value in `PremiumGlassPressButtonStyle`: the modifier type was not resolved. Opacity is the likely use.
- Default arguments of `PremiumGlassAppearModifier` (scale, offset, animation) sit at its call sites, not read.
- Bounded searches with no result (imports, M-R2): `glassEffectUnion`, `glassEffectTransition`, `backgroundExtensionEffect`, `ShaderLibrary`, `colorEffect`, `layerEffect`, `distortionEffect`, `NSHapticFeedbackManager`. An inlined modifier does not show as an import.
- Doc drift: `docs/skills/swiftui-whats-new-27/references/toolbar.md` (exported from Xcode 27.0 beta 27A5237l) names `toolbarMinimizeBehavior(_:for:)`. The Xcode-beta macOS SDK in this checkout and Mosaic's import (M-R7) use `toolbarMinimizationBehavior(_:for:)` with `ToolbarMinimizationBehavior`. Check the SDK before you use the name from the skill.
