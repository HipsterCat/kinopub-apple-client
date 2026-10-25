import assert from "node:assert/strict";
import { test } from "node:test";
import { handleAdmin } from "./admin.js";
import { handleImage } from "./title.js";

function memoryEnv(initial = {}) {
  const documents = { ...initial };
  return {
    ADMIN_TOKEN: "secret",
    documents,
    DOCUMENTS: {
      async get(key, opts) {
        const raw = documents[key];
        if (raw == null) return null;
        return opts?.type === "json" ? raw : JSON.stringify(raw);
      },
      async put(key, value) {
        documents[key] = JSON.parse(value);
      },
    },
  };
}

function admin(path, { token = "secret", body } = {}) {
  return new Request(`https://example.test${path}`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: body == null ? undefined : JSON.stringify(body),
  });
}

test("admin routes stay hidden without the token", async () => {
  const env = memoryEnv();
  env.ADMIN_TOKEN = "";
  const response = await handleAdmin(admin("/admin/kinopub/7/forget?kind=logo"), env);
  assert.equal(response.status, 404);
});

test("pick pins a logo and the image route serves that file", async () => {
  const env = memoryEnv({
    "title:kinopub:7": {
      pending: false,
      artwork: {
        logo: [{ source: "tmdb", url: "https://image.tmdb.org/t/p/original/old.png", lang: "ru", width: 100, height: 40 }],
      },
    },
  });
  const picked = await handleAdmin(admin("/admin/kinopub/7/pick", {
    body: { logo: "https://image.tmdb.org/t/p/original/chosen.png", logo_lang: "en" },
  }), env);
  assert.equal(picked.status, 200);
  const image = await handleImage(
    new Request("https://example.test/img/logo/by/kinopub/7"),
    env,
    { waitUntil() {} },
  );
  assert.equal(image.status, 302);
  assert.equal(image.headers.get("location"), "https://example.test/img/logo/by/kinopub/7/en/logo.png?v=1");
  assert.equal(image.headers.get("content-language"), "en");
});

test("forget clears the logo", async () => {
  const env = memoryEnv({
    "title:kinopub:7": {
      pending: false,
      artwork: { logo: [{ source: "tmdb", url: "https://image.tmdb.org/t/p/original/old.png", lang: "ru" }] },
    },
  });
  const response = await handleAdmin(admin("/admin/kinopub/7/forget?kind=logo"), env);
  assert.equal(response.status, 200);
  assert.equal(env.documents["title:kinopub:7"].artwork.logo.length, 0);
  assert.equal(env.documents["title:kinopub:7"].art_rev, 1);
});
