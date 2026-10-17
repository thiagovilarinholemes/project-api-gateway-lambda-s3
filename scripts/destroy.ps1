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
# CONFIRMAÇÃO
# ============================================================

Write-Host ""
Write-Host "ATENÇÃO!" -ForegroundColor Yellow
Write-Host "Este script removerá os recursos do projeto no LocalStack." -ForegroundColor Yellow
Write-Host ""
Write-Host "Serão removidos:" -ForegroundColor Yellow
Write-Host "  - API Gateway: $ApiName"
Write-Host "  - Lambda:      $FunctionName"
Write-Host "  - Bucket S3:   $BucketName"
Write-Host "  - IAM Policy:  $PolicyName"
Write-Host "  - IAM Role:    $RoleName"
Write-Host ""

$Confirmation = Read-Host "Digite DELETE para continuar"

if ($Confirmation -ne "DELETE") {
    Write-Host "Operação cancelada." -ForegroundColor Yellow
    exit 0
}

# ============================================================
# API GATEWAY
# ============================================================

Write-Step "1. Removendo API Gateway"

$Apis = Invoke-AwsJson @(
    "apigateway",
    "get-rest-apis",
    "--region",
    $Region
)

$Api = $Apis.items |
    Where-Object { $_.name -eq $ApiName } |
    Select-Object -First 1

if ($Api) {

    $ApiId = $Api.id

    Invoke-Aws @(
        "apigateway",
        "delete-rest-api",
        "--rest-api-id",
        $ApiId,
        "--region",
        $Region
    )

    Write-Host "API removida: $ApiId" -ForegroundColor Green
}
else {
    Write-Host "API não encontrada." -ForegroundColor Yellow
}

# ============================================================
# LAMBDA
# ============================================================

Write-Step "2. Removendo Lambda"

try {

    Invoke-Aws @(
        "lambda",
        "delete-function",
        "--function-name",
        $FunctionName,
        "--region",
        $Region
    )

    Write-Host "Lambda removida." -ForegroundColor Green

}
catch {

    Write-Host "Lambda não encontrada ou já removida." -ForegroundColor Yellow
}

# ============================================================
# S3
# ============================================================

Write-Step "3. Esvaziando bucket S3"

try {

    Invoke-Aws @(
        "s3",
        "rm",
        "s3://$BucketName",
        "--recursive",
        "--region",
        $Region
    )

    Write-Host "Objetos removidos do bucket." -ForegroundColor Green

}
catch {

    Write-Host "Bucket vazio ou não encontrado." -ForegroundColor Yellow
}

Write-Step "4. Removendo bucket S3"

try {

    Invoke-Aws @(
        "s3",
        "rb",
        "s3://$BucketName",
        "--region",
        $Region
    )

    Write-Host "Bucket removido." -ForegroundColor Green

}
catch {

    Write-Host "Bucket não encontrado ou já removido." -ForegroundColor Yellow
}

# ============================================================
# IAM POLICY
# ============================================================

Write-Step "5. Desanexando IAM Policy"

$PolicyArn = "arn:aws:iam::000000000000:policy/$PolicyName"

try {

    Invoke-Aws @(
        "iam",
        "detach-role-policy",
        "--role-name",
        $RoleName,
        "--policy-arn",
        $PolicyArn,
        "--region",
        $Region
    )

    Write-Host "Policy desanexada." -ForegroundColor Green

}
catch {

    Write-Host "Policy já estava desanexada." -ForegroundColor Yellow
}

# ============================================================
# IAM POLICY DELETE
# ============================================================

Write-Step "6. Removendo IAM Policy"

try {

    Invoke-Aws @(
        "iam",
        "delete-policy",
        "--policy-arn",
        $PolicyArn,
        "--region",
        $Region
    )

    Write-Host "Policy removida." -ForegroundColor Green

}
catch {

    Write-Host "Policy não encontrada ou já removida." -ForegroundColor Yellow
}

# ============================================================
# IAM ROLE
# ============================================================

Write-Step "7. Removendo IAM Role"

try {

    Invoke-Aws @(
        "iam",
        "delete-role",
        "--role-name",
        $RoleName,
        "--region",
        $Region
    )

    Write-Host "Role removida." -ForegroundColor Green

}
catch {

    Write-Host "Role não encontrada ou já removida." -ForegroundColor Yellow
}

# ============================================================
# RESULTADO
# ============================================================

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "                 DESTROY CONCLUÍDO                         " -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green

Write-Host ""
Write-Host "Recursos do projeto removidos do LocalStack." -ForegroundColor Green
Write-Host ""