#!/bin/bash
# Recarga diaria del "navegador" de WhatsApp Web (Evolution / Baileys).
#
# Evolution solo pide a WhatsApp la version vigente de WhatsApp Web al
# conectar. Esto reconecta la instancia (como recargar la pestana del
# navegador) SIN cerrar sesion: no hace logout y no pide QR, la sesion
# sigue en Postgres. Asi cada dia queda con la version y el certificado
# de navegador al dia.
#
# Corre de dia (pedido de gabriel, 2026-10-15) a una hora al azar para no
# formar patron. La apikey se lee del propio contenedor; no va escrita aqui.
set -u
INST=soporte-prueba-whatsapp-tilapia
API=http://127.0.0.1:8080
LOG_PREFIX="[$(date '+%F %T')]"

if [ "${1:-}" != "--ya" ]; then
  # Ventana 10:00-15:00 Lima: el cron arranca a las 10:00 y aqui se sortea la espera.
  sleep $(( RANDOM % 300 ))m
fi

KEY=$(docker exec "$INST" printenv AUTHENTICATION_API_KEY 2>/dev/null)
if [ -z "$KEY" ]; then echo "$LOG_PREFIX sin apikey, no se recarga"; exit 1; fi

estado() {
  curl -sS -m 15 -H "apikey: $KEY" "$API/instance/connectionState/$INST" \
    | grep -o '"state":"[a-z]*"' | cut -d'"' -f4
}

ANTES=$(estado)
if [ "$ANTES" != "open" ]; then
  echo "$(date '+%F %T') estado=$ANTES; no se toca una sesion que no esta abierta"
  exit 0
fi

curl -sS -m 30 -X POST -H "apikey: $KEY" "$API/instance/restart/$INST" >/dev/null
for i in $(seq 1 12); do
  sleep 10
  [ "$(estado)" = "open" ] && break
done
DESPUES=$(estado)
VERSION=$(docker logs --since 5m "$INST" 2>&1 | grep -o 'Baileys version: [0-9.]*' | tail -1)
echo "$(date '+%F %T') recarga: antes=$ANTES despues=$DESPUES $VERSION"
