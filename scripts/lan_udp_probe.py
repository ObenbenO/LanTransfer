#!/usr/bin/env python3
"""
与 X 传输工具「局域网 UDP 发现」同格式探针：端口 45678，载荷 XTR1 + JSON。

用法（两台电脑，网段 192.168.110.x）：
  1) 在电脑 A 上先关掉本机 X 传输（否则会占满 45678），然后：
       python scripts/lan_udp_probe.py listen
  2) 在电脑 B 上：
       python scripts/lan_udp_probe.py send
     若 A 收到打印，说明 UDP 广播路径 + 防火墙入站基本正常。

也可：B 开着 X 传输，A 只跑 listen（不发包），若每约 2 秒出现一行，说明程序发出的广播能到 A。

【易误判】同一台电脑同时开 listen + send，或只在本机测广播时，Windows 常把
192.168.110.x 的广播又交给本机 socket，来源会显示为本机 IP（如 192.168.110.105），
这并不代表「对端机器」收到了包。正确做法：只在电脑 A 上 listen，只在电脑 B 上 send；
此时 A 上应看到「来源 = B 的 IP」。若 A 始终收不到，再试 unicast 直连 B→A 的单播。

依赖：仅标准库。
"""
from __future__ import annotations

import argparse
import json
import socket
import sys
import time

PORT = 45678
MAGIC = b"XTR1"


def build_payload() -> bytes:
    body = {
        "v": 1,
        "did": "python-probe",
        "inst": "probe",
        "nick": "py",
        "tags": "",
        "fport": 12345,
        "rport": 0,
    }
    return MAGIC + json.dumps(body, separators=(",", ":")).encode("utf-8")


def cmd_listen(_: argparse.Namespace) -> int:
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        s.bind(("0.0.0.0", PORT))
    except OSError as e:
        print(f"绑定 0.0.0.0:{PORT} 失败: {e}", file=sys.stderr)
        print("本机是否已打开 X 传输（占用 45678）？请先关闭再试。", file=sys.stderr)
        return 1
    print(f"监听 UDP {PORT}，等待数据… (Ctrl+C 结束)")
    print(
        "提示：若「来源 IP」是本机自己的 192.168.110.x，多为本机广播回环；"
        "验证跨机请只在对方执行 send，本机不要执行 send。",
        file=sys.stderr,
    )
    while True:
        data, addr = s.recvfrom(4096)
        head = data[:4]
        tail = data[4 : min(len(data), 200)]
        ok = "XTR1" if head == MAGIC else "????"
        print(f"来自 {addr[0]}:{addr[1]}  [{ok}] {tail!r}")


def cmd_send(ns: argparse.Namespace) -> int:
    pkt = build_payload()
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    targets = []
    if ns.broadcast:
        targets.append(ns.broadcast)
    if ns.global_too and "255.255.255.255" not in targets:
        targets.append("255.255.255.255")
    if not targets:
        targets = ["192.168.110.255", "255.255.255.255"]
    for host in targets:
        try:
            s.sendto(pkt, (host, PORT))
            print(f"已发送到 {host}:{PORT} ({len(pkt)} 字节)")
        except OSError as e:
            print(f"发送到 {host} 失败: {e}", file=sys.stderr)
    s.close()
    return 0


def cmd_ping(ns: argparse.Namespace) -> int:
    """连发几秒，便于对端观察防火墙是否间歇放行。"""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    pkt = build_payload()
    targets = [ns.broadcast, "255.255.255.255"] if ns.global_too else [ns.broadcast]
    end = time.time() + ns.seconds
    n = 0
    while time.time() < end:
        for host in targets:
            try:
                s.sendto(pkt, (host, PORT))
            except OSError:
                pass
        n += 1
        time.sleep(0.5)
    s.close()
    print(f"已在 {ns.seconds}s 内向 {targets} 各发约 {n} 轮")
    return 0


def cmd_unicast(ns: argparse.Namespace) -> int:
    """向指定主机单播一包（不走广播），用于判断是否是「广播被拦」。"""
    pkt = build_payload()
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        if ns.bind_local:
            s.bind((ns.bind_local, 0))
        s.sendto(pkt, (ns.dest, PORT))
        extra = f"，源绑定 {ns.bind_local}" if ns.bind_local else ""
        print(f"已单播到 {ns.dest}:{PORT}{extra} ({len(pkt)} 字节)")
    except OSError as e:
        print(f"单播失败: {e}", file=sys.stderr)
        return 1
    finally:
        s.close()
    return 0


def cmd_diag(_: argparse.Namespace) -> int:
    """本机环境快照：与 Flutter 是否占用 45678 无关的诊断（尝试绑定会短暂占用端口后释放）。"""
    import platform

    print("=== lan_udp_probe diag ===")
    print("platform:", platform.system(), platform.release(), platform.machine())
    try:
        hn = socket.gethostname()
        print("hostname:", hn)
        print("gethostbyname_ex:", socket.gethostbyname_ex(hn))
    except OSError as e:
        print("gethostbyname_ex failed:", e)
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        s.bind(("0.0.0.0", PORT))
        print(f"bind 0.0.0.0:{PORT}: OK（当前无进程占用；若随后启动 Flutter listen 会失败）")
    except OSError as e:
        print(f"bind 0.0.0.0:{PORT}: FAIL -> {e}")
        print("说明：本机已有进程监听 45678（常为 X 传输或另一 listen），与对端无关。")
    finally:
        s.close()
    print(
        "Wireshark：选正在上网的网卡，过滤 udp.port == 45678，"
        "看 OUT/IN 与 Flutter 诊断报告对照。"
    )
    return 0


def main() -> int:
    p = argparse.ArgumentParser(description="局域网 UDP 45678 / XTR1 探针")
    sub = p.add_subparsers(dest="cmd", required=True)

    sp_d = sub.add_parser("diag", help="打印本机网络快照并探测 45678 是否被占用")
    sp_d.set_defaults(func=cmd_diag)

    sp_l = sub.add_parser("listen", help="在本机监听 45678")
    sp_l.set_defaults(func=cmd_listen)

    sp_s = sub.add_parser("send", help="发 1 次广播（默认 192.168.110.255 + 全局）")
    sp_s.add_argument(
        "--broadcast",
        "-b",
        default=None,
        metavar="IP",
        help="子网广播地址，默认 192.168.110.255",
    )
    sp_s.add_argument(
        "--no-global",
        action="store_true",
        help="不发送 255.255.255.255",
    )

    def _send_ns(ns: argparse.Namespace) -> int:
        if ns.broadcast is None:
            ns.broadcast = "192.168.110.255"
        ns.global_too = not ns.no_global
        return cmd_send(ns)

    sp_s.set_defaults(func=_send_ns)

    sp_p = sub.add_parser("ping", help="连续发多秒（默认只发 192.168.110.255）")
    sp_p.add_argument(
        "-b",
        "--broadcast",
        default="192.168.110.255",
        help="子网广播地址",
    )
    sp_p.add_argument(
        "--seconds",
        type=float,
        default=5.0,
        help="持续时间（秒）",
    )
    sp_p.add_argument(
        "--global-too",
        action="store_true",
        help="同时发 255.255.255.255",
    )
    sp_p.set_defaults(func=cmd_ping)

    sp_u = sub.add_parser(
        "unicast",
        help="向指定 IP 单播 1 包（对比广播：若仅 B→A 单播失败，常见为多网卡/VPN 源地址错）",
    )
    sp_u.add_argument(
        "dest",
        metavar="IP",
        help="接收端 IP（运行 listen 的那台机器的地址）",
    )
    sp_u.add_argument(
        "-B",
        "--bind",
        dest="bind_local",
        metavar="LOCAL_IP",
        default=None,
        help="绑定本机 192.168.110.x 网卡 IP 再发送（排除 VPN/虚拟网卡抢走默认路由）",
    )
    sp_u.set_defaults(func=cmd_unicast)

    ns = p.parse_args()
    try:
        return ns.func(ns)
    except KeyboardInterrupt:
        print("\n已退出")
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
