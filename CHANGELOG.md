# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/);
versões seguem [Versionamento Semântico](https://semver.org/lang/pt-BR/).

## [Não lançado]

## [1.0.0] - 2026-11-20

### Adicionado
- Imagens base (php-fpm, nginx, redis) e imagens de aplicação do GLPI e do WordPress (`dev/`).
- Manifestos GitOps do GLPI (teste, homologação, produção) com promoção de imagens sem rebuild (`infra/gitops-glpi`).
- Manifestos GitOps do WordPress: base comum, overlay por site, multisite e temas somente leitura (`infra/gitops-wordpress`).
- AppProjects, Applications, ApplicationSet e Image Updater do Argo CD (`infra/argocd`).
- Validação automática: kustomize + kubeconform e shellcheck.
- `ferramentas/personalizar.sh`: troca os valores de exemplo (domínios dos Ingress, registry, Git, NFS, SMTP) pelos da instituição.
- Laboratório local em MicroK8s (`laboratorio/`): overlays que reaproveitam os templates, MariaDB simulando o banco externo, segredos selados e Argo CD lendo o Git.
- `laboratorio/coletar-evidencias.sh`: relatório da validação (estado das Applications, segredos selados, resposta HTTP e testes de drift cronometrados).

[Não lançado]: https://github.com/gustsbs/gitops-opensource-templates/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/gustsbs/gitops-opensource-templates/releases/tag/v1.0.0
