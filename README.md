# Med_Pront — Prontuário Eletrônico LGPD

Prontuário eletrônico autohospedado para clínicas ambulatoriais de pequeno/médio porte.  
Baseado em **OpenEMR 7.x**, com infraestrutura Zero-Trust via Cloudflare Tunnel.

## Stack

| Componente | Tecnologia |
|-----------|-----------|
| EMR Core | OpenEMR 7.0.2 (PHP 8.1+, Bootstrap 4.6.2) |
| Tema Customizado | CSS Custom Properties + custom.yaml injection (TC-1) |
| Banco de dados | MariaDB 10.11 |
| Reverse proxy | Traefik v3 |
| Tunnel | Cloudflare Tunnel (cloudflared) |
| Serviço de notificações | Python 3.11 + FastAPI (BFF + adapters) |
| Frontend externo (paciente) | Next.js 14 + React 18 + Tailwind CSS + shadcn/ui |
| SMS | Twilio API (com fallback para e-mail — CHK036) |
| Containerização | Docker Compose (3 redes: frontend, backend, egress) |

## Arquitetura

```
                          INTERNET
                             │
                             ▼
                  ┌──────────────────┐
                  │  Cloudflare CDN   │
                  │  (DDoS, WAF, TLS) │
                  └────────┬─────────┘
                           │
                  ┌────────▼─────────┐
                  │ Cloudflare Tunnel │
                  │  (cloudflared)    │
                  └────────┬─────────┘
                           │
              ╔════════════╧══════════════╗
              ║    FRONTEND NETWORK       ║
              ║    10.10.10.0/24          ║
              ║                           ║
              ║  ┌─────────────────────┐  ║
              ║  │  Traefik v3         │  ║
              ║  │  (TLS termination,  │  ║
              ║  │   routing, rate     │  ║
              ║  │   limiting)         │  ║
              ║  └────┬──────────┬─────┘  ║
              ║       │          │        ║
              ╚═══════╧══════════╧════════╝
                      │          │
         ┌────────────┘          └────────────┐
         ▼                                     ▼
┌─────────────────────┐          ┌─────────────────────────┐
│  OpenEMR (Apache)    │          │  Patient Frontend        │
│  PHP 8.1             │          │  Next.js 14              │
│                      │          │  (HTTPS :3000)           │
│  ┌────────────────┐  │          │                          │
│  │ custom.yaml    │  │          │  SMART on FHIR OAuth2   │
│  │ medpront-theme │  │          │  PKCE + NextAuth.js     │
│  │ enhancements.js│  │          │  (TC-5)                 │
│  │ logo/ícone     │  │          │                          │
│  └────────────────┘  │          │  • Pré-cadastro         │
│  (TC-1: sobrevive    │          │  • Portal do paciente   │
│   a upgrades Docker) │          │  • Upload documentos    │
│                      │          │  • Entrada teleconsulta │
│  • Cadastro Mestre   │          └───────────┬─────────────┘
│  • Agenda Principal  │                      │
│  • Dashboard Paciente│         ╔════════════╧══════════════╗
│  • Encounters/Consultas│       ║   BACKEND NETWORK        ║
│  • Documentos Clínicos│        ║   10.10.20.0/24          ║
│  • CID/Diagnósticos   │         ║                          ║
│  • Auditoria/Admin    │         ║  ┌─────────────────────┐ ║
│  • Telehealth (interno)│        ║  │ Integration Service │ ║
└───────────┬───────────┘          ║  │ FastAPI :8000       │ ║
            │                      ║  │ (BFF + Notificações)│ ║
            │                      ║  │                     │ ║
            │                      ║  │ NotificationService │ ║
            │                      ║  │  ├─ WhatsAppAdapter │ ║
            │                      ║  │  ├─ SMSAdapter      │ ║
            │                      ║  │  └─ EmailAdapter    │ ║
            │                      ║  │                     │ ║
            │                      ║  │ ConsentService      │ ║
            │                      ║  │  └─ LGPD checks     │ ║
            │                      ║  └──────────┬──────────┘ ║
            │                      ║             │             ║
            │                      ╚═════════════╧═════════════╝
            │                                    │
            └──────────────┬─────────────────────┘
                           │
              ╔════════════╧══════════════╗
              ║    DATA NETWORK           ║
              ║    10.10.30.0/24          ║
              ║                           ║
              ║  ┌─────────────────────┐  ║
              ║  │  MariaDB 10.11      │  ║
              ║  │  (volumes LUKS)     │  ║
              ║  └─────────┬───────────┘  ║
              ║            │              ║
              ║  ┌─────────▼───────────┐  ║
              ║  │  docs_data/         │  ║
              ║  │  (AES-256 encrypted │  ║
              ║  │   documents volume) │  ║
              ║  └─────────────────────┘  ║
              ╚════════════════════════════╝

              ╔════════════════════════════╗
              ║    EGRESS NETWORK          ║
              ║    (external APIs)         ║
              ║                            ║
              ║  Twilio SMS ──────┐        ║
              ║  WhatsApp API ────┤        ║
              ║  SMTP (Mailgun) ──┤        ║
              ║  Jitsi-Meet ──────┘        ║
              ║  (Fase 6: self-hosted)     ║
              ╚════════════════════════════╝
```

## Estrutura do Projeto

```
Med_Pront/
├── docker/
│   ├── openemr/
│   │   └── custom/                     # Tema customizado (sobrevive a upgrades)
│   │       └── assets/
│   │           ├── custom.yaml          # Injeção de assets (Header.php)
│   │           ├── css/
│   │           │   └── medpront-theme.css  # ~500 linhas, 12 seções
│   │           ├── js/
│   │           │   └── medpront-enhancements.js  # UX enhancements vanilla JS
│   │           └── img/
│   │               ├── medpront-logo.svg    # Logo da clínica
│   │               └── medpront-favicon.ico # Favicon
│   ├── integration-service/            # BFF + Notification pipeline
│   │   └── src/
│   │       ├── main.py                 # FastAPI app
│   │       ├── config.py               # Settings via env vars
│   │       ├── adapters/
│   │       │   ├── openemr.py          # OpenEMR REST/FHIR client
│   │       │   ├── email.py            # SMTP adapter
│   │       │   ├── whatsapp.py         # WhatsApp Business adapter + BR validation
│   │       │   └── sms.py              # Twilio adapter + BR validation (CHK036)
│   │       ├── services/
│   │       │   ├── consent.py          # LGPD consent management
│   │       │   └── notification.py      # Reminder orchestration + retry logic
│   │       └── models/
│   │           └── reminder.py         # Reminder domain model
│   ├── docker-compose.yml
│   ├── docker-compose.dev.yml
│   └── .env.example
├── frontend/                           # Patient-facing Next.js app (Fase 5-6)
│   └── (em construção)
├── scripts/
│   ├── setup-vps.sh
│   ├── setup-cloudflare-tunnel.sh
│   └── setup-openemr.sh
├── specs/main/
│   ├── spec.md                         # Especificação completa
│   ├── plan.md                         # Plano de implementação (6 fases)
│   ├── research.md                     # Phase 0 — pesquisa técnica
│   ├── data-model.md                   # Modelo de dados + LGPD
│   ├── quickstart.md                   # Guia de deploy + verificação
│   ├── contracts/
│   │   ├── api-contracts.md            # Contratos REST/FHIR
│   │   └── frontend-contracts.md       # Contratos frontend externo
│   └── checklists/
│       └── release-gate.md             # 87/87 PASS — pronto para produção
├── docs/
│   ├── hardening-guide.md
│   ├── lgpd-checklist.md
│   └── backup-restore.md
├── Makefile
└── README.md
```

## Funcionalidades

### Interno (OpenEMR + Tema Customizado)
- **Cadastro Mestre do Paciente** com campos nativos + LBF: CPF (validado, write-once), CEP, convênio, terapias, responsável legal, consentimento LGPD granular
- **Agenda Principal** com status visuais por cor (confirmado/pendente/cancelado/telemedicina/no-show) e timeline do dia
- **Dashboard do Paciente** com resumo clínico sempre visível, sem troca de contexto
- **Encounters/Consultas** com SOAP notes, prescrições, evolução clínica
- **Documentos Clínicos** em volume criptografado (AES-256), com categorias e ACL por perfil
- **CID/Diagnósticos** com busca ICD-10 carregada
- **Telemedicina** via Comlink Telehealth (Fase 0-5) → Jitsi-Meet self-hosted (Fase 6+, Q4 2026)
- **RBAC** 3 perfis: Recepção, Médico, Admin
- **Auditoria** completa com SHA512, retenção 5 anos, logs criptografados
- **2FA** TOTP para Médico e Admin (10 códigos de backup single-use)
- **Perfil do Usuário** e **Configurações Admin** (LBF, Listas, ACL, Globals)

### Externo (Frontend Next.js — Fase 5-6)
- **Pré-cadastro** mobile-first em etapas com validação inline, CPF/telefone mascarados
- **Portal do Paciente** simplificado — próximas consultas, upload de documentos, perfil
- **Confirmação/Cancelamento** de consulta em 1 clique
- **Entrada em Teleconsulta** com link pré-autenticado (Jitsi)
- **Consentimento LGPD** explícito e granular por canal antes de cada ação
- **Login seguro** via SMART on FHIR OAuth2 + PKCE + NextAuth.js (TC-5)

### Notificações Automatizadas
- **Lembretes 24h antes** por canais múltiplos: E-mail, WhatsApp, SMS
- **Pipeline multicanal** — WhatsApp Business API + Twilio SMS + SMTP
- **Validação BR** de telefone `(XX)9XXXXXXXX` em WhatsApp e SMS (CHK034)
- **SMS → Email fallback** em falha permanente de SMS, se paciente tem consentimento de e-mail (CHK036)
- **Retry logic**: 3 tentativas, intervalos de 1h, alerta admin em falha permanente (T057)
- **Consent check** antes de cada envio — `ConsentService.is_channel_allowed()` (LGPD)
- **Mensagens mínimas** — sem dados clínicos ou diagnóstico (data minimization)

### Segurança & LGPD
- **Zero-Trust**: VPS sem portas expostas, acesso exclusivo via Cloudflare Tunnel
- **Volume LUKS** para banco de dados em repouso
- **Documentos criptografados** AES-256 em volume dedicado
- **TLS 1.2+** em todo tráfego externo
- **Consentimento granular** por canal (SMS, e-mail, WhatsApp, telemedicina) com revogação imediata
- **Minimização de dados** — frontend paciente nunca expõe CID, diagnósticos, SOAP notes
- **Auditoria imutável** — todos os acessos a dados do paciente são registrados
- **Soberania de dados** — VPS em jurisdição brasileira, sem trânsito internacional
- **Backups diários** criptografados com restore testado trimestralmente (CHK030)

## Design System v1

Tema customizado aplicado via mecanismo oficial `custom.yaml` do OpenEMR — **zero modificação no core**, sobrevive a upgrades Docker.

| Token | Cor | Hex | Uso |
|-------|-----|-----|-----|
| primary | Teal discreto | #0D7377 | Ações, links, sidebar ativa |
| neutral-50 | Branco suave | #F8FAFA | Fundo principal |
| neutral-900 | Preto suave | #1A2424 | Texto principal |
| success | Verde clínico | #1B7A3D | Confirmado, concluído |
| warning | Âmbar | #B8860B | Pendência, atenção |
| error | Vermelho sóbrio | #B91C1C | Cancelado, erro |
| info | Azul | #1D5FA6 | Telemedicina, informativo |

**Tipografia**: Inter (legibilidade clínica, fallback system-ui) | **Acessibilidade**: WCAG 2.1 AA, contraste 4.5:1+

### Componentes Internos (CI-1 a CI-10)
`PatientHeader` · `AppointmentCard` · `StatusBadge` · `SectionedForm` · `DocumentList` · `ClinicalSummaryPanel` · `ActionDrawer` · `AuditHintBlock` · `QuickSearch` · `AgendaTimeline`

### Melhorias de UI (`medpront-enhancements.js`)
Sidebar colapsável com persistência localStorage · Máscaras de input (CPF/CEP/telefone) com MutationObserver · Validação inline de CPF · Skip-to-content (a11y) · Focus trap em modais · Seções colapsíveis em formulários

## Release Gate: 87/87 PASS

Todos os 87 itens do [release gate](specs/main/checklists/release-gate.md) passaram na auditoria de qualidade de requisitos. Veja o checklist completo para detalhes de cada item (LGPD, Segurança, Infraestrutura, Integrações, Performance, UX).

## Quick Start

```bash
# 1. Clonar o repositório
git clone <repo-url> && cd med_pront

# 2. Endurecer a VPS
sudo bash scripts/setup-vps.sh

# 3. Configurar variáveis de ambiente
cp docker/.env.example docker/.env
# Editar: DB passwords, SMTP, Twilio, WhatsApp, domínio

# 4. Subir os serviços
cd docker && docker compose up -d

# 5. Configurar Cloudflare Tunnel
sudo bash scripts/setup-cloudflare-tunnel.sh

# 6. Configurar OpenEMR
bash scripts/setup-openemr.sh

# 7. Verificar
make health-check     # Checar todos os containers
make audit-verify     # Verificar auditoria ativa
make backup-test      # Testar backup criptografado
```

## Pré-requisitos

- VPS Debian 12 LTS (4 vCPU, 16 GB RAM, 100 GB SSD)
- Domínio apontando para Cloudflare
- Cloudflare Tunnel habilitado
- Docker 24+ e Docker Compose 2.20+
- Credenciais: WhatsApp Business API (opcional), Twilio (opcional), SMTP (Mailgun/Gmail)
- Banda mínima: 10↓/5↑ Mbps (recomendado: 25↓/10↑ Mbps para telemedicina)

## Documentação

- [docs/hardening-guide.md](docs/hardening-guide.md) — Configuração de segurança da VPS
- [docs/lgpd-checklist.md](docs/lgpd-checklist.md) — Checklist de conformidade LGPD
- [docs/backup-restore.md](docs/backup-restore.md) — Procedimentos de backup e restore
- [specs/main/quickstart.md](specs/main/quickstart.md) — Guia de verificação pós-deploy
- [specs/main/plan.md](specs/main/plan.md) — Plano de implementação (6 fases)
- [specs/main/research.md](specs/main/research.md) — Pesquisa técnica e decisões
- [specs/main/checklists/release-gate.md](specs/main/checklists/release-gate.md) — Release gate 87/87

## Roadmap

| Fase | Sprint | Entregável | Status |
|------|--------|-----------|--------|
| Fase 1 | 1 | Diagnóstico e Inventário de telas | Planejado |
| Fase 2 | 2-3 | **Design System + Tema OpenEMR** | Concluído |
| Fase 3 | 4-6 | Redesign Cadastro, Agenda, Dashboard | Pendente |
| Fase 4 | 7-8 | Componentização (biblioteca interna) | Pendente |
| Fase 5 | 9-11 | Front Externo v1 (Next.js) | Pendente |
| Fase 6 | 12-14 | Portal do Paciente + Telemedicina | Pendente |

## Licença

Uso interno — não distribuir sem autorização.
