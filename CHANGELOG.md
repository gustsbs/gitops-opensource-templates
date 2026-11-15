# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/);
versões seguem [Versionamento Semântico](https://semver.org/lang/pt-BR/).

## [Não lançado]

### Adicionado
- Imagens base (php-fpm, nginx, redis) e imagens de aplicação do GLPI e do WordPress (`dev/`).
- Manifestos GitOps do GLPI (teste, homologação, produção) com promoção de imagens sem rebuild (`infra/gitops-glpi`).
- Manifestos GitOps do WordPress: base comum, overlay por site, multisite e temas somente leitura (`infra/gitops-wordpress`).
- AppProjects, Applications, ApplicationSet e Image Updater do Argo CD (`infra/argocd`).
- Validação automática: kustomize + kubeconform e shellcheck.
- `ferramentas/personalizar.sh`: troca os valores de exemplo (domínios dos Ingress, registry, Git, NFS, SMTP) pelos da instituição.
