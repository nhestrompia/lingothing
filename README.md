# LingoThing

LingoThing is a macOS menu bar app for language practice.

## Install

### Homebrew (tap + cask)

```bash
brew tap nhestrompia/lingothing https://github.com/nhestrompia/lingothing
brew install --cask nhestrompia/lingothing/lingothing
```

### Manual install

1. Open [Releases](https://github.com/nhestrompia/lingothing/releases).
2. Download `LingoThing-<version>.app.zip`.
3. Unzip and move `LingoThing.app` into `/Applications`.

## Update

### Homebrew

```bash
brew update
brew upgrade --cask nhestrompia/lingothing/lingothing
```

### Manual

Download the latest release ZIP and replace the app in `/Applications`.

## Uninstall

### Homebrew

```bash
brew uninstall --cask nhestrompia/lingothing/lingothing
brew untap nhestrompia/lingothing
```

### Manual

Delete `/Applications/LingoThing.app`.

## Release Checklist

1. Build/sign/notarize and regenerate cask:

   ```bash
   ./scripts/release-macos.sh --version 0.1.0 --notary-profile <your-profile>
   ```

2. Commit release files:

   ```bash
   git add Casks/lingothing.rb dist/checksums.txt
   git commit -m "release: v0.1.0"
   git push
   ```

3. Create GitHub release:
   - Tag: `v0.1.0`
   - Title: `v0.1.0`
   - Assets: `LingoThing-0.1.0.app.zip` and `checksums.txt`

Tag and cask version must match (`v0.1.0` <-> `version "0.1.0"`), or Homebrew install will fail.

## Notes

- `brew install --cask nhestrompia/lingothing/lingothing` alone will try to clone `nhestrompia/homebrew-lingothing`.
- Because this project repo is `nhestrompia/lingothing`, use the explicit tap URL command shown above.
