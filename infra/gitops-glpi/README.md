# gitops-glpi (equipe `infra`)

Manifestos declarativos do GLPI em três ambientes, aplicados pelo Argo CD.

```
gitops/
├── base/            igual nos 3 ambientes: Deployment (php-glpi + nginx-glpi),
│                    CronJob, Service, Redis + NetworkPolicy, ConfigMaps, pool do PHP-FPM
└── overlays/
    ├── teste/       namespace, Ingress, SealedSecrets, caminho do volume e tags
    ├── homologa/
    └── producao/
ci/                  Jenkinsfiles de promoção e scripts usados pelo CI
scripts/             geração dos SealedSecrets
```

As imagens ficam sem tag na base. Cada overlay define só o `newTag`:

```yaml
images:
  - name: registry.exemplo.edu.br/dev/glpi/php-glpi
    newTag: 11.0.11-v1.0
```

## Premissas

- Banco de dados **externo** ao cluster (MySQL/MariaDB/Percona), informado no
  `config_db.php` selado.
- `files/` do GLPI em volume persistente compartilhado (no exemplo, NFS).
- Sealed Secrets instalado no cluster; TLS termina antes do ingress.

## Fluxo das imagens (CI + Argo CD)

A imagem é construída uma vez e promovida **sem rebuild**: o mesmo digest
passa por teste, homologação e produção.

| Etapa | Job | O que faz | Quem decide |
|---|---|---|---|
| Teste | `dev/glpi` → `Jenkinsfile` | build (tag `<versão>-build-N`) e commit em `overlays/teste` | automático; Argo CD aplica (selfHeal) |
| Homologação | `ci/Jenkinsfile.promover-homologa` (`VERSAO_PHP`, `VERSAO_NGINX` opcional) | copia a candidata do teste para a tag de versão no registry (mesmo digest, nunca sobrescreve) e abre MR em `overlays/homologa` | merge do MR (dev ou infra) |
| Produção | `ci/Jenkinsfile.promover-producao` | lê as tags da homologação, recusa candidatas `-build-`, confere as imagens e abre MR em `overlays/producao` | aprovação da infra (CODEOWNERS) e Sync manual no Argo CD |

O CI não acessa o cluster e não grava na `main` de homologação ou produção:
só publica imagens e abre MRs. Rollback: reverter o MR e sincronizar.

`ci/abrir-mr.sh` usa *push options* do GitLab para criar o MR; em outra
forja (GitHub, Gitea), troque esse trecho pela CLI ou API correspondente.

## Segredos (Sealed Secrets)

Cada cluster tem seu par de chaves: um SealedSecret selado para um cluster
não abre em outro. Os arquivos `sealed-*.yaml` dos overlays são **exemplos**
e precisam ser gerados no seu cluster:

```bash
kubectl config use-context <cluster-de-destino>
cp gitops/config_db.php.example gitops/overlays/teste/config_db.php   # preencha
php -r 'echo sodium_crypto_secretbox_keygen();' > gitops/overlays/teste/glpicrypt.key  # instalação nova
./scripts/seal-config-secrets.sh teste
./scripts/seal-oauth-keys.sh teste --generate
rm gitops/overlays/teste/config_db.php gitops/overlays/teste/glpicrypt.key
```

O `glpicrypt.key` precisa ser o mesmo que cifrou os dados do banco usado
pelo overlay (em migração, reaproveite a chave existente).
