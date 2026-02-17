# UWS Examples

Step-by-step walkthroughs demonstrating UWS workflows.

## Available Examples

### [Python ML Research Project](python-ml-project/)

Demonstrates the **7-phase research workflow** (hypothesis through publication) with agent handoffs between researcher, experimenter, and documenter. Ideal for academic research, ML experiments, and data science projects.

### [Node.js Web Application](nodejs-webapp/)

Demonstrates the **6-phase SDLC workflow** (requirements through maintenance) with agent handoffs between architect, implementer, experimenter, and deployer. Ideal for web applications, APIs, and production software.

## Running the Demos

Each example includes a `walkthrough.sh` script that runs a fully automated demo in a temporary directory:

```bash
bash examples/python-ml-project/walkthrough.sh
bash examples/nodejs-webapp/walkthrough.sh
```

No cleanup needed — the temp directories are removed automatically.

## Using UWS in Your Own Project

```bash
# Option 1: With CLI installed
uws init [research|software|ml|llm|...]

# Option 2: Direct script
./scripts/init_workflow.sh [type]
```

See the main [README](../README.md) for full documentation.
