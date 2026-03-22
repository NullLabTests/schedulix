#!/usr/bin/env bash
set -euo pipefail

# =====================================================================
# ALL-IN-ONE SCRIPT: Fix DB, Create/Migrate DB, Start Phoenix Server
# Run this from ANYWHERE - it will cd to ~/schedulix automatically
# =====================================================================

echo "============================================================="
echo "  schedulix Full Fix & Start Script                         "
echo "  - Fixes postgres password auth issue                      "
echo "  - Sets up DB (create + migrate)                           "
echo "  - Starts mix phx.server                                   "
echo "  - Works from anywhere (auto cd to ~/schedulix)            "
echo "============================================================="

PROJECT_DIR="$HOME/schedulix"

# 1. Check if project exists
if [[ ! -d "$PROJECT_DIR" ]]; then
  echo "ERROR: schedulix folder not found in $HOME"
  echo "       Make sure the project is in ~/schedulix"
  exit 1
fi

cd "$PROJECT_DIR" || { echo "Cannot cd to $PROJECT_DIR"; exit 1; }
echo "Working directory: $(pwd)"

# 2. Option: Trust local connections (no password needed) - recommended for dev
echo "→ Configuring PostgreSQL to trust local connections (no password)..."
PG_HBA="/etc/postgresql/$(ls /etc/postgresql)/main/pg_hba.conf"

if [[ ! -f "$PG_HBA" ]]; then
  echo "ERROR: pg_hba.conf not found. Check PostgreSQL installation."
  exit 1
fi

# Backup original
sudo cp "$PG_HBA" "${PG_HBA}.bak.$(date +%Y%m%d-%H%M%S)"

# Replace peer → trust for local connections
sudo sed -i 's/^\(local\s\+all\s\+all\s\+\)peer/\1trust/' "$PG_HBA"

# Restart PostgreSQL
echo "→ Restarting PostgreSQL..."
sudo systemctl restart postgresql

# Wait a few seconds
sleep 3

# 3. Update config/dev.exs - remove password requirement
echo "→ Updating config/dev.exs (removing password)..."
CONFIG_FILE="config/dev.exs"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "ERROR: config/dev.exs not found. Are you in the schedulix project?"
  exit 1
fi

# Comment out or remove password line if present
sed -i '/password:/ s/^/# /' "$CONFIG_FILE" || true

# Make sure username & database are correct
if ! grep -q "username: \"postgres\"" "$CONFIG_FILE"; then
  echo "→ Adding username to config..."
  sed -i '/Repo,/a \  username: "postgres",' "$CONFIG_FILE"
fi

# 4. Database setup
echo "→ Setting up database..."
mix ecto.drop   || echo "Drop skipped (db may not exist yet)"
mix ecto.create || { echo "Create failed - check logs"; exit 1; }
mix ecto.migrate || { echo "Migration failed - check logs"; exit 1; }

# 5. Optional: Install watchman for better Tailwind watching (silent fail OK)
echo "→ Installing watchman (optional - improves hot reload)..."
sudo apt install -y watchman 2>/dev/null || echo "watchman install skipped"

# 6. Start the server
echo ""
echo "===================================================="
echo "               Starting Phoenix Server              "
echo "===================================================="
echo ""
echo "Server will run at http://localhost:4000"
echo "Press Ctrl+C to stop"
echo ""

mix phx.server
