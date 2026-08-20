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
| `zimmplayer-deploy` (ce dépôt) | Orchestration (compose et chart Helm), configuration, livrable airgap |

## Démarrage rapide (réseau normal)

```bash
cp .env.example .env
# éditer .env : PUBLIC_BASE_URL, les accès au MinIO du réseau, les mots de passe
docker compose up -d
```

Ensuite : alimenter le bucket MinIO avec la musique (organisée en
`Artiste/Album/NN - Titre.ext`), puis lancer un scan depuis la page
**Administration** de l'application.

Sur Kubernetes, la même stack se déploie par la [chart
Helm](#kubernetes--la-chart-helm) — snapserver compris.

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

**La chart Helm règle déjà tout ce qui suit** ; cette section explique ce
qu'elle fait, pour qui écrit ses propres manifestes.

Si l'API tourne dans un pod dont l'IP change à chaque reprogrammation, **ne
pas** figer cette IP dans `SNAPCAST_ADVERTISE_HOST`. Deux routes marchent, et
elles ne coûtent pas la même chose :

- **Un Service sans `clusterIP` (« headless »)**, ce que fait la chart. Le DNS
  rend alors l'IP **du pod**, et snapserver ouvre sa connexion dessus
  directement : la plage `SNAPCAST_PORT_START`…`_END` n'a **rien à déclarer**,
  puisque aucun Service ne relaie. L'IP change à chaque reprogrammation, mais
  l'API la re-résout à chaque session créée et à chaque redémarrage
  (`restore()` reconstruit tous les flux au démarrage).

  Ce Service doit porter `publishNotReadyAddresses: true`. Sans lui, le DNS ne
  publie que les adresses *prêtes* — or `restore()` tourne **avant** que le
  pod le soit. Mesuré : l'API journalise alors `impossible de resoudre
  '…-api-direct' en adresse IP`, snapserver reste pointé sur l'IP du pod
  **précédent**, et toutes les sessions restent muettes jusqu'à une
  intervention manuelle.

- **Un Service `ClusterIP` ordinaire**, dont l'IP virtuelle est stable. Il
  faut alors y **déclarer chaque port un par un** — Kubernetes ne sait pas
  exposer une plage.

Si snapserver vit **hors du cluster**, ni l'une ni l'autre ne suffit : il lui
faut une adresse réellement joignable de l'extérieur (`NodePort`,
`LoadBalancer`/MetalLB, ou `hostNetwork` sur le pod), et c'est celle-là qu'il
faut annoncer.

Dernier piège, propre à l'application : `SNAPCAST_ADVERTISE_HOST` n'est qu'une
**valeur par défaut**. Dès qu'on touche à ce champ depuis l'écran
Configuration, il est écrit en base et c'est lui qui prime — l'environnement
n'est plus lu, et l'adresse se fige. Sur un cluster, ne pas y toucher.

**Contrainte plus fondamentale, indépendante de Kubernetes** : ce mécanisme
garde son état (flux ouverts, sockets en écoute) **en mémoire du process
API**, jamais partagé entre plusieurs instances. Snapcast n'est donc
utilisable qu'avec **une seule replica** de `api` à la fois. C'est pourquoi la
chart fixe `replicas: 1` sans l'exposer en réglage, et déploie l'API en
`strategy: Recreate` : pendant un `RollingUpdate`, l'ancien et le nouveau pod
tiendraient tous deux la même plage de ports.

## Kubernetes : la chart Helm

`charts/zimmplayer` déploie la stack entière — front, API, MariaDB et
snapserver — en un `helm install`. Le **stockage S3 reste extérieur**, comme
pour le compose.

```bash
helm install zimmplayer charts/zimmplayer \
  --namespace zimmplayer --create-namespace \
  --set publicBaseUrl=http://musique.maison.lan \
  --set s3.endpoint=http://192.168.10.10:9000 \
  --set s3.accessKey=zimmplayer-reader \
  --set s3.secretKey=une-cle-secrete-dediee \
  --set mariadb.rootPassword=... \
  --set mariadb.password=... \
  --set mariadb.persistence.storageClass=longhorn
```

Les valeurs sans défaut possible font **échouer l'installation** avec un
message qui les nomme, plutôt que de démarrer une stack qui ne lira rien :
`publicBaseUrl`, `s3.endpoint`, `s3.accessKey`, `s3.secretKey`,
`mariadb.rootPassword`, `mariadb.password`.

### Classe de stockage

Deux volumes, chacun avec sa classe :

| Valeur | Volume | Défaut |
|---|---|---|
| `mariadb.persistence.storageClass` | la base | classe par défaut du cluster |
| `api.persistence.storageClass` | les pochettes extraites | classe par défaut du cluster |

Trois formes sont acceptées :

- **vide** — la classe par défaut du cluster ;
- **`"-"`** — *aucune* classe (`storageClassName: ""`), pour lier un PV créé à
  la main. C'est le cas des clusters sans provisionneur dynamique, où laisser
  la valeur vide laisserait le PVC en `Pending` sans expliquer pourquoi ;
- **un nom** — cette classe-là.

**Aucun des deux volumes n'est effacé par `helm uninstall`** — vérifié : les
deux PVC sont toujours là après désinstallation. Celui des pochettes porte
`helm.sh/resource-policy: keep` (elles se régénèrent depuis le bucket, mais un
scan complet coûte cher) ; celui de la base vient d'un `volumeClaimTemplate`,
que Kubernetes ne ramasse pas avec le StatefulSet.

C'est rassurant pour une mise à jour, et **piégeux pour une réinstallation** :
réinstaller sous le même nom de release reprend la base d'avant. Pour repartir
d'une base vierge, supprimer les PVC explicitement.

### Sondes

| Composant | Vivacité | Disponibilité |
|---|---|---|
| `api` | `/api/health/live` — ne touche pas la base | `/api/health/ready` — vérifie la base, 503 sinon |
| `web` | `/healthz` — aucun upstream | `/healthz` |
| `mariadb` | `healthcheck.sh --connect` | `healthcheck.sh --connect --innodb_initialized` |
| `snapserver` | HTTP sur 1780 | port audio 1704 ouvert |

Les deux dissociations ne sont pas décoratives :

- l'API garde une vivacité **aveugle à la base**. Sinon une panne de MariaDB
  la ferait tuer et redémarrer en boucle, sans jamais rien réparer, et en
  l'empêchant de reprendre au retour de la base. Vérifié sur cluster : base
  arrêtée, le pod passe `0/1` et sort du Service, **`RESTARTS` reste à 0**, et
  il redevient prêt tout seul quand la base revient ;
- le front ne consulte **aucun upstream**. Lier son état à celui de l'API
  ferait disparaître l'interface à chaque panne de l'API — alors que c'est
  précisément elle qui sait afficher l'erreur ;
- MariaDB distingue « le serveur répond » de « il peut servir des requêtes » :
  une récupération InnoDB longue satisfait le premier et pas le second. Une
  vivacité sur le second tuerait une base en train de se réparer.

Une sonde de démarrage (`startupProbe`) couvre les migrations Alembic, qui
tournent **avant** uvicorn : jusqu'à cinq minutes, sans que les deux autres
sondes ne s'en mêlent.

### Réglages courants

| Valeur | Rôle | Défaut |
|---|---|---|
| `image.tag` | version des images `back`/`front` | `appVersion` de la chart |
| `web.replicaCount` | replicas du front (sans état) | `2` |
| `ingress.enabled`, `ingress.host`, `ingress.className` | exposition HTTP | désactivé |
| `snapcast.enabled` | déployer snapserver | `true` |
| `snapcast.tag` | tag de l'image snapserver | `amd64-latest` |
| `snapcast.service.type` | joignabilité du port 1704 | `ClusterIP` |
| `oidc.*`, `superAdmins` | identité, voir plus haut | désactivé |
| `tls.existingSecret` / `tls.existingConfigMap` | autorité interne, montée dans `api` et `web` | aucune |

Ce que la chart **n'expose pas**, volontairement : le nombre de replicas de
l'API et de snapserver. Tous deux gardent leur état en mémoire du processus ;
proposer le réglage laisserait croire qu'on peut les mettre à l'échelle.

### Trois pièges

- **`s3.endpoint` doit être résolvable depuis le cluster.** nginx refuse de
  démarrer si l'hôte d'un upstream ne résout pas : les pods `web` partiraient
  en `CrashLoopBackOff`, avec pour seul indice un `host not found in upstream`
  dans les journaux. Une adresse IP est le choix sûr.
- **`publicBaseUrl` doit être l'adresse exacte tapée par les utilisateurs**,
  port compris — c'est la cause de loin la plus probable d'une lecture qui ne
  démarre pas. Avec un Ingress, `ingress.host` doit s'y accorder.
- **Les snapclients physiques du réseau doivent joindre le port 1704** du
  service snapserver. Il est en `ClusterIP` par défaut, donc injoignable hors
  du cluster : passer `snapcast.service.type` à `LoadBalancer` ou `NodePort`.

Redémarrer snapserver seul lui fait perdre les flux enregistrés par l'API ;
un `kubectl rollout restart deploy/<release>-zimmplayer-api` les réinscrit
tous.

### Image de snapserver

`rfabri/snapserver` (Rogger Fabri), snapserver **0.35**. Deux particularités :

- elle ne publie **ni tag `latest` ni manifeste multi-architecture** : le tag
  porte l'architecture. `amd64-latest` par défaut, `arm64v8-latest` sur
  Raspberry Pi ;
- la syntaxe du fichier de configuration a changé depuis la 0.29 : `[tcp]` est
  devenu `[tcp-control]`, et le port audio a sa propre section
  `[tcp-streaming]`. La `ConfigMap` de la chart est écrite pour la 0.35 —
  recopier telle quelle une configuration 0.29 ne marcherait pas.

## Livrable pour un réseau airgap

Depuis un poste **connecté** :

```bash
bash scripts/bundle_airgap.sh
```

Tire les cinq images (`zimmplayer-front`, `zimmplayer-back`, `snapserver`,
`mariadb`, `minio`) — `FRONT_TAG`/`BACK_TAG`/`SNAP_TAG` en variables
d'environnement pour choisir une version précise plutôt que `latest` — et
produit `dist-airgap/` : les images exportées (`images.tar.gz`),
`docker-compose.yml`, `.env.example`, la chart Helm (`charts/`), et un
`INSTALL.md` prêt à suivre sur la cible. Transférer tout le dossier, puis sur
la cible :

```bash
gunzip -c images.tar.gz | docker load
cp .env.example .env    # éditer PUBLIC_BASE_URL et les mots de passe
docker compose up -d
```

Pour une cible **Kubernetes**, l'`INSTALL.md` généré décrit la même chose avec
la chart. Attention : `docker load` ne suffit alors pas, sauf si le cluster
tourne sous Docker — les images doivent entrer dans le runtime de *chaque*
nœud (`ctr -n k8s.io images import`), ou passer par un registre interne.

## Ce qui n'est volontairement pas ici

Les scripts de vérification (`check_scan.sh`, `check_queue.sh`,
`check_snapcast.sh`) et le générateur de bibliothèque de test
(`seed_minio.py`) ne sont pas repris dans ce dépôt : ce sont des outils de
développement qui exigent le code source du backend et sa stack de dev
(`docker-compose.dev.yml`), pas seulement les images publiées. Les inclure ici
aurait été trompeur — ils ne fonctionneraient pas sans ce contexte.

## Licence

MIT, voir [`LICENSE`](./LICENSE).
