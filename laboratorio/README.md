# Laboratório local (MicroK8s)

Reproduz o modelo inteiro numa única máquina: as imagens de `dev/` são
construídas localmente e o **Argo CD sincroniza os templates de `infra/` a
partir do repositório Git**, como em produção.

Os overlays daqui **reaproveitam os templates sem alterá-los**
(`resources: ../../infra/...`) e trocam só o que um laboratório não tem:

| Template | Laboratório |
|---|---|
| imagens em `registry.exemplo.edu.br` | build local, push para o registry do MicroK8s (`localhost:32000`, tag `lab`) |
| volume NFS | PVC do `hostpath-storage` |
| banco externo | MariaDB no namespace `lab-db`, simulando o servidor externo |
| SealedSecrets de exemplo | removidos; o script sela segredos novos com a chave do Sealed Secrets **deste** cluster |
| domínios `*.exemplo.edu.br` | `glpi.lab.localhost` e `site.lab.localhost` |
| — | Jobs de instalação (sync-wave `-1`): banco do GLPI (`db:install`) e arquivos do WordPress no volume |

## Pré-requisitos

- WSL 2 com systemd, MicroK8s (testado na série 1.32) e Docker no WSL.
- Repositório publicado no Git (o Argo CD lê `laboratorio/` e `infra/` de lá).

O script habilita os addons que faltarem (`dns`, `hostpath-storage`,
`ingress`, `registry`, `helm3`) e instala o `kubeseal`, o Sealed Secrets e o
Argo CD se ainda não existirem.

## Uso

```bash
laboratorio/laboratorio.sh tudo
```

Ou por etapas: `pre-requisitos`, `imagens`, `banco`, `segredos`, `argocd`
(ou `aplicar`, que aplica direto da pasta local, sem Argo CD), `testar` e
`tunel`. Para testar antes de publicar no Git: `tudo-local`. Para apagar:
`remover`.

Senhas, `glpicrypt.key` e chaves OAuth do laboratório ficam em
`~/.config/gitops-lab/` (fora do Git) e são reaproveitadas nas próximas
execuções.

## Acesso

No WSL em modo `mirrored`, o navegador do Windows só alcança portas com um
processo escutando; o ingress do MicroK8s usa `hostPort` (iptables). Abra o
túnel em outro terminal e deixe rodando:

```bash
laboratorio/laboratorio.sh tunel
```

| | Endereço | Acesso |
|---|---|---|
| GLPI | https://glpi.lab.localhost | aceite o certificado autoassinado; `glpi` / `glpi` (troque no primeiro acesso) |
| WordPress | http://site.lab.localhost | assistente de instalação do WordPress |
| Argo CD | `microk8s kubectl -n argocd port-forward svc/argocd-server 8443:443` → https://localhost:8443 | `admin` / senha do Secret `argocd-initial-admin-secret` |

Os nomes `*.localhost` apontam para a própria máquina nos navegadores
atuais, sem editar o arquivo `hosts` (que, aliás, é ignorado para esses
nomes). O GLPI usa HTTPS porque o template marca o cookie de sessão como
`Secure`, como em produção.

## O que fica validado

- As imagens de `dev/` constroem e rodam sem root (`runAsNonRoot`, nginx na 8080).
- Os manifestos de `infra/` são aplicados pelo Argo CD a partir do Git,
  com sync automático, *self-heal* e *prune*.
- O Sealed Secrets abre os segredos selados para o cluster.
- GLPI: initContainer que copia `public/`, probes `/healthz` e `/fpm-ping`,
  Redis isolado por NetworkPolicy, CronJob.
- WordPress: base + overlay de site, Redis, regras do nginx.

Para testar o *drift*: altere algo à mão (`microk8s kubectl -n glpi-lab
scale deploy glpi --replicas=0`) e veja o Argo CD desfazer a mudança.

## Evidências para a validação

Com o laboratório aplicado pelo Argo CD (etapa `argocd`):

```bash
laboratorio/coletar-evidencias.sh
```

Gera em `~/evidencias-gitops-lab/<data-hora>/` um `relatorio.md` com:

1. estado das Applications (revisão do Git sincronizada, sync, saúde e política);
2. recursos em execução, com imagem e digest de cada contêiner;
3. SealedSecrets e os Secrets abertos pelo controller;
4. resposta HTTP pelo ingress;
5. testes de *drift* cronometrados: alterações feitas direto no cluster
   (réplicas, ConfigMap, Service, Ingress, NetworkPolicy) e o tempo até o
   Argo CD restaurar o estado declarado no Git.

Os arquivos brutos (YAML das Applications, histórico de sincronização,
estado antes e depois de cada teste) ficam ao lado do relatório.
`--sem-drift` coleta só o estado, sem alterar nada.
