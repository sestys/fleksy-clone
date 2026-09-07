#!/usr/bin/env python3
"""Builds Resources/Dictionaries/names-{cs,en}.txt from public name statistics.

Why this exists: the bundled word lists come from OpenSubtitles, so they know the
names that get *said in films* and little else. English comes off well (of the top
1000 US surnames only ~90 are missing); Czech does not, and the keyboard mangled
Kucera into kamera, Adela into dela and Sarka into sakra.

Sources, both public statistics rather than creative works:

  cs  Ministerstvo vnitra CR name frequencies, split by given name / surname and by
      gender, mirrored with diacritics intact at github.com/wilx/jmena. The commonly
      cited copy at github.com/lpavlicek/zxcvbn-czech is romanised, which is useless
      here: adding "novak" without "novak"-with-accents makes correction worse, not
      better.
  en  US Census 2010 surnames (public domain). Given names are not added: the corpus
      already has them.

The sources count people; the lexicon counts word occurrences. Those cannot be
converted into one another honestly: the names present in both are disproportionately
the ones that are also ordinary words (Cerny = black, Svoboda = freedom, Brown,
Miller), so any measured ratio is inflated by exactly the entries that tell you least.
Rank is mapped into an explicit frequency band instead, which preserves the ordering,
keeps the band under deliberate control, and does not depend on population size.

Run: python3 scripts/build-names.py   (downloads sources into a cache directory)
"""

import csv
import io
import math
import os
import re
import subprocess
import sys
import unicodedata
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DICTS = os.path.join(ROOT, "Resources", "Dictionaries")
CACHE = os.path.join(ROOT, "build", "name-sources")

MVCR = "https://raw.githubusercontent.com/wilx/jmena/master/"
CENSUS = "https://www2.census.gov/topics/genealogy/2010surnames/names.zip"

# How many of each kind to keep. Given names are steeply distributed (the top 1000
# cover 97% of Czechs) so a short list does nearly everything; surnames have a long
# flat tail, and every extra thousand costs memory and adds near-miss candidates that
# compete with ordinary words, so the list stops well before the tail is exhausted.
KEEP = {"cs_given": 1000, "cs_surname": 3000, "en_surname": 5000}

# The band each kind's ranking is mapped onto, most common name first. The floor is
# what stops a rare name being corrected away; the top is deliberately modest, because
# every name common enough to be *said in films* is already in the corpus and gets
# skipped below - what we are adding is by definition the rarer tail. For reference,
# 12000 is around the top 8% of Czech words and 8000 the top 10% of English ones.
FLOOR = 120
TOP = {"given": 12_000, "surname": 8_000}

WORD = re.compile(r"^[^\W\d_]+$", re.UNICODE)


def fold(word):
    """Strips diacritics, matching Diacritics.fold in FleksyCore."""
    return "".join(c for c in unicodedata.normalize("NFD", word.lower())
                   if unicodedata.category(c) != "Mn")


def fetch(url, name):
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, name)
    if not os.path.exists(path):
        print(f"  downloading {name}", file=sys.stderr)
        subprocess.run(["curl", "-sSL", "--fail", "-m", "180", "-o", path, url], check=True)
    return path


def load_lexicon(language):
    """The bundled word list: {word: frequency}."""
    words = {}
    with open(os.path.join(DICTS, f"{language}.txt"), encoding="utf-8") as f:
        for line in f:
            parts = line.split()
            if len(parts) == 2:
                words[parts[0]] = int(parts[1])
    return words


def load_mvcr(filename):
    """A semicolon-separated 'NAME;count' file, header included."""
    counts = {}
    with open(fetch(MVCR + filename, filename), encoding="utf-8") as f:
        reader = csv.reader(f, delimiter=";")
        next(reader, None)
        for row in reader:
            if len(row) >= 2 and row[1].strip().isdigit():
                counts[row[0].strip().lower()] = int(row[1])
    return counts


def load_census():
    with open(fetch(CENSUS, "census2010.zip"), "rb") as f:
        archive = zipfile.ZipFile(io.BytesIO(f.read()))
    with archive.open("Names_2010Census.csv") as raw:
        reader = csv.DictReader(io.TextIOWrapper(raw, encoding="utf-8"))
        counts = {}
        for row in reader:
            name = row["name"].strip().lower()
            if name and name != "all other names" and row["count"].isdigit():
                counts[name] = int(row["count"])
    return counts


def band(kind, position, total):
    """Maps a name's rank onto the frequency band for its kind, log-linearly, so the
    spacing matches how word frequencies are actually distributed."""
    top = TOP[kind]
    if total <= 1:
        return top
    span = math.log(top) - math.log(FLOOR)
    return round(math.exp(math.log(top) - span * position / (total - 1)))


def merge(*sources):
    """Combines people counts, keeping the larger where a name appears in several."""
    out = {}
    for source in sources:
        for name, count in source.items():
            out[name] = max(out.get(name, 0), count)
    return out


def build(language, groups, known=None):
    """groups: [(kind, {name: people count}, keep)]
    known: every name the source knows, any spelling, for the tests below."""
    known = known or {}
    lexicon = load_lexicon(language)
    # The sources list spellings separately, so an accented name and its plain variant
    # both appear (Ondrej-with-accents 60248 alongside Ondrej 1951). Adding the minority
    # spelling is worse than useless: it shadows the correct one, which is how the first
    # cut of this list made the keyboard "correct" Ondrej-with-accents into Ondrej.
    # Whichever spelling more people actually have is the one that stands.
    majority = {}
    for name, people in known.items():
        bare = fold(name)
        if people > known.get(majority.get(bare, ""), 0):
            majority[bare] = name
    # Words the lexicon already holds, indexed by accent-free form. A name that folds
    # onto a *more common* word must sit below it, or typing the word gets "corrected"
    # into the name: nic -> nic-with-accents, sakra -> Sakra, dostal -> Dostal.
    #
    # Collisions with a *rare* corpus entry need no such care, and must not get it. Those
    # are usually the name itself with its diacritics knocked off in a subtitle (novak,
    # 276, beside Novak-with-accents, the most common Czech surname of all); the name's
    # own band value already outranks them, which is what makes typing "novak" produce
    # the properly spelled name.
    by_folded = {}
    for word, frequency in lexicon.items():
        by_folded.setdefault(fold(word), []).append(frequency)

    chosen = {}
    stats = {"already known": 0, "too short": 0, "not a word": 0,
             "minority spelling": 0, "demoted": 0}
    for kind, counts, keep in groups:
        ranked = sorted(counts.items(), key=lambda kv: -kv[1])[:keep]
        for position, (name, people) in enumerate(ranked):
            if len(name) < 3:
                stats["too short"] += 1
                continue
            if not WORD.match(name):
                stats["not a word"] += 1
                continue
            bare = fold(name)
            preferred = majority.get(bare, name)
            if preferred != name and known.get(name, 0) * 4 < known.get(preferred, 0):
                stats["minority spelling"] += 1
                continue
            if name in lexicon:
                stats["already known"] += 1   # the corpus covers it; nothing to add
                continue
            frequency = band(kind, position, len(ranked))
            strongest = max(by_folded.get(bare, [0]))
            if strongest >= frequency:
                frequency = max(FLOOR, strongest // 2)
                stats["demoted"] += 1
            chosen[name] = max(chosen.get(name, 0), frequency)

    path = os.path.join(DICTS, f"names-{language}.txt")
    with open(path, "w", encoding="utf-8") as f:
        for name, frequency in sorted(chosen.items(), key=lambda kv: (-kv[1], kv[0])):
            f.write(f"{name} {frequency}\n")
    notes = ", ".join(f"{v} {k}" for k, v in stats.items() if v)
    print(f"{path}: {len(chosen)} names  ({notes})")


def main():
    print("Czech (Ministerstvo vnitra CR)", file=sys.stderr)
    given = merge(load_mvcr("cet_jm_muzi_ciz-utf8.csv"),
                  load_mvcr("cet_jmena_zeny_vsechny-utf8.csv"))
    surnames = merge(load_mvcr("cet_prijm_muzi-utf8.csv"),
                     load_mvcr("cet_prijm_zeny-utf8.csv"))
    build("cs", [("given", given, KEEP["cs_given"]),
                 ("surname", surnames, KEEP["cs_surname"])],
          known=merge(given, surnames))

    print("English (US Census 2010)", file=sys.stderr)
    census = load_census()
    build("en", [("surname", census, KEEP["en_surname"])], known=census)


if __name__ == "__main__":
    main()
