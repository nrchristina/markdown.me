# Markdown.me

A native Markdown editor for macOS. Write with the formatting visible, or edit the Markdown source directly. The file on disk stays plain Markdown either way.

> **Status: in development, not released yet.** The Markdown engine is done and tested; the app itself is being built. The plan is in [`docs/PLAN.md`](docs/PLAN.md) (in Russian).

<!-- Screenshot: add once the app has a window. -->

## Features

Planned for 1.0:

- **Two views of one file.** The text view hides the Markdown syntax and shows the formatting. The Markdown view shows the source with highlighting. Switch with ⌘/. Switching never changes the file.
- **Formatting from the keyboard or the toolbar.** Bold ⌘B, italic ⌘I, strikethrough ⌘⇧X, headings ⌘1–⌘3, links ⌘K. Lists, checklists, quotes, code, images and horizontal rules are in the toolbar.
- **Folders as workspaces.** Open a folder, browse it in the sidebar, keep several files open. Changes made by other apps or by `git checkout` are picked up.
- **PDF export** with ⌘E.
- **Text color and size.** They are stored as inline HTML, so the file is still valid Markdown.
- **Light and dark themes**, following the system or set by hand. English and Russian interface.

## Download

There is no release yet. Releases will be on the [Releases page](https://github.com/nrchristina/markdown.me/releases) as `MarkdownMe.dmg`, signed with an Apple Developer ID and notarized by Apple.

Requires macOS 14 Sonoma or later, on Apple Silicon or Intel.

Markdown.me is free. There is no account, license key or telemetry. The app contacts GitHub to check for updates, and you can turn that off in Settings.

## Build from source

You need macOS 14 or later and Xcode 26 (Swift 6.2).

```sh
git clone https://github.com/nrchristina/markdown.me.git
cd markdown.me
swift test
```

`swift test` runs the tests of `MarkdownCore`, the editor's Markdown engine. It needs only Swift 6.2, so it runs on Linux too; CI runs it on every push.

The app target and `scripts/build-app.sh`, which builds a signed `Markdown.me.app`, are not in the repository yet.

## Repository

| Path | Contents |
|---|---|
| `Sources/MarkdownCore` | Markdown parsing for highlighting, and the formatting commands. No AppKit or SwiftUI. |
| `Tests/MarkdownCoreTests` | Tests for `MarkdownCore`. |
| `docs/spec.md` | Requirements (in Russian). |
| `docs/PLAN.md` | Architecture decisions and the task list (in Russian). |
| `docs/macos-signing-tcc.md` | Code signing and privacy permissions (in Russian). |
| `docs/site-copy.md` | Texts for the website, in English and Russian. |
| `release-notes/` | Release notes, one file per version. |
