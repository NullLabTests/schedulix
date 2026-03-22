#!/usr/bin/env bash
set -euo pipefail

# =====================================================================
# FINAL FIXED SCRIPT: Force-add password to config/dev.exs
# - Finds pg_hba.conf correctly
# - Sets trust for local
# - Adds password: "postgres" to config if missing
# - Creates/migrates DB
# - Starts server
# =====================================================================

echo "============================================================="
echo "  schedulix FINAL DB Fix & Start Script                     "
echo "  - Sets password 'postgres' for user postgres              "
echo "  - Forces password in config/dev.exs                       "
echo "  - Trusts local (backup)                                   "
echo "  - Creates DB and starts server                            "
echo "============================================================="

PROJECT_DIR="$HOME/schedulix"

# 1. Go to project
if [[ ! -d "$PROJECT_DIR" ]]; then
  echo "ERROR: $PROJECT_DIR not found"
  exit 1
fi

cd "$PROJECT_DIR" || exit 1
echo "Working in: $(pwd)"

# 2. Set postgres password explicitly (this works even if pg_hba is peer)
echo "→ Setting postgres user password to 'postgres'..."
sudo -u postgres psql -c "ALTER USER postgres WITH PASSWORD 'postgres';" || {
  echo "Failed to set password - Postgres may need manual fix"
  echo "Try: sudo -u postgres psql"
  exit 1
}

# 3. Find pg_hba.conf
echo "→ Locating pg_hba.conf..."
HBA_FILE=$(sudo -u postgres psql -t -P format=unaligned -c "SHOW hba_file;" 2>/dev/null)

if [[ -z "$HBA_FILE" || ! -f "$HBA_FILE" ]]; then
  echo "Could not auto-detect pg_hba.conf"
  HBA_FILE="/etc/postgresql/$(ls /etc/postgresql/ | head -1)/main/pg_hba.conf"
  echo "Trying fallback: $HBA_FILE"
fi

if [[ -f "$HBA_FILE" ]]; then
  echo "→ Backing up $HBA_FILE"
  sudo cp "$HBA_FILE" "${HBA_FILE}.bak.$(date +%Y%m%d-%H%M)"

  echo "→ Setting local to trust (optional safety net)"
  sudo sed -i '/^local\s\+all\s\+all\s\+/ s/peer/trust/' "$HBA_FILE"
  sudo sed -i '/^local\s\+all\s\+all\s\+/ s/ident/trust/' "$HBA_FILE"
  sudo systemctl restart postgresql
  sleep 3
else
  echo "WARNING: pg_hba.conf not found - assuming password is now set"
fi

# 4. Force password in config/dev.exs
echo "→ Forcing password in config/dev.exs..."
CONFIG_FILE="config/dev.exs"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "ERROR: config/dev.exs missing"
  exit 1
fi

# Remove old password line if exists
sed -i '/password:/d' "$CONFIG_FILE"

# Add fresh password line after Repo config start
sed -i '/config :schedulix, Schedulix.Repo,/a \  password: "postgres",' "$CONFIG_FILE"

echo "Config now includes password: \"postgres\""

# 5. DB setup
echo "→ Setting up database..."
mix ecto.drop   || true
mix ecto.create || { echo "Create failed - see above"; exit 1; }
mix ecto.migrate || { echo "Migrate failed - see above"; exit 1; }

# 6. Start server
echo ""
echo "===================================================="
echo "          Server Starting NOW                       "
echo "  → http://localhost:4000                           "
echo "===================================================="

mix phx.server
