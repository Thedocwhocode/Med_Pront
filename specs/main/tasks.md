# Tasks: Med_Pront — Prontuario Eletronico LGPD

**Input**: Design documents from `/specs/main/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, contracts/api-contracts.md

**Tests**: Not explicitly requested in spec. Test tasks omitted per template guidelines.

**Organization**: Tasks grouped by user story for independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization, Docker infrastructure, VPS hardening

- [X] T001 Create project directory structure per plan.md (docker/, scripts/, docs/, Makefile, .gitignore) in repo root
- [X] T002 Create docker/.env.example with all required environment variables (DB passwords, SMTP, Twilio, WhatsApp API, OpenEMR admin) in docker/.env.example
- [X] T003 [P] Create Docker Compose base file with all 5 services (traefik, openemr, db, integration, cloudflare-tunnel) and 3 networks (frontend, backend, egress) in docker/docker-compose.yml
- [X] T004 [P] Create Docker Compose dev override for local development (port mappings, volume mounts, debug flags) in docker/docker-compose.dev.yml
- [X] T005 [P] Create MariaDB init script with charset utf8mb4 and collation utf8mb4_unicode_ci in docker/db/init.sql
- [X] T006 [P] Create Makefile with health-check, audit-verify, backup-test, and dev targets in Makefile
- [X] T007 [P] Create .gitignore excluding .env, secrets, volumes, backup_data in .gitignore

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**CRITICAL**: No user story work can begin until this phase is complete

- [X] T008 Create VPS hardening script (SSH key-only, fail2ban, UFW with Cloudflare IPs only, unattended-upgrades) in scripts/setup-vps.sh
- [X] T009 [P] Create Traefik static config with HTTPS termination, rate limiting, and Cloudflare Origin Cert in docker/traefik/traefik.yml
- [X] T010 [P] Create Traefik dynamic config with router rules for openemr and integration-service in docker/traefik/dynamic.yml
- [X] T011 [P] Create Cloudflare Tunnel setup script in scripts/setup-cloudflare-tunnel.sh
- [X] T012 Create OpenEMR initial setup script (wait for healthy, run setup wizard via API, set site ID) in scripts/setup-openemr.sh
- [X] T013 [P] Create integration service scaffold with FastAPI app, config module, and health endpoint in docker/integration-service/src/main.py
- [X] T014 [P] Create integration service config module loading env vars (OpenEMR API, Twilio, WhatsApp, SMTP) in docker/integration-service/src/config.py
- [X] T015 [P] Create integration service Dockerfile (Python 3.11-slim, pip install, uvicorn) in docker/integration-service/Dockerfile
- [X] T016 [P] Create integration service requirements.txt (fastapi, uvicorn, httpx, pydantic, python-dotenv) in docker/integration-service/requirements.txt
- [X] T017 Configure OpenEMR RBAC: create 3 ACL groups (recepcao, medico, admin) with permissions per research.md via scripts/setup-openemr.sh
- [X] T018 Configure OpenEMR audit logging: enable all categories except SELECT queries, enable encryption, set SHA512 hash, 90-day password expiry via scripts/setup-openemr.sh
- [X] T019 Configure OpenEMR document storage: set filesystem method, enable AES-256 encryption, enable thumbnail generation via scripts/setup-openemr.sh
- [X] T020 Configure OpenEMR security globals: password history 5, 2FA for medico/admin, session timeout via scripts/setup-openemr.sh
- [X] T021 [P] Create backup script with encrypted daily DB dumps (AES-256), document volume sync, and S3-like upload in docker/backup/backup.sh
- [X] T022 [P] Create restore script with decryption and volume recovery in docker/backup/restore.sh
- [X] T023 [P] Install ICD-10 codeset via OpenEMR External Data Loads in scripts/setup-openemr.sh

**Checkpoint**: Foundation ready — Docker Compose up, HTTPS via Cloudflare, RBAC configured, audit logging active, encryption on, ICD-10 loaded

---

## Phase 3: User Story 1 - Cadastro de Pacientes (Priority: P1) MVP

**Goal**: Recepcao cadastra pacientes com todos os dados de identificacao, contato, convenio, terapias, encaminhamento e consentimento LGPD usando campos nativos e customizados do OpenEMR Demographics.

**Independent Test**: Cadastrar um paciente com todos os campos preenchidos e verificar que os dados persistem corretamente (nativos + customizados). Testar CPF duplicado e menor sem responsavel.

### Implementation for User Story 1

- [X] T024 [US1] Create OpenEMR Lists for custom dropdowns (escolaridade: Fundamental Incompleto, Fundamental Completo, Medio, Superior, Pos-graduacao; convenio_nome: SUS, Unimed, Amil, Outro, Particular; terapias_tipo: Fisioterapia, Fonoaudiologia, Psicologia, Terapia Ocupacional, Nutricao, Outro) via Admin > Forms > Lists in scripts/setup-openemr.sh
- [X] T025 [US1] Create LBF custom fields in Demographics layout: escolaridade (dropdown), nome_pai (text 30), terapias_tipo (multi-select), terapias_contato (text 100), encaminhamento_contato (text 100), convenio_nome (dropdown), convenio_numero (text 30), allow_whatsapp (checkbox) via scripts/setup-openemr.sh
- [X] T026 [US1] Configure native field labels and UOR in Demographics layout: ss label to "CPF" with option flags D (duplicate check) and 1 (write-once), set required/optional per data-model.md via scripts/setup-openemr.sh
- [X] T027 [US1] Configure conditional validation for guardiansname: required when DOB indicates patient < 18 years via scripts/setup-openemr.sh
- [X] T028 [US1] Configure CEP validation pattern `\d{5}-?\d{3}` for postal_code field via scripts/setup-openemr.sh
- [ ] T029 [US1] Verify RBAC: recepcao has Demographics addonly (create + view, no edit), medico has write, admin has full — test with dedicated test users per profile

**Checkpoint**: Cadastro de Pacientes funcional — todos os campos nativos e customizados persistem, CPF duplicado rejeitado, responsavel obrigatorio para menores, consentimento LGPD registrado

---

## Phase 4: User Story 2 - Agendamento de Consultas (Priority: P2)

**Goal**: Recepcao agenda consultas presenciais e por telemedicina usando o modulo Calendar do OpenEMR, com controle de status e vinculo paciente-profissional.

**Independent Test**: Criar um agendamento presencial e um por telemedicina, verificar que ambos aparecem na agenda do profissional e que o status e controlavel.

### Implementation for User Story 2

- [X] T030 [US2] Create custom Calendar Categories: Consulta Presencial (Patient, 30 min), Consulta Telemedicina (Patient, 30 min), Retorno Presencial (Patient, 20 min), Retorno Telemedicina (Patient, 20 min), Procedimento (Patient, 45 min) via scripts/setup-openemr.sh
- [X] T031 [US2] Configure Calendar globals: interval 15 min, auto-create encounter per appointment, allow early check-in via scripts/setup-openemr.sh
- [ ] T032 [US2] Verify appointment status transitions work: Confirmed (*) -> Arrived (+) -> Checked In (@) -> Checked Out (>); Canceled (-) and No Show (%) from any status except Checked Out
- [ ] T033 [US2] Verify RBAC: recepcao has Appointments write, medico has write, admin has full — test scheduling and status changes per profile
- [ ] T034 [US2] Verify audit logging captures appointment creation, status changes, and cancellations in audit log

**Checkpoint**: Agendamento funcional — consultas presenciais e telemedicina agendaveis, status controlavel, auditoria registrada

---

## Phase 5: User Story 4 - Documentos e Exames Digitalizados (Priority: P2)

**Goal**: Recepcao ou medico faz upload de exames/relatorios digitalizados para o registro do paciente, armazenados em volume criptografado.

**Independent Test**: Fazer upload de um PDF de exame para um paciente e verificar que o documento aparece no prontuario e esta armazenado em volume criptografado.

### Implementation for User Story 4

- [X] T035 [US4] Create custom Document Categories with ACL restrictions: Identidade (recepcao, medico, admin), Prontuario Clinico (medico, admin), Exames/Laudo (medico, admin), Termos/Consentimento (recepcao, medico, admin), Encaminhamento (medico, admin), Terapias (medico, admin) via scripts/setup-openemr.sh
- [X] T036 [US4] Configure document upload size limit (50MB) in Traefik/Traefik dynamic config (request body max) in docker/traefik/dynamic.yml
- [ ] T037 [US4] Verify AES-256 encryption at rest for uploaded documents by checking encrypted files on doc_data volume
- [ ] T038 [US4] Verify RBAC: recepcao can upload to Identidade/Termos categories (addonly), medico can upload to all categories (write), recepcao cannot access Prontuario Clinico/Exames
- [ ] T039 [US4] Verify audit logging captures document upload, access, and category changes

**Checkpoint**: Documentos funcional — upload para categorias com ACL, criptografia em repouso, auditoria de acesso

---

## Phase 6: User Story 3 - Telemedicina (Priority: P3)

**Goal**: Agendamentos do tipo telemedicina geram link de teleconsulta vinculado ao agendamento via modulo Comlink Telehealth, e o prontuario registra a modalidade.

**Independent Test**: Agendar consulta de telemedicina, gerar link, simular acesso, e verificar que o encounter registra modalidade telemedicina.

### Implementation for User Story 3

- [X] T040 [US3] Install and enable Comlink Telehealth module via Modules > Manage Modules in scripts/setup-openemr.sh
- [X] T041 [US3] Configure Comlink Telehealth: enable auto-register providers, enable pre-authenticated patient login link, set session window +/-2h in scripts/setup-openemr.sh
- [ ] T042 [US3] Verify telehealth link generation for Consulta Telemedicina and Retorno Telemedicina calendar categories
- [ ] T043 [US3] Verify patient prerequisites: email in demographics, Allow Email + Allow Patient Portal enabled, portal credentials exist
- [ ] T044 [US3] Verify encounter records modalidade "telemedicina" inferred from calendar category of originating appointment

**Checkpoint**: Telemedicina funcional — links gerados para agendamentos de telemedicina, encounters registram modalidade

---

## Phase 7: User Story 5 - Lembretes Automaticos de Consulta (Priority: P3)

**Goal**: Sistema envia lembretes 24h antes da consulta por e-mail e/ou WhatsApp com conteudo minimalista (sem dados clinicos), respeitando consentimento explicito.

**Independent Test**: Cadastrar paciente com consentimento, agendar consulta para 24h no futuro, verificar que o lembrete e enviado sem dados clinicos.

### Implementation for User Story 5

- [X] T045 [US5] Create OpenEMR API client adapter for integration service (auth, appointments FHIR, patient demographics, consent check) in docker/integration-service/src/adapters/openemr.py
- [X] T046 [US5] Create consent verification service that checks hipaa_allowsms, hipaa_allowemail, and allow_whatsapp per patient in docker/integration-service/src/services/consent.py
- [X] T047 [US5] [P] Create WhatsApp Business API adapter with template message sending (pt_BR, no clinical data) in docker/integration-service/src/adapters/whatsapp.py
- [X] T048 [US5] [P] Create SMTP email adapter for appointment reminders in docker/integration-service/src/adapters/email.py
- [X] T049 [US5] Create notification service: scan appointments 24h ahead, verify consent per channel, send reminders, log results with content hash in docker/integration-service/src/services/notification.py
- [X] T050 [US5] Create Reminder model (appointment_id, patient_pid, channel, consent_verified, sent_at, status, content_hash, error_message) in docker/integration-service/src/models/reminder.py
- [X] T051 [US5] Create cron endpoint GET /internal/reminders/check that triggers the notification pipeline in docker/integration-service/src/main.py
- [X] T052 [US5] Create send endpoint POST /internal/reminders/send for manual single-reminder trigger in docker/integration-service/src/main.py
- [X] T053 [US5] Create consent endpoint GET /internal/consent/{patient_pid} in docker/integration-service/src/main.py
- [X] T054 [US5] Configure OpenEMR email notifications: SMTP host/port/security, notification hours 24, cron for cron_email_notification.php in scripts/setup-openemr.sh
- [X] T055 [US5] Configure oe-module-faxsms with Twilio credentials and cron for cron_sms_notification.php in scripts/setup-openemr.sh
- [X] T056 [US5] Set cron for integration service reminders (every 5 min) pointing to localhost:8000/internal/reminders/check in scripts/setup-openemr.sh
- [X] T057 [US5] Implement retry logic: failed reminders retry after 1h, permanent failure after 3 attempts, notify admin via email in docker/integration-service/src/services/notification.py
- [X] T058 [US5] Implement consent revocation: immediate stop of pending reminders, log revocation event in docker/integration-service/src/services/consent.py
- [ ] T059 [US5] Verify LGPD compliance: no clinical data (diagnosis, CID, medications) in reminder content — validate template parameters

**Checkpoint**: Lembretes funcionais — envio 24h antes respeitando consentimento, retry em falhas, sem dados clinicos, revogacao imediata

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, validation, and hardening across all user stories

- [X] T060 [P] Create LGPD compliance checklist in docs/lgpd-checklist.md
- [X] T061 [P] Create hardening guide in docs/hardening-guide.md
- [X] T062 [P] Create backup/restore procedures in docs/backup-restore.md
- [X] T063 Create project README with overview, architecture diagram, and quickstart link in README.md
- [ ] T064 Run full verification checklist from quickstart.md: HTTPS, RBAC, 2FA, audit logs, encryption, backups, Cloudflare Tunnel, consent, telehealth
- [X] T065 [P] Create integration service unit tests for consent service, notification service, and adapters in docker/integration-service/tests/
- [ ] T066 Verify edge cases: CPF duplicado rejeitado, menor sem responsavel bloqueado, horario ocupado alerta, upload >50MB rejeitado, falha WhatsApp com retry, revogacao consentimento

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion — BLOCKS all user stories
- **User Story 1 (Phase 3)**: Depends on Foundational — MVP
- **User Story 2 (Phase 4)**: Depends on Foundational — independent of US1 but natural sequence
- **User Story 4 (Phase 5)**: Depends on Foundational — independent of US1 and US2
- **User Story 3 (Phase 6)**: Depends on Foundational + US2 (telemedicina needs agendamento categories)
- **User Story 5 (Phase 7)**: Depends on Foundational + US1 (consent) + US2 (appointments)
- **Polish (Phase 8)**: Depends on all user stories complete

### User Story Dependencies

```text
US1 (P1) ─────────────────────────────────────────────┐
    │                                                   │
US2 (P2) ───────────────────┬──────────────────────────│
    │                       │                          │
US4 (P2) ───────────────────│──────────────────────────│
    │                       │                          │
    └─── US3 (P3) depends on US2                        │
    │                                                   │
    └─── US5 (P3) depends on US1 + US2 ─────────────────┘
                                                        │
                                          Polish (Phase 8)
```

### Within Each User Story

- Infrastructure config before functional verification
- RBAC verification after config
- Audit logging verification last (validates config)

### Parallel Opportunities

- T003, T004, T005, T006, T007 (Phase 1) — all parallel
- T009, T010, T011, T013, T014, T015, T016, T021, T022, T023 (Phase 2) — most parallel
- US2 and US4 (Phase 4 and 5) — fully parallel after Foundational
- T047, T048 (Phase 7) — WhatsApp and email adapters parallel

---

## Parallel Example: Phase 2 (Foundational)

```bash
# Launch all parallel foundational tasks together:
Task T009: "Traefik static config in docker/traefik/traefik.yml"
Task T010: "Traefik dynamic config in docker/traefik/dynamic.yml"
Task T011: "Cloudflare Tunnel setup in scripts/setup-cloudflare-tunnel.sh"
Task T013: "Integration service scaffold in docker/integration-service/src/main.py"
Task T014: "Integration service config in docker/integration-service/src/config.py"
Task T015: "Integration service Dockerfile in docker/integration-service/Dockerfile"
Task T016: "Integration service requirements.txt"
Task T021: "Backup script in docker/backup/backup.sh"
Task T022: "Restore script in docker/backup/restore.sh"
Task T023: "ICD-10 codeset install via setup-openemr.sh"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL — blocks all stories)
3. Complete Phase 3: User Story 1 — Cadastro de Pacientes
4. **STOP and VALIDATE**: Test US1 independently (all fields persist, CPF unique, consent works)
5. Deploy/demo MVP

### Incremental Delivery

1. Setup + Foundational → Infrastructure ready
2. Add US1 (P1) → Test → Deploy (MVP — prontuario com cadastro funcional)
3. Add US2 (P2) → Test → Deploy (agendamento presencial + telemedicina)
4. Add US4 (P2) → Test → Deploy (documentos digitalizados com criptografia)
5. Add US3 (P3) → Test → Deploy (telemedicina com links de video)
6. Add US5 (P3) → Test → Deploy (lembretes WhatsApp/email LGPD-compliant)
7. Polish → Test → Final deploy

### Parallel Team Strategy

With multiple developers after Foundational:

- Developer A: US1 (P1) — Cadastro
- Developer B: US2 (P2) — Agendamento (parallel with A)
- Then: US4 (P2) and US3 (P3) can proceed in parallel
- US5 (P3) after US1 + US2 complete

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story is independently completable and testable
- OpenEMR configuration tasks use setup-openemr.sh as the delivery mechanism (API calls or SQL inserts)
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- Avoid: vague tasks, same file conflicts, cross-story dependencies that break independence