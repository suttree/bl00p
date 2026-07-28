# Managed workflow persistence

This note describes the persisted state that connects the Manager's plan
approval gate to the Builder handoff. It is intended for contributors changing
workflow restoration or the associated tests.

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

- `relaunchRecoversACompletedManagerPlanAndDispatchesBuilderOnce`
- `relaunchDoesNotTurnARuntimeApprovalIntoAPlanApproval`
- `relaunchAdoptsAPlanApprovalCardWhoseWorkflowIDWasNotSaved`
- `relaunchDoesNotRestoreIncompleteOrResolvedManagerPlans`

Run the complete suite with:

```sh
xcrun swift test --disable-sandbox
```
