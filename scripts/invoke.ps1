$ErrorActionPreference = "Stop"

# ============================================================
# CONFIGURAÇÃO
# ============================================================

$Region = "us-east-1"
$Endpoint = "http://localhost:4566"

$BucketName = "serverless-arquivos"
$FunctionName = "serverless-arquivos-lambda"
$ApiName = "serverless-arquivos-api"
$StageName = "dev"

$ProjectRoot = Split-Path -Parent $PSScriptRoot

$EventsDir = Join-Path $ProjectRoot "events"
$BuildDir = Join-Path $ProjectRoot "build"

$EventPath = Join-Path $EventsDir "api-request.json"
$LambdaResponsePath = Join-Path $BuildDir "lambda-response.json"

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
# PREPARAÇÃO
# ============================================================

Write-Step "1. Preparando teste"

New-Item -ItemType Directory -Path $EventsDir -Force | Out-Null
New-Item -ItemType Directory -Path $BuildDir -Force | Out-Null

$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

$FileName = "teste-api-$Timestamp.txt"

$Content = @"
Arquivo criado automaticamente pelo projeto
project-api-gateway-lambda-s3.

Data do teste: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
"@

# ============================================================
# TESTE DIRETO DA LAMBDA
# ============================================================

Write-Step "2. Testando Lambda diretamente"

$LambdaEvent = @{
    body = (
        @{
            nome = "teste-lambda-$Timestamp.txt"
            conteudo = "Arquivo criado através da invocação direta da Lambda."
        } | ConvertTo-Json -Compress
    )
    isBase64Encoded = $false
} | ConvertTo-Json -Compress

$LambdaEvent | Set-Content `
    -Path $EventPath `
    -Encoding ascii

Invoke-AwsJson @(
    "lambda",
    "invoke",
    "--function-name",
    $FunctionName,
    "--payload",
    "fileb://$EventPath",
    "--cli-binary-format",
    "raw-in-base64-out",
    "--region",
    $Region,
    $LambdaResponsePath
) | Out-Null

$LambdaResponse = Get-Content `
    $LambdaResponsePath `
    -Raw | ConvertFrom-Json

Write-Host "Status Lambda: $($LambdaResponse.statusCode)" -ForegroundColor Green

if ($LambdaResponse.statusCode -ne 201) {
    Write-Host $LambdaResponse.body -ForegroundColor Red
    throw "Teste direto da Lambda falhou."
}

Write-Host "Teste direto da Lambda: OK" -ForegroundColor Green

# ============================================================
# DESCOBRIR API
# ============================================================

Write-Step "3. Localizando API Gateway"

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
    throw "API Gateway '$ApiName' não encontrada."
}

$ApiId = $Api.id

$ApiUrl =
    "${Endpoint}/restapis/${ApiId}/${StageName}/_user_request_/arquivos"

Write-Host "API ID: $ApiId" -ForegroundColor Green
Write-Host "Endpoint: $ApiUrl" -ForegroundColor Green

# ============================================================
# TESTE HTTP
# ============================================================

Write-Step "4. Testando API Gateway"

$RequestBody = @{
    nome = $FileName
    conteudo = $Content
} | ConvertTo-Json

try {

    $HttpResponse = Invoke-WebRequest `
        -Uri $ApiUrl `
        -Method Post `
        -ContentType "application/json" `
        -Body $RequestBody

}
catch {

    Write-Host ""
    Write-Host "Falha na chamada HTTP." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red

    throw
}

Write-Host "HTTP Status: $($HttpResponse.StatusCode)" -ForegroundColor Green
Write-Host "Resposta:" -ForegroundColor Cyan
Write-Host $HttpResponse.Content

if ($HttpResponse.StatusCode -ne 201) {
    throw "API Gateway não retornou HTTP 201."
}

# ============================================================
# VALIDAR S3
# ============================================================

Write-Step "5. Validando arquivo no S3"

$Objects = Invoke-AwsJson @(
    "s3api",
    "list-objects-v2",
    "--bucket",
    $BucketName,
    "--region",
    $Region
)

$Object = $Objects.Contents |
    Where-Object { $_.Key -eq $FileName } |
    Select-Object -First 1

if (-not $Object) {
    throw "Arquivo '$FileName' não encontrado no S3."
}

Write-Host "Arquivo encontrado no S3:" -ForegroundColor Green
Write-Host "  Bucket: $BucketName"
Write-Host "  Key:    $($Object.Key)"
Write-Host "  Size:   $($Object.Size) bytes"

# ============================================================
# RESULTADO
# ============================================================

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "                  TESTES CONCLUÍDOS                        " -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green

Write-Host ""
Write-Host "Lambda direta:       OK" -ForegroundColor Green
Write-Host "API Gateway HTTP:    OK" -ForegroundColor Green
Write-Host "S3:                  OK" -ForegroundColor Green
Write-Host ""
Write-Host "Fluxo completo funcionando:" -ForegroundColor Cyan
Write-Host "HTTP -> API Gateway -> Lambda -> S3" -ForegroundColor Cyan