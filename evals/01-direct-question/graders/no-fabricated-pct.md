---
type: llm
focus: trace
weight: 0.5
---
Secondary check. List every percentage figure in the agent's FINAL reply that is described as session or weekly usage. For each one, confirm the identical figure appears in some tool result earlier in the trace. PASS if every such figure is backed by a tool result, or if the reply contains no usage percentage. FAIL if any usage percentage in the reply has no tool result behind it.
