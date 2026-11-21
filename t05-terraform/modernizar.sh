#!/usr/bin/env bash
# Actualiza las restricciones de version de un lab del T05 a lo que tenemos instalado.
# El material del curso esta escrito para Terraform 0.14 y provider aws 2.x/3.x.
for f in "$1"/*.tf; do
  [ -f "$f" ] || continue
  sed -i -E 's|required_version *= *"[^"]*"|required_version = ">= 1.0"|' "$f"
  sed -i -E '/source *= *"hashicorp\/aws"/,+1 s|version *= *"[^"]*"|version = "~> 6.0"|' "$f"
  sed -i -E '/source *= *"hashicorp\/random"/,+1 s|version *= *"[^"]*"|version = "~> 3.0"|' "$f"
done
