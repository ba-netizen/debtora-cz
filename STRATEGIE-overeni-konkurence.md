# Konkurenční strategie — modul „Ověření nájemce" (DEBTORA CZ)

Průzkum: červen 2026

---

## 1. Trh

V ČR je cca **223 tisíc investičních bytů** v rukou cca **71 tisíc pronajímatelů**; 78 % bytů drží malí a střední pronajímatelé (fyzické osoby). V nájmu bydlí ~21 % domácností a podíl roste. Při běžné obměně nájemců (20–30 % ročně) jde řádově o **50–100 tisíc nových nájemních vztahů ročně** u malých pronajímatelů — tedy trh prověření v řádu jednotek milionů Kč ročně.

**Klíčový závěr: samotné prověřování není byznys, který uživí firmu — je to akviziční vstup (wedge).** Skutečná hodnota je v tom, koho přivede: pronajímatele, tedy budoucí klienty tržiště Debtora (prodej pohledávek za neplatiči) a odběratele navazujících služeb.

## 2. Konkurence

| Konkurent | Cena | Síla | Slabina |
|---|---|---|---|
| **Rentivo** (provereni.rentivo.cz) | 129 Kč / 199 Kč s Bank iD | Nejlepší produkt: 11 registrů CZ/SK/UA, Bank iD flow, PDF report | Malá distribuce, prověření je doplněk k SW na správu nemovitostí |
| **Bezrealitky** | 129 Kč | Obrovská distribuce (inzertní portál), prověření v místě poptávky | Jen 7 subjektů, bez Bank iD, bez monitoringu; vyžaduje RČ a adresu |
| **UlovDomov** | 149 Kč | Portálová distribuce, výsledek do 1 min, 6 rejstříků | Bez Bank iD, doplňková služba |
| **CEE oficiálně** (ceecr.cz) | 60 Kč | Autoritativní zdroj | Jen exekuce, surový výpis, žádná interpretace |

Všichni končí ve stejném bodě: **vydají report a tím služba končí.** Nikdo neřeší, co se děje po podpisu smlouvy, a nikdo nepomáhá, když už nájemce dluží.

## 3. Strategie: „Celý životní cyklus rizika"

Nesoutěžit o to, kdo má hezčí report. Vyhrát tím, co konkurence strukturálně nemůže kopírovat — Debtora je jediná, jejíž jádro je **trh s pohledávkami**.

```
   PŘED nájmem          BĚHEM nájmu              PO problému
   ─────────────        ─────────────            ─────────────
   Prověření 122 Kč  →  Monitoring 39 Kč/měs  →  Vymožení / odkup pohledávky
   (konkurence ano)     (NIKDO nenabízí)         (NIKDO nemá — jádro Debtory)
```

### Pilíř A — Monitoring nájemce (hlavní produktová diferenciace)
Průběžné hlídání nájemce po dobu nájmu: nová exekuce, insolvence → okamžitý e-mail pronajímateli. Technicky triviální rozšíření (Smart Collectors podporuje dávkové dotazy, ISIR zdarma; cron přes pg_cron). Cena **39 Kč/měs** nebo 390 Kč/rok za nájemce → **opakovaný příjem** místo jednorázových 122 Kč. Nikdo na trhu to malým pronajímatelům nenabízí.

### Pilíř B — „Když už je pozdě" (nekopírovatelná synergie)
Pronajímatel s neplatičem je v reportu i monitoringu jediným klikem od řešení: *„Nájemce dluží? Pomůžeme vám pohledávku vymoci, nebo ji od vás odkoupíme."* → lead pro tržiště Debtora. Konkurenti by museli postavit celý marketplace, aby tohle nabídli. Zároveň obráceně: každý prodejce pohledávky z nájmu je kandidát na prověřování a monitoring u dalšího nájemce.

### Pilíř C — Cena a free tier jako akvizice
- Placené kontroly trvale **5 % pod trhem** (122 / 189 Kč s Bank iD) — u komodity rozhoduje cena.
- **ISIR + ARES zdarma** (máme hotové, náklad 0 Kč) — konkurence nedává nic zdarma. Bezplatná kontrola = SEO magnet („zkontrolovat insolvenci zdarma") a sběr registrací.
- Nájemcův report s Bank iD lze **30 dní sdílet dalším pronajímatelům** — nájemce zaplatí jednou a sám službu šíří (virální smyčka, kterou Bezrealitky má jen uvnitř svého portálu).

### Pilíř D — B2B kanál (obejití distribuční nevýhody)
Bezrealitky a UlovDomov vyhrávají distribucí na vlastních portálech — tam je nedohoníme. Obejdeme je tam, kde portály nejsou:
- **realitní kanceláře a správci nemovitostí**: balíčky (94 Kč/ks už máme), API/white-label report s logem RK,
- **poskytovatelé garantovaného nájmu** (Ideální nájemce spravuje 2 500+ bytů — prověřují neustále),
- **SVJ a družstva** (prověření člena/podnájemce).

### Pilíř E — Důvěra a obsah
- Transparentně uvádět oficiální zdroje (CEE, ISIR justice.cz) — odlišení od šedých přeprodejců výpisů.
- Obsahový marketing: průvodce „jak vybrat nájemce", vzory smluv a dodatků zdarma ke každému reportu, kalkulačka „kolik stojí neplatič" (6–18 měsíců vystěhování) → SEO + sběr e-mailů.
- Badge „Prověřeno Debtora" s QR ověřením pravosti reportu.

## 4. Co NEdělat

- Nezávodit v počtu registrů (SK/UA doplnit až podle poptávky — Rentivo je má, ale rozhodující jsou CZ exekuce + insolvence).
- Nestavět vlastní inzertní portál kvůli distribuci.
- Nedotovat cenu pod náklady — 5 % pod trh stačí, válka o cenu s portály je prohraná.

## 5. Roadmapa spuštění

1. **Teď:** dokončit Comgate + nasadit, spustit free tier bez fanfár (SEO začne pracovat).
2. **+1 měsíc:** smlouva Smart Collectors → ostrá CEE kontrola; obsahové stránky (průvodce, kalkulačka neplatiče).
3. **+2 měsíce:** monitoring nájemce (pg_cron + e-maily) — hlavní diferenciace; CTA „neplatič → prodejte pohledávku" do reportů.
4. **+3–4 měsíce:** Bank iD (smlouva běží paralelně od začátku), pozvánkový flow, sdílení reportu.
5. **+6 měsíců:** B2B: API pro RK, white-label, oslovení správců a poskytovatelů garantovaného nájmu.

## 6. Metriky úspěchu

- počet bezplatných kontrol/měs (akvizice) a konverze free → paid (cíl 5–10 %),
- podíl monitoringových předplatných na tržbách (cíl: do roka > jednorázové kontroly),
- počet leadů předaných na tržiště Debtora z reportů s nálezem,
- CAC ≈ 0 z organiky (SEO free tier) vs. placené kanály.

---

*Zdroje: provereni.rentivo.cz, bezrealitky.com, ulovdomov.cz, ceecr.cz, Asociace nájemního bydlení (studie 223 tis. investičních bytů), ČSÚ (podíl nájemního bydlení).*
