# 自建邮件服务器完整指南：Stalwart + 阿里云 + Caddy

> 在阿里云 ECS 上用 Docker 搭建 Stalwart 邮件服务器，通过阿里云邮件推送绕过 25 端口限制，实现收发邮件。

## 背景

阿里云 ECS 默认封锁出站 25 端口（SMTP），意味着服务器可以接收邮件，但无法直接向外部投递。解决方案是通过**阿里云邮件推送（DirectMail）**作为 SMTP 中继——邮件先提交到阿里云的 465 端口，再由阿里云代为投递到对方服务器。

本文使用 **Stalwart Mail Server**，一个用 Rust 编写的现代化邮件服务器，支持 JMAP/IMAP/SMTP，单容器部署约 300MB 内存。

---

## 环境

| 项目 | 说明 |
|------|------|
| 服务器 | 阿里云 ECS，1.6 GB RAM，40 GB 磁盘 |
| 操作系统 | Ubuntu / Debian |
| 域名 | `<YOUR_DOMAIN>`（替换为你的域名） |
| 邮件服务器 | Stalwart v0.16（Docker） |
| 反向代理 | Caddy |
| SMTP 中继 | 阿里云邮件推送 |

> **前提**：阿里云安全组需开放端口 25、465、587、993。Caddy 占用 80/443。

---

## 一、安装 Stalwart

### 创建数据卷

```bash
docker volume create email-server_stalwart-data
```

### Docker Compose

`compose.yaml`：

```yaml
services:
  stalwart:
    image: ghcr.io/stalwartlabs/stalwart:v0.16
    container_name: stalwart
    restart: unless-stopped
    network_mode: host
    volumes:
      - stalwart-data:/opt/stalwart
      - /etc/letsencrypt:/etc/letsencrypt:ro
    environment:
      - TZ=Asia/Shanghai
      # 首次启动时用临时密码进入 setup wizard
      - STALWART_RECOVERY_ADMIN=admin:yourTempPassword

volumes:
  stalwart-data:
    external: true
    name: email-server_stalwart-data
```

> **为什么用 `network_mode: host`**：Docker 的端口映射（`docker-proxy`）在转发 HTTP 到 Stalwart 时存在 TLS 兼容性问题，导致连接被静默关闭。`network_mode: host` 让容器直接使用宿主机网络栈，避免这个问题。端口由 Stalwart 自行绑定。

### 启动

```bash
docker compose up -d
```

首次启动时 Stalwart 进入 **bootstrap 模式**，在 8080 端口提供 setup wizard。

---

## 二、初始配置

### 1. 完成 Setup Wizard

浏览器打开 `http://<服务器IP>:8080/admin`，用上面设置的临时密码登录（用户名 `admin`）。

Setup Wizard 最后一步会要求你创建**永久管理员账户**——这才是日常使用的凭据，临时密码在向导完成后自动失效。

Wizard 配置项参考：
- **主机名**：`mail.<YOUR_DOMAIN>`
- **域名**：`<YOUR_DOMAIN>`
- **存储后端**：RocksDB（默认）
- **目录**：Internal Directory
- **TLS**：先跳过，后续挂载 certbot 证书

完成向导后 Stalwart 重启进入正常模式，`config.json` 自动生成。

> **安全建议**：向导完成后从 `compose.yaml` 中移除 `STALWART_RECOVERY_ADMIN` 并重启容器。

### 2. 创建邮箱账户

Admin 面板 → Management → Directory → Accounts → Create user：
- 邮箱：`hello@<YOUR_DOMAIN>`
- 用户名：`hello`
- 设置密码

---

## 三、DNS 记录配置

在域名 DNS 控制台添加以下记录（将 `<YOUR_DOMAIN>` 替换为你的域名）：

```
# MX（收信必须）
<YOUR_DOMAIN>  MX  10  mail.<YOUR_DOMAIN>

# SPF（发信身份验证，注意 include 阿里云 SPF）
<YOUR_DOMAIN>  TXT  v=spf1 mx include:spf1.dm.aliyun.com -all

# DKIM（从 Stalwart 管理面板获取，注意 DKIM 选择器前缀可能不同）
<selector1>._domainkey.<YOUR_DOMAIN>  TXT  v=DKIM1; k=rsa; h=sha256; p=<公钥>
<selector2>._domainkey.<YOUR_DOMAIN>  TXT  v=DKIM1; k=ed25519; h=sha256; p=<公钥>

# DMARC（可选，建议先用 p=none 观察再改为 reject）
_dmarc.<YOUR_DOMAIN>  TXT  v=DMARC1; p=none; rua=mailto:postmaster@<YOUR_DOMAIN>

# 服务发现（可选，方便客户端自动配置）
_submissions._tcp.<YOUR_DOMAIN>  SRV  0 1 465 mail.<YOUR_DOMAIN>
_imaps._tcp.<YOUR_DOMAIN>        SRV  0 1 993 mail.<YOUR_DOMAIN>
```

DKIM 公钥获取路径：Admin 面板 → Management → Domains → 点域名右边的 `...` → View DNS Records。

> **注意**：阿里云邮件推送的域名验证会要求添加 SPF 和 MX 记录。如果阿里云的 MX 记录覆盖了你的 MX，可以删除阿里云的 MX 记录（不影响中继发信功能），或者为阿里云单独使用一个子域名（如 `dm.<YOUR_DOMAIN>`）。

---

## 四、SSL 证书

Stalwart 支持通过 ACME 自动获取证书。如果你已有 certbot 管理的证书，可以挂载复用：

### 挂载 certbot 证书

compose.yaml 中已挂载 `/etc/letsencrypt:/etc/letsencrypt:ro`。然后在 Admin 面板 → Settings → TLS → Certificates → Add Certificate：

- ID: 任意名称（如 `main`）
- Certificate: `%{file:/etc/letsencrypt/live/<YOUR_DOMAIN>/fullchain.pem}%`
- Private Key: `%{file:/etc/letsencrypt/live/<YOUR_DOMAIN>/privkey.pem}%`

### 修复证书权限

Let's Encrypt 的 live 目录默认仅 root 可遍历，私钥仅 root 可读。Stalwart 容器以 UID 2000 运行，需要额外授权：

```bash
chmod o+x /etc/letsencrypt/live /etc/letsencrypt/archive
chmod 644 /etc/letsencrypt/archive/<YOUR_DOMAIN>/privkey*.pem
```

> 证书续期后需重启 Stalwart 以加载新证书。可配合 certbot 的 `--deploy-hook` 自动重启。

---

## 五、Caddy 反向代理

以下 Caddy 配置通过 `https://mail.<YOUR_DOMAIN>` 访问 admin 面板：

```
mail.<YOUR_DOMAIN> {
    reverse_proxy localhost:8080 {
        header_up Host {host}
        header_up X-Real-IP {remote_host}
    }
    encode gzip zstd
}
```

> `network_mode: host` 下 Stalwart 的 8080 端口直接暴露在宿主机，Caddy 通过 `localhost:8080` 即可访问。

---

## 六、配置阿里云 SMTP 中继

### 1. 开通服务

登录 [阿里云邮件推送控制台](https://dm.console.aliyun.com)，开通 DirectMail 服务。

### 2. 创建发信域名

新建域名 `<YOUR_DOMAIN>`，按提示配置 DNS 验证记录。验证通过后状态变为绿色。

> **冲突提醒**：阿里云的域名验证会自动添加一条 MX 记录指向 `mx01.dm.aliyun.com`。如果这与你自己的 MX 记录冲突（导致收不到邮件），可删除阿里云的 MX 记录，或改用子域名（如 `dm.<YOUR_DOMAIN>`）作为发信域名。

### 3. 创建发信地址

新建发信地址 `hello@<YOUR_DOMAIN>`，点击「设置 SMTP 密码」生成独立密码。

> **重要**：这是阿里云邮件推送专用的 SMTP 密码，与 Stalwart 中的邮箱登录密码无关。

### 4. 在 Stalwart 中配置 Relay

Admin 面板 → Settings → MTA → Outbound：

#### a. TLS Strategies

点 `default` → Security Requirements：
- DANE: `Disabled`
- MTA-STS: `Disabled`
- STARTTLS: `Optional`

#### b. Routes → Create route

- 类型: `Relay Host`
- Address: `smtpdm.aliyun.com`
- Port: `465`
- Implicit TLS: ✅ 开启
- Username: `hello@<YOUR_DOMAIN>`
- Secret: `Secret value` → 填阿里云 SMTP 密码
- Name: `aliyun`

#### c. Strategy → Routing

| | Condition | Result |
|---|---|---|
| IF | `is_local_domain(rcpt_domain)` | `'local'` |
| ELSE | | `'aliyun'` |

含义：收件域是你的域名时本地投递，其余全部通过阿里云中继外发。

#### d. Strategy → Scheduling

| | Condition | Result |
|---|---|---|
| IF | `is_local_domain(rcpt_domain)` | `'local'` |
| IF | `source == 'dsn'` | `'dsn'` |
| IF | `source == 'report'` | `'report'` |
| ELSE | | `'remote'` |

> 除 Routing 和 Scheduling 外，Connection 和 TLS 子项保持默认即可。

---

## 七、客户端配置

| 协议 | 服务器 | 端口 | 加密 | 说明 |
|------|--------|------|------|------|
| SMTP | `mail.<YOUR_DOMAIN>` | 465 | SSL/TLS | 发信 |
| IMAP | `mail.<YOUR_DOMAIN>` | 993 | SSL/TLS | 收信（推荐） |
| POP3 | `mail.<YOUR_DOMAIN>` | 995 | SSL/TLS | 收信（备选） |

- **用户名**：完整邮箱地址（如 `hello@<YOUR_DOMAIN>`）
- **密码**：Stalwart 中设置的邮箱密码（非阿里云 SMTP 密码）
- **认证**：需勾选「需要登录认证」

> QQ 邮箱、Apple Mail 等客户端对自建邮局兼容性不一，若自动配置失败请选手动配置。PC 端推荐 Thunderbird，Android 推荐 FairEmail。

---

## 八、测试

### 命令行发送

```bash
# 安装 swaks（一款 SMTP 测试工具）
apt install -y swaks

# 发送测试邮件
swaks --to your-test@qq.com \
  --from hello@<YOUR_DOMAIN> \
  --server mail.<YOUR_DOMAIN> --port 465 --tls \
  --auth LOGIN --auth-user hello@<YOUR_DOMAIN> --auth-password 你的密码
```

### 收信测试

用外部邮箱（如 QQ、Gmail）向 `hello@<YOUR_DOMAIN>` 发一封邮件，检查是否出现在收件箱。

### 在线评分

向 [mail-tester.com](https://mail-tester.com) 发信，查看 SPF/DKIM/DMARC 综合评分。

---

## 常见问题

### 收不到邮件

- 检查 MX 记录是否指向 `mail.<YOUR_DOMAIN>`（`dig MX <YOUR_DOMAIN>`）
- 阿里云安全组是否开放 TCP 25 入站
- Routing Strategy 的 IF 条件是否为 `is_local_domain(rcpt_domain)`

### 发不出邮件

- 阿里云邮件推送的 SMTP 密码与 Stalwart 邮箱密码是两码事，不要混淆
- 确认 Routes → `aliyun` 中的 Username 和 Secret 与阿里云控制台一致
- 阿里云发信域名状态是否为「已验证」

### Admin 面板打不开 / 502

- 检查 Stalwart 容器是否在运行：`docker ps | grep stalwart`
- 确认 `network_mode: host` 已生效
- Caddy 代理目标应为 `localhost:8080`

### 证书问题

- `Permission denied`：执行上文「修复证书权限」中的 chmod 命令
- 证书路径格式必须为 `%{file:/绝对路径}%`

---

## 总结

Stalwart + 阿里云邮件推送，在封锁 25 端口的云服务器上实现完整邮件收发：

- ✅ SMTP / IMAP 收发邮件
- ✅ Let's Encrypt 加密传输
- ✅ SPF / DKIM / DMARC 防伪造
- ✅ 阿里云中继外发
- ✅ 网页管理面板
- ✅ 约 300MB 内存，单容器运行

进一步可配置：Sieve 邮件过滤、ClamAV 反病毒、多域名、自动备份等。

---

*本文基于 Stalwart v0.16.6，2026 年 5 月。*
