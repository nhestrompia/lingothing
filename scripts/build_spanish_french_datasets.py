#!/usr/bin/env python3
"""
Build Spanish and French datasets compatible with NotchGreek Phrase schema.

This script:
1) Snapshots source files from validated URLs into a local cache directory.
2) Records source metadata (URL, license, checksum, fetch date).
3) Generates:
   - pronunciation-items-es.json
   - pronunciation-items-fr.json
   - phrases-es.json
   - phrases-fr.json
4) Enforces category quotas based on current Greek resource files.
"""

from __future__ import annotations

import argparse
import bz2
import hashlib
import json
import re
import sqlite3
import unicodedata
import urllib.request
from collections import Counter, OrderedDict, defaultdict
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable


ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / "NotchGreek" / "Resources"

GREEK_PRONUN = RESOURCES / "pronunciation-items.json"
GREEK_PHRASES = RESOURCES / "phrases.json"

OUT_PRONUN_ES = RESOURCES / "pronunciation-items-es.json"
OUT_PRONUN_FR = RESOURCES / "pronunciation-items-fr.json"
OUT_PHRASES_ES = RESOURCES / "phrases-es.json"
OUT_PHRASES_FR = RESOURCES / "phrases-fr.json"
OUT_METADATA = RESOURCES / "language-dataset-sources.json"


SOURCE_SPECS = OrderedDict(
    {
        "frequency_es": {
            "url": "https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018/es/es_50k.txt",
            "filename": "es_50k.txt",
            "license": "FrequencyWords content: CC-BY-SA-4.0 (repository README)",
        },
        "frequency_fr": {
            "url": "https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018/fr/fr_50k.txt",
            "filename": "fr_50k.txt",
            "license": "FrequencyWords content: CC-BY-SA-4.0 (repository README)",
        },
        "frequency_readme": {
            "url": "https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/README.md",
            "filename": "frequencywords_README.md",
            "license": "FrequencyWords repository README",
        },
        "wikdict_es_en": {
            "url": "https://download.wikdict.com/dictionaries/sqlite/2_2025-11/es-en.sqlite3",
            "filename": "es-en.sqlite3",
            "license": "WikDict/Wiktionary data: CC BY-SA 3.0",
        },
        "wikdict_fr_en": {
            "url": "https://download.wikdict.com/dictionaries/sqlite/2_2025-11/fr-en.sqlite3",
            "filename": "fr-en.sqlite3",
            "license": "WikDict/Wiktionary data: CC BY-SA 3.0",
        },
        "tatoeba_spa_sentences": {
            "url": "https://downloads.tatoeba.org/exports/per_language/spa/spa_sentences.tsv.bz2",
            "filename": "spa_sentences.tsv.bz2",
            "license": "Tatoeba sentences: CC-BY 2.0 FR by default; per-sentence licensing applies",
        },
        "tatoeba_spa_eng_links": {
            "url": "https://downloads.tatoeba.org/exports/per_language/spa/spa-eng_links.tsv.bz2",
            "filename": "spa-eng_links.tsv.bz2",
            "license": "Tatoeba link metadata",
        },
        "tatoeba_fra_sentences": {
            "url": "https://downloads.tatoeba.org/exports/per_language/fra/fra_sentences.tsv.bz2",
            "filename": "fra_sentences.tsv.bz2",
            "license": "Tatoeba sentences: CC-BY 2.0 FR by default; per-sentence licensing applies",
        },
        "tatoeba_fra_eng_links": {
            "url": "https://downloads.tatoeba.org/exports/per_language/fra/fra-eng_links.tsv.bz2",
            "filename": "fra-eng_links.tsv.bz2",
            "license": "Tatoeba link metadata",
        },
        "tatoeba_eng_sentences": {
            "url": "https://downloads.tatoeba.org/exports/per_language/eng/eng_sentences.tsv.bz2",
            "filename": "eng_sentences.tsv.bz2",
            "license": "Tatoeba sentences: mixed per-sentence licensing, CC-BY 2.0 FR default",
        },
        "wikivoyage_spanish_phrasebook": {
            "url": "https://en.wikivoyage.org/w/index.php?title=Spanish_phrasebook&action=raw",
            "filename": "Spanish_phrasebook.raw.txt",
            "license": "Wikivoyage text: CC BY-SA 4.0",
        },
        "wikivoyage_french_phrasebook": {
            "url": "https://en.wikivoyage.org/w/index.php?title=French_phrasebook&action=raw",
            "filename": "French_phrasebook.raw.txt",
            "license": "Wikivoyage text: CC BY-SA 4.0",
        },
    }
)


CATEGORY_PREFIX = {
    "adjectives": "adj",
    "airport": "air",
    "animals": "anim",
    "cafe": "cafe",
    "clothes": "cloth",
    "colors": "color",
    "common-phrases": "common",
    "countries": "country",
    "daily-sentences": "sent",
    "days-months": "day",
    "directions": "dir",
    "emergency": "emerg",
    "family": "fam",
    "food-drink": "food",
    "furniture": "furn",
    "greetings": "greet",
    "groceries": "groc",
    "gym": "gym",
    "health": "health",
    "hospital": "hosp",
    "instruments": "inst",
    "introduction": "intro",
    "kitchenware": "kit",
    "market": "market",
    "numbers": "num",
    "occupations": "occ",
    "problems": "prob",
    "questions": "quest",
    "restaurant": "rest",
    "shopping": "shop",
    "social": "social",
    "time": "time",
    "transport": "trans",
    "verbs": "verb",
    "weather": "wth",
}


WORD_FOCUSED_CATEGORIES = {
    "adjectives",
    "animals",
    "clothes",
    "colors",
    "countries",
    "days-months",
    "family",
    "food-drink",
    "furniture",
    "instruments",
    "kitchenware",
    "numbers",
    "occupations",
    "questions",
    "time",
    "verbs",
}


PRONUN_DEFAULT_ORDER = [
    "greetings",
    "common-phrases",
    "introduction",
    "questions",
    "daily-sentences",
    "numbers",
    "days-months",
    "time",
    "countries",
    "directions",
    "transport",
    "airport",
    "restaurant",
    "cafe",
    "shopping",
    "market",
    "groceries",
    "food-drink",
    "health",
    "hospital",
    "emergency",
    "problems",
    "weather",
    "family",
    "occupations",
    "animals",
    "clothes",
    "furniture",
    "kitchenware",
    "instruments",
    "adjectives",
    "verbs",
    "gym",
]


PHRASE_DEFAULT_ORDER = [
    "greetings",
    "directions",
    "restaurant",
    "shopping",
    "time",
    "numbers",
    "social",
    "emergency",
]


ADJECTIVE_HINTS = {
    "good",
    "bad",
    "new",
    "old",
    "big",
    "small",
    "high",
    "low",
    "young",
    "beautiful",
    "ugly",
    "easy",
    "hard",
    "important",
    "different",
    "same",
    "possible",
    "early",
    "late",
    "free",
    "busy",
    "open",
    "closed",
    "hot",
    "cold",
    "happy",
    "sad",
    "strong",
    "weak",
    "fast",
    "slow",
    "clean",
    "dirty",
    "true",
    "false",
    "safe",
    "dangerous",
    "ready",
}


NUMBER_HINTS = {
    "zero",
    "one",
    "two",
    "three",
    "four",
    "five",
    "six",
    "seven",
    "eight",
    "nine",
    "ten",
    "eleven",
    "twelve",
    "thirteen",
    "fourteen",
    "fifteen",
    "sixteen",
    "seventeen",
    "eighteen",
    "nineteen",
    "twenty",
    "thirty",
    "forty",
    "fifty",
    "sixty",
    "seventy",
    "eighty",
    "ninety",
    "hundred",
    "thousand",
    "first",
    "second",
    "third",
}


COUNTRY_HINTS = {
    "spain",
    "france",
    "germany",
    "italy",
    "portugal",
    "greece",
    "turkey",
    "england",
    "ireland",
    "scotland",
    "wales",
    "britain",
    "uk",
    "united kingdom",
    "united states",
    "america",
    "canada",
    "mexico",
    "argentina",
    "brazil",
    "chile",
    "peru",
    "colombia",
    "venezuela",
    "ecuador",
    "bolivia",
    "paraguay",
    "uruguay",
    "cuba",
    "dominican republic",
    "china",
    "japan",
    "korea",
    "india",
    "russia",
    "ukraine",
    "poland",
    "sweden",
    "norway",
    "denmark",
    "finland",
    "switzerland",
    "austria",
    "netherlands",
    "belgium",
    "romania",
    "bulgaria",
    "serbia",
    "croatia",
    "albania",
    "egypt",
    "morocco",
    "algeria",
    "tunisia",
    "nigeria",
    "south africa",
    "australia",
    "new zealand",
}


DAYS_MONTHS_HINTS = {
    "monday",
    "tuesday",
    "wednesday",
    "thursday",
    "friday",
    "saturday",
    "sunday",
    "january",
    "february",
    "march",
    "april",
    "may",
    "june",
    "july",
    "august",
    "september",
    "october",
    "november",
    "december",
    "week",
    "month",
    "year",
    "today",
    "tomorrow",
    "yesterday",
}


CATEGORY_HINTS = {
    "airport": {"airport", "flight", "plane", "boarding", "passport", "baggage", "luggage", "terminal", "gate", "customs", "check-in", "security"},
    "animals": {"animal", "dog", "cat", "horse", "bird", "fish", "cow", "pig", "sheep", "lion", "tiger", "wolf", "rabbit", "duck", "goat"},
    "cafe": {"coffee", "espresso", "cappuccino", "latte", "tea", "cafe", "barista"},
    "clothes": {"shirt", "t-shirt", "pants", "trousers", "dress", "skirt", "jacket", "coat", "shoe", "hat", "jeans", "sweater", "clothes"},
    "colors": {"color", "colour", "red", "blue", "green", "yellow", "black", "white", "orange", "purple", "pink", "gray", "grey", "brown"},
    "common-phrases": {"yes", "no", "please", "thanks", "thank you", "sorry", "excuse me", "of course", "maybe"},
    "countries": COUNTRY_HINTS,
    "days-months": DAYS_MONTHS_HINTS,
    "directions": {"direction", "left", "right", "straight", "turn", "map", "street", "road", "corner", "near", "far"},
    "family": {"family", "mother", "father", "mom", "dad", "brother", "sister", "son", "daughter", "wife", "husband", "parents", "child"},
    "food-drink": {"food", "water", "wine", "beer", "bread", "rice", "meat", "fish", "milk", "cheese", "fruit", "vegetable", "breakfast", "lunch", "dinner"},
    "furniture": {"furniture", "table", "chair", "bed", "sofa", "couch", "desk", "wardrobe", "lamp", "shelf"},
    "groceries": {"grocery", "supermarket", "fresh", "kilo", "tomato", "potato", "onion", "lettuce", "banana", "apple", "market"},
    "gym": {"gym", "exercise", "workout", "fitness", "train", "training", "muscle", "weights", "stretch", "cardio"},
    "health": {"health", "doctor", "medicine", "pain", "fever", "headache", "sick", "pharmacy", "dentist"},
    "hospital": {"hospital", "nurse", "clinic", "emergency room", "x-ray", "allergy", "symptom", "ambulance"},
    "instruments": {"guitar", "piano", "violin", "drum", "flute", "trumpet", "saxophone", "instrument"},
    "introduction": {"my name", "i am", "i'm", "nice to meet", "from", "years old", "married", "single"},
    "kitchenware": {"plate", "glass", "cup", "fork", "knife", "spoon", "pan", "pot", "bowl", "kitchen"},
    "market": {"market", "buy", "sell", "price", "cost", "receipt", "cash", "change"},
    "numbers": NUMBER_HINTS,
    "occupations": {"teacher", "doctor", "engineer", "lawyer", "student", "driver", "chef", "accountant", "manager", "nurse", "worker", "job"},
    "problems": {"help", "problem", "lost", "stolen", "broken", "wrong", "can't", "cannot", "issue", "trouble", "missing"},
    "questions": {"what", "who", "when", "where", "why", "how", "which", "whose"},
    "restaurant": {"restaurant", "menu", "bill", "check", "table", "order", "meal", "dish", "reservation", "waiter"},
    "shopping": {"shop", "shopping", "store", "size", "try on", "expensive", "cheap", "discount", "card", "cash"},
    "social": {"friend", "party", "music", "dance", "conversation", "talk", "speak", "call", "meet"},
    "time": {"time", "hour", "minute", "second", "morning", "afternoon", "evening", "night", "late", "early", "clock"},
    "transport": {"bus", "train", "metro", "subway", "station", "platform", "taxi", "car", "tram", "ticket", "transport"},
    "verbs": {"be", "have", "do", "go", "come", "make", "take", "see", "know", "want", "can", "must", "say", "get"},
    "weather": {"weather", "rain", "sun", "cloud", "wind", "cold", "hot", "snow", "storm", "temperature"},
}


BLOCKLIST = {
    "fuck",
    "fucking",
    "shit",
    "bitch",
    "bastard",
    "asshole",
    "sex",
    "sexual",
    "porn",
    "rape",
    "murder",
    "kill yourself",
    "suicide",
    "nazi",
}


SECTION_HINTS = {
    "basic": ["common-phrases", "greetings", "introduction", "questions"],
    "conversation": ["social", "common-phrases"],
    "numbers": ["numbers"],
    "time": ["time", "days-months"],
    "directions": ["directions", "transport"],
    "transportation": ["transport", "airport", "directions"],
    "flying": ["airport", "transport"],
    "train": ["transport"],
    "bus": ["transport"],
    "taxi": ["transport"],
    "driving": ["transport"],
    "accommodation": ["furniture", "shopping"],
    "eating": ["restaurant", "cafe", "food-drink"],
    "drinking": ["cafe", "restaurant"],
    "shopping": ["shopping", "market", "groceries", "clothes"],
    "health": ["health", "hospital"],
    "emergency": ["emergency", "problems", "health"],
    "weather": ["weather"],
}


LANG_QUESTION_WORDS = {
    "es": {"qué", "quien", "quién", "cuándo", "dónde", "donde", "por qué", "cómo", "como", "cuál", "cual"},
    "fr": {"quoi", "qui", "quand", "où", "ou", "pourquoi", "comment", "quel", "quelle", "quels", "quelles"},
}


LANG_VERB_ENDINGS = {
    "es": ("ar", "er", "ir"),
    "fr": ("er", "ir", "re", "oir"),
}


@dataclass(frozen=True)
class Candidate:
    text: str
    english: str
    source: str
    kind: str  # "word" | "sentence"
    language: str  # "es" | "fr"
    rank: int
    section_hint: str | None = None


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as f:
        while True:
            chunk = f.read(1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def download_sources(cache_dir: Path, refresh: bool) -> dict[str, Path]:
    cache_dir.mkdir(parents=True, exist_ok=True)
    source_paths: dict[str, Path] = {}
    source_meta: list[dict[str, object]] = []

    for source_id, spec in SOURCE_SPECS.items():
        path = cache_dir / spec["filename"]
        if refresh or not path.exists():
            request = urllib.request.Request(
                spec["url"],
                headers={
                    "User-Agent": "Mozilla/5.0 (compatible; NotchGreekDatasetBuilder/1.0)",
                    "Accept": "*/*",
                },
            )
            with urllib.request.urlopen(request) as response:
                data = response.read()
            path.write_bytes(data)

        source_paths[source_id] = path
        stat = path.stat()
        source_meta.append(
            {
                "id": source_id,
                "url": spec["url"],
                "license": spec["license"],
                "snapshotPath": str(path),
                "sizeBytes": stat.st_size,
                "sha256": sha256_file(path),
                "fetchedAt": datetime.fromtimestamp(stat.st_mtime, tz=timezone.utc).replace(microsecond=0).isoformat(),
            }
        )

    OUT_METADATA.write_text(
        json.dumps(
            {
                "generatedAt": now_iso(),
                "generator": str(Path(__file__).resolve()),
                "sources": source_meta,
            },
            ensure_ascii=False,
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    return source_paths


def load_quota(path: Path, fallback_order: list[str]) -> OrderedDict[str, int]:
    data = json.loads(path.read_text(encoding="utf-8"))
    counts = Counter(item["category"] for item in data)
    ordered = OrderedDict()
    for category in fallback_order:
        if category in counts:
            ordered[category] = counts[category]
    for category in sorted(counts):
        if category not in ordered:
            ordered[category] = counts[category]
    return ordered


def strip_accents(text: str) -> str:
    normalized = unicodedata.normalize("NFD", text)
    return "".join(ch for ch in normalized if unicodedata.category(ch) != "Mn")


def normalize_spaces(text: str) -> str:
    return re.sub(r"\s+", " ", text).strip()


def clean_target_text(text: str) -> str:
    text = text.replace("\u00a0", " ")
    text = re.sub(r"\s+", " ", text)
    text = text.strip()
    text = text.strip("“”\"")
    return text


def transliteration_for_latin(text: str) -> str:
    lowered = text.lower()
    lowered = re.sub(r"[^\w\s'\-áéíóúüñàâæçéèêëîïôœùûüÿ]", " ", lowered, flags=re.UNICODE)
    lowered = lowered.replace("_", " ")
    return normalize_spaces(lowered)


def canonical_text(text: str) -> str:
    lowered = strip_accents(text.lower())
    lowered = re.sub(r"[^\w\s]", "", lowered, flags=re.UNICODE)
    lowered = lowered.replace("_", " ")
    return normalize_spaces(lowered)


def accepted_pronunciations(text: str) -> list[str]:
    variants: list[str] = []
    base = normalize_spaces(text.lower())
    stripped = re.sub(r"[^\w\s'\-áéíóúüñàâæçéèêëîïôœùûüÿ]", " ", base, flags=re.UNICODE)
    stripped = normalize_spaces(stripped.replace("_", " "))
    if stripped:
        variants.append(stripped)

    accentless = normalize_spaces(strip_accents(stripped))
    if accentless and accentless not in variants:
        variants.append(accentless)

    no_apostrophe = normalize_spaces(accentless.replace("'", " "))
    if no_apostrophe and no_apostrophe not in variants:
        variants.append(no_apostrophe)

    return variants[:4]


def is_learner_safe(text: str, english: str) -> bool:
    text_n = canonical_text(text)
    eng_n = canonical_text(english)
    joined = f"{text_n} {eng_n}"
    if any(term in joined for term in BLOCKLIST):
        return False
    if "http" in joined or "www" in joined or "@" in joined:
        return False
    if len(text_n) < 2 or len(eng_n) < 2:
        return False
    return True


def clean_wiki_markup(text: str) -> str:
    text = re.sub(r"\{\{[^{}]*\}\}", " ", text)
    text = re.sub(r"\[\[(?:[^|\]]+\|)?([^\]]+)\]\]", r"\1", text)
    text = re.sub(r"''+", "", text)
    text = re.sub(r"\([^)]*\)", " ", text)
    text = re.sub(r"[{}]+", " ", text)
    text = text.replace("&nbsp;", " ")
    text = text.replace("  ", " ")
    text = re.sub(r"<[^>]+>", " ", text)
    text = normalize_spaces(text)
    return text


def parse_wikivoyage_phrases(path: Path, language: str) -> list[Candidate]:
    candidates: list[Candidate] = []
    section = ""
    in_phrase_list = False
    with path.open("r", encoding="utf-8", errors="ignore") as f:
        for raw_line in f:
            line = raw_line.strip()
            if re.match(r"^==\s*phrase list\s*==$", line, flags=re.IGNORECASE):
                in_phrase_list = True
                section = "phrase list"
                continue
            if line.startswith("=="):
                section = clean_wiki_markup(line.strip("= ")).lower()
                # Ignore all top-level sections before phrase list.
                if not in_phrase_list:
                    continue
                continue
            if not in_phrase_list:
                continue
            if not line.startswith(";"):
                continue
            line = line[1:].strip()
            if ":" not in line:
                continue
            english_raw, target_raw = line.split(":", 1)
            target_raw = re.sub(r"\(''.*?''\)", " ", target_raw)
            target_raw = re.sub(r"\{\{IPA[^}]*\}\}", " ", target_raw, flags=re.IGNORECASE)
            target_raw = re.sub(r"\(\s*''.*$", " ", target_raw)
            english = clean_wiki_markup(english_raw)
            target = clean_wiki_markup(target_raw)
            if not english or not target:
                continue
            if "_" in english or "_" in target:
                continue

            # Prefer first alternative before slash for consistency.
            if "/" in target:
                target = target.split("/", 1)[0].strip()
            if ";" in target:
                target = target.split(";", 1)[0].strip()

            english = re.sub(r"^\s*(latin america|spain|france|canada)\s*:\s*", "", english, flags=re.I)
            target = re.sub(r"^\s*(latin america|spain|france|canada)\s*:\s*", "", target, flags=re.I)
            english = re.sub(r"\[([^\]]+)\]", r"\1", english)
            target = re.sub(r"\[([^\]]+)\]", r"\1", target)
            english = re.sub(r"^\.\.\.\s*", "", english)
            target = re.sub(r"^\.\.\.\s*", "", target)
            target = clean_target_text(target)
            english = clean_target_text(english)
            if not target or not english:
                continue

            if english.isupper():
                continue
            if "..." in target or "..." in english:
                continue
            if re.search(r"\b(literally|pronounce|pronounced|vowel|consonant|grammar|formal speech)\b", english, flags=re.I):
                continue
            if english in {"a", "e", "i", "o", "u", "y"}:
                continue
            if target.endswith("}}") or "{{" in target:
                continue

            if not is_learner_safe(target, english):
                continue

            candidates.append(
                Candidate(
                    text=target,
                    english=english,
                    source="wikivoyage",
                    kind="sentence",
                    language=language,
                    rank=len(candidates) + 1,
                    section_hint=section,
                )
            )
    return candidates


def parse_trans_list(raw: str | None) -> list[str]:
    if not raw:
        return []
    value = raw.strip().strip('"')
    parts = [p.strip(" '\"") for p in value.split("|")]
    cleaned: list[str] = []
    for part in parts:
        part = re.sub(r"\[\[(?:[^|\]]+\|)?([^\]]+)\]\]", r"\1", part)
        part = normalize_spaces(part)
        if part and not part.startswith("$"):
            cleaned.append(part)
    return cleaned


def best_gloss(raw: str | None) -> str | None:
    for gloss in parse_trans_list(raw):
        cleaned = re.sub(r"[;,:]+$", "", gloss)
        if re.search(r"[a-zA-Z]", cleaned):
            return cleaned
    return None


def lookup_gloss(conn: sqlite3.Connection, word: str) -> str | None:
    query = "SELECT trans_list FROM simple_translation WHERE written_rep = ? LIMIT 1"
    row = conn.execute(query, (word,)).fetchone()
    if row:
        gloss = best_gloss(row[0])
        if gloss:
            return gloss

    lower = word.lower()
    if lower != word:
        row = conn.execute(query, (lower,)).fetchone()
        if row:
            gloss = best_gloss(row[0])
            if gloss:
                return gloss

    accentless = strip_accents(lower)
    if accentless != lower:
        row = conn.execute(query, (accentless,)).fetchone()
        if row:
            gloss = best_gloss(row[0])
            if gloss:
                return gloss
    return None


def clean_frequency_word(word: str, language: str) -> str | None:
    word = word.strip().lower()
    word = word.strip(".,;:!?¡¿\"“”()[]{}")
    if not word:
        return None
    if any(ch.isdigit() for ch in word):
        return None
    # Drop detached clitics such as c', d' etc.
    if word.endswith("'") and len(word) <= 3:
        return None
    if re.search(r"[^a-zàâæçéèêëîïôœùûüÿáéíóúüñ'-]", word):
        return None
    if language == "fr" and word in {"c'", "d'", "j'", "l'", "m'", "n'", "s'", "t'", "qu'"}:
        return None
    return word


def parse_frequency_words(freq_path: Path, sqlite_path: Path, language: str, limit: int = 50000) -> list[Candidate]:
    candidates: list[Candidate] = []
    conn = sqlite3.connect(str(sqlite_path))
    conn.row_factory = sqlite3.Row
    try:
        with freq_path.open("r", encoding="utf-8", errors="ignore") as f:
            for rank, line in enumerate(f, start=1):
                if rank > limit:
                    break
                parts = line.strip().split()
                if not parts:
                    continue
                word = clean_frequency_word(parts[0], language)
                if not word:
                    continue
                english = lookup_gloss(conn, word)
                if not english:
                    continue
                if not is_learner_safe(word, english):
                    continue
                candidates.append(
                    Candidate(
                        text=word,
                        english=english,
                        source="frequency+wikdict",
                        kind="word",
                        language=language,
                        rank=rank,
                    )
                )
    finally:
        conn.close()
    return candidates


def parse_links(path: Path) -> dict[str, str]:
    mapping: dict[str, str] = {}
    with bz2.open(path, "rt", encoding="utf-8", errors="ignore") as f:
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if len(parts) < 2:
                continue
            local_id, eng_id = parts[0], parts[1]
            if local_id not in mapping:
                mapping[local_id] = eng_id
    return mapping


def load_selected_sentences(path: Path, wanted_ids: set[str]) -> dict[str, str]:
    out: dict[str, str] = {}
    with bz2.open(path, "rt", encoding="utf-8", errors="ignore") as f:
        for line in f:
            parts = line.rstrip("\n").split("\t", 2)
            if len(parts) < 3:
                continue
            sid = parts[0]
            if sid in wanted_ids:
                out[sid] = parts[2]
    return out


def parse_tatoeba_pairs(local_sentences_path: Path, local_links_path: Path, eng_sentences_path: Path, language: str) -> list[Candidate]:
    local_to_eng = parse_links(local_links_path)
    eng_ids = set(local_to_eng.values())
    eng_map = load_selected_sentences(eng_sentences_path, eng_ids)
    candidates: list[Candidate] = []
    with bz2.open(local_sentences_path, "rt", encoding="utf-8", errors="ignore") as f:
        for line in f:
            parts = line.rstrip("\n").split("\t", 2)
            if len(parts) < 3:
                continue
            local_id, text = parts[0], parts[2]
            eng_id = local_to_eng.get(local_id)
            if not eng_id:
                continue
            english = eng_map.get(eng_id)
            if not english:
                continue
            text = clean_target_text(text)
            english = clean_target_text(english)
            if not text or not english:
                continue
            if not is_learner_safe(text, english):
                continue
            # Moderate learner-safe length constraints.
            token_count = len(text.split())
            if token_count < 2 or token_count > 16:
                continue
            if len(text) > 110 or len(english) > 130:
                continue
            candidates.append(
                Candidate(
                    text=text,
                    english=english,
                    source="tatoeba",
                    kind="sentence",
                    language=language,
                    rank=len(candidates) + 1,
                )
            )
            if len(candidates) >= 120000:
                break
    return candidates


def text_for_matching(candidate: Candidate) -> tuple[str, str]:
    text = canonical_text(candidate.text)
    english = canonical_text(candidate.english)
    return text, english


def match_keywords(text: str, english: str, words: set[str]) -> bool:
    blob = f"{text} {english}"
    tokens = set(re.findall(r"[a-zàâæçéèêëîïôœùûüÿáéíóúüñ0-9']+", blob))
    for keyword in words:
        kw = keyword.lower().strip()
        if not kw:
            continue
        if " " in kw:
            if kw in blob:
                return True
        elif kw in tokens:
            return True
    return False


def classify_candidate(candidate: Candidate) -> list[str]:
    text, english = text_for_matching(candidate)
    categories: set[str] = set()

    if candidate.section_hint:
        section = candidate.section_hint
        for key, hinted_categories in SECTION_HINTS.items():
            if key in section:
                categories.update(hinted_categories)

    for category, keywords in CATEGORY_HINTS.items():
        if category == "numbers":
            continue
        if match_keywords(text, english, keywords):
            categories.add(category)

    if candidate.kind == "word":
        lang = candidate.language
        if text in LANG_QUESTION_WORDS[lang]:
            categories.add("questions")
        if any(english == word or english.startswith(f"{word} ") for word in ADJECTIVE_HINTS):
            categories.add("adjectives")
        english_tokens = english.split()
        if english_tokens:
            first = english_tokens[0]
            if first in NUMBER_HINTS and len(english_tokens) <= 3:
                categories.add("numbers")
        if any(english.startswith(f"{word} ") or english == word for word in DAYS_MONTHS_HINTS):
            categories.add("days-months")
        if english.startswith("to "):
            categories.add("verbs")
        if any(text.endswith(suffix) for suffix in LANG_VERB_ENDINGS[lang]) and len(text) > 3:
            categories.add("verbs")
        if not categories:
            categories.add("daily-sentences")
    else:
        token_count = len(candidate.text.split())
        if candidate.text.endswith("?"):
            categories.add("questions")
        if re.search(r"\b\d+\b", candidate.text) or re.search(r"\b\d+\b", candidate.english):
            categories.add("numbers")
        if token_count <= 5:
            categories.add("common-phrases")
        if token_count >= 4:
            categories.add("daily-sentences")
        if any(greet in english for greet in {"hello", "hi", "good morning", "good evening", "good night", "goodbye"}):
            categories.add("greetings")
        if any(intro in english for intro in {"my name", "i am", "i'm", "nice to meet"}):
            categories.add("introduction")

    if "daily-sentences" not in categories and candidate.kind == "sentence":
        categories.add("daily-sentences")

    return sorted(categories)


def difficulty_for_candidate(candidate: Candidate) -> int:
    if candidate.kind == "word":
        if candidate.rank <= 1000:
            return 1
        if candidate.rank <= 5000:
            return 2
        return 3
    token_count = len(candidate.text.split())
    if token_count <= 4:
        return 1
    if token_count <= 8:
        return 2
    return 3


def to_item(candidate: Candidate, category: str, idx: int, phrase_style: bool = False) -> dict[str, object]:
    prefix = CATEGORY_PREFIX.get(category, category.replace("-", ""))
    width = 3 if phrase_style else 4
    text = clean_target_text(candidate.text)
    translit = transliteration_for_latin(text)
    if not translit:
        translit = text.lower()

    return {
        "id": f"{prefix}_{idx:0{width}d}",
        "greek": text,
        "transliteration": translit,
        "english": clean_target_text(candidate.english),
        "category": category,
        "difficulty": difficulty_for_candidate(candidate),
        "acceptedPronunciations": accepted_pronunciations(text),
        "contextNote": None,
    }


def build_pools(candidates: Iterable[Candidate]) -> dict[str, list[Candidate]]:
    pools: dict[str, list[Candidate]] = defaultdict(list)
    for candidate in candidates:
        for category in classify_candidate(candidate):
            pools[category].append(candidate)
    return pools


def pick_items_for_quotas(
    quotas: OrderedDict[str, int],
    word_pools: dict[str, list[Candidate]],
    sentence_pools: dict[str, list[Candidate]],
    phrase_mode: bool,
) -> list[dict[str, object]]:
    selected: list[dict[str, object]] = []
    used_canonical: set[str] = set()
    per_category_index: Counter[str] = Counter()

    def add_candidate(category: str, candidate: Candidate) -> bool:
        key = canonical_text(candidate.text)
        if not key or key in used_canonical:
            return False
        if not is_learner_safe(candidate.text, candidate.english):
            return False
        if phrase_mode:
            if candidate.kind != "sentence" and category not in {"numbers", "time"}:
                return False
            token_count = len(candidate.text.split())
            if candidate.kind == "sentence" and (token_count < 2 or token_count > 12):
                return False
        per_category_index[category] += 1
        selected.append(to_item(candidate, category, per_category_index[category], phrase_style=phrase_mode))
        used_canonical.add(key)
        return True

    all_word = sorted(
        {c for values in word_pools.values() for c in values},
        key=lambda c: c.rank,
    )
    all_sentence = sorted(
        {c for values in sentence_pools.values() for c in values},
        key=lambda c: c.rank,
    )

    for category, quota in quotas.items():
        category_words = sorted(set(word_pools.get(category, [])), key=lambda c: c.rank)
        category_sentences = sorted(set(sentence_pools.get(category, [])), key=lambda c: c.rank)

        ordered: list[Candidate] = []
        seen: set[Candidate] = set()

        def extend_unique(items: Iterable[Candidate]) -> None:
            for item in items:
                if item not in seen:
                    ordered.append(item)
                    seen.add(item)

        if phrase_mode:
            if category in {"numbers", "time"}:
                extend_unique(category_words)
            if category == "emergency":
                extend_unique(sentence_pools.get("problems", []))
                extend_unique(sentence_pools.get("health", []))
                extend_unique(sentence_pools.get("hospital", []))
            extend_unique([c for c in category_sentences if c.source == "wikivoyage"])
            extend_unique([c for c in category_sentences if c.source == "tatoeba"])
        else:
            if category in WORD_FOCUSED_CATEGORIES:
                extend_unique(category_words)
                extend_unique(category_sentences)
            elif category == "daily-sentences":
                extend_unique(category_sentences)
                extend_unique(all_sentence)
                extend_unique(category_words)
            else:
                extend_unique(category_sentences)
                extend_unique(category_words)

            # Fallback priority from plan.
            extend_unique([c for c in all_sentence if c.source == "wikivoyage"])
            extend_unique([c for c in all_sentence if c.source == "tatoeba"])
            extend_unique(all_word)

        for candidate in ordered:
            if per_category_index[category] >= quota:
                break
            add_candidate(category, candidate)

        if per_category_index[category] != quota:
            raise RuntimeError(
                f"Could not satisfy quota for category '{category}' "
                f"(needed {quota}, got {per_category_index[category]})"
            )

    return selected


def validate_output(path: Path, expected_count: int, quotas: OrderedDict[str, int]) -> None:
    data = json.loads(path.read_text(encoding="utf-8"))
    if len(data) != expected_count:
        raise RuntimeError(f"{path.name}: expected {expected_count}, got {len(data)}")

    ids = [item["id"] for item in data]
    if len(ids) != len(set(ids)):
        raise RuntimeError(f"{path.name}: duplicate IDs found")

    counts = Counter(item["category"] for item in data)
    for category, expected in quotas.items():
        got = counts.get(category, 0)
        if got != expected:
            raise RuntimeError(f"{path.name}: category '{category}' expected {expected}, got {got}")

    for item in data:
        if not item.get("greek") or not item.get("english"):
            raise RuntimeError(f"{path.name}: empty text found in item {item.get('id')}")
        if not item.get("acceptedPronunciations"):
            raise RuntimeError(f"{path.name}: missing acceptedPronunciations in item {item.get('id')}")


def write_json(path: Path, data: list[dict[str, object]]) -> None:
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def build_for_language(
    language: str,
    source_paths: dict[str, Path],
    pronun_quotas: OrderedDict[str, int],
    phrase_quotas: OrderedDict[str, int],
) -> tuple[list[dict[str, object]], list[dict[str, object]]]:
    if language == "es":
        freq_path = source_paths["frequency_es"]
        dict_path = source_paths["wikdict_es_en"]
        local_sentences_path = source_paths["tatoeba_spa_sentences"]
        local_links_path = source_paths["tatoeba_spa_eng_links"]
        phrasebook_path = source_paths["wikivoyage_spanish_phrasebook"]
    elif language == "fr":
        freq_path = source_paths["frequency_fr"]
        dict_path = source_paths["wikdict_fr_en"]
        local_sentences_path = source_paths["tatoeba_fra_sentences"]
        local_links_path = source_paths["tatoeba_fra_eng_links"]
        phrasebook_path = source_paths["wikivoyage_french_phrasebook"]
    else:
        raise ValueError(f"Unsupported language: {language}")

    eng_sentences_path = source_paths["tatoeba_eng_sentences"]

    print(f"[{language}] loading frequency words...", flush=True)
    word_candidates = parse_frequency_words(freq_path, dict_path, language, limit=35000)
    print(f"[{language}] loaded {len(word_candidates)} word candidates", flush=True)
    print(f"[{language}] loading Tatoeba pairs...", flush=True)
    tatoeba_candidates = parse_tatoeba_pairs(local_sentences_path, local_links_path, eng_sentences_path, language)
    print(f"[{language}] loaded {len(tatoeba_candidates)} sentence candidates from Tatoeba", flush=True)
    print(f"[{language}] loading Wikivoyage phrasebook entries...", flush=True)
    phrasebook_candidates = parse_wikivoyage_phrases(phrasebook_path, language)
    print(f"[{language}] loaded {len(phrasebook_candidates)} sentence candidates from Wikivoyage", flush=True)

    sentence_candidates = phrasebook_candidates + tatoeba_candidates

    word_pools = build_pools(word_candidates)
    sentence_pools = build_pools(sentence_candidates)

    print(f"[{language}] selecting pronunciation dataset items...", flush=True)
    pronun_items = pick_items_for_quotas(pronun_quotas, word_pools, sentence_pools, phrase_mode=False)
    print(f"[{language}] selecting phrase dataset items...", flush=True)
    phrase_items = pick_items_for_quotas(phrase_quotas, word_pools, sentence_pools, phrase_mode=True)

    return pronun_items, phrase_items


def main() -> None:
    parser = argparse.ArgumentParser(description="Build Spanish/French NotchGreek-compatible datasets.")
    parser.add_argument(
        "--cache-dir",
        default=str(ROOT / ".cache" / "language-source-snapshots"),
        help="Directory to store downloaded source snapshots",
    )
    parser.add_argument("--refresh", action="store_true", help="Force re-download of source snapshots")
    args = parser.parse_args()

    cache_dir = Path(args.cache_dir).resolve()
    source_paths = download_sources(cache_dir, refresh=args.refresh)

    pronun_quotas = load_quota(GREEK_PRONUN, PRONUN_DEFAULT_ORDER)
    phrase_quotas = load_quota(GREEK_PHRASES, PHRASE_DEFAULT_ORDER)

    pronunciation_es, phrases_es = build_for_language("es", source_paths, pronun_quotas, phrase_quotas)
    pronunciation_fr, phrases_fr = build_for_language("fr", source_paths, pronun_quotas, phrase_quotas)

    write_json(OUT_PRONUN_ES, pronunciation_es)
    write_json(OUT_PRONUN_FR, pronunciation_fr)
    write_json(OUT_PHRASES_ES, phrases_es)
    write_json(OUT_PHRASES_FR, phrases_fr)

    validate_output(OUT_PRONUN_ES, sum(pronun_quotas.values()), pronun_quotas)
    validate_output(OUT_PRONUN_FR, sum(pronun_quotas.values()), pronun_quotas)
    validate_output(OUT_PHRASES_ES, sum(phrase_quotas.values()), phrase_quotas)
    validate_output(OUT_PHRASES_FR, sum(phrase_quotas.values()), phrase_quotas)

    print("Generated files:")
    print(f"- {OUT_PRONUN_ES}")
    print(f"- {OUT_PRONUN_FR}")
    print(f"- {OUT_PHRASES_ES}")
    print(f"- {OUT_PHRASES_FR}")
    print(f"- {OUT_METADATA}")


if __name__ == "__main__":
    main()
