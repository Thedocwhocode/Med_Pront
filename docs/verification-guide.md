# Manual Verification Guide: Med_Pront

**Purpose**: Step-by-step manual verification for all items that cannot be automated in `scripts/verify-all.sh`.
**Audience**: QA / DevOps / Release Approver
**Prerequisites**: OpenEMR running, integration service running, VPS hardened, Cloudflare Tunnel active.

---

## 1. Infrastructure Verification

### 1.1 HTTPS & Cloudflare Tunnel

- [ ] Access `https://<domain>/openemr` — should load without certificate warnings
- [ ] Verify HTTP→HTTPS redirect works: `curl -I http://<domain>` should return 301/302 to HTTPS
- [ ] Check Cloudflare dashboard > Zero Trust > Networks > Tunnels — tunnel status should be "Healthy"
- [ ] From an external network, run `nmap <vps-ip> -p 80,443,8080,8443` — only filtered/closed ports should appear (no open ports directly on VPS)

### 1.2 VPS Hardening

- [ ] SSH: `ssh -o PasswordAuthentication=no root@<vps>` — should fail if password auth is disabled
- [ ] Fail2ban: `sudo systemctl status fail2ban` — should be active
- [ ] UFW: `sudo ufw status` — should show only Cloudflare IPs and SSH
- [ ] Unattended upgrades: `sudo systemctl status unattended-upgrades` — should be active

### 1.3 Docker Services

- [ ] `docker compose ps` — all 6 services should show "Up" or "healthy"
- [ ] `docker compose logs traefik --tail=20` — no TLS errors
- [ ] `docker compose logs openemr --tail=20` — OpenEMR startup complete
- [ ] `docker compose logs integration --tail=20` — FastAPI started on port 8000
- [ ] Health check: `curl -s http://localhost:8000/health` should return `{"status":"ok"}`

---

## 2. RBAC Verification

### 2.1 Create Test Users

For each profile, create a dedicated test user:

1. **recepcao_test**: ACL group `recepcao`
2. **medico_test**: ACL group `medico`
3. **admin_test**: ACL group `admin`

### 2.2 RBAC Tests — Recepcao

Login as `recepcao_test`:

- [ ] Can create new patient (Demographics > Add)
- [ ] Can view patient demographics (read)
- [ ] **Cannot** edit patient demographics (should see read-only or access denied)
- [ ] Can create/edit appointments
- [ ] Can upload documents to Identidade category
- [ ] Can upload documents to Termos/Consentimento category
- [ ] **Cannot** access Prontuario Clinico category
- [ ] **Cannot** access Exames/Laudo category
- [ ] **Cannot** access Encaminhamento category
- [ ] **Cannot** access Terapias category

### 2.3 RBAC Tests — Medico

Login as `medico_test`:

- [ ] Can create and edit patient demographics (write access)
- [ ] Can create encounters
- [ ] Can access Prontuario Clinico documents
- [ ] Can access Exames/Laudo documents
- [ ] Can access all document categories
- [ ] Can view and edit medical records
- [ ] **Cannot** access admin functions (ACL restrictions)

### 2.4 RBAC Tests — Admin

Login as `admin_test`:

- [ ] Full access to all modules
- [ ] Can manage users
- [ ] Can manage ACL groups
- [ ] Can access all document categories
- [ ] Can view audit logs

---

## 3. 2FA Verification

- [ ] Login as medico_test — should prompt for TOTP code after password
- [ ] Login as admin_test — should prompt for TOTP code after password
- [ ] Login as recepcao_test — TOTP should NOT be required (optional for this profile)
- [ ] Test TOTP fallback: enter wrong code 3 times — should lock for a period

---

## 4. Audit Logging Verification

### 4.1 Login/Logout Events

- [ ] Login as any user → check audit log for login event
- [ ] Logout → check audit log for logout event
- [ ] Failed login attempt → check audit log for failed login event

### 4.2 Patient Access Events

- [ ] View a patient's demographics → audit log should record access
- [ ] Edit a patient's demographics → audit log should record the change
- [ ] Access a restricted document (as recepcao) → audit log should record denied access attempt

### 4.3 Appointment Events

- [ ] Create appointment → audit log should record creation
- [ ] Change appointment status → audit log should record status change
- [ ] Cancel appointment → audit log should record cancellation

### 4.4 Document Events

- [ ] Upload document → audit log should record upload
- [ ] Access document → audit log should record access
- [ ] Change document category → audit log should record category change

### 4.5 Audit Log Integrity

- [ ] Verify audit log entries have encrypted content (SHA512 hash)
- [ ] Verify SELECT queries are NOT logged (performance)
- [ ] Verify IP address is captured in audit events

---

## 5. Document Encryption Verification

### 5.1 Encryption at Rest

- [ ] Upload a test PDF via OpenEMR UI
- [ ] SSH into VPS and run:
  ```bash
  docker exec -it med_pront-openemr-1 ls /var/www/localhost/htdocs/openemr/sites/default/documents/
  ```
- [ ] Verify files are NOT readable plaintext (should be encrypted binary)
- [ ] In OpenEMR: Administration > Globals > Documents > Encryption should be "Enabled"

### 5.2 Volume Encryption (LUKS)

- [ ] Verify DB volume uses LUKS encryption:
  ```bash
  lsblk -o NAME,FSTYPE,SIZE,MOUNTPOINT
  # Should show crypt/luks for db_data volume
  ```

---

## 6. Telehealth Verification

### 6.1 Telehealth Link Generation

- [ ] Create appointment with category "Consulta Telemedicina"
- [ ] Verify telehealth link appears in appointment details
- [ ] Verify link uses the configured Comlink domain
- [ ] Verify link is accessible within the configured time window (+/- 2h)

### 6.2 Patient Prerequisites

- [ ] Verify patient has email in demographics
- [ ] Verify patient has "Allow Email" enabled
- [ ] Verify patient has "Allow Patient Portal" enabled
- [ ] Verify patient has portal credentials (username/password set)

### 6.3 Encounter Telemedicine Modality

- [ ] Complete a telehealth appointment (check-in → check-out)
- [ ] Open the resulting encounter
- [ ] Verify encounter is linked to the telemedicine category appointment

---

## 7. LGPD Compliance Verification

### 7.1 Consent Management

- [ ] Create patient with all consent options enabled (SMS, email, WhatsApp)
- [ ] Call `GET /internal/consent/{pid}` — should return `{"sms": true, "email": true, "whatsapp": true}`
- [ ] Revoke WhatsApp consent: `POST /internal/consent/{pid}/revoke` with `{"channel": "whatsapp"}`
- [ ] Call `GET /internal/consent/{pid}` — should now return `{"sms": true, "email": true, "whatsapp": false}`
- [ ] Verify no WhatsApp reminders are sent after revocation

### 7.2 Data Minimization in Reminders

- [ ] Check WhatsApp template in Meta Business Suite — should have ONLY these parameters: `patient_name`, `date`, `time`, `type`
- [ ] Verify template does NOT contain: diagnosis, CID, medications, clinical notes
- [ ] Check email template in `docker/integration-service/src/adapters/email.py` — should contain no clinical data
- [ ] Verify `content_hash` is logged instead of actual message content

### 7.3 Patient Rights

- [ ] **Access**: Patient can view their record via Patient Portal
- [ ] **Rectification**: Doctor/admin can edit patient demographics (except CPF with flag `1`)
- [ ] **Revocation**: Consent can be revoked via API endpoint with immediate effect
- [ ] **Portability**: Data can be exported via OpenEMR Reports

---

## 8. Edge Cases Verification

### 8.1 CPF Duplicado

- [ ] Create patient with CPF "123.456.789-00"
- [ ] Try to create a second patient with the same CPF
- [ ] Expected: rejection with error message (OpenEMR option flag `D`)
- [ ] Covered by: `scripts/verify-all.sh` (automated)

### 8.2 Menor sem Responsável

- [ ] Create patient with DOB indicating age < 18
- [ ] Leave `guardiansname` field empty
- [ ] Expected: validation error requiring guardian name
- [ ] Note: Conditional validation via OpenEMR layout configuration

### 8.3 Horário Ocupado

- [ ] Book appointment for Provider A at 10:00-10:30
- [ ] Try to book a second appointment for Provider A at the same time
- [ ] Expected: conflict warning (not a hard block — provider can override)
- [ ] Note: OpenEMR shows warning but allows double-booking by default

### 8.4 Upload > 50MB

- [ ] Upload a file larger than 50MB via OpenEMR
- [ ] Expected: rejection with 413 Request Entity Too Large
- [ ] Covered by: Traefik `client_max_body_size: 50MB` in dynamic.yml

### 8.5 WhatsApp Failure + Retry

- [ ] Disable WhatsApp API (change token to invalid value)
- [ ] Trigger a reminder for a consented patient
- [ ] Expected: reminder fails, retry queued for 1 hour later
- [ ] After 3 failures: permanent failure logged, admin notified via email
- [ ] Covered by: `scripts/verify-all.sh` (manual step)

### 8.6 Consent Revocation

- [ ] Revoke WhatsApp consent for a patient
- [ ] Verify no more WhatsApp reminders are sent
- [ ] Verify revocation event is logged in consent service
- [ ] Re-enable consent and verify reminders resume
- [ ] Covered by: `scripts/verify-all.sh` (manual step)

---

## 9. Backup Verification

### 9.1 Daily Backup

- [ ] Run `make backup-test` or `docker/backup/backup.sh`
- [ ] Verify encrypted dump file exists in `backup_data/`
- [ ] Verify dump is AES-256 encrypted (not readable plaintext)
- [ ] Check cron is configured: `crontab -l | grep backup`

### 9.2 Restore Test

- [ ] Run `docker/backup/restore.sh <backup-file>`
- [ ] Verify data integrity after restore
- [ ] Verify application functions correctly after restore

---

## 10. Custom Theme Verification

- [ ] Login to OpenEMR
- [ ] Verify medpront-theme.css is loaded (check browser DevTools > Network tab)
- [ ] Verify custom.yaml is active (Administration > Globals > Appearance should show theme settings)
- [ ] Check sidebar styling matches design system (teal/azul-esverdeado primary color)
- [ ] Check typography hierarchy (titles, body text, labels)

---

## 11. Patient Frontend Verification (Future — Phase 5/6)

- [ ] Next.js app accessible via HTTPS
- [ ] SMART on FHIR OAuth2 client registered in OpenEMR
- [ ] Login flow: patient authenticates → redirected to portal
- [ ] BFF endpoints operational (registration, demographics, appointment, document upload)
- [ ] Data minimization: no clinical data in patient-facing responses

---

## Verification Results Template

| Category | Pass | Fail | Warn | N/A |
|----------|------|------|------|-----|
| 1. Infrastructure | | | | |
| 2. RBAC | | | | |
| 3. 2FA | | | | |
| 4. Audit Logging | | | | |
| 5. Encryption | | | | |
| 6. Telehealth | | | | |
| 7. LGPD Compliance | | | | |
| 8. Edge Cases | | | | |
| 9. Backup | | | | |
| 10. Custom Theme | | | | |
| 11. Patient Frontend | | | | |
| **TOTAL** | | | | |

**Approver**: _________________ **Date**: _________________

**Decision**: [ ] APPROVED FOR RELEASE  [ ] BLOCKED — See failures above