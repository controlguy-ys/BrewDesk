# BrewDesk

<img src="assets/BrewDesk-icon.png" alt="BrewDesk app icon" width="128">

Homebrew, npm, pip3, pipx, uv, Cargo and RubyGems, in one native macOS app.

**English** · [한국어](README.ko.md)

[Download v0.4.0 for Apple Silicon](https://github.com/controlguy-ys/BrewDesk/releases/tag/v0.4.0) · [Watch the 60-second walkthrough](docs/media/brewdesk-walkthrough.mp4)

![BrewDesk installed packages](docs/media/installed-en.png)

## Download and run

1. Have at least one supported package manager installed. BrewDesk detects existing executables; it does not install package managers for you.
2. Download `BrewDesk-0.4.0-macos-arm64.dmg` from the [release page](https://github.com/controlguy-ys/BrewDesk/releases/tag/v0.4.0).
3. Open the DMG, drag **BrewDesk** into **Applications**, and launch it.
4. Choose a package manager and environment in the sidebar. Use **Settings → Manager to add → Choose executable…** for a custom executable, including a virtual environment’s pip3.

Requires **macOS 14 or newer**. The downloadable build is for **Apple Silicon**. Intel builds can be compiled on an Intel Mac but have not been validated here.

**Preview build:** the app is ad-hoc signed, with no Developer ID signature or Apple notarization. macOS may block a downloaded copy. If you trust this release and choose to run it, use the app-specific **Open Anyway** option in **System Settings → Privacy & Security** after attempting to open it. See [Apple’s guidance](https://support.apple.com/en-us/102445). Do not disable Gatekeeper globally. Validation so far covers the development Mac; installation on a separate Mac remains untested.

Download both the DMG and `SHA256SUMS.txt` into the same directory. Open Terminal in that directory and check the downloaded DMG:

```sh
shasum -a 256 -c SHA256SUMS.txt
```

## What you can do

BrewDesk manages packages in the selected environment. Switching environments clears the current selection, filters and pending confirmation.

- Browse installed packages with search, sorting, checkboxes and Select All (⌘A).
- Inspect installed and available versions. Homebrew also provides dependencies and verified installation paths; other managers may provide less detail.
- Review the exact command and targets before an update or removal.
- Update multiple selected packages sequentially. A failure stops the remaining queue.
- Authenticate in the embedded terminal and inspect operation results and version changes.
- Switch between **English**, **한국어**, and **System language**. English is the default.

### A typical workflow

Select an environment and package to inspect its details. **Check for updates** queries available versions; Homebrew first reviews and runs `brew update`. **Refresh list** reads installed state and repeats availability queries if this environment has already been checked.

Some Cask installers or uninstallers may request administrator authentication. These prompts come from the underlying Homebrew or installer operation; respond in the embedded terminal. BrewDesk does not provide a separate password form.

Use the checkbox to the left of each package to select it. Above the list, **Select all** adds all visible packages, **Deselect all** clears the entire selection, and the selection count includes selected packages hidden by filters. **⌘A** selects all visible rows when the table has focus; in the search field it selects the search text. Command-click and checkboxes share the same selection. **Update all (N)…** reviews every eligible installed update regardless of search or filters, excluding pinned packages. **Update selection** includes only selected packages with available updates, excluding pinned packages. One confirmation approves the reviewed batch. Changes run one at a time. After an operation, BrewDesk queries the selected manager again and records observed version changes, including dependencies.

Formula removal is blocked when installed dependents are found. Cask removal uses ordinary `brew uninstall --cask`; Homebrew’s uninstall scripts may run. There is no forced removal or `--zap` cleanup. Stopping an operation sends Ctrl-C; it does not roll back changes. The app prevents quitting while an operation is active.

## See it in action

[![Watch the real Computer Use recording](docs/media/package-details.png)](docs/media/brewdesk-walkthrough.mp4)

**[Watch or download the MP4](https://github.com/controlguy-ys/BrewDesk/releases/download/v0.2.0/brewdesk-walkthrough.mp4)** — a silent, continuous 60-second recording at 1920 × 1080. App interactions were performed through Computer Use and captured by macOS. It shows package details, a removal confirmation followed by cancellation, and live English/Korean switching. No package was updated or removed for the demonstration.

| Review a removal | Use Korean |
| --- | --- |
| ![Removal confirmation](docs/media/removal-confirmation.png) | ![Korean language settings](docs/media/language-ko.png) |

[All screenshots and capture notes](docs/media/README.md)

## Package managers and scope

| Manager | Managed scope | New package lookup | Update check |
| --- | --- | --- | --- |
| Homebrew | Selected prefix, Formulae and Casks | Name search; All types by default | `brew update`, then installed/outdated metadata |
| npm | Global packages under the selected npm prefix | npm registry search | `npm outdated --global --json` |
| pip3 | Packages visible to the selected pip3 executable | Exact name on PyPI | `pip3 list --outdated --format=json` |
| pipx | Installed isolated tools, excluding injected libraries as separate entries | Exact name on PyPI | `pipx runpip <tool> list --outdated` |
| uv | Installed `uv tool` tools | Exact name on PyPI | `uv pip list --outdated` against each tool’s Python |
| Cargo | Binaries installed with `cargo install` in the selected root | Exact name on crates.io | Stable registry version comparison |
| RubyGems | Gems visible to the selected gem executable | Exact name on rubygems.org | `gem outdated` |

**Environment** means the selected executable and its resolved installation location. npm uses its global prefix, pip3 uses its Python environment, pipx/uv use their tool directories, and RubyGems uses its configured gem home and paths. Cargo uses CARGO_INSTALL_ROOT, then CARGO_HOME, then ~/.cargo. Custom executables are run for version and location discovery; failures are shown in Settings when adding them.

**Check for updates** queries the selected environment. **Update** uses the last successful check and reviews all available, unpinned upgrades in that environment, including hidden and unselected packages; filters do not limit this batch. Initial non-Homebrew lists show **Updates not checked** until a check succeeds. Changes remain sequential and stop at the first failure or unresolved verification. Results appear in the console and History. You answer recognized terminal Yes/No prompts in a popup; other interactive input remains in the terminal. The app never answers on your behalf.

Project `node_modules`, requirements files, Cargo projects and Bundler lockfiles are not edited. Virtual environments are not searched recursively or changed automatically; choose their pip3 executable explicitly. No `sudo`, `--break-system-packages`, or forced removal is added. An externally managed Python or a protected Ruby installation may reject a change, and that failure remains visible. npm linked packages, Ruby default gems, Cargo local/git installs, and pipx pinned/custom specifications are excluded from both individual and batch upgrades. Their removal controls remain available; the manager can still reject removal of protected packages. RubyGems removal explicitly reviews removal of **all versions** of the selected gem.

Python, Cargo and RubyGems catalog lookup uses the named public registry. Installation and update resolution use the selected manager’s configuration; private indexes, runtime requirements, pins and tool constraints can affect the result. npm/pip/Cargo/RubyGems install commands use the reviewed version. pipx/uv install by package name and retain the manager’s normal tool requirements; the registry can change between review and execution. Tool constraints that prevent an upgrade are reported as unresolved verification, not a successful update. Cargo comparisons cover stable three-component versions; prerelease/custom versions do not receive inferred upgrades.

Reference: [npm outdated](https://docs.npmjs.com/cli/v11/commands/npm-outdated/), [pip list](https://pip.pypa.io/en/stable/cli/pip_list/), [PyPI JSON API](https://docs.pypi.org/api/json/), [uv commands](https://docs.astral.sh/uv/reference/cli/), [Cargo install](https://doc.rust-lang.org/cargo/commands/cargo-install.html), [RubyGems commands](https://guides.rubygems.org/command-reference/).

## Install packages

Select an environment, then open **Install packages**. For Homebrew, leave **All types** selected to search Formulae and Casks together (or narrow the type), enter a package name, and press Search or Return. Select a result to load its description, version, dependencies, and homepage. **Install…** opens a confirmation with the exact command. Installed packages cannot be installed again from this screen. After installation, BrewDesk verifies the installed package and records its changes. Search displays up to 200 matches; narrow the query when needed. Package metadata stays in Homebrew’s original language.

The top-right toolbar has **Check for updates** on the left and **Update** on the right. The left button checks the selected environment (running `brew update` for Homebrew); the right reviews all available unpinned package upgrades in that environment. Refresh installed state with **⌘R** or the View menu.

## History and terminal confirmations

Click anywhere on a history summary row, including its result, date, or blank space, to expand or collapse it. Log text selection and copy/save buttons remain independent.

Explicit terminal questions ending in `[y/n]` or `(yes/no)` are shown in a **Yes / No** popup while the process is waiting in normal line-input mode. The answer is sent to the running process; **Respond in terminal** leaves it unanswered for manual input. Password prompts, raw-input prompts, and unrecognized questions remain in the terminal. Detection resumes when normal echoed line input returns after authentication; secret-input log suppression remains in force. No response is sent automatically.

## Language support

Open **Settings → Language → App language**. Changes apply immediately and persist across launches. **System language** selects the first supported English or Korean language in macOS preferences, falling back to English. Relaunch BrewDesk after changing macOS language preferences.

App-owned screens, confirmation dialogs, errors, and new history result summaries are localized. Package names, Homebrew descriptions, raw terminal output, and legacy history snapshots retain their original text.

Translations live in [`en.json`](Sources/BrewDesk/Resources/en.json) and [`ko.json`](Sources/BrewDesk/Resources/ko.json). Placeholders such as `{0}` preserve dynamic values. Missing translations fall back to English, then to the original key. To add a language, register it in [`Localization.swift`](Sources/BrewDesk/Localization.swift), add its catalog and system-language resolution, and update `CFBundleLocalizations` in the build script. Catalog tests check matching keys and placeholders.

## Build and test

Building requires a Swift 6 toolchain and an internet connection for the initial pinned SwiftTerm dependency download. Tested with Swift 6.3 from Command Line Tools and Xcode 26.6. Command Line Tools suffice for building; tests require full Xcode with XCTest. `scripts/test.sh` selects `/Applications/Xcode.app/Contents/Developer` when available; set `DEVELOPER_DIR` to your Xcode developer directory if installed elsewhere. The scripts build for the host Mac’s CPU architecture.

```sh
git clone https://github.com/controlguy-ys/BrewDesk.git
cd BrewDesk
./scripts/test.sh
./scripts/build-app.sh
open dist/BrewDesk.app
```

Create a DMG with `./scripts/package-dmg.sh`. Output is `dist/BrewDesk-local.dmg`. During development, `swift run BrewDesk` also works. For everyday use, copy the app from the DMG to Applications; File Provider folders can add metadata that affects signature verification.

The XCTest suite covers command validation, JSON parsing, version changes, history permissions, large stderr output, PTY exits and interruption, secret-input handling, operation sequencing, and localization. The default run skips one optional local fixture test. These tests do not update or remove real Homebrew packages. Real administrator-authenticated Cask changes remain outside the completed validation.

| Source | Responsibility |
| --- | --- |
| `Domain.swift` | Package models, command allowlist, version differences |
| `BrewRepository.swift` | Homebrew queries, read processes, local history |
| `ManagerRepository.swift` | npm, pip3, pipx, uv, Cargo and RubyGems adapters |
| `PTYRunner.swift` | SwiftTerm terminal and child-process lifecycle |
| `AppModel.swift` | UI state, sequential operations, verification |
| `BrewDeskApp.swift` | Native views, settings, and quit protection |
| `Localization.swift` | Language preferences, catalogs, dynamic messages |

## Local data and limits

History stores the latest 200 command records in `~/Library/Application Support/BrewDesk/history.json`, with directory permissions `0700` and file permissions `0600`. Terminal input is not saved. Output is omitted while terminal echo is disabled and for the remainder of an operation after secret input is sent. Saved logs may therefore be incomplete. Terminal output and manually exported logs can contain local paths and installer messages.

BrewDesk does not manage services, elevate privileges, or roll back changes. Self-updating and `latest` Casks have update-check limitations. Observed changes cannot always distinguish BrewDesk operations from concurrent external modifications.

Built with SwiftUI and [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm). See [third-party notices](THIRD_PARTY_NOTICES.md). Homebrew command behavior is documented in the [Homebrew manual](https://docs.brew.sh/Manpage) and [JSON query documentation](https://docs.brew.sh/Querying-Brew).

## License

BrewDesk is licensed under the [MIT License](LICENSE). Third-party components retain their respective licenses; see [third-party notices](THIRD_PARTY_NOTICES.md).
