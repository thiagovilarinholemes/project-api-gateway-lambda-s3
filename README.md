# 🚀 Project API Gateway + Lambda + S3

Projeto de uma arquitetura serverless local utilizando **AWS API
Gateway**, **AWS Lambda**, **Amazon S3**, **IAM** e **LocalStack**.

O projeto simula localmente um fluxo completo de upload de arquivos:

``` text
      Cliente HTTP
           │
           │ POST /arquivos
           ▼
┌──────────────────────┐
│     API Gateway      │
│        REST          │
└──────────┬───────────┘
           │ AWS_PROXY
           ▼
┌──────────────────────┐
│        Lambda        │
│      Python 3.12     │
└──────────┬───────────┘
           │ s3:PutObject
           ▼
┌──────────────────────┐
│         S3           │
│ serverless-arquivos  │
└──────────────────────┘
```

## 📋 Sumário

- [🎯 Objetivo](#-objetivo)
- [🏗️ Arquitetura](#️-arquitetura)
- [🛠️ Tecnologias](#️-tecnologias)
- [📁 Estrutura do projeto](#-estrutura-do-projeto)
- [⚙️ Pré-requisitos](#️-pré-requisitos)
- [🐳 LocalStack](#-localstack)
- [🚀 Deploy](#-deploy)
- [🧪 Testes](#-testes)
- [🌐 API](#-api)
- [📦 Payload](#-payload)
- [🪣 S3](#-s3)
- [🔐 IAM](#-iam)
- [🧹 Destroy](#-destroy)
- [🐛 Troubleshooting](#-troubleshooting)
- [📌 Comandos úteis](#-comandos-úteis)
- [📦 Enviar arquivo](#-enviar-arquivo)
- [🎯 Resultado](#-resultado)
- [👨‍💻 Autor](#-autor)

## 🎯 Objetivo

Demonstrar, de forma prática, uma arquitetura serverless usando serviços
compatíveis com AWS executados localmente pelo LocalStack.

A aplicação recebe uma requisição HTTP contendo o nome e o conteúdo de
um arquivo. A função Lambda valida a requisição e grava o conteúdo em um
bucket S3.

## 🏗️ Arquitetura

``` text
POST /arquivos
      │
      ▼
API Gateway (REST)
      │ AWS_PROXY
      ▼
Lambda (Python 3.12)
      │ s3:PutObject
      ▼
S3: serverless-arquivos
```

**Responsabilidades**

- **API Gateway:** disponibiliza o endpoint HTTP `POST /arquivos`.
- **Lambda:** interpreta o JSON, valida os campos, normaliza o nome,
  grava o conteúdo no S3 e devolve uma resposta HTTP.
- **S3:** armazena os arquivos enviados.
- **IAM:** concede à Lambda a permissão necessária para executar
  `s3:PutObject`.

## 🛠️ Tecnologias

- Python 3.12
- AWS Lambda
- Amazon S3
- Amazon API Gateway (REST)
- AWS IAM
- AWS CLI
- LocalStack
- Docker e Docker Compose
- PowerShell

## 📁 Estrutura do projeto

``` text
project-api-gateway-lambda-s3/
├── docker-compose.yml
├── README.md
├── .env
├── .env.example
├── .gitignore
├── src/
│   └── lambda_function.py
├── events/
│   └── api-request.json
├── scripts/
│   ├── deploy.ps1
│   ├── invoke.ps1
│   └── destroy.ps1
├── tests/
│   └── test_lambda_function.py
└── build/
    ├── lambda-package/
    ├── lambda_function.zip
    ├── s3-policy.json
    └── trust-policy.json
```

> A estrutura acima documenta os arquivos esperados. A pasta `build/`
> contém artefatos gerados durante o build e o deploy; normalmente ela
> não deve ser versionada no Git.

## ⚙️ Pré-requisitos

Instale e configure:

- Docker Desktop com Docker Compose
- AWS CLI
- Python 3.12 ou compatível para preparar o pacote
- PowerShell
- Git (opcional, para versionamento)

## 🐳 LocalStack

O endpoint local utilizado pelo projeto é:

``` text
http://localhost:4566
```

O `docker-compose.yml` deve habilitar os serviços necessários, incluindo
`s3`, `lambda`, `apigateway`, `iam` e `sts`.

Iniciar o ambiente:

``` powershell
docker compose up -d
```

Verificar os containers:

``` powershell
docker compose ps
```

Consultar logs:

``` powershell
docker compose logs localstack --tail 100
```

Verificar a resposta do serviço STS:

``` powershell
aws --endpoint-url=http://localhost:4566 sts get-caller-identity --region us-east-1
```

## 🚀 Deploy

Na raiz do projeto, execute:

``` powershell
.\scripts\deploy.ps1
```

O script de deploy foi criado para automatizar as principais etapas:

1.  validar ferramentas e arquivos necessários;
2.  iniciar o LocalStack;
3.  preparar o pacote da Lambda e instalar `boto3`;
4.  criar o bucket S3, se necessário;
5.  criar a IAM Role e a policy de acesso ao S3, se necessário;
6.  anexar a policy à Role;
7.  criar ou atualizar a função Lambda;
8.  criar ou reutilizar a API REST;
9.  criar ou reutilizar o recurso `/arquivos`;
10. configurar o método `POST` e a integração proxy com a Lambda;
11. configurar a permissão de invocação;
12. publicar o stage `dev`.

Ao final, o script informa o endpoint da API. Se houver erro, leia a
mensagem no terminal e corrija-o antes de continuar.

## 🧪 Testes

Execute:

``` powershell
.\scripts\invoke.ps1
```

O script testa a invocação direta da Lambda, envia uma requisição HTTP
para o API Gateway e verifica se o objeto esperado existe no S3.

Resultado esperado:

``` text
Lambda direta:       OK
API Gateway HTTP:    OK
S3:                  OK

Fluxo completo funcionando:
HTTP -> API Gateway -> Lambda -> S3
```

## 🌐 API

O endpoint usa o seguinte formato:

``` text
POST http://localhost:4566/restapis/{API_ID}/dev/_user_request_/arquivos
```

O `API_ID` é informado pelo `deploy.ps1`. Use o ID da API criada no seu
ambiente LocalStack.

## 📦 Payload

Exemplo de corpo JSON:

``` json
{
  "nome": "exemplo.txt",
  "conteudo": "Olá! Este arquivo foi enviado para o S3."
}
```

Exemplo de chamada usando PowerShell:

``` powershell
$ApiId = "SEU_API_ID"
$ApiUrl = "http://localhost:4566/restapis/$ApiId/dev/_user_request_/arquivos"

$Body = @{
    nome = "exemplo.txt"
    conteudo = "Olá! Este arquivo foi enviado para o S3."
} | ConvertTo-Json

Invoke-RestMethod `
    -Uri $ApiUrl `
    -Method Post `
    -ContentType "application/json" `
    -Body $Body
```

A função retorna uma resposta de sucesso com o nome do bucket e a chave
do arquivo. Em caso de falha, consulte a resposta HTTP e os logs do
LocalStack.

## 🪣 S3

Bucket utilizado:

``` text
serverless-arquivos
```

Listar objetos:

``` powershell
aws --endpoint-url=http://localhost:4566 s3 ls s3://serverless-arquivos/ --region us-east-1
```

Baixar um objeto:

``` powershell
aws --endpoint-url=http://localhost:4566 s3 cp s3://serverless-arquivos/exemplo.txt . --region us-east-1
```

## 🔐 IAM

**Role**

``` text
lambda-local-role
arn:aws:iam::000000000000:role/lambda-local-role
```

**Policy**

``` text
lambda-s3-write-policy
arn:aws:iam::000000000000:policy/lambda-s3-write-policy
```

A policy concede `s3:PutObject` sobre os objetos do bucket
`serverless-arquivos`.

Verificar as policies anexadas:

``` powershell
aws --endpoint-url=http://localhost:4566 iam list-attached-role-policies `
    --role-name lambda-local-role `
    --region us-east-1
```

## 🧹 Destroy

Para remover os recursos criados pelo projeto:

``` powershell
.\scripts\destroy.ps1
```

O script solicita uma confirmação antes de remover os recursos. Digite
`DELETE` somente se realmente quiser prosseguir.

A limpeza remove a API Gateway, a Lambda, os objetos e o bucket S3, a
IAM policy e a IAM Role configuradas para este projeto. **A remoção do
bucket apaga os arquivos armazenados nele.** O script não desinstala o
Docker Desktop nem remove o próprio projeto do disco.

## 🐛 Troubleshooting

### LocalStack não responde

``` powershell
docker compose ps
docker compose logs localstack --tail 100
aws --endpoint-url=http://localhost:4566 sts get-caller-identity --region us-east-1
```

### IAM não está habilitado

Confira se o `docker-compose.yml` inclui `iam` na lista de serviços do
LocalStack, junto de `s3`, `lambda`, `apigateway` e `sts`. Após alterar
a configuração, reinicie o ambiente:

``` powershell
docker compose down
docker compose up -d
```

### Lambda não aparece

``` powershell
aws --endpoint-url=http://localhost:4566 lambda list-functions --region us-east-1
```

### Consultar a configuração da Lambda

``` powershell
aws --endpoint-url=http://localhost:4566 lambda get-function-configuration `
    --function-name serverless-arquivos-lambda `
    --region us-east-1
```

### Listar buckets S3

``` powershell
aws --endpoint-url=http://localhost:4566 s3 ls --region us-east-1
```

### Listar APIs REST

``` powershell
aws --endpoint-url=http://localhost:4566 apigateway get-rest-apis --region us-east-1
```

### Erro de variável vazia no PowerShell

Execute os scripts a partir da raiz do projeto e prefira rodar o script
completo em vez de copiar apenas linhas de continuação de um comando. Os
scripts definem as variáveis usadas nas chamadas da AWS CLI.

## 📌 Comandos úteis

  Ação |                                Comando
  |---|---|
  Iniciar LocalStack |                  `docker compose up -d`
  Ver containers |                      `docker compose ps`
  Ver logs |                            `docker compose logs localstack --tail 100`
  Fazer deploy |                        `.\scripts\deploy.ps1`
  Executar testes |                     `.\scripts\invoke.ps1`
  Remover recursos |                    `.\scripts\destroy.ps1`
  Listar Lambdas |                      `aws --endpoint-url=http://localhost:4566 lambda list-functions --region us-east-1`
  Listar buckets |                      `aws --endpoint-url=http://localhost:4566 s3 ls --region us-east-1`
  Listar APIs |                         `aws --endpoint-url=http://localhost:4566 apigateway get-rest-apis --region us-east-1`
  
## 📦 Enviar arquivo
Script para enviar arquivo pela API Gateway → Lambda → S3:
```shell
$apiId = aws --endpoint-url=http://localhost:4566 apigateway get-rest-apis --query "items[?name=='serverless-arquivos-api'].id | [0]" --output text

$url = "http://localhost:4566/restapis/$apiId/dev/_user_request_/arquivos"

$body = @{
    nome = "meu-arquivo.txt"
    conteudo = "Este arquivo foi enviado pela API Gateway e Lambda para o S3."
} | ConvertTo-Json

Invoke-RestMethod `
    -Uri $url `
    -Method Post `
    -ContentType "application/json" `
    -Body $body
```
Confirmar que o arquivo chegou ao S3:
```shell
aws --endpoint-url=http://localhost:4566 s3 ls s3://serverless-arquivos/
```
Para ver o conteúdo do arquivo:
```shell
aws --endpoint-url=http://localhost:4566 s3 cp s3://serverless-arquivos/meu-arquivo.txt -
```
## 🎯 Resultado

O projeto demonstra um fluxo serverless local de envio e armazenamento
de arquivos:

``` text
Cliente HTTP
    → API Gateway
    → AWS Lambda (Python)
    → Amazon S3
```

Tudo é executado localmente usando Docker e LocalStack, facilitando o
aprendizado e a experimentação sem provisionar esses recursos na AWS
real.

------------------------------------------------------------------------

**Projeto:** `project-api-gateway-lambda-s3`\
**Região local:** `us-east-1`\
**Endpoint LocalStack:** `http://localhost:4566`

## 👨‍💻 Autor

**Thiago Vilarinho Lemes**
👤 Autor: Thiago Vilarinho Lemes <br>
💻 Engenheiro e Analista de Dados.\
🏠 Home: https://thiagolemes.netlify.app/ \
🔗 LinkedIn: <a href="https://www.linkedin.com/in/thiago-v-lemes-b1232727" target="_blank">Thiago Lemes</a><br>
✉️ e-mail:contatothiagolemes@gmail.com | lemes_vilarinho@yahoo.com.br


Principais áreas:

```text
Data Engineering
Docker
Kafka
Python
SQL
Apache Airflow
Docker
PostgreSQL
Data Lake
ETL
APIs
Cloud
IoT
Machine Learning
Generative AI
```