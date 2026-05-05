<!--
Sync Impact Report
==================
Version change: 0.0.0 → 1.0.0
Modified principles: N/A (initial ratification)
Added sections:
  - 7 Core Principles (I–VII)
  - Architecture & Infrastructure Constraints
  - Development Workflow & Compliance Gates
  - Governance
Removed sections: N/A
Templates requiring updates:
  - .specify/templates/plan-template.md: ✅ no changes needed (Constitution Check gate already present)
  - .specify/templates/spec-template.md: ✅ compatible (requirements format aligns)
  - .specify/templates/tasks-template.md: ✅ compatible (phase structure aligns)
  - .specify/templates/constitution-template.md: ✅ source template, not modified
Follow-up TODOs: None
-->

# Med_Pront Constitution

## Core Principles

### I. OpenEMR-Core

O núcleo do sistema é o **OpenEMR 7.x**. Toda funcionalidade DEVE ser
implementada como extensão, módulo ou configuração do OpenEMR — nunca como
substituição. Customizações que exijam código fora do OpenEMR (ex.: serviço de
integração WhatsApp) MUST ser isoladas em containers separados que consomem a
API REST/FHIR do OpenEMR, sem modificar seu schema ou código-fonte diretamente.
Campos customizados de cadastro DEVEM usar Layout Based Forms / User Defined
Fields nativos do OpenEMR. Rationale: preservar upgrade path, evitar fork
inadvertido, manter compatibilidade com patches de segurança do upstream.

### II. LGPD Compliance by Design

Todo dado pessoal e dados sensíveis de saúde (art. 5º LGPD) DEVEM ser
tratados sob os princípios de finalidade, adequação, minimização e
segurança. O sistema MUST registrar consentimento explícito para cada
finalidade de processamento (lembretes, telemedicina, compartilhamento com
convênio). Retenção de dados MUST seguir política documentada; exclusão ou
anonimização MUST ser executada ao término do prazo. Nenhum dado sensível
PODE ser exposto em integrações externas (WhatsApp, SMS, e‑mail). Rationale:
conformidade legal e ética médica (CFM Resolução 2.331/2023); violação
implica sanções administrativas (ANPD) e éticas (CFM).

### III. Security-First Infrastructure

A infraestrutura MUST adotar modelo Zero-Trust: acesso externo exclusivamente
via túnel (Cloudflare Tunnel ou equivalente), VPS sem portas expostas além de
HTTPS. Autenticação MUST exigir senhas robustas + 2FA para perfis médico e
administrativo. RBAC MUST ser configurado com perfis mínimos (recepção, médico,
admin), cada um com acesso estritamente necessário. Criptografia em trânsito
(HTTPS/TLS 1.2+) e em repouso (LUKS ou equivalente para volumes de DB e
documentos) é NON-NEGOTIABLE. Rationale: dados de saúde são alvo de alto valor;
vazamento gera responsabilidade civil e criminal.

### IV. Data Minimization in External Integrations

Mensagens de lembrete, notificações e qualquer comunicação via canais externos
(WhatsApp, SMS, e‑mail) DEVEM conter exclusivamente: nome do paciente,
data/hora da consulta, tipo (presencial/telemedicina) e telefone da clínica.
Nenhum diagnóstico, CID, dado clínico ou informação sensível PODE ser
incluído. O serviço de integração MUST operar como buffer: consome dados do
OpenEMR internamente, filtra e envia apenas o mínimo necessário. Rationale:
minimização é princípio legal (art. 6º LGPD) e redução de superfície de
exposição em canais não controlados.

### V. Audit & Accountability

Logs de auditoria DEVEM estar ativos e imutáveis em ambiente de produção.
Registro MUST cobrir: login/logout, acessos a prontuário, criação/alteração/
exclusão de agendamentos, upload/download de documentos, alterações em permissões
RBAC. Logs NEVER podem ser desativados para ganho de performance. Retenção
MUST ser de no mínimo 5 anos (conforme CFM e LGPD). Revisão periódica de logs
MUST ser procedimento documentado. Rationale: trilha de auditoria é requisito
legal (LGPD art. 46) e ético (CEM art. 79) e é evidência em investigações.

### VI. Incremental Delivery with Security Baseline

O plano de implementação DEVE ser incremental (MVP → incrementos). O MVP
MUST incluir segurança como requisito não negociável desde o primeiro
deploy: HTTPS, RBAC, autenticação forte, logs de auditoria, criptografia em
repouso. Funcionalidades subsequentes DEVEM ser priorizadas por valor clínico
e risco de exposição de dados. Ambiente de testes com base anonimizada MUST
existir antes de qualquer teste em dados reais. Rationale: segurança não é
acréscimo; vulnerabilidades em MVPs são exploradas antes de correções.

### VII. Sovereignty & Jurisdiction

Dados de pacientes (PHI) DEVEM residir exclusivamente em jurisdições
Brasil/UE. Backups externos DEVEM usar storage S3-like em provedores cujos
data centers estejam em jurisdições compatíveis. Nenhum dado sensível PODE
transitar por ou ser armazenado em provedores que violem soberania de dados
(Ex.: S3 US-East sem garantias de jurisdição, Google Drive sem
admin-lockdown). Serviços de API externos (WhatsApp Business, SMS gateway)
DEVEM operar sob DPA ou termos que garantam não-armazenamento de conteúdo.
Rationale: LGPD art. 33 (transferência internacional) exige garantias
equivalentes; CFM proíbe armazenamento de prontuários fora de controle do
médico.

## Architecture & Infrastructure Constraints

O sistema DEVE operar em VPS Linux endurecida (Debian/Ubuntu LTS) com
firewall (ufw/iptables), fail2ban, SSH acessível apenas por chave + 2FA.
Containers DEVEM ser orquestrados via docker-compose (não Kubernetes —
complexidade desnecessária para clínica de pequeno/médio porte). O reverse
proxy (Traefik ou Nginx) MUST terminar HTTPS, aplicar rate limiting e atuar
como WAF mínimo. O banco de dados (MariaDB) MUST rodar em container com
volume criptografado, sem exposição de porta ao host. Documentos anexos DEVEM
ser armazenados em volume criptografado separado. O serviço de integração
(WhatsApp/notificações) DEVE ser container isolado, conectado ao OpenEMR via
rede interna Docker, sem acesso direto à internet — apenas egress para APIs
de notificação. Backups DEVEM ser diários, criptografados (AES-256 ou
equivalente), enviados para storage externo S3-like com rotação de 30 dias
diários + 12 meses mensais. Testes de restore DEVEM ocorrer trimestralmente.

## Development Workflow & Compliance Gates

Toda mudança no sistema DEVE passar pelos seguintes gates antes de merge/deploy:

1. **Constitution Check**: a mudança viola algum princípio? Se sim, MUST ser
   rejeitada ou MUST gerar emenda à constituição com justificativa e aprovação
   documentada.
2. **Security Review**: mudanças que tocam autenticação, autorização, criptografia,
   exposição de dados ou integrações externas DEVEM passar por security review.
3. **LGPD Impact**: mudanças que criam novos fluxos de dados pessoais ou
   alteram retenção/consentimento DEVEM ter avaliação de impacto documentada.
4. **Audit Trail Verification**: mudanças que alteram logging DEVEM garantir
   que nenhuma categoria de auditoria existente seja removida ou reduzida.

Toda configuração de campo customizado, módulo ou integração DEVE ser
documentada em `.specify/` com spec e plan vinculados. O ambiente de produção
MUST ter monitoramento básico: health checks dos containers, alertas de
disco/CPU, e coleta de logs com retenção adequada.

## Governance

Esta constituição tem precedência sobre quaisquer práticas, convenções ou
decisões ad hoc. Emendas DEVEM ser propostas com: (a) justificativa técnica
ou legal, (b) impacto nos princípios existentes, (c) plano de migração para
sistemas já em produção. Emendas que contrariem princípios NON-NEGOTIABLE
(II, III, IV, V) DEVEM ser rejeitadas. Versão segue versionamento semântico:
MAJOR para remoção/redefinição de princípio, MINOR para adição/expansão,
PATCH para esclarecimentos. Compliance review MUST ocorrer a cada 6 meses
ou antes de cada release que toque segurança ou dados pessoais.

**Version**: 1.0.0 | **Ratified**: 2026-05-04 | **Last Amended**: 2026-05-04