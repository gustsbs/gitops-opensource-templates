# docker-base-images (equipe `dev`)

Imagens **base genéricas** (php-fpm, nginx, redis), sem código de aplicação.
Cada sistema (`dev/glpi`, `dev/wordpress`) tem o próprio Dockerfile `FROM`
destas bases.

| Imagem | Origem | Usuário / porta | Observações |
|---|---|---|---|
| `php` | `php:8.5-fpm-alpine` | `www-data` (82) / 9000 | extensões mysqli, pdo_mysql, gd, zip, exif, intl, mbstring, bcmath, ldap, redis (PECL com versão fixa); `/fpm-ping` para as probes |
| `nginx` | `nginxinc/nginx-unprivileged:1.30-alpine` (ramo stable) | `nginx` (101) / 8080 | perfis de configuração em `/opt/nginx-confs/` (não ativados na base) |
| `redis` | `redis:8-alpine` | `redis` / 6379 | perfis em `/opt/redis-confs/` |

## Premissas de execução

- Compatíveis com `runAsNonRoot` e `readOnlyRootFilesystem: true`: montar
  `emptyDir` em `/tmp` (php e nginx) e em `/var/cache/nginx` (nginx).
- `opcache.validate_timestamps=0`: o código só muda com uma imagem nova.
  Imagens cujo código fica num volume gravável (ex.: `php-wordpress`) trocam
  para `1`.
- O redis roda sem senha (`protected-mode no`): o isolamento é feito pela
  **NetworkPolicy** do namespace, que é obrigatória.

## Versionamento

Tag da imagem: `<versão-upstream>-v<X.Y>` (ex.: `8.5.12-fpm-alpine-v1.0`).
A revisão `v<X.Y>` reinicia em `v1.0` a cada versão nova do upstream. A tag
de versão nunca é sobrescrita: correção gera nova revisão. O commit de
origem vai no label `org.opencontainers.image.revision`.

```bash
docker build --platform linux/amd64 \
  --label org.opencontainers.image.revision=$(git rev-parse HEAD) \
  -t registry.exemplo.edu.br/dev/docker-base-images/php:8.5.12-fpm-alpine-v1.0 php
docker push registry.exemplo.edu.br/dev/docker-base-images/php:8.5.12-fpm-alpine-v1.0
```

Fixe o `FROM` por digest (`@sha256:...`) para builds reprodutíveis:

```bash
docker buildx imagetools inspect php:8.5.12-fpm-alpine | grep -m1 Digest
```
