#!/usr/bin/env python3
"""
VPS Traffic Consumer - AWS VPS 流量消耗工具
支持设置目标流量(GB)、消耗时间、速率限制，支持下载/上传两种模式
"""

import argparse
import os
import signal
import sys
import socket
import time
import threading
import urllib.request
import urllib.error
from datetime import timedelta

DOWNLOAD_URLS = [
    "http://speedtest.tele2.net/10GB.zip",
    "http://speedtest.tele2.net/1GB.zip",
    "http://proof.ovh.net/files/10Gb.dat",
    "http://proof.ovh.net/files/1Gb.dat",
    "http://speedtest.ftp.otenet.gr/files/test10Gb.db",
    "http://speedtest.ftp.otenet.gr/files/test1Gb.db",
]

UPLOAD_URLS = [
    "http://speedtest.tele2.net/upload.php",
    "http://bouygues.testdebit.info/",
]

GB = 1024 ** 3
MB = 1024 ** 2


class TrafficConsumer:
    def __init__(self, target_gb, duration_minutes, mode, threads, speed_limit_mbps):
        self.target_bytes = int(target_gb * GB)
        self.duration_seconds = duration_minutes * 60 if duration_minutes > 0 else 0
        self.mode = mode
        self.threads = threads
        self.speed_limit_bps = int(speed_limit_mbps * MB) if speed_limit_mbps else 0
        self.consumed = 0
        self.running = True
        self.start_time = None
        self.lock = threading.Lock()
        self.errors = 0

        signal.signal(signal.SIGINT, self._on_stop)
        signal.signal(signal.SIGTERM, self._on_stop)

    def _on_stop(self, *_):
        print("\n\n正在停止...")
        self.running = False

    def _add(self, n):
        with self.lock:
            self.consumed += n

    def _calc_target_speed(self):
        """根据目标流量和时间计算期望速率 (bytes/s)"""
        if self.speed_limit_bps > 0:
            return self.speed_limit_bps
        if self.duration_seconds > 0:
            return self.target_bytes / self.duration_seconds
        return 0

    def _throttle(self):
        """按需限速：如果进度超前则等待"""
        if not self.running:
            return
        target_speed = self._calc_target_speed()
        if target_speed <= 0:
            return
        elapsed = time.time() - self.start_time
        if elapsed <= 0:
            return
        expected = target_speed * elapsed
        if self.consumed > expected * 1.05:
            overshoot = (self.consumed - expected) / target_speed
            sleep_time = min(overshoot, 2.0)
            time.sleep(sleep_time)

    def _done(self):
        return not self.running or self.consumed >= self.target_bytes

    # ---- 下载模式 ----
    def _download_worker(self, worker_id):
        chunk_size = 256 * 1024  # 256KB
        url_idx = worker_id % len(DOWNLOAD_URLS)
        retries = 0

        while not self._done():
            url = DOWNLOAD_URLS[url_idx]
            try:
                req = urllib.request.Request(url, headers={
                    "User-Agent": "Mozilla/5.0 (VPS Traffic Consumer)",
                })
                with urllib.request.urlopen(req, timeout=30) as resp:
                    while not self._done():
                        chunk = resp.read(chunk_size)
                        if not chunk:
                            break
                        self._add(len(chunk))
                        self._throttle()
                retries = 0
            except Exception:
                self.errors += 1
                retries += 1
                url_idx = (url_idx + 1) % len(DOWNLOAD_URLS)
                time.sleep(min(retries * 2, 10))

    # ---- 上传模式 ----
    def _upload_worker(self, worker_id):
        upload_chunk = 2 * MB  # 每次上传 2MB
        url_idx = worker_id % len(UPLOAD_URLS)
        retries = 0

        while not self._done():
            remaining = self.target_bytes - self.consumed
            size = min(upload_chunk, remaining)
            data = os.urandom(size)
            url = UPLOAD_URLS[url_idx]
            try:
                req = urllib.request.Request(url, data=data, method="POST", headers={
                    "User-Agent": "Mozilla/5.0 (VPS Traffic Consumer)",
                    "Content-Type": "application/octet-stream",
                    "Content-Length": str(len(data)),
                })
                with urllib.request.urlopen(req, timeout=60) as resp:
                    resp.read()
                self._add(size)
                self._throttle()
                retries = 0
            except Exception:
                self.errors += 1
                retries += 1
                url_idx = (url_idx + 1) % len(UPLOAD_URLS)
                time.sleep(min(retries * 2, 10))

    # ---- 双向模式 ----
    def _duplex_worker(self, worker_id):
        if worker_id % 2 == 0:
            self._download_worker(worker_id)
        else:
            self._upload_worker(worker_id)

    # ---- 进度显示 ----
    def _progress_loop(self):
        last_bytes = 0
        while not self._done():
            time.sleep(1)
            elapsed = time.time() - self.start_time
            consumed_gb = self.consumed / GB
            target_gb = self.target_bytes / GB
            pct = min(self.consumed / self.target_bytes * 100, 100)

            current_speed = (self.consumed - last_bytes) / MB
            last_bytes = self.consumed

            avg_speed = self.consumed / (elapsed * MB) if elapsed > 0 else 0

            remaining = self.target_bytes - self.consumed
            eta = timedelta(seconds=int(remaining / (avg_speed * MB))) if avg_speed > 0 else "--:--:--"

            bar_len = 25
            filled = int(bar_len * pct / 100)
            bar = "█" * filled + "░" * (bar_len - filled)

            line = (
                f"\r[{bar}] {pct:5.1f}%  "
                f"{consumed_gb:.2f}/{target_gb:.2f} GB  "
                f"速度: {current_speed:.1f} MB/s (均 {avg_speed:.1f})  "
                f"剩余: {eta}  "
                f"错误: {self.errors}"
            )
            sys.stdout.write(line)
            sys.stdout.flush()

    def run(self):
        target_gb = self.target_bytes / GB
        target_speed = self._calc_target_speed()

        mode_label = {"download": "下载 (入站)", "upload": "上传 (出站)", "duplex": "双向 (上传+下载)"}
        print("=" * 60)
        print("  VPS Traffic Consumer")
        print("=" * 60)
        print(f"  模式:     {mode_label[self.mode]}")
        print(f"  目标流量: {target_gb:.2f} GB")
        if self.duration_seconds > 0:
            print(f"  计划时间: {self.duration_seconds / 60:.0f} 分钟")
        if target_speed > 0:
            print(f"  限速:     {target_speed / MB:.1f} MB/s")
        else:
            print(f"  限速:     不限速 (全速)")
        print(f"  线程数:   {self.threads}")
        print("=" * 60)
        print("  Ctrl+C 随时停止")
        print("=" * 60)
        print()

        self.start_time = time.time()

        progress_t = threading.Thread(target=self._progress_loop, daemon=True)
        progress_t.start()

        worker_fn = {
            "download": self._download_worker,
            "upload": self._upload_worker,
            "duplex": self._duplex_worker,
        }[self.mode]

        workers = []
        for i in range(self.threads):
            t = threading.Thread(target=worker_fn, args=(i,), daemon=True)
            t.start()
            workers.append(t)

        for t in workers:
            while t.is_alive() and self.running:
                t.join(timeout=1)

        self.running = False
        time.sleep(0.3)

        elapsed = time.time() - self.start_time
        consumed_gb = self.consumed / GB
        avg_speed = self.consumed / (elapsed * MB) if elapsed > 0 else 0

        print(f"\n\n{'=' * 60}")
        print(f"  完成!")
        print(f"  已消耗:   {consumed_gb:.2f} GB")
        print(f"  耗时:     {timedelta(seconds=int(elapsed))}")
        print(f"  平均速度: {avg_speed:.1f} MB/s")
        print(f"  错误次数: {self.errors}")
        print(f"{'=' * 60}")


def main():
    parser = argparse.ArgumentParser(
        description="VPS Traffic Consumer - 消耗 VPS 流量",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
示例:
  %(prog)s -g 10                      # 全速下载消耗 10GB
  %(prog)s -g 50 -t 60                # 在 60 分钟内消耗 50GB (下载)
  %(prog)s -g 20 -m upload            # 上传模式消耗 20GB (出站流量)
  %(prog)s -g 100 -t 120 -m duplex    # 双向模式 120 分钟内消耗 100GB
  %(prog)s -g 5 -s 10                 # 限速 10 MB/s 消耗 5GB
  %(prog)s -g 30 -n 8                 # 8 线程全速消耗 30GB
""",
    )
    parser.add_argument("-g", "--gb", type=float, required=True, help="目标流量 (GB)")
    parser.add_argument("-t", "--time", type=int, default=0, help="计划消耗时间 (分钟), 0 = 不限时")
    parser.add_argument(
        "-m", "--mode",
        choices=["download", "upload", "duplex"],
        default="download",
        help="模式: download=下载入站, upload=上传出站, duplex=双向 (默认 download)",
    )
    parser.add_argument("-n", "--threads", type=int, default=4, help="并发线程数 (默认 4)")
    parser.add_argument("-s", "--speed", type=float, default=0, help="速度限制 (MB/s), 0 = 不限速")

    args = parser.parse_args()

    if args.gb <= 0:
        parser.error("目标流量必须大于 0")
    if args.time < 0:
        parser.error("时间不能为负数")

    consumer = TrafficConsumer(
        target_gb=args.gb,
        duration_minutes=args.time,
        mode=args.mode,
        threads=args.threads,
        speed_limit_mbps=args.speed,
    )
    consumer.run()


if __name__ == "__main__":
    main()
