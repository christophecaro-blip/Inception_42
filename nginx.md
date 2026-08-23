# Ressources pour le conteneur nginx

## Documentation officielle NGINX
`nginx.org/en/docs/` — en particulier :
- **`ngx_http_ssl_module`** — pour configurer `ssl_protocols` (TLSv1.2/1.3, exige par le sujet), `ssl_certificate`, `ssl_certificate_key`.
- **`ngx_http_fastcgi_module`** — nginx ne fait pas un simple reverse-proxy HTTP vers WordPress. PHP-FPM parle le protocole **FastCGI**, pas HTTP — c'est `fastcgi_pass` qu'il faut, pas `proxy_pass`.

## Le certificat TLS
Pas de certificat public signe possible (domaine local `login.42.fr`) — il faut un certificat **auto-signe**, via `openssl` (generation de cle/certificat). Chercher sa doc pour comprendre chaque parametre (duree de validite, algorithme, CN...) plutot que de copier une commande toute faite.

## La page du paquet Alpine
`pkgs.alpinelinux.org/package/v3.23/main/x86_64/nginx` (adapter la version) — pour voir les chemins par defaut reels sur Alpine (`/etc/nginx/...`), differents de ceux montres dans des tutos Debian/Ubuntu.

## La doc embarquee
Une fois le paquet installe : `nginx -h`, et le fichier de conf par defaut copie par le paquet (regarder son contenu tel quel dans le conteneur) — fidele a la version exacte utilisee.

## Piege a eviter
Ne pas copier le `docker-entrypoint.sh`/la conf de l'image officielle `nginx` sur Docker Hub — potentiellement pensee pour Debian, et le but est de comprendre sa propre conf, pas d'adapter quelque chose de non compris.

https://www.ionos.fr/digitalguide/serveur/configuration/tutoriel-nginx-premiers-pas-avec-nginxconf/

https://blog.stephane-robert.info/docs/services/web/nginx/

Un URI (Uniform Resource Identifier, ou Identifiant Uniforme de Ressource) est une courte suite de caractères qui sert à identifier une ressource de manière unique sur un réseau comme Internet. Il regroupe sous un même terme général l'adresse pour trouver un site (URL) et le nom officiel d'un objet (URN).Les deux types d'URIURL (Uniform Resource Locator) : Indique où se trouve la ressource sur le Web et comment y accéder (par exemple, une page web ou une image).URN (Uniform Resource Name) : Donne un nom fixe et unique à une ressource sans dire où elle se trouve (comme le numéro ISBN d'un livre).Rôle et UtilisationPermet de lier des documents et des fichiers entre eux.Sert de cible pour les requêtes des programmes informatiques et des navigateurs.Peut lancer des actions précises (ouvrir un e-mail, exécuter un script).

Test du serveur avec curl:

    curl -I http://localhost

- Si certificat auto-signe -> rejet car certificat non officel

Pour forcer, ajouter -k(--insecure)

    curl -Ik https://localhost

Attention : le conteneur n'ecoute qu'en HTTPS (port 443, `listen 443 ssl;`) — une requete en `http://` (port 80 par defaut) echoue avec `Could not connect to server`, c'est attendu.

# Le Dockerfile

```dockerfile
FROM alpine:3.23

COPY conf/nginx.conf /etc/nginx/http.d/default.conf

RUN apk update && apk upgrade && apk add --no-cache \
    vim \
    nginx \
    openssl \
    curl && \
    mkdir -p /etc/nginx/ssl && \
    openssl req -x509 -nodes -out /etc/nginx/ssl/inception.crt -keyout /etc/nginx/ssl/inception.key -subj "/C=FR/ST=IDF/L=Marseille/O=42/OU=42/CN=ccaro.42/UID=ccaro" && \
    mkdir -p /var/run/nginx && \
    mkdir -p /var/www/html && \
    chmod +rwx /var/www/html && \
    chown -R nginx:nginx /var/www/html

EXPOSE 443

ENTRYPOINT ["nginx", "-g", "daemon off;"]
```

## `COPY conf/nginx.conf /etc/nginx/http.d/default.conf`
Contrairement au reflexe initial (copier vers `/etc/nginx/nginx.conf`, le fichier de conf **principal**), la conf specifique au site va dans `/etc/nginx/http.d/`. Teste et confirme : le `nginx.conf` par defaut d'Alpine contient deja les blocs `events{}`/`http{}` necessaires, et se termine par `include /etc/nginx/http.d/*.conf;` — donc tout fichier `.conf` place dans ce dossier est automatiquement inclus **a l'interieur** du bon contexte `http{}`. Ecraser `nginx.conf` directement avec un bloc `server{}` seul provoque l'erreur `"server" directive is not allowed here` (`server` n'est valide qu'a l'interieur d'un bloc `http{}`, jamais au premier niveau du fichier).

## L'ordre des commandes dans le `RUN` (teste, deux bugs corriges)
1. **`mkdir -p /etc/nginx/ssl` doit venir avant `openssl req`** — sinon `openssl` echoue avec `Can't open "/etc/nginx/ssl/inception.key" for writing, No such file or directory`, puisqu'il essaie d'ecrire dans un dossier qui n'existe pas encore. Meme logique que pour `/run/mariadbd` dans le Dockerfile mariadb.
2. **Chaque commande doit etre reliee par `&&`**, jamais juste par un `\` de continuation de ligne sans `&&`/`;`. Teste : sans `&&` entre `openssl req ...` et `mkdir -p /var/run/nginx`, le shell interprete `mkdir`, `-p`, `/var/run/nginx`, etc. comme des **arguments supplementaires de `openssl req`**, qui ne les reconnait pas (`req: Extra option: "mkdir"`) et echoue.
3. **`mkdir -p /var/www/html` est necessaire avant le `chmod`/`chown`** sur ce meme chemin — Alpine ne le cree pas par defaut (son docroot par defaut reel est `/var/lib/nginx/html`, pas `/var/www/html` — encore une difference avec les tutos penses pour Debian).

## `chown -R nginx:nginx` (pas `www-data`)
Piege classique (deja vu plusieurs fois pour mariadb) : les tutos Debian/Ubuntu utilisent l'utilisateur `www-data`, qui **n'existe pas** sur Alpine. Verifie : le paquet `nginx` cree un utilisateur systeme `nginx` (`nginx:x:100:101:nginx:/var/lib/nginx:/sbin/nologin`), c'est lui qu'il faut utiliser pour `chown`.

## `ENTRYPOINT ["nginx", "-g", "daemon off;"]`
Forme **JSON/exec** (tableau entre crochets), pas la forme "shell". Cette forme execute `nginx` **directement**, sans passer par un shell intermediaire — donc pas besoin d'un `exec` explicite ici (contrairement a un script shell) : il n'y a pas de shell a remplacer, `nginx` est deja le process init du conteneur des le depart. Teste et confirme : `nginx` apparait bien en PID 1 (`nginx: master process`), les workers en dessous comme processus enfants normaux (architecture standard nginx, pas un doublon d'instance comme le probleme rencontre avec mariadb).

`-g "daemon off;"` est indispensable : par defaut, `nginx` se demonise tout seul (part en arriere-plan) — ce flag l'en empeche, pour qu'il reste au premier plan et puisse etre PID 1.

Teste : `docker stop` s'arrete quasi instantanement (`SIGTERM` bien recu et gere par le master process).

# Le certificat TLS auto-signe

```sh
openssl req -x509 -nodes -out /etc/nginx/ssl/inception.crt -keyout /etc/nginx/ssl/inception.key -subj "/C=FR/ST=IDF/L=Marseille/O=42/OU=42/CN=ccaro.42/UID=ccaro"
```

- **`req`** — sous-commande de generation de requete de certificat (utilisee ici pour generer directement un certificat, pas juste une requete a signer par un tiers).
- **`-x509`** — au lieu de produire une requete de signature (CSR) a envoyer a une autorite, genere directement un certificat **auto-signe**, au format X.509 (le format standard des certificats TLS).
- **`-nodes`** ("no DES") — la cle privee generee n'est **pas chiffree** par un mot de passe. Necessaire ici : un serveur qui demarre seul (sans intervention humaine pour taper une passphrase a chaque lancement) a besoin d'une cle immediatement utilisable.
- **`-out .../inception.crt`** — chemin de sortie du certificat public.
- **`-keyout .../inception.key`** — chemin de sortie de la cle privee associee.
- **`-subj "..."`** — fournit directement les informations d'identite du certificat (pays, region, ville, organisation, nom commun...) en ligne de commande, pour eviter le mode interactif (qui bloquerait le build, aucune saisie possible pendant un `docker build`).

Aucune duree de validite (`-days`) n'est precisee ici — openssl utilise sa valeur par defaut (verifier avec `openssl req -help` quelle est cette valeur par defaut sur cette version precise, plutot que de la supposer).

Comme ce certificat n'est signe par aucune autorite reconnue, tout client qui verifie la chaine de confiance par defaut (comme `curl` sans option) le rejette — comportement normal, pas un bug (cf section test avec curl plus haut, `-k`/`--insecure` pour contourner volontairement en test).

# Le fichier `nginx.conf` (copie vers `http.d/default.conf`)

```nginx
server {
    listen 443 ssl;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_certificate /etc/nginx/ssl/inception.crt;
    ssl_certificate_key /etc/nginx/ssl/inception.key;

    root /var/www/html;
    server_name localhost;
    index index.php index.html index.htm;

    location / {
    try_files $uri $uri/ =404;
    }

    # location ~ \.php$ {
    #     include snippets/fastcgi-php.conf;
    #     fastcgi_pass wordpress:9000;
    # }
}
```

- **`listen 443 ssl;`** — ecoute uniquement sur le port 443, en HTTPS. Conforme a l'exigence du sujet (nginx = seul point d'entree, via 443 uniquement).
- **`ssl_protocols TLSv1.2 TLSv1.3;`** — restreint aux versions TLS exigees par le sujet (exclut les versions plus anciennes/moins sures comme TLSv1.0/1.1).
- **`ssl_certificate` / `ssl_certificate_key`** — pointent vers les fichiers generes par `openssl req` juste avant. Les chemins doivent correspondre exactement a ceux utilises dans le Dockerfile.
- **`root /var/www/html;`** — dossier racine des fichiers servis. Doit correspondre au dossier cree/chown dans le Dockerfile, et sera plus tard le point de montage du volume partage avec WordPress.
- **`index ...`** — fichier(s) recherche(s) par defaut quand une requete cible un dossier plutot qu'un fichier precis. `index.php` en premier, pour que WordPress (qui repose sur PHP) soit prioritaire sur un `index.html` statique s'il existe.
- **`location / { try_files $uri $uri/ =404; }`** — pour toute requete, cherche d'abord un fichier correspondant exactement (`$uri`), sinon un dossier (`$uri/`), sinon renvoie une 404. Standard pour un site avec fichiers statiques.
- **Le bloc `location ~ \.php$` (commente)** — future prise en charge des requetes PHP, a activer une fois WordPress branche. `fastcgi_pass wordpress:9000` enverra les requetes `.php` au conteneur wordpress via le protocole **FastCGI** (pas HTTP — php-fpm ne parle pas HTTP), sur le port 9000 (port standard de php-fpm), en utilisant `wordpress` comme nom d'hote — fonctionnera une fois les deux conteneurs sur le meme reseau Docker, grace a la resolution DNS interne par nom de service.

# Bugs rencontres et corriges (recapitulatif)

1. `USER mysql` (erreur de copier-coller depuis mariadb) — jamais eu besoin ici, retire.
2. `RUN ... vim && nginx &&` — `&&` errone entre deux noms de paquets au lieu d'un espace, transformait `nginx` en tentative de commande separee plutot qu'un second paquet a installer.
3. `\` de continuation de ligne trainant en fin de bloc `RUN`, avalant l'instruction `EXPOSE` suivante dans la meme commande shell (meme piege que sur le Dockerfile mariadb).
4. `ENTRYPOINT ["sh"]` (placeholder de debut de projet) — sans commande a executer, le conteneur demarrait et s'arretait aussitot (`exit code 0`, boucle de redemarrage) : rien ne le maintenait vivant.
5. `mkdir -p /etc/nginx/ssl` place apres `openssl req` au lieu d'avant.
6. Commandes `openssl`/`mkdir`/`chmod`/`chown` non reliees par `&&` — avalees comme arguments d'`openssl req`.
7. `mkdir -p /var/www/html` manquant avant le `chmod`/`chown` sur ce chemin.
8. `chown -R www-data:www-data` — utilisateur inexistant sur Alpine, corrige en `nginx:nginx`.
9. `COPY` vers `/etc/nginx/nginx.conf` (fichier principal) au lieu de `/etc/nginx/http.d/default.conf` — provoquait `"server" directive is not allowed here`.
10. `curl -I http:localhost` (`//` manquant) puis `curl -I http://localhost` (mauvais schema, port 80 au lieu de 443) — deux erreurs distinctes de commande de test, pas des bugs du conteneur lui-meme.
