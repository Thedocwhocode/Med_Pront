# API Contracts: Med_Pront

## OpenEMR REST/FHIR API (consumed by integration service)

### Authentication (Integration Service → OpenEMR)
```
POST /oauth2/default/token
Body: { "grant_type": "client_credentials", "client_id": "...", "client_secret": "...", "scope": "openid api:oemr api:fhir" }
Response: { "access_token": "...", "token_type": "Bearer", "expires_in": 3600, "scope": "..." }
```

### Authentication (Patient Frontend → OpenEMR via SMART on FHIR)
```
Authorization Code + PKCE flow:
1. GET /oauth2/default/authorize?response_type=code&client_id=...&redirect_uri=...&scope=patient/*.rs openid fhirUser&code_challenge=...&code_challenge_method=S256
2. User authenticates → redirect with ?code=...
3. POST /oauth2/default/token { grant_type: "authorization_code", code: "...", code_verifier: "...", redirect_uri: "..." }
4. Response: { "access_token": "...", "token_type": "Bearer", "expires_in": 3600, "refresh_token": "...", "patient": "pid", "scope": "patient/*.rs" }
```

### Appointments (FHIR Appointment)
```
GET /fhir/Appointment?date=2026-05-05&status=booked
Response: Bundle of Appointment resources with patient, practitioner, status
```

### Patient Demographics
```
GET /api/patient/{pid}
Response: { "fname", "lname", "phone_cell", "email", "hipaa_allowsms", ... }
```

### Document Upload
```
POST /api/document/upload
Body: multipart/form-data { patient_id, category_id, file }
```

## Integration Service API (internal)

### Check Reminders (cron endpoint)
```
GET /internal/reminders/check
Triggers: scan appointments 24h ahead, verify consent, send reminders
Response: { "checked": N, "sent": N, "skipped": N, "failed": N }
```

### Send Reminder
```
POST /internal/reminders/send
Body: { "appointment_id": "...", "channel": "whatsapp|sms|email" }
Response: { "status": "sent|failed|skipped", "reason": "..." }
```

### Consent Verification
```
GET /internal/consent/{patient_pid}
Response: { "sms": true|false, "email": true|false, "whatsapp": true|false }
```

## WhatsApp Business API (external)

### Send Template Message
```
POST https://graph.facebook.com/v18.0/{phone_id}/messages
Headers: Authorization: Bearer {token}
Body: {
  "messaging_product": "whatsapp",
  "to": "+55XXXXXXXXXXX",
  "type": "template",
  "template": {
    "name": "appointment_reminder",
    "language": { "code": "pt_BR" },
    "components": [
      { "type": "body", "parameters": [
        { "type": "text", "text": "Nome Paciente" },
        { "type": "text", "text": "05/05/2026 14:00" },
        { "type": "text", "text": "Presencial" }
      ]}
    ]
  }
}
```

**Constraint**: Template must be pre-approved by Meta. No clinical data in parameters.

## Docker Compose Contract

### Services

| Service | Image | Port (internal) | Depends On |
|---------|-------|-----------------|------------|
| traefik | traefik:v3 | 80, 443 | — |
| openemr | openemr/openemr:7.0.2 | 8080, 8443 | db |
| frontend | med_pront/frontend:latest | 3000 | integration |
| db | mariadb:10.11 | 3306 | — |
| integration | med_pront/integration:latest | 8000 | openemr |
| cloudflare-tunnel | cloudflare/cloudflared:latest | — | traefik |

### Networks
- `frontend`: traefik ↔ openemr
- `backend`: openemr ↔ db ↔ integration
- `egress`: integration only (for WhatsApp/SMS/email APIs)

### Volumes
- `db_data`: encrypted (LUKS), MariaDB data
- `doc_data`: encrypted (LUKS), OpenEMR documents
- `backup_data`: backup scripts + temp files