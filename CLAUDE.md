# bridge

## CI is pinned

Every input to CI is pinned in the source (bats-lang/repository-prototype#269),
so a commit that passes keeps passing:

* `bats.lock` is committed: CI never runs `bats lock` for the package, so
  `bats check` and `bats build` fetch exactly the locked versions, and fail
  when the lock is missing or does not match `bats.toml`. A library's lock
  pins only its own CI and tests; its dependents still resolve their own.
* The compiler is the commit in `.github/bats-version`, read by every
  workflow that builds bats (and by the publish workflow).
* The package repository is fetched at the commit in
  `.github/repository-version`, so what the test packages under `tests/`
  lock (`bats lock --dev`) is pinned too.
* `publish.yml` and `relock-pins.yml` in bats-lang/repository-prototype are
  called by commit, never `@main`.

Pins move only through a reviewed pull request that runs the same CI. The
daily `relock.yml` (the shared `relock-pins.yml`) relocks against the
newest, moves the compiler and repository pins, pushes `relock/<date>`,
opens a pull request listing the old and new versions and dispatches
`check.yml` on it, so a breaking publish shows as a red relock pull
request and main stays green. GITHUB_TOKEN cannot change workflow files,
so without a `RELOCK_TOKEN` secret that pull request lists a workflow pin
that would move instead of moving it: move it in a pull request of its
own. A pull request that needs newer packages runs `bats lock
--repository <dir>` and commits `bats.lock` (and
`.github/repository-version`) with the change.

## Primitives only

bridge's JS offers generic DOM and platform primitives only; what to do
with them (which attributes, which roles, when) is the app's, in Bats.
A DOM primitive is an operation of the stream `dom_flush` applies,
addressed by element id like the others (CLONE_NODE copies an element
and nothing more: what the copy keeps is set by the app's own
operations on its id).

## Adversarial review before merge

No pull request merges before an adversarial review: a comment on the
pull request (its form is below), written by someone other than its
author (another agent or a person). The review first confirms the
pull request's kind from its diff, whatever the author called it.

* **A bug fix** (bridge deviates from its spec: what an atom or opcode
  is documented to do, or the platform API it wraps): the review
  confirms it really is a deviation from the spec, that the fix is
  minimal, and that no capability slipped in: a "fix" that adds or
  widens an atom or opcode, or puts policy in bridge, is reviewed as a
  new capability.
* **A new capability** (an atom or an opcode): the review answers, with
  evidence (code, measurements, the platform API's documentation):
  1. Is there no way to do this with what exists, at reasonable
     performance?
  2. Is this the minimal wrapper? Does it map 1:1 to the platform API?
     Why can it not be broken into smaller atoms? (Always asked; in
     detail when it is not 1:1.)
  3. Does it write to the DOM? Then it must be an opcode of the diff
     stream `dom_flush` applies: writes batch in the stream, in order,
     and a separate call is an extra JS crossing outside the batch's
     order.

  The review analyzes the plausible alternatives and says why each
  would not work. For a DOM clone, say: rebuilding the copy with
  CREATE_ELEMENT per node would be expensive, and a separate JS call
  (`copy_node`) crosses outside the batch, so it is CLONE_NODE in the
  stream.
* **Process, documentation or CI** changes: the review confirms they add
  no capability.

App policy (which attributes, roles, defaults, when) never lives in
bridge's JS: it is the app's, in Bats (bats-lang/pwa#49). A pull request
that puts policy in bridge gets `Verdict: changes needed`.

### The review comment

The newest comment whose first line is `## Adversarial review` decides,
alone; an older one never counts again. Outside fenced code blocks, it
holds exactly one line that starts (past any markdown marks) with the
word Verdict, and exactly one that starts with Reviewed:

* `Verdict: approved` or `Verdict: changes needed`, exactly: no bold, no
  trailing period, no other words;
* `Reviewed: <SHA>`, the full 40-character lowercase SHA of the pull
  request's head commit it reviewed.

A verdict is never edited: an edited review counts as no approval, and a
new verdict is a new comment.

### The gate

`.github/workflows/review-gate.yml` sets the commit status
`adversarial-review` on the pull request's head commit, on every pull
request event and every comment created, edited or deleted. It is
success only when the newest review is unedited, its one verdict line is
`Verdict: approved` and its one Reviewed line names the current head;
anything else is pending. A push after an approval turns it back to
pending, until a new review names the new head.

It runs on `pull_request_target`, so the gate that runs is the base
branch's file, not the pull request's; it checks out nothing and runs no
code of the pull request, which is what makes that safe.

Known limits:

* Any workflow or token with `statuses: write` can post an
  `adversarial-review` status, so a pull request that adds or changes a
  file in `.github/workflows` could forge one. Such a pull request is a
  process change, and its review must check exactly this: that no
  workflow it adds or changes can post the status or widen its
  permissions to do so.
* The gate checks the comment's form, not who wrote it: agents here post
  under one account, so the review names its reviewer, and the reviewer
  is never the author.
* Deleting the newest review makes the one before it the newest again.

`adversarial-review` must be made a required status check of `main` by
a repository admin (Settings → Branches → the rule for `main` →
Require status checks to pass before merging → add
`adversarial-review`); until then the gate only reports. The pull
request template (`.github/pull_request_template.md`) asks the author
the same questions; the reviewer checks the answers, not just their
presence.
