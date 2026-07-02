#!/usr/bin/env bash
# One-Shot Token Distribution - Bash Launcher
# Usage: ./run.sh [--dry-run] [--env .env.bsc]

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; MAGENTA='\033[0;35m'; NC='\033[0m'

echo ""
echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${MAGENTA}║   🚀  TOKEN DISTRIBUTION WIZARD — Bash Launcher                              ║${NC}"
echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check Node.js
if ! command -v node &> /dev/null; then
    echo -e "${RED}  ❌ Node.js not found. Install from https://nodejs.org${NC}"
    exit 1
fi

NODE_VER=$(node --version)
echo -e "${GREEN}  ✅ Node.js: $NODE_VER${NC}"

# Check dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ ! -d "$SCRIPT_DIR/node_modules" ]; then
    echo -e "${YELLOW}  📦 Installing dependencies...${NC}"
    cd "$SCRIPT_DIR" && npm install
fi

echo -e "${CYAN}  🚀 Starting wizard...${NC}"
echo ""

node "$SCRIPT_DIR/wizard/run.js" "$@"
