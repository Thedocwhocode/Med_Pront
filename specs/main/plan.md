# Implementation Plan: Frontend Redesign OpenEMR — Med_Pront

**Branch**: `main` | **Date**: 2026-05-04 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/main/spec.md` + Frontend Redesign Prompt

## Summary

Redesign do front-end do OpenEMR para clínica ambulatorial de pequeno/médio porte no Brasil. O core clínico permanece no OpenEMR 7.x, com customização via tema, overrides controlados e LBF. Fluxos de paciente (pré-cadastro, portal, confirmação, upload de docs, telemedicina) são construídos como front externo React/Next.js consumindo REST/FHIR do OpenEMR. Design system clínico com foco em legibilidade, baixa carga cognitiva e velocidade operacional.

## Technical Context

**Language/Version**: PHP 8.x (tema OpenEMR) + TypeScript/React 18+ / Next.js 14+ (front externo)
**Primary Dependencies**: OpenEMR 7.0.2, Bootstrap 4.6.2 (OpenEMR interno), Tailwind CSS (front externo), shadcn/ui (front externo)
**Storage**: MariaDB 10.11 (OpenEMR), S3-like (documentos criptografados)
**Testing**: PHPUnit (OpenEMR internals), Vitest + Playwright (front externo)
**Target Platform**: Web — desktop (interno clínico), mobile-first (front externo paciente)
**Project Type**: Web application dual — tema interno + front externo desacoplado
**Performance Goals**: Home operacional < 2s carga, API response < 200ms p95, front externo LCP < 2.5s
**Load Testing Parameters** (CHK057): 15 usuários concorrentes (interno), 50 usuários concorrentes (front externo), 200 consultas/dia, 50 req/s no integration service, 3:1 read:write ratio
**Bandwidth Minimum** (CHK080): 10 Mbps download / 5 Mbps upload para operações clínicas; 25 Mbps download / 10 Mbps upload recomendado considerando telemedicina (video 720p ~1.5 Mbps por stream)
**Constraints**: Zero modificação no schema/core do OpenEMR, LGPD compliance, dados clínicos nunca expostos no front externo, upgrades sustentáveis
**Scale/Scope**: ~15 telas internas (tema/customização), ~6 telas externas (React/Next.js)

### Decisões Técnicas (RESOLVED)

| # | Questão | Decisão | Rationale |
|---|---------|---------|-----------|
| TC-1 | Mecanismo exato de tema customizado no OpenEMR 7.x que sobrevive a upgrades | **`custom.yaml` injection** em `/custom/assets/custom.yaml` com Docker bind-mount | Mecanismo oficial do OpenEMR (Header.php lê custom.yaml e injeta CSS em toda página). Diretório `/custom/` sobrevive a upgrades. Não requer SCSS compilation nem fork. |
| TC-2 | Portal do Paciente nativo do OpenEMR — estender ou substituir? | **Hybrid (Approach C)** — manter portal para messaging, construir front externo para todo o resto | Portal é PHP monolítico (Phreeze framework) sem extensibilidade mobile. Messaging funcional. Migração para Approach B (full external) conforme FHIR write APIs amadurecem. |
| TC-3 | Endpoints FHIR/REST disponíveis para fluxos de paciente | **FHIR R4 read-only** (`patient/*` scope) + **Standard REST write** via integration service BFF (`client_credentials`) | FHIR: 30+ recursos read, Patient write only. Standard REST: full CRUD mas requer staff credentials. Gaps: sem API para auto-registro, appointment status update (PR #7333), geração programática de portal credentials. |
| TC-4 | Bootstrap override strategy no OpenEMR | **CSS custom properties + `!important` seletivo** via custom.yaml | OpenEMR 7.0.2 usa **Bootstrap 4.6.2** (NÃO 5). Sem CSS variables nativas do BS. Override: definir `:root` custom properties, usar `!important` apenas contra BS utilities de alta especificidade. Migração futura para CSS custom properties quando OpenEMR migrar para BS5. |
| TC-5 | Auth flow para front externo | **SMART on FHIR v2.2.0** (Authorization Code + PKCE) + **NextAuth.js** wrapping OpenEMR OIDC | Padrão ONC para apps de paciente. Auto-approval para `patient/*` scopes. Refresh tokens (3-month). NextAuth.js gerencia sessão e token refresh no Next.js. Dual-token: `patient/*` para FHIR reads, `client_credentials` para writes via BFF. |

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Princípio | Verificação | Status | Notas |
|-----------|-------------|--------|-------|
| I. OpenEMR-Core | Front externo NÃO substitui core — consome via REST/FHIR. Tema usa overrides, não fork. | PASS | Regra explícita: sem modificação de schema ou código-fonte |
| II. LGPD Compliance by Design | Front externo expõe apenas dados mínimos. Consentimento verificado antes de cada interação. | PASS | Data minimization enforced no API gateway |
| III. Security-First Infrastructure | Front externo acessa via HTTPS + auth controlado. Sem portas adicionais. | PASS | Cloudflare Tunnel + Traefik |
| IV. Data Minimization in External Integrations | Portal do paciente mostra apenas: próximas consultas, ações pendentes, upload. Sem diagnóstico, CID, dados clínicos. | PASS | API gateway filtra campos sensíveis |
| V. Audit & Accountability | Front externo gera logs de acesso (login, visualização de consulta, upload). | PASS | Middleware de auditoria no API gateway |
| VI. Incremental Delivery with Security Baseline | Fase 1 = tema + home operacional. Front externo vem em Fase 5. Segurança desde o início. | PASS | Roadmap incremental |
| VII. Sovereignty & Jurisdiction | VPS no Brasil, dados não transitam para fora. Front externo hospedado na mesma VPS. | PASS | Single-region deployment |

**Gate Status**: PASS — nenhuma violação identificada. Princípios I-IV são particularmente críticos para o redesign de frontend e devem ser re-verificados após Phase 1.

## Project Structure

### Documentation (this feature)

```text
specs/main/
├── plan.md              # This file
├── research.md           # Phase 0 — frontend research output
├── data-model.md         # Phase 1 — entities (existing + frontend additions)
├── quickstart.md         # Phase 1 — setup guide (existing + frontend additions)
├── contracts/
│   ├── api-contracts.md  # Phase 1 — existing + frontend API contracts
│   └── frontend-contracts.md # Phase 1 — external frontend API contracts
└── tasks.md              # Phase 2 output (NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
docker/
├── openemr/
│   ├── custom/
│   │   └── assets/
│   │       ├── custom.yaml            # Asset injection config (survives upgrades)
│   │       ├── css/
│   │       │   └── medpront-theme.css  # Custom theme override (TC-1)
│   │       └── js/
│   │           └── medpront-enhancements.js
│   ├── layout-forms/               # LBF definitions
│   ├── overrides/                  # Config/template overrides (controlled)
│   └── modules/                    # Custom modules (if needed)
├── integration-service/           # BFF + WhatsApp/email service (TC-3, TC-5)
├── docker-compose.yml
└── .env

frontend/                           # External patient frontend
├── src/
│   ├── app/                        # Next.js 14 app router
│   │   ├── (auth)/                 # Login/register (SMART on FHIR + PKCE)
│   │   ├── portal/                 # Patient portal
│   │   ├── pre-cadastro/           # Pre-registration flow
│   │   └── teleconsulta/           # Telehealth entry
│   ├── components/
│   │   ├── ui/                     # Design system components (shadcn/ui)
│   │   ├── patient/               # Patient-specific components
│   │   └── layout/                # Layout components
│   ├── lib/
│   │   ├── openemr-client.ts       # API client (FHIR reads + BFF writes)
│   │   └── auth.ts                 # NextAuth.js + SMART on FHIR (TC-5)
│   └── styles/                     # Design tokens
├── tests/
│   ├── e2e/                        # Playwright
│   └── unit/                       # Vitest
├── next.config.ts
├── tailwind.config.ts
└── package.json

scripts/
docs/
```

**Structure Decision**: Dual-structure — tema OpenEMR fica em `docker/openemr/custom/` usando o mecanismo oficial `custom.yaml` (TC-1), que sobrevive a upgrades Docker. Front externo em `frontend/` como app Next.js 14 independente. Integration service atua como BFF para operações de escrita em nome do paciente (TC-3, TC-5).

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| N/A | N/A | N/A — nenhuma violação de constituição |

## Frontend Redesign — Inventario de Telas

### Telas Internas (OpenEMR Core + Tema)

| # | Tela | Usuário | Classificação | Frequência | Criticidade Legal | Sensibilidade | Mobile? |
|---|------|---------|---------------|-----------|-------------------|--------------|---------|
| I-1 | Home Operacional | Recepção | THEME_CUSTOMIZATION | Alta | Baixa | Média | Não |
| I-2 | Cadastro Mestre do Paciente | Recepção/Admin | THEME_CUSTOMIZATION | Alta | Alta | Alta | Não |
| I-3 | Agenda Principal | Recepção | THEME_CUSTOMIZATION | Alta | Média | Baixa | Não |
| I-4 | Dashboard do Paciente | Médico | THEME_CUSTOMIZATION | Alta | Alta | Alta | Não |
| I-5 | Encounters/Consulta | Médico | CORE_OPENEMR | Alta | Alta | Alta | Não |
| I-6 | Documentos Clínicos | Médico/Recepção | CORE_OPENEMR | Média | Alta | Alta | Não |
| I-7 | Issues/Diagnósticos (CID) | Médico | CORE_OPENEMR | Média | Alta | Alta | Não |
| I-8 | Permissões/Admin | Admin | CORE_OPENEMR | Baixa | Alta | Alta | Não |
| I-9 | Log de Auditoria | Admin | CORE_OPENEMR | Baixa | Alta | Alta | Não |
| I-10 | Config LBF/Listas | Admin | CORE_OPENEMR | Baixa | Média | Média | Não |
| I-11 | Calendário Semanal | Recepção/Médico | THEME_CUSTOMIZATION | Média | Baixa | Baixa | Não |
| I-12 | Busca de Paciente | Todos | THEME_CUSTOMIZATION | Alta | Baixa | Média | Não |
| I-13 | Insurance/Convênio | Recepção | THEME_CUSTOMIZATION | Média | Média | Média | Não |
| I-14 | Perfil do Usuário | Todos | THEME_CUSTOMIZATION | Baixa | Baixa | Baixa | Não |
| I-15 | Telehealth (interno) | Médico | CORE_OPENEMR | Média | Média | Média | Parcial |

### Telas Externas (Front Moderno)

| # | Tela | Usuário | Classificação | Frequência | Criticidade Legal | Sensibilidade | Mobile? |
|---|------|---------|---------------|-----------|-------------------|--------------|---------|
| E-1 | Login Seguro | Paciente | EXTERNAL_FRONT | Baixa | Média | Média | Sim |
| E-2 | Pré-cadastro | Paciente | EXTERNAL_FRONT | Baixa | Alta | Alta | Sim |
| E-3 | Atualização Cadastral | Paciente | EXTERNAL_FRONT | Baixa | Média | Média | Sim |
| E-4 | Portal do Paciente | Paciente | EXTERNAL_FRONT | Média | Baixa | Baixa | Sim |
| E-5 | Envio de Documentos/Exames | Paciente | EXTERNAL_FRONT | Baixa | Média | Média | Sim |
| E-6 | Confirmação/Cancelamento | Paciente | EXTERNAL_FRONT | Média | Baixa | Baixa | Sim |
| E-7 | Entrada Teleconsulta | Paciente/Médico | EXTERNAL_FRONT | Média | Média | Média | Sim |

## Design System v1 — Diretrizes

### Tom Visual
- Clínico, confiável, limpo, calmo, funcional
- Software operacional de saúde, não landing page
- Baixa ornamentação, alto contraste, foco em leitura

### Paleta Funcional

| Token | Cor | Hex | Uso |
|-------|-----|-----|-----|
| primary | Teal discreto | #0D7377 | Ações primárias, links, sidebar ativa |
| primary-light | Teal claro | #E6F5F5 | Hover, backgrounds sutis |
| neutral-50 | Branco suave | #F8FAFA | Fundo principal |
| neutral-100 | Cinza claro | #EDF2F2 | Cards, superfícies |
| neutral-300 | Cinza médio | #C1CCCC | Bordas, divisores |
| neutral-700 | Cinza escuro | #3D4F4F | Texto secundário |
| neutral-900 | Preto suave | #1A2424 | Texto principal |
| success | Verde clínico | #1B7A3D | Confirmado, concluído |
| warning | Âmbar | #B8860B | Pendência, atenção |
| error | Vermelho sóbrio | #B91C1C | Cancelado, erro |
| info | Azul info | #1D5FA6 | Telemedicina, ações informativas |

### Tipografia

| Nível | Tamanho | Peso | Uso |
|-------|---------|------|-----|
| heading-xl | 28-32px | 700 | Título de página |
| heading-lg | 20-24px | 600 | Título de seção |
| heading-md | 16-18px | 600 | Subtítulo, grupo de formulário |
| body | 16px | 400 | Texto corrido, formulários |
| body-sm | 14px | 500 | Labels, badges, metadados |
| caption | 12px | 500 | Timestamps, hints de auditoria |

Fonte primária: Inter (legibilidade em tela, amplo suporte a caracteres).
Fonte fallback: system-ui, -apple-system, sans-serif.

### Grid/Layout

- Sidebar fixa: 240px (colapsável: 64px)
- Topbar: 56px altura
- Conteúdo principal: max-width 1200px, padding 24px
- Grid interno: 12 colunas, gap 16px
- Layout padrão: 2 colunas (8+4) para dashboards, 1 coluna para formulários

### Padrões de Cor por Status (Agenda)

| Status | Background | Texto | Badge |
|--------|-----------|-------|-------|
| Confirmado | #E6F5F5 | #0D7377 | ● verde |
| Aguardando docs | #FFF8E1 | #B8860B | ● âmbar |
| Cancelado | #FEE2E2 | #B91C1C | ● vermelho |
| Telemedicina | #DBEAFE | #1D5FA6 | ● azul |
| Checked-in | #ECFDF5 | #1B7A3D | ● verde escuro |
| No-show | #F5F5F5 | #6B7280 | ● cinza |

### Padrões de Formulário
- Campos agrupados por seção com `<fieldset>` + `<legend>`
- Labels acima dos inputs, nunca inline
- Obrigatório: asterisco vermelho + `aria-required`
- Validação inline (não modal)
- Seções colapsíveis para cadastro longo
- Largura máxima de input: 400px (exceto textareas e endereço)

### Padrões de Tabela
- Cabeçalho fixo sticky
- Zebra striping sutil
- Linha clicável para abrir detalhe
- Coluna de ação à direita
- Paginação: 25/50/100 linhas
- Sort por header click

### Padrões de Card
- Card com borda 1px neutral-300, border-radius 8px
- Header com título + badge de status
- Body com conteúdo primário
- Footer com ações (se houver)
- Sem sombra pesada — elevação mínima

### Padrões de Modais/Drawers/Tabs
- Modal: para confirmações destrutivas e formulários simples
- Drawer: para ações rápidas da recepção (não sair da tela)
- Tabs: para organizar seções do dashboard do paciente
- Nunca empilhar modal sobre modal

### Acessibilidade
- WCAG 2.1 AA como mínimo
- Contraste 4.5:1 para texto normal, 3:1 para texto grande
- Focus ring visível em todos os interativos
- Navegação por teclado completa
- Screen reader: aria-labels, roles, live regions
- Skip-to-content link

### Responsividade
- Interno: desktop-first (1440px, 1280px, 1024px breakpoints)
- Externo: mobile-first (375px, 428px, 768px, 1024px breakpoints)
- Sidebar colapsa em <1024px
- Tabelas: scroll horizontal em <768px com colunas fixas

## Biblioteca de Componentes v1

### Componentes Internos (OpenEMR tema)

| # | Componente | Propósito | Estados |
|---|-----------|-----------|---------|
| CI-1 | PatientHeader | Cabeçalho fixo do paciente | loading, empty, with-alert, no-alert |
| CI-2 | AppointmentCard | Cartão de agendamento | confirmed, pending, canceled, telemedicine, no-show |
| CI-3 | StatusBadge | Badge de status | all status types, disabled |
| CI-4 | SectionedForm | Formulário em blocos temáticos | default, loading, error |
| CI-5 | DocumentList | Lista de documentos anexados | empty, loading, error, with-items |
| CI-6 | ClinicalSummaryPanel | Painel de resumo clínico | loading, empty, with-data |
| CI-7 | ActionDrawer | Drawer de ações rápidas | open, closed |
| CI-8 | AuditHintBlock | Bloco de auditoria discreto | default |
| CI-9 | QuickSearch | Busca rápida de paciente | idle, searching, results, no-results |
| CI-10 | AgendaTimeline | Timeline de agenda do dia | loading, empty, with-items |

### Componentes Externos (Front do Paciente)

| # | Componente | Propósito | Estados |
|---|-----------|-----------|---------|
| CE-1 | StepForm | Pré-cadastro em etapas | step-1..N, loading, error, success |
| CE-2 | ConsentBox | Bloco de consentimento LGPD | unchecked, checked, required |
| CE-3 | UploadZone | Envio de documentos | idle, dragging, uploading, success, error |
| CE-4 | NextAppointmentCard | Próxima consulta do paciente | confirmed, pending, canceled |
| CE-5 | TelevisitEntryCard | Entrada em teleconsulta | available, unavailable, in-progress |
| CE-6 | PatientTimelineLite | Histórico simplificado | empty, with-items, loading |

## UX por Perfil de Usuário

### Recepção
- **Princípio**: "O que preciso fazer agora?"
- Home operacional com pendências em destaque
- Agenda do dia como tela padrão
- Ações de 1 clique: confirmar, reagendar, abrir cadastro
- Sem exposição de dados clínicos sensíveis
- Drawer para ações rápidas sem perder contexto

### Médico
- **Princípio**: "Foco clínico, continuidade de raciocínio"
- Dashboard do paciente como tela central
- Resumo clínico sempre visível (não escondido em tabs)
- Atalho para novo encounter sempre acessível
- Documentos organizados por relevância temporal
- Minimizar troca de contexto entre telas

### Paciente (front externo)
- **Princípio**: "Simplicidade, confiança, privacidade"
- Mobile-first, toque como interação primária
- Máximo 3 ações por tela
- Consentimento claro e explícito antes de cada ação
- Sem jargão médico — linguagem acessível
- Feedback visual imediato para cada ação

## Roadmap de Implementação

### Fase 1 — Diagnóstico e Inventário (Sprint 1)
- **Objetivo**: Mapear telas existentes, classificar, identificar gaps
- **Entregáveis**: Inventário completo, classificação CORE/THEME/EXTERNAL, mapa de navegação
- **Dependências**: OpenEMR funcional em dev
- **Risco**: Incompletude do inventário → mitigar com walkthrough manual
- **Critério de aceite**: Todas as telas mapeadas e classificadas

### Fase 2 — Design System e Tema OpenEMR (Sprint 2-3)
- **Objetivo**: Criar tema customizado e design tokens
- **Entregáveis**: CSS custom theme, design tokens, paleta, tipografia, componentes base
- **Dependências**: TC-1 (mecanismo de tema), TC-4 (Bootstrap override)
- **Risco**: Override quebrar em upgrade → mitigar com CSS variables
- **Critério de aceite**: Tema aplicado sem modificar core, visual consistente em 3 telas

### Fase 3 — Redesign de Cadastro, Agenda e Dashboard (Sprint 4-6)
- **Objetivo**: Redesenhar as 3 telas de maior impacto operacional
- **Entregáveis**: Home operacional, cadastro reorganizado, agenda visual, dashboard do paciente
- **Dependências**: Design system pronto (Fase 2), LBF configurado
- **Risco**: LBF limitar reorganização → mitigar com overrides de template
- **Critério de aceite**: Recepção identifica pendências em <10s, médico vê contexto sem trocar de tela

### Fase 4 — Componentização (Sprint 7-8)
- **Objetivo**: Extrair componentes reutilizáveis das telas redesenhadas
- **Entregáveis**: Biblioteca de componentes internos (CI-1 a CI-10)
- **Dependências**: Fase 3 completa
- **Risco**: Componentes muito acoplados ao tema → mitigar com props e slots
- **Critério de aceite**: Componentes reusáveis em pelo menos 2 telas cada

### Fase 5 — Front Externo v1 (Sprint 9-11)
- **Objetivo**: Pré-cadastro, confirmação de consulta, upload de documentos
- **Entregáveis**: App Next.js com 3 fluxos, API client, auth flow
- **Dependências**: TC-2 (portal), TC-3 (API endpoints), TC-5 (auth flow)
- **Risco**: API insuficiente → mitigar com FHIR + REST fallback
- **Critério de aceite**: Paciente completa pré-cadastro em mobile em <3 min, upload <30s

### Fase 6 — Portal do Paciente e Telemedicina (Sprint 12-14)
- **Objetivo**: Portal simplificado + entrada em teleconsulta
- **Entregáveis**: Portal, timeline, teleconsulta entry, consentimento
- **Dependências**: Fase 5 completa, Comlink configurado
- **Risco**: UX de teleconsulta dependente de Comlink → mitigar com fallback Jitsi
- **Critério de aceite**: Paciente acessa teleconsulta em <2 cliques, sem dados clínicos expostos

## Fora do Escopo Inicial

- Redesign completo do prontuário clínico profundo (encounters detail)
- Substituição integral da agenda nativa
- Reescrita total do portal em todos os módulos
- Backend clínico paralelo ao OpenEMR
- Dark mode (futuro)
- Notificações push (futuro)
- App nativo mobile (futuro — PWA como intermediário)
- Internacionalização i18n (futuro — pt-BR como padrão)