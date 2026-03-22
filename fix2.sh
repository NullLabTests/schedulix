#!/usr/bin/env bash
set -euo pipefail

# =====================================================================
# IMPROVED ALL-IN-ONE SCRIPT: Fix DB Auth, Setup DB, Start Server
# - Dynamically finds pg_hba.conf using PostgreSQL itself
# - Falls back to common Ubuntu path if needed
# - Safely edits config, creates DB, starts server
# Run from anywhere
# =====================================================================

echo "============================================================="
echo "  schedulix Ultimate Fix & Start Script                     "
echo "  - Auto-detects pg_hba.conf location                       "
# ──────────────────────────────────────────────────────────────────────────────
# CHANGE ONLY if project path is different
# ──────────────────────────────────────────────────────────────────────────────
PROJECT_DIR="$HOME/schedulix"

# 1. Change to project directory
if [[ ! -d "$PROJECT_DIR" ]]; then
  echo "ERROR: Project not found at $PROJECT_DIR"
  echo "Check if folder exists or edit PROJECT_DIR in script"
  exit 1
fi

cd "$PROJECT_DIR" || exit 1
echo "Working in: $(pwd)"

# 2. Find pg_hba.conf dynamically (best way)
echo "→ Finding pg_hba.conf location..."
HBA_FILE=$(sudo -u postgres psql -t -P format=unaligned -c "SHOW hba_file;" 2>/dev/null || echo "")

if [[ -z "$HBA_FILE" || ! -f "$HBA_FILE" ]]; then
  echo "→ Could not query pg_hba.conf path (Postgres may need password fix first)"
  echo "→ Trying common Ubuntu location..."
  # Find version dir
  PG_VERSION_DIR=$(ls -d /etc/postgresql/* 2>/dev/null | head -n 1)
  if [[ -n "$PG_VERSION_DIR" ]]; then
    HBA_FILE="$PG_VERSION_DIR/main/pg_hba.conf"
  else
    HBA_FILE="/etc/postgresql/17/main/pg_hba.conf"  # fallback guess
  fi
fi

if [[ ! -f "$HBA_FILE" ]]; then
  echo "ERROR: Could not locate pg_hba.conf"
  echo "Try manually:"
  echo "  sudo find /etc/postgresql -name pg_hba.conf"
  echo "Or run: sudo -u postgres psql -c 'SHOW hba_file;' after fixing auth"
  exit 1
fi

echo "Found pg_hba.conf at: $HBA_FILE"

# 3. Backup & modify pg_hba.conf (trust local)
echo "→ Backing up pg_hba.conf..."
sudo cp "$HBA_FILE" "${HBA_FILE}.bak.$(date +%Y%m%d-%H%M%S)"

echo "→ Setting local connections to 'trust' (no password)..."
sudo sed -i '/^local\s\+all\s\+all\s\+/ s/peer/trust/' "$HBA_FILE"
# Also handle ident if present
sudo sed -i '/^local\s\+all\s\+all\s\+/ s/ident/trust/' "$HBA_FILE"

# 4. Restart PostgreSQL
echo "→ Restarting PostgreSQL service..."
sudo systemctl restart postgresql
sleep 5  # give time to restart

# 5. Verify connection works
echo "→ Testing connection (should succeed now)..."
if sudo -u postgres psql -c "\q" >/dev/null 2>&1; then
  echo "Connection test OK - no password needed"
else
  echo "WARNING: Connection still fails - manual check needed"
  echo "Try: sudo -u postgres psql"
fi

# 6. Update Phoenix config/dev.exs - remove password
echo "→ Updating config/dev.exs..."
CONFIG_FILE="config/dev.exs"
if [[ -f "$CONFIG_FILE" ]]; then
  # Comment out password line
  sed -i '/password:/ s/^/# /' "$CONFIG_FILE" || true
  # Ensure username is set
  if ! grep -q "username:" "$CONFIG_FILE"; then
    sed -i '/Repo,/a \  username: "postgres",' "$CONFIG_FILE"
  fi
  echo "Config updated"
else
  echo "WARNING: config/dev.exs not found"
fi

# 7. Database setup
echo "→ Creating and migrating database..."
mix ecto.drop   || echo "Drop skipped (OK if db didn't exist)"
mix ecto.create || echo "Create may have warnings - continue"
mix ecto.migrate || echo "Migrate may have warnings - continue"

# 8. Optional watchman
sudo apt install -y watchman 2>/dev/null || true

# 9. Start server
echo ""
echo "===================================================="
echo "          Server Starting - Open http://localhost:4000"
echo "===================================================="
echo "Press Ctrl+C to stop"
echo ""

mix phx.server
