# Vaulty design system: "Editorial Vault"

Premium and calm by default, with a hint of Gen Z in a few deliberate places. This file is the source of
truth for UI decisions. The tokens live in `lib/theme/app_theme.dart`, the icons in
`lib/widgets/glyphs.dart`, and the components in `lib/widgets/common.dart`.

## Why this direction (market read, Sept 2026)

- **Typography is doing the branding.** Current premium apps use a serif display face for headlines and a
  clean sans for UI, and they treat type as the brand's voice rather than decoration.
- **"AI slop" has recognisable tells:** purple-to-blue gradients, Inter everywhere, an icon inside a rounded
  square on every card, emoji used as bullets, and rounded drop-shadow cards on every surface. Our old UI
  had all of them. The fix is a committed direction: a distinctive font pairing, one dominant colour with a
  sharp accent, borderless or hairline surfaces, and motion used only at key moments.
- **Premium Gen-Z apps pair restraint with a few tactile moments.** Opal's gem animation is one example of
  a delight moment that builds affinity. Airbnb's redesign shows a single app surface holding many kinds of
  content through consistency.

So Vaulty is **paper and ink** with editorial serif headlines, one violet brand colour, and a single loud
lime accent used in tiny doses. Vo, the mascot, is reserved for emotional moments: onboarding, empty
states and the lock screen.

## Rules

1. **No emoji in the UI.** Use Vaulty Glyphs (`VIcon(G.x)`). User content can still contain emoji.
2. **No gradients** on surfaces or buttons. The mascot is the only shaded thing in the app.
3. **No drop shadows.** Use a surface colour plus a 1px hairline (`VCard`).
4. **Don't put an icon in a box by default.** Show a category as a coloured glyph plus a small-caps label
   (`CategoryLabel`).
5. **Colour means something.** Countdowns are neutral ink until they need you: amber when soon, red when
   urgent or overdue.
6. **Lime is rare.** Use it for the active-tab dot, the capture button, the Up next numeral, toast icons and
   the "after" checks. Never use it for text on paper.
7. **Italic serif marks exactly one word per headline**, in brand violet ("Ask *anything.*").
8. **Copyable data is mono** (DM Mono): codes, sizes, prices, passwords.

## Type

| Role | Face | Size / weight | Used for |
|---|---|---|---|
| display | Instrument Serif | 40, tight leading | Screen heroes, greetings |
| headline | Instrument Serif | 26–32 | Detail titles, sheet titles, questions |
| numeral | Instrument Serif | 28–72 | Countdowns, stats, date blocks |
| accent | Instrument Serif *italic*, brand | inherits | The one emphasised word |
| title | Instrument Sans 600 | 17 | Section headers |
| item | Instrument Sans 600 | 15.5 | Row and card titles |
| body / bodySoft | Instrument Sans 400 | 15 / 14.5 | Paragraphs |
| caption | Instrument Sans 400 | 12.5 | Meta lines |
| eyebrow | Instrument Sans 600, caps, +1.2 tracking | 11 | Labels above content |
| mono | DM Mono 500 | 11–26 | Data |

## Colour (light / dark)

| Token | Light | Dark | Use |
|---|---|---|---|
| bg | `#F6F4EF` | `#0D0D0F` | Paper background |
| surface | `#FFFFFF` | `#17171B` | Cards, sheets, inputs |
| sunken | `#EFECE5` | `#202026` | Chips, tracks, neutral tags |
| line | `#E4E0D8` | `#2A2A31` | Hairlines |
| ink / inkSoft / inkFaint | `#151419` / `#54525A` / `#6D6974` | `#F3F1EC` / `#B4B1BA` / `#8A8690` | Text and primary UI |
| brand | `#5B44F2` | `#9788FF` | Accent word, links, "best match" |
| acid | `#D4F54A` | `#D4F54A` | Lime accent (see rule 6) |
| danger / warn / ok | `#CC2933` / `#985D0E` / `#277953` | brighter equivalents | Status only |
| ochre / rose / teal / slate | `#926016` / `#C0345B` / `#18776F` / `#5A6273` | brighter equivalents | Category glyph colours |

Every text colour is at least 4.5:1 (WCAG AA) on bg, surface and sunken in both themes, and status colours
also meet it on their soft fills. inkFaint is the floor: use it for eyebrows, hints and tertiary icons,
never for anything lighter. If you retune a token, re-run the contrast check before merging.

## Spacing, shape and motion

- Spacing scale is 4, 8, 12, 16, 24, 32. Page gutter is 20.
- Radii are 10, 14, 20 and 28. Buttons and chips are full pills.
- Press feedback is a 0.97 scale plus a selection haptic. Springs use `easeOutBack` on **scale only**,
  never on size, because overshooting a size produces negative constraints.
- The floating ink capsule nav with a lime **+** is the signature Gen-Z element.
- **Launch:** the native splash shows Vo centred on `bg`, and `SplashIntro` continues from that exact frame.
  It is the app's one choreographed delight moment, so keep it under 2 s and skippable.

## Vaulty Glyphs

The icons sit on a 24-unit grid with a 1.7 stroke and rounded caps and joins. A filled dot is the only fill
allowed. To add one, add a value to `G` and a `case` in `_GlyphPainter`, then render it on the glyph sheet
next to its neighbours to check its weight.

## Components (`lib/widgets/common.dart`)

`VButton` (ink / brand / outline / ghost / danger) · `VIconButton` · `VCard` · `Hairline` · `Eyebrow` ·
`SectionHeader` · `CountdownTag` · `CategoryLabel` · `Monogram` · `UnderlineTabs` · `VChip` ·
`ListGroup` / `ListRow` · `EmptyState` · `toaster` / `showToast` · `confirmDialog` · `Wordmark`

Memory UI lives in `lib/widgets/memory_cards.dart`: `HeroCard`, `DateBlock`, `MemoryRow`, `MemoryList`,
`FactCard` and `MemoryGrid`.

## Sources

- [Tubik Studio: UI design trends 2026](https://tubikstudio.com/blog/ui-design-trends-2026/)
- [Made Good Designs: font trends 2026](https://madegooddesigns.com/font-trends-2026/)
- [Untitled UI: best free fonts for UI](https://www.untitledui.com/blog/best-free-fonts)
- [925 Studios: AI slop design tells](https://www.925studios.co/blog/ai-slop-design-tells)
- [DEV: the purple gradient problem](https://dev.to/james_anderson_h/the-purple-gradient-problem-why-ai-ui-all-looks-alike-and-how-to-fix-it-3j65)
- [Supercharged Studio: Gen Z design aesthetics](https://www.supercharged.studio/blog/gen-z-design-trends)
- [RevenueCat: how Opal scaled](https://www.revenuecat.com/blog/growth/kenneth-schlenker-sub-club-podcast-2026)
- [It's Nice That: Airbnb app redesign](https://www.itsnicethat.com/articles/airbnb-app-redesign-140525)
