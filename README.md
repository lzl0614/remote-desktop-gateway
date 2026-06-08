# Remote Desktop Gateway

一个自托管的浏览器远程桌面网关工程。

本工程使用 `Apache Guacamole + guacd + PostgreSQL + Caddy` 搭建网页远程桌面入口。被控 Windows 设备通过 SSH 反向隧道主动接入云服务器，公网不需要开放 `3389` RDP 端口。

## 适合什么场景

- 想通过浏览器远程控制家里、办公室或实验室的 Windows 电脑
- 不想直接暴露公网 RDP `3389`
- 不想给控制端安装远程桌面客户端
- 不想搭完整 VPN，只需要少量设备远控入口
- 有一台 Linux 云服务器，可以运行 Docker 和 SSH

## 最终效果

部署完成后，你会得到两个入口：

```text
http://<server-ip>/gateway/      自定义入口页
http://<server-ip>/guacamole/    Guacamole 登录页
```

如果使用 Caddy HTTPS，也可以访问：

```text
https://<server-ip>/
https://<your-domain>/
```

登录 Guacamole 后，选择已经创建好的连接，例如 `PC-1`，即可通过浏览器进入 Windows 桌面。

## 架构

```text
Browser
  |
  | HTTP/HTTPS
  v
Nginx / Caddy
  |
  | /guacamole/
  v
Apache Guacamole
  |
  v
guacd
  |
  | 127.0.0.1:13389
  v
SSH reverse tunnel
  |
  v
Windows RDP 127.0.0.1:3389
```

核心点：

- Guacamole Web 只绑定到服务器本机 `127.0.0.1:8081`
- Windows 的 RDP 不暴露公网
- 服务器上的 `13389`、`13390` 等反向隧道端口只绑定 `127.0.0.1`
- 公网只暴露 SSH、HTTP、HTTPS

## 目录结构

```text
remote-desktop-gateway/
├── .env.example
├── .gitignore
├── README.md
├── docker-compose.yml
├── caddy/
│   └── Caddyfile
├── nginx/
│   └── guacamole.conf.example
└── portal/
    ├── index.html
    └── styles.css
```

文件说明：

- `.env.example`：Docker Compose 环境变量模板
- `docker-compose.yml`：Guacamole、guacd、PostgreSQL、Caddy 服务编排
- `caddy/Caddyfile`：Caddy HTTPS 和静态入口页配置
- `nginx/guacamole.conf.example`：Nginx `/guacamole/` 反向代理示例
- `portal/index.html`：自定义入口页
- `portal/styles.css`：入口页样式

## 前置条件

云服务器：

- Linux 服务器，推荐 Ubuntu 22.04 或 24.04
- 已安装 Docker
- 已安装 Docker Compose 插件
- 已安装 OpenSSH Server
- 可以开放安全组端口

本地 Windows 设备：

- Windows 专业版、企业版或其他支持 RDP 的版本
- 已开启远程桌面
- 已允许当前 Windows 用户远程登录
- 可以主动 SSH 连接云服务器

控制端：

- 任意现代浏览器
- 不需要安装远程桌面客户端

## 端口规划

公网建议只开放：

```text
22/tcp   SSH，用于服务器运维和 Windows 反向隧道
80/tcp   HTTP，可由 Nginx 提供 /gateway/ 和 /guacamole/
443/tcp  HTTPS，可由 Caddy 提供入口
```

不要对公网开放：

```text
3389/tcp   Windows RDP
13389/tcp  第一台设备隧道端口
13390/tcp  第二台设备隧道端口
13391/tcp  更多设备隧道端口
```

服务器本机内部使用：

```text
127.0.0.1:8081   Guacamole Web
127.0.0.1:13389  PC-1 反向隧道端口
```

## 快速部署

### 1. 克隆仓库

```bash
git clone https://github.com/lzl0614/remote-desktop-gateway.git
cd remote-desktop-gateway
```

### 2. 准备环境变量

```bash
cp .env.example .env
```

编辑 `.env`：

```env
GUAC_VERSION=latest

POSTGRES_DB=guacamole_db
POSTGRES_USER=guacamole_user
POSTGRES_PASSWORD=change_this_postgres_password

GUACD_HOSTNAME=host.docker.internal
GUACD_PORT=4822

GUAC_WEB_BIND=127.0.0.1:8081
```

必须修改：

- `POSTGRES_PASSWORD`

生产环境建议：

- 不要长期使用 `latest`
- 将 `GUAC_VERSION` 固定为明确版本号

### 3. 生成 Guacamole 数据库初始化脚本

```bash
mkdir -p initdb postgres backups
docker run --rm guacamole/guacamole:${GUAC_VERSION:-latest} \
  /opt/guacamole/bin/initdb.sh --postgresql > initdb/initdb.sql
```

注意：

- 这一步只在第一次部署前执行
- PostgreSQL 初始化完成后，不会重复执行 `initdb/initdb.sql`
- 如果需要重新初始化数据库，需要先备份并删除 `postgres/` 数据目录

### 4. 启动服务

```bash
docker compose up -d
```

检查容器：

```bash
docker compose ps
```

正常情况下会看到：

```text
guac-postgres
guacd
guacamole
guac-caddy
```

### 5. 验证本机 Guacamole

在服务器上执行：

```bash
curl -I http://127.0.0.1:8081/guacamole/
```

如果返回 `200`，说明 Guacamole Web 已经启动。

## 使用 Caddy 访问

仓库里的 `caddy/Caddyfile` 默认监听 `:443`：

```caddyfile
:443 {
    tls internal

    @guacamole path /guacamole /guacamole/*
    handle @guacamole {
        reverse_proxy guacamole:8080
    }

    root * /usr/share/caddy
    file_server
}
```

默认配置会：

- 访问 `/` 时显示 `portal/` 自定义入口页
- 访问 `/guacamole/` 时反向代理到 Guacamole
- 使用 Caddy 内部证书，因此浏览器可能提示证书不受信任

如果你有域名，建议改成：

```caddyfile
rdp.example.com {
    @guacamole path /guacamole /guacamole/*
    handle @guacamole {
        reverse_proxy guacamole:8080
    }

    root * /usr/share/caddy
    file_server
}
```

然后把域名 DNS A 记录指向服务器 IP。

## 使用 Nginx 提供公网 HTTP 入口

如果服务器已经有 Nginx，可以使用 `nginx/guacamole.conf.example` 中的配置。

关键片段：

```nginx
location = /guacamole {
    return 302 /guacamole/;
}

location ^~ /guacamole/ {
    proxy_pass http://127.0.0.1:8081;
    proxy_buffering off;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
}
```

这里必须使用：

```nginx
location ^~ /guacamole/
```

否则 `/guacamole/*.css` 和 `/guacamole/*.js` 可能会被静态资源规则拦截，导致登录页只剩输入框边线、样式和脚本全部丢失。

应用配置：

```bash
sudo nginx -t
sudo systemctl reload nginx
```

验证：

```bash
curl -I http://<server-ip>/guacamole/
curl -I http://<server-ip>/guacamole/angular.min.js
```

两个请求都应返回 `200`。

## 发布自定义入口页到 Nginx

如果你希望通过 Nginx 暴露入口页：

```bash
sudo mkdir -p /var/www/html/gateway
sudo cp portal/index.html /var/www/html/gateway/index.html
sudo cp portal/styles.css /var/www/html/gateway/styles.css
```

然后访问：

```text
http://<server-ip>/gateway/
```

如果你的站点根目录不是 `/var/www/html`，请替换为实际目录。

## 创建 SSH 隧道用户

建议每台 Windows 设备使用一个独立 SSH 用户。

以第一台设备 `PC-1` 为例：

```bash
sudo adduser --disabled-password --gecos "" tunnel-pc1
sudo mkdir -p /home/tunnel-pc1/.ssh
sudo nano /home/tunnel-pc1/.ssh/authorized_keys
sudo chown -R tunnel-pc1:tunnel-pc1 /home/tunnel-pc1/.ssh
sudo chmod 700 /home/tunnel-pc1/.ssh
sudo chmod 600 /home/tunnel-pc1/.ssh/authorized_keys
```

`authorized_keys` 中放入 Windows 设备生成的 SSH 公钥。

建议限制该用户不能交互登录，只用于端口转发。可以在 `authorized_keys` 单行公钥前追加限制参数，例如：

```text
no-pty,no-X11-forwarding,no-agent-forwarding ssh-ed25519 AAAA... pc1
```

是否进一步限制命令和来源 IP，取决于你的运维策略。

## Windows 设备接入

### 1. 开启 Windows 远程桌面

在 Windows 中开启：

```text
设置 -> 系统 -> 远程桌面 -> 启用远程桌面
```

确认当前 Windows 用户允许远程登录。

### 2. 生成 SSH key

在 Windows PowerShell 中执行：

```powershell
ssh-keygen -t ed25519 -f $env:USERPROFILE\.ssh\rdp_tunnel_pc1
```

把生成的 `.pub` 公钥内容加入服务器 `tunnel-pc1` 用户的 `authorized_keys`。

### 3. 建立反向隧道

在 Windows PowerShell 中执行：

```powershell
ssh -N `
  -i $env:USERPROFILE\.ssh\rdp_tunnel_pc1 `
  -R 127.0.0.1:13389:127.0.0.1:3389 `
  tunnel-pc1@<server-ip>
```

保持这个窗口运行。

如果需要长期运行，建议把它做成 Windows 计划任务或服务。

### 4. 验证服务器隧道端口

在服务器上执行：

```bash
ss -lntp | grep 13389
```

应看到 `127.0.0.1:13389` 正在监听。

## Guacamole 中添加 Windows 连接

登录 Guacamole 后添加连接：

```text
Name: PC-1
Protocol: RDP
Hostname: 127.0.0.1
Port: 13389
Security mode: NLA
Ignore server certificate: true
```

连接时弹出的凭据填写 Windows 本机账号：

```text
用户名：Windows 登录用户名
密码：Windows 登录密码
域：通常留空
```

注意：

- 这里不是 Guacamole 登录账号
- 如果 Windows 使用微软账号登录，用户名通常填写微软邮箱
- 如果 Windows 使用本地账号，用户名填写本地账户名

## Guacamole 默认账号

Guacamole 默认账号通常是：

```text
guacadmin / guacadmin
```

首次登录后必须立即：

- 修改默认管理员密码
- 创建自己的管理员账号
- 禁用或删除默认 `guacadmin`

不要把真实 Guacamole 密码写入仓库。

## 多设备端口规划

建议按设备递增分配：

```text
PC-1 -> 127.0.0.1:13389
PC-2 -> 127.0.0.1:13390
PC-3 -> 127.0.0.1:13391
PC-4 -> 127.0.0.1:13392
PC-5 -> 127.0.0.1:13393
PC-6 -> 127.0.0.1:13394
```

这些端口都只应绑定 `127.0.0.1`，不要开放到公网。

## 常用命令

查看容器：

```bash
docker compose ps
```

查看日志：

```bash
docker compose logs -f
```

重启服务：

```bash
docker compose restart
```

停止服务：

```bash
docker compose down
```

更新镜像：

```bash
docker compose pull
docker compose up -d
```

备份数据库：

```bash
docker compose exec -T postgres \
  pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB" > backups/guacamole-$(date +%Y%m%d%H%M%S).sql
```

## 排障

### 登录页样式缺失，只显示输入框边线

检查资源：

```bash
curl -I http://<server-ip>/guacamole/1.guacamole.c2fc19251fc606ad2140.css
curl -I http://<server-ip>/guacamole/angular.min.js
```

如果返回 `404`，检查 Nginx 配置是否使用：

```nginx
location ^~ /guacamole/ {
    proxy_pass http://127.0.0.1:8081;
}
```

### Guacamole 页面打不开

检查：

```bash
docker compose ps
curl -I http://127.0.0.1:8081/guacamole/
docker compose logs --tail=100 guacamole
```

### 登录后没有连接

需要在 Guacamole 后台手动创建 RDP 连接，或者检查连接权限是否授予当前用户。

### 连接 PC 失败

检查：

- Windows 是否启用远程桌面
- Windows 防火墙是否允许 RDP
- Windows 用户是否有远程登录权限
- SSH 反向隧道是否仍在运行
- 服务器是否监听 `127.0.0.1:13389`
- Guacamole 连接端口是否填写正确

### RDP 认证失败

检查：

- Windows 用户名是否正确
- Windows 密码是否正确
- 域是否应该留空
- 是否使用微软账号邮箱作为用户名
- Windows 是否允许该用户远程登录

## 安全建议

- 不要开放公网 `3389`
- 不要开放公网 `13389`、`13390` 等隧道端口
- 不要提交 `.env`
- 不要提交 SSH 私钥
- 不要提交 PostgreSQL 数据目录
- 不要长期使用 `guacadmin / guacadmin`
- 给 Guacamole 管理员设置强密码
- SSH 建议使用密钥登录
- SSH 建议限制来源 IP
- 有条件时为 Guacamole 开启多因素认证
- 生产环境建议使用独立域名和正式 HTTPS 证书

## 当前已验证状态

本工程已在一台云服务器上完成验证：

- `guacamole` 容器运行正常
- `guacd` 容器运行正常
- `guac-postgres` 容器运行正常
- `guac-caddy` 容器运行正常
- `/gateway/` 自定义入口页可访问
- `/guacamole/` 登录页可访问
- `/guacamole/` 下 CSS 和 JS 资源返回 `200`
- 第一台 Windows 设备可通过 `127.0.0.1:13389` 反向隧道接入

## 不包含什么

本仓库不包含：

- Guacamole 官方源码
- guacd 官方源码
- PostgreSQL 数据目录
- 真实 `.env`
- SSH 私钥
- Windows 登录密码
- 云服务器连接密码

后端能力来自 Docker 镜像：

- `guacamole/guacamole`
- `guacamole/guacd`
- `postgres:16`
- `caddy:2`

## 许可证

本仓库保留 GitHub 仓库中的 `LICENSE` 文件。
