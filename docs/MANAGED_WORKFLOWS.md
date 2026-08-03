# Managed workflow persistence

This note describes the persisted state that connects the Manager's plan
approval gate to the Builder handoff. It is intended for contributors changing
workflow restoration or the associated tests.

## Repository and participant sessions

`AgentSessionState.repositoryPath` is the persisted source of truth for a
chat's repository. `BotProfile.workingDirectory` and its legacy worktree field
exist only so older saved state can be migrated; runtime setup must not read or
mutate them as bot settings.

Starting a workflow snapshots the Manager session's repository in
`ManagerWorkflow.repositoryPath`. It also creates dedicated Builder, Reviewer,
and Documenter sessions and records their IDs in `participantSessionIDs`.
Those sessions all retain the same base repository:

- The Manager runs in the selected repository.
- The Builder creates and owns an isolated worktree from that repository.
- The Reviewer and Documenter run in the Builder handoff worktree while their
  persisted `repositoryPath` remains the workflow's base repository.

Participant creation must not select, reset, or mutate an existing standalone
chat. This is what allows two Manager chats to use the same configured profiles
for concurrent workflows in different repositories. Handoffs whose
`repositoryPath` differs from the workflow snapshot must be rejected or pause
the workflow before a recipient is launched.

On restoration, legacy session repositories are inferred in this order from
session worktree ownership, a pending handoff, and the former profile working
directory. Legacy workflows also recover their repository from saved handoffs,
the Manager session, participant sessions, or legacy profile data. Once a
workflow repository is known, its participant sessions are normalized to that
base repository.

Do not use a profile's selected chat to locate a workflow participant. Resolve
the Manager, Builder, Reviewer, and Documenter / PR Writer sessions from
`participantSessionIDs` on the workflow. This is required for concurrent
workflows: the same configured team profiles may have multiple dedicated
participant sessions active at once.

Repository changes are allowed only for an unstarted standalone chat. A chat
is considered locked once it has a runtime thread, an owned worktree, a pending
handoff, or workflow membership. Closing a chat may clean up its own worktree,
but must not unlock or change another chat's repository.

## Closing chats with managed worktrees

Closing a chat always deletes its local chat history. For a managed worktree,
`AppModel.closeAssessment` distinguishes the normal cleanup path from a
worktree that cannot be inspected safely:

- A clean or dirty worktree that can be assessed is removed from disk when the
  user confirms the close. Dirty worktrees are removed forcefully after the
  confirmation, while their Git branch is retained for recovery.
- If the worktree cannot be assessed or safely removed, the chat may be closed
  while the worktree remains on disk. Its Git branch is still retained, and the
  assessment detail is shown in the confirmation.

The confirmation copy is composed by the pure
`SessionCloseWarningMessage.make(for:)` helper in `ConversationView` so each
cleanup outcome stays explicit and regression-tested. Keep this message logic
in sync with `SessionCloseAssessment`: `hasManagedWorktree` controls whether
the normal deletion/branch-retention message is shown, while
`leavesWorktreeOnDisk` takes precedence for unsafe cleanup. Focused coverage is
in `SessionCloseWarningMessageTests`.

## Builder handoffs

Builder turns can finish as `blocked` when Claude reports one or more
non-fatal permission denials after the turn. This is a terminal status, not an
answerable question. Standalone chats still surface the blocked state as
needing attention, but managed workflows treat it like a completed Builder turn
for handoff preparation while keeping the normal readiness gate in charge.

The readiness gate must still require a handoff from the workflow repository,
a clean worktree, and a local commit beyond the required base revision — those
remain hard blockers regardless of why the turn ended. `needsAnswer` remains
reserved for real provider questions, such as Codex `requestUserInput` events,
and those still pause the workflow.

Test evidence is more nuanced. Genuinely failing tests are always a hard
blocker, on both the initial build and the revision pass. Missing or stale
test evidence is also a hard blocker on a normal (non-blocked) turn, on
either pass — the two passes are symmetric. But when the Builder turn ended
`blocked` and recorded an unresolved permission denial whose command matches
a known test runner (the same list `HandoffTestEvidence` uses to recognize a
test command), missing or stale test evidence instead advances the handoff to
the Reviewer carrying a caveat: `GitHandoffPackage.testStatus` is set to
`.unverified` and `testSummary` is rewritten to name the blocked action, so
the Reviewer sees "Tests: Unverified (blocked)" rather than a misleading "Not
run" or stale "Passed". The Reviewer is the quality backstop for this case,
not a second automatic test run. A denial unrelated to running tests (e.g. a
blocked `rm -rf build`) does not earn this leniency — it hard-blocks like any
other untested pass, since the denial gives no reason to believe the test
step itself was what got blocked. This denial lookup is scoped to entries
recorded since the current turn started (`turnEntryStartIndices`), so a stale
"Some actions were blocked" entry from an earlier, already-resolved turn is
never reused to justify a caveat on a later turn.

A blocked Builder turn without the required commit or clean tree, or with
genuinely failing tests, still pauses with the `Builder handoff is not ready`
question card. When the turn recorded a permission denial whose command
plausibly explains that specific failure (a `git commit`/`git add`-flavored
denial for a missing commit or dirty tree), the pause reason names the
blocked action (parsed from the recorded denial detail) and states that the
handoff will retry automatically, instead of the generic "finish the work and
commit" text. A denial that doesn't match the failure category (e.g. that
same blocked `rm -rf build` alongside a genuinely missing commit) is not
named as the cause — the pause reason falls back to the plain, un-annotated
text rather than misattributing the failure. `ManagerWorkflow.awaitingBuilderHandoffRetry`
is set whenever this gate hard-pauses a `building`/`revising` workflow; while
set, the workflow is re-evaluated (bypassing the normal "skip paused
workflows" rule) the next time its Builder session reaches `completed` or
`blocked`, so a resolved blocker advances the workflow without a manual
resume or an explicit new chat message. The flag is scoped to this pause
reason only — other pauses (`needsAnswer`, `needsApproval`, plan approval,
different-repository rejection) are unaffected and do not auto-advance.

There is exactly one readiness-gate implementation
(`AppModel.builderHandoffReadiness`), shared by the initial build and revision
passes and used from the same `validate` call on the live auto-advance path.

Workflow handoffs should carry the Manager's implementation plan when one was
approved, falling back to the original workflow request. Generic fallback text
such as `No task context was captured.` must not be delivered to workflow
Reviewers during automatic dispatch.

## Approval state

While a Manager workflow is in the `planning` stage, a Claude Manager may run
the test suite and read-only inspection commands to ground the plan it
produces. In Ask mode those commands still pause on an approval card; in Auto
mode supported commands are approved automatically by
`ClaudeToolApprovalPolicy.decision`. Managers still cannot edit files, commit,
push, or publish in either mode. `allowedTools(for:)` intentionally keeps
shell access out of the Manager's preapproved tool list so these requests keep
flowing through the runtime policy. Codex Managers remain read-only.

If a Claude Manager finishes the planning turn with non-empty plan text, any
permission denials from read-only inspection commands are treated as
non-blocking workflow noise rather than an actionable blocked state. This
keeps the produced plan on the normal approval path instead of replacing it
with a generic blocked pause. A planning turn with no non-empty assistant
response still pauses as incomplete, so missing plans are not silently treated
as approved-ready output.

The persisted workflow stores the implementation plan and the ID of its
approval timeline entry. The session stores the corresponding pending
approval card with the title
`Approve implementation plan`. The card is the user-facing source of truth for
the action; the workflow fields connect it back to orchestration state.

The Manager can be relaunched safely when the saved state is incomplete:

- A completed planning session can recover its latest assistant response as
  the plan and recreate the pending approval card.
- A session already waiting for approval can recover only from saved plan
  evidence: its referenced pending card, a matching saved plan, or another
  non-empty pending plan card.
- A missing or stale workflow ID can be adopted from a matching pending card.
  If multiple plan cards exist, the matching saved plan wins and the remaining
  duplicates are removed while the selected card keeps its timeline position.
- An unrelated runtime permission approval is never treated as a plan card.
  If no valid plan evidence remains, the session returns to `stopped`.

Restoration is idempotent. A second relaunch must not create another card,
change `updatedAt`, or write the state store when the saved approval is already
coherent. A declined plan remains resolved and does not become pending again;
the workflow stays paused so the Manager can receive revision feedback.

## Change guidance

Keep plan-card selection and mutation in the shared restore/write helpers in
`AppModel`. Restoration should distinguish completed planning sessions, where a
new approval may be reconstructed from the latest assistant response, from
sessions already marked `needsApproval`, where unrelated assistant or runtime
approval text must not fabricate a plan.

The model tests covering these invariants include:

- `legacyProfileSessionsMigrateIntoSelectedTabsWithTheirWorktree`
- `chatTabsKeepIndependentDraftsHistoriesAndRuntimeIdentities`
- `newChatsRequireARepositoryAndLockItAfterStarting`
- `builderWorktreesUseEachChatsRepository`
- `managedWorkflowsCreateDedicatedSessionsAndCanRunConcurrently`
- `workflowRejectsAHandoffFromAnotherRepository`
- `relaunchRecoversACompletedManagerPlanAndDispatchesBuilderOnce`
- `relaunchDoesNotTurnARuntimeApprovalIntoAPlanApproval`
- `relaunchAdoptsAPlanApprovalCardWhoseWorkflowIDWasNotSaved`
- `relaunchDoesNotRestoreIncompleteOrResolvedManagerPlans`
- `managerDenialsAreSuppressedWhenAPlanWasProduced`
- `managerDenialsArePreservedWhenNoPlanWasProduced`

The Builder handoff readiness gate is covered by:

- `blockedBuilderTurnWithReadyHandoffAdvancesWorkflowAutomatically`
- `blockedBuilderTurnWithUnverifiedTestsAdvancesWithACaveat`
- `blockedBuilderTurnWithUnrelatedDenialDoesNotEarnATestCaveat`
- `revisitedBuilderTurnDoesNotReuseAStaleBlockedActionFromAnEarlierTurn`
- `blockedBuilderTurnWithFailingTestsStillPauses`
- `blockedBuilderTurnWithoutCommitStillPausesWithAnActionableReason`
- `completedBuilderHandoffAutomaticallyRepairsAndAdvances`
- `completedBuilderHandoffStopsAfterBoundedAutomaticRepairs`
- `builderHandoffRepairStateSurvivesWorkflowPersistence`
- `invalidRevisedBuilderHandoffPausesBeforeDocumenterRuns`

When a test seeds a persisted workflow directly at stage `building` or
`revising`, it must also seed the Builder session with the already-delivered
visible handoff entry (`Implementation brief` on the initial pass). Restoration
always runs through the interrupted-dispatch recovery path, and a seeded
workflow that omits that evidence will be treated as an incomplete initial
dispatch rather than a ready-to-validate Builder handoff.

Likewise, helper runtimes used by handoff-focused tests should only settle the
role whose terminal state the test is asserting. Auto-completing the Reviewer
or Documenter turn can legitimately trigger the next workflow transition
(revision or publishing) and move the workflow past the state under test.

Run the complete suite with:

```sh
xcrun swift test --disable-sandbox
```

For the stalled-workflow watchdog coverage specifically, run the exact
watchdog tests by name rather than the broad `stalled` filter, which also
matches unrelated `installed...` tests:

```sh
xcrun swift test --disable-sandbox \
  --filter stalledBuilderResolvesViaBypassWhenBoundedRecoveryIsExhausted
xcrun swift test --disable-sandbox \
  --filter manualRetryRedispatchesAParticipantStillStuckAtWorking
xcrun swift test --disable-sandbox \
  --filter stalledReviewerBoundsAutomaticRecoveryAndPausesWithStallReason
xcrun swift test --disable-sandbox \
  --filter toolOutputEventsResetTheIdleWatchdog

xcrun swift test --disable-sandbox --no-parallel \
  --filter stalledBuilderResolvesViaBypassWhenBoundedRecoveryIsExhausted
xcrun swift test --disable-sandbox --no-parallel \
  --filter manualRetryRedispatchesAParticipantStillStuckAtWorking
xcrun swift test --disable-sandbox --no-parallel \
  --filter stalledReviewerBoundsAutomaticRecoveryAndPausesWithStallReason
xcrun swift test --disable-sandbox --no-parallel \
  --filter toolOutputEventsResetTheIdleWatchdog
```

## Managed worktree setup

`GitWorktreeManager` must treat repository worktrees as isolated automation
state, not as an interactive developer shell. Its internal git plumbing
commands therefore force `core.hooksPath=/dev/null` so repository hooks such
as `post-checkout` cannot break `worktree add`, cleanup, or status checks by
depending on tools that are absent from bl00p's launch environment.

This hook bypass is intentionally scoped to bl00p's own repository-management
commands. It does not change the environment inside a prepared worktree when a
Builder, Reviewer, or Documenter session later runs normal project commands.
Keep that distinction intact if worktree setup is refactored.
## Structured evidence and automatic repair

Builder-to-Reviewer handoffs require a new local commit, a clean worktree,
and a successfully completed relevant test command. Runtime command outcomes
are recorded structurally (`running`, `succeeded`, or `failed`) with a
completion time; timelines saved by older releases still use the legacy
command-title fallback. Read/search/tool output that merely mentions tests is
never treated as test evidence.

The gate recognizes common runners and project wrappers, including Swift,
Vitest, Jest, RSpec, package-manager wrappers, and compound commands. A
failed or running test command cannot be promoted by success-looking output.

When a normal Builder completion is recoverably incomplete, bl00p sends a
targeted repair instruction automatically. The instruction names the exact
failed readiness category (missing commit, dirty tree, failed tests, or missing
or stale test evidence) and asks the Builder to repair the existing worktree,
run the relevant tests, clean the tree, and commit locally. Repairs are
persisted before dispatch and bounded to two attempts per initial build or
revision pass, so relaunching cannot duplicate turns or create a loop. A
successful repair clears the counter and resumes normal handoff validation.
Once exhausted, the workflow pauses with the unmet requirement, retry count,
and latest evidence. A denied test action continues with an unverified caveat;
a denied commit action remains paused so the required approval can be
resolved, and permission-denial pauses do not consume automatic repair turns.

## Revision round capping and resumption

When the Reviewer detects issues that the Builder must fix, the workflow
enters a revision loop. The automatic revision loop is capped at
`maximumRevisionRounds = 2` consecutive `changesRequested` dispositions on
any single revision pass (initial build or post-repair revision). If the
Reviewer disposition is `changesRequested` on round `n` where
`n >= maximumRevisionRounds`, the workflow pauses with a question card
("Review loop needs attention") rather than dispatching another revision.

When the workflow is resumed after hitting this cap (via the Manager or
Reviewer sending an explicit message), `ManagerWorkflow.revisionLimitReached`
is used to signal that the revision budget should be reset. The reset is
scoped to this pause reason only—other pause reasons (`needsAnswer`,
`needsApproval`, plan approval, different-repository rejection,
`awaitingBuilderHandoffRetry`) do not touch `revisionRounds` or
`revisionLimitReached` on resume. After the reset, `revisionRounds` returns
to 0 and the automatic Builder ↔ Reviewer loop gets a fresh bounded budget
(up to 2 more rounds) before pausing again if issues remain.

The revision loop's bounded design prevents unbounded back-and-forth while
human oversight can direct scope or strategy shifts that automatic retries
cannot. A paused workflow does not automatically advance—it requires
explicit human direction via the Manager or the Reviewer's next message.

Tests covering the revision loop and resumption include:

- `managedWorkflowPausesAfterTwoUnresolvedRevisionRounds`
- `managedWorkflowResetsRevisionRoundsWhenResumingAfterLimitReached` — explicit send resume
- `managedWorkflowResetsRevisionRoundsOnRelaunchResumeAfterLimitReached` — app-relaunch resume

Negative coverage for unrelated pause reasons remains in the Builder handoff
repair tests above: those resumes must not reset `revisionRounds` or clear
`revisionLimitReached` unless the workflow had specifically paused because the
revision cap was reached.

## Turn supervision & stall recovery

`AppModel.handleWorkflowStatus` only advances or pauses a workflow in
response to a *status transition*. Without a backstop, a participant turn
that never reports a terminal status leaves the workflow silently wedged on
`working`/`launching` forever — the symptom is "the sub agent looks stuck and
the whole managed workflow stops progressing." Two mechanisms guarantee that
every participant turn in a non-completed workflow resolves into either an
advance/handoff or a visible, resumable pause — never a silent wedge.

**Stream-end reconciliation.** All three drain sites (the launch handshake,
the turn-response loop, and the shared `consume` lifecycle channel in
`AppModel`) route their natural stream-end through
`reconcileNonTerminalStreamEnd`. If the stream finishes while its generation
is still current and the session status is still `working`/`launching`, it
synthesizes `.status(.failed)` with a system entry ("Agent ended without
reporting a result") so the normal pause machinery in `handleWorkflowStatus`
always runs, and then attempts bounded recovery. This covers a runtime bug or
a disconnect where the transport closes without ever reporting a result.

**Idle watchdog.** A transport that stays open but stops emitting events (a
hung subprocess — the same class of bug fixed by the `git-subprocess-deadlock`
commits) never trips stream-end reconciliation, since the stream never ends.
`armIdleWatchdog` / `refreshIdleWatchdog` track a per-session idle deadline
(`AppModel.stallIdleDeadline`, four minutes by default, injectable for tests)
that resets on every event the drain loops process — including tool output —
so a long-running test suite is never mistaken for a hang. The watchdog is
scoped to workflow participants only (`containingManagerWorkflowID`);
standalone chats are unaffected. On expiry, `handleIdleWatchdogExpiry` pauses
the workflow with an actionable reason ("`<role>` appears stalled — no
activity for N min") and attempts bounded recovery.

The watchdog's test seam is `ManualIdleWatchdogGate` in
`Tests/Bl00pTests/ModelTests.swift`. Keep it order-independent: tests must be
able to request expiry before or after the next arm registers, and a cancelled
arm must not consume a pending expiry that belongs to its live successor.
Those tests intentionally drive expiry through the seam instead of waiting on
wall-clock deadlines so watchdog coverage stays deterministic in normal,
parallel, and release workflow runs.

**Bounded auto-recovery.** `attemptStallRecovery` stops the wedged runtime,
resets the stalled session out of `working`/`launching` (without routing
through `apply`/`handleWorkflowStatus`, since that would re-announce and
re-pause the workflow being recovered), and redispatches the same stage —
restoring the pending git handoff first if the stage needs one
(`restoreWorkflowHandoffIfNeeded`, shared with manual `resumeWorkflow`).
Recovery is bounded per stalled stage via
`ManagerWorkflow.stallRecoveryStage`/`stallRecoveryAttempts`: the counter
resets only when the workflow has genuinely moved to a different stage, not
merely because a redispatched turn reports `working` again, so retries cannot
loop indefinitely on one stuck stage. State is persisted before the redispatch
so a relaunch mid-recovery cannot duplicate a turn.

`ManagerWorkflow.awaitingStallRecovery` generalizes the existing
`awaitingBuilderHandoffRetry` bypass in `handleWorkflowStatus`: while set, a
stall-paused workflow is re-evaluated on the *next* terminal status from its
active participant, across every stage — not just `building`/`revising`
`completed`/`blocked`. This covers the case where bounded recovery could not
act (attempts exhausted, or the handoff could not be restored) but the
original turn was not actually dead and later reports its own real result;
that result still resolves the pause instead of requiring a manual retry.
The flag is cleared by `resumeWorkflowIndicator`, alongside
`awaitingBuilderHandoffRetry`, once the workflow shows real forward progress.

Manual recovery still works through the same shared redispatch path: sending
any message directly to the paused participant
(`resumeWorkflowsForExplicitSend`) or using the manager banner action clears
the pause before redispatching, independent of the automatic path. The banner
shows `Resume` for an app-restart recovery (`resumeAvailableAfterRestart`) and
`Retry` for a stalled participant (`awaitingStallRecovery`), matching the
user-visible intent in each case.

Runtime-level hardening (making `ClaudeRuntime`/`CodexAppServerRuntime`
`stop()` always emit a terminal status) was considered but deliberately
scoped out: both runtimes reuse the same continuation/generation across a
`start()`-triggered self-stop and an explicit relaunch, so an unconditional
terminal-status emission there risks racing a live drain loop into an
incorrect `stopped` status mid-relaunch. `AppModel`-level reconciliation and
the idle watchdog are the primary mechanism and already cover both runtimes
uniformly; revisit runtime-level emission only alongside a broader
continuation-lifecycle refactor.
