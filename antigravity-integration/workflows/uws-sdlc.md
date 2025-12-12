---
description: Manage the Software Development Life Cycle (SDLC)
---

# UWS SDLC Workflow

This workflow drives the project through a strict SDLC process with error handling.

**Arguments:**
- `action`: The action to perform (`start`, `next`, `status`, `fail`)
- `details`: Optional details or error message

```bash
# Delegate to core script
bash ./scripts/sdlc.sh "${1:-status}" "${2:-}"
```
