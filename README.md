# Zimmplayer — Déploiement

[![Docker](https://img.shields.io/badge/images-GHCR-blue)](https://github.com/ririmi56?tab=packages)

Stack complète de [Zimmplayer](https://github.com/ririmi56/zimmplayer-back), à
partir des images publiées sur GHCR — rien à construire, rien d'autre à
cloner. Trois dépôts composent le projet :

| Dépôt | Contenu |
|---|---|
| [`zimmplayer-back`](https://github.com/ririmi56/zimmplayer-back) | API (FastAPI) |
| [`zimmplayer-front`](https://github.com/ririmi56/zimmplayer-front) | Client web (React) |
| `zimmplayer-deploy` (ce dépôt) | Orchestration, configuration, livrable airgap |

## Démarrage rapide (réseau normal)

```bash
cp .env.example .env
# éditer .env : PUBLIC_BASE_URL et les mots de passe
docker compose up -d
```

Ensuite : alimenter le bucket MinIO avec la musique (organisée en
`Artiste/Album/NN - Titre.ext`), puis lancer un scan depuis la page
**Administration** de l'application.

```bash
curl -s localhost/api/health     # {"status":"ok","database":"ok"}
```

## Réglage obligatoire : `PUBLIC_BASE_URL`

La cause de loin la plus probable d'une lecture qui ne démarre pas. Cette
variable doit correspondre **exactement** à l'adresse tapée par les
utilisateurs, port compris (`http://192.168.10.20`, `http://musique:8080`).
Les URLs audio sont signées pour cette adresse ; MinIO rejette la signature au
moindre écart, et rien ne se lit — pas d'erreur explicite côté interface.

## Services et variables d'environnement

Le compose démarre quatre services : `web` (front + reverse proxy nginx),
`api`, `mariadb`, `minio`. Voir [`.env.example`](./.env.example) pour la liste
complète et les valeurs par défaut ; l'essentiel :

| Variable | Rôle |
|---|---|
| `PUBLIC_BASE_URL` | **Obligatoire.** Adresse exacte vue par les utilisateurs |
| `HTTP_PORT` | Port d'écoute de l'application (défaut `80`) |
| `DB_ROOT_PASSWORD`, `DB_PASSWORD` | Secrets MariaDB — à changer impérativement |
| `MINIO_ROOT_USER`, `MINIO_ROOT_PASSWORD` | Secrets du MinIO fourni par ce compose — à changer impérativement, sauf si vous utilisez `S3_ENDPOINT`/`S3_ACCESS_KEY`/`S3_SECRET_KEY` ci-dessous à la place |
| `S3_ENDPOINT`, `S3_ACCESS_KEY`, `S3_SECRET_KEY` | Facultatif — pointer vers un MinIO déjà déployé, voir juste en dessous |
| `S3_BUCKET`, `S3_PREFIX` | Bucket et sous-dossier à indexer |
| `FRONT_TAG`, `BACK_TAG` | Version des images à déployer (`latest`, un tag `X.Y.Z`, ou un sha court — voir les [packages GHCR](https://github.com/ririmi56?tab=packages) pour ce qui est disponible) |
| `SNAPCAST_*` | Facultatif, voir ci-dessous |

## Utiliser un MinIO déjà déployé

Le compose fournit un MinIO tout prêt, mais rien n'oblige à s'en servir :
renseigner `S3_ENDPOINT`, `S3_ACCESS_KEY` et `S3_SECRET_KEY` dans `.env` pointe
l'application vers n'importe quel MinIO (ou service S3 compatible) déjà
présent sur le réseau, à la place. Ces trois variables prennent le pas sur
`MINIO_ROOT_USER`/`MINIO_ROOT_PASSWORD` pour l'API, et sont aussi répercutées
côté `web` (qui expose `/s3` au navigateur) — un seul endroit à régler.

**Aucun besoin du compte root de ce MinIO-là.** L'application ne fait jamais
que lister et lire le bucket — jamais écrire, jamais administrer — donc un
compte access key/secret key scopé à cet unique usage suffit. Policy MinIO
minimale (remplacer `music` par la valeur de `S3_BUCKET` si différente) :

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:ListBucket"],
      "Resource": ["arn:aws:s3:::music"]
    },
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject"],
      "Resource": ["arn:aws:s3:::music/*"]
    }
  ]
}
```

À créer et attacher via le client `mc` :

```bash
mc alias set monminio http://mon-minio-existant:9000 <admin> <mot-de-passe>
mc admin policy create monminio zimmplayer-reader policy.json
mc admin user add monminio zimmplayer-reader une-cle-secrete-dediee
mc admin policy attach monminio zimmplayer-reader --user zimmplayer-reader
```

Puis dans `.env` :

```bash
S3_ENDPOINT=http://mon-minio-existant:9000
S3_ACCESS_KEY=zimmplayer-reader
S3_SECRET_KEY=une-cle-secrete-dediee
```

Pour omettre complètement le `minio` fourni par ce compose plutôt que de le
laisser tourner sans s'en servir, `--no-deps` est nécessaire — `depends_on`
sinon le redémarre de toute façon, même absent de la liste :

```bash
docker compose up -d --no-deps web api mariadb
```

## Snapcast (facultatif)

Zimmplayer ne fournit pas de serveur Snapcast — il s'y connecte. Il en faut
donc un déjà présent sur le réseau pour activer ce mode. Aucune modification
de `snapserver.conf` n'est nécessaire : chaque session y enregistre son propre
flux à la volée. Deux réglages sont obligatoires si `SNAPCAST_ENABLED=true` :

- `SNAPCAST_ADVERTISE_HOST` — l'adresse de **cette API**, vue depuis
  snapserver (c'est lui qui vient s'y connecter, pas l'inverse). **Peut être un
  nom d'hôte** : l'API le résout elle-même en IP (`socket.gethostbyname`) à
  chaque enregistrement de flux — snapserver, lui, ne reçoit qu'une IP dans
  l'URI, mais c'est l'API qui s'en charge, pas vous.
- La plage `SNAPCAST_PORT_START`…`SNAPCAST_PORT_END` doit être joignable
  depuis snapserver — un port par session diffusée simultanément.

### Snapcast et Kubernetes (ou tout environnement à IP non stable)

Si l'API tourne dans un pod dont l'IP change à chaque reprogrammation,
**ne pas** utiliser cette IP directement dans `SNAPCAST_ADVERTISE_HOST` :

- si snapserver vit **dans le même cluster**, pointer vers le nom DNS d'un
  **Service** stable (`zimmplayer-api.mon-namespace.svc.cluster.local`, ou en
  forme courte si même namespace) plutôt que vers un pod. Le Service garde la
  même IP virtuelle quel que soit le pod qui le sert à un instant donné, et
  l'API la re-résout à chaque session créée et à chaque redémarrage
  (`restore()` reconstruit tous les flux au démarrage) — un pod remplacé ne
  casse donc rien.
- si snapserver vit **hors du cluster**, l'IP virtuelle d'un Service
  `ClusterIP` n'est en général pas joignable de l'extérieur : il faut une
  adresse réellement externe (`NodePort`, `LoadBalancer`/MetalLB, ou
  `hostNetwork` sur le pod), et c'est celle-là qu'il faut avancer.
- la plage `SNAPCAST_PORT_START`…`_END` doit être **explicitement déclarée**
  dans le Service (chaque port un par un — Kubernetes ne sait pas exposer une
  plage dynamique) ou, plus simple si le cas s'y prête, faire tourner le pod
  en `hostNetwork: true`.

**Contrainte plus fondamentale, indépendante de Kubernetes** : ce mécanisme
garde son état (flux ouverts, sockets en écoute) **en mémoire du process
API**, jamais partagé entre plusieurs instances. Snapcast n'est donc
utilisable qu'avec **une seule replica** de `api` à la fois — un
`Deployment` avec `replicas: 1` (ou un `StatefulSet` à une seule instance) et
sans mise à l'échelle automatique sur ce composant.

## Livrable pour un réseau airgap

Depuis un poste **connecté** :

```bash
bash scripts/bundle_airgap.sh
```

Tire les quatre images (`zimmplayer-front`, `zimmplayer-back`, `mariadb`,
`minio`) — `FRONT_TAG`/`BACK_TAG` en variables d'environnement pour choisir une
version précise plutôt que `latest` — et produit `dist-airgap/` : les images
exportées (`images.tar.gz`), `docker-compose.yml`, `.env.example`, et un
`INSTALL.md` prêt à suivre sur la cible. Transférer tout le dossier, puis sur
la cible :

```bash
gunzip -c images.tar.gz | docker load
cp .env.example .env    # éditer PUBLIC_BASE_URL et les mots de passe
docker compose up -d
```

## Ce qui n'est volontairement pas ici

Les scripts de vérification (`check_scan.sh`, `check_queue.sh`,
`check_snapcast.sh`) et le générateur de bibliothèque de test
(`seed_minio.py`) ne sont pas repris dans ce dépôt : ce sont des outils de
développement qui exigent le code source du backend et sa stack de dev
(`docker-compose.dev.yml`), pas seulement les images publiées. Les inclure ici
aurait été trompeur — ils ne fonctionneraient pas sans ce contexte.

## Licence

MIT, voir [`LICENSE`](./LICENSE).
