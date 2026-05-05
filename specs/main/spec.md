# Feature Specification: Prontuario Eletronico LGPD (Med_Pront)

**Feature Branch**: `main`
**Created**: 2026-05-04
**Status**: Draft
**Input**: Prompt spec — Prontuario eletronico LGPD para clinica de pequeno/medio porte (base OpenEMR)

## User Scenarios & Testing

### User Story 1 - Cadastro de Pacientes (Priority: P1)

A recepcao cadastra um novo paciente com todos os dados de identificacao,
contato, convenio, terapias e encaminhamento. O sistema armazena os dados de
forma estruturada usando campos nativos e customizados do OpenEMR Demographics.
O cadastro deve contemplar: nome completo, data de nascimento, CPF,
escolaridade, nome da mae, nome do pai, nome do responsavel (quando aplicavel),
endereco completo com CEP, e-mail, celular/WhatsApp, convenio, terapias/
reabilitacao (tipo + contatos da equipe), encaminhamento (nome + contato),
codificacao ICD-10/11, e consentimento explicito para lembretes.

**Why this priority**: Sem cadastro estruturado, nenhum outro modulo do
prontuario funciona. E a base de dados para agendamentos, documentos e
lembretes.

**Independent Test**: Cadastrar um paciente com todos os campos preenchidos e
verificar que os dados persistem corretamente, tanto nativos quanto
customizados.

**Acceptance Scenarios**:

1. **Given** um novo paciente sem registro, **When** a recepcao preenche todos
   os campos obrigatorios e submete, **Then** o registro e criado com dados
   nativos e customizados persistidos corretamente.
2. **Given** um paciente ja cadastrado, **When** a recepcao edita campo
   customizado (ex.: terapias), **Then** a alteracao e registrada no log de
   auditoria e o dado e atualizado.
3. **Given** um paciente menor de idade, **When** o campo responsavel legal e
   preenchido, **Then** o sistema vincula o responsavel ao paciente.

---

### User Story 2 - Agendamento de Consultas (Priority: P2)

A recepcao agenda consultas presenciais e por telemedicina usando o modulo
Calendar do OpenEMR. Cada agendamento associa paciente e profissional, registra
tipo (presencial/telemedicina), data/hora e status (confirmado, cancelado, etc.).

**Why this priority**: Agendamento e o fluxo operacional principal da clinica.
Depende do cadastro (P1) mas e independente de documentos e lembretes.

**Independent Test**: Criar um agendamento presencial e um por telemedicina,
verificar que ambos aparecem na agenda do profissional e que o status e
controlavel.

**Acceptance Scenarios**:

1. **Given** um paciente cadastrado, **When** a recepcao agenda consulta
   presencial, **Then** o agendamento aparece na agenda do profissional com
   tipo "presencial".
2. **Given** um agendamento existente, **When** o status e alterado para
   "cancelado", **Then** a alteracao e registrada no log de auditoria e o
   slot da agenda e liberado.

---

### User Story 3 - Telemedicina (Priority: P3)

Para agendamentos do tipo telemedicina, o sistema gera link de teleconsulta
vinculado ao agendamento, via modulo Comlink Telehealth ou equivalente. O
prontuario registra que a consulta foi realizada em telemedicina.

**Why this priority**: Telemedicina agrega valor mas requer agendamento
funcional. Pode ser adiado se a clinica priorizar presencial primeiro.

**Independent Test**: Agendar consulta de telemedicina, gerar link, simular
acesso ao link, e verificar que o encounter registra modalidade telemedicina.

**Acceptance Scenarios**:

1. **Given** um agendamento de telemedicina, **When** o profissional acessa a
   consulta, **Then** um link de video e gerado e vinculado ao agendamento.
2. **Given** uma teleconsulta realizada, **When** o profissional encerra o
   encounter, **Then** o prontuario registra modalidade "telemedicina".

---

### User Story 4 - Documentos e Exames Digitalizados (Priority: P2)

A recepcao ou medico faz upload de exames/relatorios digitalizados (recebidos
via WhatsApp/e-mail) para o registro do paciente. Os anexos ficam em storage
criptografado, sem exposicao direta a internet.

**Why this priority**: Digitalizacao e o objetivo principal de "se livrar do
papel". Prioridade igual ao agendamento — ambos P2, independentes entre si.

**Independent Test**: Fazer upload de um PDF de exame para um paciente e
verificar que o documento aparece no prontuario e esta armazenado em volume
criptografado.

**Acceptance Scenarios**:

1. **Given** um paciente cadastrado, **When** a recepcao faz upload de
   exame, **Then** o documento e anexado ao registro do paciente em storage
   criptografado.
2. **Given** um documento anexado, **When** o medico acessa o prontuario,
   **Then** o documento e visivel e o acesso e registrado no log de auditoria.

---

### User Story 5 - Lembretes Automaticos de Consulta (Priority: P3)

O sistema envia lembretes automaticos 24h antes da consulta por e-mail e/ou
WhatsApp, com conteudo minimalista (nome, data/hora, tipo, telefone da
clinica — sem dados clinicos). O envio requer consentimento explicito do
paciente, registrado no cadastro.

**Why this priority**: Lembretes reduzem no-show mas dependem de cadastro com
consentimento e agendamentos funcionais. Podem ser adiadados sem comprometer
o core do prontuario.

**Independent Test**: Cadastrar paciente com consentimento, agendar consulta
para 24h no futuro, verificar que o lembrete e enviado sem dados clinicos.

**Acceptance Scenarios**:

1. **Given** um paciente com consentimento para lembretes, **When** faltam
   24h para a consulta, **Then** o lembrete e enviado contendo apenas nome,
   data/hora, tipo e telefone da clinica.
2. **Given** um paciente sem consentimento, **When** faltam 24h para a
   consulta, **Then** nenhum lembrete e enviado e o evento e logado.

---

### Edge Cases

- CPF duplicado: sistema deve impedir cadastro de paciente com CPF ja
  existente no sistema.
- Paciente menor de idade sem responsavel: campo responsavel e obrigatorio
  para menores.
- Agendamento em horario ja ocupado: sistema deve alertar conflito com
  WARNING (nao bloquear). O profissional pode sobrepor o alerta se
  necessario. Conflito parcial (mesmo horario com sobreposicao) tambem
  gera warning.
- Upload de arquivo >50MB: rejeitar com mensagem clara (HTTP 413).
- Upload de extensao nao suportada: rejeitar com mensagem informando
  extensoes permitidas (PDF, JPG, PNG, DOC, DOCX). Configurado via
  OpenEMR globals > Documents > Allowed file extensions.
- Falha no envio de lembrete (API WhatsApp indisponivel): registrar falha no
  log, tentar retry em 1h, apos 3 falhas permanentes: (a) notificar admin
  por e-mail, (b) tentar canal alternativo (SMS se consentido, e-mail se
  consentido), (c) marcar agendamento para follow-up manual.
- Revogacao de consentimento: interromper envios imediatamente, logar evento.
  Se lembrete ja foi enviado antes da revogacao: registrar evento de
  revogacao retroativa, nao tentar cancelar mensagem ja enviada, impedir
  futuros envios a partir do momento da revogacao.
- Acesso nao autorizado (RBAC): exibir mensagem "Acesso negado" e registrar
  tentativa no log de auditoria com IP, usuario, recurso tentado.
- Falha permanente de SMS: tentar e-mail como canal secundario se o paciente
  tem consentimento de e-mail ativo. Se nenhum canal estiver disponivel,
  notificar admin para contato manual.

## Requirements

### Functional Requirements

- **FR-001**: Sistema MUST cadastrar pacientes com campos nativos e
  customizados conforme especificacao (nome, nascimento, CPF, escolaridade,
  nome da mae/pai/responsavel, endereco+CEP, e-mail, celular/WhatsApp,
  convenio, terapias, encaminhamento, ICD-10/11).
- **FR-002**: Sistema MUST registrar consentimento explicito para lembretes
  (WhatsApp/e-mail) no cadastro do paciente.
- **FR-003**: Sistema MUST impedir cadastro duplicado por CPF.
- **FR-004**: Sistema MUST agendar consultas presenciais e por telemedicina
  usando o modulo Calendar do OpenEMR.
- **FR-005**: Sistema MUST controlar status de agendamento (confirmado,
  cancelado, etc.) e registrar alteracoes em log de auditoria.
- **FR-006**: Sistema MUST gerar links de teleconsulta vinculados ao
  agendamento via modulo de telehealth.
- **FR-007**: Sistema MUST registrar no encounter que a consulta foi
  realizada em telemedicina.
- **FR-008**: Sistema MUST permitir upload de documentos/exames ao registro
  do paciente, armazenados em volume criptografado.
- **FR-009**: Sistema MUST enviar lembretes 24h antes da consulta com
  conteudo minimalista (sem dados clinicos) via e-mail e/ou WhatsApp.
  Janela de envio: consultas com inicio em 23-25 horas a partir do
  momento da verificacao. O nome do profissional e permitido no lembrete
  (dados de identificacao, nao clinicos). Verificacao executada a cada
  5 minutos pelo integration service.
- **FR-010**: Sistema MUST respeitar consentimento: sem consentimento, sem
  lembrete.
- **FR-011**: Sistema MUST registrar toda atividade em log de auditoria
  (login/logout, acessos a prontuario, alteracoes em agendamentos e
  documentos, mudancas de permissao RBAC).
- **FR-012**: Sistema MUST permitir a exportacao de dados do paciente em
  formato legivel por máquina (PDF e/ou CSV) conforme LGPD Art. 18(V).
  Escopo: dados demograficos, encounters, documentos anexados, historico
  de agendamentos. Exportacao via OpenEMR Reports ou integration service
  endpoint dedicado.
- **FR-013**: Sistema MUST implementar retencao de dados por periodo minimo
  de 5 anos conforme LGPD, com processo de anonimizacao ou destruicao
  segura apos expiracao. Registros medicos devem ser mantidos pelo prazo
  legal (20 anos para documentos, 5 anos para dados operacionais).
- **FR-014**: Sistema MUST gerenciar o ciclo de vida de usuarios: criacao
  (cadastro com perfil RBAC), ativacao/desativacao (sem exclusao de
  registro — manter auditoria), alteracao de perfil (com log de
  mudanca). Usuarios desativados mantem historico de acoes mas nao podem
  fazer login.
- **FR-015**: Sistema MUST gerar alertas automaticos para eventos de
  auditoria suspeitos: multiplos logins falhos (>5 em 15min), acesso a
  prontuario sem encounter vinculado, tentativas de acesso a recursos
  nao autorizados. Alertas enviados ao admin por e-mail.
- **FR-016**: Sistema MUST implementar timeout de sessao: 15 minutos de
  inatividade para desconexao automatica, 8 horas de duracao maxima de
  sessao. Configurado via OpenEMR globals.
- **FR-017**: Sistema MUST proteger contra forca bruta: apos 5 tentativas
  de login falhas, bloquear a conta por 15 minutos. Fail2ban no VPS
  complementa com bloqueio de IP apos 10 tentativas em 10 minutos.
- **FR-018**: Sistema MUST gerenciar chaves de criptografia com procedimentos
  definidos para: (a) rotacao periodica da chave AES-256 (a cada 12 meses,
  via script de rotacao que re-criptografa documentos com nova chave), (b)
  backup seguro da chave mestra em local separado do volume de dados
  (cofre de senhas ou HSM), (c) procedimento de revogacao/emergencia em
  caso de comprometimento. Chave LUKS do volume deve ter passphrase
  armazenada separadamente do VPS.
- **FR-019**: Sistema MUST implementar destruicao segura de dados: wipe seguro
  (shred/overwrite) para volumes LUKS descomissionados, destruicao de
  backups expirados (>12 meses mensais, >30 dias diarios) com verificacao
  de integridade pos-destruicao, e registro em log de auditoria.
- **FR-020**: Integration service MUST implementar observabilidade: logs
  estruturados em formato JSON (timestamp, level, service, action,
  patient_id hash, error_detail), endpoint /health com detalhes
  (status do DB, status do OpenEMR API, uptime, last_error_time),
  e metricas de error rate com alerta automatico para o admin quando
  error rate exceder 5% em 5 minutos.

### Key Entities

- **Paciente**: Identificacao completa, contato, convenio, terapias,
  encaminhamento, codificacao ICD, consentimento. Entidade central.
- **Agendamento**: Vincula paciente e profissional, com data/hora, tipo
  (presencial/telemedicina), status. Depende de Paciente.
- **Encounter**: Registro da consulta realizada. Pode ser presencial ou
  telemedicina. Depende de Agendamento.
- **Documento**: Arquivo anexado ao paciente (exame, relatorio).
  Armazenado em volume criptografado. Depende de Paciente.
- **Lembrete**: Notificacao enviada ao paciente antes da consulta.
  Depende de Agendamento e Consentimento.
- **Usuario**: Profissional ou staff da clinica, com perfil RBAC.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Recepcao consegue cadastrar um paciente completo em menos de
  5 minutos.
- **SC-002**: Agendamento de consulta leva menos de 1 minuto para consultas
  recorrentes.
- **SC-003**: Upload de documentos e concluido em menos de 30 segundos para
  arquivos ate 50MB.
- **SC-004**: Lembretes sao enviados em 100% dos casos com consentimento ativo
  (excluindo falhas de API externa).
- **SC-005**: Logs de auditoria cobrem 100% das acoes listadas em FR-011.
- **SC-006**: Nenhum dado clinico sensivel aparece em mensagens de lembrete.

## Assumptions

- A clinica tem conexao estavel a internet para acesso ao sistema
  (minimo: 10Mbps download / 5Mbps upload, considerando teleconsulta por video).
- A VPS sera provisionada em provedor com data center no Brasil (ex.:
  Hostinger, Locaweb).
- OpenEMR 7.x Docker image oficial esta disponivel e mantida.
- WhatsApp Business API sera contratada como servico de terceiros, com
  DPA (Data Processing Agreement) cobrindo jurisdicao de dados no Brasil,
  retencao minima e direitos LGPD do titular. Limite de rate por tier
  documentado (1K-100K conversacoes/24h conforme tier Meta).
- Twilio SMS sera usado com plano de contingencia: se SMS falhar, e-mail
  e tentado como canal secundario (se consentido pelo paciente). SLA do
  Twilio: 99.95% uptime documentado em contrato.
- O modulo Comlink Telehealth esta disponivel para OpenEMR 7.x, com
  plano de migracao para Jitsi-Meet self-hosted na Fase 6+ (pos-MVP).
- A clinica nao precisa de modulos hospitalares (UTI, enfermaria, etc.) no
  escopo inicial.
- O certificado TLS sera obtido via Cloudflare (incluido no Tunnel).
- Cloudflare Tunnel e o unico ponto de entrada publico. Em caso de
  indisponibilidade do Cloudflare: estrategia de failover com DNS apontando
  diretamente para o IP do VPS com certificado Let's Encrypt auto-assinado
  pelo Traefik, ativado manualmente pelo admin. SLA target: 99.5% uptime,
  janela de manutencao: domingo 2h-6h.
- RTO (Recovery Time Objective): <4h. RPO (Recovery Point Objective): <24h
  (baseado em backup diario).
- Testes de carga: 15 usuarios concorrentes, 200 consultas/dia, API response
  <200ms p95 (integration service), <500ms p95 (OpenEMR REST), <1s (FHIR).
- Sessoes: 15min timeout de inatividade, 8h duracao maxima.
- Protecao contra forca bruta: 5 tentativas falhas → bloqueio de 15min por
  conta; fail2ban no VPS bloqueia IP apos 10 tentativas em 10min.
- "addonly" no contexto RBAC significa: pode criar novos registros e visualizar
  registros existentes naquela categoria, mas NAO pode editar ou excluir
  registros ja existentes. Para categorias restritas (Prontuario Clinico,
  Exames/Laudo), o perfil recepcao nao tem acesso nenhum (nem visualizar).
- Validacao de numero de telefone: formato brasileiro obrigatorio (XX9XXXXXXXX)
  com normalizacao automatica (+55) antes do envio de mensagens.
- E-mail de lembrete segue o mesmo principio de minimizacao do WhatsApp:
  sem dados clinicos, apenas nome, data/hora, tipo de consulta e telefone
  da clinica. O nome do profissional e permitido (dado de identificacao,
  nao clinico).