# Data Model: Med_Pront — OpenEMR 7.x

**Date**: 2026-05-04 | **Status**: Draft | **Branch**: main

## Overview

O Med_Pront usa o schema nativo do OpenEMR 7.x com extensoes via Layout Based
Forms (LBF). Este documento descreve como os campos nativos e customizados se
mapeiam para os requisitos da clinica, sem modificar o schema do OpenEMR.

---

## Entity: Paciente (patient_data + LBF)

### Campos Nativos (patient_data)

| Campo OpenEMR | Requisito | UOR | Notas |
|---------------|-----------|-----|-------|
| `title` | Titulo (Dr., etc.) | Optional | — |
| `fname` | Nome | Required | — |
| `mname` | Nome do meio | Optional | — |
| `lname` | Sobrenome | Required | — |
| `DOB` | Data de nascimento | Required | Format: YYYY-MM-DD |
| `sex` | Sexo | Required | — |
| `ss` | CPF | Required | Repurpose label; option flags: `D` (duplicate check), `1` (write-once) |
| `street` | Rua | Required | — |
| `city` | Cidade | Required | — |
| `state` | Estado | Required | — |
| `postal_code` | CEP | Required | — |
| `country_code` | Pais | Required | Default: BR |
| `phone_home` | Telefone residencial | Optional | — |
| `phone_cell` | Celular / WhatsApp | Required | Principal canal de lembrete |
| `phone_biz` | Telefone comercial | Optional | — |
| `email` | E-mail | Required | Canal de lembrete + telehealth |
| `mothersname` | Nome da mae | Required | — |
| `guardiansname` | Nome do responsavel | Conditional | Obrigatorio para menores |
| `guardianrelationship` | Parentesco do responsavel | Conditional | — |
| `guardianphone` | Telefone do responsavel | Conditional | — |
| `referral_source` | Fonte de encaminhamento | Optional | — |
| `referrer` | Nome de quem encaminhou | Optional | Mapear para encaminhamento |
| `hipaa_allowsms` | Consentimento SMS/LGPD | Required | Checkbox — revogacao imediata impediu envios futuros |
| `hipaa_allowemail` | Consentimento e-mail | Required | Checkbox — canal secundario se WhatsApp falhar |
| `allow_patient_portal` | Acesso ao portal | Required | Necessario para telehealth |

### Campos Customizados (via LBF / layout_options)

| Field ID | Label | Data Type | UOR | Options |
|----------|-------|-----------|-----|---------|
| `escolaridade` | Escolaridade | Dropdown list | Required | List: Fundamental Incompleto, Fundamental Completo, Medio, Superior, Pos-graduacao |
| `nome_pai` | Nome do pai | Text (30) | Optional | — |
| `terapias_tipo` | Tipo de terapia/reabilitacao | Multi-select list | Optional | List: Fisioterapia, Fonoaudiologia, Psicologia, Terapia Ocupacional, Nutricao, Outro |
| `terapias_contato` | Contato da equipe terapeutica | Text (100) | Optional | Texto livre com nome + telefone |
| `encaminhamento_contato` | Contato de quem encaminhou | Text (100) | Optional | Nome + telefone |
| `convenio_nome` | Nome do convenio | Dropdown list | Optional | List: SUS, Unimed, Amil, Outro, Particular |
| `convenio_numero` | Numero da carteira do convenio | Text (30) | Optional | — |
| `allow_whatsapp` | Consentimento WhatsApp | Checkbox | Required | LGPD — opt-in explicito; revogacao imediata interrompe envios |

### Insurance (native — separate section)

| Campo OpenEMR | Requisito | Notas |
|---------------|-----------|-------|
| `insurance_companies` | Cadastro de convenios | Tabela separada |
| `insurance_data` | Dados do convenio por paciente | Vinculado ao patient_data |

---

## Entity: Agendamento (openemr_postcalendar_events)

### Campos Nativos (openemr_postcalendar_events)

| Campo | Requisito | Notas |
|-------|-----------|-------|
| `pc_pid` | Paciente (FK) | — |
| `pc_aid` | Profissional (FK) | — |
| `pc_eventDate` | Data | — |
| `pc_startTime` | Hora inicio | — |
| `pc_endTime` | Hora fim | — |
| `pc_catid` | Categoria (FK) | Mapeia tipo: presencial/telemedicina |
| `pc_title` | Titulo | — |
| `pc_apptstatus` | Status | `*` confirmed, `-` canceled, `%` no-show, `@` checked-in, `>` checked-out |
| `pc_comments` | Conflito de horario | WARNING (nao bloqueio) ao detectar sobreposicao |
| `pc_notes` | Observacoes | — |

### Appointment Categories (calendar categories)

| ID | Nome | Tipo | Duracao padrao |
|----|------|------|---------------|
| custom | Consulta Presencial | Patient | 30 min |
| custom | Consulta Telemedicina | Patient | 30 min |
| custom | Retorno Presencial | Patient | 20 min |
| custom | Retorno Telemedicina | Patient | 20 min |
| custom | Procedimento | Patient | 45 min |

---

## Entity: Encounter (forms + form_encounter)

### Campos Nativos

| Campo | Requisito | Notas |
|-------|-----------|-------|
| `encounter` | ID do encounter | Auto-increment |
| `pid` | Paciente (FK) | — |
| `date` | Data da consulta | — |
| `provider_id` | Profissional (FK) | — |
| `reason` | Motivo | — |
| `facility_id` | Local | Presencial vs telemedicina |

### Telehealth Metadata

O modulo Comlink registra dados de telehealth em tabela propria
(`comlink_telehealth_sessions`), vinculada ao agendamento. O encounter
resultante nao tem campo nativo de "modalidade" — isso e inferido pela
categoria do agendamento que gerou o encounter.

---

## Entity: Documento (documents)

### Campos Nativos

| Campo | Requisito | Notas |
|-------|-----------|-------|
| `id` | ID do documento | Auto-increment |
| `foreign_id` | Paciente (FK) | — |
| `type` | Categoria do documento | FK para categories |
| `date` | Data do documento | — |
| `url` | Path no filesystem | Criptografado em repouso |
| `mimetype` | Tipo MIME | — |
| `docdate` | Data do conteudo | — |

### Document Categories (custom)

| Nome | ACL |
|------|-----|
| Identidade | recepcao, medico, admin |
| Prontuario Clinico | medico, admin |
| Exames/Laudo | medico, admin |
| Termos/Consentimento | recepcao, medico, admin |
| Encaminhamento | medico, admin |
| Terapias | medico, admin |

---

## Entity: Lembrete (Integration Service)

### Modelo do Integration Service (nao e tabela OpenEMR)

| Campo | Tipo | Notas |
|-------|------|-------|
| appointment_id | String | FK para openemr_postcalendar_events |
| patient_pid | String | FK para patient_data |
| channel | Enum | sms, email, whatsapp |
| consent_verified | Boolean | Verificado antes do envio |
| reminder_window_start | DateTime | 25h antes da consulta (inicio da janela) |
| reminder_window_end | DateTime | 23h antes da consulta (fim da janela) |
| check_interval_minutes | Integer | 5 (verificacao a cada 5 minutos) |
| status | Enum | pending, sent, failed, retrying, failed_permanent |
| content_hash | String | Hash do conteudo enviado (para auditoria) |
| error_message | String | NULL se sucesso |
| retry_count | Integer | Contador de retentativas (max 3 antes de failed_permanent) |
| fallback_channel | Enum | Canal alternativo tentado (sms, email) — NULL se nenhum |
| admin_notified | Boolean | True apos 3 falhas permanentes notificarem admin |

---

## Entity: Usuario (users)

### Campos Nativos

| Campo | Requisito | Notas |
|-------|-----------|-------|
| `username` | Login | Unique |
| `password` | Senha (hash) | SHA512 + salt |
| `fname`, `lname` | Nome | — |
| `active` | Ativo | 1 = ativo, 0 = inativo (desativado — sem exclusao) |
| `role_id` | Perfil RBAC | FK para acl groups |

### User Lifecycle States

| Estado | active | Pode login | Descricao |
|--------|--------|------------|-----------|
| Active | 1 | Sim | Usuario operacional normal |
| Inactive | 0 | Nao | Desativado pelo admin — mantem historico de acoes mas nao pode logar |
| Locked | 0 | Nao | Bloqueado por 5+ tentativas falhas de login (15 min auto-desbloqueio) |
| Password Reset | 1 | Nao (requer troca) | Senha expirada — usuario deve trocar no proximo login |

### RBAC Profiles

| Perfil | ACL Group | Acesso | Notas |
|--------|-----------|--------|-------|
| Recepcao | `recepcao` | Demographics addonly*, Appointments write, Documents addonly* | *addonly = criar novos + visualizar, NAO editar/excluir existentes. Sem acesso a Prontuario Clinico, Exames/Laudo, Encaminhamento, Terapias |
| Medico | `medico` | Demographics write, Medical Records write, Encounters write, All documents | Acesso total a registros clinicos |
| Admin | `admin` | Full access | Gerenciamento de usuarios, ACLs, auditoria |

---

## Validation Rules

| Rule | Field | Validation |
|------|-------|------------|
| CPF unico | `ss` | Option flag `D` — duplicate check nativo do OpenEMR |
| CPF imutavel | `ss` | Option flag `1` — write-once nativo do OpenEMR |
| Responsavel obrigatorio para menores | `guardiansname` | Conditional: required if `DOB` indica < 18 anos |
| Consentimento antes de lembrete | `hipaa_allallowsms`, `hipaa_allowemail`, `allow_whatsapp` | Verificado pelo integration service antes de cada envio |
| Revogacao de consentimento | `hipaa_allowsms`, `hipaa_allowemail`, `allow_whatsapp` | Revogacao imediata: interrompe envios futuros, nao cancela mensagem ja enviada, loga evento de revogacao |
| Upload max 50MB | Documents | Config no reverse proxy (client_max_body_size) — HTTP 413 se excedido |
| Extensoes permitidas | Documents | PDF, JPG, PNG, DOC, DOCX — rejeitar outras com mensagem clara. Config via OpenEMR globals > Documents > Allowed file extensions |
| CEP formato | `postal_code` | Regex: `\d{5}-?\d{3}` |
| Telefone formato | `phone_cell` | Formato brasileiro obrigatorio: XX9XXXXXXXX, normalizacao automatica +55 antes do envio |
| Janela de lembrete | Lembrete | Consultas com inicio em 23-25h a partir do momento da verificacao; verificacao a cada 5 minutos |
| Brute force | `users` | 5 tentativas falhas → bloqueio de 15 min por conta; fail2ban no VPS bloqueia IP apos 10 tentativas em 10 min |
| Sessao timeout | `users` | 15 min de inatividade para desconexao automatica, 8h duracao maxima de sessao |

---

## State Transitions

### Appointment Status

```text
   * (Confirmed)
   |      \
   v       v
   + (Arrived)   - (Canceled)
   |
   v
   @ (Checked In) → auto-creates encounter
   |
   v
   > (Checked Out)

   % (No Show) ← from any status except > (Checked Out)
```

### Notification Status

```text
   pending → sent
   pending → failed → retry (1h) → sent | failed_permanent
   failed_permanent → admin_notified (apos 3 falhas)
   failed_permanent → fallback_channel (sms ou email, se consentido)
```

### User Lifecycle

```text
   Active → Inactive (admin desativa)
   Active → Locked (5+ login failures)
   Locked → Active (apos 15 min auto-desbloqueio ou admin desbloqueia)
   Active → Password_Reset (admin força troca ou politica expiração)
   Password_Reset → Active (usuario troca senha)
   Inactive → Active (admin reativa)

   NOTA: Nunca excluir usuario — manter historico de auditoria.
         Usuario desativado nao pode fazer login mas mantem
         registro de todas as acoes realizadas.
```

### Consent Lifecycle

```text
   Opt-in (paciente marca consentimento)
      ↓
   Active → lembretes enviados pelo canal consentido
      ↓
   Revoke (paciente desmarca) → log de revogacao
      ↓
   Revoked → nenhum lembrete enviado pelo canal revogado
      ↓
   Re-opt-in (paciente marca novamente) → log de reativacao
      ↓
   Active

   NOTA: Mensagem ja enviada antes da revogacao nao e cancelada.
         Revogacao tem efeito imediato a partir do momento do registro.
```

---

## Entity: BFF Session (Integration Service — patient-facing)

### Modelo do BFF (nao e tabela OpenEMR — cache/audit no integration service)

| Campo | Tipo | Notas |
|-------|------|-------|
| patient_pid | String | FK para patient_data, extraido do token SMART on FHIR |
| access_token_hash | String | Hash do token do paciente (nao armazena token) |
| token_expiry | DateTime | Validade do token patient |
| last_action | String | Ultima acao BFF executada (register, update, upload, etc.) |
| last_action_at | DateTime | Timestamp da ultima acao |
| consent_snapshot | JSON | Snapshot de consentimentos no momento da acao (sms, email, whatsapp, telehealth) |
| ip_address | String | IP do paciente (para auditoria LGPD) |
| user_agent | String | Browser/app do paciente |

---

## Entity: Data Export (Integration Service — LGPD Portability)

### Modelo de Exportacao (nao e tabela — gerado sob demanda)

| Formato | Escopo | Metodo | Notas |
|---------|--------|--------|-------|
| CSV | Demographics, appointments | OpenEMR Reports ou BFF endpoint | Legivel por maquina, Art. 18(V) |
| PDF | Prontuario completo (encounters, documentos) | OpenEMR Reports ou BFF endpoint | Legivel por humano |
| ZIP | Documentos anexados (exames, laudos) | Integration service endpoint | Arquivos originais criptografados em repouso, descriptografados para export |

### Integration Service Export Endpoint

| Endpoint | Metodo | Escopo | Auth |
|----------|--------|--------|------|
| `/internal/export/{pid}/csv` | GET | Demographics + appointments | Bearer token (BFF service) |
| `/internal/export/{pid}/pdf` | GET | Prontuario completo | Bearer token (BFF service) |
| `/internal/export/{pid}/documents` | GET | ZIP com documentos | Bearer token (BFF service) |

### Retencao e Destruicao (LGPD)

| Tipo de Dado | Retencao Minima | Destruicao |
|--------------|----------------|------------|
| Registros medicos | 20 anos | Anonimizacao apos expiracao |
| Dados operacionais (agendamentos) | 5 anos | Destruicao segura apos expiracao |
| Logs de lembretes | 90 dias | Shred/overwrite |
| Logs de auditoria | 5 anos | Destruicao segura |
| Consentimento | duracao do tratamento + 5 anos | Destruicao segura |
| Backups diarios | 30 dias | Shred com verificacao |
| Backups mensais | 12 meses | Shred com verificacao |

---

## Encryption Architecture (Dual-Layer)

### Layer 1: LUKS (Volume-Level)

| Aspecto | Detalhe |
|---------|---------|
| Escopo | Volume inteiro do banco de dados (`db_data`) |
| Algoritmo | AES-256-XTS |
| Key management | Passphrase armazenada separadamente do VPS (cofre de senhas ou HSM) |
| Rotacao | Re-criptografia do volume inteiro com nova passphrase |
| Backup | Chave LUKS em cofre separado do volume de dados |

### Layer 2: CryptoGen (Document-Level)

| Aspecto | Detalhe |
|---------|---------|
| Escopo | Documentos individuais (exames, laudos) |
| Algoritmo | AES-256 (via OpenEMR CryptoGen) |
| Key management | Chave AES-256 com rotacao periodica (12 meses) |
| Rotacao | Script de rotacao re-criptografa documentos com nova chave |
| Revogacao/emergencia | Procedimento de revogacao para comprometimento de chave |

---

## Entity: OAuth2 Client Registration (OpenEMR oauth2_clients)

### Campos para Patient Frontend

| Campo | Valor | Notas |
|-------|-------|-------|
| client_id | `medpront-patient-app` | Identificador do app Next.js |
| client_secret | NULL (public client) | PKCE flow — nao requer secret |
| redirect_uri | `https://portal.dominio.com/api/auth/callback/openemr` | NextAuth.js callback |
| scopes | `patient/*.rs openid fhirUser` | Escopos patient-only |
| grant_types | `authorization_code` | Com PKCE obrigatorio |
| is_confidential | 0 | Public client |
| is_enabled | 1 | Ativo |
| auto_approve | 1 | Auto-approval para patient scopes (ONC) |

### Campos para Integration Service BFF

| Campo | Valor | Notas |
|-------|-------|-------|
| client_id | `medpront-bff-service` | Identificador do BFF |
| client_secret | `<generated>` | Confidential client |
| scopes | `openid api:oemr api:fhir` | Staff-level scopes |
| grant_types | `client_credentials` | Service-to-service |
| is_confidential | 1 | Confidential client |
| is_enabled | 1 | Ativo |