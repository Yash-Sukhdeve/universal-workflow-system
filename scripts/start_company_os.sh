#!/usr/bin/env bash
# Start Company OS development environment

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

echo "=========================================="
echo "       Company OS Development Setup"
echo "=========================================="

# Check for .env file
if [[ ! -f ".env" ]]; then
    echo "Creating .env file from .env.example..."
    cp .env.example .env
    echo "Please edit .env with your configuration"
fi

# Check Docker
if ! command -v docker &> /dev/null; then
    echo "ERROR: Docker not found. Please install Docker."
    exit 1
fi

if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
    echo "ERROR: Docker Compose not found. Please install Docker Compose."
    exit 1
fi

# Start services
echo ""
echo "Starting PostgreSQL and Redis..."
docker compose up -d postgres redis

echo ""
echo "Waiting for PostgreSQL to be ready..."
sleep 5

# Check if migrations ran
echo ""
echo "Checking database..."
docker compose exec postgres psql -U company_os -d company_os -c '\dt' 2>/dev/null || true

echo ""
echo "=========================================="
echo "          Services Running"
echo "=========================================="
echo ""
echo "PostgreSQL: localhost:5432"
echo "Redis:      localhost:6379"
echo ""
echo "To start the API server:"
echo "  Option 1 (Docker):  docker compose up api"
echo "  Option 2 (Local):   uvicorn company_os.api.main:app --reload"
echo ""
echo "API will be available at: http://localhost:8000"
echo "API docs at: http://localhost:8000/docs"
echo ""
echo "To stop services: docker compose down"
echo "=========================================="
