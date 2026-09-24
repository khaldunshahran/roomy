# Roomy App Icon — note for the integrator

## Master

`icon-1024.png` is the **1024×1024 icon master**. It is the only icon source file
in the repo:

- Generated 2026-09-24 with the media image tool.
- Design: simple flat motif — a roomy/open box (expanding-photo-frame feel) in
  warm teal with a coral accent on a deep navy background. No text.
- Composed with generous margins around the subject, so it is safe under iOS's
  rounded-square ("squircle") masking — nothing important touches the edges.

## Generating the iconset

From this master, export the standard iOS icon sizes and place them in:

```
Roomy/Roomy/Assets.xcassets/AppIcon.appiconset/
```

Sizes (points × scale → pixels): **20, 29, 40, 58, 60, 76, 80, 87, 120, 152,
167, 180, 1024**.

Example export with ImageMagick (run from `AppIcon-src/`):

```powershell
# PowerShell
$sizes = 20,29,40,58,60,76,80,87,120,152,167,180,1024
foreach ($s in $sizes) {
    magick icon-1024.png -resize "${s}x${s}" "../Assets.xcassets/AppIcon.appiconset/icon-$s.png"
}
```

Then add a `Contents.json` in the `.appiconset` folder describing each file.
Apple's template maps each size to its idiom/scale slot; the required entries
are:

| filename | idiom | scale | size |
|---|---|---|---|
| icon-20.png | iphone | 2x | 20x20 |
| icon-20.png | iphone | 3x | 20x20 |
| icon-29.png | iphone | 2x | 29x29 |
| icon-29.png | iphone | 3x | 29x29 |
| icon-40.png | iphone | 2x | 40x40 |
| icon-40.png | iphone | 3x | 40x40 |
| icon-60.png | iphone | 2x | 60x60 |
| icon-60.png | iphone | 3x | 60x60 |
| icon-76.png | ipad | 1x | 76x76 |
| icon-76.png | ipad | 2x | 76x76 |
| icon-80.png | iphone | 2x | 40x40 |
| icon-80.png | iphone | 3x | 40x40 |
| icon-87.png | iphone | 3x | 29x29 |
| icon-120.png | iphone | 2x, 3x | 60x60 |
| icon-152.png | ipad | 2x | 76x76 |
| icon-167.png | ipad | 2x | 83.5x83.5 |
| icon-180.png | iphone | 3x | 60x60 |
| icon-1024.png | ios-marketing | 1x | 1024x1024 |

(Several sizes reuse the same pixel file at different scale slots — e.g. 120px
serves both 2x and 3x 60pt. Export once, reference as needed.)

## Do not edit the master destructively

If the icon needs changes, regenerate a new master and re-export — never
hand-edit the exported pixel files.
