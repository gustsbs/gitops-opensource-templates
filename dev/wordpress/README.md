# wordpress (equipe `dev`)

Imagens **sem código** dos sites WordPress: um conjunto de imagens atende
todos os sites, cada um com o próprio volume e banco.

| Imagem | Papel | Usuário / porta |
|---|---|---|
| `php-wordpress` | PHP-FPM + `php.ini` de produção + pool dimensionado | 33 no Pod / 9000 |
| `nginx-wordpress` | servidor web com regras de segurança do WordPress | 101 / 8080 |
| `redis-wordpress` | object cache sem persistência | redis / 6379 |

## Modalidade validada

Core, plugins, temas e uploads ficam no **volume do site** (NFS, RWX) e são
atualizados pelo wp-admin. A imagem garante o runtime padronizado (versão do
PHP, extensões, limites e regras do nginx) para todos os sites, e o GitOps
garante a configuração declarativa de cada site.

Por isso `opcache.validate_timestamps=1` (o código muda no volume) e o nginx
bloqueia PHP em `wp-content/uploads`, `xmlrpc.php` e arquivos ocultos.

## Atualização

Mudou um Dockerfile ou arquivo de `confs/`: gere a imagem com nova revisão
(`<versão-upstream>-v<X.Y>`) e troque o `newTag` em `base/kustomization.yaml`
do `infra/gitops-wordpress`. Todos os sites recebem a mudança pelo Argo CD.
