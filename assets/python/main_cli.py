#!/usr/bin/env python3
"""
高级下载器 — 交互式命令行入口
直接调用各平台 bridge 模块的功能，保持与参考项目一致的交互体验。
Flutter 终端只做 stdin/stdout 转发，不干预任何逻辑。
"""
import sys
import os
import json
import platform as _platform

# 添加脚本目录到 path
script_dir = os.path.dirname(os.path.abspath(__file__))
if script_dir not in sys.path:
    sys.path.insert(0, script_dir)

# ── 全局配置 ──
current_platform = os.environ.get("PLATFORM_ID", "douyin")
download_path = ""

def _get_download_path():
    global download_path
    if download_path:
        return download_path
    home = os.path.expanduser("~")
    dirs = {"douyin": "DyDownload", "xhs": "XhsDownload", "kuaishou": "KsDownload"}
    download_path = os.path.join(home, "Downloads", dirs.get(current_platform, "DyDownload"))
    os.makedirs(download_path, exist_ok=True)
    return download_path

def _get_bridge():
    """获取当前平台的 bridge 模块"""
    if current_platform == "douyin":
        import dy_bridge
        return dy_bridge
    elif current_platform == "xhs":
        import xhs_bridge
        return xhs_bridge
    elif current_platform == "kuaishou":
        import ks_bridge
        return ks_bridge
    return None

def print_banner():
    name = {"douyin": "抖音", "xhs": "小红书", "kuaishou": "快手"}.get(current_platform, "抖音")
    print()
    print("=" * 56)
    print(f"  高级下载器 — {name}模块")
    print(f"  内嵌 Python {_platform.python_version().split()[0]}")
    print(f"  下载目录: {_get_download_path()}")
    print("=" * 56)
    print()

def print_menu():
    name = {"douyin": "抖音", "xhs": "小红书", "kuaishou": "快手"}.get(current_platform, "")
    print(f"── {name}功能菜单 ──")
    print(" [1] 粘贴链接下载")
    print(" [2] 批量下载（多链接）")

    if current_platform == "douyin":
        print(" [3] 检测链接信息（作者/合集）")
        print(" [4] 下载作者全部作品")
        print(" [5] 浏览收藏夹")
        print(" [6] 下载收藏夹")
        print(" [7] 下载合集")
        print(" [8] 录制直播")
        print(" [9] 从历史记录重新下载")

    print()
    print(" [s] 设置")
    print(" [h] 帮助")
    print(" [q] 退出")
    print()

def handle_download():
    """单链接下载"""
    link = input("粘贴链接: ").strip()
    if not link:
        print("❌ 链接不能为空")
        return
    bridge = _get_bridge()
    if not bridge:
        print("❌ 模块加载失败")
        return
    print(f"\n🔍 正在解析...")
    result = bridge.parse_link(link, _get_download_path(), "")
    print_result(result)

def handle_batch():
    """批量下载"""
    print("请输入多个链接（每行一个，空行结束）:")
    links = []
    while True:
        line = input("链接: ").strip()
        if not line:
            break
        links.append(line)
    if not links:
        print("❌ 未输入任何链接")
        return

    bridge = _get_bridge()
    if not bridge:
        print("❌ 模块加载失败")
        return

    ok, fail = 0, 0
    for i, link in enumerate(links):
        print(f"\n[{i+1}/{len(links)}] {link[:60]}...")
        result = bridge.parse_link(link, _get_download_path(), "")
        if isinstance(result, str):
            try:
                result = json.loads(result)
            except:
                pass
        if isinstance(result, dict) and result.get("success"):
            ok += 1
            print(f"  ✅ {result.get('title', '完成')}")
        else:
            fail += 1
            print(f"  ❌ {result.get('message', '失败') if isinstance(result, dict) else result}")
    print(f"\n📊 批量下载完成: 成功 {ok}, 失败 {fail}")

def handle_detect():
    """检测链接信息"""
    if current_platform != "douyin":
        print("❌ 此功能仅支持抖音")
        return
    link = input("粘贴链接: ").strip()
    if not link:
        return
    try:
        import dy_bridge
        print("🔍 检测中...")
        r = dy_bridge.detect_link_info(link)
        if isinstance(r, str):
            r = json.loads(r)
        if r.get("success"):
            print(f"\n📝 标题: {r.get('title', '')}")
            author = r.get("author")
            if author:
                print(f"👤 作者: {author.get('nickname', '')} (UID: {author.get('uid', '')})")
                print(f"   sec_uid: {author.get('sec_uid', '')}")
            mix = r.get("mix")
            if mix:
                print(f"📁 合集: {mix.get('mix_name', '')} ({mix.get('count', 0)}个)")
        else:
            print(f"❌ {r.get('message', '失败')}")
    except Exception as e:
        print(f"❌ {e}")

def handle_author():
    """下载作者全部作品"""
    if current_platform != "douyin":
        print("❌ 此功能仅支持抖音")
        return
    sec_uid = input("作者 sec_uid: ").strip()
    if not sec_uid:
        return
    nickname = input("作者昵称（可选）: ").strip() or f"作者_{sec_uid[:8]}"
    try:
        import dy_bridge
        print(f"⬇️ 下载作者作品: {nickname}...")
        result = dy_bridge.batch_download_account(sec_uid, nickname, _get_download_path(), "")
        print_result(result)
    except Exception as e:
        print(f"❌ {e}")

def handle_browse_collects():
    """浏览收藏夹"""
    if current_platform != "douyin":
        print("❌ 此功能仅支持抖音")
        return
    try:
        import dy_bridge
        print("📚 获取收藏夹...")
        r = dy_bridge.list_collect_folders()
        if isinstance(r, str):
            r = json.loads(r)
        if r.get("success"):
            folders = r.get("folders", [])
            if not folders:
                print("没有收藏夹")
                return
            print(f"\n── 收藏夹 ({len(folders)}) ──")
            for i, f in enumerate(folders):
                print(f"  [{i+1}] {f.get('name', '未命名')} ({f.get('count', 0)}个)")
                print(f"      ID: {f.get('id', '')}")
        else:
            print(f"❌ {r.get('message', '失败')}")
    except Exception as e:
        print(f"❌ {e}")

def handle_download_collect():
    """下载收藏夹"""
    if current_platform != "douyin":
        print("❌ 此功能仅支持抖音")
        return
    cid = input("收藏夹 ID: ").strip()
    if not cid:
        return
    cname = input("名称（可选）: ").strip() or f"收藏夹_{cid[:8]}"
    try:
        import dy_bridge
        print(f"⬇️ 下载收藏夹: {cname}...")
        result = dy_bridge.batch_download_collect(cid, cname, _get_download_path(), "")
        print_result(result)
    except Exception as e:
        print(f"❌ {e}")

def handle_mix():
    """下载合集"""
    if current_platform != "douyin":
        print("❌ 此功能仅支持抖音")
        return
    mid = input("合集 mix_id: ").strip()
    if not mid:
        return
    mname = input("名称（可选）: ").strip() or f"合集_{mid[:8]}"
    try:
        import dy_bridge
        print(f"⬇️ 下载合集: {mname}...")
        result = dy_bridge.batch_download_mix(mid, mname, _get_download_path(), "")
        print_result(result)
    except Exception as e:
        print(f"❌ {e}")

def handle_live():
    """录制直播"""
    if current_platform != "douyin":
        print("❌ 此功能仅支持抖音")
        return
    url = input("直播间链接: ").strip()
    if not url:
        return
    try:
        import dy_bridge
        print("🎥 开始录制...")
        result = dy_bridge.record_live(url, _get_download_path(), "")
        print_result(result)
    except Exception as e:
        print(f"❌ {e}")

def handle_retry():
    """从历史记录重新下载"""
    if current_platform != "douyin":
        print("❌ 此功能仅支持抖音")
        return
    try:
        import dy_bridge
        print("🔄 从历史记录重新下载...")
        result = dy_bridge.redownload_from_history(_get_download_path(), "")
        print_result(result)
    except Exception as e:
        print(f"❌ {e}")

def handle_settings():
    """设置菜单"""
    global download_path, current_platform
    print()
    print("── 设置 ──")
    print(f" [1] 切换平台 (当前: {current_platform})")
    print(f" [2] 设置 Cookie")
    print(f" [3] 设置代理")
    print(f" [4] 设置下载目录 (当前: {_get_download_path()})")
    print(f" [5] 查看 Python 信息")
    print(f" [b] 返回")
    print()
    c = input("选择: ").strip()

    if c == "1":
        print("\n  1=抖音  2=小红书  3=快手")
        p = input("  选择: ").strip()
        m = {"1": "douyin", "2": "xhs", "3": "kuaishou"}
        if p in m:
            current_platform = m[p]
            download_path = ""  # reset
            print(f"  ✅ 已切换到 {current_platform}")
    elif c == "2":
        cookie = input("输入 Cookie: ").strip()
        if cookie:
            bridge = _get_bridge()
            if bridge:
                bridge.set_cookie(cookie)
                print(f"  ✅ Cookie 已设置 ({len(cookie)} 字符)")
    elif c == "3":
        proxy = input("输入代理 (如 http://127.0.0.1:7890): ").strip()
        if proxy:
            bridge = _get_bridge()
            if bridge:
                bridge.set_proxy(proxy)
                print(f"  ✅ 代理: {proxy}")
    elif c == "4":
        path = input("输入下载目录: ").strip()
        if path:
            download_path = path
            os.makedirs(path, exist_ok=True)
            print(f"  ✅ 下载目录: {path}")
    elif c == "5":
        print(f"  Python: {_platform.python_version()}")
        print(f"  路径: {sys.executable}")
        print(f"  平台: {_platform.platform()}")
        print(f"  脚本目录: {script_dir}")

def print_result(result):
    """统一打印结果"""
    if isinstance(result, str):
        try:
            result = json.loads(result)
        except:
            print(result)
            return
    if isinstance(result, dict):
        if result.get("success"):
            print(f"\n✅ {result.get('title', '完成')}")
            msg = result.get("message", "")
            if msg:
                print(f"   {msg}")
            if result.get("path"):
                print(f"   路径: {result['path']}")
            if result.get("size") and result["size"] > 0:
                mb = result["size"] / (1024 * 1024)
                print(f"   大小: {mb:.1f} MB")
        else:
            print(f"\n❌ {result.get('message', '未知错误')}")
    else:
        print(result)

def main():
    print_banner()
    print_menu()

    handlers = {
        "1": handle_download,
        "2": handle_batch,
        "3": handle_detect,
        "4": handle_author,
        "5": handle_browse_collects,
        "6": handle_download_collect,
        "7": handle_mix,
        "8": handle_live,
        "9": handle_retry,
    }

    while True:
        try:
            choice = input(">>> ").strip().lower()
        except (EOFError, KeyboardInterrupt):
            print("\n退出")
            break

        if not choice:
            continue
        if choice in ("q", "quit", "exit"):
            print("退出")
            break
        elif choice in ("h", "help", "menu"):
            print_menu()
        elif choice == "s":
            handle_settings()
        elif choice in handlers:
            if current_platform != "douyin" and choice not in ("1", "2"):
                print("❌ 此功能仅支持抖音平台")
                continue
            handlers[choice]()
        else:
            # 不是菜单选项，可能是直接粘贴的链接
            if choice.startswith("http://") or choice.startswith("https://"):
                bridge = _get_bridge()
                if bridge:
                    print(f"\n🔍 正在解析...")
                    result = bridge.parse_link(choice, _get_download_path(), "")
                    print_result(result)
            else:
                print(f"❓ 未知选项: {choice}，输入 h 查看菜单")

if __name__ == "__main__":
    main()
