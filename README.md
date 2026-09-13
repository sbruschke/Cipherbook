# Cipherbook

An iOS EPUB reader built for learning a cipher: every word can be rendered in
**two typefaces at once** — the main font on the line, a smaller second font
directly underneath it (WebKit ruby annotations, positioned under the text).

- Import `.epub` files (Files app / share sheet / the app's Documents folder).
- Import your own `.ttf` / `.otf` fonts and switch fonts in two taps.
- Main font + sub font, independent; swap them with one toggle.
- Text size, line spacing, margins, letter spacing, justification, 4 themes.
- Optional **punctuation tint**: every Unicode P/S character takes its own
  colour, the way the print editions set punctuation in blue (`#000091`).
- Optional **cell grid**: dots at every character-cell corner (a space wide, a
  line tall), anchored so the body type lands on the grid, as in the print
  build's `--grid`.
- Chapter list from the EPUB 3 nav doc or EPUB 2 NCX; reading position is saved.

## Build

Unsigned IPA is produced by GitHub Actions on a macOS runner:

```
xcodegen generate
xcodebuild -scheme Cipherbook -sdk iphoneos CODE_SIGNING_ALLOWED=NO build
```

- `build-ipa.yml` — compile check on pull requests and manual dispatch.
- `release.yml` — **every push to main that touches `App/`, `Core/`,
  `Resources/` or `project.yml`** builds, packages, and commits the IPA plus a
  refreshed `source.json`, then tags the release. The LiveContainer feed
  therefore never lags behind main.

## Versioning

`MARKETING_VERSION` in `project.yml` is the single source of truth for the
human-facing version; the **build number is the release workflow's run number**,
so it increases on every publish. That is what makes LiveContainer offer an
update even when the marketing version has not moved — a release whose build
number did not increase is invisible to the installed app.

```
./scripts/version.sh                 # what is main on right now
./scripts/bump-version.sh minor      # major | minor | patch | X.Y.Z
./scripts/fetch-latest-ipa.sh        # pull down what the feed is serving
```

Bump the marketing version for user-visible features; leave it alone for fixes
and let the build number carry them.

Source feed: `https://raw.githubusercontent.com/sbruschke/Cipherbook/main/source.json`
