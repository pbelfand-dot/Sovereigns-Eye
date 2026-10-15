# Roadmap

What's done, what's being built, and what comes next. Each phase ships as a
playable build. Numbers and content live in `data/*.json`.

| Phase | What | Status |
|---|---|---|
| 1 | Village, people, Appraisal (current vs. hidden potential) | Done |
| 2 | Noble society: the heir, retainers, offices, training, knighthood | Done |
| Art | Kit buildings, meadow, outfits, nature, props, sound | Done |
| 3.1 | Territory: stores, Build menu, construction sites, Master of Works | Done (on the preview build) |
| 3.2 | Growth: settlers, homes that build and upgrade themselves | Done (on the preview build) |
| **Eye** | **On foot: scan first, then talk and persuade** (below) | **In progress: gameplay video waiting for approval** |
| 3.3 | Charters: Hamlet → Village → Market Town → Town (raises the 110-person limit, unlocks taverns, chapels, markets) | Next |
| 4+ | Dynasties (ageing, marriage, children, succession), wider realm, military | Later |

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
   - **Ordinary:** a quick, quiet reveal. Plain frame, soft chime.
   - **Skilled:** a light sweep, a sharper bell, a silver frame and a few
     sparks.
   - **Exceptional:** gold and royal blue, a longer build-up, the camera
     moves closer, clues (their role, then the gift without its rank),
     layered bells, and a big stat reveal.
   - **Legendary:** the biggest sequence. The Eye's rune ring turns, a
     heartbeat plays, the person's silhouette appears, a motto, a fanfare
     sting, the most sparks, and the top skill lands last.
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
- [ ] **Approval of the gameplay video** before final polish
- [ ] Polish: per-tier timing, custom eye-opening art, richer particles,
      a dedicated sting for each tier, card portrait lighting
- [ ] Optional: idle "bark" lines villagers say aloud as you pass; rebinding
      keys
