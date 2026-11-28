/**
 * Pictures an admin uploads for a title nobody else has art for.
 *
 *   POST /admin/kinopub/{id}/upload?kind=logo|poster|cover|backdrop&lang=ru&width=&height=
 *        body: the image bytes (PNG, JPEG or WebP, at most MAX_UPLOAD_BYTES)
 *   GET  /img/upload/{sha256}.{png|jpg|webp}
 *
 * The bytes go to KV under `upload:{sha256}` (the DOCUMENTS namespace already bound,
 * so nothing new to set up; a value may be 25 MiB). The same file uploaded twice is
 * one entry. The URL never changes, so it is served immutable. The title's document
 * lists its uploads (`uploads[]`) so the picker can offer them again after another
 * pick replaced them.
 */

export const MAX_UPLOAD_BYTES = 20 * 1024 * 1024;
const UPLOAD_PATH = /^\/img\/upload\/([0-9a-f]{64})\.(png|jpg|webp)$/;
const TYPES = { png: "image/png", jpg: "image/jpeg", webp: "image/webp" };

export function isUploadURL(url) {
  try {
    return UPLOAD_PATH.test(new URL(url).pathname);
  } catch {
    return false;
  }
}

/** Stores the request body; returns `{ url, sha, type }` or `{ error, status }`. */
export async function storeUpload(request, env) {
  if (!env?.DOCUMENTS) return { error: "no KV", status: 500 };
  const declared = Number(request.headers.get("Content-Length") || 0);
  if (declared > MAX_UPLOAD_BYTES) return { error: "image is larger than 20 MB", status: 413 };
  const bytes = new Uint8Array(await request.arrayBuffer());
  if (!bytes.length) return { error: "empty body", status: 400 };
  if (bytes.length > MAX_UPLOAD_BYTES) return { error: "image is larger than 20 MB", status: 413 };
  const ext = sniff(bytes);
  if (!ext) return { error: "PNG, JPEG or WebP only", status: 415 };
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  const sha = [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
  const key = `upload:${sha}`;
  const existing = await env.DOCUMENTS.get(key, { type: "stream" }).catch(() => null);
  if (existing) await existing.cancel?.();
  else await env.DOCUMENTS.put(key, bytes, { metadata: { type: TYPES[ext] } });
  const origin = new URL(request.url).origin;
  return { url: `${origin}/img/upload/${sha}.${ext}`, sha, type: TYPES[ext] };
}

export async function serveUpload(request, env) {
  const match = new URL(request.url).pathname.match(UPLOAD_PATH);
  if (!match || !env?.DOCUMENTS) return new Response("not found", { status: 404 });
  const stored = await env.DOCUMENTS.getWithMetadata(`upload:${match[1]}`, { type: "arrayBuffer" });
  if (!stored?.value) return new Response("not found", { status: 404 });
  const headers = new Headers({
    "Content-Type": stored.metadata?.type || TYPES[match[2]],
    "Cache-Control": "public, max-age=31536000, immutable",
    "Access-Control-Allow-Origin": "*",
    "X-KinoPub-Image-Source": "upload",
  });
  return new Response(request.method === "HEAD" ? null : stored.value, { status: 200, headers });
}

function sniff(bytes) {
  const at = (i, ...values) => values.every((v, j) => bytes[i + j] === v);
  if (at(0, 0x89, 0x50, 0x4e, 0x47)) return "png";
  if (at(0, 0xff, 0xd8, 0xff)) return "jpg";
  if (at(0, 0x52, 0x49, 0x46, 0x46) && at(8, 0x57, 0x45, 0x42, 0x50)) return "webp";
  return null;
}
