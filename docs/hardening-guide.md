# Hardening Guide — Med_Pront VPS

## 1. Pré-requisitos

- Debian 12 LTS ou Ubuntu 22.04 LTS
- Acesso root via SSH com chave pública
- Domínio configurado no Cloudflare

## 2. Hardening da VPS

```bash
sudo bash scripts/setup-vps.sh
```

O script aplica automaticamente:
- **SSH key-only**: desativa autenticação por senha (`PasswordAuthentication no`)
- **fail2ban**: ban de 3600s após 5 tentativas falhas no SSH
- **UFW**: apenas IPs do Cloudflare podem acessar 80/443; SSH liberado
- **unattended-upgrades**: atualizações de segurança automáticas (sem auto-reboot)

## 3. Verificar Firewall

```bash
sudo ufw status verbose
# Deve mostrar apenas Cloudflare IPs para 80/443
```

## 4. Cloudflare Tunnel (Zero-Trust)

```bash
sudo bash scripts/setup-cloudflare-tunnel.sh
# Ou: defina CF_TUNNEL_TOKEN no .env e use o container cloudflare-tunnel
```

- Nenhuma porta exposta diretamente na VPS além do SSH
- Todo tráfego HTTP/HTTPS passa pelo túnel Cloudflare
- Certificado TLS gerenciado pelo Cloudflare + ACME (Let's Encrypt via DNS challenge)

## 5. Traefik (Reverse Proxy)

- Rate limiting: 100 req/s (burst 50) via middleware `rate-limit`
- Headers de segurança: `X-Frame-Options`, `X-Content-Type-Options`, `CSP`
- TLS 1.2 mínimo, cipher suites modernos
- Upload máximo: 50MB (middleware `upload-limit`)

## 6. Criptografia de Dados

### Em Trânsito
- TLS 1.2+ em todas as conexões externas (Cloudflare Tunnel)
- Conexões internas entre containers via rede Docker `backend` (isolada)

### Em Repouso
- Documentos: AES-256 via OpenEMR (`document_encryption=1`)
- Backups: AES-256-CBC com `openssl enc -pbkdf2 -iter 100000`
- Volume `db_data`: considerar LUKS no nível do disco para máxima proteção

## 7. Gerenciamento de Chaves

```bash
# Gerar chave de backup segura
openssl rand -base64 64 > /root/.backup_key
chmod 600 /root/.backup_key
# Adicionar ao .env: BACKUP_ENCRYPTION_KEY=$(cat /root/.backup_key)
```

- **Nunca** commitar `.env` ou chaves no git
- Rotacionar `BACKUP_ENCRYPTION_KEY` a cada 90 dias
- Guardar cópia da chave em cofre físico separado

## 8. Monitoramento

```bash
make health-check    # Estado dos containers
make audit-verify    # Últimas entradas do audit log
fail2ban-client status sshd  # Status do fail2ban
```

## 9. Checklist Pós-Deploy

- [ ] `ufw status` — apenas Cloudflare IPs em 80/443
- [ ] SSH funciona apenas com chave pública
- [ ] `docker ps` — todos os 5 containers rodando
- [ ] HTTPS funciona em https://yourdomain.com
- [ ] `make audit-verify` — audit log gravando eventos
- [ ] `make backup-test` — backup gera arquivo `.enc` válido
- [ ] 2FA configurado para medico e admin no OpenEMR
