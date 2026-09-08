# App icon

`assets/BrewDesk-icon.png` is the square, opaque master artwork (1254 × 1254 pixels). Replacement masters should be square PNGs at least 1024 × 1024 pixels. `assets/BrewDesk.icns` contains multiple square macOS representations from 16 × 16 through 1024 × 1024 pixels and is copied into the app bundle by `scripts/build-app.sh`, with `CFBundleIconFile` pointing to it. From the repository root, regenerate `assets/BrewDesk.icns` on macOS with `./scripts/build-icon.sh` after replacing the master.

Created with the built-in image_gen tool. Art direction: a warm orange package cube and green verification badge on charcoal, with a bold silhouette and no text. Final edit prompt: “Preserve orange package and green check. Remove all checkerboard pattern entirely. Replace entire backdrop with uniform deep charcoal #202427 extending edge-to-edge to all four square canvas edges. No transparency, no checkerboard, no rounded tile outline, no exterior margin. Full-bleed square dark charcoal app icon, same centered large orange package and green check, no text. All corners must be solid dark charcoal.”

The ICNS representations use the same artwork, resized with macOS `sips` and packaged with `iconutil`.
