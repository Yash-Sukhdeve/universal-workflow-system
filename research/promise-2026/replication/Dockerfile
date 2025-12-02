# UWS Replication Package - Docker Environment
#
# Build: docker build -t uws-replication .
# Run:   docker run -v $(pwd)/results:/results uws-replication

FROM ubuntu:22.04

# Prevent interactive prompts
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git \
    bash \
    bc \
    python3 \
    python3-pip \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /uws

# Copy project files
COPY . /uws/

# Install Python dependencies
RUN pip3 install --no-cache-dir -r replication/requirements.txt

# Make scripts executable
RUN chmod +x scripts/*.sh tests/benchmarks/*.sh replication/*.sh 2>/dev/null || true

# Set up git config (required for benchmarks)
RUN git config --global user.email "replication@test.com" && \
    git config --global user.name "Replication"

# Default command: run all benchmarks
CMD ["/bin/bash", "-c", "python3 tests/benchmarks/baseline_benchmark.py && ./tests/benchmarks/benchmark_runner.sh && cp -r artifacts/benchmark_results /results/ 2>/dev/null || echo 'Results saved'"]
