#!/usr/bin/env bash
set -euo pipefail

DATA_DIR="/vw-data"
COMPOSE_DIR="/home/denny/projects/personal/vaultwarden"
BACKUP_DIR="/tmp/vw-backup-$$"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
ARCHIVE="/tmp/vaultwarden-${TIMESTAMP}.tar.gz"
R2_DEST="r2:backup/vaultwarden"
KEEP=30

cd "$COMPOSE_DIR"
mkdir -p "$BACKUP_DIR"
# Always restart the container and clean up temps on exit
trap 'docker compose start vaultwarden 2>/dev/null || true; rm -rf "$BACKUP_DIR" "$ARCHIVE" 2>/dev/null || true' EXIT

echo "[1/4] Stopping vaultwarden..."
docker compose stop vaultwarden

echo "[2/4] Copying data..."
rsync -a "$DATA_DIR/" "$BACKUP_DIR/"

echo "[3/4] Restarting vaultwarden..."
docker compose start vaultwarden

echo "[4/4] Archiving and uploading..."
tar -czf "$ARCHIVE" -C "$BACKUP_DIR" .
rclone copyto --log-level INFO --s3-disable-checksum "$ARCHIVE" "$R2_DEST/$(basename "$ARCHIVE")"

# Prune old backups, keep the $KEEP most recent
rclone lsf "$R2_DEST/" --include "vaultwarden-*.tar.gz" \
  | sort -r \
  | tail -n "+$((KEEP + 1))" \
  | while read -r old; do
      echo "Pruning old backup: $old"
      rclone delete "$R2_DEST/$old"
    done

echo "Done: vaultwarden-${TIMESTAMP}.tar.gz → $R2_DEST"
