# PR Dock

A native macOS pull-request docklet that floats above normal application windows.

## Features

- Compact bottom-edge view with your latest open pull requests
- Expands on hover with a native spring animation
- Pin, refresh, open, and squash-merge controls
- Review, CI, conflict, draft, diff, and branch status
- Automatically positions beside a left or right macOS Dock
- Menu-bar controls and no permanent Dock icon
- Refreshes from GitHub every minute

## Requirements

- macOS 13 or later
- Swift 5.9 or later
- [GitHub CLI](https://cli.github.com/) installed and authenticated:

```sh
brew install gh
gh auth login
```

## Run

```sh
make run
```

To install it in `~/Applications`:

```sh
make install
```

PR Dock uses the active GitHub CLI account and never stores a token itself.
