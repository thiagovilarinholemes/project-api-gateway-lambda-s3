"""
Lambda responsável por receber uma requisição HTTP,
validar os dados e armazenar um objeto no S3.
"""

import base64
import json
import logging
import os
from typing import Any

import boto3


logger = logging.getLogger()
logger.setLevel(logging.INFO)


# A configuração vem do ambiente da Lambda.
BUCKET_NAME = os.environ.get(
    "BUCKET_NAME",
    "serverless-arquivos",
)

AWS_REGION = os.environ.get(
    "AWS_DEFAULT_REGION",
    "us-east-1",
)


s3 = boto3.client(
    "s3",
    region_name=AWS_REGION,
)


def create_response(
    status_code: int,
    body: dict[str, Any],
) -> dict[str, Any]:
    """
    Cria uma resposta HTTP no formato esperado
    pelo API Gateway.
    """

    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
        },
        "body": json.dumps(
            body,
            ensure_ascii=False,
        ),
    }


def lambda_handler(
    event: dict[str, Any],
    context: Any,
) -> dict[str, Any]:
    """
    Ponto de entrada da AWS Lambda.
    """

    logger.info("Lambda iniciada.")

    try:
        body = event.get("body")

        if body is None:
            logger.warning(
                "Requisição sem body."
            )

            return create_response(
                400,
                {
                    "erro": "Body não informado."
                },
            )

        # O API Gateway pode enviar o body
        # codificado em Base64.
        if event.get("isBase64Encoded"):
            body = base64.b64decode(
                body
            ).decode("utf-8")

        # Converte JSON textual para objeto Python.
        if isinstance(body, str):
            body = json.loads(body)

        if not isinstance(body, dict):
            return create_response(
                400,
                {
                    "erro": (
                        "Body deve ser um objeto JSON."
                    )
                },
            )

        nome = body.get("nome")
        conteudo = body.get("conteudo")

        # Validação do nome.
        if not isinstance(nome, str):
            return create_response(
                400,
                {
                    "erro": (
                        "O campo 'nome' "
                        "é obrigatório."
                    )
                },
            )

        nome = nome.strip()

        if not nome:
            return create_response(
                400,
                {
                    "erro": (
                        "O campo 'nome' "
                        "não pode ser vazio."
                    )
                },
            )

        # Validação do conteúdo.
        if not isinstance(conteudo, str):
            return create_response(
                400,
                {
                    "erro": (
                        "O campo 'conteudo' "
                        "é obrigatório."
                    )
                },
            )

        # Evita nomes com caminhos.
        nome = nome.replace("/", "_")
        nome = nome.replace("\\", "_")

        # Converte texto para bytes.
        arquivo = conteudo.encode("utf-8")

        logger.info(
            "Gravando objeto %s no bucket %s.",
            nome,
            BUCKET_NAME,
        )

        s3.put_object(
            Bucket=BUCKET_NAME,
            Key=nome,
            Body=arquivo,
            ContentType=(
                "text/plain; charset=utf-8"
            ),
        )

        logger.info(
            "Objeto armazenado com sucesso."
        )

        return create_response(
            201,
            {
                "mensagem": (
                    "Arquivo armazenado "
                    "com sucesso."
                ),
                "bucket": BUCKET_NAME,
                "arquivo": nome,
            },
        )

    except json.JSONDecodeError:
        logger.exception(
            "JSON inválido."
        )

        return create_response(
            400,
            {
                "erro": "JSON inválido."
            },
        )

    except Exception:
        logger.exception(
            "Erro inesperado."
        )

        return create_response(
            500,
            {
                "erro": (
                    "Erro interno ao processar "
                    "a requisição."
                ),
            },
        )