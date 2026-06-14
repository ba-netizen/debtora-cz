# CLAUDE.md — Debtora CZ

Pokyny pro práci na tomto repu. **Na startu každé session přečti nejdřív [`HANDOFF.md`](HANDOFF.md)** —
obsahuje reálný stav (git, produkce, Supabase, TODO, blokery).

## Stack (orientace)
- Frontend: statické HTML/CSS/JS, **bez build stepu**, hostováno na Vercelu (`npx vercel --prod`).
- Backend: Supabase (PostgreSQL + RLS, Auth na `auth.users`, Edge Functions v Denu/TS, Storage).
- Migrace: `sql/0NN_*.sql` v pořadí; edge funkce v `supabase/functions/*`.

## Tvrdá pravidla
- **Service-role klíč NIKDY ve frontendu.** Anon klíč jen pro veřejné čtení přes RLS. Privilegované
  operace jen přes Edge Functions / SECURITY DEFINER RPC.
- **Edge regexy = třídy znaků** (`[0-9]`, `[^0-9]`, `[^]`), nikdy `\d`/`\w` — Supabase MCP deploy
  zpětná lomítka rozbíjí.
- **Nespouštět** `sql/legacy/*` (původní custom-login schéma).
- Deploy frontendu pouští **uživatel** (`npx vercel --prod`); neběhat bezargumentový Vercel MCP deploy.

## Správa kontextu a kompakce
Než dojde na kompakci kontextu (a vždy před koncem delší session), **aktualizuj `HANDOFF.md`** podle
reálného stavu. Na startu nové session ho přečti jako první zdroj pravdy.

**Při kompakci ZACHOVAT (nesmí se ztratit):**
- Finální podobu kódu (cesty + co soubor dělá), ne mezikroky.
- Architektonická rozhodnutí a **proč** vznikla.
- Schéma DB (tabulky, RLS, RPC), stav migrací (applied/pending).
- Názvy env proměnných / secrets a kde se nastavují (ne jejich hodnoty).
- Edge-cases a záludnosti (např. MCP komolí `\d`; ISIR WS2 = prázdný výsledek; VIES výpadek).
- Aktuální **TODO** s prioritami (P1/P2/P3) a otevřené blokery.

**Při kompakci ZAHODIT nebo jen shrnout do jedné věty:**
- Krok-za-krokem debugging a slepé uličky (stačí závěr a fix).
- Staré/přepsané verze kódu, dočasné experimenty.
- Plné výpisy logů, dumpů, tool outputů.
- Mezivýsledky, které už jsou nahrazené finálním stavem.

**Workflow:**
1. Před kompakcí: zkontroluj `git log`, stav migrací a edge funkcí → promítni do `HANDOFF.md`.
2. Po kompakci / na startu session: `HANDOFF.md` je výchozí kontext; teprve pak čti zdrojáky.
3. `HANDOFF.md` drž stručný a pravdivý — žádné placeholdery, jen reálný stav.
