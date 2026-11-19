# InstaSales — working notes for Claude

InstaMart's multi-channel profit dashboard. Live at
https://pickpackpro1.github.io/instasales-dashboard/

## Shape of the project

- `index.html` is the entire app — ~1.4 MB, with every parser, compute engine
  and the whole UI inside one inline `<script>`. There is no build step and no
  server. Expect to search within it rather than open a named module.
- Data lives in Supabase; `supabase/migrations/` holds the schema.
- `.github/workflows/pages.yml` deploys to GitHub Pages on every push to
  `main`. Pushing is publishing — the live dashboard updates a minute or two
  later. There is no staging environment.
- `.claude/launch.json` serves the folder on port 8777 (`python -m http.server`)
  for local preview.

## Channels and accounts

TikTok Shop, Amazon 1 (Vemart), Amazon 2 (Vefive), eBay, Shopify. The two
Amazon accounts are deliberately kept apart everywhere.

## Reaching the live dashboard

The app sits behind a client-side password gate. The user signs in themselves —
Claude does not type passwords into sign-in forms. Once they have, the app can
be read and driven through the browser pane.

Note: the in-app browser pane closes itself between turns, so it usually needs
reopening before the user can reach it.

## Changing data vs changing the app

Two different things, with different risk:

- **Data** (Cost Manager prices, SKU maps, OpEx, uploaded reports) writes to
  Supabase and is shared across everyone on the account. Because costs are
  dated, editing one can retroactively change what past months report as
  profit. Confirm with the user before each such change.
- **The app** means editing `index.html` here and pushing.

## Reaching the database from a local copy

The app signs in to Supabase, and that session is per ORIGIN. A local copy served
on localhost has no session, so every read comes back empty with NO error and
every write is refused. That is row-level security working, not a bug and not an
empty account - do not read an empty result on localhost as data loss, and do not
expect a local copy to exercise the cloud round trip. Check live data from the
deployed origin, where the session exists.

Checked 2026-11-19: the settings row holds the cost book (1,727 entries) and
price book (416), and anonymous access is denied. The earlier worry that the
public page exposed the data was wrong.

## Known open questions
- As of 2026-11-14, eBay listing 358157954894 ("Dry Floral Foam Bricks") showed
  -£3,573.67, single-handedly turning eBay from profitable to loss-making.
  Not yet investigated — could be genuine or a fee-calculation bug.
