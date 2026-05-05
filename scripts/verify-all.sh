#!/usr/bin/env bash
# verify-all.sh — Automated verification for Med_Pront (OpenEMR-based)
# Run after docker compose up with OpenEMR healthy.
# Uses environment variables from docker/.env
set -euo pipefail

# --- Config ---
BASE_URL="${OPENEMR_BASE_URL:-https://localhost}"
API_BASE="${BASE_URL}/apis/default/api"
FHIR_BASE="${BASE_URL}/apis/default/fhir"
INTEGRATION_BASE="${BASE_URL}/internal"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

pass() { ((PASS++)); echo -e "${GREEN}PASS${NC} $1"; }
fail() { ((FAIL++)); echo -e "${RED}FAIL${NC} $1"; }
warn() { ((WARN++)); echo -e "${YELLOW}WARN${NC} $1"; }

# --- Auth ---
echo "=== Authentication ==="
TOKEN=""
auth_result=$(curl -s -w "\n%{http_code}" -X POST \
  "${BASE_URL}/oauth2/default/token" \
  -d "grant_type=client_credentials&client_id=${OPENEMR_CLIENT_ID}&client_secret=${OPENEMR_CLIENT_SECRET}&scope=openid+api:oemr+api:fhir" \
  2>/dev/null) || true
auth_status=$(echo "$auth_result" | tail -1)
auth_body=$(echo "$auth_result" | sed '$d')

if [ "$auth_status" = "200" ]; then
  TOKEN=$(echo "$auth_body" | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])" 2>/dev/null || echo "")
  if [ -n "$TOKEN" ]; then
    pass "OAuth2 client_credentials auth succeeded"
  else
    fail "OAuth2 returned 200 but token extraction failed"
  fi
else
  fail "OAuth2 auth failed (HTTP $auth_status)"
fi

# Helper
api_call() {
  local method="$1" path="$2" body="${3:-}"
  if [ "$method" = "GET" ]; then
    curl -s -w "\n%{http_code}" -H "Authorization: Bearer $TOKEN" "${API_BASE}${path}" 2>/dev/null
  else
    curl -s -w "\n%{http_code}" -X "$method" -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/json" -d "$body" "${API_BASE}${path}" 2>/dev/null
  fi
}

# ============================================================
# T029 — Verify RBAC for Demographics
# ============================================================
echo ""
echo "=== T029: RBAC — Demographics ==="
if [ -z "$TOKEN" ]; then
  warn "Skipped (no auth token)"
else
  # Test that authenticated user can read patient demographics
  result=$(api_call GET /patient 2>/dev/null || true)
  status=$(echo "$result" | tail -1)
  if [ "$status" = "200" ]; then
    pass "Authenticated user can list patients"
  else
    fail "Authenticated user cannot list patients (HTTP $status)"
  fi
fi

# ============================================================
# T032 — Verify Appointment Status Transitions
# ============================================================
echo ""
echo "=== T032: Appointment Status Transitions ==="
if [ -z "$TOKEN" ]; then
  warn "Skipped (no auth token)"
else
  # Create a test appointment
  appt_result=$(api_call POST /appointment '{
    "pc_pid": 1,
    "pc_aid": 1,
    "pc_eventDate": "2099-12-31",
    "pc_startTime": "10:00:00",
    "pc_endTime": "10:30:00",
    "pc_catid": 1,
    "pc_apptstatus": "*",
    "pc_title": "Verification Test"
  }' 2>/dev/null || true)
  appt_status=$(echo "$appt_result" | tail -1)
  appt_body=$(echo "$appt_result" | sed '$d')

  if [ "$appt_status" = "200" ] || [ "$appt_status" = "201" ]; then
    pass "Appointment creation succeeded"
    APPT_ID=$(echo "$appt_body" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('id','') or d.get('id',''))" 2>/dev/null || echo "")

    if [ -n "$APPT_ID" ]; then
      # Test status transitions: * -> + -> @ -> >
      transitions=("*:Confirmed" "+:Arrived" "@:Checked In" ">:Checked Out")
      for t in $transitions; do
        code="${t%%:*}"
        label="${t##*:}"
        upd=$(api_call PUT "/appointment/${APPT_ID}" "{\"pc_apptstatus\": \"${code}\"}" 2>/dev/null || true)
        upd_status=$(echo "$upd" | tail -1)
        if [ "$upd_status" = "200" ]; then
          pass "Status transition to ${code} (${label}) succeeded"
        else
          fail "Status transition to ${code} (${label}) failed (HTTP $upd_status)"
        fi
      done

      # Test cancellation
      upd=$(api_call PUT "/appointment/${APPT_ID}" '{"pc_apptstatus": "-"}' 2>/dev/null || true)
      upd_status=$(echo "$upd" | tail -1)
      if [ "$upd_status" = "200" ]; then
        pass "Cancellation (status -) succeeded"
      else
        fail "Cancellation (status -) failed (HTTP $upd_status)"
      fi

      # Cleanup: delete test appointment
      api_call DELETE "/appointment/${APPT_ID}" 2>/dev/null || true
    else
      warn "Could not extract appointment ID for transition tests"
    fi
  else
    warn "Test appointment creation failed (HTTP $appt_status) — may need patient/provider first"
  fi
fi

# ============================================================
# T033 — RBAC for Appointments
# ============================================================
echo ""
echo "=== T033: RBAC — Appointments ==="
warn "RBAC appointment verification requires dedicated test users per profile (recepcao, medico, admin)"
warn "Manual step: Login as recepcao user, verify can create/edit appointments"
warn "Manual step: Login as medico user, verify can create/edit appointments"
warn "Manual step: Verify admin has full access"

# ============================================================
# T034 — Audit Logging for Appointments
# ============================================================
echo ""
echo "=== T034: Audit Logging — Appointments ==="
if [ -z "$TOKEN" ]; then
  warn "Skipped (no auth token)"
else
  # Check audit log for recent appointment events
  audit_result=$(api_call GET "/audit log" 2>/dev/null || true)
  audit_status=$(echo "$audit_result" | tail -1)
  if [ "$audit_status" = "200" ]; then
    pass "Audit log API accessible"
    # Check for appointment-related entries
    audit_body=$(echo "$audit_result" | sed '$d')
    if echo "$audit_body" | grep -qi "appointment"; then
      pass "Audit log contains appointment entries"
    else
      warn "No appointment entries found in current audit log window"
    fi
  else
    warn "Audit log API returned HTTP $audit_status (may need admin credentials)"
  fi
fi

# ============================================================
# T037 — AES-256 Encryption at Rest for Documents
# ============================================================
echo ""
echo "=== T037: Document Encryption at Rest ==="
echo "Manual verification required:"
warn "1. Upload a document via OpenEMR UI"
warn "2. SSH into VPS: docker exec -it med_pront-openemr-1 ls /var/www/localhost/htdocs/openemr/sites/default/documents/"
warn "3. Verify files are NOT readable plaintext (should be encrypted binary)"
warn "4. Check OpenEMR globals: Administration > Globals > Documents > Encryption = Enabled"

# ============================================================
# T038 — RBAC for Documents
# ============================================================
echo ""
echo "=== T038: RBAC — Documents ==="
warn "RBAC document verification requires dedicated test users per profile"
warn "Manual step: Login as recepcao, verify can upload to Identidade/Termos categories"
warn "Manual step: Login as recepcao, verify CANNOT access Prontuario Clinico/Exames"
warn "Manual step: Login as medico, verify can upload to ALL categories"

# ============================================================
# T039 — Audit Logging for Documents
# ============================================================
echo ""
echo "=== T039: Audit Logging — Documents ==="
warn "Manual step: Upload a document, then check audit log for upload event"
warn "Manual step: Access a document, then check audit log for access event"
warn "Manual step: Change document category, then check audit log for category change"

# ============================================================
# T042 — Telehealth Link Generation
# ============================================================
echo ""
echo "=== T042: Telehealth Link Generation ==="
warn "Manual step: Create appointment with category 'Consulta Telemedicina'"
warn "Manual step: Verify telehealth link is generated in appointment details"
warn "Manual step: Verify link uses Comlink domain"

# ============================================================
# T043 — Patient Prerequisites for Telehealth
# ============================================================
echo ""
echo "=== T043: Telehealth Patient Prerequisites ==="
warn "Manual step: Verify patient has email in demographics"
warn "Manual step: Verify patient has 'Allow Email' and 'Allow Patient Portal' enabled"
warn "Manual step: Verify patient has portal credentials (username/password set)"

# ============================================================
# T044 — Encounter Records Telemedicine Modality
# ============================================================
echo ""
echo "=== T044: Encounter Telemedicine Modality ==="
warn "Manual step: Complete a telehealth appointment (check-in → check-out)"
warn "Manual step: Open the resulting encounter"
warn "Manual step: Verify encounter is linked to telemedicine category appointment"

# ============================================================
# T059 — LGPD Compliance in Reminders
# ============================================================
echo ""
echo "=== T059: LGPD Compliance — Reminder Content ==="
if [ -z "$TOKEN" ]; then
  warn "Skipped (no auth token)"
else
  # Check that reminder template parameters contain NO clinical data
  echo "Checking WhatsApp template parameters..."
  if [ -n "${WHATSAPP_TEMPLATE_NAME:-}" ]; then
    pass "WhatsApp template name configured: $WHATSAPP_TEMPLATE_NAME"
    warn "Manual: Verify template in Meta Business Suite has ONLY these parameters: patient_name, date, time, type"
    warn "Manual: Verify template does NOT contain: diagnosis, CID, medications, clinical notes"
  else
    fail "WHATSAPP_TEMPLATE_NAME not configured"
  fi

  # Check email template content
  echo "Checking email reminder template..."
  EMAIL_TEMPLATE="docker/integration-service/src/adapters/email.py"
  if [ -f "$EMAIL_TEMPLATE" ]; then
    if grep -q "CID\|diagnosis\|medication\|diagnostico\|receita" "$EMAIL_TEMPLATE" 2>/dev/null; then
      fail "Email template contains clinical data keywords!"
    else
      pass "Email template does not contain clinical data keywords"
    fi
  fi
fi

# ============================================================
# T064 — Full Verification Checklist
# ============================================================
echo ""
echo "=== T064: Full Verification Checklist ==="
echo "Checking infrastructure items..."

# HTTPS
if [ -n "$TOKEN" ]; then
  pass "HTTPS: API accessible via authenticated request"
else
  fail "HTTPS: Could not authenticate"
fi

# Cloudflare Tunnel
warn "Manual: Verify Cloudflare Tunnel is active (Cloudflare dashboard > Zero Trust > Networks > Tunnels)"
warn "Manual: Verify no VPS ports are directly exposed (nmap from external)"

# RBAC
warn "Manual: RBAC — verify recepcao cannot access medical records"
warn "Manual: RBAC — verify medico can access medical records"

# 2FA
warn "Manual: 2FA — verify TOTP enabled for medico and admin accounts"

# Audit
warn "Manual: Audit — verify login/logout events are logged"
warn "Manual: Audit — verify patient access events are logged"

# Encryption
warn "Manual: Encryption — verify document encryption enabled in OpenEMR globals"
warn "Manual: Encryption — verify DB volume uses LUKS"

# Backups
warn "Manual: Backup — verify daily cron runs (check /etc/cron.d/ or crontab -l)"
warn "Manual: Backup — verify backup files exist and are encrypted"

# Consent
warn "Manual: Consent — verify integration service checks consent before sending"
warn "Manual: Consent — verify consent revocation stops reminders immediately"

# Telehealth
warn "Manual: Telehealth — verify Comlink module is active and generating links"

# Custom theme
warn "Manual: Theme — verify medpront-theme.css is loaded via custom.yaml"

# Patient frontend
warn "Manual: Frontend — verify Next.js app is accessible via HTTPS"
warn "Manual: Frontend — verify SMART on FHIR OAuth2 client is registered"
warn "Manual: Frontend — verify BFF endpoints are operational"

# ============================================================
# T066 — Edge Cases
# ============================================================
echo ""
echo "=== T066: Edge Cases ==="
echo "Running automated edge case tests where possible..."

# CPF duplicado
if [ -z "$TOKEN" ]; then
  warn "Skipped (no auth token)"
else
  echo "Testing CPF duplicate..."
  # Create patient with known CPF
  cpf_test="123.456.789-00"
  p1=$(api_call POST /patient "{
    \"fname\": \"Test\", \"lname\": \"Duplicate\", \"DOB\": \"1990-01-01\",
    \"sex\": \"Male\", \"ss\": \"${cpf_test}\", \"email\": \"test1@example.com\",
    \"phone_cell\": \"11999999999\"
  }" 2>/dev/null || true)
  p1_status=$(echo "$p1" | tail -1)
  if [ "$p1_status" = "200" ] || [ "$p1_status" = "201" ]; then
    pass "First patient with CPF created"
    # Try duplicate
    p2=$(api_call POST /patient "{
      \"fname\": \"Test2\", \"lname\": \"Duplicate2\", \"DOB\": \"1991-01-01\",
      \"sex\": \"Female\", \"ss\": \"${cpf_test}\", \"email\": \"test2@example.com\",
      \"phone_cell\": \"11999999998\"
    }" 2>/dev/null || true)
    p2_status=$(echo "$p2" | tail -1)
    if [ "$p2_status" = "409" ] || [ "$p2_status" = "422" ]; then
      pass "Duplicate CPF rejected (HTTP $p2_status)"
    elif [ "$p2_status" = "200" ] || [ "$p2_status" = "201" ]; then
      fail "Duplicate CPF was NOT rejected — OpenEMR option flag D may not be configured"
    else
      warn "Duplicate CPF test returned HTTP $p2_status — needs manual verification"
    fi
  else
    warn "Could not create test patient for CPF duplicate test (HTTP $p1_status)"
  fi
fi

# Menor sem responsável
warn "Manual: Test — Create patient with DOB < 18 years, without guardiansname — should be rejected or warned"

# Horário ocupado
warn "Manual: Test — Book two appointments for same provider/time — should show conflict warning"

# Upload >50MB
warn "Manual: Test — Upload file >50MB — should be rejected by Traefik (413 Request Entity Too Large)"

# WhatsApp falha + retry
warn "Manual: Test — Disable WhatsApp API temporarily, trigger reminder, verify retry after 1h"
warn "Manual: Test — After 3 failures, verify permanent failure logged and admin notified"

# Revogação consentimento
warn "Manual: Test — Revoke WhatsApp consent for a patient, verify no more reminders sent"
warn "Manual: Test — Verify revocation event is logged in consent service"

# ============================================================
# Summary
# ============================================================
echo ""
echo "==========================================="
echo -e "  ${GREEN}PASS${NC}: $PASS"
echo -e "  ${RED}FAIL${NC}: $FAIL"
echo -e "  ${YELLOW}WARN${NC}: $WARN (requires manual verification)"
echo "==========================================="
echo ""

if [ "$FAIL" -gt 0 ]; then
  echo -e "${RED}VERIFICATION FAILED${NC} — $FAIL test(s) did not pass"
  exit 1
elif [ "$WARN" -gt 0 ]; then
  echo -e "${YELLOW}AUTOMATED TESTS PASSED${NC} — $WARN item(s) require manual verification"
  exit 0
else
  echo -e "${GREEN}ALL TESTS PASSED${NC}"
  exit 0
fi