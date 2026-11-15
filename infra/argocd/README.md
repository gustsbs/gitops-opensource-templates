# argocd (equipe `infra`)

Declaração do que o Argo CD gerencia. Aplicado uma vez por `kubectl apply`
(ou por uma Application "app of apps").

| Pasta | Conteúdo |
|---|---|
| `projects/` | AppProjects: limitam repositório de origem, namespaces de destino e recursos de cluster |
| `applications/glpi/` | uma Application por ambiente; teste com sync automático, homologação e produção manuais |
| `applicationsets/wordpress.yaml` | uma Application por pasta `overlays/*-prod` do gitops-wordpress |
| `image-updater/` | atualização automática da imagem de temas (opcional) |

```bash
kubectl apply -f projects/
kubectl apply -f applications/glpi/
kubectl apply -f applicationsets/
```

## Por que ApplicationSet no WordPress

Com centenas de sites, manter uma Application e uma entrada no AppProject por
site vira trabalho manual e fonte de erro. O gerador `git directories` faz do
repositório a única fonte: criar ou remover um overlay basta para o Argo CD
criar ou remover a Application. No GLPI, com três ambientes fixos e políticas
de sync diferentes, Applications explícitas são mais claras.
