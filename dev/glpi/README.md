# glpi (equipe `dev`)

Imagens do GLPI separadas em dois containers do mesmo Pod:

| Imagem | Conteúdo | Usuário / porta |
|---|---|---|
| `php-glpi` | PHP-FPM + código do GLPI + plugins homologados (`downloads.sh`) | uid 33 no Pod / 9000 |
| `nginx-glpi` | nginx unprivileged com a configuração do GLPI, **sem código** | 101 / 8080 |

O nginx recebe `public/` por um `emptyDir` semeado por um initContainer a
partir da `php-glpi` (ver `infra/gitops-glpi`). Assim o código existe em um
único artefato versionado.

## Decisões

- **Código imutável**: dono `root`, somente leitura; o GLPI grava apenas em
  `files/` (volume persistente). `GLPI_MARKETPLACE_ENABLE=0` no GitOps impede
  instalar plugins pela loja: plugin novo entra pelo `downloads.sh`.
- **Uma imagem para todos os ambientes**: a mesma lista de plugins em teste,
  homologação e produção; o que fica ativo é decidido no próprio GLPI. Isso
  permite promover o mesmo digest sem rebuild.
- **Configuração e segredos fora da imagem**: `config_db.php`,
  `glpicrypt.key` e as chaves OAuth chegam por SealedSecret; `php.ini` por
  ConfigMap (`PHP_INI_SCAN_DIR`).

## Fluxo de CI

1. Commit na `main` deste repositório → `Jenkinsfile` constrói as duas
   imagens com a tag `<versão>-v<X.Y>-build-<N>` e grava a tag em
   `gitops/overlays/teste` do `infra/gitops-glpi`.
2. O Argo CD sincroniza o teste automaticamente.
3. Homologação e produção: ver `infra/gitops-glpi/README.md`.

## Build local

```bash
docker build --pull -f docker/php/Dockerfile -t php-glpi:dev .
docker build -f docker/nginx/Dockerfile \
  --build-arg BASE_IMAGE=nginxinc/nginx-unprivileged:1.30.6-alpine \
  -t nginx-glpi:dev docker/nginx
```
