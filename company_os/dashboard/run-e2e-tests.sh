#!/bin/bash

# Company OS Dashboard E2E Test Runner
# This script installs Playwright browsers if needed and runs all E2E tests

set -e

echo "================================================"
echo "Company OS Dashboard E2E Test Suite"
echo "================================================"
echo ""

# Check if servers are running
echo "Checking if servers are running..."
if ! curl -s http://localhost:8000/health > /dev/null 2>&1; then
    echo "ERROR: Backend server not running on port 8000"
    echo "Please start it with: cd .. && python -m uvicorn company_os.main:app --host 0.0.0.0 --port 8000"
    exit 1
fi

if ! curl -s http://localhost:5173 > /dev/null 2>&1; then
    echo "ERROR: Frontend dev server not running on port 5173"
    echo "Please start it with: npm run dev"
    exit 1
fi

echo "✓ Backend API running on http://localhost:8000"
echo "✓ Frontend running on http://localhost:5173"
echo ""

# Install Playwright browsers if not present
echo "Checking Playwright browsers..."
if ! npx playwright --version > /dev/null 2>&1; then
    echo "ERROR: Playwright not installed"
    exit 1
fi

# Try to install browsers (will skip if already installed)
echo "Installing/verifying Playwright browsers..."
npx playwright install chromium --with-deps || true

echo ""
echo "Running E2E tests..."
echo "================================================"
echo ""

# Run the tests
npm run test:e2e

echo ""
echo "================================================"
echo "Test run complete!"
echo "================================================"
echo ""
echo "To view the HTML report, run: npm run test:e2e:report"
echo ""
