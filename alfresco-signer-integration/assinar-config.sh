#!/usr/bin/env bash
# =============================================================================
#  Configuracao da integracao de assinatura Alfresco <-> microsservico PAdES
#  Ajuste os valores marcados. Os IDs das pastas sao preenchidos por 'setup'.
# =============================================================================

# --- Alfresco ---
export ALF_BASE="http://localhost:8080"
export ALF_ADMIN_USER="admin"
# TROQUE pela senha do admin do Alfresco (a mesma de ALF_ADMIN_PASS do deploy):
export ALF_ADMIN_PASS="ALTERE_pela_senha_admin"

# --- Microsservico de assinatura ---
export SIGNER_URL="http://localhost:8092"
# Certificado A1 do cofre (/opt/alfresco/certificados) e sua senha.
# Para TESTE use o teste.p12 (teste123). Em producao, troque pelo A1 real da Cliente.
export SIGN_CERT="teste.p12"
export SIGN_PASS="teste123"
export SIGN_REASON="Assinatura digital ICP-Brasil (PAdES)"

# --- Pastas (preenchidas automaticamente pelo comando 'setup') ---
export A_ASSINAR_FOLDER=""
export ASSINADOS_FOLDER=""
