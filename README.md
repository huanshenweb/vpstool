# VPS Traffic Consumer

AWS VPS 流量消耗工具，用于按需消耗服务器带宽流量。支持精确控制流量额度、消耗时间和速率。

## 特性

- **精确控制** — 设定目标流量 (GB)，到量自动停止
- **时间规划** — 指定消耗时长，自动匀速分配
- **速率限制** — 手动限速，避免瞬时带宽占满
- **三种模式** — 下载 (入站) / 上传 (出站) / 双向
- **多线程** — 可调并发数，充分利用带宽
- **实时进度** — 进度条 + 速度 + 剩余时间
- **零依赖** — 纯 Python 3 标准库，无需 pip install

## 环境要求

- Python 3.6+
- 网络可达公共测速服务器

## 一键安装

SSH 登录 VPS 后，执行以下命令即可下载并使用：

```bash
wget -O traffic_consumer.py https://raw.githubusercontent.com/huanshenweb/vpstool/main/traffic_consumer.py && chmod +x traffic_consumer.py
```

或使用 curl：

```bash
curl -fsSL -o traffic_consumer.py https://raw.githubusercontent.com/huanshenweb/vpstool/main/traffic_consumer.py && chmod +x traffic_consumer.py
```

## 快速开始

下载完成后直接运行：

```bash
# 全速下载消耗 10GB
python3 traffic_consumer.py -g 10
```

一键下载并运行（下载 + 消耗 10GB）：

```bash
curl -fsSL https://raw.githubusercontent.com/huanshenweb/vpstool/main/traffic_consumer.py | python3 - -g 10
```

## 参数说明

| 参数 | 全称 | 类型 | 必填 | 默认值 | 说明 |
|------|------|------|------|--------|------|
| `-g` | `--gb` | float | 是 | — | 目标流量，单位 GB |
| `-t` | `--time` | int | 否 | 0 | 消耗时间，单位分钟，0 = 不限时 |
| `-m` | `--mode` | str | 否 | download | 模式：`download` / `upload` / `duplex` |
| `-n` | `--threads` | int | 否 | 4 | 并发线程数 |
| `-s` | `--speed` | float | 否 | 0 | 速率上限，单位 MB/s，0 = 不限速 |

## 使用示例

### 基本用法

```bash
# 全速下载消耗 10GB 入站流量
python3 traffic_consumer.py -g 10

# 上传模式消耗 20GB 出站流量
python3 traffic_consumer.py -g 20 -m upload
```

### 控制时间

```bash
# 在 60 分钟内匀速消耗 50GB（自动计算速率约 14.2 MB/s）
python3 traffic_consumer.py -g 50 -t 60

# 在 2 小时内消耗 100GB
python3 traffic_consumer.py -g 100 -t 120
```

### 控制速率

```bash
# 限速 10 MB/s 消耗 5GB
python3 traffic_consumer.py -g 5 -s 10

# 限速 50 MB/s 消耗 30GB
python3 traffic_consumer.py -g 30 -s 50
```

### 高级用法

```bash
# 双向模式 + 8线程 + 120分钟消耗 100GB
python3 traffic_consumer.py -g 100 -t 120 -m duplex -n 8
```

## 后台运行

长时间消耗流量时，建议后台运行以防止 SSH 断连导致任务中断。

### 方式一：nohup（最简单）

```bash
# 后台运行，日志输出到文件
nohup python3 traffic_consumer.py -g 50 -t 60 > traffic.log 2>&1 &

# 查看运行状态
tail -f traffic.log

# 停止任务
kill $(pgrep -f traffic_consumer)
```

### 方式二：screen

```bash
# 创建一个新的 screen 会话
screen -S traffic

# 在 screen 中运行
python3 traffic_consumer.py -g 100 -t 180

# 按 Ctrl+A 然后按 D 脱离会话（任务继续运行）
# 重新连接查看进度
screen -r traffic

# 列出所有 screen 会话
screen -ls
```

### 方式三：tmux

```bash
# 创建一个新的 tmux 会话
tmux new -s traffic

# 在 tmux 中运行
python3 traffic_consumer.py -g 100 -t 180

# 按 Ctrl+B 然后按 D 脱离会话（任务继续运行）
# 重新连接查看进度
tmux attach -t traffic

# 列出所有 tmux 会话
tmux ls
```

### 方式四：systemd 服务（开机自启）

创建服务文件：

```bash
sudo tee /etc/systemd/system/traffic-consumer.service << 'EOF'
[Unit]
Description=VPS Traffic Consumer
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /root/traffic_consumer.py -g 50 -t 60
Restart=no
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
```

管理服务：

```bash
# 启动
sudo systemctl start traffic-consumer

# 查看状态
sudo systemctl status traffic-consumer

# 查看日志
sudo journalctl -u traffic-consumer -f

# 停止
sudo systemctl stop traffic-consumer

# 设置开机自启（可选）
sudo systemctl enable traffic-consumer
```

## 运行效果

```
============================================================
  VPS Traffic Consumer
============================================================
  模式:     下载 (入站)
  目标流量: 50.00 GB
  计划时间: 60 分钟
  限速:     14.2 MB/s
  线程数:   4
============================================================
  Ctrl+C 随时停止
============================================================

[████████████░░░░░░░░░░░░░]  48.3%  24.15/50.00 GB  速度: 13.8 MB/s (均 14.1)  剩余: 0:31:12  错误: 0
```

## 模式说明

| 模式 | 流量方向 | 适用场景 |
|------|----------|----------|
| `download` | 入站 (服务器 ← 互联网) | 消耗入站流量配额 |
| `upload` | 出站 (服务器 → 互联网) | 消耗出站流量配额（AWS 计费方向） |
| `duplex` | 双向同时 | 同时消耗入站和出站流量 |

> **AWS 流量计费提示**：AWS 通常对**出站流量**收费，入站流量免费。如需消耗计费流量配额，使用 `upload` 或 `duplex` 模式。

## 限速机制

脚本支持两种限速方式（可同时使用，取较小值生效）：

1. **按时间限速** (`-t`)：根据目标流量和时间自动计算速率
   - 例：50GB / 60分钟 ≈ 14.2 MB/s
2. **手动限速** (`-s`)：直接指定速率上限
   - 例：`-s 10` 限制为 10 MB/s

## 测速源

脚本使用以下公共测速服务器：

**下载源：**
- speedtest.tele2.net (1GB / 10GB)
- proof.ovh.net (1Gb / 10Gb)
- speedtest.ftp.otenet.gr (1Gb / 10Gb)

**上传目标：**
- speedtest.tele2.net/upload.php
- bouygues.testdebit.info

如某个源不可用，脚本会自动切换到下一个。

## 注意事项

- 请确认 VPS 的流量套餐和计费规则，避免产生意外费用
- 建议先小量测试（如 `-g 0.1`）确认脚本正常工作
- 长时间运行建议配合 `screen` 或 `tmux` 使用
- `Ctrl+C` 可随时安全停止，脚本会输出已消耗的统计信息
