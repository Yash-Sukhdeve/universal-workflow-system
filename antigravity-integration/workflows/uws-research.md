---
description: Manage the Research Methodology Lifecycle
---

# UWS Research Workflow

This workflow manages the Research Methodology lifecycle, enabling scientific rigor.

**Arguments:**
- `action`: `start`, `next`, `status`, `reject` (hypothesis failed)

```bash
# Delegate to core script
bash ./scripts/research.sh "${1:-status}"
```
