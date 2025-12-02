# Framework Comparison Results

**Note**: Results marked with * are SIMULATED based on documented framework behavior.

## Overall Performance

| Framework | Success Rate | Mean Time (ms) | Mean Completeness | Simulated? |
|-----------|-------------|----------------|-------------------|------------|
| AutoGen | 46.7% | 126.71 | 25.5% | Yes* |
| CrewAI | 53.3% | 63.03 | 29.1% | Yes* |
| LangGraph | 66.7% | 13.43 | 36.4% | Yes* |
| UWS | 100.0% | 0.04 | 11.9% | No |

## Performance by Corruption Level

| Framework | Corruption | Success Rate | Time (ms) | Completeness |
|-----------|------------|-------------|-----------|--------------|
| AutoGen | 0% | 33% | 119.1 +/- 60.8 | 18.2% |
| AutoGen | 10% | 67% | 135.1 +/- 68.3 | 36.4% |
| AutoGen | 30% | 33% | 110.4 +/- 52.0 | 18.2% |
| AutoGen | 50% | 67% | 128.1 +/- 39.7 | 36.4% |
| AutoGen | 90% | 33% | 140.8 +/- 52.5 | 18.2% |
| CrewAI | 0% | 33% | 54.1 +/- 26.4 | 18.2% |
| CrewAI | 10% | 67% | 40.5 +/- 9.4 | 36.4% |
| CrewAI | 30% | 67% | 77.2 +/- 21.0 | 36.4% |
| CrewAI | 50% | 33% | 73.5 +/- 9.0 | 18.2% |
| CrewAI | 90% | 67% | 69.8 +/- 14.6 | 36.4% |
| LangGraph | 0% | 67% | 10.0 +/- 5.1 | 36.4% |
| LangGraph | 10% | 100% | 14.2 +/- 5.1 | 54.5% |
| LangGraph | 30% | 33% | 15.8 +/- 3.4 | 18.2% |
| LangGraph | 50% | 100% | 12.5 +/- 5.8 | 54.5% |
| LangGraph | 90% | 33% | 14.7 +/- 3.0 | 18.2% |
| UWS | 0% | 100% | 0.0 +/- 0.0 | 59.6% |
| UWS | 10% | 100% | 0.0 +/- 0.0 | 0.0% |
| UWS | 30% | 100% | 0.0 +/- 0.0 | 0.0% |
| UWS | 50% | 100% | 0.0 +/- 0.0 | 0.0% |
| UWS | 90% | 100% | 0.0 +/- 0.0 | 0.0% |