#!/usr/bin/env python3
"""Closed-pool person-name probe (RapidFuzz + prefix + rough RU→LAT).

Mirrors the stage-1 scorer documented in the Project store
`docs/person-name-matching.md`. Alias dictionaries are intentionally out of scope.

  pip install rapidfuzz
  python3 tools/person-name-match-probe.py
"""

from __future__ import annotations

import re
import unicodedata

from rapidfuzz import fuzz

RU2LAT = str.maketrans({
    "а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "е": "e", "ё": "e", "ж": "z",
    "з": "z", "и": "i", "й": "i", "к": "k", "л": "l", "м": "m", "н": "n", "о": "o",
    "п": "p", "р": "r", "с": "s", "т": "t", "у": "u", "ф": "f", "х": "h", "ц": "t",
    "ч": "c", "ш": "s", "щ": "s", "ъ": "", "ы": "i", "ь": "", "э": "e", "ю": "u", "я": "a",
})

ACCEPT_SCORE = 72.0
ACCEPT_MARGIN = 8.0


def normalize(s: str) -> str:
    s = unicodedata.normalize("NFKD", s)
    s = "".join(c for c in s if not unicodedata.combining(c))
    s = s.lower().replace("ё", "е").strip()
    s = re.sub(r"[^\w\s\-]", " ", s, flags=re.UNICODE)
    return re.sub(r"[\s\-]+", " ", s).strip()


def to_latin(s: str) -> str:
    s = normalize(s)
    if re.search(r"[а-я]", s):
        s = s.translate(RU2LAT)
    return s


def tokens(s: str) -> list[str]:
    return [t for t in to_latin(s).split() if t]


def token_score(a: str, b: str) -> float:
    if a == b:
        return 100.0
    if a.startswith(b) or b.startswith(a):
        shorter, longer = (a, b) if len(a) <= len(b) else (b, a)
        if len(shorter) >= 2:
            return 85.0 + 15.0 * len(shorter) / len(longer)
    return float(fuzz.ratio(a, b))


def name_score(query: str, cand: str) -> float:
    qt, ct = tokens(query), tokens(cand)
    if not qt or not ct:
        return 0.0
    full = float(fuzz.token_set_ratio(to_latin(query), to_latin(cand)))
    sur = token_score(qt[-1], ct[-1])
    qg, cg = qt[:-1], ct[:-1]
    if not qg and not cg:
        given = 100.0
    elif not qg or not cg:
        given = 70.0
    else:
        used: set[int] = set()
        parts: list[float] = []
        for q in qg:
            best = (-1.0, None)
            for i, c in enumerate(cg):
                if i in used:
                    continue
                sc = token_score(q, c)
                if sc > best[0]:
                    best = (sc, i)
            if best[1] is not None:
                used.add(best[1])
                parts.append(best[0])
            else:
                parts.append(0.0)
        given = sum(parts) / len(parts)
    def grams(s: str, n: int = 2) -> set[str]:
        s = to_latin(s).replace(" ", "")
        return {s[i : i + n] for i in range(max(0, len(s) - n + 1))} or set()
    gq, gc = grams(query), grams(cand)
    jacc = 100.0 * len(gq & gc) / len(gq | gc) if gq and gc else 0.0
    return 0.35 * full + 0.35 * sur + 0.20 * given + 0.10 * jacc


def best(query: str, pool: list[str]) -> tuple[str, float, float]:
    ranked = sorted(((name_score(query, c), c) for c in pool), reverse=True)
    best_s, winner = ranked[0]
    second = ranked[1][0] if len(ranked) > 1 else 0.0
    return winner, best_s, second


POOL = [
    "Brad Pitt", "Edward Norton", "Helena Bonham Carter", "Meat Loaf", "Jared Leto",
    "Raymond Nicholson", "Michael C. Hall", "Michael K. Hall", "Owen Wilson", "Luke Wilson",
    "Lola Bond", "Gu Gyo-hwan", "Do Kyung-soo", "Lee Kwang-soo", "Zhang Ziyi",
    "Remi Bezançon", "Carrie-Anne Moss", "Mikey Madison", "Erica Alexander", "Tom Holland",
]
POOL_RU = [
    "Брэд Питт", "Эдвард Нортон", "Хелена Бонем Картер", "Мит Лоуф", "Джаред Лето",
    "Реймонд Николсон", "Майкл С. Холл", "Майкл К. Холл", "Оуэн Уилсон", "Люк Уилсон",
    "Лола Бонд", "Ку Гё-Хван", "До Кён Су", "Ли Кван Су", "Чжан Цзыи",
    "Реми Безансон", "Кэрри-Энн Мосс", "Майки Мэдисон", "Эрика Александер", "Том Холланд",
]

CASES = [
    ("Рей Николсон", POOL_RU, "Реймонд Николсон"),
    ("Ray Nicholson", POOL, "Raymond Nicholson"),
    ("Lola Bond", POOL_RU, "Лола Бонд"),
    ("Лола Бонд", POOL, "Lola Bond"),
    ("Ку ГёХван", POOL_RU, "Ку Гё-Хван"),
    ("Оуэн Уилсон", POOL, "Owen Wilson"),
    ("Майкл С. Холл", ["Майкл К. Холл", "Майкл С. Холл"], "Майкл С. Холл"),
    ("Уилсон", POOL_RU, None),
]


def main() -> None:
    print(f"{'query':<22} {'expected':<22} {'winner':<22} {'score':>6} {'2nd':>6} {'ok'}")
    print("-" * 90)
    for query, pool, expected in CASES:
        winner, best_s, second = best(query, pool)
        margin = best_s - second
        if expected is None:
            ok = "AMBIG" if margin < ACCEPT_MARGIN else "OK"
        elif best_s < ACCEPT_SCORE or margin < ACCEPT_MARGIN:
            ok = "REJECT" if winner == expected else "MISS"
        else:
            ok = "OK" if winner == expected else "MISS"
        print(f"{query:<22} {(expected or '(ambiguous)'):<22} {winner:<22} {best_s:6.1f} {second:6.1f} {ok}")


if __name__ == "__main__":
    main()
