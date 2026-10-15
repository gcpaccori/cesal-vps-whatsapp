#!/bin/bash
# Respalda la sesion de WhatsApp de Evolution API.
#
# La vinculacion del numero NO esta en ningun archivo: vive en la base
# PostgreSQL y en el volumen de instancias. Si se pierden, hay que volver a
# escanear el QR con el telefono. Este script guarda ambos.
#
# Uso:  ./respaldar-sesion.sh
# Cron: 0 3 * * * root /opt/evolution/respaldar-sesion.sh >> /var/log/nawpariy-respaldo.log 2>&1

set -euo pipefail

ENV_FILE="${ENV_FILE:-/opt/evolution/.env}"
DESTINO="${DESTINO:-/root/backups/evolution}"
CONSERVAR_DIAS="${CONSERVAR_DIAS:-14}"
FECHA=$(date +%Y%m%d-%H%M%S)

[ -f "$ENV_FILE" ] || { echo "no existe $ENV_FILE"; exit 1; }
mkdir -p "$DESTINO"

# Las credenciales salen del .env; no van escritas aqui.
URI=$(grep -E '^DATABASE_CONNECTION_URI=' "$ENV_FILE" | cut -d= -f2-)
USUARIO=$(echo "$URI" | sed -E 's#^postgresql://([^:]+):.*#\1#')
BASE=$(echo "$URI" | sed -E 's#.*/([^?]+)(\?.*)?$#\1#')

echo "[$(date '+%F %T')] respaldando base '$BASE' como '$USUARIO'"
docker exec evolution-postgres pg_dump -U "$USUARIO" -d "$BASE" \
  | gzip > "$DESTINO/evolution-$FECHA.sql.gz"

echo "[$(date '+%F %T')] respaldando volumen de instancias"
docker run --rm \
  -v evolution_evolution_instances:/datos:ro \
  -v "$DESTINO":/salida \
  alpine tar czf "/salida/instancias-$FECHA.tar.gz" -C /datos .

find "$DESTINO" -name '*.gz' -mtime "+$CONSERVAR_DIAS" -delete

echo "[$(date '+%F %T')] listo:"
ls -lh "$DESTINO" | tail -3
