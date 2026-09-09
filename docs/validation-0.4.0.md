# BrewDesk 0.4.0 validation

Validated on the development Apple Silicon Mac, 2026-09-09. This is an ad-hoc signed preview, not a notarized release.

## Automated checks

`./scripts/test.sh`: 37 tests, one optional local-fixture test skipped, zero failures. New manager fixtures exercise command scope and identifier validation, npm/pip/pipx/uv/Cargo/RubyGems parsing, installation and removal with observed state changes, npm update discovery, verified upgrades, stale confirmations, and preservation of the previous list on registry errors. These fixtures execute temporary test scripts, not real package mutations.

A short-process stall was reproduced in Foundation `waitUntilExit`. Read processes now observe termination before launch and drain both pipes concurrently. Existing pipe, exit, interruption and terminal prompt tests pass.

`./scripts/package-dmg.sh` completed. The app bundle includes the MIT LICENSE and third-party notices and passes the build script's strict signature verification outside the File Provider workspace.

## Computer Use checks

- Homebrew: existing installed list loaded after automatic discovery.
- npm: selected the user-global environment; six installed entries were shown. A read-only update check marked five updates. Registry search returned `typescript` and scoped packages. The installation confirmation for `@babel/preset-typescript` displayed the selected executable, global prefix and reviewed version; it was cancelled.
- pip3: selected a Homebrew-provided pip3; four installed entries and four available updates were shown. Exact-name PyPI lookup loaded `requests` and its description/version.
- uv: the installed tool `ouroboros-ai` was listed. A separate read-only CLI check validated the tool-Python outdated JSON command.
- Cargo: the selected install root had an empty installed list; exact-name crates.io lookup loaded `ripgrep` and its stable version.
- RubyGems: the selected executable loaded 86 installed entries, with default gems excluded from upgrades. Computer Use temporarily timed out during the transition; reconnection confirmed the completed list. The app process and direct gem listing were also inspected.
- pipx was not installed on this Mac. Its parser, command generation, install/remove verification and history were exercised with fixtures; no live pipx installation was performed.

No real package installation, upgrade or removal was performed for this validation. Real authenticated mutations, private indexes and all possible manager/runtime versions are not covered by these checks. Existing walkthrough media remains the earlier Homebrew demonstration and does not demonstrate the new managers.
