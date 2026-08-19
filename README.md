# Zimmplayer — Déploiement

[![Docker](https://img.shields.io/badge/images-GHCR-blue)](https://github.com/ririmi56?tab=packages)

Stack de [Zimmplayer](https://github.com/ririmi56/zimmplayer-back), à partir
des images publiées sur GHCR — rien à construire, rien d'autre à cloner. Le
**stockage n'est pas fourni** : l'application se branche sur un MinIO (ou un
service compatible S3) déjà présent sur le réseau. Trois dépôts composent le
projet :

| Dépôt | Contenu |
|---|---|
| [`zimmplayer-back`](https://github.com/ririmi56/zimmplayer-back) | API (FastAPI) |
| [`zimmplayer-front`](https://github.com/ririmi56/zimmplayer-front) | Client web (React) |
| `zimmplayer-deploy` (ce dépôt) | Orchestration, configuration, livrable airgap |

## Démarrage rapide (réseau normal)

```bash
cp .env.example .env
# éditer .env : PUBLIC_BASE_URL, les accès au MinIO du réseau, les mots de passe
docker compose up -d
```

Ensuite : alimenter le bucket MinIO avec la musique (organisée en
`Artiste/Album/NN - Titre.ext`), puis lancer un scan depuis la page
**Administration** de l'application.

Pas de MinIO sous la main pour un premier essai ? Un service jetable est fourni
derrière un profil, voir [MinIO jetable](#minio-jetable-pour-un-essai).

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

Le compose démarre trois services : `web` (front + reverse proxy nginx), `api`
et `mariadb`. Voir [`.env.example`](./.env.example) pour la liste complète et
les valeurs par défaut ; l'essentiel :

| Variable | Rôle |
|---|---|
| `PUBLIC_BASE_URL` | **Obligatoire.** Adresse exacte vue par les utilisateurs |
| `S3_ENDPOINT`, `S3_ACCESS_KEY`, `S3_SECRET_KEY` | **Obligatoires.** Le MinIO du réseau, voir juste en dessous |
| `HTTP_PORT` | Port d'écoute de l'application (défaut `80`) |
| `DB_ROOT_PASSWORD`, `DB_PASSWORD` | Secrets MariaDB — à changer impérativement |
| `S3_BUCKET`, `S3_PREFIX` | Bucket et sous-dossier à indexer |
| `S3_REGION` | Région annoncée dans la signature SigV4 (défaut `us-east-1`) |
| `FRONT_TAG`, `BACK_TAG` | Version des images à déployer (`latest`, un tag `X.Y.Z`, ou un sha court — voir les [packages GHCR](https://github.com/ririmi56?tab=packages) pour ce qui est disponible) |
| `OIDC_*`, `SUPER_ADMINS`, `SESSION_SECRET` | Authentification et administrateurs, facultatif — voir ci-dessous |
| `TLS_CA_FILE` | Autorité de certification interne — indispensable en airgap, voir ci-dessous |
| `PROXY_SSL_VERIFY` | Vérification par nginx des upstreams `https` (défaut `off`) |
| `SNAPCAST_*` | Facultatif, voir ci-dessous |
| `MINIO_ROOT_USER`, `MINIO_ROOT_PASSWORD` | Uniquement pour le MinIO jetable du profil `minio` |

`S3_REGION` n'a aucune importance face à MinIO, qui accepte n'importe quelle
valeur — mais un vrai S3 exige la région du bucket, faute de quoi il rejette la
signature.

## Brancher le stockage

`S3_ENDPOINT`, `S3_ACCESS_KEY` et `S3_SECRET_KEY` pointent l'application vers
n'importe quel MinIO (ou service compatible S3) du réseau. Elles servent à la
fois à l'API et au service `web`, qui expose `/s3` au navigateur — un seul
endroit à régler.

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

### MinIO jetable pour un essai

Pour essayer la stack sans stockage sous la main, le compose embarque un
service `minio`. Il est placé derrière un **profil**, donc `docker compose
up -d` ne le démarre pas ; il faut le demander :

```bash
docker compose --profile minio up -d
```

Il faut alors le désigner comme stockage, avec des identifiants cohérents :

```bash
S3_ENDPOINT=http://minio:9000
S3_ACCESS_KEY=minioadmin           # = MINIO_ROOT_USER
S3_SECRET_KEY=changez-moi-aussi    # = MINIO_ROOT_PASSWORD
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=changez-moi-aussi
```

Le bucket (`S3_BUCKET`, `music` par défaut) reste à créer une fois, depuis la
console MinIO — décommenter son port dans le compose pour y accéder.

**À réserver aux essais** : ce MinIO stocke la musique dans un volume Docker
local et ne sert qu'à voir tourner l'application. Un déploiement réel se
branche sur le stockage du réseau.

## Autorité de certification interne (airgap)

Sur un réseau airgap, les certificats sont signés par une **autorité maison**
qu'aucune image publique ne connaît. Une seule variable la déclare :

```dotenv
TLS_CA_FILE=/etc/pki/mon-autorite.pem
```

Le chemin est celui de **l'hôte**. Le compose monte le fichier au même chemin
dans `api` et `web`, en lecture seule : il n'y a rien d'autre à écrire. Laissée
vide, la variable ne monte rien et les images utilisent leur magasin système.

Elle couvre tout ce que l'API joint en chiffré :

| Client | Ce qu'il joint |
|---|---|
| boto3 | `S3_ENDPOINT` — listage, téléchargement, signature des URLs |
| ffmpeg | l'URL présignée du morceau, en lecture Snapcast |
| websockets | le proxy TLS devant snapserver (voir `SNAPCAST_TLS`) |

Trois points à connaître :

- **le fichier remplace le magasin système**, il ne s'y ajoute pas. Pour joindre
  aussi des serveurs à certificat public, y concaténer les deux jeux ;
- **nginx est à part.** Le proxy `/s3` vers MinIO ne vérifie aucun certificat
  par défaut, comme nginx en général. Dès que `S3_ENDPOINT` est en `https`,
  ajouter `PROXY_SSL_VERIFY=on` : la vérification se fait alors avec
  `TLS_CA_FILE`, ou avec le magasin de l'image si elle est vide ;
- **ffmpeg ne vérifiait rien** jusqu'ici (`tls_verify` vaut `0` par défaut chez
  lui). C'est désormais activé dès que l'URL est en `https`. Un stockage `https`
  à certificat auto-signé et sans `TLS_CA_FILE` cessera donc de fonctionner —
  c'est le but : l'URL présignée qui y transite porte les droits de lecture du
  bucket.

Un mauvais chemin se voit tout de suite : `web` refuse de démarrer en nommant le
fichier introuvable, et l'API échoue à son premier accès au stockage.

## Authentification (OIDC, facultatif)

Par defaut, chacun choisit un pseudo dans l'ecran Configuration et **rien
n'est verifie**. `OIDC_ENABLED=true` remplace ce pseudo par l'identite du
fournisseur.

Seule l'URL de l'emetteur est declaree ; les points d'entree sont lus dans son
document de decouverte. **N'importe quel fournisseur OIDC conforme convient** —
Authentik, Keycloak, Dex, Zitadel, Entra.

```dotenv
OIDC_ENABLED=true
OIDC_ISSUER=https://authentik.interne/application/o/zimmplayer/
OIDC_CLIENT_ID=...
OIDC_CLIENT_SECRET=...
SUPER_ADMINS=adrien@interne   # comptes toujours administrateurs
SESSION_SECRET=               # openssl rand -hex 32, obligatoire
```

**L'URI de redirection a declarer chez le fournisseur** est
`<PUBLIC_BASE_URL>/api/auth/callback`, au caractere pres. C'est de loin la
premiere cause d'echec.

### Cote Authentik

1. **Fournisseur OAuth2/OpenID**, type de client **confidentiel** ;
2. URI de redirection : `<PUBLIC_BASE_URL>/api/auth/callback` ;
3. portees : `openid`, `profile`, `email`, plus la portee **groups** ;
4. relever l'**URL de configuration OpenID** de l'application : c'est
   `OIDC_ISSUER`, en retirant le `/.well-known/openid-configuration` final.

Sans la portee `groups`, tout fonctionne mais aucun groupe n'arrive. Les
groupes ne donnent aucun role — ils sont seulement affiches — mais c'est
l'oubli le plus courant, autant le savoir.

### Certificats

Le fournisseur est joint avec `TLS_CA_FILE` — la meme autorite interne que le
reste (voir plus haut). `OIDC_CA_FILE` n'existe que pour le cas ou le
fournisseur serait signe par une autre. **La verification n'est jamais
desactivable** : un fournisseur d'identite usurpe permettrait de forger
n'importe quelle connexion.

### Administrateurs

`SUPER_ADMINS` liste les comptes **toujours** administrateurs, par `sub` ou par
courriel. C'est par eux que l'on entre la premiere fois, et **leur role ne se
retire pas depuis l'interface** : meme si la base est perdue, ces comptes-la
font toujours entrer.

Ils nomment ensuite les autres depuis la page **Administration**, ce qui est
conserve en base. `/api/admin/*` repond **403** a qui n'est pas administrateur,
et l'onglet disparait de la navigation.

Trois refus deliberes : se retirer soi-meme le role, retrograder un compte de
`SUPER_ADMINS`, et retirer le dernier administrateur quand aucun
super-administrateur connu n'existe.

**On ne peut promouvoir que quelqu'un qui s'est deja connecte au moins une
fois** : aucune API OIDC standard ne permet de lister les comptes d'un
fournisseur, l'application ne connait donc que ceux qu'elle a vus.

Laisser `SUPER_ADMINS` vide expose a se retrouver sans administrateur du tout.
L'API le signale au demarrage, dans ses journaux.

Sans OIDC, tout le monde est administrateur : sans fournisseur d'identite,
distinguer les roles n'aurait aucun fondement.

L'en-tete `X-User-Name` **cesse d'etre lue** des qu'OIDC est actif : la laisser
offrirait un chemin trivial pour se faire passer pour quelqu'un d'autre.

## Snapcast (facultatif)

Zimmplayer ne fournit pas de serveur Snapcast — il s'y connecte. Il en faut
donc un déjà présent sur le réseau pour activer ce mode. Aucune modification
de `snapserver.conf` n'est nécessaire : chaque session y enregistre son propre
flux à la volée.

**Un seul port de snapserver est utilisé** : celui de son serveur HTTP intégré
(`SNAPCAST_HTTP_PORT`, 1780 par défaut), qui porte à la fois le contrôle
JSON-RPC (`/jsonrpc`) et l'audio (`/stream`). Le port de contrôle TCP 1705 n'a
plus besoin d'être ouvert ni déclaré.

Réglages obligatoires si `SNAPCAST_ENABLED=true` :

- `SNAPCAST_HOST` et `SNAPCAST_HTTP_PORT` — le serveur HTTP de snapserver, vu
  depuis l'API.
- `SNAPCAST_ADVERTISE_HOST` — l'adresse de **cette API**, vue depuis
  snapserver (c'est lui qui vient s'y connecter, pas l'inverse). **Peut être un
  nom d'hôte** : l'API le résout elle-même en IP (`socket.gethostbyname`) à
  chaque enregistrement de flux — snapserver, lui, ne reçoit qu'une IP dans
  l'URI, mais c'est l'API qui s'en charge, pas vous.
- La plage `SNAPCAST_PORT_START`…`SNAPCAST_PORT_END` doit être joignable
  depuis snapserver — un port par session diffusée simultanément.

### Snapcast en TLS

Snapserver ne chiffre rien lui-même. `SNAPCAST_TLS=true` suppose donc un
**reverse proxy TLS devant lui**, avec `SNAPCAST_HTTP_PORT` pointant sur ce
proxy : contrôle et audio passent alors tous les deux en `wss://`.

Le certificat est toujours vérifié, sans option pour désactiver ce contrôle.
Avec une autorité maison — le cas courant en airgap — il n'y a rien à ajouter
ici : `TLS_CA_FILE` s'applique aussi à snapserver.

```dotenv
SNAPCAST_TLS=true
# Si l'on joint le serveur par IP alors que le certificat porte un nom :
SNAPCAST_TLS_SERVER_NAME=snapserver.mon-reseau
```

`SNAPCAST_TLS_CA_FILE` n'existe que pour le cas où le proxy de snapserver est
signé par une **autre** autorité que le stockage. Ce chemin-là n'est pas monté
automatiquement : il faut alors ajouter le volume soi-même.

À la différence de l'hôte, du port et de l'adresse annoncée, **ces trois
réglages ne sont pas modifiables depuis l'écran Configuration** : les changer
demande un redéploiement.

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
