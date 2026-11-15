# gitops-wordpress (equipe `infra`)

Um repositório para **todos** os sites WordPress: uma base comum e um overlay
por site. Cada site roda em namespace próprio (`<slug>-prod`), com o seu
volume, o seu banco e o seu Redis.

```
base/                 Deployment (nginx-wordpress + php-wordpress), Service,
                      Redis + NetworkPolicy; tags das imagens de TODOS os sites
components/
└── tema-somente-leitura/   temas institucionais vindos de uma imagem, montados readOnly
overlays/
├── site-exemplo-prod/      site simples: PV/PVC NFS, Ingress, patch do volume
└── portal-multisite-prod/  multisite em subdiretórios + temas somente leitura
scripts/
└── novo-site-overlay.sh    gera o overlay de um site novo
```

## Novo site

```bash
./scripts/novo-site-overlay.sh meusite meusite.exemplo.edu.br 192.0.2.10
git add overlays/meusite-prod
git commit -m "feat(meusite-prod): adicionar o site meusite.exemplo.edu.br"
```

O ApplicationSet (`infra/argocd/applicationsets/wordpress.yaml`) cria a
Application `wordpress-meusite-prod` a partir da pasta nova.

## Atualizar todos os sites

Troque o `newTag` em `base/kustomization.yaml`. Como a versão está na base,
uma mudança revisada em um único commit chega a todos os sites, e reverter o
commit desfaz a mudança no parque inteiro.

## Premissas

- O volume de cada site (NFS, `ReadWriteMany`) contém core, plugins, temas,
  uploads e `wp-config.php`, com dono `33:33`; o nginx (uid 101) precisa de
  leitura (ACL ou grupo).
- Banco de dados externo ao cluster, configurado no `wp-config.php` do site.
- TLS termina antes do ingress (balanceador); o Ingress de cada site fica
  versionado no overlay.
- `wordpress-regcred` (pull das imagens) existe no namespace, se o registry
  for privado.
