/**
 * Our genre ids — the same table the app reads (`genres.json` in KinoPubMedia)
 * and the ingest writes documents with (`tools/metadata-ingest/genres.py`).
 * Only what this worker needs: TMDB's ids, which is what it gets from TMDB.
 */
import table from "../../../Packages/KinoPubMedia/Sources/KinoPubMedia/Resources/genres.json" with { type: "json" };

const byId = new Map(table.genres.map((row) => [row.id, row]));
const byTmdb = new Map();
for (const row of table.genres) {
  for (const id of row.tmdb || []) {
    if (!byTmdb.has(id)) byTmdb.set(id, []);
    byTmdb.get(id).push(row);
  }
}

const ours = (row) => ({
  id: row.id, domain: row.domain, name: { en: row.en, ru: row.ru }, group: row.group,
  mapped: true, source: "tmdb",
});

/** TMDB's `genres` → ours, in TMDB's order (its first is the primary genre). A
 *  folded TV pair (10759 Action & Adventure) is two of ours; an unknown id is
 *  kept under `tmdb:<id>`, unmapped, never dropped. */
export function tmdbGenres(genres) {
  const result = [];
  for (const genre of genres || []) {
    const pair = table.tmdb_pairs[String(genre.id)];
    const rows = pair ? pair.map((id) => byId.get(id)).filter(Boolean) : byTmdb.get(genre.id);
    const mapped = rows?.length
      ? rows.map(ours)
      : [{ id: `tmdb:${genre.id}`, domain: "video", name: { en: genre.name, ru: genre.name },
           group: null, mapped: false, source: "tmdb" }];
    for (const g of mapped) if (!result.some((r) => r.id === g.id)) result.push(g);
  }
  return result;
}
