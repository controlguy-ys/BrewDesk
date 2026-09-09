# App icon

`assets/BrewDesk-icon.png` is the user-supplied terminal-and-mug artwork, cropped from the supplied 1280 × 698 JPEG to a 440 × 440 square at x=420, y=120. Its original design is preserved. The source is opaque; larger icon representations are upscaled from the supplied pixels.

`assets/BrewDesk.icns` contains square representations from 16 × 16 through 1024 × 1024 pixels. From the repository root, run `./scripts/build-icon.sh` on macOS after replacing the master. The script uses `sips` and `iconutil`. `scripts/build-app.sh` copies the ICNS into the app bundle and declares it using `CFBundleIconFile`.
