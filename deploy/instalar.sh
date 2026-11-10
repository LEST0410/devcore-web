#!/usr/bin/env bash
# Monta la web de DevCore en la Pi (gymtracker), junto a KAIROKU (8081) y NexoFit (3000).
# Uso: copia la carpeta devcore-web a la Pi y corre:  bash deploy/instalar.sh
set -euo pipefail

DOMINIO="devcoremx.mx"
PUERTO=8082
DESTINO=/var/www/devcore
TUNEL=9429758e-3650-41d0-87e4-10ebdb0e09c8
CFG=/etc/cloudflared/config.yml
AQUI="$(cd "$(dirname "$0")/.." && pwd)"

echo "== 1. Copiando el sitio a $DESTINO"
sudo mkdir -p "$DESTINO"
sudo cp "$AQUI/index.html" "$DESTINO/"
sudo cp "$AQUI/robots.txt" "$AQUI/sitemap.xml" "$DESTINO/"
sudo chown -R www-data:www-data "$DESTINO"

echo "== 2. Sitio de Nginx en 127.0.0.1:$PUERTO"
sudo tee /etc/nginx/sites-available/devcore > /dev/null <<EOF
server {
    listen 127.0.0.1:$PUERTO;
    server_name _;
    root $DESTINO;
    index index.html;

    if (\$host = www.$DOMINIO) { return 301 https://$DOMINIO\$request_uri; }

    add_header X-Content-Type-Options nosniff always;
    add_header Referrer-Policy strict-origin-when-cross-origin always;
    add_header X-Frame-Options SAMEORIGIN always;
    add_header Cache-Control "no-cache" always;

    gzip on;
    gzip_types text/css application/javascript image/svg+xml application/xml;

    location / { try_files \$uri \$uri/ /index.html; }
}
EOF
sudo ln -sf /etc/nginx/sites-available/devcore /etc/nginx/sites-enabled/devcore
sudo nginx -t
sudo systemctl reload nginx
curl -s -o /dev/null -w "   local: %{http_code}\n" http://127.0.0.1:$PUERTO/

echo "== 3. Rutas en el túnel de Cloudflare"
if grep -q "hostname: $DOMINIO\$" "$CFG"; then
  echo "   ya existían, no se toca $CFG"
else
  sudo cp "$CFG" "$CFG.bak-$(date +%Y%m%d-%H%M%S)"
  # Inserta las dos rutas justo antes de la regla final 404
  sudo sed -i "s|^  - service: http_status:404|  - hostname: $DOMINIO\n    service: http://127.0.0.1:$PUERTO\n  - hostname: www.$DOMINIO\n    service: http://127.0.0.1:$PUERTO\n  - service: http_status:404|" "$CFG"
fi
cloudflared tunnel --config "$CFG" ingress validate

echo "== 4. DNS (si ya existe un registro en $DOMINIO o www, bórralo antes en el panel)"
cloudflared tunnel route dns "$TUNEL" "$DOMINIO" || echo "   !! No se pudo crear $DOMINIO: revisa el panel DNS"
cloudflared tunnel route dns "$TUNEL" "www.$DOMINIO" || echo "   !! No se pudo crear www.$DOMINIO: revisa el panel DNS"

echo "== 5. Reiniciando el túnel"
sudo systemctl restart cloudflared
sleep 6
for h in $DOMINIO www.$DOMINIO kairoku.mx api.devcoremx.mx; do
  printf '   %-22s %s\n' "$h" "$(curl -s -o /dev/null -w '%{http_code}' https://$h/)"
done
echo "Listo. Esperado: devcoremx.mx 200, www 301, kairoku 200, api igual que antes."
