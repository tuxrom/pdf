#!/usr/bin/env bash
# Construit l'image arm64 sur un Raspberry Pi à partir d'un dist/ compilé localement,
# la pousse sur ghcr.io sous :arm64, puis met à jour le manifeste multi-arch :latest.
#
# Prérequis :
#   - accès SSH par clé au Pi (PI_HOST), Docker installé sur le Pi
#   - sur le Pi, une fois : docker login ghcr.io -u <utilisateur> (token avec write:packages)
#
# Usage : scripts/build-arm64-pi.sh [--skip-build]
set -euo pipefail

PI_HOST="${PI_HOST:-pi@192.168.31.118}"
IMAGE="${IMAGE:-ghcr.io/tuxrom/pdf}"
REMOTE_DIR="${REMOTE_DIR:-logis-pdf-build}"

cd "$(dirname "$0")/.."

if [ "${1:-}" != "--skip-build" ]; then
  echo "==> Compilation locale (npm run build)"
  HUSKY=0 npm run build --script-shell bash
fi

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

echo "==> Préparation du contexte (fins de ligne LF)"
for f in Dockerfile.prebuilt nginx.conf nginx-ipv6.sh nginx-noindex.sh \
         security-headers.conf security-headers-docs.conf; do
  sed 's/\r$//' "$f" > "$STAGE/$f"
done
tar -czf "$STAGE/dist.tgz" dist

echo "==> Envoi vers $PI_HOST:$REMOTE_DIR"
ssh "$PI_HOST" "rm -rf ~/$REMOTE_DIR && mkdir -p ~/$REMOTE_DIR"
scp -q "$STAGE"/Dockerfile.prebuilt "$STAGE"/nginx.conf "$STAGE"/nginx-ipv6.sh \
  "$STAGE"/nginx-noindex.sh "$STAGE"/security-headers.conf \
  "$STAGE"/security-headers-docs.conf "$STAGE/dist.tgz" "$PI_HOST:$REMOTE_DIR/"

echo "==> Build arm64 et push sur le Pi"
ssh "$PI_HOST" "set -e
  cd ~/$REMOTE_DIR
  tar -xzf dist.tgz && rm dist.tgz
  docker build -f Dockerfile.prebuilt -t $IMAGE:arm64 .
  docker push $IMAGE:arm64
  if docker buildx imagetools inspect $IMAGE:amd64 > /dev/null 2>&1; then
    docker buildx imagetools create -t $IMAGE:latest $IMAGE:amd64 $IMAGE:arm64
  else
    echo 'Pas encore d image :amd64 (CI), :latest non modifié'
  fi"

echo "==> Terminé : $IMAGE:arm64"
