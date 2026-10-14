# Déploiement de Logis PDF

Logis PDF est une version personnalisée de [BentoPDF](https://github.com/alam00000/bentopdf)
(logo Logis, interface épurée). Tous les traitements PDF se font **dans le navigateur** :
le serveur ne fait que servir des fichiers statiques via nginx, aucun fichier n'est envoyé.

L'image Docker est publiée automatiquement sur GitHub Container Registry :

```
ghcr.io/tuxrom/pdf:latest
```

## Prérequis

- Docker Engine 24+ avec le plugin `docker compose`
- Architecture **x86_64 / amd64** ou **arm64** (Raspberry Pi 4/5, serveurs ARM) : l'image est multi-arch
- Un port libre sur l'hôte (8080 par défaut)

## Déploiement rapide

```bash
mkdir logis-pdf && cd logis-pdf
curl -O https://raw.githubusercontent.com/tuxrom/pdf/main/compose.yaml
docker compose up -d
```

L'application est alors disponible sur `http://<serveur>:8080`.

Sans compose :

```bash
docker run -d --name logis-pdf --restart unless-stopped -p 8080:8080 ghcr.io/tuxrom/pdf:latest
```

## Configuration

Variables d'environnement (à l'exécution) :

| Variable         | Défaut  | Rôle                                                                   |
| ---------------- | ------- | ---------------------------------------------------------------------- |
| `PORT`           | `8080`  | Port d'écoute de nginx dans le conteneur                               |
| `DISABLE_IPV6`   | `false` | `true` si l'hôte n'a pas d'IPv6 (sinon nginx peut refuser de démarrer) |
| `ROBOTS_NOINDEX` | `false` | `true` pour interdire l'indexation par les moteurs de recherche        |

Pour changer le port exposé, modifier la ligne `ports` du `compose.yaml`, par exemple `'80:8080'`.

## Derrière un reverse proxy (HTTPS)

L'application a besoin des en-têtes `Cross-Origin-Opener-Policy` et
`Cross-Origin-Embedder-Policy` (envoyés par le nginx du conteneur) pour certains outils
utilisant WebAssembly. Le reverse proxy doit les **laisser passer** sans les écraser.

Exemple nginx :

```nginx
server {
    listen 443 ssl;
    server_name pdf.example.fr;

    ssl_certificate     /etc/ssl/certs/pdf.example.fr.pem;
    ssl_certificate_key /etc/ssl/private/pdf.example.fr.key;

    client_max_body_size 0;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

Exemple Traefik (labels à ajouter au service dans `compose.yaml`) :

```yaml
labels:
  - traefik.enable=true
  - traefik.http.routers.logis-pdf.rule=Host(`pdf.example.fr`)
  - traefik.http.routers.logis-pdf.entrypoints=websecure
  - traefik.http.routers.logis-pdf.tls.certresolver=letsencrypt
  - traefik.http.services.logis-pdf.loadbalancer.server.port=8080
```

> HTTPS est fortement recommandé : plusieurs API du navigateur utilisées par les outils
> (service worker, WebAssembly multithread) ne fonctionnent qu'en contexte sécurisé
> (HTTPS ou `localhost`).

## Mise à jour

```bash
docker compose pull
docker compose up -d
```

## Construire l'image soi-même

Depuis un clone du dépôt :

```bash
git clone https://github.com/tuxrom/pdf.git
cd pdf
docker compose -f compose.build.yaml up -d --build
```

Options de build utiles (`--build-arg` ou section `args` de `compose.build.yaml`) :

| Argument                | Rôle                                                                           |
| ----------------------- | ------------------------------------------------------------------------------ |
| `VITE_DEFAULT_LANGUAGE` | Langue par défaut de l'interface (`fr`, `en`, …). Sinon : langue du navigateur |
| `BASE_URL`              | Servir l'application dans un sous-dossier, ex. `/pdf/`                         |
| `DISABLE_TOOLS`         | Liste d'outils à masquer, séparés par des virgules                             |

La compilation demande environ 4 Go de RAM.

## Publication de l'image

L'image `ghcr.io/tuxrom/pdf` est **multi-arch** : `docker pull` choisit automatiquement
la bonne version (amd64 ou arm64). Elle est assemblée à partir de deux tags :

| Tag      | Construit par                    | Quand                         |
| -------- | -------------------------------- | ----------------------------- |
| `:amd64` | GitHub Actions                   | automatiquement à chaque push |
| `:arm64` | Raspberry Pi (script ci-dessous) | manuellement                  |

### amd64 (CI)

Le workflow [`.github/workflows/docker-publish.yml`](.github/workflows/docker-publish.yml) :

- construit et pousse `:amd64` (et `:sha-<commit>-amd64`) à chaque push sur `main` ;
- recrée le manifeste `:latest` = `:amd64` + `:arm64` (si `:arm64` existe) ;
- sur un tag `vX.Y.Z`, publie aussi `X.Y.Z` et `X.Y`.

```bash
git tag v1.0.0
git push origin v1.0.0
```

### arm64 (Raspberry Pi)

Le contenu compilé (`dist/`) est identique quelle que soit l'architecture. On le compile
sur un PC (environ 4 Go de RAM nécessaires, trop pour un Pi à 2 Go), puis le Pi assemble
seulement l'image nginx arm64 avec [`Dockerfile.prebuilt`](Dockerfile.prebuilt).

Une seule fois, sur le Pi, se connecter au registre avec un token GitHub ayant le droit
`write:packages` (GitHub → Settings → Developer settings → Personal access tokens) :

```bash
docker login ghcr.io -u tuxrom
```

Puis, depuis le PC (Git Bash), à la racine du dépôt :

```bash
scripts/build-arm64-pi.sh
```

Le script compile, envoie `dist/` au Pi (`PI_HOST`, par défaut `pi@192.168.31.118`), y
construit et pousse `:arm64`, puis met à jour `:latest`. L'option `--skip-build` réutilise
un `dist/` déjà compilé.

> La version arm64 n'est mise à jour que lorsque ce script est relancé : après des
> modifications du code, le relancer pour garder les deux architectures alignées.

## Licence

Projet dérivé de BentoPDF, distribué sous licence **AGPL-3.0**. Si l'application est
proposée à des utilisateurs via un réseau, le code source modifié doit leur rester
accessible (ce dépôt public remplit cette obligation).
