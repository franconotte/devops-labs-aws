#!/usr/bin/env bash
# Corre un lab del T05 de punta a punta y deja todo destruido.
#   bash correr-lab.sh <carpeta-del-lab> [--conservar]
export PATH="$HOME/.local/bin:$PATH"
D="$1"; CONSERVAR="${2:-}"
cd "$D" || exit 1
NOMBRE=$(basename "$D")
echo "=================== $NOMBRE ==================="

# Los AMI hardcodeados de las guias ya caducaron: se resuelve el vigente.
AMI=""
if grep -qE 'ami-[0-9a-f]{8,}' *.tf 2>/dev/null; then
  AMI=$(aws ec2 describe-images --owners amazon --region us-east-1 \
    --filters "Name=name,Values=al2023-ami-*-x86_64" "Name=state,Values=available" \
    --query "sort_by(Images,&CreationDate)[-1].ImageId" --output text)
  sed -i -E "s|ami-[0-9a-f]{8,}|$AMI|g" *.tf
  echo "AMI actualizado a $AMI"
fi
sed -i 's|"t2\.micro"|"t3.micro"|g' *.tf 2>/dev/null
sed -i 's|"terraform-key"|"vockey"|g' *.tf 2>/dev/null

rm -f .terraform.lock.hcl
terraform init -no-color >/dev/null 2>&1 || { echo "init: FALLO"; terraform init -no-color 2>&1 | tail -5; exit 1; }
terraform validate -no-color | tail -1

PLAN=$(terraform plan -no-color -input=false 2>&1)
echo "$PLAN" | grep -E "^Plan:|No changes" | tail -1
if echo "$PLAN" | grep -q "Error"; then
  echo "PLAN CON ERROR:"; echo "$PLAN" | grep -A4 "Error" | head -12; exit 1
fi

terraform apply -auto-approve -no-color -input=false > /tmp/apply.log 2>&1
if grep -q "Apply complete" /tmp/apply.log; then
  grep -E "Apply complete" /tmp/apply.log
  echo "--- recursos en el state ---"; terraform state list | sed 's/^/    /'
  OUT=$(terraform output -no-color 2>/dev/null | head -8)
  [ -n "$OUT" ] && { echo "--- outputs ---"; echo "$OUT" | sed 's/^/    /'; }
else
  echo "APPLY CON ERROR:"; grep -A4 "Error" /tmp/apply.log | head -12; exit 1
fi

if [ "$CONSERVAR" != "--conservar" ]; then
  terraform destroy -auto-approve -no-color > /tmp/destroy.log 2>&1
  grep -E "Destroy complete|Error" /tmp/destroy.log | head -3
fi
echo ""
