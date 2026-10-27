# bridge

## Comments name their area by keyword

A comment states its reason in one line and names the area by keyword; the detail lives in this file: search it for the keyword before changing the code.

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
* `package-check.yml`, `publish.yml` and `relock-pins.yml` in
  bats-lang/repository-prototype are called by commit, never `@main`:
  `check.yml` only calls `package-check.yml` (its `uses:` line, with the
  commit and a version comment), and the steps of the check are that shared
  workflow's, described in repository-prototype's CLAUDE.md ("A library's
  check.yml is a caller of package-check.yml"), not `check.yml`'s: the bats
  setup, `bats check`, `bats test`, the static tests, and for the dynamic
  tests valgrind, Node and `npm ci`.
* Node, which runs the dynamic tests, is the version in `.nvmrc`, read by
  `package-check.yml`.
* The runner image (`ubuntu-24.04`, not `ubuntu-latest`) and every action
  (by its commit, with its release in a comment) are pinned in
  `package-check.yml`, at the commit `check.yml` names, so they move with that
  commit.
* The bats setup action (`bats-lang/bats`, `.github/actions/setup`) is
  what sets up a bats job: it installs libgmp-dev and lld, builds bats
  from the checked-in `bootstrap/c` of the commit in `.github/bats-version`,
  installs ATS2 with `bats ats2 install`, clones the package repository
  at `.github/repository-version`, and sets the patsopt caps. Its ATS2 pin
  is bats's (`src/ats2.bats`): the GMP build's tarball, checked by its
  SHA-256 (`73c64f14...`) before it is unpacked, from a URL on the
  `master` branch of ats-lang.github.io, not a fixed commit, so the
  sha256 is what pins the tarball. The apt packages (libgmp-dev, lld) are
  unversioned: they are bounded by the pinned Ubuntu series (`ubuntu-24.04`
  is re-imaged about weekly), not pinned by version, because Ubuntu's
  archive drops superseded versions and an exact version would fail the
  day a security update lands.
* The dynamic tests' npm dependencies (jsdom, fake-indexeddb) are exact
  versions in `tests/dynamic/package.json`, and `tests/dynamic/package-lock.json`
  is committed: `package-check.yml` installs them with `npm ci`, never
  `npm install`. A dependency is changed by `npm install --package-lock-only`
  in `tests/dynamic`, in a pull request of its own.
* What the relock does not move is moved by Dependabot
  (`.github/dependabot.yml`): the commits of third-party actions this
  repository's own workflows use, with their release comments
  (`github-actions`; the check's actions are in `package-check.yml`, not
  here) and the npm versions and lock
  (`npm`, `tests/dynamic`), checked weekly, each release proposed once it is 7
  days old. All of its updates arrive in one pull request (owner ruling on
  quire#795, bridge#202, as quire#799, pwa#160 and capacitor-plugins#28):
  `.github/dependabot.yml` has one top-level `multi-ecosystem-groups` group,
  `dependencies`, holding `schedule: interval: weekly` and `patterns: ["*"]`;
  the `github-actions` and `npm` entries each join it with
  `multi-ecosystem-group: dependencies` and `patterns: ["*"]` and have no
  `schedule` of their own, since the group carries it; their cooldowns, ignores
  and directories are unchanged. A weekly run opens one pull request for both
  ecosystems and one `check` run, which runs the same CI and is reviewed.
  Documentation:
  https://docs.github.com/en/code-security/concepts/supply-chain-security/multi-ecosystem-updates
  The actions and the runner label of the check are in `package-check.yml`,
  moved in repository-prototype (the relock moves the commit `check.yml`
  names). Moved by hand, in a pull request of their own: the runner label
  (`ubuntu-24.04`) of bridge's own `review-gate.yml` and
  `review-gate-relay.yml`, when GitHub announces its successor, since
  Dependabot does not track a label and nothing else moves it. The ATS2
  tarball is not here: its pin is bats's, moved in bats.

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

## Every outcome is distinct, and the unexpected is said as such

(bats-lang/quire#334: a Google error that ended the consent screen
reached the app as the reader backing out, and the app said nothing
useful.)

* An atom answers each outcome its platform documents with a
  constructor of its own, decoded once from what JS gives (for
  google_authorize: `AuthorizeRefused` with a `google_status`,
  `AuthorizeCanceled`, `ConsentShowing`, `AuthorizeUnavailable`). One
  outcome is never folded into another.
* Anything the atom does not recognise is an explicit `...Unexpected`
  constructor carrying which case it was as a datatype (for
  google_authorize, `google_unexpected`), with the answer as JS wrote
  it. So is an answer the atom's types rule out (for google_authorize,
  the plugin's `INVALID_OPTIONS`).
* What a call cannot take is unrepresentable in the atom's type:
  google_authorize takes `google_scopes(t)` of at least one
  `google_scope`, each made only by `google_scope_of` (printable
  ASCII), and a token or an account as a `google_text` (printable
  ASCII), made by `google_text_of` or decoded from an answer; the
  scopes an answer grants are a `google_granted`, which no call takes.
* The atom's dynamic test passes through every constructor,
  `...Unexpected` included, with a stand-in for the platform. The app
  matches every answer with `case+` and handles each constructor
  visibly (quire's CLAUDE.md).

## An atom's JS only writes the answer down

How google_authorize takes a platform's answer (bats-lang/quire#334),
and the rule for an atom's answers:

* JS decides nothing. It looks the plugin up, reads the call's arguments
  and calls the method in one try; what came back, resolved or rejected,
  or what threw, it writes as text in a try of its own: `JSON.stringify`
  with a replacer that writes an Error as its own properties and its
  name and a BigInt as its digits; when that throws or gives nothing,
  `String` of it; when that throws too, its type; nothing for undefined.
  When the text cannot be kept, its type is kept instead, and when that
  cannot be either, nothing. The answer code says where the call was
  (resolved, rejected, which step threw, or a method that returned no
  promise) and how the text was written. The check that the plugin is
  there answers the same way when its lookup throws.
* Bats reads the text with the json package and decides there, with
  `case+`: each outcome the platform documents, and each case it does
  not recognise, which keeps the text (as UTF-8, as TextEncoder writes
  it: a lone surrogate, which only the String form can hold, becomes
  U+FFFD). A text over 1 MiB is kept as its whole length and its first 1
  MiB, whatever its form: a case of its own, or, with an answer code JS
  never gives, kept so by that case. An outcome that came with a text
  keeps it (for google_authorize, `Authorized` and `NotAuthorized` too),
  so a field the atom does not read is not dropped.
* A credential in a kept text (an access token) is kept; the app hides
  it where it shows the text.
* The atom's dynamic test plays the documented answers, a fixed list of
  nasty ones (values JSON has no form for, throwing getters and Proxy
  traps, cycles, huge and odd strings, thenables, answers at and just
  over the cap, a lookup, arguments and method that throw, a method that
  returns no promise, a text that cannot be kept), answers JS never
  gives, and a fuzz from a fixed seed, and checks that every call
  settles once with a known outcome, and every unexpected one keeps its
  text or is a case that has none. Where the output would hold the
  engine's own wording (a revoked Proxy's message), it names it instead.

## Platform (bats-lang/bridge#191, for quire#688)

`platform_read` (platform.bats) says the engine, the operating system and the app
shell a page runs in, and `platform_available` whether there is a `navigator`.
Primitives only: bridge reports, the app (quire) maps it to a look.

* **What JS writes down** (`batsJsPlatformFact`, one call for each fact, no
  decision): `navigator.userAgent`, `navigator.userAgentData.platform`,
  `navigator.platform`, `navigator.maxTouchPoints` (a number, written as its
  digits) and `Capacitor.getPlatform()`. Each is a `platform_fact`: its text,
  absent (undefined), a read that threw (what, as text), a value that is not a
  string (what, as text), or a code JS never gives. Bats decodes once, with
  `case+`, into `engine_reading` (Blink, WebKit, Gecko), `os_reading` (Android,
  Ios, IpadOs, MacOs, Windows, Linux, ChromeOs) and `shell_reading` (Browser,
  App of Ios or Android, WebView), each with an `...Unexpected` that keeps its
  source and the fact (`OsUnexpected` keeps all five facts that were read, and
  its source is where the answer came from: maxTouchPoints when the count is no
  count, else the last of navigator.platform, userAgentData.platform and the
  user agent that gave a text; every `platform_source` is made by some input). Tokens are searched in the first 2048 bytes of a text
  (a longer user agent with its token past that is Unexpected, with its whole
  text kept); the reading is linear (the facts hold blobs), freed by `case+ ~`
  or `platform_free`.
* **Reliability, by signal** (MDN's browser-detection guide; the UA-CH pages;
  Ionic, Framework7 and Flutter decide by operating system with an override,
  none by engine):
  * the user agent: present in every engine; tokens `Firefox/` (Gecko),
    `Chrome/` (Blink: Edge, Opera, Samsung and Android WebView carry it),
    `AppleWebKit/` without `Chrome/` (WebKit); `CriOS/`, `FxiOS/` and
    `EdgiOS/` are WebKit because every iOS browser draws with WebKit (Apple's
    rule; in the EU an alternative engine is possible since iOS 17.4, and its
    user agent decides then). Chrome's reduced user agent keeps the family
    (`Android`, `Windows NT`, `Macintosh`, `X11; Linux`, `CrOS`) and freezes
    the version. Spoofable, which is fine: we report what the platform says.
  * `navigator.userAgentData.platform`: Blink only (Firefox and Safari have no
    `userAgentData`), secure contexts only, experimental. Used as the second
    word for the system when the user agent names none.
  * `navigator.platform`: deprecated but present in every engine (`Win32`,
    `MacIntel`, `Linux x86_64`, `iPhone`); the third word.
  * `navigator.maxTouchPoints`: an iPad in its desktop mode sends a Macintosh
    user agent and `MacIntel`, and reports 5; a Mac reports 0. A Macintosh with
    more than one is `IpadOs`; none, one, or absent is `MacOs`; a value that is
    no count of at most 6 digits is `OsUnexpected` from `SourceTouchPoints`
    (not folded into a Mac).
  * `Capacitor.getPlatform()`: `ios`, `android` or `web` in a Capacitor app;
    reliable there, absent elsewhere. `window.webkit.messageHandlers` is not
    read: it exists only if the shell registers handlers, and Capacitor, which
    does, answers the same question through `getPlatform()`. `is_native_platform`
    (app.bats) is Capacitor's `isNativePlatform()` and only a bool, so it is
    not enough: this atom tells the system and a WebView apart.
  * a WebView without Capacitor: an Android WebView's user agent has `; wv)`;
    a WKWebView's has `AppleWebKit/` and no `Safari/` (Safari and the iOS
    browsers all carry `Safari/`). An app can set its user agent, then the page
    looks like a browser: that is what the platform says.
  * feature probes (CSS `@supports`, `window.chrome`, API presence): not used.
    They tell what an engine implements today, change with every release, and
    the Blink-with-WebKit-tokens spoof of an e2e test would defeat them; the
    tokens are the documented, stable signal.
* **X11 is not Linux**: only `Linux` names Linux. User agents of FreeBSD,
  OpenBSD and SunOS say `X11` and no `Linux`, so they are `OsUnexpected` (with the
  texts kept), never folded into `OsLinux`; `tests/dynamic/platform-read` plays them.
* **Two forms of the bridge (the overlap rule, bridge#253)**: the JS that carries
  the platform atom is larger than the old bound of `produce_bridge`,
  `produce_bridge_app` and `emit_js_all`, so those keep their old bounds and emit
  the bridge without the platform atom (deprecated, removal bridge#253), and
  `produce_bridge_platform`, `produce_bridge_app_platform` and
  `emit_js_all_platform` are beside them with the larger bounds. The emitters are
  shared (the platform section and its three imports are the only difference), so
  nothing is duplicated. An app that reads the platform generates its bridge with
  the platform forms (pwa's `create_pwa` still calls the old one; moving it is
  pwa's, in a pull request of its own). `tests/dynamic/old-bridge` calls the old
  forms and `tests/static/accept/produce-bridge-old-bound` their old bounds.
* **The desktop environment** (GNOME, KDE) is not readable from a page: no
  browser API reports it, the user agent says `X11; Linux` for all of them. So
  there is no field for it; an app that wants an Adwaita look needs a setting.
* **Testing each case**: Playwright's context options set `userAgent`,
  `isMobile` and `hasTouch` (device presets such as `iPhone 13` set all three);
  they do not set `navigator.platform` or `userAgentData`, which an
  `addInitScript` overrides. `tests/dynamic/platform-read` stands in for all five
  facts in jsdom and plays every constructor, the nasty facts (none, empty, not a
  string, a read that throws, a text over the 2048 read, a lone surrogate, a touch
  count that is no count) and the answers JS never gives.
* **Not decided here**: which look a platform gets (quire#688).

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

### Who reviews, and where

Only a comment by a trusted author counts: its `author_association` is
OWNER, MEMBER or COLLABORATOR. These repositories are public, so anyone
else's comment, approving or not, is ignored; the gate's log names each
review attempt's author and association, and the status says "No review
by a trusted author" with the associations it saw. The reviewer is
another agent or person than the one that wrote the change: all agents
here post from one account, so the review is done by a separate
reviewer agent, named on its `Reviewer:` line.

A review that approves is a comment in the pull request's conversation,
not a formal pull request review and not a line comment. A formal review
by a trusted author can only block:

* its text is read like a comment's (as rendered), ordered with the
  comments by when it was submitted, so a formal review that is the
  newest review attempt makes the gate pending, whatever it says (the
  agents post from the pull request author's account, so their formal
  reviews can only be "Comment" reviews);
* one that requests changes (GitHub's "Request changes") stands, as
  GitHub's own rule does, until it is dismissed, whatever comments
  follow.

### The review comment

The gate reads each comment (and each formal review's text) twice: as written, and as GitHub renders it
(`body_text`, GitHub's own plain text of the comment), so what it judges
is what a reader sees. A comment is a review attempt when one of the
first three non-blank lines of either says "adversarial review", read
loosely: NFKC, no zero-width characters, BOM, combining marks or CR,
lower case, entities, escapes, link targets and marks dropped, digits
read as the letters they look like, any non-ASCII letter standing for
any letter, and up to two letters wrong. The newest attempt decides,
alone; an older one never counts again. It approves only when it is
perfectly formed:

* written, its first line is exactly `## Adversarial review`, and shown,
  its first line is `Adversarial review`;
* written and shown, it has exactly one line with `Verdict:` in it (or
  starting with the word), and that line is exactly `Verdict: approved`
  (or `Verdict: changes needed`): no bold, no indent, no trailing space
  or period, no other words;
* written, it has exactly one line with `Reviewed:` in it (or starting
  with the word), and that line is exactly `Reviewed: <SHA>`, the full
  40-character lowercase SHA of the pull request's head commit it
  reviewed; shown, that line is the same, with the SHA as GitHub
  shortens it (7 digits) or in full;
* written, its letters are ASCII, and it has no invisible (format)
  characters, no combining marks, no code fence (three backticks or
  three tildes, anywhere), no HTML comment, no HTML tag (`<` followed by
  a letter or `/`) and no link or footnote definition (a line starting
  `[…]:`). Reviews use inline code and plain text only.

A verdict is never edited: an edited review counts as no approval, and a
new verdict is a new comment. Anything short of the form above is
pending, whatever it says; the status's description says what is wrong.
Other comments should not say "adversarial review" in their first three
lines: such a comment is an attempt, and as the newest it makes the gate
pending.

### The gate

`.github/workflows/review-gate.yml` sets the commit status
`adversarial-review` on the pull request's head commit (read from the
pull request, exactly 40 lowercase hex digits, three tries): success
only for a perfectly formed, unedited approval of the current head in
the newest attempt by a trusted author, with no standing request for
changes. Anything else is pending, and so is any failure (an API error,
a parse error, any unexpected exit), so an earlier success never
outlives a failed run. A push after an approval turns it back to
pending, until a new review names the new head.

It runs on every pull request event (`pull_request_target`), every
comment created, edited or deleted (`issue_comment`), every formal
review submitted, edited or dismissed (through
`.github/workflows/review-gate-relay.yml`, which has no permissions and
does nothing: `pull_request_review` would run the pull request's own
copy of a workflow, so the relay's completion runs the gate through
`workflow_run`), and over every open pull request about every 15
minutes, best effort (`schedule`). All of them run the gate as the
default branch has it, never as the pull request has it; it checks out nothing and runs no code
of the pull request, which is what makes that safe. The relay is only a
fast path; correctness rests on the schedule. It uses no action, only
the runner's `gh` and `python3`.

Known limits:

* Any workflow or token with `statuses: write` can post an
  `adversarial-review` status, so a pull request that adds or changes a
  file in `.github/workflows` could forge one. Such a pull request is a
  process change, and its review must check exactly this: that no
  workflow it adds or changes can post the status or widen its
  permissions to do so, and that the gate and its relay stay as they
  are.
* A commit status belongs to a commit, not to a pull request: two pull
  requests with the same head commit share one `adversarial-review`
  status, set by whichever ran last.
* A pull request can change or delete its own copy of the relay, and a
  fork's runs can wait for "Approve and run": a formal review's effect
  then waits for the next comment, push or scheduled run.
* The schedule is about every 15 minutes, best effort: GitHub delays
  scheduled runs under load and sometimes drops them, and turns a public
  repository's schedules off after 60 days without activity; they stay
  off until someone enables the workflow again (Actions → review-gate →
  Enable workflow). A scheduled run and an event's run are not in one
  concurrency group, so a scheduled run that read the comments just
  before a new review can post after that review's own run, until the
  next run.
* A review attempt is seen only by its first three non-blank lines, and
  only its one Verdict line is judged: a header further down, or prose
  that contradicts the exact approved line, is not caught. Each needs a
  careless or bad-faith review that still writes the exact approved
  line.
* If every lookup of the head fails on a comment event, nothing can be
  marked; the next scheduled run decides.
* The gate checks the comment's form and its author's association, not
  which agent or person wrote it: under one account, the authoring
  agent could post a perfectly formed approval itself; and a header misspelt by more than two
  letters is not seen as an attempt.
* Deleting the newest review makes the one before it the newest again.
  So does editing a formal review: the API gives a formal review no edit
  time, so an edit is not detected, and a trusted reviewer who edits a
  blocking formal review so that it is no longer a review attempt makes
  the older approval the newest again.
* Dismissing a "Request changes" review ends the standing request, but
  not the review attempt its text is: while it is the newest attempt,
  the gate stays pending, and a new review comment is still needed.
* Line comments on the diff are not read: a review posted only as a
  line comment does not block.
* An organization member whose membership is private may show as
  CONTRIBUTOR to the workflow's token, so their reviews do not count:
  the gate's log shows the association it saw. Make the membership
  public, or add them as a collaborator.

`adversarial-review` must be made a required status check of `main` by
a repository admin (Settings → Branches → the rule for `main` →
Require status checks to pass before merging → add
`adversarial-review`); until then the gate only reports. The pull
request template (`.github/pull_request_template.md`) asks the author
the same questions; the reviewer checks the answers, not just their
presence.
