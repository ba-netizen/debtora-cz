# E2E script pro Veo — spot „Ušetřil 122 Kč" (jeden souvislý prompt)

Cíl: vygenerovat celý spot jako navazující sekvenci ve Veo 3.1 (Flow), ne lepit 4 nesouvisející klipy. Klíč ke konzistenci: **stejná definice postavy a prostředí v každém segmentu, slovo od slova.**

Veo generuje klipy po max ~8 s → spot = **3 segmenty × 6 s** řetězené přes „Extend / continue from last frame". Audio: jen ambient (žádná řeč — české titulky dodáme v CapCutu). Žádný text v obraze.

---

## Definice postavy a prostředí (vlož do KAŽDÉHO promptu)

```
CHARACTER "MAREK": Czech man in his early 50s, short gray hair,
clean-shaven, navy blue sweater over white shirt, calm trustworthy face.
LOCATION: bright modern Prague apartment with white walls, wooden floor,
large window, small kitchen with wooden table.
STYLE: cinematic, shallow depth of field, natural film grain, realistic,
vertical 9:16. No on-screen text, no captions, no logos.
```

## Segment 1 (0–6 s) — Váhání a rozhodnutí ušetřit

```
[CHARACTER + LOCATION + STYLE block]

SHOT 1 (0-3s): Close-up. MAREK stands in the apartment hallway looking
at his smartphone screen, slightly hesitant expression, thinking about
something. Daylight. Ambient: quiet room tone.
SHOT 2 (3-6s): He gives a small dismissive smile, shakes his head,
locks the phone and slides it into his pocket with confidence.
Camera: slow push-in, handheld feel.
```

## Segment 2 (6–12 s) — Důvěra: předání klíčů
*(Extend z posledního snímku segmentu 1)*

```
[CHARACTER + LOCATION + STYLE block]
CONTINUITY: continues directly from previous shot, same hallway,
same lighting.

SHOT 3 (0-3s): A second man in his 30s wearing a gray jacket enters
frame; warm friendly handshake with MAREK, both smiling. Sunlight
through the window. Ambient: faint street noise, friendly murmur
(no intelligible words).
SHOT 4 (3-6s): Close-up of MAREK's hand placing apartment keys into
the younger man's open palm. Slow motion feel, optimistic warm tones.
```

## Segment 3 (12–18 s) — O půl roku později + lítost
*(nový klip — střihová elipsa, stejná postava a byt, jiná atmosféra)*

```
[CHARACTER + LOCATION + STYLE block]
TIME JUMP: six months later, same apartment but at dusk, cold dim
lighting, rain on the window.

SHOT 5 (0-3s): MAREK sits at the wooden kitchen table, exhausted,
staring at a large pile of unopened envelopes stacked in front of him.
Ambient: rain, distant thunder, ticking clock.
SHOT 6 (3-6s): Close-up. MAREK picks up his smartphone, screen light
on his regretful face, he slowly closes his eyes and lowers the phone.
Camera: slow push-in. Ambient fades to silence.
```

## Negative prompt (všechny segmenty)

```
text, captions, subtitles, watermark, logo, words on screen, distorted
hands, extra fingers, morphing face, different actor between shots,
cartoon, oversaturated
```

---

## Postprodukce (CapCut) — finální časování 0:21

| Čas | Zdroj | Titulek |
|---|---|---|
| 0–3 s | Seg. 1a | „Prověřit nájemce za 122 Kč?" |
| 3–6 s | Seg. 1b | „…Zbytečné. Vypadá slušně." |
| 6–12 s | Seg. 2 | „Ušetřeno: 122 Kč ✓" (styl zelené notifikace) |
| 12–15 s | Seg. 3a | „O 6 měsíců později: ani koruna nájmu." |
| 15–18 s | Seg. 3b | „Ušetřil 122 Kč za prověření." |
| 18–21 s | statický slide | **„Stálo ho to 80 000 Kč."** → Prověření nájemce **122 Kč** · Insolvence zdarma · debtora.cz + logo |

Hudba: tichý minimalistický podkres, od 12 s jen ambient/ticho, akcent na slide (knihovna Meta).

## Workflow ve Flow

1. Nový projekt → Veo 3.1, 9:16, délka 6 s (pozn.: vyžaduje plán s Veo 3.1; z ČR případně přes fal.ai/Replicate)
2. Segment 1 → vygenerovat 2–3 takes, vybrat
3. „Extend" na vybraném take → prompt segmentu 2
4. Segment 3 jako nový klip (časový skok) — konzistenci drží CHARACTER blok; ideálně přilož referenční snímek MAREKA ze segmentu 1 (image reference)
5. Stáhnout všechny segmenty → CapCut → titulky dle tabulky → export 1080×1920

Pokud Veo opět spadne na „internal error": otestuj nejdřív samotný SHOT 1 (zcela nezávadný) — když neprojde ani ten, je to región/účet, ne prompt → stejné prompty fungují 1:1 v Klingu 3.0 (má multi-shot režim, segmenty zvládne v jednom zadání).
