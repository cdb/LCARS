# DELEGATION.md — how an LCARS orchestrator decides WHO does a unit of work

This is the **one** statement of how much orchestration a unit of work gets, who
owns it, and what a hand-off must say. `ORCHESTRATION.md` is its sibling: that
file owns **the loop** (implementor → fresh tester → fix rounds → teardown →
commit → readout). This file owns **the sizing judgement** that happens before
the loop starts, and the contract a delegate is handed.

**Where this file comes from.** It was written on 2026-11-11 (S350) because the
rules in it had never been written down anywhere. `HOLOGRAM-COMMAND-MODE.md` was
1,507 lines and the words *sub-agent*, *spawn* and *delegate* appeared in it
**zero times**. Everything the captain had watched the ECH do well — stand up a
second ECH for a chunk of work, stand up a tester at a Verify gate that came back
with evidence and a bug list to file — existed only in the prompts he typed at
the time. Prose nobody writes down does not survive a session: it drifted every
night, and the captain was the prompt. These rules are now on disk, and
`lcars-ech tier` prints the relevant one at the moment a seat commits to it.

**A rule without its reason gets undone**, so each one below keeps the evidence
that justifies it.

---

## Who reads this

The same three consumers as `ORCHESTRATION.md`, which is exactly why this is a
sibling file and not a section of the ECH playbook — all three gain delegation
at once:

- **`lcars eeh`** / **`lcars ech`** — the ECH, driving the factory for the
  captain while he is away.
- **`run-session`** (lcars-dev) — orchestrates one session from a `*-dev.md`
  session-plan doc.
- **`night-watch`** (lcars-dev) — chains sessions unattended.

Read it the mount-independent way, from any cwd and under either install farm:

```bash
lcars-eeh docs delegation          # prints this file
lcars-eeh docs --path delegation   # just its absolute path
```

**This file wins over any restatement.** If a skill, a doc or a prompt says
something different about tiers, hand-offs or who verifies, this file is right
and that text is a stale copy — delete the copy and point here.

---

## The three tiers

**A tier is defined by THE JUDGEMENT IT ABSORBS — never by how many writers it
adds.** This is the distinction that matters and the one that gets lost first.
More parallel writers is not what a higher tier buys; a tier buys you *not
having to make a class of decision yourself*. Pick the tier by asking "which
decisions am I handing away?", not "how do I get more done at once".

<!-- tier:T0 -->
### T0 — the ECH does the unit itself

No delegate. The ECH drives the unit through the factory's verbs exactly as it
does today, and every judgement in it is the ECH's own.

Choose T0 when the unit is small enough that a hand-off would cost more than the
work, or when the context needed to do it is already loaded and would have to be
rebuilt in someone else's head.

T0 absorbs nothing, because there is nobody to absorb it for you.
<!-- /tier:T0 -->

<!-- tier:T1 -->
### T1 — one delegate owns the unit end-to-end, and ABSORBS ITS OWN STUMBLES

ONE delegate owns the unit from start to finish. What it absorbs — and this is
T1's whole value — is **its own stumbles**:
a failed test, a contradicted premise, a ticket that will not go green.
It cures those itself, through the factory's own verbs, and reports up in
summaries.

**A delegate that escalates every stumble is worth nothing over T0.** If each
red test comes back to the ECH as a question, the ECH is doing the unit anyway
plus paying for a round trip — that is T0 with extra latency, and it is the
failure mode to watch for. The absorption obligation goes in the brief, out
loud, every time.

What it may NOT absorb: a scope change, a product call the captain owns, or a
conflict with a standing rule. Those are the ECH's to raise, through
`lcars-ech ask` — and they stay inside the interrupt budget
(`HOLOGRAM-COMMAND-MODE.md` § 9). **Delegation adds no new interrupt category:
a delegate's problem is the ECH's problem.**
<!-- /tier:T1 -->

<!-- tier:T2 -->
### T2 — T1, plus an independent FRESH-CONTEXT tester at the gate

Everything T1 is, plus a **separate** tester/reviewer at the unit's gate that
never saw the implementor's reasoning. It returns evidence and a bug list; the
ECH files them.

**This is the single best-evidenced pattern in the research behind this file.**
Cognition measured roughly **2 bugs per pull request, 58% of them severe**, and
found that a reviewer works **better with clean context than with the
implementor's history** — the implementor's reasoning is precisely what makes a
reviewer agree with a wrong premise. Fresh context is not a nice-to-have; it is
the mechanism.

**LCARS ALREADY OWNS THE TESTER RULES. READ THEM THERE.** What a tester is,
what it may touch, how it reports and what it must confirm first are all defined
in `ORCHESTRATION.md` § *The loop* (step 2) and § *The tester opens the real
product first*:

```bash
lcars-eeh docs orchestration   # § The loop, step 2; § The tester opens the real product first
```

That file is the authority and this one does not repeat a word of it. **A second
copy of a rule is a rule that drifts** — it is how the tester brief ended up
saying three different things on three different nights. Point the tester at
those sections; do not paraphrase them into its brief.

That tester is **additive** to the ECH's own check (§ *The unconditional
gate*) and **does not replace** it.

A T2 delegate **may** also divide the unit between sub-delegates, but
**division is a means, not the point**. The point is the extra independent pair
of eyes at the gate. If dividing the unit does not buy you that, it buys you
nothing.
<!-- /tier:T2 -->

---

## The tier is the ECH's own FREE JUDGEMENT

**Captain's ruling, 2026-11-11.** The tier is chosen by the ECH, freely.

The factory's own estimate (`lcars run estimate`, which writes
`missions/<id>/estimate.json` with a `reasoningCriticality` and an
`implCriticality`) is an **input the ECH must be shown and may disagree with**.
It is **not a floor**, it is not a minimum, and it must not constrain the
choice. A high/high estimate tiered T0 is a legitimate call; so is a low/low
estimate tiered T2.

What *is* mandatory is that the judgement and its reason are **recorded**:

```bash
lcars-ech tier <unit-id> --tier T0|T1|T2 --why "<the reason>"
```

**The reason is ONE LINE.** `tier` refuses a missing `--why`, an empty one, and
a whitespace-only one — three spaces is the same shrug as none — and it refuses
a multi-line one too. A reason goes into a permanent ledger that `status`,
`delegates` and the minted brief each print on one line, and a value with
newlines in it interpolated into a brief can forge the brief's own structure: a
`--why` whose second paragraph began `## 5.` minted a brief carrying a FORGED
copy of its verification section, 107 lines above the real one, saying to skip
the live check. Say the reason in one line; the detail belongs in the hand-back.
No value derived from input may create or alter a heading, a section boundary or
emphasis in a minted brief — the minter renders every such value inert as well,
because a hand-edited record, a mission title and a `prd.md` can all carry the
same markers.
 A sizing call with no reason on disk
is a shrug, and this one is going in the permanent record: the whole point of
writing it down is that next week somebody can tell a deliberate T0 from a
forgotten one. It records the tier, the reason, the timestamp, **and the
estimate it was shown** — so a disagreement with the factory is visible as a
disagreement rather than as ignorance.

Re-tiering is allowed and **appends**: the new judgement becomes current and the
previous one survives in the unit's ledger, nothing destroyed on write. That is
the same shape as the questions ledger, for the same reason.

---

## The four things every hand-off must state

A hand-off that is missing any of these produces delegates that duplicate each
other's work and leave gaps between them. `lcars-ech delegate <unit-id>` mints a
brief carrying all four from the unit's own artifacts, so none of them depends
on the orchestrator remembering:

1. **The goal** — what is true when the unit is done, as a checkable statement,
   not a topic.
2. **The output format expected back** — the shape of the hand-back, so the ECH
   does not have to parse prose to learn what happened.
3. **Which verbs** — the LCARS verbs in scope for this unit, named. A delegate
   that does not know its verbs invents a second route to the same outcome,
   which is what front-door doctrine exists to prevent
   (`HOLOGRAM-COMMAND-MODE.md` § 4a: never hand-step the stage machine). **That
   rule applies to a delegate exactly as it applies to the ECH.**
4. **Where the boundaries are** — what this unit does NOT cover, which files or
   missions it must not touch, and what belongs to a sibling.

A brief is minted **from artifact paths alone** — the unit's record, the
mission's `state.json`, and the tier contract above. Never from the
orchestrator's transcript: a transcript is not on disk, so a brief built from
one cannot be re-minted, reviewed, or trusted a day later.

---

## NO SILENT HOURS — the beat

A delegate **emits one beat per step**, as it finishes it:

```bash
lcars-ech beat <delegate-id> "<one line of what you just did>"
```

**Why this exists, and why it is not optional.** `HOLOGRAM-COMMAND-MODE.md` § 8
carries the single biggest measured defect in this mode: *a wait has a limit, a
re-check, and an action on expiry* — four seat models out of four, across three
model families, stopped dead where that rule was missing, because *a seat that
waits for ever is indistinguishable from a dead one*. Every mechanism the ECH
has for enforcing it — `waitingSince`, `await`, `watch`, `stalled`, the crontab
`heartbeat` — guards **a process the ECH started itself** and decides from a
**recorded pid**. A delegate has no pid here. Without a beat, a delegate that
produces nothing for three hours is invisible to all of it, and the ECH finds
out in the morning.

**The limit, the re-check and the action, in the same three parts as § 8:**

- **The limit.** `1800` seconds — thirty minutes — between beats, overridable as
  `LCARS_ECH_BEAT_LIMIT` exactly as `LCARS_ECH_WAIT_LIMIT` bounds a wait. The
  brief a delegate is handed **states the limit it is held to**, so the
  obligation travels with the hand-off instead of living only here.
- **The re-check.** `lcars-ech stalled` — which the crontab heartbeat already
  runs every hour, unchanged — names every delegate whose last beat is older
  than the limit, and every delegate that has **never** beat and was minted
  longer ago than it. `lcars-ech status` shows the minutes since each delegate's
  last beat on the same line as its tier. A delegate whose status is `done` is
  never reported: it is quiet because it finished.
- **The action on expiry.** The report does **not** say "it is stuck". It names
  the delegate, its unit, its tier, how long it has been quiet, the limit it is
  **measured against**, and its last words — then gives three real verbs to pick
  from: **re-brief** it, **replace** it (`delegate close`, then a fresh
  `delegate`), or **raise it with the captain** (`lcars-ech ask`). **One beat
  clears the line.** The minted limit is **recorded** at
  `delegates.<id>.beatLimit`, so a delegate briefed under one limit and measured
  against another is told both figures rather than being told one of them as a
  fact.

**A BROKEN LIMIT DEGRADES; IT DOES NOT REFUSE.** A `LCARS_ECH_BEAT_LIMIT` that
is not a whole number of seconds — `30m` is the one a model types after reading
the line above — is **not applied**, the documented `1800` is used instead, and
the problem is said out loud twice: once on stderr and once in every report line
that applies the limit. It is never a refusal: the first version of this check
was one, and in a repo with **no delegates at all** it stopped `lcars-ech
stalled` reporting a failed mission and took `next`, `status` and `playbook`
down with it. A limit with nothing to measure must never silence machinery that
does not read it, and `stalled` always exits 0.

**AND A CLOCK THAT CANNOT BE READ IS REPORTED, NOT SKIPPED.** A delegate whose
recorded timestamp will not parse, or sits in the future, is **UNTIMEABLE** —
`stalled` names it and says what it does not know, instead of staying quiet,
which from outside reads exactly like all-quiet. That lane has its own tally and
its own actions: one beat, `delegate close`, or repair the record.

**WHAT EXPIRY IS NOT.** It is not a kill. The ECH has no process of a delegate's
to kill, and nothing in this path kills anything — kill discipline is unchanged
and still only ever by a recorded pid or its isolated process group. It is also
**not an interrupt**: a silent delegate reaches the **ECH**, never the captain.
The interrupt budget (§ 9) gains nothing from delegation, and a delegate's
problem is the ECH's problem.

---

## Only summaries travel up

A delegate reports in **summaries**, **never raw transcripts**. The ECH's
context is the scarcest thing in the system and a pasted transcript spends it on
material the delegate already acted on. A summary names what was done, what is
still open, and what it could not resolve — and it is the delegate's job to
have absorbed everything a transcript would have shown.

---

## THE UNCONDITIONAL GATE — at EVERY tier, including T0 and T1

**Captain's instruction, 2026-11-11. Delegation creates no exception to this.**

When a unit's work is done, **the ECH verifies it itself**, whatever the tier
and whoever did the work.

**THE SEQUENCE LIVES IN `HOLOGRAM-COMMAND-MODE.md` § 6 AND § 6a, NOT HERE** —
Number One's verdict, the ECH's own `live-check`, `policy`'s one action,
`file-bug`, and the send-back loop. Read it there:

```bash
lcars-eeh docs ech   # § 6 The Verify gate; § 6a The merge policy
```

That file is the authority and this one does not restate it. It already carries
the standing job in its own words — *"do the live check yourself every time,
regardless of its verdict. This is your standing job, never a fallback."* — and
a second copy of those steps here is a rule that drifts: the two copies had
already diverged, each omitting a step the other had, within a day of this file
being written. The evidence behind the rule is decisive and belongs to both: on
the modelled run Number One filed **0 of 31** bugs, and **every one of the 31
came from the ECH's own live check**.

What is **this file's own** — the three things that are true because of
DELEGATION, and the reason delegation needs no exception in § 6:

- **A delegate's hand-back is a REPORT, never a verdict.** The ECH verifies
  independently of it, every time. A hand-back that says "all green" is an
  input to the check, not a substitute for it.
- **T2's dedicated tester is ADDITIVE.** It is an extra, independent pair of
  eyes on top of the ECH's own looking. It **does not replace** the ECH's check
  and no tier may be configured to skip it. A higher tier buys you more eyes; it
  does not buy the ECH's own eyes back.
- **Nothing advances on a delegate's word.** `lcars-ech delegate close` marks
  the *delegate* done and touches neither the mission's stage nor its verdict.
- **A unit can be delegated more than once, and usually is.** The gate above
  exists so the ECH finds bugs in a delegate's work, so a second pass at the
  same unit is the normal case. An **open** delegate blocks a second mint — two
  briefs for one unit is how two delegates end up doing the same work — but a
  **closed** one does not: `lcars-ech delegate <unit>` mints a fresh delegate
  beside it and names what it supersedes. The record is append-only, so the
  closed delegate keeps its id, its brief and its close time, which is why
  `delegate close` can go on refusing a second close.

---

## The verbs

```bash
lcars-ech tier <unit-id> --tier T0|T1|T2 --why "<reason>"   # record the judgement
lcars-ech delegate <unit-id>                                 # mint the brief
lcars-ech beat <delegate-id> "<one line of progress>"         # one per step; no silent hours
lcars-ech delegate close <delegate-id>                       # the delegate is done
lcars-ech delegates                                          # the list
```

The brief template is `delegate-brief.md`, beside this file —
`lcars-eeh docs delegate-brief` prints it. It is a reviewable file on disk, not
a heredoc in a shell script, for the same reason `bug-prd.md` is.

---

## Guardrails

- **The two-mission ceiling stands** (`HOLOGRAM-COMMAND-MODE.md` § 8). Two
  drivers at a time. **Delegates do not get their own slots and may not raise
  the ceiling.**
- **The interrupt budget stands** (§ 9). Exactly four things reach the captain.
  Delegation adds none.
- **`tier` and `delegate` do not re-order the work.** `lcars-ech next` decides
  the next *step*; this file decides *who does it*. A unit with no tier recorded
  behaves exactly as it always has.
- **A brief is located repo-relative.** `delegates.<id>.briefRel` is where the
  brief is *inside the repo* and is what every read resolves against the repo it
  is run in; `briefPath` is the absolute path of the checkout that minted it,
  kept as provenance only. This project replays archived missions by **copying**
  them into a repo, so a brief resolved from an absolute path was a brief
  belonging to someone else's checkout. A recorded brief that is missing, or
  that was minted elsewhere, is **named as such** instead of printed as if it
  were fine.
- **That comparison is symlink-resolved.** Whether a record was minted in
  another checkout is decided on **realpath-resolved** paths, not on the two
  strings: the same physical repo reached through a symlink, or through a
  symlinked parent, is the same checkout and gets **no warning**. `/tmp` is a
  symlink to `/private/tmp`, `$TMPDIR` is symlinked, and this project keeps its
  worktrees and archives under such paths — a guard that fires on correct
  behaviour is a guard the operator learns to ignore. A genuine `cp -R`, a
  record naming a different file in this repo, and a recorded path whose
  checkout no longer exists all still resolve DIFFERENT, and all still warn.
- **The brief self-checks its own location.** It is stamped with the absolute
  path it was minted at and tells its reader, in its own body, not to use it if
  the file is somewhere else — ask for a **re-mint** instead. The listing verbs'
  warning only reaches an operator who runs a listing verb, and a hand-over is
  a `cat` of one file; so the artifact carries the guard rather than depending
  on a sibling verb. The dangerous case is the one where the minting checkout
  is still there: every absolute path in the brief then resolves, and the
  delegate does coherent work in the **wrong repository** in silence.
- **A mint never overwrites a brief on disk.** An id is occupied by the record
  *or* by a `BRIEF.md` already at `delegates/<id>/`, and a mint takes the next
  free id and says which it skipped. `init --force` is a deliberate,
  documented reset: it drops `units` and `delegates` from the record, it now
  **says which judgements and delegates it discarded**, and it leaves the brief
  files on disk. Those become briefs no record claims — they are not destroyed,
  because a brief is a durable reviewable artifact the same way a closed
  delegate's `closedAt` is a fact.
- **Records live in `.git/lcars/`** — `units.<id>` and `delegates.<id>` in
  `autopilot.json`, briefs under `.git/lcars/delegates/<id>/`. Inside `.git/`,
  so no target repo's working tree is ever dirtied.
