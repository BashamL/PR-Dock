# PR Dock

PR Dock is a native macOS 26 pull-request companion that lives in the unused
space beside the Dock. It stays compact at rest and expands into a focused PR
cockpit when clicked.

## What’s in v2

- Native Liquid Glass that adapts to the desktop and accessibility settings
- Dock-aware leading or trailing placement across bottom and side Docks
- Available across desktop Spaces without overlaying full-screen apps
- Compact preview of the latest pushed owned PR with merge and CI status
- Authored pull requests and pull requests awaiting your review
- “Needs attention,” “Ready,” “Review requests,” and “Waiting” sections
- CI, review, conflict, draft, branch, comment, and diff context
- Last-successful cache for instant launch and offline visibility
- Rate-limit-aware refresh, wake refresh, retry states, and typed setup errors
- Status-aware menu-bar icon and right-click utility menu
- Safe squash merge with a fresh status check and explicit confirmation
- Settings for PR scopes, placement, refresh cadence, GitHub CLI path, and
  launch at login
- VoiceOver labels, keyboard focus, high-contrast support, and reduced motion

PR Dock uses Apple’s public Liquid Glass APIs. macOS does not expose a public
API for third-party apps to extend or join the system Dock itself, so PR Dock is
a separate borderless companion panel that follows the Dock’s available area.
It does not read private Dock preferences or request Accessibility or Screen
Recording permission.

## Requirements

- macOS 26 or later
- Swift 6.2 or later
- [GitHub CLI](https://cli.github.com/) installed and authenticated:

```sh
brew install gh
gh auth login
```

PR Dock uses the active GitHub CLI account. It never reads or stores your
GitHub token.

## Build and run

```sh
make run
```

Install the ad-hoc-signed local build in `~/Applications`:

```sh
make install
```

Other commands:

```sh
make build
make test
make app
make clean
```

The generated app is at `build/PR Dock.app`. Public distribution still requires
signing with a Developer ID certificate and notarizing the final archive.

## Using PR Dock

- Click anywhere on the compact strip to expand it.
- Click outside the expanded panel, or use its collapse button, to close it.
- Click a pull request to open it on GitHub.
- Right-click a row to open it or copy its branch.
- Use the merge button only on authored PRs that GitHub reports as ready.
- Left-click the menu-bar icon to show or hide the panel; right-click it for
  refresh, Settings, GitHub, and quit actions.

## Privacy

GitHub requests and merge operations run through the authenticated `gh`
executable. PR metadata from the last successful sync is cached locally in the
user’s Application Support directory. PR Dock does not collect analytics,
tracking data, credentials, or other personal data.
