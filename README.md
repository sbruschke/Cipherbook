# Cipherbook

An iOS EPUB reader built for learning a cipher: every word can be rendered in
**two typefaces at once** — the main font on the line, a smaller second font
directly underneath it (WebKit ruby annotations, positioned under the text).

- Import `.epub` files (Files app / share sheet / the app's Documents folder).
- Import your own `.ttf` / `.otf` fonts and switch fonts in two taps.
- Main font + sub font, independent; swap them with one toggle.
- Text size, line spacing, margins, letter spacing, justification, 4 themes.
- Chapter list from the EPUB 3 nav doc or EPUB 2 NCX; reading position is saved.

## Build

Unsigned IPA is produced by GitHub Actions (`.github/workflows/build-ipa.yml`)
on a macOS runner:

```
xcodegen generate
xcodebuild -scheme Cipherbook -sdk iphoneos CODE_SIGNING_ALLOWED=NO build
```

Then `./scripts/fetch-latest-ipa.sh` pulls the artifact locally for sideloading.
