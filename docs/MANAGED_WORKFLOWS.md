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

## Builder handoffs

Builder turns can finish as `blocked` when Claude reports one or more
non-fatal permission denials after the turn. This is a terminal status, not an
answerable question. Standalone chats still surface the blocked state as
needing attention, but managed workflows treat it like a completed Builder turn
for handoff preparation while keeping the normal readiness gate in charge.

The readiness gate must still require a handoff from the workflow repository,
a clean worktree, a local commit beyond the required base revision, and passing
test evidence. A ready blocked Builder handoff advances to the Reviewer
automatically. A blocked Builder turn without the required commit, clean tree,
or passing tests must pause with the existing `Builder handoff is not ready`
question card. `needsAnswer` remains reserved for real provider questions, such
as Codex `requestUserInput` events, and those still pause the workflow.

Workflow handoffs should carry the Manager's implementation plan when one was
approved, falling back to the original workflow request. This applies to both
automatic dispatch and the manual Hand off button. Generic fallback text such
as `No task context was captured.` must not be delivered to workflow
Reviewers.

## Approval state

While a Manager workflow is in the `planning` stage, the persisted workflow
stores the implementation plan and the ID of its approval timeline entry. The
session stores the corresponding pending approval card with the title
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

Run the complete suite with:

```sh
xcrun swift test --disable-sandbox
```
