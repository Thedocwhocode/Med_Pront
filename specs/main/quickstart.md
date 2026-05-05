# Quickstart: Med_Pront

## Prerequisites

- VPS Debian 12 LTS (4 vCPU, 16GB RAM, 100GB SSD)
- Domain pointing to Cloudflare
- Cloudflare account with Tunnel enabled
- WhatsApp Business API credentials (optional)
- Twilio account with +55 number (optional)
- SMTP credentials (Mailgun/Gmail)

## Quick Start

```bash
# 1. Clone the repo
git clone https://github.com/org/med_pront.git && cd med_pront

# 2. Harden VPS
sudo bash scripts/setup-vps.sh

# 3. Configure environment
cp docker/.env.example docker/.env
# Edit .env with: DB passwords, SMTP, Twilio, WhatsApp API keys, OpenEMR admin

# 4. Start services
cd docker && docker compose up -d

# 5. Setup Cloudflare Tunnel
sudo bash scripts/setup-cloudflare-tunnel.sh

# 6. Configure OpenEMR
# Access https://your-domain/openemr
# Run initial setup wizard
bash scripts/setup-openemr.sh

# 7. Verify
make health-check    # Check all containers
make audit-verify    # Verify audit logging is active
make backup-test     # Test backup creates encrypted dump
```

### Periodic Backup Restore Testing (CHK030)

Para garantir a integridade dos backups, execute testes de restore conforme:
- **Frequência**: Trimestral (a cada 3 meses)
- **Procedimento**: `docker/backup/restore.sh` em ambiente de staging isolado
- **Validação**: Verificar integridade do banco, acesso a documentos criptografados, login funcional com credenciais existentes
- **Registro**: Documentar resultado do teste em log de auditoria com data, status (PASS/FAIL), e ações corretivas se necessário
```

## Post-Setup Configuration

### OpenEMR Admin Tasks (manual)
1. **Layout Based Forms**: Admin > Forms > Layouts > Demographics — add custom fields (escolaridade, nome_pai, terapias_tipo, terapias_contato, encaminhamento_contato, convenio_nome, convenio_numero, allow_whatsapp)
2. **Lists**: Admin > Forms > Lists — create dropdown options for escolaridade, terapias, convenio
3. **Calendar Categories**: Admin > Calendar > Categories — add Consulta Presencial, Consulta Telemedicina, etc.
4. **ACL Groups**: Admin > ACL — create recepcao, medico, admin groups
5. **Audit Logging**: Admin > Globals > Logging — enable all except SELECT queries, enable encryption
6. **Documents**: Admin > Globals > Documents — enable encryption, create categories
7. **Telehealth**: Modules > Comlink Telehealth — register, install, enable
8. **ICD-10**: Admin > Coding > External Data Loads — install ICD10 codeset
9. **Users**: Admin > Users — create accounts, assign ACL groups, enable 2FA

### Custom Theme (MedPront)
```bash
# The custom theme is auto-loaded via custom.yaml injection mechanism.
# CSS file at docker/openemr/custom/assets/css/medpront-theme.css
# Config at docker/openemr/custom/assets/custom.yaml
# Docker bind-mount in docker-compose.yml: ./openemr/custom/:/var/www/localhost/htdocs/openemr/custom/
# No build step required — pure CSS overrides loaded by OpenEMR Header.php
```

### Patient Frontend (Next.js)
```bash
# 1. Install dependencies
cd frontend && npm install

# 2. Configure environment
cp .env.example .env.local
# Edit .env.local with:
#   NEXTAUTH_URL=https://portal.your-domain.com
#   NEXTAUTH_SECRET=<generate with: openssl rand -base64 32>
#   OPENEMR_FHIR_URL=https://your-domain.com/apis/default/fhir
#   OPENEMR_AUTH_URL=https://your-domain.com/oauth2/default
#   OPENEMR_BFF_URL=https://your-domain.com/bff  (integration service)
#   OPENEMR_CLIENT_ID=<registered OAuth2 client ID>
#   OPENEMR_CLIENT_SECRET=<if confidential client>

# 3. Register OAuth2 client in OpenEMR
# Admin > System > API Clients > Add New
#   Client ID: medpront-patient-app
#   Redirect URI: https://portal.your-domain.com/api/auth/callback/openemr
#   Scopes: patient/*.rs openid fhirUser
#   Grant type: Authorization Code + PKCE (public client)

# 4. Development
npm run dev    # http://localhost:3000

# 5. Production build
npm run build && npm start

# 6. Docker deployment (add to docker-compose.yml)
# frontend service on 'frontend' network, proxied by Traefik
```

### Integration Service (BFF Extension)
```bash
# Extend existing integration service with BFF endpoints
# See specs/main/contracts/frontend-contracts.md for API contracts

# Set cron for reminders (every 5 min)
echo "*/5 * * * * curl -s http://localhost:8000/internal/reminders/check" | crontab -
```

## Verification Checklist

- [ ] HTTPS with valid TLS cert (via Cloudflare Tunnel)
- [ ] RBAC: recepcao cannot access medical records
- [ ] 2FA enabled for medico and admin
- [ ] Audit logs recording login/logout and patient access
- [ ] Document encryption enabled
- [ ] DB volume encrypted (LUKS)
- [ ] Backups running daily with encryption
- [ ] Cloudflare Tunnel active (no VPS ports exposed)
- [ ] Integration service sending reminders only to consented patients
- [ ] Telehealth module generating video links
- [ ] Custom theme (medpront-theme.css) loaded via custom.yaml
- [ ] Patient frontend (Next.js) accessible via HTTPS
- [ ] SMART on FHIR OAuth2 client registered in OpenEMR
- [ ] BFF endpoints operational (registration, demographics, appointment, document upload)
- [ ] LGPD consent management working (sms, email, whatsapp, telehealth)
- [ ] Data minimization enforced (no clinical data in patient-facing responses)