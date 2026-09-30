# kino.pub HLS master (`files[].url.hls4`)

Not documented by kino.pub. Everything here was **captured**, not read: items 126352 (*Мятеж*,
movie, 13 dubs) and 127393 (*Трудно быть богом*, series, S1E1), 2026-09-28. The AVFoundation
half was read on **macOS 27.2** with a probe that loads the master and prints both media
selection groups; tvOS has not been checked the same way yet.

## Four stream types, and we play one

Every `files[]` row carries four links; kino.pub's device setting `streamingType` (device.md)
says which one a client is meant to use. We — and upstream's `BestVideoQualityFinder`, and the
community fork (checked 2026-09-29) — hard-code `hls4`. What AVFoundation sees in each, for
127393 and 126352:

| Link | What it is | Audio options | Subtitle options |
| --- | --- | --- | --- |
| `http` | progressive MP4 | — | — |
| `hls` | CDN packager, one quality, `…/master-v1a1.m3u8` | **1**, muxed, `Unknown` / `Язык не указан` | CC only |
| `hls2` | `api…/manifest/hls2/<mid>.m3u8`, three qualities | **1**, muxed, `Unknown` | CC only |
| `hls4` | `api…/manifest/hls4/<mid>.m3u8`, three qualities | **one per API row**, as below | the master's own list |

- In `hls` the audio is chosen **by the link**: `master-v1a2.m3u8` … `a4` all answer 200 with
  their own `index-v1-aN` playlist. A client on `hls` / `hls2` picks the dub outside the player
  and the system menu shows a single `Язык не указан` — which is what kino.pub's own TVML app
  shows (not verified in their code; matches the screen).
- `hls` / `hls2` carry the **first** row's audio (`index` 1) and no subtitle renditions, even on a
  title with 13 dubs and 5 subtitle tracks.

## What the master carries

```
#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="sub",NAME="RUS #01",LANGUAGE="rus",URI="…"
#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="sub",NAME="RUS #03 Forced",LANGUAGE="rus",FORCED=YES,URI="…"
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio1080",NAME="01. Дубляж. Пифагор (RUS)",LANGUAGE="rus",DEFAULT=YES,URI="…"
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio1080",NAME="09. Дубляж (UKR)",LANGUAGE="ukr",DEFAULT=NO,URI="…"
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio1080",NAME="13. Оригинал (ENG)",LANGUAGE="eng",DEFAULT=NO,URI="…"
… the same audio lines again under audio720 and audio480 …
#EXT-X-STREAM-INF:PROGRAM-ID=1,BANDWIDTH=5346327,VIDEO-RANGE=SDR,RESOLUTION=1920x960,CODECS="avc1.640028,mp4a.40.2",FRAME-RATE=23.976,HDCP-LEVEL=NONE,AUDIO="audio1080",SUBTITLES="sub"
```

- **One variant per quality** (1080 / 720 / 480), each with its own audio group. The audio lines
  are **repeated verbatim in every group** — same `NAME`, same `LANGUAGE`, same order. Subtitles
  are one shared group.
- **Audio `NAME` is built from the API row** (`audios[]` of that video):
  - `NN. <type.title>. <author.title> (<LANG>)` — `NN` is `index`, zero-padded;
  - `NN. <type.title> (<LANG>)` when `author` is null;
  - `Track N (<LANG>)` when `type` is null, with ` AC3` appended for an `ac3` row.
  `LANGUAGE` is the API's `lang` (ISO 639-2). **No** `AUTOSELECT`, `CHANNELS`, `CHARACTERISTICS`
  or `STABLE-RENDITION-ID`. `DEFAULT=YES` is always the first row.
- **The number is the only id the master shares with the API.** Type and studio exist in the
  master only as the Russian words the CDN wrote; their ids (`type.id`, `author.id`) are in the
  API row the number points to.
- An `ac3` row sits in the **same group** as the AAC rows, and the variant's `CODECS` lists only
  `mp4a.40.2`.
- **Subtitles are not the API's `subtitles[]`.** 126352: the master has five renditions —
  `RUS #01`, `RUS #02`, `RUS #03 Forced` (`FORCED=YES`), `RON #04`, `ENG #05` — the API three
  sidecar SRTs, `ron`, `rus`, `eng`, in that order. `#NN` is the rendition's position, not an API
  field; the API rows have no index, title or kind. Language is the only thing in common.

## The API side of the same tracks

One track in several codecs is **several rows**. 127393 S1E1 has one Russian track and three rows:

| `index` | `codec` | `channels` | `type` | `author` |
| --- | --- | --- | --- | --- |
| 1 | aac | 6 | null | null |
| 2 | aac | 6 | 6 / Orig | null |
| 3 | ac3 | 6 | null | null |

…and the master has three renditions for them (`Track 1 (RUS)`, `02. Оригинал (RUS)`,
`Track 3 (RUS) AC3`). The duplication is the source's, not ours.

## What AVFoundation makes of it (macOS 27.2)

- **Per-quality copies merge into one option.** 126352 → 13 audio options, 127393 → 3. The
  collapse `HLSAudioLabeler` performs is not needed for this.
- **A track in two codecs stays two options.** AVFoundation picks a codec by itself only when the
  same rendition (same `NAME`) sits in one group per codec and each variant's `CODECS` says which.
  `hls4` puts the AAC and AC-3 rows in the *same* group under different names, and `CODECS` lists
  only AAC — so to the player they are different tracks. That is how one Russian soundtrack in
  127393 becomes three menu rows in every client that plays `hls4` untouched.
- The legible group also offers **CC** (`transcribes-spoken-dialog`, `describes-music-and-sound`)
  with no `NAME` — the variants declare no `CLOSED-CAPTIONS`, so in-band captions are advertised.
- **How an audio option is named** — `displayName(with:)`, which is what the system menu shows:

| Option | UI in the rendition's language (ru UI, `rus`) | UI in another language |
| --- | --- | --- |
| `DEFAULT=YES` or `AUTOSELECT=YES` (main program content) | language only — `Русский` | language only |
| other, `NAME` starts with the language name | `NAME` as is — `Русский ∙ 2` | language only — `Russian` |
| other, any other `NAME` | `NAME — русский` | language only |

  So the system menu can tell two dubs apart **only in the viewer's own language, and never the
  default one.** Four Ukrainian dubs read `Украинский` ×4 to a Russian UI; eight Russian dubs read
  `Russian` ×8 to an English one. With no `DEFAULT=YES` anywhere, the first option shows its
  `NAME` like the rest. Subtitles follow the same rule, plus the system's own kind words
  (`Russian Forced`, `обязательные субтитры`).

*Apple API limitation* (macOS 27.2 SDK, probed): nothing in `NAME` reaches a viewer whose UI
language differs from the rendition's. Re-probe on tvOS and on the next SDK.
