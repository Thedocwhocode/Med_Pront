# Backup & Restore — Med_Pront

## Visão Geral

| Item | Método | Frequência | Retenção |
|------|--------|-----------|----------|
| Banco de dados (MariaDB) | mysqldump + gzip + AES-256 | Diário (cron) | 30 dias |
| Documentos (doc_data) | tar + AES-256 | Diário (cron) | 30 dias |
| Upload S3-like | aws s3 cp | Após backup local | Configurável |

## Backup Manual

```bash
# Backup completo (DB + documentos)
sudo bash docker/backup/backup.sh

# Teste de integridade (sem dados reais)
sudo bash docker/backup/backup.sh --test

# Arquivos gerados em $BACKUP_DIR (padrão: /opt/med_pront/backups/)
ls -lh /opt/med_pront/backups/
```

## Backup Automático (Cron)

```bash
# Adicionar ao crontab do root:
0 2 * * * bash /opt/med_pront/docker/backup/backup.sh >> /var/log/med_pront_backup.log 2>&1
```

## Restore

### 1. Listar backups disponíveis

```bash
ls -lhtr /opt/med_pront/backups/*.enc
```

### 2. Restore do banco (DRY RUN primeiro)

```bash
sudo bash docker/backup/restore.sh \
  --db /opt/med_pront/backups/db_20260504_020000.sql.gz.enc \
  --dry-run
```

### 3. Restore completo (DB + documentos)

```bash
sudo bash docker/backup/restore.sh \
  --db /opt/med_pront/backups/db_20260504_020000.sql.gz.enc \
  --docs /opt/med_pront/backups/docs_20260504_020000.tar.gz.enc
```

> **ATENÇÃO**: O restore apaga o banco atual. Confirme com `yes` quando solicitado.

## Variáveis de Ambiente Necessárias

```bash
BACKUP_ENCRYPTION_KEY=<sua-chave-segura>   # Obrigatório
BACKUP_DIR=/opt/med_pront/backups          # Padrão
BACKUP_RETENTION_DAYS=30                   # Padrão
BACKUP_S3_BUCKET=med-pront-backups         # Opcional
```

## Verificar Integridade de um Backup

```bash
openssl enc -aes-256-cbc -pbkdf2 -iter 100000 -d \
  -in /opt/med_pront/backups/db_XXXXXX.sql.gz.enc \
  -pass pass:"$BACKUP_ENCRYPTION_KEY" | gunzip -t \
  && echo "OK" || echo "CORROMPIDO"
```

## Disaster Recovery

1. Provisionar nova VPS (Debian 12, mesmas especificações)
2. Instalar Docker + Docker Compose
3. Clonar repositório
4. Copiar `.env` de backup seguro
5. `docker compose up -d` — esperar containers subirem
6. Executar restore com último backup válido
7. Executar `bash scripts/setup-openemr.sh` (reaplica configurações)
8. Verificar com `make health-check`

**RPO alvo**: 24h (1 backup diário)
**RTO alvo**: 2-4h (provisioning + restore manual)
