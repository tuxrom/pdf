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
- Architecture **x86_64 / amd64**
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

## Publication de l'image (CI)

Le workflow [`.github/workflows/docker-publish.yml`](.github/workflows/docker-publish.yml)
construit et pousse l'image sur `ghcr.io/tuxrom/pdf` :

- à chaque push sur `main` → tags `latest` et `sha-<commit>`
- à chaque tag `vX.Y.Z` → tags `X.Y.Z` et `X.Y`

Pour publier une version :

```bash
git tag v1.0.0
git push origin v1.0.0
```

## Licence

Projet dérivé de BentoPDF, distribué sous licence **AGPL-3.0**. Si l'application est
proposée à des utilisateurs via un réseau, le code source modifié doit leur rester
accessible (ce dépôt public remplit cette obligation).
