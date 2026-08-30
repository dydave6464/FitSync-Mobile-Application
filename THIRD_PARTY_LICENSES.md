# Third-party licenses

Components in FitSync that are not the work of the repository owner, and the
terms each is used under.

---

## 1. Exercise dataset — data

**Source:** [hasaneyldrm/exercises-dataset](https://github.com/hasaneyldrm/exercises-dataset),
pinned at commit `7455efae41b330c265e7cd4b78dfa848e7ce5ebd`.

**Used for:** exercise names, categories, body parts, equipment, targets and
muscle groups, and the English coaching cues.

**Licence:** MIT.

```
MIT License

Copyright (c) 2026 Hasan Emir Yıldırım

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation and data files (the "Software"),
to deal in the Software without restriction, including without limitation the
rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
sell copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

## 2. Exercise media — animations and thumbnails

> **© Gym visual — https://gymvisual.com/**

**Used for:** the exercise animation GIFs and thumbnail images referenced by
`exercises.animation_url` and `exercises.thumbnail_url`.

The MIT licence in section 1 does not extend to these files; the dataset's
`LICENSE` carries an explicit media exception.

**Conditions:**

- **Attribution.** The credit `© Gym visual — https://gymvisual.com/` accompanies
  the media wherever it is displayed.
- **Resolution.** The media is used at **180×180**, unmodified.

**Governing terms:** https://gymvisual.com/content/3-terms-and-conditions-of-use

---

## 3. Typefaces — Space Grotesk and JetBrains Mono

**Source:** [google/fonts](https://github.com/google/fonts) —
`ofl/spacegrotesk/SpaceGrotesk[wght].ttf` and
`ofl/jetbrainsmono/JetBrainsMono[wght].ttf`.

**Used for:** the entire app UI (Space Grotesk) and numeric/label text
(JetBrains Mono), bundled under `client/assets/fonts/` as variable fonts.

Bundled rather than fetched from Google Fonts at runtime, so the app renders
identically offline.

**Licence:** SIL Open Font License 1.1 — both families.

- Space Grotesk © Florian Karsten.
- JetBrains Mono © JetBrains s.r.o.

**Conditions:**

- **Attribution.** The copyright notices above are retained here, and the OFL
  text ships inside each font file's metadata.
- **No standalone sale.** The fonts are distributed only as part of this
  application, never sold on their own.
- **Reserved names.** Neither font is renamed or distributed under a Reserved
  Font Name.

**Full licence text:** https://openfontlicense.org
