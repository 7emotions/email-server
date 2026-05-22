# 自建邮件服务器完整指南：Stalwart + 阿里云 + Caddy

> 在阿里云 ECS 上用 Docker 搭建 Stalwart 邮件服务器，通过阿里云邮件推送绕过 25 端口限制，实现收发邮件。

## 背景

阿里云 ECS 默认封锁出站 25 端口（SMTP），意味着服务器可以接收邮件，但无法直接向外部发送邮件。解决方案是通过**阿里云邮件推送（DirectMail）** 作为 SMTP 中继——邮件先提交到阿里云的 465 端口，再由阿里云代为投递。

本文使用 **Stalwart Mail Server**，一个用 Rust 编写的现代化邮件服务器，支持 JMAP/IMAP/SMTP，单容器部署，内存占用仅 ~300MB。

---

## 环境

| 项目 | 说明 |
|------|------|
| 服务器 | 阿里云 ECS，1.6 GB RAM，40 GB 磁盘 |
| 操作系统 | Ubuntu / Debian |
| 域名 | `<YOUR_DOMAIN>`（替换为你的域名） |
| 邮件服务器 | Stalwart v0.16（Docker） |
| 反向代理 | Caddy（已安装） |
| SMTP 中继 | 阿里云邮件推送 |

---

## 一、安装 Stalwart

### Docker Compose

`compose.yaml`：

```yaml
services:
  stalwart:
    image: ghcr.io/stalwartlabs/stalwart:v0.16
    container_name: stalwart
    command: ["--config", "/opt/stalwart/etc/config.json"]
    restart: unless-stopped
    network_mode: host
    volumes:
      - stalwart-data:/opt/stalwart
      - /etc/letsencrypt:/etc/letsencrypt:ro
    environment:
      - TZ=Asia/Shanghai
      - STALWART_RECOVERY_ADMIN=admin:yourTempPassword

volumes:
  stalwart-data:
    external: true
    name: email-server_stalwart-data
```

> **注意**：使用 `network_mode: host` 而非端口映射，能避免 Docker proxy 的 TLS 兼容性问题。

### 启动

```bash
docker compose up -d
```

首次启动时 Stalwart 进入 **bootstrap 模式**，在 8080 端口提供 setup wizard。

---

## 二、初始配置

### 1. 完成 Setup Wizard

浏览器打开 `http://<服务器IP>:8080/admin`。

首次启动时 Stalwart 进入 **bootstrap 模式**，日志会打印临时管理员密码。如果你设置了 `STALWART_RECOVERY_ADMIN=admin:yourTempPass`，则使用你指定的临时凭据登录。

Setup Wizard 最后一步会要求你创建**永久管理员账户**（用户名 + 密码），这个才是之后日常使用的凭据。临时密码在向导完成后自动失效。

Wizard 会引导你配置：
- **主机名**：`mail.<YOUR_DOMAIN>`
- **域名**：`<YOUR_DOMAIN>`
- **存储后端**：RocksDB（默认）
- **目录**：Internal Directory
- **TLS**：选择 ACME（Let's Encrypt）自动获取证书

完成向导后 Stalwart 重启进入正常模式。此时可以移除 `STALWART_RECOVERY_ADMIN` 环境变量，之后用永久管理员账户登录。

### 2. 创建邮箱账户

Admin 面板 → Management → Directory → Accounts → Create user：
- 邮箱：`lorenzo@<YOUR_DOMAIN>`
- 用户名：`lorenzo`
- 设置密码

---

## 三、DNS 记录配置

在域名 DNS 控制台添加以下记录：

```
# MX（邮件交换）
<YOUR_DOMAIN>  MX  10  mail.<YOUR_DOMAIN>

# SPF（发信身份验证）
<YOUR_DOMAIN>  TXT  v=spf1 mx include:spf1.dm.aliyun.com -all

# DKIM（从 Stalwart 管理面板获取）
v1-ed25519-20260521._domainkey.<YOUR_DOMAIN>  TXT  v=DKIM1; k=ed25519; h=sha256; p=...
v1-rsa-20260521._domainkey.<YOUR_DOMAIN>      TXT  v=DKIM1; k=rsa; h=sha256; p=...

# DMARC
_dmarc.<YOUR_DOMAIN>  TXT  v=DMARC1; p=reject; rua=mailto:postmaster@<YOUR_DOMAIN>

# 服务发现（可选）
_submissions._tcp.<YOUR_DOMAIN>  SRV  0 1 465 mail.<YOUR_DOMAIN>
_imaps._tcp.<YOUR_DOMAIN>        SRV  0 1 993 mail.<YOUR_DOMAIN>
```

DKIM 公钥从 Admin 面板 → Management → Domains → 点域名右边的 `...` → View DNS Records 获取。

---

## 四、SSL 证书

Stalwart 内置 ACME 支持，但如果你有 Caddy 或 certbot 管理的证书，可以挂载复用：

### 挂载 certbot 证书

```yaml
volumes:
  - /etc/letsencrypt:/etc/letsencrypt:ro
```

然后在 Admin 面板 → Settings → Server → TLS → Certificates 添加：

- Certificate: `%{file:/etc/letsencrypt/live/<YOUR_DOMAIN>/fullchain.pem}%`
- Private Key: `%{file:/etc/letsencrypt/live/<YOUR_DOMAIN>/privkey.pem}%`

> **权限问题**：确保 `chmod o+x /etc/letsencrypt/live /etc/letsencrypt/archive && chmod 644 /etc/letsencrypt/archive/<YOUR_DOMAIN>/privkey*.pem`，否则 Stalwart（UID 2000）无法读取私钥。

---

## 五、Caddy 反向代理

Caddy 代理 admin 面板（Stalwart 内部 8080 端口）：

```
mail.<YOUR_DOMAIN> {
    reverse_proxy localhost:8080 {
        header_up Host {host}
        header_up X-Real-IP {remote_host}
    }
    encode gzip zstd
}
```

---

## 六、配置阿里云 SMTP 中继

### 1. 开通阿里云邮件推送

登录 [阿里云邮件推送控制台](https://dm.console.aliyun.com)，开通服务。

### 2. 创建发信域名

新建域名 `<YOUR_DOMAIN>`，按提示配置 DNS 验证记录（SPF、MX 等）。验证通过后状态变为绿色。

### 3. 创建发信地址

新建发信地址 `lorenzo@<YOUR_DOMAIN>`，点击「设置 SMTP 密码」生成密码（**注意：这是独立于邮箱密码的 SMTP 密码**）。

### 4. 在 Stalwart 中配置 Relay

Admin 面板 → Settings → MTA → Outbound：

#### Routes → Create route

- **类型**：Relay Host
- Address: `smtpdm.aliyun.com`
- Port: `465`
- Protocol: SMTP
- **Implicit TLS**: ✅ 开启
- **Username**: `lorenzo@<YOUR_DOMAIN>`
- **Secret**: `Secret value` → 填阿里云 SMTP 密码
- **Name**: `aliyun`

#### TLS Strategies

点 `default` → Security Requirements：
- **DANE**: Disabled
- **MTA-STS**: Disabled
- **STARTTLS**: Optional

#### Strategy → Routing

| | Condition | Result |
|---|---|---|
| IF | `is_local_domain(rcpt_domain)` | `'local'` |
| ELSE | | `'aliyun'` |

#### Strategy → Scheduling

| | Condition | Result |
|---|---|---|
| IF | `is_local_domain(rcpt_domain)` | `'local'` |
| IF | `source == 'dsn'` | `'dsn'` |
| IF | `source == 'report'` | `'report'` |
| ELSE | | `'remote'` |

---

## 七、客户端配置

| 协议 | 服务器 | 端口 | 加密 |
|------|--------|------|------|
| SMTP 发信 | `mail.<YOUR_DOMAIN>` | 465 | SSL/TLS |
| IMAP 收信 | `mail.<YOUR_DOMAIN>` | 993 | SSL/TLS |
| POP3 收信 | `mail.<YOUR_DOMAIN>` | 995 | SSL/TLS |

**用户名**：完整邮箱地址（如 `lorenzo@<YOUR_DOMAIN>`）
**密码**：Stalwart 中设置的邮箱密码

---

## 八、测试

### 发送测试邮件

```bash
# 通过自有服务器提交
swaks --to 你的测试邮箱@qq.com \
  --from lorenzo@<YOUR_DOMAIN> \
  --server mail.<YOUR_DOMAIN> --port 465 --tls \
  --auth LOGIN --auth-user lorenzo@<YOUR_DOMAIN> --auth-password 你的密码
```

### 在线评分

向 [mail-tester.com](https://mail-tester.com) 发送一封邮件，查看 SPF/DKIM/DMARC 评分。

---

## 常见问题

### 1. 收不到邮件

- 检查 MX 记录是否指向 `mail.<YOUR_DOMAIN>`
- 确保阿里云安全组开放端口 25
- 检查 Routing Strategy 的 IF 条件是 `is_local_domain(rcpt_domain)`

### 2. 发不出邮件（550 Mailbox not found / 535 Auth failure）

- 确认阿里云 SMTP 密码与邮箱密码不同
- 阿里云邮件推送的「发信地址」需设置独立的 SMTP 密码
- 确认 Routes 中 `aliyun` 的 Username 和 Secret 正确

### 3. Admin 面板 502

- Caddy 代理的目标端口是否正确（`localhost:8080` 或 `localhost:443`）
- 检查 `network_mode: host` 是否生效

### 4. TLS 证书相关问题

- certbot 证书文件权限：`chmod o+x /etc/letsencrypt/live`
- Stalwart 证书路径格式：`%{file:/path/to/cert.pem}%`

---

## 总结

通过 Stalwart + 阿里云邮件推送的组合，你在阿里云 ECS 上拥有了一套功能完整的邮件服务器：

- ✅ 收发邮件（SMTP + IMAP）
- ✅ Let's Encrypt SSL/TLS 加密
- ✅ SPF / DKIM / DMARC 全配置
- ✅ 阿里云邮件中继绕过 25 端口限制
- ✅ 网页管理面板
- ✅ 仅需 ~300MB 内存

之后可以考虑启用 ClamAV 反病毒、Sieve 邮件过滤、多域名支持等高级功能。

---

*本文写于 2026 年 5 月，基于 Stalwart v0.16.6。*
