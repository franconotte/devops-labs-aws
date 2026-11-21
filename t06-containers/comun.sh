# Variables y helpers compartidos por los labs del T06
export PATH="$HOME/.local/bin:$PATH"
export AWS_PAGER=""
REGION="us-east-1"
R="--region $REGION"
IDS="$HOME/practica/t06/ids-t06.env"
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
LABROLE="arn:aws:iam::${ACCOUNT}:role/LabRole"
ECR_REGISTRY="${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com"
guardar() { grep -v "^$1=" "$IDS" 2>/dev/null > "$IDS.tmp" || true; echo "$1=$2" >> "$IDS.tmp"; mv "$IDS.tmp" "$IDS"; }
cargar()  { [ -f "$IDS" ] && . "$IDS"; }
