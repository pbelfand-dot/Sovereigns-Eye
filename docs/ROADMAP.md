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
| **4.3** | **Succession: name your heir, play on as them, regency, a family tree, "let the years pass"** (below) | Done |
| **5.1** | **Military: raids on the village, the warband, live battles with real risk** (below) | Done |
| **5.2** | **The wider realm: a map of the noble houses' seats, visits, regard, fostering kin; bandit camps to clear; battle orders, gentle fights** (below) | Done |
| **5.3** | **Your castle: a motte and bailey, then a stone castle, raised by your builders; houses that send men-at-arms in aid, rivals, and houses that come against you** (below) | Done |
| **6.1** | **The economy, step 1: the market: prices that move with the season, the harvest and your own trade; buying and selling food, wood and stone; the steward's standing orders; the treasury** (below) | Done |
| 6.2 | The economy, step 2: crafts that make goods (cloth, ironware, ale) and carts to the noble houses' seats, along the realm's roads | Next |
| 6.3 | The economy, step 3: the lord's mill, an annual fair by charter, and the Crown's tax on movable wealth (the sink for a rich town's gold) | Later |

## The market (Phase 6.1)

Decided (the player chose the economy for Phase 6; going ahead on the
recommendations): the economy in three steps, the market first. Before it,
nothing could be bought or sold: gold only came in (rents, dues) and went
out on one-off costs, about 4,100 gold in a whole game against a Town's
150 a day, and a stone castle waiting for stone couldn't buy any.

- `MarketData` (`WorldState.market`: the day's price pressure from your own
  trade, what's traded today, the steward's standing orders, a ledger of
  recent trades) and `Market` (static, `data/market.json`).
- Prices (gold per unit): food 0.3, wood 0.35, stone 0.9 in an even year,
  by season (food: Spring 1.25, Summer 1.15, Autumn 0.75, Winter 1.0; wood
  dearest in winter) and, for food, by the realm's harvest, drawn from the
  seed each autumn: plenty (x0.8, fields +10% that autumn), fair, poor
  (x1.3, -10%), dearth (x1.8, -20%), told when it comes in. Your own trade
  moves the price (0.4% a unit, at most 60%), recovering 30% a day, so a
  flood of sales fetches less and a rush of buying costs more.
- Where: the merchant's stall in the square from the start (25 units of
  each good a day, 30% on each side); each Market Hall adds 60 a day and
  narrows the spread by 5 points; the village's merchant best at haggling
  narrows it by up to 10 more (Politics: the Eye finds the gifted one).
- The steward's standing orders (needs a steward appointed): each morning
  buy up to a keep mark and sell above a sell mark, never spending below
  ten days' wages. Build panel: Market (prices, Sell/Buy in lots of 10 and
  50, the marks, the latest trades). Court panel: the treasury part by part
  (lands, rent, dues, Market Halls, the steward's hand; wages, tutors,
  upkeep) and the steward's trade this season.
- Calibration (`charter_sim.gd`, whose steward now keeps orders: ten days
  of food, wood and stone once chartered, more stone while the castle
  rises, the rest sold above four fifths of the stores; `MARKET=0` without):
  trading speeds a growing village, the Market Town and Town charters on
  seed 9 at days 68 and 127 (111 and 165 without), on 4242 at 81 and 93
  (103 and 130); 12345 about the same. A grown town's gold still piles up
  (53,000 by day 400 with trade, 45,000 without): trade turns gold into
  goods but doesn't take it away. That's Phase 6.3's Crown and works.
- Save v19 (the market).


## Your castle, and the houses at war (Phase 5.3)

Decided (going ahead on the recommendations after 5.2): the castle is the
house's own works, not a Build menu building: a **motte and bailey** first,
then a **stone castle** in its place; the steward chooses the ground; and
the noble houses take sides: **rivals**, **men-at-arms in aid**, and
**hosts** that come against a house they hold in contempt.

- `CastleData` (`WorldState.castle`: what stands, the works, the site,
  the crew, what's been used, why the works wait) and `CastleSystem`
  (static, `data/castle.json`): ordered from the Court panel when the
  charter allows (a Village for the motte and bailey, a Market Town for
  the stone castle) and the hire is paid. The site is chosen once
  (`CastleLayout.site_rect`: room for both castles) at the edge of the land
  the village builds on, its gate toward the village; boulders there are
  broken up for their stone, trees felled for their wood, the ground
  levelled (`TerrainHeight.set_pads`), a lane laid to the nearest road, and
  no building may be ordered on it. The village's builders work it at the
  usual rates, using wood and stone as they go; the works wait when a
  store runs dry. Builders at the castle make nothing else.
- `CastleView` raises the pieces (`CastleLayout`, from the castle kit) as
  the work is done; a stone castle takes the motte and bailey's place,
  the old palisade coming down first and the motte last. Its walls are
  solid (`WorldGeometry`), builders walk to their places at the works.
- What it gives: renown, room for more retainers, the regard of every
  house (not cooled by rivals); in a raid the warband forms up before the
  gate, fights harder (+5 / +10 Combat), breaks later, and the house's gold
  is half (timber) or wholly (stone) out of the raiders' reach.
- Rivals (`RealmData` `rival`, paired from the seed): half of what you win
  with a house you lose with its rival (gifts, talk, visits, fostering, a
  marriage; not a castle raised or a camp cleared, which please everyone).
- Aid: a house that holds yours warmly (40+), its seat within three days,
  sends men-at-arms (2 to 4, by its renown) against a coming raid; a
  friendly one (15+) sends them if you ask (Defence, "Ask House X for men"),
  at a cost in its regard. They stand in your line (`Battle`'s own NPCs)
  and the report says how they fared.
- Hosts: at a season's start a house at -40 or worse may demand a share of
  your gold (`Military.plan_host`), its host (5 to 14, a third of them
  knights) marching by the road toward its seat. Pay, and it keeps the
  peace (a truce); beat it, and it ransoms its fallen knights, you win
  renown, and it keeps the peace; lose, and it takes more than it asked.
- Pacing (historical): a motte of 40 m took some 50 men 42 working days;
  Harlech (1283-89) and Conwy (1283-87) took years. Here a motte and
  bailey takes about half a year of a well-run village's builders and a
  stone castle some two years. The charter sim's steward (`charter_sim.gd`,
  now raising the castle as soon as it can): on seed 12345 the motte and
  bailey took 19 days (begun on day 39), the stone castle 74 (begun on day
  68); on seed 9, 17 and 60 days; the charters came no later for it.
- Hosts (`life_sim.gd <seed> 40 steward favour`, the house courting one
  house each year): on seed 9 the courted house's rival turned to
  contempt and came against the house in year 7 and again in year 14, the
  courted house's men in the line both times (both beaten). Without
  courting anyone (`steward`, `steward matches` on seeds 9, 12345 and
  4242) no house turned hostile in 40 years: a host is the price of
  taking sides.
- In a live fight with a castle standing, the band (or host) comes for the
  castle, where the gold is, and meets the warband before its gate (at
  first it went for the square while the line waited at the gate, and a
  fight the captains called certain was lost piecemeal). Live host fights
  against a stone castle now follow the captains' odds
  (`capture.tscn battle_stats` with `BATTLE_KEEP=stone BATTLE_HOST=1`): a
  village's watch alone has little chance against a host of knights (odds
  0 to 0.4 on seeds 12345, 9, 4242, all lost), which is what allies, trained
  knights or paying the demand are for.
- Save v18 (the castle; rivals and truces, migrated from the seed).

## The wider realm (Phase 5.2)

Decided (going with the recommendations after 5.1): the wider realm next,
real risk kept as the default with a **Gentle fights** choice per game, and
two orders in a fight (**Charge now**, **Fall back**).

- `RealmData` gains the map: each house's seat (`pos`, `days` 2 to 4 days'
  ride, spread round the compass from the seed), what it's `known_for`
  (arms, command, learning, statecraft, stewardship: the attribute a
  fostered child learns), its lord or lady (`head`), the day you last
  `visited`, the house's young you've met (`households`: CharacterData with
  ids below -2000, never villagers, aged on each visit; past 25 they marry
  away and children are born) and the heir's `trip`.
- `Realm` (static, `data/realm.json`): regard (the houses' `standing`)
  fades each season; a visit, gifts and a talk (Politics, or a gaffe) raise
  it, as do fostering and clearing a camp near the seat. Visits: `set_out`
  (the heir is away: `CharacterData.away_at`), `arrive`, `give_gift`,
  `speak`, `look` (the Eye on their young), `ask_hand` (once a visit; the
  house must be friendly, then `MatchSystem.consider` plus the house's
  wish), `foster` (a kin child of 7 to 13; trains each season, home at 16
  or to rule), `take_leave`, `come_home` (the betrothed is brought into the
  village by `CharacterGenerator.bring_member` and wed, with the dowry).
- Camps (`Military`, `data/military.json` "camps"): a band makes camp out
  along one of the village's roads, hidden until its raid shows the way or
  the woodcutters find it; it starts at most of the band the village draws
  and grows, sends its whole band, keeps what it takes, and scatters when
  beaten down. The warband rides against a known camp (`ride_out`: away
  for the camp's days each way, the fight on arrival with `resolve`, the
  band +10 Combat on its own ground; `finish_camp`); the village keeps only
  who's left. With the heir at its head, the days pass as on a journey.
- The world: bodies leave and come back (`away`/`back` events); journeys
  run `pass_time(days, away)` (only a succession stops them); no saving
  while the heir is away. UI: the realm map (`RealmMap`, drawn from the
  seed: woods, hills, a river; regard rings), `RealmPanel` (J), the
  `VisitPanel`, camps and the expedition in the Court panel's Defence,
  camp fights in the battle report.
- Calibration (`life_sim.gd <seed> 40 steward`; the steward bot now also
  rides against a known camp when the captains' odds are good). Before
  camps were hidden, every fresh camp was cleared within days and no raid
  ever came; now, over 40 years: seed 9, 17 raids (16 won), 15 camps
  cleared, 15 fighters dead; 12345, 16 raids (all won), 13 camps, 4 dead;
  4242, 16 raids (11 won, tribute paid three times, a camp held against
  the warband), 9 camps, 22 dead. A band strikes every two to three years,
  and the danger lies in who you lose.

## Military (Phase 5.1)

Decided with the player: **military first** (before the wider realm),
**real risk** (anyone who falls may die, knights and the heir too) and
fights that **play out in the village** rather than as a report.

- `Military` (static, `data/military.json`): raids are planned with a
  warning (`plan_raid`: size from people, charter and renown, harder bands
  as the years pass; the raiders are generated people kept out of the
  village, ids below zero), paid off (`pay_off`) or fought; the warband
  (retainers, knights, the watch, the levy if called); blows (`strike`:
  Combat against Combat, armor by role), the breaking point (the captain's
  Leadership, brave and craven), `resolve` for fights out of sight and
  `odds` (the captains' reckoning, from fixed-seed fights), and `finish`
  (the fallen die about a third of the time or lie wounded; Combat for
  those who stood; renown and purse, or loot and a shaken village).
- `Battle` (in the world): the band marches up its road; the warband,
  warned two days before, stands in line on open ground across it; the
  village shelters (a brain errand); at contact the fight pairs off (each
  takes the nearest foe least beset), with the same `strike`, and a side
  breaks on the fallen among those in the fight. You can strike (E) and be
  struck. Health bars, sword and axe and shield in hand, sound, music.
- Calibration (`capture.tscn ... battle_stats`, seeds 1 to 10 with and
  without the levy): live fights won 10 of 20 against captains' odds that
  averaged 0.61; across 60 fights out of sight, 32% of the fallen died (the
  death roll is 0.35).
  Over 40 years with the steward bot (`life_sim.gd ... steward`, which calls
  the levy when the odds are poor and pays when even that isn't enough, but
  never recruits a fighter): the watch alone, trained by its fights, holds
  for 10 to 28 years on the seeds tried (9, 12345, 4242), losing now and
  then; after that the bands outgrow it and it pays tribute, about a fifth
  of its gold each time. Finding and training fighters with the Eye is the
  answer.

## Succession (Phase 4.3)

Decided with the player: a child who inherits rules through a **regent**
until 16; **any child** can be named heir; the years can be let pass a
season or a year at a time **with a summary**; and you live on the **same
gentle curve** as everyone, warned when your health fails.

- `Succession` (static, data in `data/succession.json`): `heir` (named, else
  the eldest child), `successor` (heir, grandchild, sibling, spouse, anyone
  of the house), `name_heir` (older children passed over take it ill once),
  `pass_on` (you go on as the successor: opinions blend, the Eye's records
  stay), `crown` (the dowager, the lady, the house's list of rulers, a
  regent for a minor), the regency's income and skim, the health warning and
  the family tree. Only an empty house ends the game.
- The world hands your body on (`VillageWorld.take_over`) and lets the years
  pass (`pass_time`): a few days a frame, quietly, stopping early for what
  needs you. Save v15 (heir, regent, rulers, warnings, an ended house).
- Over 100 years with the steward bot, gifted suitors taken and the most
  gifted child named heir (`tools/life_sim.gd -- <seed> 100 steward matches
  heirs`): seeds 9, 4242 and 12345 each pass through 4 or 5 rulers and 3 or
  4 player characters, each warned at 62 (or on inheriting, if older), and
  no house ends. Children are usually grown by then, so a regency comes only
  when a ruler dies young (`capture.tscn -- 9 <dir> succession` stages one:
  seed 2's lord dies at 33 and his son of 13 rules through his mother).

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
