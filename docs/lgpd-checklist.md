# LGPD Compliance Checklist — Med_Pront

**Reference**: Lei 13.709/2018 (LGPD) · ANPD Resolução CD/ANPD nº 2/2022

## 1. Base Legal para Tratamento de Dados

- [ ] Consentimento explícito coletado no cadastro (hipaa_allowsms, hipaa_allowemail, allow_whatsapp)
- [ ] Formulário de consentimento com linguagem clara e granular por canal
- [ ] Registro de data/hora e versão do termo aceito por paciente
- [ ] Possibilidade de revogação a qualquer momento via `/internal/consent/{pid}` revoke

## 2. Minimização de Dados

- [ ] Lembretes contêm apenas: nome, data, hora, tipo de consulta — sem CID, diagnóstico, medicamentos
- [ ] Campos opcionais não coletados por padrão (terapias_contato, encaminhamento_contato)
- [ ] Integração externa (WhatsApp, SMTP) não recebe dados clínicos
- [ ] Logs de auditoria não registram queries SELECT (minimização de rastreabilidade)
- [ ] Hash do conteúdo enviado registrado (content_hash) em vez do conteúdo completo

## 3. Segurança e Integridade

- [ ] TLS 1.2+ em todas as comunicações externas (Traefik + Cloudflare Tunnel)
- [ ] AES-256-CBC em documentos em repouso (doc_data volume)
- [ ] AES-256-CBC nos backups (backup.sh)
- [ ] Senhas SHA512 + salt no OpenEMR
- [ ] 2FA obrigatório para perfis medico e admin
- [ ] Sessão expira em 15 minutos de inatividade
- [ ] Histórico de senhas: 5 últimas não reutilizáveis

## 4. Acesso e RBAC

- [ ] Recepcao: Demographics addonly, Appointments write — sem acesso a prontuário clínico
- [ ] Medico: Medical Records write, Encounters write — sem acesso administrativo
- [ ] Admin: acesso completo com 2FA
- [ ] Documento "Prontuário Clínico" e "Exames/Laudo" — apenas medico e admin
- [ ] Logs de acesso auditados por perfil

## 5. Auditoria e Rastreabilidade

- [ ] Audit log ativo para: patient-record, scheduling, documents, security-administration
- [ ] Logs criptografados com hash SHA512
- [ ] IP capturado em cada evento de auditoria
- [ ] Retenção de logs mínima 5 anos (configurar política no S3/volume)
- [ ] Logs imutáveis (sem DELETE/UPDATE nas tabelas de auditoria)

## 6. Direitos do Titular

- [ ] Direito de acesso: paciente pode visualizar prontuário via Patient Portal
- [ ] Direito de retificação: medico/admin podem corrigir dados
- [ ] Direito de revogação de consentimento: via endpoint /internal/consent/{pid}/revoke
- [ ] Direito de exclusão: documentado — dados de saúde têm retenção mínima legal (CFM)
- [ ] Direito de portabilidade: exportação via OpenEMR Reports

## 7. Gestão de Incidentes

- [ ] Procedimento de notificação ANPD em até 72h documentado
- [ ] Contato do DPO/responsável documentado
- [ ] Plano de resposta a incidentes criado

## 8. Contratos e DPA

- [ ] DPA assinado com: provedor VPS, Cloudflare, Twilio (se aplicável), WhatsApp Business (se aplicável)
- [ ] DPA assinado com provedor SMTP
- [ ] Jurisdição verificada: dados em território brasileiro ou UE
- [ ] Registro de atividades de tratamento (ROPA) atualizado

---
*Última revisão: 2026-05-04*
