# Player Lab

A throwaway tvOS simulator app: a plain list of **real catalogue titles** (Plozz's
`KinoPubDemoCatalog.json`, real posters and Russian text), each played in the system player the way
one approach would play it. Every row lists the AVKit API it exercises in `[brackets]`. The metadata
comes from the real `KinoPubMedia` sources (`PlayerInfo`), not a copy.

```sh
DEVICE=<udid> ./build.sh               # build, install, launch (DEVICE if several Apple TVs are booted)
./build.sh -autoplay 8739-e1           # open an episode row straight away
```

Needs Xcode-beta and `ffmpeg` (makes a 120 s clip). `CATALOG=` overrides the JSON path.
Groups: native player features · Apple TV app style · kino.pub style · ours today · metadata cases.
What was learned about the API lives in `docs/product/playback-info.md`, not here.
