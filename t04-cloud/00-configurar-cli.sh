#!/usr/bin/env bash
# T04 - Paso 0: instalar y configurar la AWS CLI
# Uso: bash 00-configurar-cli.sh
set -e

if ! command -v aws >/dev/null; then
    echo "Instalando AWS CLI v2..."
    cd /tmp
    curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
    unzip -q -o awscliv2.zip
    sudo ./aws/install --update -i /usr/local/aws-cli -b /usr/local/bin
    cd - >/dev/null
fi

aws --version

echo ""
echo "Ahora carga tus credenciales del Learner Lab (AWS Details -> AWS CLI -> Show):"
echo ""
echo "    aws configure"
echo "      AWS Access Key ID:     <aws_access_key_id>"
echo "      AWS Secret Access Key: <aws_secret_access_key>"
echo "      Default region name:   us-east-1"
echo "      Default output format: yaml"
echo ""
echo "    aws configure set aws_session_token <aws_session_token>"
echo ""
echo "Verificar:"
echo "    aws sts get-caller-identity"
echo "    aws ec2 describe-instances --output table"
echo ""
echo "Estas credenciales caducan cuando se apaga el Learner Lab."
