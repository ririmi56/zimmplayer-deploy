#!/bin/bash
# Fabrique un livrable autonome pour une cible sans acces reseau.
#
# Tire les images publiees sur GHCR plutot que de les reconstruire depuis les
# sources : ce depot n'a pas besoin de zimmplayer-front/zimmplayer-back a cote
# de lui. Produit dist-airgap/ contenant les images exportees et tout ce qu'il
# faut pour demarrer. A lancer depuis un poste connecte.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/dist-airgap"
cd "$ROOT"

FRONT_IMAGE="ghcr.io/ririmi56/zimmplayer-front:${FRONT_TAG:-latest}"
BACK_IMAGE="ghcr.io/ririmi56/zimmplayer-back:${BACK_TAG:-latest}"

echo "==> Recuperation des images"
docker pull "$FRONT_IMAGE"
docker pull "$BACK_IMAGE"
docker pull mariadb:11
docker pull minio/minio:latest

mkdir -p "$OUT"

echo "==> Export des images (peut prendre plusieurs minutes)"
docker save "$FRONT_IMAGE" "$BACK_IMAGE" mariadb:11 minio/minio:latest \
  | gzip > "$OUT/images.tar.gz"

cp docker-compose.yml "$OUT/"
cp .env.example "$OUT/"

cat > "$OUT/INSTALL.md" <<EOF
# Installation sur la cible airgap

1. Charger les images :

       gunzip -c images.tar.gz | docker load

2. Configurer :

       cp .env.example .env
       # editer .env : PUBLIC_BASE_URL, le stockage S3, les mots de passe

   PUBLIC_BASE_URL doit correspondre a l'adresse exacte que les utilisateurs
   taperont, port compris. Les URLs audio sont signees pour cette adresse.

3. Choisir le stockage, puis demarrer.

   - MinIO deja present sur le reseau airgap (cas normal) : renseigner
     S3_ENDPOINT / S3_ACCESS_KEY / S3_SECRET_KEY, puis

         docker compose up -d

   - MinIO fourni par ce livrable (essai, ou site sans stockage) : mettre
     S3_ENDPOINT=http://minio:9000, faire correspondre S3_ACCESS_KEY et
     S3_SECRET_KEY a MINIO_ROOT_USER / MINIO_ROOT_PASSWORD, puis

         docker compose --profile minio up -d

     Le bucket (S3_BUCKET, \`music\` par defaut) est alors a creer une fois
     depuis la console MinIO.

4. Alimenter le bucket MinIO avec la musique, rangee en
   \`Artiste/Album/NN - Titre.ext\`, puis lancer un scan depuis la page
   Administration de l'application.

## Images incluses

- $FRONT_IMAGE
- $BACK_IMAGE
- mariadb:11
- minio/minio:latest

## Verification

    curl -s localhost/api/health     # {"status":"ok","database":"ok"}
EOF

echo
echo "==> Livrable pret dans $OUT"
du -sh "$OUT"/* 2>/dev/null || true
