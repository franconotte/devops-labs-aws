#!/usr/bin/env bash
# T04 - 03-storage / Lab 4: S3 como sitio web estatico
# Partes A y B del lab: hosting, bucket policy, Cafe App y lifecycle a Glacier.
#
#   bash 03-s3-sitio-estatico.sh            -> contra AWS real
#   USAR_LOCALSTACK=1 bash 03-s3-...sh      -> contra LocalStack (sin cuenta de AWS)
#   bash 03-s3-sitio-estatico.sh limpiar
set -euo pipefail

REGION="us-east-1"
BUCKET="${BUCKET:-fnotte-bucket}"      # {inicial}{apellido}-bucket, unico en el mundo
AWS="aws"
[ "${USAR_LOCALSTACK:-0}" = "1" ] && AWS="aws --endpoint-url=http://localhost:4566"

if [ "${1:-}" = "limpiar" ]; then
    $AWS s3 rm "s3://$BUCKET" --recursive --region "$REGION" || true
    $AWS s3 rb "s3://$BUCKET" --region "$REGION" || true
    echo "Bucket eliminado"
    exit 0
fi

echo "== Parte A: crear el bucket"
$AWS s3 mb "s3://$BUCKET" --region "$REGION"

echo "== Desactivar Block Public Access"
$AWS s3api put-public-access-block --bucket "$BUCKET" --region "$REGION" \
  --public-access-block-configuration \
  "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false"

echo "== Habilitar static website hosting"
$AWS s3 website "s3://$BUCKET" --index-document index.html --region "$REGION"

echo "== Bucket policy de lectura publica"
POLICY_FILE=$(mktemp)
printf '%s\n' \
  '{' \
  '  "Version": "2012-10-17",' \
  '  "Statement": [' \
  '    {' \
  '      "Effect": "Allow",' \
  '      "Principal": "*",' \
  '      "Action": "s3:GetObject",' \
  "      \"Resource\": \"arn:aws:s3:::$BUCKET/*\"" \
  '    }' \
  '  ]' \
  '}' > "$POLICY_FILE"
$AWS s3api put-bucket-policy --bucket "$BUCKET" --policy "file://$POLICY_FILE" --region "$REGION"
rm -f "$POLICY_FILE"

echo "== Subir la Cafe App"
APP_DIR=$(mktemp -d)
git clone --quiet --depth 1 https://github.com/ORT-ATI-CertificadoDevOps/cafeApp.git "$APP_DIR/cafeApp" \
  || echo "No se pudo clonar cafeApp (repo privado?): subi los archivos a mano"
if [ -d "$APP_DIR/cafeApp/website" ]; then
    # El repo trae el sitio dentro de website/: se sube SU CONTENIDO a la raiz del bucket,
    # si no index.html no queda en la raiz y el endpoint responde 404.
    $AWS s3 sync "$APP_DIR/cafeApp/website" "s3://$BUCKET" --region "$REGION"
elif [ -d "$APP_DIR/cafeApp" ]; then
    $AWS s3 sync "$APP_DIR/cafeApp" "s3://$BUCKET" --exclude ".git/*" --region "$REGION"
fi
rm -rf "$APP_DIR"

echo "== Parte B: lifecycle to_glacier5d sobre for_archive/"
LC_FILE=$(mktemp)
printf '%s\n' \
  '{' \
  '  "Rules": [' \
  '    {' \
  '      "ID": "to_glacier5d",' \
  '      "Status": "Enabled",' \
  '      "Filter": { "Prefix": "for_archive/" },' \
  '      "Transitions": [ { "Days": 5, "StorageClass": "GLACIER" } ]' \
  '    }' \
  '  ]' \
  '}' > "$LC_FILE"
$AWS s3api put-bucket-lifecycle-configuration --bucket "$BUCKET" \
  --lifecycle-configuration "file://$LC_FILE" --region "$REGION"
rm -f "$LC_FILE"

echo "== Verificacion"
$AWS s3api get-bucket-website --bucket "$BUCKET" --region "$REGION"
$AWS s3api get-bucket-lifecycle-configuration --bucket "$BUCKET" --region "$REGION"
$AWS s3 ls "s3://$BUCKET" --region "$REGION"

echo ""
if [ "${USAR_LOCALSTACK:-0}" = "1" ]; then
    echo "URL (LocalStack): http://$BUCKET.s3-website.localhost.localstack.cloud:4566"
else
    echo "URL del sitio:    http://$BUCKET.s3-website-$REGION.amazonaws.com"
fi
echo ""
echo "Parte B, restringir por IP: cambiar el Principal/Condition de la policy por"
echo '  "Condition": { "IpAddress": { "aws:SourceIp": "TU_IP/32" } }'
echo "Al terminar: bash 03-s3-sitio-estatico.sh limpiar"
