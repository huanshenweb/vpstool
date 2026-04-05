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

# 后台运行，日志输出到文件
nohup python3 traffic_consumer.py -g 50 -t 60 > traffic.log 2>&1 &

# 配合 screen 使用
screen -S traffic
python3 traffic_consumer.py -g 100 -t 180
# Ctrl+A D 脱离，screen -r traffic 恢复
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
