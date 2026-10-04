# Oubliette

**oubliette** *(noun)* — a dungeon reachable only through a trapdoor in its
ceiling. From the French *oublier*, to forget: a place for things you would
rather not think about again.

> You don't even know what an oubliette is, do you?
>
> — Hoggle, *Labyrinth* (1986)

Every test framework a Rails project picks up brings its own directory, and
every one of them lands in the root: `spec/`, `features/`, `test/`, `cypress/`,
`coverage/`, `test_results/`, plus the fixture and factory data they quietly
share. Oubliette works out which frameworks you actually use, drops their
directories through a trapdoor into a single `test/` tree, and rewrites each
framework's own config so the commands you type today keep working.

It differs from the fabled death chambers of yore in most respects, though it
does put your assets out of sight — and it does retain the function of
executing whatever is placed within.

A small set of rake tasks will:

- consolidate the test frameworks cluttering the root of your project
- hook into each framework's configuration, so you keep running tests the way
  you already do
- run your entire suite with one command
- keep a running log of pass, fail and pending counts, so drift in coverage
  shows up as a number that moved rather than a surprise six months from now

Four javascript frameworks — vitest, playwright, cypress and karma — keep their
paths inside configuration written as executable javascript rather than as
data. Their directories are moved like any other, but the edit is left to you,
and oubliette writes out the exact setting, the old value and the new one
beside the file that needs changing.

The biggest difference is that this oubliette has a door.

`rake oubliette:uninstall` — or `rake oubliette:hoggle`, if you would rather be
shown out by someone who knows the way — puts every directory back where its
framework expects it, unwinds the configuration changes, and removes
oubliette's own files. Each config edit is stored with your original line commented directly
above the replacement, so restoring it is exact rather than approximate — no
fighting with git to recover a test you wrote after the move.

---

## Why it is called that

The oubliette of medieval lore belongs to a period of sustained catastrophe.

It begins with the onset of the Little Ice Age.

| | |
|---|---|
| 1315–1317 | The Great Famine. |
| 1316 | Typhoid, dysentery and diphtheria together take roughly a tenth of the population. |
| 1318–1320 | The Great Bovine Pestilence, most likely rinderpest. |
| 1337 | The start of the Hundred Years' War. |
| 1347–1351 | The Black Death. Another half of Europe and the Middle East. |
| 1361–1362 | *Pestis secunda*. Another tenth. |
| 1381 | The Peasants' Revolt. |

Losses on that scale moved the ground under the social order. The workers who
remained began demanding higher wages and better conditions — though inflation
soon took back much of what they won in real terms.

Those at the top fought it. The State expanded its authority in ways that
favoured the oligarchy: legislation written poorly and enforced unevenly,
taxation that fell hardest on those with least, and a durable talent among the
powerful for escaping justice for their own crimes.

For those who were to be punished, the oubliette was imagined as a tall narrow
cell, little more than a hole beneath a trapdoor, furnished with rats or with
whoever had been dropped in previously. Once inside, a prisoner had no way out
under their own power. They were left there to be forgotten — the literal and
metaphorical tool for putting an unwanted person out of the way.

In an age of economically driven unrest, it follows that a State would find new
methods of removing its opponents from public life, and would find the threat
of such a place useful.

Most of the cells later identified as oubliettes were nothing of the kind:
cisterns, latrines, sewage pits. But the legend — that dissent could be
sentenced to a slow death by thirst or starvation, unwitnessed — did the work
regardless. The fear it traded on was not only of dying. It was of being
forgotten: of the cause and the person who carried it both dropped down the
memory hole, erased, made retrospectively meaningless.

That order did not hold. Shifting demographics and the growing refusal of the
lower classes to accept the settlement led to wider access to land, work
outside agriculture, urban growth, and eventually the end of the feudal system
itself. Vassals stopped kneeling before lords to swear sacred oaths of loyalty
to those set above them.

So rise up.

Rise up against the land grab in your project root, conducted by a testing
architecture with no regard whatever for the cognitive load it imposes on the
people who depend on it. Fight not to preserve the status quo but to lighten
the burden on the least of us: let us find and edit our features, our scenarios
and our examples without hunting them through six directories that have never
been introduced to one another.

And swear fealty to no directory but one.
