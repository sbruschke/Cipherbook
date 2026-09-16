#!/usr/bin/env python3
"""Build Keyboard/Resources/lexicon.dat, the keyboard's word list and next-word table.

Sources (fetched into scripts/lexicon-src/, not committed):
  * wordfreq (pip) — word frequencies, CC BY-SA 4.0. Clean, and it has contractions.
  * https://norvig.com/ngrams/count_1w.txt / count_2w.txt — Google Web Trillion Word
    Corpus counts. Only used for which word follows which; its unigrams are too noisy.

Output is little-endian and mapped straight into memory by `Lexicon.swift`:

    magic "CBLX", u32 version, u32 wordCount, u32 blobSize, u32 bigramCount
    u8  blob[blobSize]              words, UTF-8, sorted by byte order, zero-padded to 4
    u32 wordOffsets[wordCount + 1]  word i is blob[offsets[i] ..< offsets[i + 1]]
    f32 logFreq[wordCount]          natural log of the word's probability
    u32 bigramStart[wordCount + 2]  CSR rows; row wordCount is sentence start
    u32 bigramNext[bigramCount]     follower word ids, most likely first
    f32 bigramLogP[bigramCount]     ln P(follower | word)

Usage: pip install wordfreq && python3 scripts/build-lexicon.py
"""
from __future__ import annotations

import math
import re
import struct
import sys
import urllib.request
from collections import defaultdict
from pathlib import Path

from wordfreq import top_n_list, word_frequency

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "scripts" / "lexicon-src"
OUT = ROOT / "Keyboard" / "Resources" / "lexicon.dat"

VOCAB_SCAN = 60000        # how deep into wordfreq's ranking to look
FOLLOWERS_PER_WORD = 12   # next-word candidates kept per word
MIN_WORD_LEN_1 = {"a", "i"}
WORD_RE = re.compile(r"^[a-z]+(?:'[a-z]+)?$")

# Apostrophe-less spellings that are only ever a contraction typed lazily. Where the
# bare form is a real word too (cant, wont, well, were, hell, ill, its, lets, shell)
# it stays, and frequency decides between the two.
LAZY_CONTRACTIONS = {
    "dont": "don't", "im": "i'm", "ive": "i've", "youre": "you're", "didnt": "didn't",
    "doesnt": "doesn't", "isnt": "isn't", "thats": "that's", "theres": "there's",
    "theyre": "they're", "wasnt": "wasn't", "arent": "aren't", "couldnt": "couldn't",
    "wouldnt": "wouldn't", "shouldnt": "shouldn't", "hasnt": "hasn't", "havent": "haven't",
    "hadnt": "hadn't", "werent": "weren't", "whats": "what's", "youve": "you've",
    "youll": "you'll", "theyve": "they've", "theyll": "they'll", "weve": "we've",
    "wouldve": "would've", "couldve": "could've", "shouldve": "should've", "aint": "ain't",
    "heres": "here's", "whos": "who's", "hows": "how's", "wheres": "where's",
    "youd": "you'd", "theyd": "they'd", "itll": "it'll", "thatll": "that'll",
    "mustnt": "mustn't", "neednt": "needn't",
}
# Tokens the bigram corpus splits or spells without the apostrophe.
BIGRAM_ALIASES = {**LAZY_CONTRACTIONS, "cant": "can't", "wont": "won't"}


def fetch(name: str) -> Path:
    path = SRC / name
    if not path.exists():
        SRC.mkdir(parents=True, exist_ok=True)
        urllib.request.urlretrieve(f"https://norvig.com/ngrams/{name}", path)
    return path


def build_vocab() -> dict[str, float]:
    vocab: dict[str, float] = {}
    for word in top_n_list("en", VOCAB_SCAN, wordlist="best"):
        word = word.replace("’", "'")
        if not WORD_RE.match(word) or word in LAZY_CONTRACTIONS:
            continue
        if len(word) == 1 and word not in MIN_WORD_LEN_1:
            continue
        freq = word_frequency(word, "en", wordlist="best")
        if freq > 0:
            vocab[word] = math.log(freq)
    return vocab


def build_bigrams(vocab: dict[str, float]) -> dict[str, list[tuple[str, float]]]:
    unigram: dict[str, int] = {}
    for line in fetch("count_1w.txt").read_text().splitlines():
        word, count = line.split("\t")
        unigram[word] = int(count)

    def canon(token: str) -> str | None:
        if token == "<S>":
            return token
        token = BIGRAM_ALIASES.get(token, token)
        return token if token in vocab else None

    rows: dict[str, dict[str, int]] = defaultdict(lambda: defaultdict(int))
    firsts: dict[str, int] = defaultdict(int)
    for line in fetch("count_2w.txt").read_text().splitlines():
        pair, count = line.split("\t")
        first, _, second = pair.partition(" ")
        a, b = canon(first.lower()) if first != "<S>" else "<S>", canon(second.lower())
        if a is None or b is None or b == "<S>":
            continue
        rows[a][b] += int(count)
        firsts[a] += int(count)

    table = {}
    for a, followers in rows.items():
        # Prefer the corpus unigram count as the denominator; the bigram file is a
        # truncated sample, so summing it would overstate every conditional.
        raw = first_token_count(a, unigram)
        denom = max(raw, firsts[a])
        ranked = sorted(followers.items(), key=lambda kv: kv[1], reverse=True)[:FOLLOWERS_PER_WORD]
        table[a] = [(b, math.log(c / denom)) for b, c in ranked]
    return table


def first_token_count(word: str, unigram: dict[str, int]) -> int:
    if word == "<S>":
        return 0
    bare = word.replace("'", "")
    return unigram.get(word, 0) or unigram.get(bare, 0)


def write(vocab: dict[str, float], bigrams: dict[str, list[tuple[str, float]]]) -> None:
    words = sorted(vocab, key=lambda w: w.encode())
    ids = {w: i for i, w in enumerate(words)}
    blob, offsets = bytearray(), [0]
    for w in words:
        blob += w.encode()
        offsets.append(len(blob))
    # Pad so every array after the blob starts on a 4-byte boundary.
    blob += b"\0" * (-len(blob) % 4)

    starts, nexts, logps = [0], [], []
    for row in words + ["<S>"]:
        for b, lp in bigrams.get(row, []):
            nexts.append(ids[b])
            logps.append(lp)
        starts.append(len(nexts))

    n = len(words)
    out = bytearray(b"CBLX")
    out += struct.pack("<4I", 1, n, len(blob), len(nexts))
    out += blob
    out += struct.pack(f"<{n + 1}I", *offsets)
    out += struct.pack(f"<{n}f", *(vocab[w] for w in words))
    out += struct.pack(f"<{n + 2}I", *starts)
    out += struct.pack(f"<{len(nexts)}I", *nexts)
    out += struct.pack(f"<{len(logps)}f", *logps)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_bytes(out)
    print(f"{OUT.relative_to(ROOT)}: {n} words, {len(nexts)} bigrams, "
          f"{len(out) / 1024:.0f} KiB", file=sys.stderr)


if __name__ == "__main__":
    v = build_vocab()
    write(v, build_bigrams(v))
