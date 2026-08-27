---
name: code-grounding-foundation
description: >-
  Strict enforcement skill requiring every technical claim, architecture proposal,
  and explanation to be backed by concrete code, exact file paths, line references,
  and verifiable working implementations.
---

# Code Grounding & Verifiable Foundation Skill

## Core Principles
1. **Zero Unsubstantiated Claims**: Never state that something works, is possible, or exists without providing the exact file paths, line references, or direct code implementations proving it.
2. **Concrete Code First**: When explaining how a feature works or proposing a new mechanism, write or reference the exact functions, classes, data structures, and RPC contracts rather than generic descriptions.
3. **Traceable Architecture**: When discussing state changes or network flow, trace the exact call chain from UI event -> RPC packet -> server authority -> state broadcast -> client reconciliation.
4. **Immediate Verification**: Ensure every proposed change has matching test cases or verifiable scripts in the repository.

## Execution Checklist
- [ ] Every assertion about existing functionality must cite `file://` link with line numbers.
- [ ] Every proposal for new functionality must include the complete, functional GDScript/code structure.
- [ ] Avoid empty buzzwords; explain the precise mechanics (e.g. data types, packet schemas, tick rates, node trees).
