#!/usr/bin/env bash
# Sube cambios del index.html sin tocar Nginx ni el túnel.
set -euo pipefail
AQUI="$(cd "$(dirname "$0")/.." && pwd)"
sudo cp "$AQUI/index.html" "$AQUI/robots.txt" "$AQUI/sitemap.xml" /var/www/devcore/
sudo chown -R www-data:www-data /var/www/devcore
curl -s -o /dev/null -w "devcoremx.mx: %{http_code}\n" https://devcoremx.mx/
