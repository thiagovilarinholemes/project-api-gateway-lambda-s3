$ErrorActionPreference = "Stop"

# ============================================================
# CONFIGURAÇÃO
# ============================================================

$Region = "us-east-1"
$Endpoint = "http://localhost:4566"

$BucketName = "serverless-arquivos"
$FunctionName = "serverless-arquivos-lambda"
$RoleName = "lambda-local-role"
$PolicyName = "lambda-s3-write-policy"

$ApiName = "serverless-arquivos-api"
$StageName = "dev"

$ProjectRoot = Split-Path -Parent $PSScriptRoot

$BuildDir = Join-Path $ProjectRoot "build"
$LambdaPackageDir = Join-Path $BuildDir "lambda-package"
$ZipPath = Join-Path $BuildDir "lambda_function.zip"

$LambdaSource = Join-Path $ProjectRoot "src\lambda_function.py"

$TrustPolicyPath = Join-Path $BuildDir "trust-policy.json"
$S3PolicyPath = Join-Path $BuildDir "s3-policy.json"

# ============================================================
# FUNÇÕES AUXILIARES
# ============================================================

function Write-Step {
    param(
        [string]$Message
    )

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host $Message -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
}

function Invoke-Aws {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    & aws "--endpoint-url=$Endpoint" @Arguments

    if ($LASTEXITCODE -ne 0) {
        throw "AWS CLI retornou código $LASTEXITCODE."
    }
}

function Invoke-AwsJson {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $Output = & aws "--endpoint-url=$Endpoint" @Arguments 2>&1

    if ($LASTEXITCODE -ne 0) {
        throw ($Output -join "`n")
    }

    return ($Output -join "`n") | ConvertFrom-Json
}

# ============================================================
# VALIDAÇÕES
# ============================================================

Write-Step "1. Validando ambiente"

if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
    throw "AWS CLI não encontrada."
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw "Docker não encontrado."
}

if (-not (Test-Path $LambdaSource)) {
    throw "Lambda não encontrada: $LambdaSource"
}

Write-Host "Projeto: $ProjectRoot" -ForegroundColor Green
Write-Host "Lambda:  $LambdaSource" -ForegroundColor Green

# ============================================================
# LOCALSTACK
# ============================================================

Write-Step "2. Garantindo que o LocalStack está ativo"

docker compose up -d

Start-Sleep -Seconds 5

Invoke-Aws @(
    "sts",
    "get-caller-identity",
    "--region",
    $Region
) | Out-Null

Write-Host "LocalStack disponível." -ForegroundColor Green

# ============================================================
# BUILD
# ============================================================

Write-Step "3. Preparando pacote da Lambda"

New-Item -ItemType Directory -Path $BuildDir -Force | Out-Null
New-Item -ItemType Directory -Path $LambdaPackageDir -Force | Out-Null

# Limpar somente o pacote da Lambda.
Get-ChildItem $LambdaPackageDir -Force -ErrorAction SilentlyContinue |
    Remove-Item -Recurse -Force

Copy-Item $LambdaSource `
    (Join-Path $LambdaPackageDir "lambda_function.py") `
    -Force

Write-Host "Instalando boto3 no pacote..." -ForegroundColor Yellow

python -m pip install `
    boto3 `
    --target $LambdaPackageDir `
    --upgrade `
    --quiet

if ($LASTEXITCODE -ne 0) {
    throw "Falha ao instalar dependências da Lambda."
}

if (Test-Path $ZipPath) {
    Remove-Item $ZipPath -Force
}

Compress-Archive `
    -Path "$LambdaPackageDir\*" `
    -DestinationPath $ZipPath `
    -Force

$ZipInfo = Get-Item $ZipPath

Write-Host "Pacote criado: $($ZipInfo.FullName)" -ForegroundColor Green
Write-Host "Tamanho: $($ZipInfo.Length) bytes" -ForegroundColor Green

# ============================================================
# S3
# ============================================================

Write-Step "4. Criando bucket S3"

$ExistingBuckets = Invoke-AwsJson @(
    "s3api",
    "list-buckets",
    "--region",
    $Region
)

$BucketExists = $ExistingBuckets.Buckets |
    Where-Object { $_.Name -eq $BucketName }

if (-not $BucketExists) {
    Invoke-Aws @(
        "s3",
        "mb",
        "s3://$BucketName",
        "--region",
        $Region
    )
}
else {
    Write-Host "Bucket já existe: $BucketName" -ForegroundColor Yellow
}

# ============================================================
# IAM TRUST POLICY
# ============================================================

Write-Step "5. Configurando IAM"

$TrustPolicy = @'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
'@

$TrustPolicy | Set-Content `
    -Path $TrustPolicyPath `
    -Encoding ascii

# Criar Role se necessário.
$RoleExists = $true

try {
    Invoke-AwsJson @(
        "iam",
        "get-role",
        "--role-name",
        $RoleName,
        "--region",
        $Region
    ) | Out-Null
}
catch {
    $RoleExists = $false
}

if (-not $RoleExists) {

    Invoke-AwsJson @(
        "iam",
        "create-role",
        "--role-name",
        $RoleName,
        "--assume-role-policy-document",
        "file://$TrustPolicyPath",
        "--region",
        $Region
    ) | Out-Null

    Write-Host "Role criada: $RoleName" -ForegroundColor Green
}
else {
    Write-Host "Role já existe: $RoleName" -ForegroundColor Yellow
}

$RoleArn = "arn:aws:iam::000000000000:role/$RoleName"

# ============================================================
# IAM S3 POLICY
# ============================================================

$S3Policy = @'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject"
      ],
      "Resource": "arn:aws:s3:::serverless-arquivos/*"
    }
  ]
}
'@

$S3Policy | Set-Content `
    -Path $S3PolicyPath `
    -Encoding ascii

$PolicyArn = "arn:aws:iam::000000000000:policy/$PolicyName"

$PolicyExists = $true

try {
    Invoke-AwsJson @(
        "iam",
        "get-policy",
        "--policy-arn",
        $PolicyArn,
        "--region",
        $Region
    ) | Out-Null
}
catch {
    $PolicyExists = $false
}

if (-not $PolicyExists) {

    Invoke-AwsJson @(
        "iam",
        "create-policy",
        "--policy-name",
        $PolicyName,
        "--policy-document",
        "file://$S3PolicyPath",
        "--region",
        $Region
    ) | Out-Null

    Write-Host "Policy criada: $PolicyName" -ForegroundColor Green
}
else {
    Write-Host "Policy já existe: $PolicyName" -ForegroundColor Yellow
}

# Anexar policy à Role.
Invoke-Aws @(
    "iam",
    "attach-role-policy",
    "--role-name",
    $RoleName,
    "--policy-arn",
    $PolicyArn,
    "--region",
    $Region
)

Write-Host "Policy anexada à Role." -ForegroundColor Green

# ============================================================
# LAMBDA
# ============================================================

Write-Step "6. Criando/atualizando Lambda"

$FunctionExists = $true

try {
    Invoke-AwsJson @(
        "lambda",
        "get-function",
        "--function-name",
        $FunctionName,
        "--region",
        $Region
    ) | Out-Null
}
catch {
    $FunctionExists = $false
}

if (-not $FunctionExists) {

    Invoke-Aws @(
        "lambda",
        "create-function",
        "--function-name",
        $FunctionName,
        "--runtime",
        "python3.12",
        "--handler",
        "lambda_function.lambda_handler",
        "--role",
        $RoleArn,
        "--zip-file",
        "fileb://$ZipPath",
        "--timeout",
        "30",
        "--memory-size",
        "256",
        "--environment",
        "Variables={BUCKET_NAME=$BucketName,AWS_DEFAULT_REGION=$Region}",
        "--region",
        $Region
    )

    Write-Host "Lambda criada." -ForegroundColor Green
}
else {

    Invoke-Aws @(
        "lambda",
        "update-function-code",
        "--function-name",
        $FunctionName,
        "--zip-file",
        "fileb://$ZipPath",
        "--region",
        $Region
    )

    Invoke-Aws @(
        "lambda",
        "update-function-configuration",
        "--function-name",
        $FunctionName,
        "--role",
        $RoleArn,
        "--handler",
        "lambda_function.lambda_handler",
        "--runtime",
        "python3.12",
        "--timeout",
        "30",
        "--memory-size",
        "256",
        "--environment",
        "Variables={BUCKET_NAME=$BucketName,AWS_DEFAULT_REGION=$Region}",
        "--region",
        $Region
    )

    Write-Host "Lambda atualizada." -ForegroundColor Green
}

# ============================================================
# API GATEWAY
# ============================================================

Write-Step "7. Configurando API Gateway"

$Apis = Invoke-AwsJson @(
    "apigateway",
    "get-rest-apis",
    "--region",
    $Region
)

$Api = $Apis.items |
    Where-Object { $_.name -eq $ApiName } |
    Select-Object -First 1

if (-not $Api) {

    $Api = Invoke-AwsJson @(
        "apigateway",
        "create-rest-api",
        "--name",
        $ApiName,
        "--description",
        "API para enviar arquivos ao S3 usando AWS Lambda",
        "--region",
        $Region
    )

    Write-Host "API criada." -ForegroundColor Green
}
else {
    Write-Host "API já existe." -ForegroundColor Yellow
}

$ApiId = $Api.id

Write-Host "API ID: $ApiId" -ForegroundColor Green

# ============================================================
# RECURSO /arquivos
# ============================================================

$Resources = Invoke-AwsJson @(
    "apigateway",
    "get-resources",
    "--rest-api-id",
    $ApiId,
    "--region",
    $Region
)

$RootResource = $Resources.items |
    Where-Object { $_.path -eq "/" } |
    Select-Object -First 1

$FileResource = $Resources.items |
    Where-Object { $_.path -eq "/arquivos" } |
    Select-Object -First 1

if (-not $FileResource) {

    $FileResource = Invoke-AwsJson @(
        "apigateway",
        "create-resource",
        "--rest-api-id",
        $ApiId,
        "--parent-id",
        $RootResource.id,
        "--path-part",
        "arquivos",
        "--region",
        $Region
    )

    Write-Host "Recurso /arquivos criado." -ForegroundColor Green
}

$ResourceId = $FileResource.id

# ============================================================
# MÉTODO POST
# ============================================================

try {
    Invoke-AwsJson @(
        "apigateway",
        "get-resource",
        "--rest-api-id",
        $ApiId,
        "--resource-id",
        $ResourceId,
        "--region",
        $Region
    ) | Out-Null
}
catch {
    throw "Não foi possível localizar o recurso /arquivos."
}

$ResourceInfo = Invoke-AwsJson @(
    "apigateway",
    "get-resource",
    "--rest-api-id",
    $ApiId,
    "--resource-id",
    $ResourceId,
    "--region",
    $Region
)

$PostExists = $false

if ($ResourceInfo.resourceMethods) {
    $PostExists =
        $ResourceInfo.resourceMethods.PSObject.Properties.Name -contains "POST"
}

if (-not $PostExists) {

    Invoke-Aws @(
        "apigateway",
        "put-method",
        "--rest-api-id",
        $ApiId,
        "--resource-id",
        $ResourceId,
        "--http-method",
        "POST",
        "--authorization-type",
        "NONE",
        "--region",
        $Region
    )
}

# ============================================================
# INTEGRAÇÃO LAMBDA
# ============================================================

$LambdaArn = "arn:aws:lambda:${Region}:000000000000:function:${FunctionName}"

$IntegrationUri =
    "arn:aws:apigateway:${Region}:lambda:path/2015-03-31/functions/${LambdaArn}/invocations"

Invoke-Aws @(
    "apigateway",
    "put-integration",
    "--rest-api-id",
    $ApiId,
    "--resource-id",
    $ResourceId,
    "--http-method",
    "POST",
    "--type",
    "AWS_PROXY",
    "--integration-http-method",
    "POST",
    "--uri",
    $IntegrationUri,
    "--region",
    $Region
)

# ============================================================
# PERMISSÃO API GATEWAY → LAMBDA
# ============================================================

$SourceArn =
    "arn:aws:execute-api:${Region}:000000000000:${ApiId}/*/POST/arquivos"

try {

    Invoke-Aws @(
        "lambda",
        "add-permission",
        "--function-name",
        $FunctionName,
        "--statement-id",
        "apigateway-invoke",
        "--action",
        "lambda:InvokeFunction",
        "--principal",
        "apigateway.amazonaws.com",
        "--source-arn",
        $SourceArn,
        "--region",
        $Region
    )

    Write-Host "Permissão API Gateway → Lambda criada." -ForegroundColor Green
}
catch {

    Write-Host "Permissão já existente ou não foi necessário recriá-la." -ForegroundColor Yellow
}

# ============================================================
# DEPLOYMENT
# ============================================================

Write-Step "8. Publicando API"

Invoke-Aws @(
    "apigateway",
    "create-deployment",
    "--rest-api-id",
    $ApiId,
    "--stage-name",
    $StageName,
    "--description",
    "Deploy automático",
    "--region",
    $Region
)

$ApiUrl =
    "${Endpoint}/restapis/${ApiId}/${StageName}/_user_request_/arquivos"

# ============================================================
# RESULTADO
# ============================================================

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "                 DEPLOY CONCLUÍDO                          " -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green

Write-Host ""
Write-Host "S3:" -ForegroundColor Cyan
Write-Host "  s3://$BucketName"

Write-Host ""
Write-Host "Lambda:" -ForegroundColor Cyan
Write-Host "  $FunctionName"

Write-Host ""
Write-Host "API Gateway:" -ForegroundColor Cyan
Write-Host "  $ApiName"

Write-Host ""
Write-Host "Endpoint:" -ForegroundColor Cyan
Write-Host "  POST $ApiUrl"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green