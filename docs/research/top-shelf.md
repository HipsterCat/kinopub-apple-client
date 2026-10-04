# tvOS Top Shelf

## How we do it now
No Top Shelf target ([ROADMAP.md L377](https://github.com/HipsterCat/kinopub-apple-client/blob/b89d194c6a2f4f08fd2b34e52c75cbc18faf4a06/ROADMAP.md#L377)); CURRENT lists Top Shelf as non-MVP.

## What others do
| Repo | What | Link |
|---|---|---|
| Sodalite | **The app renders the cells and the extension only reads them** (App Group): no server re-encodes, no system-side fetches we can't see. | [34131a9](https://github.com/superuser404notfound/Sodalite/commit/34131a9f0e1f252325e71defff7c98ef3a77f2b8) |
| Sodalite | One download per picture, not per cell; resume bar burned into the cell; keeps the last good shelf on a failed fetch. | [70b5d10](https://github.com/superuser404notfound/Sodalite/commit/70b5d101f6fff1fcb687a72c8861323e72a9e237), [bd4dbef](https://github.com/superuser404notfound/Sodalite/commit/bd4dbef) |
| Rivulet | Backdrop + clear-logo compositor, composited on cache write; the extension renders the file. Full-bleed carousel from Continue Watching. | [292fef5](https://github.com/l984-451/Rivulet/commit/292fef59219f19513de7e12d62fab1f60a36787e), [da88dc1](https://github.com/l984-451/Rivulet/commit/da88dc111cf21344660bff317e0adf66823bd4bf), [e02b8e3](https://github.com/l984-451/Rivulet/commit/e02b8e3) |
| Plozz | Holds three; a card says where you got to and lands you there; identity scoped by account. | [e7fd7db](https://github.com/brandomoore/Plozz/commit/e7fd7db3), [a062b79](https://github.com/brandomoore/Plozz/commit/a062b794) |
| strimr | Top Shelf content provider. | [PR #91](https://github.com/wunax/strimr/pull/91) |

## Proposal — M · P2 (stage 5)
A Top Shelf extension with `TVTopShelfCarouselContent` from Continue Watching + Up Next. Images are pre-composited by the app (16:9 backdrop + title logo + progress bar) into the App Group when `ContentStore` refreshes. Deep links to the detail page or to play. Logos come from [title-logos.md](title-logos.md) A.
