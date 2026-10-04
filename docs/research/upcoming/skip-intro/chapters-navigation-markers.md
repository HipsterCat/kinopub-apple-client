# Skip markers — chapters (`navigationMarkerGroups`)

## Mechanism
`AVPlayerItem.navigationMarkerGroups` ([Apple docs](https://developer.apple.com/documentation/avfoundation/avplayeritem/navigationmarkergroups)) with `AVTimedMetadataGroup`s shows chapters in the system scrubber/info panel. ROADMAP stage 7: "Chapters via `navigationMarkerGroups`, once any marker source exists".

## Proposal
Build chapters from the validated segments: "Recap", "Intro", "Episode", "Credits". Titles go through `Localizable.xcstrings` (RU + EN). Only when at least one marker exists; never synthesise empty chapters.

## Prior art
Parallax highlights the current chapter in its chapter menu ([9a15d23](https://github.com/eutialia/Parallax/commit/9a15d23)); strimr has chapter navigation + scrubbing thumbnails (README).

## Effort
S · P2.
