# Nawpariy CESAL: VPS de WhatsApp y documentos

Configuracion del VPS Contabo `inictel-uni-host` (167.86.74.132,
`https://vmi3402471.contaboserver.net`). Aqui corren el canal de WhatsApp
(Evolution API), el servicio de OCR y los crones que mueven la API PHP del
hosting. Sin este repositorio, si el VPS se pierde no hay forma de
reconstruirlo. La app y la API viven en `gcpaccori/CESAL-IoT-App`.

Copiado del servidor el 2026-10-15. **Ningun secreto va aqui**: las apikeys, la
contrasena de Postgres y el token de los crones (`TOKEN_CRON`) se rellenan a mano.

## Que hay y donde va

| En este repo | En el VPS | Que hace |
|---|---|---|
| `evolution/docker-compose.yml` | `/opt/evolution/` | Evolution API v2.3.7 + Postgres 16 + Redis 7 |
| `evolution/.env.example` | `/opt/evolution/.env` | Plantilla, rellenar |
| `evolution/respaldar-sesion.sh` | `/opt/evolution/` | Respaldo de la sesion de WhatsApp |
| `nawpariy-docs/` | `/opt/nawpariy-docs/` | OCR y conversion de documentos |
| `nawpariy-docs.env.example` | `/opt/nawpariy-docs/.env` | Token del servicio |
| `nginx/evolution.conf` | `/etc/nginx/sites-available/evolution` | HTTPS: `/` a Evolution, `/docs/` al OCR |
| `cron/nawpariy-*` | `/etc/cron.d/` | Crones de root (ver abajo) |
| `usuario/crontab` | `crontab` de `inicteladm` | Recarga diaria de WhatsApp Web |
| `usuario/recargar-whatsapp.sh` | `/home/inicteladm/nawpariy/` | Script de esa recarga |

Los contenedores escuchan solo en loopback; desde fuera se entra por nginx.

## Crones

| Cuando | Que |
|---|---|
| Cada 15 s | `agente/cola`: despacha las respuestas del bot |
| Cada minuto | `anuncios/despachar` |
| Cada 15 min | `motor/evaluar` (motor agronomico) |
| 03:00 | Respaldo de la sesion de WhatsApp (14 dias) |
| 05:00 | `planes/evaluar` |
| 10:00 + azar hasta 15:00 | Recarga de WhatsApp Web (usuario `inicteladm`) |

## Recarga diaria de WhatsApp Web

Evolution (Baileys) pide a WhatsApp la version vigente de WhatsApp Web solo al
conectar. `usuario/recargar-whatsapp.sh` reconecta la instancia una vez al dia,
de dia y a una hora al azar, **sin cerrar sesion**: llama a
`POST /instance/restart`, que cierra el socket y vuelve a conectar con la
sesion guardada en Postgres. No hace logout, no pide QR y no reinicia el
contenedor. Si la sesion no esta abierta, no la toca.

Probado el 2026-10-15 09:45: `antes=open despues=open`, version
2.3000.1050463354. Registro en `/home/inicteladm/nawpariy/recarga.log`.

Antes (2026-10-03 a 2026-10-15) se hacia con `docker restart` del contenedor
entero; queda como `usuario/reinicio-evolution.sh.antiguo`.

Para probarla a mano, sin esperar el azar:

```bash
~/nawpariy/recargar-whatsapp.sh --ya
```

## Reconstruir el VPS desde cero

```bash
# 1. Evolution
sudo mkdir -p /opt/evolution && cd /opt/evolution
# copiar evolution/docker-compose.yml, .env.example y respaldar-sesion.sh
cp .env.example .env      # y rellenar apikey y contrasenas
docker compose up -d

# 2. Servicio de documentos (OCR)
sudo mkdir -p /opt/nawpariy-docs && cd /opt/nawpariy-docs
# copiar nawpariy-docs/*
echo "DOC_TOKEN=$(openssl rand -hex 24)" > .env && chmod 600 .env
docker compose up -d --build

# 3. nginx
# copiar nginx/evolution.conf a /etc/nginx/sites-available/evolution y enlazarlo
certbot --nginx -d TU-HOST
nginx -t && systemctl reload nginx

# 4. Crones de root
# copiar cron/* a /etc/cron.d/, chmod 644, cambiar TOKEN_CRON
systemctl restart cron

# 5. Crontab del usuario
mkdir -p ~/nawpariy && cp usuario/recargar-whatsapp.sh ~/nawpariy/
crontab usuario/crontab
```

Despues, en `api-v3/config/agente.local.php` del hosting, apuntar
`EVOLUTION_API_URL`, `EVOLUTION_API_KEY` y `DOCS_TOKEN` a los valores nuevos.

## Vincular el número de WhatsApp

La instancia se llama `soporte-prueba-whatsapp-tilapia`. Para vincular un teléfono:

```bash
# Estado actual
curl -H "apikey: LA_APIKEY" \
     http://127.0.0.1:8080/instance/connectionState/soporte-prueba-whatsapp-tilapia

# Pedir el codigo QR
curl -H "apikey: LA_APIKEY" \
     http://127.0.0.1:8080/instance/connect/soporte-prueba-whatsapp-tilapia
```

Devuelve un QR en base64 que **caduca en unos 40 segundos**: hay que escanearlo casi
en el momento. Se escanea desde *WhatsApp → Dispositivos vinculados → Vincular*.

Tras vincular aparece un `stream:error 515` en los logs: es el reconecte normal de
Baileys, no un fallo. Lo que vale es que `connectionState` diga `open`.

El webhook debe apuntar a:

```text
https://citeapurimac.org/NawapariyProject/api-v3/agente/whatsapp/webhook?token=...
```

## Acceso

Esta red bloquea los puertos que no son 443: **el 22 y el 2083 solo funcionan por el
túnel SOCKS5.** Ver `Tools/internet.md`, junto con `tunel.py`, `vps.py` y `cpanel.py`.

---

## Respaldo de la sesion de WhatsApp

**La vinculacion del numero no esta en ningun archivo de este repositorio.**
Vive en la base PostgreSQL de Evolution, en la tabla `Session` (credenciales de
Baileys). Si se pierde esa base, hay que volver a escanear el QR con el telefono.

`evolution/respaldar-sesion.sh` la guarda. Se instala en el VPS asi:

```bash
cp evolution/respaldar-sesion.sh /opt/evolution/
chmod +x /opt/evolution/respaldar-sesion.sh
cp cron/nawpariy-respaldo /etc/cron.d/
```

Corre cada dia a las 03:00 y deja en `/root/backups/evolution/`:

- `evolution-FECHA.sql.gz` — volcado completo (37 tablas, ~2.9 MB)
- `instancias-FECHA.tar.gz` — volumen de instancias

Conserva 14 dias. Las credenciales las lee de `/opt/evolution/.env`, no van
escritas en el script.

### Restaurar

```bash
docker exec -i evolution-postgres psql -U evolution -d evolution \
  < <(gunzip -c /root/backups/evolution/evolution-FECHA.sql.gz)
docker restart soporte-prueba-whatsapp-tilapia
```

Al reiniciar, la instancia retoma la sesion sin pedir QR.

