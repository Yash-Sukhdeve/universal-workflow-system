# Framework Comparison Design Document

**Purpose**: Establish fair methodology for comparing UWS against existing agentic frameworks
**Date**: 2025-12-01
**Following**: R1 (Truthfulness), R5 (Reproducibility)

---

## 1. Frameworks Under Evaluation

| Framework | Version | State Persistence | Recovery Mechanism |
|-----------|---------|-------------------|-------------------|
| UWS | 2.0 | YAML + checkpoints | recover_context.sh |
| LangGraph | 0.0.x | StateGraph | Checkpointer interface |
| AutoGen | 0.2.x | JSON messages | ConversableAgent state |
| CrewAI | 0.x | Agent memory | Task context |

---

## 2. Canonical Task Definition

To ensure fair comparison, all frameworks execute the **same logical workflow**:

### Task: Multi-Step Code Review Pipeline

```
Phase 1: Context Loading (read files, parse structure)
Phase 2: Analysis (identify issues, compute metrics)
Phase 3: Synthesis (generate report, prioritize findings)
Phase 4: Validation (verify recommendations)
```

**Why this task?**
- Representative of real AI-assisted development workflows
- Requires state accumulation across phases
- Meaningful intermediate states worth preserving
- Can be interrupted at any phase boundary

---

## 3. State Artifact Isolation

Each framework must persist state to **isolated files** for corruption testing:

| Framework | State Location | Format |
|-----------|----------------|--------|
| UWS | `.workflow/state.yaml` | YAML |
| LangGraph | `.langgraph/state.json` | JSON |
| AutoGen | `.autogen/messages.json` | JSON |
| CrewAI | `.crewai/context.json` | JSON |

**Isolation Requirements**:
- Each framework runs in separate directory
- State files are the ONLY persistence mechanism
- No in-memory caching across sessions

---

## 4. Corruption Methodology

Apply **identical corruption logic** to all frameworks:

```python
def corrupt_state_file(filepath: str, corruption_level: float) -> None:
    """
    Apply byte-level corruption to state file.

    Args:
        filepath: Path to state artifact
        corruption_level: Fraction of bytes to corrupt (0.0 - 1.0)
    """
    with open(filepath, 'rb') as f:
        data = bytearray(f.read())

    num_bytes_to_corrupt = int(len(data) * corruption_level)
    positions = random.sample(range(len(data)), num_bytes_to_corrupt)

    for pos in positions:
        data[pos] = random.randint(0, 255)

    with open(filepath, 'wb') as f:
        f.write(data)
```

### Corruption Levels
- 0%: No corruption (baseline)
- 10%: Light corruption (typos, minor damage)
- 30%: Moderate corruption (partial file damage)
- 50%: Heavy corruption (significant data loss)
- 90%: Catastrophic corruption (near-total destruction)

---

## 5. Outcome Metrics

All frameworks measured on **identical metrics**:

### Primary Metrics
| Metric | Definition | Measurement |
|--------|------------|-------------|
| Recovery Success | Binary: Did recovery complete without error? | Exit code = 0 |
| Recovery Time | Milliseconds from start to completion | Wall clock time |
| State Completeness | Percentage of original state recovered | Semantic comparison |

### Secondary Metrics
| Metric | Definition |
|--------|------------|
| Phase Restoration | Which phases have valid state? |
| Data Integrity | Are recovered values correct? |
| Graceful Degradation | Partial recovery vs total failure? |

---

## 6. Experimental Protocol

### Setup Phase
1. Initialize each framework with canonical task
2. Execute workflow to Phase 3 completion
3. Create reference state snapshot (ground truth)

### Corruption Phase
4. Copy state to corruption directory
5. Apply corruption at specified level
6. Record corruption metadata

### Recovery Phase
7. Invoke framework's recovery mechanism
8. Measure recovery time
9. Compare recovered state to ground truth
10. Compute completeness score

### Repetition
- 3 trials per (framework, corruption_level) pair
- 5 corruption levels × 4 frameworks × 3 trials = 60 experiments

---

## 7. Framework Adapters

Each framework requires an adapter implementing:

```python
class FrameworkAdapter(ABC):
    @abstractmethod
    def initialize(self, task_config: dict) -> None:
        """Set up framework for canonical task."""
        pass

    @abstractmethod
    def execute_to_phase(self, phase: int) -> dict:
        """Execute workflow to specified phase, return state."""
        pass

    @abstractmethod
    def get_state_filepath(self) -> str:
        """Return path to primary state artifact."""
        pass

    @abstractmethod
    def recover(self) -> tuple[bool, float, dict]:
        """
        Attempt recovery from current state.
        Returns: (success, time_ms, recovered_state)
        """
        pass

    @abstractmethod
    def compute_completeness(self, original: dict, recovered: dict) -> float:
        """Compute semantic similarity between states (0-100%)."""
        pass
```

---

## 8. What We Can Fairly Claim

### Valid Claims (if supported by data)
- "UWS achieves X% recovery success at Y% corruption, compared to Z% for Framework A"
- "UWS recovery time scales as O(f(corruption)) while Framework B scales as O(g(corruption))"
- "UWS provides explicit checkpointing while Framework C relies on implicit state"

### Invalid Claims (avoid)
- "UWS is better than X" (subjective without context)
- "UWS is state-of-the-art" (requires broader validation)
- "Other frameworks fail" (without specifying conditions)

---

## 9. Threats to Validity

### Construct Validity
- Canonical task may not represent all workflows
- Byte-level corruption may not match real failure modes
- Completeness metric is framework-specific

### Internal Validity
- Implementation quality varies across adapters
- We may not be using frameworks optimally
- UWS has "home advantage" in test design

### External Validity
- Results may not generalize to other tasks
- Real-world corruption patterns differ from synthetic
- Single-user scenario (no concurrent access)

### Mitigation
- Document all adapter implementations
- Provide replication package with all code
- Acknowledge limitations explicitly in paper

---

## 10. Expected Outcomes

### Hypothesis H1: Explicit Checkpointing Helps
Frameworks with explicit checkpointing (UWS) should show:
- Higher recovery success at moderate corruption
- More predictable recovery times
- Better graceful degradation

### Hypothesis H2: Structured State Helps
Frameworks with structured state (YAML/JSON schemas) should show:
- Better completeness detection
- Easier partial recovery
- More informative failure modes

### Null Hypothesis H0
All frameworks perform comparably under controlled corruption.
If H0 holds, UWS's contribution is the **benchmark methodology**, not the framework itself.

---

## 11. Implementation Priority

1. **UWS Adapter**: Already have (recover_context.sh)
2. **LangGraph Adapter**: High priority (widely used)
3. **AutoGen Adapter**: Medium priority (Microsoft backing)
4. **CrewAI Adapter**: Lower priority (simpler state model)

---

**Status**: Design complete. Ready for implementation.
