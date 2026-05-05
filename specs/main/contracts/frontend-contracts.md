# Frontend API Contracts: Med_Pront — Patient BFF

## Architecture Overview

```
[Next.js Patient App]
       │
       ├── FHIR R4 reads ──────────> [OpenEMR /apis/{site}/fhir]
       │   (patient/* Bearer)         (direct, no BFF)
       │
       └── Write operations ──────> [Integration Service BFF]
           (patient Bearer)            │
                                        ├── Verify patient identity
                                        ├── Check LGPD consent
                                        ├── Strip clinical fields (data minimization)
                                        ├── Log audit entry
                                        └── Call OpenEMR Standard REST API
                                            (client_credentials Bearer)
```

## Authentication

### Patient → BFF
All BFF endpoints require a valid patient Bearer token (SMART on FHIR Authorization Code + PKCE). The BFF validates the token by introspection or by calling the OpenEMR userinfo endpoint.

```
Authorization: Bearer {patient_access_token}
```

The BFF extracts the `patient` ID from the token response to scope all operations to the authenticated patient only.

### BFF → OpenEMR Standard REST API
The BFF authenticates to OpenEMR using client_credentials:

```
POST /oauth2/default/token
Body: { "grant_type": "client_credentials", "client_id": "...", "client_secret": "...", "scope": "openid api:oemr api:fhir" }
Response: { "access_token": "...", "token_type": "Bearer", "expires_in": 3600 }
```

Token is cached and auto-refreshed before expiry.

---

## Endpoints

### 1. Patient Self-Registration (Pre-cadastro)

```
POST /bff/patient/register
Headers: Authorization: Bearer {patient_token}
Body: {
  "fname": "Maria",
  "lname": "de Souza",
  "DOB": "1984-03-15",
  "sex": "Female",
  "phone_cell": "+5511999999999",
  "email": "maria@example.com",
  "street": "Rua Exemplo 123",
  "city": "São Paulo",
  "state": "SP",
  "postal_code": "01000-000",
  "ss": "123.456.789-00",
  "mothersname": "Ana Costa",
  "hipaa_allowsms": true,
  "hipaa_allowemail": true
}
Response 201: {
  "pid": 12345,
  "puuid": "uuid-string",
  "status": "created",
  "message": "Pré-cadastro realizado. Aguarde confirmação da clínica."
}
Response 409: {
  "status": "conflict",
  "message": "CPF já cadastrado."
}
```

**BFF Logic:**
1. Verify patient token is valid (not expired, not revoked)
2. Check if patient already exists by CPF (ss field) — reject if duplicate
3. Call `POST /api/patient` with staff credentials
4. Create portal credentials for the patient (if API available; otherwise flag for manual creation)
5. Log audit entry: patient self-registration
6. Return patient PID and UUID (no clinical data)

---

### 2. Patient Demographics Update (Atualização Cadastral)

```
PUT /bff/patient/{pid}/demographics
Headers: Authorization: Bearer {patient_token}
Body: {
  "phone_cell": "+5511988888888",
  "email": "novoemail@example.com",
  "street": "Rua Nova 456",
  "postal_code": "02000-000"
}
Response 200: {
  "status": "updated",
  "fields_updated": ["phone_cell", "email", "street", "postal_code"],
  "message": "Dados atualizados. Alterações podem requerer aprovação da clínica."
}
Response 403: {
  "status": "forbidden",
  "message": "Token does not match patient PID."
}
```

**BFF Logic:**
1. Verify patient token's `patient` ID matches `{pid}` in URL
2. Allow only non-sensitive fields (phone, email, address, postal code)
3. Reject updates to: DOB, sex, ss/CPF, fname, lname (require staff intervention)
4. Call `PUT /api/patient/{puuid}` with staff credentials
5. Log audit entry: patient demographics update with field list
6. Return list of updated fields (no clinical data in response)

---

### 3. Appointment Confirmation/Cancelation

```
POST /bff/appointment/{eid}/confirm
Headers: Authorization: Bearer {patient_token}
Body: {}
Response 200: {
  "status": "confirmed",
  "appointment_id": "eid",
  "message": "Consulta confirmada."
}

POST /bff/appointment/{eid}/cancel
Headers: Authorization: Bearer {patient_token}
Body: {
  "reason": "patient_cancel",
  "note": "Conflito de horário"
}
Response 200: {
  "status": "canceled",
  "appointment_id": "eid",
  "message": "Consulta cancelada."
}
Response 422: {
  "status": "unprocessable",
  "message": "Não é possível cancelar consultas com menos de 24h de antecedência."
}
```

**BFF Logic:**
1. Verify patient token's patient ID matches appointment's patient
2. Business rule: cancelation requires 24h minimum notice
3. Call appointment status update (requires custom module or direct DB — PR #7333 not merged)
4. Log audit entry: appointment status change with reason
5. Trigger notification (SMS/WhatsApp) to clinic
6. Return status only (no clinical details)

---

### 4. Document Upload (Envio de Documentos/Exames)

```
POST /bff/patient/{pid}/document
Headers: Authorization: Bearer {patient_token}
Content-Type: multipart/form-data
Body: {
  "file": <binary>,
  "category": "Exames/Laudo",
  "description": "Hemograma 2026-05-04"
}
Response 201: {
  "status": "uploaded",
  "document_id": "doc-uuid",
  "category": "Exames/Laudo",
  "message": "Documento enviado. Aguarde revisão da equipe."
}
Response 413: {
  "status": "too_large",
  "message": "Arquivo excede o limite de 20MB."
}
Response 415: {
  "status": "unsupported_type",
  "message": "Tipo de arquivo não suportado. Use PDF, JPG ou PNG."
}
```

**Constraints:**
- Max file size: 20MB
- Allowed types: PDF, JPG, PNG, DICOM
- Category must match an existing OpenEMR document category
- Files are encrypted at rest (OpenEMR CryptoGen AES-256)

**BFF Logic:**
1. Verify patient token's patient ID matches `{pid}`
2. Validate file size and type
3. Scan for malware (clamav or similar)
4. Call `POST /api/patient/{pid}/document?path={category}` with staff credentials
5. Log audit entry: document upload with category and filename
6. Return document ID and category only

---

### 5. Teleconsulta Entry Link

```
GET /bff/appointment/{eid}/teleconsulta
Headers: Authorization: Bearer {patient_token}
Response 200: {
  "appointment_id": "eid",
  "telehealth_url": "https://meet.jit.si/room-uuid",
  "provider_name": "Dr. João Silva",
  "appointment_time": "2026-05-04T14:00:00-03:00",
  "status": "available",
  "message": "Link disponível 30 minutos antes da consulta."
}
Response 403: {
  "status": "forbidden",
  "message": "Link disponível apenas 30 minutos antes da consulta."
}
Response 404: {
  "status": "not_found",
  "message": "Consulta não encontrada ou não é teleconsulta."
}
```

**BFF Logic:**
1. Verify appointment exists and is telehealth category
2. Verify patient token matches appointment's patient
3. Business rule: link available only within +/-30 min of appointment time
4. Retrieve Comlink/Jitsi telehealth link from OpenEMR
5. Return link with provider name and appointment time
6. Log audit entry: patient accessed teleconsulta link

---

### 6. LGPD Consent Management

```
GET /bff/patient/{pid}/consents
Headers: Authorization: Bearer {patient_token}
Response 200: {
  "sms": true,
  "email": true,
  "whatsapp": false,
  "data_sharing": false,
  "telehealth": true
}

PUT /bff/patient/{pid}/consents
Headers: Authorization: Bearer {patient_token}
Body: {
  "sms": true,
  "email": true,
  "whatsapp": true,
  "data_sharing": false,
  "telehealth": true
}
Response 200: {
  "status": "updated",
  "consents": { "sms": true, "email": true, "whatsapp": true, "data_sharing": false, "telehealth": true },
  "message": "Preferências de consentimento atualizadas."
}
```

**BFF Logic:**
1. Verify patient token's patient ID matches `{pid}`
2. Map consent fields to OpenEMR fields: `hipaa_allowsms` (SMS), `hipaa_allowemail` (email), custom `allow_whatsapp` (WhatsApp), `hipaa_mailonly` (data sharing opt-out), telehealth consent (custom LBF)
3. Update via `PUT /api/patient/{puuid}` with staff credentials
4. Log audit entry: consent change with previous and new values
5. Return current consent state

---

## Error Responses (All Endpoints)

| Code | Status | When |
|------|--------|------|
| 400 | bad_request | Invalid input data |
| 401 | unauthorized | Missing or invalid Bearer token |
| 403 | forbidden | Token patient ID does not match resource PID |
| 404 | not_found | Resource does not exist |
| 409 | conflict | Duplicate resource (e.g., CPF already registered) |
| 413 | too_large | File exceeds size limit |
| 415 | unsupported_type | File type not allowed |
| 422 | unprocessable | Business rule violation (e.g., late cancelation) |
| 429 | rate_limited | Too many requests |
| 500 | internal_error | Unexpected server error |

All error responses follow the format:
```json
{
  "status": "error_code",
  "message": "Human-readable description in pt-BR"
}
```

---

## Rate Limiting

| Endpoint Group | Limit | Window |
|---------------|-------|--------|
| Registration | 3 requests | 1 hour |
| Demographics update | 10 requests | 1 hour |
| Appointment actions | 20 requests | 1 hour |
| Document upload | 10 requests | 1 hour |
| Teleconsulta link | 6 requests | 1 hour |
| Consent management | 10 requests | 1 hour |

---

## Data Minimization Rules

The BFF MUST strip the following fields from ALL responses to the patient frontend:

| Field | Reason |
|-------|--------|
| Diagnosis/CID codes | Clinical data — patient sees via medical request, not portal |
| Clinical notes | Medical record content |
| Lab results (detailed) | Requires medical interpretation |
| Medication details | Requires medical context |
| Provider notes | Internal clinical communication |
| Insurance policy numbers | Financial data — not patient-facing |
| Billing details | Financial data — not patient-facing |

Fields ALLOWED in responses:
- Appointment date/time, provider name, status, type (presencial/teleconsulta)
- Patient demographics (own data only)
- Document upload status and category
- Consent preferences
- Teleconsulta link and timing