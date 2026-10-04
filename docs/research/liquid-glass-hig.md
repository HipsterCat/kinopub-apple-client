# Liquid Glass and HIG

## How we do it now
All glass goes through `kinoGlass` / `kinoGlassGroup` (degrades under Reduce Transparency / Increase Contrast); `.glass` / `.glassProminent` hero CTAs; system `TabView` / `sidebarAdaptable`; Dynamic Type everywhere; no shadows on tvOS cards.

## What others do
| Repo | What | Link |
|---|---|---|
| Swiftfin | The most thorough glass adoption; a fallback for **unsupported Apple TVs**; contrast-aware glass labels; tvOS `sidebarAdaptable`; tab bar placement setting. | [#2147](https://github.com/jellyfin/Swiftfin/pull/2147), [#2224](https://github.com/jellyfin/Swiftfin/pull/2224), [#2303](https://github.com/jellyfin/Swiftfin/pull/2303), [#2107](https://github.com/jellyfin/Swiftfin/pull/2107), [#2256](https://github.com/jellyfin/Swiftfin/pull/2256) |
| Parallax | Hero band reworked to the iOS 26 design language (`backgroundExtensionEffect`, iOS). | [PR #35](https://github.com/eutialia/Parallax/pull/35) |
| Sodalite | Focus ring concentric with the artwork; one radius role for every artwork surface; a theme glass carries its own opaque base on tvOS. | [8319565](https://github.com/superuser404notfound/Sodalite/commit/8319565), [09d7d1f](https://github.com/superuser404notfound/Sodalite/commit/09d7d1f), [0ff86e5](https://github.com/superuser404notfound/Sodalite/commit/0ff86e5) |

## Proposal — S · P2
Check `kinoGlass` and the hero glass CTAs on Apple TV HD / 4K 1st gen (Swiftfin #2224 found glass misbehaving on unsupported hardware), and add an adapter if needed.
