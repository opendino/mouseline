# Codex prompts — MouseLine promo images and video

Give Codex the repository plus the screenshots in `dist/press/light` and `dist/press/dark`
(made with `MouseLine --snapshot <folder> --onscreen --light|--dark`). Run the prompts
separately. The screenshots contain a personal desktop picture behind the windows; the
prompts ask Codex to cut the windows out and use its own backgrounds.

---

## Prompt 1 — Marketing images

```
You are designing launch images for MouseLine, an open-source macOS menu bar app for mouse
gestures: hold the right mouse button, draw a line or shape, release, and an action runs
(snap a window, go back, play/pause, run a shortcut). Tagline: "Draw a line. Get it done."

Inputs in this repo:
- App screenshots: dist/press/light/*.png and dist/press/dark/*.png (settings window panes,
  the welcome guide, the calibration sheet, the gesture HUD). They were captured over a
  personal desktop picture: cut out only the windows (keep their rounded corners and
  shadows) and never show the original background.
- App icon: Support/AppIcon.icns (render the 1024 px image from it).
- Copy: docs/marketing/promo.md.

Brand:
- Colors: deep indigo gradient #545CF2 → #3D33B3 → #1A124D, glowing orange trail #FF8C1A
  with a warm glow #FF6B14, white glass highlights. Plenty of dark space; light versions use
  a soft lavender-to-white gradient.
- Look: Apple-style product marketing, macOS 26 "Liquid Glass" — frosted, translucent
  panels, soft shadows, generous spacing. Typography: SF Pro Display (or Inter as fallback),
  bold headlines, short lines.
- Signature visual: a glowing orange stroke drawn across the scene, ending in a small glass
  lens, like the in-app trail.

Deliver (PNG, sRGB) in docs/marketing/images/:
1. hero-1280x640.png — GitHub social preview. Icon + "MouseLine" + tagline, an orange stroke
   sweeping from a window to the right half of a stylized desktop.
2. Five 2880x1800 feature images (dark), each with one headline and one sub-line:
   a. "Draw a line. Get it done." — the gestures pane, a stroke snapping a window left.
   b. "Learns how you draw." — the calibration sheet, four strokes being drawn.
   c. "Different gestures for every app." — the gestures pane with an app selected
      (Finder) and the "Custom" badge visible.
   d. "Feels at home on macOS." — the welcome guide over a glassy background.
   e. "Light or dark. 20 languages." — a light and a dark window side by side, with a row
      of language names (English, Türkçe, Español, Deutsch, 日本語, 简体中文, العربية …).
3. The same five in light mode (suffix -light).
4. readme-banner-1600x500.png — wide banner for the top of the README.

Rules: do not invent features; use only what the screenshots and promo.md show. Keep text
inside a 90% safe area. Add a short README section "Screenshots" that embeds the images, and
write docs/marketing/images/README.md listing each file and its purpose.
```

---

## Prompt 2 — Promo video

```
Create a 35-second promo video for MouseLine, an open-source macOS app for mouse gestures.
Build it in code with Remotion (React) in a new folder promo/ in this repo, so it can be
re-rendered when the app changes. Use the screenshots in dist/press/ (cut the windows out of
their background), Support/AppIcon.icns and the copy in docs/marketing/promo.md.

Style: Apple-like product film, macOS 26 Liquid Glass look. Dark indigo backgrounds
(#1A124D → #545CF2), a glowing orange stroke (#FF8C1A, glow #FF6B14) as the recurring motif,
smooth spring animations, SF Pro / Inter typography, no stock footage, no voice-over.
Background music: leave a placeholder track slot and render a silent version too.

Storyboard (timings at 30 fps):
0–3 s   Black → the app icon fades in; an orange stroke draws itself around it. Text:
        "MouseLine".
3–8 s   A stylized desktop with two windows. A cursor holds the right button and draws a line
        to the left (glowing trail, small glass lens at the tip). On release the front window
        snaps to the left half; a glass capsule HUD "Left · Tile window left" pops up at the
        bottom. Text: "Draw a line."
8–13 s  Three quick gestures in a row: up (window maximizes), a line left over a browser
        (page goes back), a stroke right over a music player (next track). Each shows the HUD.
        Text: "Get it done."
13–19 s The settings window (gestures pane) slides in on glass; zoom into the shape list and
        the action pickers. Text: "32 shapes. Any action: windows, media, shortcuts, apps,
        scripts."
19–24 s The calibration sheet: the progress dashes fill as four strokes are drawn. Text:
        "Learns how you draw."
24–28 s The sidebar's App-Specific Gestures with Finder selected, the "Custom" badge
        highlighted. Text: "Different gestures for every app."
28–31 s Light and dark windows side by side, language names flowing past. Text:
        "Light or dark. 20 languages."
31–35 s Icon, "MouseLine", "Free and open source for macOS", and the GitHub URL placeholder
        github.com/<owner>/MouseLine. The orange stroke underlines the URL.

Deliver:
- promo/ Remotion project with a README (install, preview, render commands).
- Renders: promo/out/mouseline-promo-1920x1080.mp4 (H.264, 30 fps) and a vertical
  1080x1920 cut for social media, plus a 6-second looping GIF of the snap gesture for the
  README (promo/out/snap-loop.gif, ≤ 3 MB).
Rules: everything shown must match the real app (screenshots, names, wording in promo.md).
Do not add a voice-over or claims that are not in promo.md.
```

---

## Prompt 3 — Short GIFs for the README (optional)

```
In the promo/ Remotion project, add three 4–6 second looping compositions rendered as GIFs
(≤ 3 MB each, 960 px wide) to docs/marketing/images/: snap-left.gif (line left snaps a
window), calibrate.gif (calibration dashes filling), per-app.gif (switching an app's
override in the settings window). Same visual language as the promo video. Embed them in the
README's Screenshots section.
```
