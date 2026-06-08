# Remote Desktop Gateway

一个自托管的浏览器远程桌面网关工程。

本工程基于 `Apache Guacamole` 搭建网页远程桌面入口，让用户可以通过浏览器访问远程 Windows 桌面。Windows 设备通过 SSH 反向隧道接入云服务器，公网不需要开放 `3389` RDP 端口。

## 项目作用

- 提供浏览器访问的远程桌面入口
- 通过 Guacamole 管理 RDP 连接
- 通过 `guacd` 代理远程桌面协议
- 使用 PostgreSQL 保存 Guacamole 配置数据
- 使用 Caddy 提供 HTTPS 入口和静态入口页
- 支持将 Windows 设备通过 SSH 反向隧道接入云服务器

## 当前架构

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

当前部署中：

- `guacamole`、`guacd`、`postgres`、`caddy` 通过 Docker Compose 运行
- Guacamole Web 绑定在服务器本机 `127.0.0.1:8081`
- 公网 HTTP 稳定入口由现有 Nginx 提供
- 公网 HTTPS 入口由 Caddy 提供
- 反向隧道端口只绑定服务器本机，不对公网开放

## 目录结构

```text
remote-desktop-gateway/
├── .env.example
├── .gitignore
├── README.md
├── docker-compose.yml
├── caddy/
│   └── Caddyfile
└── portal/
    ├── index.html
    └── styles.css
```

说明：

- `.env.example`：环境变量模板，部署时复制为 `.env`
- `docker-compose.yml`：Guacamole、guacd、PostgreSQL、Caddy 编排文件
- `caddy/Caddyfile`：Caddy HTTPS 和反向代理配置
- `portal/index.html`：自定义浏览器入口页
- `portal/styles.css`：入口页样式

## 服务组件

### PostgreSQL

用于保存 Guacamole 的用户、连接、权限等配置。

容器名：

```text
guac-postgres
```

### guacd

Guacamole 的协议代理服务，负责连接 RDP 等远程桌面协议。

容器名：

```text
guacd
```

### Guacamole

浏览器远程桌面 Web 服务。

容器名：

```text
guacamole
```

### Caddy

用于提供 HTTPS 访问和自定义入口页。

容器名：

```text
guac-caddy
```

## 端口规划

公网建议只开放：

```text
22/tcp   SSH，用于建立反向隧道和服务器运维
80/tcp   HTTP，由 Nginx 提供稳定入口
443/tcp  HTTPS，由 Caddy 提供入口
```

不要对公网开放：

```text
3389/tcp
13389/tcp
13390/tcp
13391/tcp
```

内部使用：

```text
127.0.0.1:8081   Guacamole Web
127.0.0.1:13389  第一台 Windows 设备 PC-1 的反向隧道端口
```

## 环境变量

部署前复制环境变量模板：

```bash
cp .env.example .env
```

然后修改 `.env`：

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

建议固定版本：

- 将 `GUAC_VERSION=latest` 改为明确版本号，便于后续升级和回滚

## 初始化数据库

首次部署前需要生成 Guacamole 的 PostgreSQL 初始化脚本。

示例：

```bash
mkdir -p initdb postgres backups
docker run --rm guacamole/guacamole:${GUAC_VERSION} \
  /opt/guacamole/bin/initdb.sh --postgresql > initdb/initdb.sql
```

注意：

- `initdb/initdb.sql` 只需要首次初始化时使用
- 如果 PostgreSQL 数据目录已经初始化过，后续修改 `initdb` 不会重新执行
- 不要把真实数据库数据目录提交到 Git

## 启动服务

```bash
docker compose up -d
```

查看状态：

```bash
docker compose ps
```

查看日志：

```bash
docker compose logs -f guacamole guacd postgres caddy
```

## 访问入口

当前实际部署中，稳定公网入口是：

```text
http://<server-ip>/gateway/
```

Guacamole 登录入口是：

```text
http://<server-ip>/guacamole/
```

Caddy HTTPS 入口是：

```text
https://<server-ip>/
```

说明：

- `/gateway/` 是自定义入口页
- `/guacamole/` 是实际 Guacamole 登录页
- 账号认证仍由 Guacamole 本体处理

## Nginx 反向代理要点

如果使用现有 Nginx 暴露 `/guacamole/`，需要确保 Guacamole 路径优先走反向代理，避免 CSS/JS 被静态资源规则拦截。

关键配置：

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

这里必须使用 `location ^~ /guacamole/`。

如果写成普通 `location /guacamole/`，后面的静态资源正则可能会抢先处理 `/guacamole/*.css` 和 `/guacamole/*.js`，导致登录页样式和脚本返回 `404`。

## Windows 设备接入方式

每台 Windows 设备通过 SSH 反向隧道连接云服务器。

第一台设备示例：

```text
服务器本机：127.0.0.1:13389
Windows RDP：127.0.0.1:3389
Guacamole 连接名：PC-1
```

SSH 反向隧道示例：

```bash
ssh -N -R 127.0.0.1:13389:127.0.0.1:3389 tunnel-pc1@<server-ip>
```

Guacamole 中添加 RDP 连接：

```text
Name: PC-1
Protocol: RDP
Hostname: 127.0.0.1
Port: 13389
Security mode: NLA
```

连接时需要填写 Windows 本机账号密码：

- 用户名：Windows 登录用户名
- 密码：Windows 登录密码
- 域：一般留空

## 登录账号说明

本工程不在仓库中保存真实账号密码。

Guacamole 默认账号通常是：

```text
guacadmin / guacadmin
```

首次部署后必须立即执行：

- 修改默认管理员密码
- 创建自己的管理员账号
- 禁用或删除默认账号

Windows 远程桌面连接弹出的账号密码，不是 Guacamole 账号，而是被控 Windows 设备的系统登录账号密码。

## 安全注意事项

- 不要开放公网 `3389`
- 不要开放公网 `13389`、`13390` 等反向隧道端口
- 不要提交 `.env`
- 不要提交 SSH 私钥
- 不要提交 PostgreSQL 数据目录
- 不要长期使用 `guacadmin / guacadmin`
- 建议 SSH 使用密钥登录
- 建议限制 SSH 来源 IP
- 建议为 Guacamole 开启更强认证策略
- 建议使用独立域名和正式 HTTPS 证书

## 常用排障

### 登录页只有输入框边线，样式缺失

检查 CSS/JS 是否返回 `404`：

```bash
curl -I http://<server-ip>/guacamole/app.css
curl -I http://<server-ip>/guacamole/angular.min.js
```

如果返回 `404`，通常是 Nginx location 优先级问题。

确认 `/guacamole/` 代理规则为：

```nginx
location ^~ /guacamole/ {
    proxy_pass http://127.0.0.1:8081;
}
```

### Guacamole 能打开，但连接 PC 失败

检查：

- Windows 是否启用远程桌面
- Windows 防火墙是否允许 RDP
- SSH 反向隧道是否仍在运行
- 服务器本机是否能连接 `127.0.0.1:13389`
- Guacamole 连接端口是否填写为 `13389`

### 查看容器状态

```bash
docker compose ps
```

### 重启服务

```bash
docker compose restart
```

### 重新加载 Nginx

```bash
sudo nginx -t
sudo systemctl reload nginx
```

## 已知当前部署状态

当前工程已经在云服务器上验证过：

- `guacamole` 容器运行正常
- `guacd` 容器运行正常
- `guac-postgres` 容器运行正常
- `guac-caddy` 容器运行正常
- `http://124.220.228.218/gateway/` 返回 `200`
- `http://124.220.228.218/guacamole/` 返回 `200`
- `/guacamole/` 下核心 CSS 和 JS 资源返回 `200`

## 许可证

本仓库保留 GitHub 仓库中的原始 `LICENSE` 文件。
