# Research: Med_Pront — OpenEMR 7.x Configuration & Integration

**Date**: 2026-05-04 | **Status**: Complete | **Branch**: main

## 1. Demographics + Layout Based Forms (LBF)

### Decision
Use OpenEMR's native Layout Based Forms (LBF) to customize the Demographics
form. Mix native fields with repurposed User Defined fields and new custom
fields.

### Native Fields (reuse or relabel)

| Need | Native Column | Status |
|------|---------------|--------|
| Nome completo | `title`, `fname`, `mname`, `lname` | Native |
| Data de nascimento | `DOB` | Native |
| CPF | `ss` (repurpose label to "CPF") | Native — add option flag `D` (duplicate check) and `1` (write-once) |
| Nome da mae | `mothersname` | Native |
| Responsavel legal | `guardiansname`, `guardianrelationship`, `guardianphone` | Native |
| Encaminhamento | `referral_source`, `referrer` | Native |
| Sexo/Genero | `sex`, `sex_identified`, `gender_identity` | Native |
| Endereco completo | `street`, `city`, `state`, `postal_code`, `country` | Native |
| E-mail | `email`, `email_direct` | Native |
| Celular/WhatsApp | `phone_home`, `phone_cell`, `phone_biz` | Native |
| Convenio | Insurance fields (multiple) | Native |

### Custom Fields Required (via LBF)

| Field | LBF Field ID | Data Type | Notes |
|-------|-------------|-----------|-------|
| Escolaridade | `usertext1` or new | Dropdown list | Create list: Fundamental, Medio, Superior, Pos-graduacao |
| Nome do Pai | `usertext2` or new | Textbox | No native "father's name" |
| Terapias/Reabilitacao | `usertext3` or new | Multi-select or Textbox | List of therapy types + team contacts |
| Consentimento LGPD | `hipaa_allowsms` (repurpose) | Checkbox | Already exists for SMS; extend for LGPD |
| CID por paciente | N/A — use Issues list | ICD-10 lookup | NOT a demographics field |

### Configuration Steps
1. Admin > Forms > Layouts > Demographics — edit labels, add UOR (Unused/Optional/Required)
2. Admin > Forms > Lists — create dropdown options (e.g., escolaridade)
3. New fields stored in `patient_data` via `layout_options` table

### Alternatives Considered
- **Direct DB column addition**: Rejected — LBF handles this without schema changes
- **External module for CPF validation**: Viable future option for mask/validator

---

## 2. Calendar Module — Appointment Types & Statuses

### Decision
Create custom appointment categories for "presencial" and "telemedicina" using
Calendar Categories. Customize appointment statuses via List Manager.

### Appointment Categories

| Category Name | Type | Color | Duration |
|--------------|------|-------|----------|
| Consulta Presencial | Patient | Blue | 30 min |
| Consulta Telemedicina | Patient | Green | 30 min |
| Retorno Presencial | Patient | Light Blue | 20 min |
| Retorno Telemedicina | Patient | Light Green | 20 min |
| Procedimento | Patient | Orange | 45 min |

Plus fixed categories: In Office, Out of Office, Lunch.

### Appointment Statuses (default)

| ID | Title | Type |
|----|-------|------|
| `*` | Confirmed | — |
| `+` | Arrived | — |
| `@` | Checked In | Check In |
| `#` | In Exam Room | — |
| `>` | Checked Out | Check Out |
| `-` | Canceled | — |
| `%` | No Show | — |

### Key Calendar Globals

| Setting | Value |
|---------|-------|
| Calendar Interval | 15 min |
| Auto-Create New Encounters | One per appointment |
| Allow Early Check In | Yes |

### Alternatives Considered
- **Single category with status field**: Rejected — separate categories give visual distinction and duration control

---

## 3. RBAC Configuration

### Decision
Create three ACL groups: recepcao, medico, admin.

### Perfil Recepcao
- Demographics: `addonly` (create + view, no edit)
- Appointments: `write`
- Documents: `addonly`
- Patient Notes: `addonly`
- **Cannot access**: billing, medical record editing, ACL admin

### Perfil Medico
- Demographics: `write`
- Medical Records: `write`
- Appointments: `write`
- Documents: `write`
- Encounters/Coding/Notes: `write`
- Sensitivities (Normal, High): `write`
- **Cannot access**: admin functions, ACL admin

### Perfil Admin
- Full access: superuser, all admin, all patient data, ACL administration

### Important Caveats
- ACL interface is complex — test thoroughly with dedicated test user
- Custom ACL groups **cannot be edited** after creation (must delete and recreate)
- Editing Demographics ACL also affects Insurance data access

---

## 4. Audit/Logging Configuration

### Decision
Enable comprehensive audit logging with encryption. Disable SELECT query logging
for performance.

### Key Settings (Admin > Globals > Logging)

| Setting | Value |
|---------|-------|
| Enable Audit Logging | On |
| Audit Logging Patient Record | On |
| Audit Logging Scheduling | On |
| Audit Logging Order | On |
| Audit Logging Security Administration | On |
| Audit Logging Backups | On |
| Audit Logging Miscellaneous | On |
| Audit Logging SELECT Query | Off |
| Enable Audit Log Encryption | On |

### Security Settings

| Setting | Value |
|---------|-------|
| Hash Algorithm | SHA512 |
| Password Expiration | 90 days |
| Password History | 5 (prevent reuse) |

### What Gets Logged
Date/time, Component, Event type (Insert/Update/Delete), User, Patient ID,
Status, Checksum (integrity), Description.

---

## 5. Documents Module — Upload & Encrypted Storage

### Decision
Use filesystem storage with AES-256 encryption at rest via OpenEMR's CryptoGen.

### Key Settings

| Setting | Value |
|---------|-------|
| document_storage_method | 0 (filesystem) |
| drive_encryption | On (AES-256) |
| generate_doc_thumb | On |

### Document Categories (with ACL restrictions)

| Category | ACL Restriction |
|----------|----------------|
| Identidade | recepcao, medico, admin |
| Prontuario Clinico | medico, admin |
| Exames/Laudo | medico, admin |
| Termos/Consentimento | recepcao, medico, admin |
| Encaminhamento | medico, admin |
| Terapias | medico, admin |

### Storage Path
`{site_dir}/documents/{patient_id}/{uuid_filename}` on encrypted volume.

### Alternatives Considered
- **CouchDB storage**: Rejected — adds operational complexity without clear benefit
- **No encryption**: Rejected — LGPD/HIPAA requires encryption at rest

---

## 6. Telehealth — Comlink Module

### Decision
Use Comlink Telehealth module (included in OpenEMR 7.x). Start with vendor
($9.95/mo/provider), plan migration to self-hosted Jitsi-Meet.

**Migration Timeline** (CHK078):
- **Fase 0-5 (MVP)**: Comlink vendor ($9.95/mo/provider) — validação do fluxo de telemedicina
- **Fase 6 (Pós-MVP, target Q4 2026)**: Deploy Jitsi-Meet self-hosted na VPS (container Docker dedicado, rede interna)
- **Fase 6+ (Q1 2027)**: Corte definitivo do Comlink vendor, dados migrados para self-hosted
- **Critério de migração**: fluxo de telemedicina estável por 3 meses consecutivos com vendor
- **Custo estimado self-hosted**: apenas recursos de VPS (sem custo adicional de licenciamento)

### Configuration Steps
1. Modules > Manage Modules > Register > Install > Enable Comlink Telehealth
2. Configure credentials (vendor or self-hosted Jitsi)
3. Enable: Auto Register Providers, Pre-Authenticated Patient Login Link
4. Calendar categories auto-created: "Telehealth Established/New Patient"

### Patient Prerequisites
- Contact email in demographics
- Allow Email + Allow Patient Portal enabled
- Patient portal credentials created

### Security
- Self-hosted Jitsi provides better HIPAA/LGPD control
- Sessions launch only within +/-2 hours of appointment time

---

## 7. Notification/SMS Module

### Decision
Use `oe-module-faxsms` module with Twilio for SMS + built-in cron/SMTP for
email. Build custom integration service for WhatsApp Business API.

### Channel Architecture

| Channel | Technology | Gateway |
|---------|-----------|---------|
| SMS | oe-module-faxsms | Twilio (+55 Brazil) |
| Email | Built-in cron + SMTP | Mailgun or Gmail SMTP |
| WhatsApp | Custom integration service | WhatsApp Business API |

### Key Configuration

**Email Reminders (Admin > Globals > Notifications):**
- SMTP Host/Port/Security/TLS
- Notification Hours: 24 (send reminder 24h before)
- Cron: `0 */1 * * * php .../cron_email_notification.php`

**SMS (oe-module-faxsms):**
- Twilio Account SID + Auth Token + From Number
- Cron: `*/5 * * * * php .../cron_sms_notification.php`

**WhatsApp (custom integration service):**
- Poll OpenEMR API for appointments 24h ahead
- Filter patients with consent
- Send minimal reminder via WhatsApp Business API
- Log all sends and failures

### Message Template (LGPD-compliant)
```
Ola ***NAME***, lembramos sua consulta ***DATE*** as ***STARTTIME***
(***PROVIDER***). Tipo: presencial/telemedicina. Duvidas: tel. clinica.
```
**No clinical data, no diagnosis, no CID codes.**

### Patient Opt-In
- `hipaa_allowsms` → SMS consent
- `hipaa_allowemail` → Email consent
- Custom field `allow_whatsapp` → WhatsApp consent (via LBF)

---

## 8. ICD-10/11 Coding per Patient

### Decision
Use OpenEMR's native Issues/Diagnosis list for ICD-10 coding per patient.
ICD-11 is not yet natively supported.

### Configuration Steps
1. Admin > Coding > External Data Loads > ICD10 > INSTALL
2. Admin > Forms > Lists > Code Types > Toggle ICD10 Active
3. Import CID-10-BR (Brazilian Portuguese adaptation) as custom codeset
4. Patient chart > Issues > Add ICD10 codes
5. Yearly updates from CMS

---

## 9. Infrastructure & Security

### Decision
Self-hosted VPS with Cloudflare Tunnel (Zero-Trust), Docker Compose, encrypted
volumes.

### Key Infrastructure Decisions

| Component | Decision | Rationale |
|-----------|----------|-----------|
| Reverse Proxy | Traefik | Auto-TLS via Cloudflare Origin Cert, simpler than Nginx for Docker |
| DB | MariaDB 10.11 | OpenEMR officially supports MariaDB |
| Orchestration | Docker Compose | Appropriate for single-clinic scale |
| Tunnel | Cloudflare Tunnel | Zero-Trust, WAF included, no open ports |
| Backup | Daily encrypted dumps + S3-like | AES-256, rotation 30d daily + 12mo monthly |
| Integration Service | Python FastAPI | Lightweight, async, good WhatsApp API support |
| VPS OS | Debian 12 LTS | Stability, security, Docker support |

### Security Hardening Checklist
- SSH key-only + 2FA (fail2ban)
- UFW: only 80/443 from Cloudflare IPs
- Encrypted volumes (LUKS) for DB and documents
- Audit log encryption enabled
- 2FA for medico and admin profiles
- Rate limiting on reverse proxy
- Health checks on all containers
- Quarterly restore tests

---

## 10. Custom Theme Mechanism (TC-1)

### Decision
Use the `custom.yaml` injection mechanism at `/custom/assets/custom.yaml` with Docker bind-mount for custom CSS that survives upgrades.

### How It Works
OpenEMR 7.0.2's `Header.php` (at `src/Core/Header.php`) checks for `/custom/assets/custom.yaml`. If present, it parses the YAML and merges declared assets into every page where `Header::setupHeader()` is called (essentially every page).

### Implementation
1. Add Docker volume mount: `./openemr/custom/:/var/www/localhost/htdocs/openemr/custom/`
2. Create `custom.yaml` declaring CSS assets (medpront-theme.css)
3. CSS file loaded after compiled theme CSS, so selectors take precedence
4. Use `:root` CSS custom properties for design tokens
5. Use `!important` selectively only against Bootstrap utility classes with high specificity

### Alternatives Considered
- **Custom SCSS theme in `interface/themes/`**: REJECTED — requires SCSS build toolchain in container; compiled CSS overwritten on `docker pull`; must register in database; effectively forks OpenEMR
- **CSS in `sites/default/`**: REJECTED — no built-in injection mechanism from `sites/`
- **Symfony EventFilterEvent module**: VIABLE for future (per-page conditional CSS) but overkill for pure CSS theming
- **Traefik middleware injection**: REJECTED — wrong abstraction layer, fragile HTML parsing

### Sources
- OpenEMR Header.php source (github.com/openemr/openemr/blob/master/src/Core/Header.php)
- PR #2232: Custom Assets Feature
- PR #3839: Removal of Theme Builder
- Issue #5681: Header Event Hooks for JS/CSS

---

## 11. Patient Portal Architecture (TC-2)

### Decision
**Hybrid approach (Approach C)** — Keep native portal for secure messaging, build external React/Next.js app for all other patient-facing flows. Planned migration to full external app (Approach B) as OpenEMR FHIR write APIs mature.

### Portal Assessment
The OpenEMR Patient Portal is a built-in, separate web app at `/portal/` path. It uses a hybrid architecture:
- Legacy PHP pages (portal/*.php)
- SPA application using Phreeze framework (PHP MVC)
- Document templates with Summernote WYSIWYG
- Dual-session model (patient vs staff)

### Why NOT Extend (Approach A)
- Portal is monolithic PHP with no extension points
- No mobile-first capability (Bootstrap 4, modals clip on phones, no responsive grid)
- No template override mechanism that survives upgrades
- AngularJS messaging components on dead framework (Issue #6523)
- Deep forking required, unsustainable maintenance burden

### Why Hybrid (Approach C)
- Portal messaging works — rebuilding is significant effort with no incremental value
- FHIR read APIs are production-ready today (30+ resources with `patient/*` scope)
- Integration service already serves as BFF for write operations
- Portal needs near-zero customization (only logo/branding globals)
- Clean migration path as FHIR write APIs mature

### Migration Path (C → B)
1. Phase 1 (now): Next.js reads via FHIR, writes via integration service BFF
2. Phase 2 (when FHIR Appointment POST merges, PR #11507): Move appointment creation to direct FHIR
3. Phase 3 (when FHIR DocumentReference POST merges, Issue #9076): Move document upload to direct FHIR
4. Phase 4 (when portal messaging rebuilt as API): Move messaging to Next.js, retire portal access

### Sources
- OpenEMR Patient Portal Wiki
- PR #6530: Portal Restructure
- PR #6560: Portal Portrait Mode
- Issue #6523: Portal AngularJS deprecation
- Issue #9076: FHIR Write Operations Epic
- PR #11507: FHIR Appointment Write
- PR #7333: Appointment PUT/PATCH

---

## 12. FHIR/REST API Endpoints for Patient Flows (TC-3)

### Decision
**Dual-API strategy**: FHIR R4 for read operations (patient scope), Standard REST via integration service BFF for write operations (client_credentials scope).

### FHIR R4 API (patient/* scope — read-only)

| Resource | Scope | Read | Write | Notes |
|----------|-------|------|-------|-------|
| Patient | patient/Patient.rs | ✅ | POST/PUT (create/update) | Only writable FHIR resource for patients |
| Appointment | patient/Appointment.rs | ✅ | No (PR #11507 pending) | Read-only |
| Encounter | patient/Encounter.rs | ✅ | No | Read-only |
| DocumentReference | patient/DocumentReference.rs | ✅ | No (Priority 6, Issue #9076) | Read + $docref CCD |
| Observation | patient/Observation.rs | ✅ | No | Vitals, labs, surveys |
| Condition | patient/Condition.rs | ✅ | No | Problems, health concerns |
| MedicationRequest | patient/MedicationRequest.rs | ✅ | No | Read-only |
| AllergyIntolerance | patient/AllergyIntolerance.rs | ✅ | No | Read-only |
| + 20+ more | Read-only | ✅ | No | See FHIR API docs |

### Standard REST API (api:oemr scope — staff credentials)

| Endpoint | Method | Description | Patient-accessible via BFF |
|----------|--------|-------------|---------------------------|
| /api/patient | POST | Create patient | ✅ via BFF (pre-cadastro) |
| /api/patient/{puuid} | PUT | Update patient | ✅ via BFF (atualização cadastral) |
| /api/patient/{pid}/appointment | POST | Create appointment | ✅ via BFF (agendamento) |
| /api/patient/{pid}/document?path={cat} | POST | Upload document | ✅ via BFF (envio de exames) |
| /api/appointment/{eid} | PUT/PATCH | Update appointment | ❌ PR #7333 not merged |

### Portal REST API (EXPERIMENTAL)
Only 3 read-only endpoints: Patient.r, Encounter.rs, Appointment.rs. NOT production-ready.

### Critical Gaps
1. **No patient self-registration API** — BFF must create patient via Standard REST
2. **No appointment status update** — PR #7333 pending; BFF must use direct DB or custom module
3. **No programmatic portal credential generation** — staff must create portal credentials manually
4. **No FHIR write for Appointment/DocumentReference** — Issue #9076 epic tracking

### BFF Architecture
Integration service (Python FastAPI at `docker/integration-service/`) extends to serve as BFF:
- Patient authenticates via SMART on FHIR (Authorization Code + PKCE)
- BFF receives patient Bearer token, validates patient identity
- BFF uses `client_credentials` to call Standard REST API on patient's behalf
- BFF enforces: consent verification, data minimization (strip clinical fields), audit logging

### Sources
- OpenEMR Standard API Documentation (GitHub)
- OpenEMR FHIR API Documentation (GitHub)
- OpenEMR Authentication/Authorization Documentation (GitHub)
- PR #7333: Appointment PATCH
- Issue #9076: FHIR Write Operations Epic

---

## 13. Bootstrap Override Strategy (TC-4)

### Decision
CSS custom properties + selective `!important` overrides via custom.yaml. OpenEMR 7.0.2 uses **Bootstrap 4.6.2** (NOT Bootstrap 5).

### Key Findings
- OpenEMR 7.0.2 theme system is SASS-compiled CSS built on Bootstrap 4.6.2
- Theme categories: Light (style_light), Manila (style_manila), Colors (style_blue, etc. sharing color_base.scss)
- Old themeBuilder.php (dynamic CSS from DB globals) was removed in PR #3839
- All theming now happens at build time via SCSS compilation
- No native CSS custom properties for runtime theming

### Override Strategy
| Approach | Use When | Notes |
|----------|----------|-------|
| CSS custom properties (`:root --var`) | Design tokens (colors, spacing, fonts) | Future-proof, single-point-of-change |
| Direct selectors + `!important` | Bootstrap utility class overrides | Sparingly, document why |
| High-specificity selectors (no `!important`) | Non-utility structural overrides | Preferred where specificity allows |

### Key Selectors by UI Element

| UI Element | Primary Selectors | Core SCSS Source |
|------------|-------------------|-----------------|
| Sidebar panel | .oe-sidebar, .sidebar | oe-common/oe-sidebar.scss |
| Top navigation | .menuBar, .navbar, #sddm | core/ partials |
| Tab navigation | ul.tabNav, div.tabContainer | core.scss |
| Patient demographics form | #DEM .groupname, #DEM .label_custom | core.scss |
| History form | #HIS .groupname, #HIS .label_custom | core.scss |
| Section headers | .section-header | style_pdf.scss |
| Buttons | .btn-primary, input[type=submit] | Theme-specific |
| Cards/Panels | .card, .panel | core.scss |
| Logo bar | .logobar | core.scss |

### Future: Bootstrap 5 Migration
When OpenEMR migrates to Bootstrap 5 (in progress, incomplete):
- CSS custom properties will be natively available
- `!important` overrides can be replaced with CSS variable overrides
- BS5 utility classes use CSS custom properties, reducing specificity battles

### Sources
- OpenEMR interface/themes/ README (GitHub)
- OpenEMR Header.php source (GitHub)
- PR #2232: Custom Assets Feature
- PR #3839: Removal of Theme Builder

---

## 14. Patient Authentication Flow (TC-5)

### Decision
**SMART on FHIR v2.2.0** with Authorization Code + PKCE for patient-facing app. NextAuth.js wrapping OpenEMR OIDC as hybrid auth approach.

### SMART on FHIR Standalone Launch

| Aspect | Detail |
|--------|--------|
| Grant type | Authorization Code + PKCE (public client) |
| Discovery endpoint | GET /fhir/.well-known/smart-configuration |
| Authorization URL | /oauth2/default/authorize |
| Token URL | /oauth2/default/token |
| Auto-approval | Yes for `patient/*` scopes (ONC 21st Century Cures Act) |
| Refresh tokens | Yes (3-month lifetime) |
| Token response | Includes `patient` field with patient ID context |

### Scopes

| Scope | Access | Used By |
|-------|--------|---------|
| patient/*.rs | Read all FHIR resources for the authenticated patient | Next.js (direct FHIR reads) |
| openid | Identity token | NextAuth.js session |
| fhirUser | User identity claim | NextAuth.js session |
| api:oemr | Standard REST API (staff-level) | BFF only (client_credentials) |
| api:fhir | FHIR API (staff-level) | BFF only (client_credentials) |

### NextAuth.js Integration
- NextAuth.js OIDC provider configured with OpenEMR's OAuth2 endpoints
- Handles PKCE code_verifier generation and state management
- Manages session cookies and token refresh
- Exposes `patient` ID from token response to frontend

### Dual-Token Strategy

| Token Type | Scope | Purpose | Lifetime |
|------------|-------|---------|----------|
| Patient Bearer (Authorization Code + PKCE) | patient/*.rs openid fhirUser | FHIR read operations from Next.js | 1 hour, refresh 3 months |
| Service Bearer (client_credentials) | api:oemr api:fhir openid | Write operations via BFF | 1 hour, auto-refresh |

### Auth Flow Sequence
1. Patient opens Next.js app → redirected to OpenEMR /oauth2/default/authorize
2. Patient authenticates with portal credentials (username/password)
3. OpenEMR redirects back with authorization code
4. Next.js exchanges code + code_verifier for tokens at /oauth2/default/token
5. NextAuth.js creates session with access_token + patient ID
6. Frontend calls FHIR API directly with patient Bearer token
7. Frontend calls BFF endpoints for writes; BFF uses service token for Standard REST

### Alternatives Considered
- **OAuth2 Password Grant**: REJECTED — disabled by default, no refresh tokens, no MFA, no consent screen
- **Portal session cookie**: REJECTED — no API access, desktop-only, no OAuth2
- **Custom JWT auth**: REJECTED — non-standard, not interoperable with FHIR ecosystem

### Sources
- OpenEMR Authentication Documentation (GitHub)
- OpenEMR Authorization/SMART Documentation (GitHub)
- OpenEMR SMART on FHIR Documentation (GitHub)

---

## 15. Key Management (CHK018)

### Decision
Implement dual-layer key management with documented rotation, backup, and revocation procedures.

### Key Types

| Key | Algorithm | Scope | Rotation Cycle |
|-----|-----------|-------|----------------|
| OpenEMR CryptoGen key | AES-256 | Individual document encryption | 12 months |
| LUKS volume passphrase | AES-256-XTS | Full volume encryption (DB + documents) | 12 months |
| OAuth2 client secrets | SHA-256 | API authentication tokens | 6 months |
| Backup encryption key | AES-256 | Backup file encryption | 12 months |

### Rotation Procedures

**OpenEMR CryptoGen Key Rotation:**
1. Generate new key via OpenEMR Admin > Globals > Encryption
2. Run `scripts/rotate-encryption-key.sh` which:
   - Reads all encrypted documents
   - Decrypts with current key
   - Re-encrypts with new key
   - Verifies integrity of re-encrypted files
   - Logs rotation event in audit log
3. Backup old key to secure offline storage (password manager or HSM)
4. Verify document access after rotation

**LUKS Passphrase Rotation:**
1. Add new passphrase: `cryptsetup luksAddKey /dev/sdX`
2. Verify new passphrase works
3. Remove old passphrase: `cryptsetup luksRemoveKey /dev/sdX`
4. Document rotation in ops runbook

### Backup & Recovery

| Key | Backup Location | Access Control |
|-----|-----------------|----------------|
| CryptoGen key | Encrypted backup in S3-like storage | Admin + encrypted with separate key |
| LUKS passphrase | Password manager (Bitwarden/Vault) | Admin only |
| OAuth2 secrets | Docker secrets volume | Admin only |
| Backup key | Offline USB in safe | Admin only |

### Emergency Revocation
If any key is compromised:
1. Immediately rotate the compromised key
2. Re-encrypt all affected data
3. Audit all access logs since potential exposure date
4. Notify all users of forced password reset
5. Document incident in security log

---

## 16. Data Portability (CHK006, CHK003)

### Decision
Implement patient data export via OpenEMR Reports (built-in) plus a dedicated integration service endpoint for structured export.

### Export Capabilities

| Data Category | Format | Scope | Method |
|---------------|--------|-------|--------|
| Demographics | CSV, PDF | All patient demographics | OpenEMR Reports > Report > Patient List |
| Encounter history | CSV, PDF | All encounters with dates, providers, diagnoses | OpenEMR Reports > Clinical |
| Documents | ZIP (original files) | All uploaded documents with category metadata | Integration Service GET /internal/export/{pid} |
| Appointment history | CSV | All appointments with dates, status, providers | OpenEMR Reports > Scheduling |
| Audit trail | CSV | All audit events for the patient | Admin > Logs (filtered by patient) |

### Integration Service Export Endpoint

```
GET /internal/export/{pid}?format=full|summary
Authorization: Basic <integration-auth>

Response (format=full):
{
  "patient": { ... demographics ... },
  "encounters": [ ... encounter history ... ],
  "appointments": [ ... appointment history ... ],
  "documents": [
    {
      "category": "Identidade",
      "filename": "rg_frente.pdf",
      "mimetype": "application/pdf",
      "download_url": "/internal/export/{pid}/documents/{doc_id}",
      "uploaded_at": "2026-01-15T10:30:00Z"
    }
  ],
  "consents": { "sms": true, "email": true, "whatsapp": false },
  "export_date": "2026-05-04T14:00:00Z",
  "exported_by": "admin"
}
```

### Patient Self-Service
Patient Portal provides a "Meus Dados" section with:
- View demographics (read-only)
- Request data export (triggers admin review for clinical data)
- Download demographics in PDF format

---

## 17. Data Lifecycle & Destruction (CHK005, CHK020)

### Decision
Implement tiered retention with secure destruction procedures compliant with LGPD Art. 16 and CFM Resolution 2,314/2023 (medical record retention).

### Retention Policy

| Data Type | Retention Period | After Expiration |
|-----------|-----------------|-----------------|
| Medical records (encounters, documents) | 20 years | Anonymize (remove patient identifiers) |
| Appointment history | 5 years | Anonymize |
| Reminder logs (content_hash) | 90 days operational, 5 years audit | Delete operational, anonymize audit |
| Consent records | Duration of relationship + 5 years | Anonymize |
| Audit logs | 5 years (Constitution §V) | Archive with reduced detail |
| Backup files (daily) | 30 days | Secure delete (shred) |
| Backup files (monthly) | 12 months | Secure delete (shred) |
| Session tokens | 8 hours max | Auto-delete on expiry |

### Secure Destruction Procedures

**Volume Destruction (LUKS):**
```bash
# For decommissioned volumes
cryptsetup luksErase /dev/sdX    # Erase LUKS header
shred -vfz -n 3 /dev/sdX        # 3-pass overwrite
```

**Backup File Destruction:**
```bash
# For expired backups
shred -vfz -n 3 <backup_file>.sql.enc
# Verify deletion
ls -la <backup_file>.sql.enc  # Should not exist
```

**Database Record Anonymization:**
```sql
-- Anonymize patient data after retention period
UPDATE patient_data SET
  fname = 'ANONIMIZADO',
  lname = 'ANONIMIZADO',
  ss = NULL,
  email = NULL,
  phone_cell = NULL,
  street = NULL,
  postal_code = NULL
WHERE pid = <expired_patient_id>;
-- Log anonymization event
INSERT INTO audit_log (...) VALUES (...);
```

---

## 18. User Lifecycle Management (CHK016)

### Decision
Implement user lifecycle management following OpenEMR's native user administration with documented procedures.

### User Lifecycle States

| State | Description | Can Login | Data Preserved |
|-------|-------------|-----------|----------------|
| Active | Normal operational user | Yes | Yes |
| Inactive | Deactivated user (left clinic) | No | Yes (audit trail preserved) |
| Locked | Temporarily locked (brute force) | No | Yes |
| Password Reset | Requires password change at next login | Yes (forced change) | Yes |

### Procedures

**User Creation:**
1. Admin creates user in OpenEMR > Users > Add User
2. Assign ACL group (recepcao, medico, admin)
3. Configure 2FA (TOTP) for medico and admin
4. Set password expiration (90 days) and history (5)
5. Audit event logged: user creation, assigned group

**User Deactivation (NOT deletion):**
1. Admin sets user `active = 0` in OpenEMR > Users
2. Audit trail preserved: all past actions remain linked to user
3. No data is deleted — LGPD requires audit trail retention
4. Audit event logged: user deactivation, deactivated by

**Profile Change:**
1. Admin changes ACL group assignment
2. OpenEMR requires: delete old group, create new group (ACL groups cannot be edited)
3. Audit event logged: group change, old group, new group, changed by

**Password Policy:**
- Minimum 8 characters
- Must include: uppercase, lowercase, number, special character
- Expiration: 90 days
- History: 5 previous passwords (cannot reuse)
- 2FA: TOTP required for medico and admin profiles
- Fallback: Backup recovery codes generated at 2FA setup (10 codes, single-use each)

---

## 19. Observability (CHK041)

### Decision
Implement structured logging with JSON format for the integration service, enhanced health checks, and error rate alerting.

### Structured Log Format

```json
{
  "timestamp": "2026-05-04T14:30:00.000Z",
  "level": "INFO",
  "service": "integration-service",
  "action": "reminder.send",
  "patient_id_hash": "sha256:abc123...",
  "channel": "whatsapp",
  "status": "sent",
  "duration_ms": 245,
  "error_detail": null,
  "correlation_id": "uuid-1234"
}
```

### Health Check Endpoint Enhancement

```
GET /health
{
  "status": "ok",
  "uptime_seconds": 86400,
  "components": {
    "database": "connected",
    "openemr_api": "reachable",
    "whatsapp_api": "reachable",
    "smtp": "reachable"
  },
  "last_error_time": null,
  "version": "1.0.0"
}
```

### Alerting Rules

| Condition | Threshold | Action |
|-----------|-----------|--------|
| Error rate > 5% in 5 min | 5% | Email to admin |
| Error rate > 20% in 5 min | 20% | Email + SMS to admin |
| Health check failure | 1 failure | Email to admin |
| Consecutive health failures | 3 failures | Email + SMS to admin |
| WhatsApp API down | >10 min | Email to admin |

### Log Retention
- Application logs: 90 days in Docker volumes, then rotate
- Audit logs: 5 years (per Constitution §V)
- Error summaries: 12 months

---

## 20. WhatsApp API Rate Limits (CHK033)

### Decision
Document Meta WhatsApp Business API rate limits and implement throttling in the integration service.

### Meta Rate Limits (by Tier)

| Tier | Conversations/24h | Pricing Tier |
|------|-------------------|--------------|
| Free | 1,000 | Starter |
| Tier 1 | 10,000 | Growth |
| Tier 2 | 100,000 | Pro |
| Tier 3 | Unlimited | Enterprise |

### Integration Service Throttling

```python
# In whatsapp.py
RATE_LIMITS = {
    "messages_per_minute": 80,      # Conservative limit
    "messages_per_hour": 1000,       # Well within tier 1
    "cooldown_per_patient": 300,     # 5 min between messages to same patient
    "daily_budget_warning": 0.8,     # Alert at 80% of daily limit
}
```

### Handling Rate Limit Responses
- HTTP 429 from WhatsApp API → Queue message for retry in 5 minutes
- Exponential backoff: 5min → 10min → 20min → give up after 3 attempts
- Log rate limit event with full headers for monitoring

---

## 21. External API DPA Requirements (CHK012, CHK081, CHK082)

### Decision
Document Data Processing Agreement requirements for all external API providers.

### WhatsApp Business API (Meta)

| Requirement | Specification |
|-------------|---------------|
| DPA Required | Yes — Meta Business Terms cover data processing |
| Data Jurisdiction | Data stored in region selected (choose Brazil/South America) |
| Data Retention | Messages stored for 30 days max by Meta |
| LGPD Compliance | Meta provides LGPD-compliant processing terms |
| Subprocessors | Documented in Meta Privacy Policy |
| Data Minimization | Only send: patient name, date, time, appointment type |
| Breach Notification | Meta notifies within 72 hours per Business Terms |

### Twilio SMS

| Requirement | Specification |
|-------------|---------------|
| DPA Required | Yes — Twilio Data Processing Agreement available |
| Data Jurisdiction | Choose Brazil region for phone numbers |
| Data Retention | Message logs retained 13 months by default |
| SLA | 99.95% uptime guarantee (Enterprise tier) |
| Fallback | If SMS fails: try email as secondary channel |
| LGPD Compliance | Twilio GDPR-compliant, LGPD compatible |

### SMTP Provider

| Requirement | Specification |
|-------------|---------------|
| DPA Required | Yes — provider must offer DPA |
| Data Jurisdiction | Choose Brazil or EU region |
| Data Retention | Email logs retained per provider policy |
| TLS Required | Yes — STARTTLS or TLS 1.2+ |

---

## 22. Session, Brute Force, and SLA (CHK075, CHK076, CHK071, CHK073)

### Session Management

| Parameter | Value | Configuration |
|-----------|-------|---------------|
| Inactivity timeout | 15 minutes | OpenEMR globals > Security > Timeout |
| Max session duration | 8 hours | OpenEMR globals > Security > Session Duration |
| Session storage | Database | Default OpenEMR |
| Cookie settings | Secure, HttpOnly, SameSite=Strict | Traefik middleware |

### Brute Force Protection

| Layer | Threshold | Action |
|-------|-----------|--------|
| Application (OpenEMR) | 5 failed login attempts | Lock account for 15 minutes |
| VPS (fail2ban) | 10 failed attempts in 10 min | Ban IP for 30 minutes |
| Traefik (rate limit) | 100 avg, 50 burst (general) | Return 429 |
| Login-specific rate limit | 20 requests/min per IP | Traefik middleware |

### SLA & Availability

| Metric | Target | Notes |
|--------|--------|-------|
| Uptime | 99.5% (43.8h downtime/year) | Single clinic scale |
| Maintenance window | Sunday 02:00-06:00 BRT | Planned downtime |
| RTO (Recovery Time Objective) | < 4 hours | From detection to full service |
| RPO (Recovery Point Objective) | < 24 hours | Based on daily backup |
| Backup restore test | Quarterly | Verify backup integrity and restore procedure |

### Cloudflare Tunnel Fallback

| Scenario | Response |
|----------|----------|
| Cloudflare Tunnel down | DNS failover to direct VPS IP |
| Fallback TLS | Traefik auto-generates Let's Encrypt cert for direct access |
| Fallback activation | Manual DNS change (TTL 300s) + Traefik cert switch |
| Monitoring | Health check every 60s; admin alerted on failure |
| Recovery | Automatic reconnection when Cloudflare Tunnel resumes |

### Phone Number Validation (CHK034)

Brazilian phone number validation before sending reminders:

```python
# In whatsapp.py and sms adapter
def validate_br_phone(phone: str) -> bool:
    """Validate Brazilian mobile phone number format."""
    # Remove non-digits
    digits = re.sub(r'\D', '', phone)
    # Accept formats: 11999999999, 99299999999 (with country code)
    if digits.startswith('55'):
        digits = digits[2:]  # Remove country code
    # Mobile: XX9XXXXXXXX (9th digit is always 9)
    return bool(re.match(r'^\d{2}9\d{8}$', digits))

def normalize_br_phone(phone: str) -> str:
    """Normalize to +55XX9XXXXXXXX format."""
    digits = re.sub(r'\D', '', phone)
    if digits.startswith('55'):
        digits = digits[2:]
    return f"+55{digits}"
```

---

## 23. RBAC Clarification: "addonly" and Unauthorized Access (CHK047, CHK086, CHK014)

### "addonly" Definition
In OpenEMR's ACL system, `addonly` means the user can:
- ✅ Create new records (e.g., create a new patient, upload a new document)
- ✅ View existing records in categories they have access to
- ❌ Edit existing records (no modification of existing data)
- ❌ Delete records

### Category-Level Access for Recepção

| Category | Recepção Access | Details |
|----------|----------------|---------|
| Identidade (documents) | addonly (create + view) | Can upload and view ID documents |
| Termos/Consentimento (documents) | addonly (create + view) | Can upload and view consent forms |
| Prontuario Clinico (documents) | NONE — access denied | Cannot view, create, or edit |
| Exames/Laudo (documents) | NONE — access denied | Cannot view, create, or edit |
| Encaminhamento (documents) | NONE — access denied | Cannot view, create, or edit |
| Terapias (documents) | NONE — access denied | Cannot view, create, or edit |
| Demographics (patients) | addonly (create + view) | Can create new patients, view existing |
| Appointments | write (full CRUD) | Can create, edit, cancel appointments |

### Unauthorized Access Behavior
When a user attempts to access a restricted resource:
1. OpenEMR displays "Access Denied" message
2. The attempt is logged in the audit log with: user, IP, timestamp, resource attempted
3. Admin receives aggregated weekly report of unauthorized access attempts
4. If >10 attempts from same user in 24h → automatic admin alert

---

## 24. Encryption Scope Clarification (CHK088)

### Dual-Layer Encryption Architecture

| Layer | Mechanism | Scope | What It Protects |
|-------|-----------|-------|-----------------|
| Volume level | LUKS (AES-256-XTS) | Entire DB volume + document volume | MariaDB data files, document files, config files — protects against physical disk theft |
| Application level | OpenEMR CryptoGen (AES-256-CBC) | Individual document files | Each uploaded document is encrypted individually with a key stored in the DB — protects against unauthorized file-level access even within the server |

**Important clarification**: Both layers are required for LGPD compliance. LUKS protects the entire volume at rest (including DB data files), while CryptoGen protects individual documents even from other users on the same system. Neither layer alone is sufficient — they complement each other.

| What | Protected by LUKS? | Protected by CryptoGen? |
|------|---------------------|------------------------|
| MariaDB data files (records, audit logs) | ✅ Yes | ❌ No (DB manages its own encryption) |
| Uploaded documents (PDFs, images) | ✅ Yes | ✅ Yes (double-encrypted) |
| OpenEMR configuration | ✅ Yes | ❌ No |
| Backup files | ✅ N/A (separate volume) | ✅ Yes (AES-256 via backup.sh) |