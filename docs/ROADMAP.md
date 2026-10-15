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
| **Eye** | **Discovery through the Sovereign's Eye** (below) | **In progress: reveal tiers waiting for approval** |
| 3.3 | Charters: Hamlet → Village → Market Town → Town (raises the 110-person limit, unlocks taverns, chapels, markets) | Next |
| 4+ | Dynasties (ageing, marriage, children, succession), wider realm, military | Later |

## The Sovereign's Eye: discovering talent

**Goal:** finding exceptional people should feel like spotting a hidden gem
in a crowd, not reading a spreadsheet.

### Rules

1. **Nothing gives rarity away before the Eye.** Before you've talked to
   someone and used the Eye on them you see only public things: name, job,
   age, family, home, what they're doing, their traits and mood. No numbers,
   no rank badges, no glow, no overhead marker, no "exceptional" notices.
2. **Observation still matters.** Talk and gossip carry clues, but never
   proof. A gifted person's talk often turns to their gift. Braggarts
   oversell themselves, and humble or shy people undersell. Rumors attach to
   a few ordinary show-offs too.
3. **You have to go and talk first.** Choose "Go and talk", and your heir
   walks over through the village. You can also select your heir and
   right-click the ground to walk anywhere. The first conversation unlocks
   "Use the Sovereign's Eye" for that person.
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
7. **Actionable:** after the reveal you can recruit, appoint, follow,
   remember (marked in the ledger) or close.

### Build order

- [x] Talk-first flow: heir walks over, conversation with clues, Eye unlocks
- [x] Talent hidden everywhere until the Eye (card, court panel, ledger,
      mood and recruit wording, notices)
- [x] Reusable reveal system: `EyeReveal` plays step lists from
      `data/eye.json`. `EyeEmblem` draws the Eye; `RevealCard` is the card
- [x] Four distinct tiers, a quick repeat look, skip after seen
- [x] Reduce motion, reduce flashes and captions settings; tier never shown
      by color alone
- [x] Post-reveal choices (recruit, appoint, follow, remember, close)
- [ ] **Approval of the reveal video** before polishing every tier
- [ ] Polish: per-tier timing, custom eye-opening art, richer particles,
      a dedicated sting for each tier, card portrait lighting
- [ ] Optional: walk the heir with keys, idle "bark" lines villagers say aloud
      as you pass
