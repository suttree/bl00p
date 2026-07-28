# Interactive agent questions

This guide describes the provider-neutral question flow used by Claude and
Codex runtimes. It is intended for contributors adding or changing a runtime
adapter.

## User experience

An agent question is rendered as an approval-style card in the conversation,
not as a free-form message. The card can contain:

- one prompt at a time from the provider's question batch;
- single-select or multi-select options, including option descriptions;
- an optional **Other** text answer; and
- **Continue** and **Decline** actions.

While a response is being sent, the card enters `submitting` and the composer
remains disabled. A successful answer marks the card as answered and advances
to the next prompt, if any. Declining marks the active prompt as cancelled.
Transport failures restore the pending state so the user can try again. The
question and its resolution state are persisted with the session, so a
restart can safely migrate an in-flight response to a cancelled state instead
of leaving the composer locked forever.

## Runtime contract

`AgentRuntime.resolveQuestion(entryID:answer:profile:)` is the single runtime
entry point for both answer and decline actions. `answer` is optional:

- a `QuestionAnswer` contains selected option IDs and optional custom text;
- `nil` means that the user declined the prompt.

The runtime emits `AgentEvent.questionResolved` with the entry ID, answer, and
`QuestionResolutionState`. `AppModel` uses that event to update the persisted
timeline card. `AgentRuntimeRouter` forwards the action to the provider that
owns the active session, preserving provider choice across reconnects.

Provider adapters must keep pending requests in a FIFO
`QuestionRequestQueue`. Only the first request is presented, while later
requests remain queued. Each prompt in a multi-question request gets a fresh
timeline entry ID; the provider request is answered only after every prompt has
been answered or the request is declined. `record` and `beginDecline` mark a
request as responding before awaiting transport, which prevents a double
submit for the same provider request ID. On transport failure, call
`resetResponse()` and emit a pending `questionResolved` event.

When a turn ends or a runtime stops, respond with a provider error to every
queued request that has not started responding. This prevents non-visible
requests from remaining blocked upstream.

## Provider mappings

### Claude

Claude's `control_request` with `subtype: can_use_tool` and
`tool_name: AskUserQuestion` becomes a question card. The adapter preserves the
whole original `input` object and merges the completed answers into its
`answers` field. Claude's control protocol expects each answer value as a
string, so multiple selected labels are joined with `", "`; custom text is
included as another display value. A decline returns `behavior: deny` with a
human-readable message.

The corresponding `tool_use` event upgrades the existing timeline entry when
the provider sends it in the normal tool-use order. Tool results must retain
the user-facing question card rather than exposing raw provider JSON in the
timeline.

### Codex

Codex's `item/tool/requestUserInput` request becomes a question card. Answers
are returned under the provider question IDs as `{ "answers": [...] }`, which
preserves multi-select values as an array. A decline is sent as a JSON-RPC
error response.

Both adapters skip malformed members of a question batch when valid members
remain. If no valid questions remain, they reject the provider request and add
an explanatory system entry so the turn can continue.

## Verification expectations

Changes to this flow should cover both the pure adapter behavior and the
runtime lifecycle. The relevant tests are in
`Tests/Bl00pTests/QuestionTests.swift` and include:

- single-select, multi-select, and custom answers;
- decline and transport-failure recovery;
- duplicate request protection and FIFO queueing;
- provider routing through `AgentRuntimeRouter`;
- persistence and restart migration; and
- a real Claude CLI control-protocol round trip that verifies preserved input
  metadata and the provider's string answer schema.
