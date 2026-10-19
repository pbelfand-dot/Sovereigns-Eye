# Roadmap

What's done, what's being built, and what comes next. Each phase ships as a
playable build. Numbers and content live in `data/*.json`.

| Phase | What | Status |
|---|---|---|
| 1 | Village, people, Appraisal (current vs. hidden potential) | Done |
| 2 | Noble society: the heir, retainers, offices, training, knighthood | Done |
| Art | Kit buildings, meadow, outfits, nature, props, sound | Done |
| 3.1 | Territory: stores, Build menu, construction sites, Master of Works | Done |
| 3.2 | Growth: settlers, homes that build and upgrade themselves | Done |
| **Eye** | **On foot: scan first, then talk and persuade** (below) | Done (optional extras below) |
| 3.3 | Charters: Hamlet → Village → Market Town → Town (below) | Done |
| **4.1** | **The years turn: ageing, growing up, marriage, children who inherit gifts, gentle deaths, the lord's succession** (below) | Done |
| **4.2** | **The house's matches: your own marriage, suitors from noble houses, matches for kin and retainers, your children's tutors** (below) | Done |
| 4.3 | Succession: name your heir, play on as them, regency, a family tree, "let the years pass" | Next |
| 5+ | Wider realm, military | Later |

## The house's matches (Phase 4.2)

Decided with the player: the heir can marry **both** a villager or retainer
(asking face to face) and a noble from a neighbouring house (suitors who
visit). Nobody is made to marry: every answer is weighed, not rolled, like
an offer of service, and comes with its reasons.

- `RealmData`: four noble houses round about (named for surnames the village
  doesn't use, with seats, renown and their standing with yours), the seed's
  own; saved (v14), and older saves get the houses their seed would have.
- The heir asks for a hand in the talk. Consent (`MatchSystem.consider`):
  opinion of the heir or the partner, the station it brings, duty (kin),
  loyalty (retainers), a sweetheart, a rival, the years between them, traits.
- Suitors come about once a year while the heir is unmarried (each visit is
  set for 0.5 to 1.5 times the average gap after the last ends, so there are
  no long droughts), then for unmarried kin. They stay at the manor for a
  season with a dowry and a boastful letter; the Eye tells the truth.
  Accepting brings the dowry, renown and standing; declining costs standing,
  and letting the visit lapse costs more.
- Matches for kin and retainers from their card; the newcomer joins the
  house at the manor (or the retainer's home) and takes its name. The heir's
  spouse becomes Lady (or Lord) on succession.
- Tutors: the house's children from 6 to 17 train in a chosen gift at the
  manor for 1 gold a day each.
- Over 20 years with the steward bot and a house that accepts the first
  suitor with a gift of B rank or better (`tools/life_sim.gd -- <seed> 20
  steward matches`): on seed 9 the heir weds on day 21 and a sister weds a
  suitor in year 7 (after one sent home); on seed 4242 the heir weds on day
  38, and two daughters of the house later marry suitors, one of them with
  an S+ gift. Charter pacing is unchanged (Town on day 72 for seed 12345).

## The years turn (Phase 4.1)

Decided with the player: **seasons of 10 days** (a year is 40 days, about 80
minutes at 8x), people age on their birthday so ages always match the date,
and a **gentle** tone: no child dies, and no one dies giving birth.

- Everyone has a birthday. Children grow taller and their gifts begin to show;
  at 13 they start on the family's work and at 16 take a grown trade (often a
  parent's; the fields while food is short). Commoners retire at 65 and their
  trade passes on.
- Villagers outside the house court, marry and set up home; couples have
  children whose looks, traits and gifts follow theirs often, never always:
  two parents with S+ Combat have an A-rank-or-better fighter about a third of
  the time (a 7% chance otherwise), and S+ eleven times as often.
- Adults die in time (mostly old age, rarely illness); kin mourn for a season;
  the departed stay on record (cards, chronicle). When the lord dies, the heir
  inherits the title.
- When a village holds more than its charter allows, young unmarried adults
  leave to seek their fortune.
- Tuning: `tools/life_sim.gd` lives a village for decades, data only. Left to
  itself a Hamlet holds at about 70 people for 40 years with food in balance
  (on one seed the elders outnumber the farmers in the fourth decade, and the
  player has to build). With the steward bot (`tools/charter_sim.gd`, which
  now also builds another granary when the one it has is full) every seed
  tried reaches Town between day 72 and day 157.


## Charters (Phase 3.3)

A settlement grows by royal charter (`data/charters.json`, `CharterSystem`).
Each charter has a checklist and a fee; when both are met, **Petition the
Crown** in the Build panel (B) grants it at once: banners go up around the
square, renown rises and the chronicle records it.

| Charter | Room for | Asks for | Unlocks and grants |
|---|---|---|---|
| Hamlet | 70 people | (the start) | |
| Village | 110 | 60 people, 2 Timber Houses, 5 days of food, content villagers, renown 12; 150 gold, 40 wood | a second tavern and chapel, more farmsteads; dues, +1 household place |
| Market Town | 150 | 95 people, 2 Townhouses, a bakery, a granary, happiness 53+, renown 40; 400 gold, 80 stone | the **Market Hall**; Townhouses take a second family (lodgers) |
| Town | 200 | 135 people, 6 Townhouses, a Market Hall, two chapels, happiness 55+, renown 80; 900 gold, 200 stone | more of everything; Townhouses take a third family |

Every charter also widens the land the village may build on, brings in
dues, draws settlers and makes villagers proud (a little happiness). The
**Market Hall** is an arcaded hall from the kit (open arches on timber
posts, a hall above): two merchants trade there for gold every day, market
days draw settlers, people living near it are happier, and it counts as
the market Townhouses need.

A steward bot (`tools/charter_sim.gd`) reaches Town on every seed tried,
between day 72 and day 157 (with Phase 4.1's ten-day seasons, births and a
second granary when the first is full), and fills its 200 places; beyond that,
growth comes from upgrading more homes (more taverns, chapels and markets
in the outer streets).

## On foot: scan first, then talk and persuade

**Goal:** finding exceptional people should feel like spotting a hidden gem
in a crowd, not reading a spreadsheet, and winning them over should feel
like persuading a person, not rolling dice.

### The loop

1. **Walk** the village as your heir: WASD / left stick / touch stick, a
   close camera that follows you, buildings in the way of your feet and
   your view.
2. **Look** at someone near you and use the **Sovereign's Eye** (Q / Y /
   the Eye button). No conversation needed, but they must be close (about
   10 paces), outdoors and in plain sight, so a whole town can't be read
   from a menu.
3. **The reveal** scales with their real talent (below).
4. **Talk** to the promising ones (E / A / Talk, within about 3 paces).
5. **Learn what they want**, **make an offer**, hear their answer, and
   decide: recruit, remember, appoint, or walk on.

The Eye decides who is worth talking to. Conversation is how you understand
and persuade them. Kingdom management (building, planning) happens at the
**map table** (Tab / M / View): the overhead view. Leaving it puts you back
in the heir's boots.

### Rules of the Eye

1. **Nothing gives rarity away before the Eye.** Before you look at
   someone with the Eye you see only public things: name, job, age,
   family, home, what they're doing, their traits and mood. No numbers,
   no rank badges, no glow, no overhead marker, no "exceptional" notices.
2. **Observation still matters.** Talk and gossip carry clues, but never
   proof. A gifted person's talk often turns to their gift. Braggarts
   oversell themselves, and humble or shy people undersell. Rumors attach to
   a few ordinary show-offs too.
3. **Near and in sight.** The Eye works on the person you face, within
   reach and with nothing in between (`data/controls.json` "scan").
4. **The reveal scales with real talent**, in the game's own medieval look:
   a sealed card with the Eye pressed in wax, clues, the seal breaking, and
   the card turning over.
   - **Ordinary:** a quick, quiet reveal. Plain frame, a lute's open fifth.
   - **Skilled:** a small bell, a light sweep, a silver frame, a harp
     strummed as the card turns and a few sparks.
   - **Exceptional:** gold and royal blue, a longer build-up. The camera
     moves closer, a deep bell rings, and clues come (their role, then the
     gift without its rank) over a rising harp and drum roll. The seal
     cracks with light, a held breath, then the card turns on a drum stroke
     and bells, a ring of light runs out and each ability lands on its own
     note.
   - **Legendary:** the biggest sequence. A heartbeat, a great bell, and the
     Eye's inscribed ring turns. The person's silhouette appears in the
     card's window, then a motto, and the seal bursts. The card turns on the
     victory fanfare, with rays of light, the most sparks and falling gold
     leaf, and the top skill lands last on a double bell.
5. **The first reveal is cinematic; later looks are a quick card.** A tier's
   full sequence can be skipped once you've seen it.
6. **Accessible:** reduce motion (no camera moves, shakes, spins or flips;
   shorter), reduce flashes, and captions for important sounds. A tier is
   never shown by color alone: each has a name, a crest shape
   (none / shield / sun / crown), pips (1–4) and a frame pattern
   (plain / single / double / filigree).
7. **Actionable:** after the reveal you can talk to them, appoint (your own
   retainers), remember (marked in the ledger), open their card or close.

### Rules of persuasion (`data/recruitment.json`)

No single percentage. Everyone weighs their own **motives**, from who they
are:

| Motive | Who it matters to |
|---|---|
| Fondness for you | Their opinion of you, friendship; loyal and kind people most |
| Money and security | The poor, the greedy, the hungry, parents |
| A home for their family | Parents, crowded households, the homeless |
| Advancement | The ambitious, the young, the overlooked gifted |
| Respect, duty and prestige | Burghers, clergy, knights; the devout, honest, brave, proud |
| *Ties to their life here* (holds them back) | Business owners, friends, a working spouse |
| *Caution* (holds them back) | The craven, the content, the old |

Skilled tradespeople would give up their trade to join, unless offered a
workplace where they can keep it. Working people won't give up their living
for no wage. Your house's **standing** (paid wages, kept promises) colours
every answer. One strong motive met in full can be enough on its own.

**Offers are concrete and enforced:** wages are paid from the treasury
every day; a home must be free (or promised: keep it within 6 days or lose
trust, standing, and possibly the person); a job needs a workplace with
room; offices must be vacant. **Answers are in plain words:** they accept,
name their terms (a counteroffer you can agree to), or refuse and say why.
**An offer can always be made**, since offers are what the conversation
is for: a refusal never closes the door (improve the terms and propose
again; only an insulting lowball costs a little opinion), a household
larger than your renown supports only costs upkeep (2 gold a day per extra
retainer), and your own retainers hear **new terms** (taken if they're no
worse by their own motives, raising loyalty; worse terms are turned down).
Only you, your own family and children under 10 can't be asked.

Different people, different paths (each one is a test in
`tests/test_recruitment.gd`):

- a poor, gifted craftsperson comes for **pay, a workshop and a home**
  (pay alone isn't enough to leave their trade);
- a **loyal friend** accepts a **modest wage** (a stranger wouldn't);
- an **ambitious fighter** wants **a squire's place or training**, not money;
- a **parent** comes for **a home for the family**;
- a **prosperous citizen** refuses money but answers to **duty and an
  office**.

### Build order

- [x] Reusable reveal system: `EyeReveal` plays step lists from
      `data/eye.json`. `EyeEmblem` draws the Eye; `RevealCard` is the card
- [x] Four distinct tiers, a quick repeat look, skip after seen
- [x] Reduce motion, reduce flashes and captions settings; tier never shown
      by color alone
- [x] Talent hidden everywhere until the Eye (card, court panel, ledger,
      mood wording, notices)
- [x] Direct control: `HeirController` (keyboard, controller, touch stick),
      a following camera that rises over roofs, collision with buildings,
      trunks and props (`WorldGeometry`), optional click-to-move
- [x] Scan first: focus on the person you face, Eye within reach and sight
      (`Discovery.scan_check`); no talk needed
- [x] The map table (overview) for building and planning; leaving it
      returns to the heir
- [x] Motive-based recruitment (`Recruitment`): asking about their life,
      offers, counteroffers, plain-language reasons, enforced terms and
      promises, the house's standing
- [x] Go-ahead for the final polish (the gameplay video:
      `tools/gameplay_demo.tscn` records it)
- [x] Polish (capture mode `eye`, tests in `tests/test_eye.gd`):
  - **Per-tier timing.** The steps keep to one clock, so beats never
    drift, and each tier's music is scored to its steps.
  - **Custom eye-opening art.** `EyeEmblem` is an illuminated roundel. Its
    lids part on a slit of light to show an ivory eye with a fibred iris,
    and the pupil narrows as it focuses. The ring grows richer by tier, up
    to the legend OCVLVS PRINCIPIS OMNIA VIDET.
  - **Richer particles** (`RevealFX`): sparks burst from the card's edges,
    a ring of light runs out when the seal breaks, and embers rise. The
    rarest tiers add a halo, turning rays and falling gold leaf.
  - **A dedicated sting for each tier.** Bells, harp, lute, drums and a
    drone, synthesized by `tools/audio/make_stings.py`
    ([audio/stings/](../audio/stings/README.md)). A rise plays under the
    clues and a landing as the card turns, then a note for each ability
    and the stamp's bell. The world's music and ambience are lowered while
    the Eye is open.
  - **Card portrait lighting.** The portrait sits in an arched niche lit in
    the tier's colors, with a warm key light and rim lights in the tier's
    glow (`PortraitStudio.rim_color`).
  - **The card itself.** The back is tooled leather, with a window for the
    silhouette and a wax seal on ribbons that cracks, light leaking
    through. The front is grained parchment.
- [x] Optional: idle "bark" lines villagers say aloud as you pass; rebinding
      keys
  - **Villagers' remarks** (`Barks`, `data/barks.json`): as the heir walks
    by, a villager may say a few words over their head: a greeting by what
    they think of you, their work, the hour or season, a real worry, or a
    clue to a gift. Never a rank or a number. One voice at a time, no one
    repeats themselves, and it can be switched off.
  - **Rebinding keys** (Esc → Keys...): every keyboard key except Esc, by
    where it works; a clash swaps the two; saved between sessions; prompts
    and help name the player's keys as their keyboard labels them.
