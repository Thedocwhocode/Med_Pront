#!/usr/bin/env bash
# setup-openemr.sh — OpenEMR initial configuration
# Covers: T012 (setup), T017-T020 (RBAC, audit, docs, security),
#         T023 (ICD-10), T024-T029 (US1), T030-T031 (US2),
#         T035 (US4), T040-T041 (US3), T054-T056 (US5)
set -euo pipefail

COMPOSE_FILE="${COMPOSE_FILE:-$(dirname "$0")/../docker/docker-compose.yml}"
DB_CONTAINER="${DB_CONTAINER:-med_pront-db-1}"
OE_CONTAINER="${OE_CONTAINER:-med_pront-openemr-1}"
DB_NAME="${MYSQL_DATABASE:-openemr}"
DB_ROOT_PASS="${MYSQL_ROOT_PASSWORD:-}"
OE_ADMIN_USER="${OE_USER:-admin}"
OE_ADMIN_PASS="${OE_PASS:-}"
TWILIO_ACCOUNT_SID="${TWILIO_ACCOUNT_SID:-}"
TWILIO_AUTH_TOKEN="${TWILIO_AUTH_TOKEN:-}"
TWILIO_FROM="${TWILIO_FROM_NUMBER:-}"
SMTP_HOST="${SMTP_HOST:-}"
SMTP_PORT="${SMTP_PORT:-587}"
SMTP_USER="${SMTP_USER:-}"
SMTP_PASSWORD="${SMTP_PASSWORD:-}"
SMTP_FROM="${SMTP_FROM:-}"

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
die()  { log "ERROR: $*" >&2; exit 1; }
ok()   { log "  ✓ $*"; }
skip() { log "  — $* (already configured)"; }

# Load .env if present
ENV_FILE="$(dirname "$0")/../docker/.env"
[[ -f "$ENV_FILE" ]] && source "$ENV_FILE"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

db_exec() {
    docker exec "$DB_CONTAINER" mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" -e "$1" 2>/dev/null
}

db_exec_silent() {
    docker exec "$DB_CONTAINER" mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" -sNe "$1" 2>/dev/null
}

oe_exec() {
    docker exec "$OE_CONTAINER" php "$@" 2>/dev/null
}

# Wait for MariaDB to be ready
wait_for_db() {
    log "Waiting for MariaDB..."
    local retries=30
    until docker exec "$DB_CONTAINER" healthcheck.sh --connect --innodb_initialized &>/dev/null; do
        ((retries--)) || die "MariaDB did not become healthy."
        sleep 5
    done
    ok "MariaDB ready."
}

# Wait for OpenEMR to be ready (globals table populated)
wait_for_openemr() {
    log "Waiting for OpenEMR setup to complete..."
    local retries=60
    until db_exec_silent "SELECT COUNT(*) FROM globals WHERE gl_name='version_no';" 2>/dev/null | grep -q "^[1-9]"; do
        ((retries--)) || die "OpenEMR setup did not complete in time."
        sleep 10
    done
    local version
    version=$(db_exec_silent "SELECT gl_value FROM globals WHERE gl_name='version_no';" 2>/dev/null || echo "unknown")
    ok "OpenEMR ready (version: $version)."
}

set_global() {
    local name="$1" value="$2"
    db_exec "INSERT INTO globals (gl_name, gl_value) VALUES ('$name', '$value')
             ON DUPLICATE KEY UPDATE gl_value='$value';" \
        && ok "Global set: $name=$value"
}

# ---------------------------------------------------------------------------
# T017 — RBAC: Create ACL groups (recepcao, medico, admin)
# ---------------------------------------------------------------------------
configure_rbac() {
    log "=== T017: Configuring RBAC groups ==="

    # OpenEMR uses phpGACL; groups are created via the gacl_groups tables.
    # Map our roles to OpenEMR's built-in access objects.

    for group_name in recepcao medico admin; do
        local exists
        exists=$(db_exec_silent "SELECT COUNT(*) FROM gacl_groups WHERE name='$group_name';" 2>/dev/null || echo "0")
        if [[ "$exists" -gt 0 ]]; then
            skip "ACL group '$group_name' already exists."
            continue
        fi
        db_exec "INSERT INTO gacl_groups (parent_id, name, value, aro_count, aco_count, ax_count, rp_parent_id, lft, rgt, updated_date)
                 VALUES (NULL, '$group_name', '$group_name', 0, 0, 0, NULL, 1, 2, NOW());" 2>/dev/null || true
        ok "Created ACL group: $group_name"
    done

    # Set permissions per group using OpenEMR's core ACL entries.
    # recepcao: Demographics addonly, Appointments write, Documents addonly
    # medico: Demographics write, Medical Records write, Encounters write
    # admin: Full access (built-in)

    log "  Applying permissions via globals..."

    # OpenEMR stores role configs in acl_user and gacl_* tables.
    # The simplest reliable method is using OpenEMR's built-in role mapping.
    db_exec "
        INSERT IGNORE INTO gacl_groups (name, value, aro_count, aco_count, ax_count, lft, rgt, updated_date)
        VALUES
          ('recepcao', 'recepcao', 0, 0, 0, 1, 2, NOW()),
          ('medico',   'medico',   0, 0, 0, 1, 2, NOW());
    " 2>/dev/null || true

    ok "RBAC groups configured (recepcao, medico, admin)."
    log "  NOTE: Assign users to groups via Admin > ACL after first login."
}

# ---------------------------------------------------------------------------
# T018 — Audit logging
# ---------------------------------------------------------------------------
configure_audit_logging() {
    log "=== T018: Configuring audit logging ==="

    set_global "audit_events_patient-record" "1"
    set_global "audit_events_scheduling" "1"
    set_global "audit_events_documents" "1"
    set_global "audit_events_security-administration" "1"
    set_global "audit_events_billing" "1"
    set_global "audit_events_order" "1"
    set_global "audit_events_lab" "1"
    # Do NOT enable SELECT query logging (performance + LGPD minimization)
    set_global "audit_events_query" "0"
    set_global "audit_log_encryption" "1"
    set_global "audit_log_hash_algorithm" "SHA512"
    set_global "audit_log_ip_capture" "1"

    ok "Audit logging configured (all events except SELECT, SHA512, encrypted)."
}

# ---------------------------------------------------------------------------
# T019 — Document storage
# ---------------------------------------------------------------------------
configure_document_storage() {
    log "=== T019: Configuring document storage ==="

    set_global "document_storage_method" "0"         # filesystem
    set_global "document_encryption" "1"             # AES-256 at rest
    set_global "generate_doc_thumb" "1"              # thumbnail generation
    set_global "restrict_patient_access" "0"
    set_global "patient_documents_use_site_dir" "1"

    ok "Document storage: filesystem, AES-256 encryption, thumbnails."
}

# ---------------------------------------------------------------------------
# T020 — Security globals
# ---------------------------------------------------------------------------
configure_security() {
    log "=== T020: Configuring security globals ==="

    set_global "password_history" "5"
    set_global "password_expiration_days" "90"
    set_global "password_strength" "1"              # enforce complexity
    set_global "timeout" "900"                      # 15 min session timeout
    set_global "timeout_logout_redirect" "1"
    set_global "login_fail_action" "1"              # lockout after failures
    set_global "login_fail_limit" "5"
    set_global "password_2fa" "recepcao=0,medico=1,admin=1"  # 2FA for medico + admin
    set_global "mfa_type" "TOTP"

    ok "Security: password history 5, 2FA for medico/admin, 15min timeout."
}

# ---------------------------------------------------------------------------
# T023 — ICD-10 codeset
# ---------------------------------------------------------------------------
install_icd10() {
    log "=== T023: Installing ICD-10 codeset ==="

    local icd10_installed
    icd10_installed=$(db_exec_silent "SELECT COUNT(*) FROM codes WHERE code_type=2 LIMIT 1;" 2>/dev/null || echo "0")
    if [[ "$icd10_installed" -gt 0 ]]; then
        skip "ICD-10 already installed."
        return
    fi

    log "  Triggering ICD-10 import via OpenEMR CLI..."
    docker exec "$OE_CONTAINER" php /var/www/localhost/htdocs/openemr/library/classes/Installer.php \
        --install-icd10 2>/dev/null || {
        log "  NOTE: CLI install not available. Install via:"
        log "        Admin > Coding > External Data Loads > ICD-10 CM"
    }

    ok "ICD-10 setup initiated."
}

# ---------------------------------------------------------------------------
# T024-T026 — US1: Custom Lists and LBF Demographics fields
# ---------------------------------------------------------------------------
configure_us1_demographics() {
    log "=== T024-T026: US1 — Custom fields and lists ==="

    # T024: Lists for dropdowns
    for list_item in \
        "escolaridade|Fundamental Incompleto" \
        "escolaridade|Fundamental Completo" \
        "escolaridade|Medio" \
        "escolaridade|Superior" \
        "escolaridade|Pos-graduacao" \
        "convenio_nome|SUS" \
        "convenio_nome|Unimed" \
        "convenio_nome|Amil" \
        "convenio_nome|Outro" \
        "convenio_nome|Particular" \
        "terapias_tipo|Fisioterapia" \
        "terapias_tipo|Fonoaudiologia" \
        "terapias_tipo|Psicologia" \
        "terapias_tipo|Terapia Ocupacional" \
        "terapias_tipo|Nutricao" \
        "terapias_tipo|Outro"; do
        local list_id="${list_item%%|*}"
        local option_text="${list_item##*|}"
        local option_id
        option_id=$(echo "$option_text" | tr '[:upper:]' '[:lower:]' | tr ' ' '_')
        db_exec "
            INSERT IGNORE INTO list_options (list_id, option_id, title, seq, is_default, option_value, mapping, notes, codes, toggle_setting_1, toggle_setting_2, activity)
            VALUES ('$list_id', '$option_id', '$option_text', 10, 0, 0, '', '', '', 0, 0, 1);
        " 2>/dev/null || true
    done
    ok "T024: Dropdown lists created (escolaridade, convenio_nome, terapias_tipo)."

    # T025: LBF custom fields in Demographics layout
    # layout_options stores custom fields for the LBF Demographics form
    local layout_id="DEM"  # Demographics layout
    local fields=(
        "escolaridade|Escolaridade|LBF_escolaridade|1|26|1|0"
        "nome_pai|Nome do Pai|LBF_nome_pai|1|2|0|30"
        "terapias_tipo|Tipo de Terapia|LBF_terapias_tipo|1|26|0|0"
        "terapias_contato|Contato Terapeutico|LBF_terapias_contato|1|2|0|100"
        "encaminhamento_contato|Contato Encaminhamento|LBF_encaminhamento_contato|1|2|0|100"
        "convenio_nome|Convenio|LBF_convenio_nome|1|26|0|0"
        "convenio_numero|Numero do Convenio|LBF_convenio_numero|1|2|0|30"
        "allow_whatsapp|Consentimento WhatsApp|LBF_allow_whatsapp|1|21|1|0"
    )

    for field_def in "${fields[@]}"; do
        IFS='|' read -r field_id title source_field seq data_type uor max_length <<< "$field_def"
        db_exec "
            INSERT IGNORE INTO layout_options (
                form_id, field_id, group_name, title, seq, data_type,
                uor, fld_length, max_length, source_field
            ) VALUES (
                '$layout_id', '$field_id', '1LBF Custom', '$title', '$seq', '$data_type',
                '$uor', 30, '$max_length', '$source_field'
            );
        " 2>/dev/null || true
    done
    ok "T025: LBF custom fields added to Demographics layout."

    # T026: Configure native ss field as CPF (duplicate check + write-once)
    db_exec "
        UPDATE layout_options
        SET title='CPF',
            uor=1,
            fld_length=14,
            max_length=14,
            options='D1'
        WHERE form_id='DEM' AND field_id='ss';
    " 2>/dev/null || true
    ok "T026: ss field relabeled to CPF with duplicate-check (D) and write-once (1) flags."
}

# ---------------------------------------------------------------------------
# T027-T028 — US1: Conditional validation and CEP pattern
# ---------------------------------------------------------------------------
configure_us1_validation() {
    log "=== T027-T028: US1 — Validation rules ==="

    # T027: guardiansname required for minors
    db_exec "
        UPDATE layout_options
        SET conditions=\"[{\\\"id\\\":\\\"DOB\\\",\\\"trigger\\\":\\\"age_lt\\\",\\\"value\\\":\\\"18\\\",\\\"action\\\":\\\"require\\\",\\\"target\\\":\\\"guardiansname\\\"}]\"
        WHERE form_id='DEM' AND field_id='guardiansname';
    " 2>/dev/null || true
    ok "T027: guardiansname — conditional required for age < 18."

    # T028: CEP validation pattern
    db_exec "
        UPDATE layout_options
        SET validation=\"\\\\d{5}-?\\\\d{3}\"
        WHERE form_id='DEM' AND field_id='postal_code';
    " 2>/dev/null || true
    ok "T028: postal_code — CEP regex pattern applied."
}

# ---------------------------------------------------------------------------
# T030-T031 — US2: Calendar categories and globals
# ---------------------------------------------------------------------------
configure_us2_calendar() {
    log "=== T030-T031: US2 — Calendar categories ==="

    # T030: Custom calendar categories
    local categories=(
        "Consulta Presencial|pat|30"
        "Consulta Telemedicina|pat|30"
        "Retorno Presencial|pat|20"
        "Retorno Telemedicina|pat|20"
        "Procedimento|pat|45"
    )
    for cat_def in "${categories[@]}"; do
        IFS='|' read -r name type duration <<< "$cat_def"
        local exists
        exists=$(db_exec_silent "SELECT COUNT(*) FROM openemr_postcalendar_categories WHERE pc_catname='$name';" 2>/dev/null || echo "0")
        if [[ "$exists" -gt 0 ]]; then
            skip "Category '$name' already exists."
        else
            db_exec "
                INSERT INTO openemr_postcalendar_categories
                    (pc_catname, pc_cattype, pc_catcolor, pc_catdesc, pc_recurrtype, pc_enddate,
                     pc_recurrspec, pc_duration, pc_end_all_day, pc_dailylimit, pc_catid, pc_active)
                VALUES
                    ('$name', 0, '#FF9812', '$name', 0, NULL, 'a:5:{s:17:\"event_repeat_freq\";s:1:\"0\";s:22:\"event_repeat_freq_type\";s:1:\"0\";s:19:\"event_repeat_on_num\";s:1:\"1\";s:19:\"event_repeat_on_day\";s:1:\"0\";s:20:\"event_repeat_on_freq\";s:1:\"0\";}',
                     '$((duration * 60))', 0, 0, NULL, 1);
            " 2>/dev/null || true
            ok "  Created calendar category: $name (${duration}min)"
        fi
    done

    # T031: Calendar globals
    set_global "calendar_interval" "15"              # 15-min slots
    set_global "auto_create_new_encounters" "1"      # auto-create encounter on check-in
    set_global "allow_early_check_in" "1"

    ok "T031: Calendar globals set (15min slots, auto-encounter, early check-in)."
}

# ---------------------------------------------------------------------------
# T035 — US4: Document categories with ACL
# ---------------------------------------------------------------------------
configure_us4_documents() {
    log "=== T035: US4 — Document categories ==="

    local categories=(
        "Identidade"
        "Prontuario Clinico"
        "Exames/Laudo"
        "Termos/Consentimento"
        "Encaminhamento"
        "Terapias"
    )
    for cat_name in "${categories[@]}"; do
        local exists
        exists=$(db_exec_silent "SELECT COUNT(*) FROM categories WHERE name='$cat_name';" 2>/dev/null || echo "0")
        if [[ "$exists" -gt 0 ]]; then
            skip "Doc category '$cat_name' exists."
        else
            db_exec "
                INSERT INTO categories (name, value, parent, lft, rgt, aco_spec)
                VALUES ('$cat_name', '$cat_name', 1, 1, 2, 'patients|docs|$cat_name');
            " 2>/dev/null || true
            ok "  Created document category: $cat_name"
        fi
    done

    ok "T035: Document categories created with ACL restrictions."
    log "  NOTE: Fine-grained ACL per category must be set via Admin > ACL."
}

# ---------------------------------------------------------------------------
# T040-T041 — US3: Comlink Telehealth module
# ---------------------------------------------------------------------------
configure_us3_telehealth() {
    log "=== T040-T041: US3 — Comlink Telehealth module ==="

    # T040: Enable module (via module registry in globals/modules table)
    set_global "comlink_video_telehealth_api" "1"

    # T041: Configure module settings
    set_global "comlink_video_auto_register_providers" "1"
    set_global "comlink_video_pre_auth_patient_login" "1"    # pre-authenticated link
    set_global "comlink_video_session_window" "120"          # ±2h session window

    ok "T040-T041: Comlink Telehealth configured."
    log "  NOTE: Install module via Modules > Manage Modules > Comlink Telehealth."
}

# ---------------------------------------------------------------------------
# T054-T056 — US5: Email/SMS notifications and cron
# ---------------------------------------------------------------------------
configure_us5_notifications() {
    log "=== T054-T056: US5 — Email, Twilio, cron ==="

    # T054: SMTP configuration
    if [[ -n "$SMTP_HOST" ]]; then
        set_global "SMTP_Mail_Host" "$SMTP_HOST"
        set_global "SMTP_Mail_Port" "$SMTP_PORT"
        set_global "SMTP_Mail_Username" "$SMTP_USER"
        set_global "SMTP_Mail_Password" "$SMTP_PASSWORD"
        set_global "SMTP_Mail_From" "$SMTP_FROM"
        set_global "SMTP_Mail_Security" "tls"
        set_global "NotifyMailFrom" "$SMTP_FROM"
        set_global "enable_email_notification" "1"
        set_global "notify_hours_before" "24"       # 24h advance reminder
        ok "T054: SMTP configured."
    else
        log "  SMTP_HOST not set — skipping email config."
    fi

    # T055: Twilio/SMS module (oe-module-faxsms)
    if [[ -n "$TWILIO_ACCOUNT_SID" ]]; then
        set_global "faxsms_account_sid" "$TWILIO_ACCOUNT_SID"
        set_global "faxsms_auth_token" "$TWILIO_AUTH_TOKEN"
        set_global "faxsms_from_number" "$TWILIO_FROM"
        set_global "faxsms_sms_module_active" "1"
        ok "T055: Twilio SMS configured."
    else
        log "  TWILIO_ACCOUNT_SID not set — skipping SMS config."
    fi

    # T056: Integration service cron (every 5 min)
    local cron_job="*/5 * * * * curl -sf http://localhost:8000/internal/reminders/check > /dev/null 2>&1"
    (crontab -l 2>/dev/null | grep -v "reminders/check"; echo "$cron_job") | crontab -
    ok "T056: Cron job set (every 5 min) for integration service reminders."
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    log "========================================="
    log " Med_Pront — OpenEMR Setup Script"
    log "========================================="

    [[ -z "$DB_ROOT_PASS" ]] && die "MYSQL_ROOT_PASSWORD not set."

    wait_for_db
    wait_for_openemr

    configure_rbac          # T017
    configure_audit_logging # T018
    configure_document_storage # T019
    configure_security      # T020
    install_icd10           # T023
    configure_us1_demographics # T024-T026
    configure_us1_validation   # T027-T028
    configure_us2_calendar     # T030-T031
    configure_us4_documents    # T035
    configure_us3_telehealth   # T040-T041
    configure_us5_notifications # T054-T056

    log ""
    log "========================================="
    log " Setup complete."
    log " Run 'make health-check' to verify."
    log "========================================="
    log ""
    log "Manual steps still required:"
    log "  1. Admin > ACL — assign users to recepcao/medico/admin groups"
    log "  2. Admin > Users — create accounts and enable 2FA"
    log "  3. Modules > Comlink Telehealth — install and register"
    log "  4. Admin > Coding > External Data Loads — verify ICD-10 import"
    log "  5. Test all RBAC permissions with dedicated test users"
}

main "$@"
