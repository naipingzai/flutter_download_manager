"""
Python Bridge for DyDownload Android App
Bridges the Android app with TikTokDownloader (DouK-Downloader) core functionality.
"""
import os
import sys
import json
import re
import traceback
from urllib.parse import quote, urlencode

# Configuration storage
_config = {
    "cookie": "",
    "proxy": "",
    "download_path": "",
    "video_quality": "highest",
    "max_concurrent": 5,
    "name_format": "作品类型 作品描述",
    "folder_by_author": True,
}

# 进度回调模块（通过 Chaquopy java bridge 调用 Kotlin）
_TaskManager = None
_progress_interval = 65536 * 8  # 每 512KB 报告一次
_progress_min_interval_ms = 500  # 至少间隔 500ms
_progress_last_time = {}  # {task_id: last_report_time_ms}

# ── 任务暂停控制 ──
_task_controls = {}  # {task_id: "paused"}

def pause_task(task_id: str) -> bool:
    """Signal a running task to pause."""
    _task_controls[str(task_id)] = "paused"
    return True

def resume_task(task_id: str) -> bool:
    """Clear pause signal for a task."""
    _task_controls.pop(str(task_id), None)
    return True

def is_task_paused(task_id: str) -> bool:
    """Check if a task is signaled to pause."""
    return _task_controls.get(str(task_id)) == "paused"

def _get_task_manager():
    global _TaskManager
    if _TaskManager is None:
        try:
            from java import jclass
            _TaskManager = jclass("com.advancedownloader.ui.tasks.DownloadTaskManager")
        except Exception:
            _TaskManager = False  # mark as unavailable
    return _TaskManager if _TaskManager else None

def _report_progress(task_id, downloaded, total, title=""):
    """Report download progress back to Android via Java bridge (throttled)."""
    if not task_id:
        return
    import time
    now = int(time.time() * 1000)
    last = _progress_last_time.get(task_id, 0)
    # 除非是首次(downloaded==0)或完成(downloaded>=total>0)，否则按时间间隔节流
    is_terminal = (downloaded == 0) or (total > 0 and downloaded >= total)
    if not is_terminal and (now - last) < _progress_min_interval_ms:
        return
    _progress_last_time[task_id] = now
    try:
        mgr = _get_task_manager()
        if mgr:
            mgr.updateProgress(str(task_id), int(downloaded), int(total), str(title))
    except Exception:
        pass  # non-fatal: UI just won't update


def _cookie_str_to_dict(cookie_str: str) -> dict:
    """对齐 format.py cookie_str_to_dict: 将 cookie 字符串解析为字典"""
    if not cookie_str:
        return {}
    cookie = {}
    pattern = re.compile(r"(?P<key>[^=;,]+)=(?P<value>[^;,]+)")
    for m in pattern.finditer(cookie_str):
        key = m.group("key").strip()
        value = m.group("value").strip()
        if key:
            cookie[key] = value
    return cookie


def _truncate_filename(name: str, max_bytes: int = 80) -> str:
    """按 UTF-8 字节数截断文件名，避免 Android ENAMETOOLONG"""
    encoded = name.encode("utf-8")
    if len(encoded) <= max_bytes:
        return name
    # 按字节截断后解码，忽略不完整的尾部字符
    truncated = encoded[:max_bytes].decode("utf-8", errors="ignore").rstrip()
    return truncated.strip(' ._') or name[:20]


def _cookie_dict_to_str(cookie_dict: dict) -> str:
    """对齐 format.py cookie_dict_to_str: 将字典转为 cookie 字符串"""
    if not cookie_dict:
        return ""
    return "; ".join(f"{k}={v}" for k, v in cookie_dict.items())


def _ensure_cookie_str(cookie) -> str:
    """确保 cookie 是字符串格式（兼容旧 dict 存储）"""
    if isinstance(cookie, dict):
        return _cookie_dict_to_str(cookie)
    if isinstance(cookie, str):
        return cookie.strip()
    return ""


def set_cookie(cookie: str):
    """Set the cookie for Douyin/TikTok API requests."""
    # 直接存储原始 cookie 字符串，避免 str→dict→str 有损转换
    clean = cookie.strip()
    _config["cookie"] = clean
    _save_config()
    cookie_dict = _cookie_str_to_dict(clean)
    return json.dumps({
        "success": True,
        "key_count": len(cookie_dict),
        "cookie_length": len(clean),
    })


def get_cookie_status() -> str:
    """Return cookie status info as JSON string."""
    cookie = _ensure_cookie_str(_config.get("cookie", ""))
    if not cookie:
        return json.dumps({"has_cookie": False, "keys": []})
    cookie_dict = _cookie_str_to_dict(cookie)
    important_keys = [k for k in cookie_dict if k in (
        "passport_csrf_token", "sessionid", "sessionid_ss", "odin_tt",
        "tt_csrf_token", "sid_guard", "uid_tt", "ttwid"
    )]
    return json.dumps({
        "has_cookie": True,
        "key_count": len(cookie_dict),
        "important_keys": important_keys,
    })


def set_proxy(proxy: str):
    """Set the proxy for network requests."""
    _config["proxy"] = proxy
    _save_config()


def set_download_path(path: str):
    """Set the download directory."""
    _config["download_path"] = path
    _save_config()


def get_config():
    """Return the current configuration as JSON string."""
    # 确保 cookie 字段是字符串
    safe = dict(_config)
    safe["cookie"] = _ensure_cookie_str(safe.get("cookie", ""))
    return json.dumps(safe)


def debug_info() -> str:
    """返回调试信息，帮助排查问题"""
    home = os.environ.get("HOME", "(unset)")
    config_dir = os.path.join(os.environ.get("HOME", "/data/data/com.advancedownloader"), "Volume")
    config_file = os.path.join(config_dir, "settings.json")
    cookie_raw = _config.get("cookie", "")
    return json.dumps({
        "home": home,
        "config_dir": config_dir,
        "config_file": config_file,
        "config_file_exists": os.path.exists(config_file),
        "config_dir_exists": os.path.exists(config_dir),
        "cookie_type": type(cookie_raw).__name__,
        "cookie_length": len(cookie_raw) if isinstance(cookie_raw, (str, dict)) else -1,
        "config_keys": list(_config.keys()),
    }, ensure_ascii=False)


def _save_config():
    """Save config to local storage."""
    try:
        config_dir = os.path.join(os.environ.get("HOME", "/data/data/com.advancedownloader"), "Volume")
        os.makedirs(config_dir, exist_ok=True)
        config_file = os.path.join(config_dir, "settings.json")
        with open(config_file, "w", encoding="utf-8") as f:
            json.dump(_config, f, ensure_ascii=False, indent=2)
    except Exception as e:
        print(f"[DY] Warning: _save_config failed: {e}")


def _load_config():
    """Load config from local storage."""
    try:
        config_dir = os.path.join(os.environ.get("HOME", "/data/data/com.advancedownloader"), "Volume")
        config_file = os.path.join(config_dir, "settings.json")
        if os.path.exists(config_file):
            with open(config_file, "r", encoding="utf-8") as f:
                data = json.load(f)
            if isinstance(data.get("cookie"), dict):
                data["cookie"] = _cookie_dict_to_str(data["cookie"])
            _config.update(data)
            print(f"[DY] Config loaded, cookie length={len(_config.get('cookie', ''))}")
        else:
            print(f"[DY] Config file not found: {config_file}")
    except Exception as e:
        print(f"[DY] Warning: _load_config failed: {e}")


# 模块加载时自动读取已保存的配置（包括 cookie）
_load_config()

def _sync_java_config():
    """从 Android SharedPreferences 同步配置到 Python _config"""
    try:
        from java import jclass
        Context = jclass("android.app.ActivityThread").currentApplication()
        prefs_mod = jclass("androidx.preference.PreferenceManager")
        prefs = prefs_mod.getDefaultSharedPreferences(Context)
        if prefs.contains("dy_folder_by_author"):
            _config["folder_by_author"] = prefs.getBoolean("dy_folder_by_author", True)
        if prefs.contains("dy_proxy"):
            proxy = prefs.getString("dy_proxy", "")
            if proxy: _config["proxy"] = proxy
        print(f"[DY] Synced config: folder_by_author={_config.get('folder_by_author')}")
    except Exception as e:
        print(f"[DY] Warning: _sync_java_config failed: {e}")


def parse_link(link: str, download_path: str, task_id: str = "") -> dict:
    """
    Parse a Douyin/TikTok link and download the content.

    Args:
        link: The URL to parse and download
        download_path: Directory to save downloaded files
        task_id: Kotlin task ID for progress reporting

    Returns:
        dict with keys: success (bool), title (str), message (str)
    """
    try:
        _sync_java_config()
        _config["download_path"] = download_path
        os.makedirs(download_path, exist_ok=True)

        # 提取 URL
        url_pattern = re.compile(r'https?://[^\s<>"{}|\\^`\[\]]+', re.IGNORECASE)
        urls = url_pattern.findall(link)
        if not urls:
            return {"success": False, "title": link, "message": "未找到有效链接"}

        target_url = urls[0]
        result = _download_douyin(target_url, download_path, task_id=task_id)
        return result

    except Exception as e:
        return {
            "success": False,
            "title": link,
            "message": f"解析失败: {str(e)}\n{traceback.format_exc()}"
        }


def redownload_from_history(download_path: str, task_id: str = "") -> dict:
    """读取 download_history.csv 里的所有地址重新下载"""
    try:
        import csv as _csv_imp
        csv_file = os.path.join(download_path, "data", "download_history.csv")
        urls = []
        if os.path.isfile(csv_file):
            with open(csv_file, "r", encoding="utf-8-sig") as f:
                reader = _csv_imp.reader(f)
                next(reader, None)
                for row in reader:
                    if row and row[0].strip():
                        urls.append(row[0].strip())
        else:
            history_file = os.path.join(download_path, "download_history.txt")
            if os.path.isfile(history_file):
                with open(history_file, "r", encoding="utf-8") as f:
                    urls = [line.strip() for line in f if line.strip()]
        if not urls:
            return {"success": False, "title": "重新下载", "message": "未找到下载记录"}
        if not urls:
            return {"success": False, "title": "重新下载", "message": "下载记录文件为空"}
        # 去重保留顺序
        seen = set()
        unique_urls = []
        for u in urls:
            if u not in seen:
                seen.add(u)
                unique_urls.append(u)
        total = len(unique_urls)
        success_count = 0
        fail_count = 0
        for i, url in enumerate(unique_urls):
            if task_id:
                _report_progress(task_id, i + 1, total, f"重新下载 {i+1}/{total}")
            result = _download_douyin(url, download_path, task_id="")
            if result.get("success"):
                success_count += 1
            else:
                fail_count += 1
        return {
            "success": True,
            "title": "重新下载完成",
            "message": f"共 {total} 个地址，成功 {success_count}，失败 {fail_count}"
        }
    except Exception as e:
        return {
            "success": False,
            "title": "重新下载",
            "message": f"重新下载失败: {str(e)}\n{traceback.format_exc()}"
        }


# 与 TikTokDownloader 项目保持一致的 UA / Referer / 参数
_PC_UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
          "(KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36")
_REFERER = "https://www.douyin.com/?recommend=1"

# 抖音 Web API 基础参数（对齐 template.py API.params）
_DOUYIN_PARAMS = {
    "device_platform": "webapp",
    "aid": "6383",
    "channel": "channel_pc_web",
    "update_version_code": "170400",
    "pc_client_type": "1",
    "pc_libra_divert": "Windows",
    "support_h265": "1",
    "support_dash": "1",
    "version_code": "290100",
    "version_name": "29.1.0",
    "cookie_enabled": "true",
    "screen_width": "1536",
    "screen_height": "864",
    "browser_language": "zh-CN",
    "browser_platform": "Win32",
    "browser_name": "Chrome",
    "browser_version": "139.0.0.0",
    "browser_online": "true",
    "engine_name": "Blink",
    "engine_version": "139.0.0.0",
    "os_name": "Windows",
    "os_version": "10",
    "cpu_core_num": "16",
    "device_memory": "8",
    "platform": "PC",
    "downlink": "10",
    "effective_type": "4g",
    "round_trip_time": "200",
    "uifid": "",
    "msToken": "",
}

# 下载专用 headers（对齐 internal.py DOWNLOAD_HEADERS）
_DOWNLOAD_HEADERS = {
    "Accept": "*/*",
    "Range": "bytes=0-",
    "Referer": _REFERER,
    "User-Agent": _PC_UA,
}

# API 请求通用 headers（对齐 internal.py DATA_HEADERS）
_API_HEADERS = {
    "Accept": "*/*",
    "Accept-Encoding": "*/*",
    "Referer": _REFERER,
    "User-Agent": _PC_UA,
}

# ABogus 签名
_ab = None
_cached_ms_token = ""
_ms_token_time = 0
_cached_ttwid = ""
# 固定长效 token（对齐 msToken.py TOKEN 常量，用于 get_long_ms_token 回退）
_LONG_MS_TOKEN = (
    "9cguMjz4GIfQV50B_D49quM-cEyIvWMwWi0gj1bf"
    "-4YprIjt29ZrAxmDb5oIhmzEhwvcmcC4BR_kEZGmXdS1q7Ad3V94izdpXwtxgPPpozVUzQVm7KDrc5H9nfN3pLw="
)


def _get_ttwid() -> str:
    """获取 ttwid（对齐 ttWid.py）"""
    global _cached_ttwid
    if _cached_ttwid:
        return _cached_ttwid
    try:
        import httpx
        ttwid_api = "https://ttwid.bytedance.com/ttwid/union/register/"
        ttwid_data = '{"region":"cn","aid":1768,"needFid":false,"service":"www.ixigua.com","migrate_info":{"ticket":"","source":"node"},"cbUrlProtocol":"https","union":true}'
        proxy = _config.get("proxy") or None
        with httpx.Client(follow_redirects=True, timeout=15, proxy=proxy) as client:
            resp = client.post(ttwid_api, content=ttwid_data, headers={
                "User-Agent": _PC_UA,
                "Content-Type": "application/json; charset=utf-8",
            })
            # 从 Set-Cookie 提取 ttwid
            from http.cookies import SimpleCookie
            set_cookie = resp.headers.get("set-cookie", "")
            if set_cookie:
                sc = SimpleCookie()
                sc.load(set_cookie)
                if morsel := sc.get("ttwid"):
                    _cached_ttwid = morsel.value
                    print(f"[DY] Got ttwid: {_cached_ttwid[:20]}...")
                    return _cached_ttwid
            for name, value in resp.cookies.items():
                if name == "ttwid" and value:
                    _cached_ttwid = value
                    print(f"[DY] Got ttwid from cookies: {value[:20]}...")
                    return value
            print(f"[DY] ttwid not found in response")
    except Exception as e:
        print(f"[DY] Failed to get ttwid: {e}")
    return ""


def _enrich_cookie(cookie: str) -> str:
    """给 Cookie 注入 msToken 和 ttwid（对齐参考工程 __update_cookie）"""
    ms = _get_real_ms_token()
    tw = _get_ttwid()
    # 将 msToken 和 ttwid 添加/更新到 cookie 中
    cookie_dict = _cookie_str_to_dict(cookie)
    if ms:
        cookie_dict["msToken"] = ms
    if tw and "ttwid" not in cookie_dict:
        cookie_dict["ttwid"] = tw
    return "; ".join(f"{k}={v}" for k, v in cookie_dict.items())


def _get_real_ms_token() -> str:
    """从字节跳动服务器获取真实 msToken（对齐 msToken.py）"""
    import httpx, time as _time
    global _cached_ms_token, _ms_token_time

    # 缓存 5 分钟
    if _cached_ms_token and (_time.time() - _ms_token_time) < 300:
        return _cached_ms_token

    try:
        ms_api = "https://mssdk.bytedance.com/web/common"
        ms_data = {
            "magic": 538969122,
            "version": 1,
            "dataType": 8,
            "strData": (
                "fWOdJTQR3/jwmZqBBsPO6tdNEc1jX7YTwPg0Z8CT+j3HScLFbj2Zm1XQ7/lqgSutntVKLJWaY3Hc/+vc0h+So9N1t6Eqi"
                "Imu5jKyUa+S4NPy6cNP0x9CUQQgb4+RRihCgsn4QyV8jivEFOsj3N5zFQbzXRyOV+9aG5B5EAnwpn8C70llsWq0zJz1VjN6y2KZiB"
                "ZRyonAHE8feSGpwMDeUTllvq6BG3AQZz7RrORLWNCLEoGzM6bMovYVPRAJipuUML4Hq/568bNb5vqAo0eOFpvTZjQFgbB7f/C"
                "tAYYmnOYlvfrHKBKvb0TX6AjYrw2qmNNEer2ADJosmT5kZeBsogDui8rNiI/OOdX9PVotmcSmHOLRfw1cYXTgwHXr6cJeJveu"
                "ipgwtUj2FNT4YCdZfUGGyRDz5bR5bdBuYiSRteSX12EktobsKPksdhUPGGv99SI1QRVmR0ETdWqnKWOj/7ujFZsNnfCLxNfqx"
                "QYEZEp9/U01CHhWLVrdzlrJ1v+KJH9EA4P1Wo5/2fuBFVdIz2upFqEQ11DJu8LSyD43qpTok+hFG3Moqrr81uPYiyPHnUvTFg"
                "wA/TIE11mTc/pNvYIb8IdbE4UAlsR90eYvPkI+rK9KpYN/l0s9ti9sqTth12VAw8tzCQvhKtxevJRQntU3STeZ3coz9Dg8qkv"
                "aSNFWuBDuyefZBGVSgILFdMy33//l/eTXhQpFrVc9OyxDNsG6cvdFwu7trkAENHU5eQEWkFSXBx9Ml54+fa3LvJBoacfPViyv"
                "zkJworlHcYYTG392L4q6wuMSSpYUconb+0c5mwqnnLP6MvRdm/bBTaY2Q6RfJcCxyLW0xsJMO6fgLUEjAg/dcqGxl6gDjUVRW"
                "bCcG1NAwPCfmYARTuXQYbFc8LO+r6WQTWikO9Q7Cgda78pwH07F8bgJ8zFBbWmyrghilNXENNQkyIzBqOQ1V3w0WXF9+Z3vG3"
                "aBKCjIENqAQM9qnC14WMrQkfCHosGbQyEH0n/5R2AaVTE/ye2oPQBWG1m0Gfcgs/96f6yYrsxbDcSnMvsA+okyd6GfWsdZYTI"
                "K1E97PYHlncFeOjxySjPpfy6wJc4UlArJEBZYmgveo1SZAhmXl3pJY3yJa9CmYImWkhbpwsVkSmG3g11JitJXTGLIfqKXSAhh"
                "+7jg4HTKe+5KNir8xmbBI/DF8O/+diFAlD+BQd3cV0G4mEtCiPEhOvVLKV1pE+fv7nKJh0t38wNVdbs3qHtiQNN7JhY4uWZAo"
                "sMuBXSjpEtoNUndI+o0cjR8XJ8tSFnrAY8XihiRzLMfeisiZxWCvVwIP3kum9MSHXma75cdCQGFBfFRj0jPn1JildrTh2vRgw"
                "G+KeDZ33BJ2VGw9PgRkztZ2l/W5d32jc7H91FftFFhwXil6sA23mr6nNp6CcrO7rOblcm5SzXJ5MA601+WVicC/g3p6A0lAnh"
                "jsm37qP+xGT+cbCFOfjexDYEhnqz0QZm94CCSnilQ9B/HBLhWOddp9GK0SABIk5i3xAH701Xb4HCcgAulvfO5EK0RL2eN4fb+"
                "CccgZQeO1Zzo4qsMHc13UG0saMgBEH8SqYlHz2S0CVHuDY5j1MSV0nsShjM01vIynw6K0T8kmEyNjt1eRGlleJ5lvE8vonJv7"
                "rAeaVRZ06rlYaxrMT6cK3RSHd2liE50Z3ik3xezwWoaY6zBXvCzljyEmqjNFgAPU3gI+N1vi0MsFmwAwFzYqqWdk3jwRoWLp/"
                "/FnawQX0g5T64CnfAe/o2e/8o5/bvz83OsAAwZoR48GZzPu7KCIN9q4GBjyrePNx5Csq2srblifmzSKwF5MP/RLYsk6mEE15j"
                "pCMKOVlHcu0zhJybNP3AKMVllF6pvn+HWvUnLXNkt0A6zsfvjAva/tbLQiiiYi6vtheasIyDz3HpODlI+BCkV6V8lkTt7m8QJ"
                "1IcgTfqjQBummyjYTSwsQji3DdNCnlKYd13ZQa545utqu837FFAzOZQhbnC3bKqeJqO2sE3m7WBUMbRWLflPRqp/PsklN+9jB"
                "PADKxKPl8g6/NZVq8fB1w68D5EJlGExdDhglo4B0aihHhb1u3+zJ2DqkxkPCGBAZ2AcuFIDzD53yS4NssoWb4HJ7YyzPaJro+"
                "tgG9TshWRBtUw8Or3m0OtQtX+rboYn3+GxvD1O8vWInrg5qxnepelRcQzmnor4rHF6ZNhAJZAf18Rjncra00HPJBugY5rD+Ew"
                "nN9+mGQo43b01qBBRYEnxy9JJYuvXxNXxe47/MEPOw6qsxN+dmyIWZSuzkw8K+iBM/anE11yfU4qTFt0veCaVprK6tXaFK0Zh"
                "GXDOYJd70sjIP4UrPhatp8hqIXSJ2cwi70B+TvlDk/o19CA3bH6YxrAAVeag1P9hmNlfJ7NxK3Jp7+Ny1Vd7JHWVF+R6rSJiX"
                "XPfsXi3ZEy0klJAjI51NrDAnzNtgIQf0V8OWeEVv7F8Rsm3/GKnjdNOcDKymi9agZUgtctENWbCXGFnI40NHuVHtBRZeYAYtw"
                "fV7v6U0bP9s7uZGpkp+OETHMv3AyV0MVbZwQvarnjmct4Z3Vma+DvT+Z4VlMVnkC2x2FLt26K3SIMz+KV2XLv5ocEdPFSn1vM"
                "R7zruCWC8XqAG288biHo/soldmb/nlw8o8qlfZj4h296K3hfdFubGIUtqgsrZCrLCkkRC08Cv1ozEX/y6t2YrQepwiNmwDVk5"
                "IufStVvJMj+y2r9TcYLv7UKWXx3P6aySvM2ZHPaZhv+6Z/A/jIMBSvOizn4qG11iK7Oo6JYhxCSMJZsetjsnL4ecSIAufEmoF"
                "lAScWBh6nFArRpVLvkAZ3tej7H2lWFRXIU7x7mdBfGqU82PpM6znKMMZCpEsvHqpkSPSL+Kwz2z1f5wW7BKcKK4kNZ8iveg9V"
                "zY1NNjs91qU8DJpUnGyM04C7KNMpeilEmoOxvyelMQdi85ndOVmigVKmy5JYlODNX744sHpeqmMEK/ux3xY5O406lm7dZlyGP"
                "SMrFWbm4rzqvSEIskP43+9xVP8L84GeHE4RpOHg3qh/shx+/WnT1UhKuKpByHCpLoEo144udpzZswCYSMp58uPrlwdVF31//A"
                "acTRk8dUP3tBlnSQPa1eTpXWFCn7vIiqOTXaRL//YQK+e7ssrgSUnwhuGKJ8aqNDgdsL+haVZnV9g5Qrju643adyNixvYFEp0"
                "uxzOzVkekOMh2FYnFVIL2mJYGpZEXlAIC0zQbb54rSP89j0G7soJ2HcOkD0NmMEWj/7hUdTuMin1lRNde/qmHjwhbhqL8Z9ME"
                "O/YG3iLMgFTgSNQQhyE8AZAAKnehmzjORJfbK+qxyiJ07J843EDduzOoYt9p/YLqyTFmAgpdfK0uYrtAJ47cbl5WWhVXp5/XU"
                "xwWdL7TvQB0Xh6ir1/XBRcsVSDrR7cPE221ThmW1EPzD+SPf2L2gS0WromZqj1PhLgk92YnnR9s7/nLBXZHPKy+fDbJT16Qqa"
                "bFKqAl9G0blyf+R5UGX2kN+iQp4VGXEoH5lXxNNTlgRskzrW7KliQXcac20oimAHUE8Phf+rXXglpmSv4XN3eiwfXwvOaAMVj"
                "MRmRxsKitl5iZnwpcdbsC4jt16g2r/ihlKzLIYju+XZej4dNMlkftEidyNg24IVimJthXY1H15RZ8Hm7mAM/JZrsxiAVI0A49"
                "pWEiUk3cyZcBzq/vVEjHUy4r6IZnKkRvLjqsvqWE95nAGMor+F0GLHWfBCVkuI51EIOknwSB1eTvLgwgRepV4pdy9cdp6iR8T"
                "ZndPVCikflXYVMlMEJ2bJ2c0Swiq57ORJW6vQwnkxtPudpFRc7tNNDzz4LKEznJxAwGi6pBR7/co2IUgRw1ijLFTHWHQJOjgc"
                "7KaduHI0C6a+BJb4Y8IWuIk2u2qCMF1HNKFAUn/J1gTcqtIJcvK5uykpfJFCYc899TmUc8LMKI9nu57m0S44Y2hPPYeW4XSak"
                "Scsg8bJHMkcXk3Tbs9b4eqiD+kHUhTS2BGfsHadR3d5j8lNhBPzA5e+mE=="
            ),
            "tspFromClient": int(_time.time() * 1000),
            "ulr": 0,
        }
        ms_headers = {
            "Accept": "*/*",
            "Accept-Encoding": "*/*",
            "Content-Type": "text/plain;charset=UTF-8",
            "Referer": _REFERER,
            "User-Agent": _PC_UA,
        }
        import json as _json
        proxy = _config.get("proxy") or None
        with httpx.Client(follow_redirects=True, timeout=15, proxy=proxy) as client:
            body = _json.dumps(ms_data)
            print(f"[DY] msToken request: strData_len={len(ms_data['strData'])}, tsp={ms_data['tspFromClient']}")
            resp = client.post(ms_api, content=body, headers=ms_headers,
                               params={"msToken": _cached_ms_token or ""})
            print(f"[DY] msToken response: status={resp.status_code}, headers={dict(resp.headers)}")
            # 优先从 cookies jar 提取（httpx 正确处理多个 Set-Cookie）
            for name, value in resp.cookies.items():
                if name == "msToken" and value:
                    _cached_ms_token = value
                    _ms_token_time = _time.time()
                    print(f"[DY] Got real msToken from cookies: {value[:20]}...")
                    return value
            # 回退：手动解析 Set-Cookie
            from http.cookies import SimpleCookie
            set_cookie = resp.headers.get("set-cookie", "")
            if set_cookie:
                try:
                    sc = SimpleCookie()
                    sc.load(set_cookie)
                    if morsel := sc.get("msToken"):
                        _cached_ms_token = morsel.value
                        _ms_token_time = _time.time()
                        print(f"[DY] Got real msToken via SimpleCookie: {morsel.value[:20]}...")
                        return morsel.value
                except Exception:
                    pass
            print(f"[DY] msToken not found in response, trying long token...")
    except Exception as e:
        print(f"[DY] Failed to get msToken: {e}")

    # 回退2: 使用 LONG_MS_TOKEN 重试（对齐 get_long_ms_token）
    try:
        import httpx, time as _time2
        ms_api = "https://mssdk.bytedance.com/web/common"
        ms_headers2 = {
            "Accept": "*/*",
            "Accept-Encoding": "*/*",
            "Content-Type": "text/plain;charset=UTF-8",
            "Referer": _REFERER,
            "User-Agent": _PC_UA,
        }
        import json as _json2
        proxy2 = _config.get("proxy") or None
        ms_data2 = {
            "magic": 538969122, "version": 1, "dataType": 8,
            "strData": ms_data["strData"] if 'ms_data' in dir() else "",
            "tspFromClient": int(_time2.time() * 1000), "ulr": 0,
        }
        with httpx.Client(follow_redirects=True, timeout=15, proxy=proxy2) as client2:
            resp2 = client2.post(ms_api, content=_json2.dumps(ms_data2), headers=ms_headers2,
                                params={"msToken": _LONG_MS_TOKEN})
            print(f"[DY] Long token response: status={resp2.status_code}")
            for name, value in resp2.cookies.items():
                if name == "msToken" and value:
                    _cached_ms_token = value
                    _ms_token_time = _time2.time()
                    print(f"[DY] Got msToken via long token: {value[:20]}...")
                    return value
    except Exception as e2:
        print(f"[DY] Long token fallback failed: {e2}")

    # 回退3：从 Cookie 中提取
    cookie_dict = _cookie_str_to_dict(_ensure_cookie_str(_config.get("cookie", "")))
    if ms := cookie_dict.get("msToken"):
        print(f"[DY] Using msToken from cookie: {ms[:20]}...")
        return ms

    # 最终回退：随机字符串
    import string, random
    fake = "".join(random.choice(string.ascii_letters + string.digits) for _ in range(156))
    print(f"[DY] Using fake msToken")
    return fake


def _record_history(url, title, media_type="video", author=""):
    """记录下载历史到 CSV 文件（写到 data/ 目录，兼容旧版格式）"""
    try:
        download_path = _config.get("download_path", "")
        if not download_path:
            return
        import csv, time
        # 写到 data/ 目录（兼容旧版）
        data_dir = os.path.join(download_path, "data")
        os.makedirs(data_dir, exist_ok=True)
        csv_path = os.path.join(data_dir, "download_history.csv")
        write_header = not os.path.exists(csv_path) or os.path.getsize(csv_path) == 0
        with open(csv_path, "a", newline="", encoding="utf-8-sig") as f:
            writer = csv.writer(f)
            if write_header:
                writer.writerow(["链接", "作者", "标题", "类型", "发布时间", "下载时间"])
            writer.writerow([url, author, title, media_type, "", time.strftime("%Y-%m-%d %H:%M:%S")])
    except Exception as e:
        print(f"[DY] Warning: _record_history failed: {e}")


def _get_ab():
    global _ab
    if _ab is None:
        _ab = _ABogus(_PC_UA)
    return _ab


class _ABogus:
    """ABogus 签名算法（内联自 TikTokDownloader/src/encrypt/aBogus.py）"""
    __filter = re.compile(r"%([0-9A-F]{2})")
    __arguments = [0, 1, 14]
    __ua_key = "\u0000\u0001\u000e"
    __end_string = "cus"
    __version = [1, 0, 1, 5]
    __browser = "1536|742|1536|864|0|0|0|0|1536|864|1536|864|1536|742|24|24|Win32"
    __reg = [1937774191, 1226093241, 388252375, 3666478592, 2842636476, 372324522, 3817729613, 2969243214]
    __str = {
        "s0": "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=",
        "s1": "Dkdpgh4ZKsQB80/Mfvw36XI1R25+WUAlEi7NLboqYTOPuzmFjJnryx9HVGcaStCe=",
        "s2": "Dkdpgh4ZKsQB80/Mfvw36XI1R25-WUAlEi7NLboqYTOPuzmFjJnryx9HVGcaStCe=",
        "s3": "ckdp1h4ZKsUB80/Mfvw36XIgR25+WQAlEi7NLboqYTOPuzmFjJnryx9HVGDaStCe",
        "s4": "Dkdpgh2ZmsQB80/MfvV36XI1R45-WUAlEixNLwoqYTOPuzKFjJnry79HbGcaStCe",
    }

    def __init__(self, user_agent, platform=None):
        self.chunk = []
        self.size = 0
        self.reg = self.__reg[:]
        self.ua_code = self.generate_ua_code(user_agent)
        self.browser = self.generate_browser_info(platform) if platform else self.__browser
        self.browser_len = len(self.browser)
        self.browser_code = self.char_code_at(self.browser)

    @classmethod
    def list_1(cls, random_num=None, a=170, b=85, c=45):
        return cls.random_list(random_num, a, b, 1, 2, 5, c & a)

    @classmethod
    def list_2(cls, random_num=None, a=170, b=85):
        return cls.random_list(random_num, a, b, 1, 0, 0, 0)

    @classmethod
    def list_3(cls, random_num=None, a=170, b=85):
        return cls.random_list(random_num, a, b, 1, 0, 5, 0)

    @staticmethod
    def random_list(a=None, b=170, c=85, d=0, e=0, f=0, g=0):
        from random import random as _rand
        r = a or (_rand() * 10000)
        v = [r, int(r) & 255, int(r) >> 8]
        v.append(v[1] & b | d)
        v.append(v[1] & c | e)
        v.append(v[2] & b | f)
        v.append(v[2] & c | g)
        return v[-4:]

    @staticmethod
    def from_char_code(*args):
        return "".join(chr(code) for code in args)

    @classmethod
    def generate_string_1(cls, random_num_1=None, random_num_2=None, random_num_3=None):
        return (cls.from_char_code(*cls.list_1(random_num_1))
                + cls.from_char_code(*cls.list_2(random_num_2))
                + cls.from_char_code(*cls.list_3(random_num_3)))

    def generate_string_2(self, url_params, method="GET", start_time=0, end_time=0):
        a = self.generate_string_2_list(url_params, method, start_time, end_time)
        e = self.end_check_num(a)
        a.extend(self.browser_code)
        a.append(e)
        return self.rc4_encrypt(self.from_char_code(*a), "y")

    def generate_ua_code(self, user_agent):
        u = self.rc4_encrypt(user_agent, self.__ua_key)
        u = self.generate_result(u, "s3")
        return self.sum(u)

    def generate_string_2_list(self, url_params, method="GET", start_time=0, end_time=0):
        from random import randint
        from time import time
        start_time = start_time or int(time() * 1000)
        end_time = end_time or (start_time + randint(4, 8))
        params_array = self.generate_params_code(url_params)
        method_array = self.generate_method_code(method)
        return self.list_4(
            (end_time >> 24) & 255, params_array[21], self.ua_code[23],
            (end_time >> 16) & 255, params_array[22], self.ua_code[24],
            (end_time >> 8) & 255, (end_time >> 0) & 255,
            (start_time >> 24) & 255, (start_time >> 16) & 255,
            (start_time >> 8) & 255, (start_time >> 0) & 255,
            method_array[21], method_array[22],
            int(end_time / 256 / 256 / 256 / 256) >> 0,
            int(start_time / 256 / 256 / 256 / 256) >> 0,
            self.browser_len)

    @staticmethod
    def reg_to_array(a):
        o = [0] * 32
        for i in range(8):
            c = a[i]
            o[4*i+3] = 255 & c; c >>= 8
            o[4*i+2] = 255 & c; c >>= 8
            o[4*i+1] = 255 & c; c >>= 8
            o[4*i] = 255 & c
        return o

    def compress(self, a):
        f = self.generate_f(a)
        i = self.reg[:]
        for o in range(64):
            c = self.de(i[0], 12) + i[4] + self.de(self.pe(o), o)
            c = c & 0xFFFFFFFF
            c = self.de(c, 7)
            s = (c ^ self.de(i[0], 12)) & 0xFFFFFFFF
            u = self.he(o, i[0], i[1], i[2])
            u = (u + i[3] + s + f[o + 68]) & 0xFFFFFFFF
            b = self.ve(o, i[4], i[5], i[6])
            b = (b + i[7] + c + f[o]) & 0xFFFFFFFF
            i[3] = i[2]; i[2] = self.de(i[1], 9); i[1] = i[0]; i[0] = u
            i[7] = i[6]; i[6] = self.de(i[5], 19); i[5] = i[4]
            i[4] = (b ^ self.de(b, 9) ^ self.de(b, 17)) & 0xFFFFFFFF
        for l in range(8):
            self.reg[l] = (self.reg[l] ^ i[l]) & 0xFFFFFFFF

    @classmethod
    def generate_f(cls, e):
        r = [0] * 132
        for t in range(16):
            r[t] = ((e[4*t] << 24) | (e[4*t+1] << 16) | (e[4*t+2] << 8) | e[4*t+3]) & 0xFFFFFFFF
        for n in range(16, 68):
            a = r[n-16] ^ r[n-9] ^ cls.de(r[n-3], 15)
            a = a ^ cls.de(a, 15) ^ cls.de(a, 23)
            r[n] = (a ^ cls.de(r[n-13], 7) ^ r[n-6]) & 0xFFFFFFFF
        for n in range(68, 132):
            r[n] = (r[n-68] ^ r[n-64]) & 0xFFFFFFFF
        return r

    @staticmethod
    def pad_array(arr, length=60):
        while len(arr) < length:
            arr.append(0)
        return arr

    def fill(self, length=60):
        size = 8 * self.size
        self.chunk.append(128)
        self.chunk = self.pad_array(self.chunk, length)
        for i in range(4):
            self.chunk.append((size >> 8 * (3 - i)) & 255)

    @staticmethod
    def list_4(a, b, c, d, e, f, g, h, i, j, k, m, n, o, p, q, r):
        return [44,a,0,0,0,0,24,b,n,0,c,d,0,0,0,1,0,239,e,o,f,g,0,0,0,0,h,0,0,14,i,j,0,k,m,3,p,1,q,1,r,0,0,0]

    @staticmethod
    def end_check_num(a):
        r = 0
        for i in a:
            r ^= i
        return r

    @staticmethod
    def replace_func(match):
        return chr(int(match.group(1), 16))

    @staticmethod
    def de(e, r):
        r %= 32
        return ((e << r) & 0xFFFFFFFF) | (e >> (32 - r))

    @staticmethod
    def pe(e):
        return 2043430169 if 0 <= e < 16 else 2055708042

    @staticmethod
    def he(e, r, t, n):
        if 0 <= e < 16:
            return (r ^ t ^ n) & 0xFFFFFFFF
        return (r & t | r & n | t & n) & 0xFFFFFFFF

    @staticmethod
    def ve(e, r, t, n):
        if 0 <= e < 16:
            return (r ^ t ^ n) & 0xFFFFFFFF
        return (r & t | ~r & n) & 0xFFFFFFFF

    @staticmethod
    def char_code_at(s):
        return [ord(char) for char in s]

    def write(self, e):
        self.size = len(e)
        if isinstance(e, str):
            e = self.__filter.sub(self.replace_func, e)
            e = self.char_code_at(e)
        if len(e) <= 64:
            self.chunk = e
        else:
            chunks = [e[i:i+64] for i in range(0, len(e), 64)]
            for c in chunks[:-1]:
                self.compress(c)
            self.chunk = chunks[-1]

    def reset(self):
        self.chunk = []
        self.size = 0
        self.reg = self.__reg[:]

    def sum(self, e, length=60):
        self.reset()
        self.write(e)
        self.fill(length)
        self.compress(self.chunk)
        return self.reg_to_array(self.reg)

    @classmethod
    def generate_result(cls, s, e="s4"):
        r = []
        for i in range(0, len(s), 3):
            if i + 2 < len(s):
                n = (ord(s[i]) << 16) | (ord(s[i+1]) << 8) | ord(s[i+2])
            elif i + 1 < len(s):
                n = (ord(s[i]) << 16) | (ord(s[i+1]) << 8)
            else:
                n = ord(s[i]) << 16
            for j, k in zip(range(18, -1, -6), (0xFC0000, 0x03F000, 0x0FC0, 0x3F)):
                if j == 6 and i + 1 >= len(s):
                    break
                if j == 0 and i + 2 >= len(s):
                    break
                r.append(cls.__str[e][(n & k) >> j])
        r.append("=" * ((4 - len(r) % 4) % 4))
        return "".join(r)

    def generate_method_code(self, method="GET"):
        return self.sm3_to_array(self.sm3_to_array(method + self.__end_string))

    def generate_params_code(self, params):
        return self.sm3_to_array(self.sm3_to_array(params + self.__end_string))

    @classmethod
    def sm3_to_array(cls, data):
        from gmssl import func, sm3
        if isinstance(data, str):
            b = data.encode("utf-8")
        else:
            b = bytes(data)
        h = sm3.sm3_hash(func.bytes_to_list(b))
        return [int(h[i:i+2], 16) for i in range(0, len(h), 2)]

    @classmethod
    def generate_browser_info(cls, platform="Win32"):
        from random import randint, choice
        iw = randint(1280, 1920); ih = randint(720, 1080)
        ow = randint(iw, 1920); oh = randint(ih, 1080)
        sy = choice((0, 30))
        return "|".join(str(i) for i in [iw,ih,ow,oh,0,sy,0,0,ow,oh,ow,oh,iw,ih,24,24,platform])

    @staticmethod
    def rc4_encrypt(plaintext, key):
        s = list(range(256))
        j = 0
        for i in range(256):
            j = (j + s[i] + ord(key[i % len(key)])) % 256
            s[i], s[j] = s[j], s[i]
        i = j = 0
        cipher = []
        for k in range(len(plaintext)):
            i = (i + 1) % 256
            j = (j + s[i]) % 256
            s[i], s[j] = s[j], s[i]
            cipher.append(chr(s[(s[i] + s[j]) % 256] ^ ord(plaintext[k])))
        return "".join(cipher)

    def get_value(self, url_params, method="GET", start_time=0, end_time=0,
                  random_num_1=None, random_num_2=None, random_num_3=None):
        string_1 = self.generate_string_1(random_num_1, random_num_2, random_num_3)
        string_2 = self.generate_string_2(
            urlencode(url_params, quote_via=quote) if isinstance(url_params, dict) else url_params,
            method, start_time, end_time)
        return self.generate_result(string_1 + string_2, "s4")


def _extract_live_room(resp_json: dict) -> dict | None:
    """从直播 API 响应中提取 room 信息，对齐 dy_src/extract/extractor.py"""
    data = resp_json.get("data", {})
    if not data:
        return None

    room = None
    room_data = data.get("data", [])
    if isinstance(room_data, list) and room_data:
        room = room_data[0]
    elif isinstance(room_data, dict) and room_data:
        room = room_data

    if not room or not isinstance(room, dict):
        room = data.get("room", {})

    # 如果 room 没有 stream_url，继续尝试其他路径
    if not room.get("stream_url"):
        if data.get("stream_url"):
            room = data
        elif data.get("room", {}).get("stream_url"):
            room = data["room"]
        elif data.get("user", {}).get("room", {}).get("stream_url"):
            room = data["user"]["room"]

    return room if room and isinstance(room, dict) else None


def _sign_params(params: dict, method: str = "GET") -> str:
    """对齐 template.py deal_url_params: 确保 msToken 在最后, urlencode 后追加 a_bogus"""
    # 对齐 __generate_params: 将 msToken 移到最后
    params["msToken"] = params.pop("msToken")
    ab = _get_ab()
    params_str = urlencode(params, safe="=", quote_via=quote)
    params_str += f"&a_bogus={ab.get_value(params_str, method)}"
    return params_str


def _download_douyin(link: str, download_path: str, task_id: str = "") -> dict:
    """
    抖音下载流程:
    1. 跟踪短链重定向，提取 aweme_id
    2. 调用 Web API 获取作品详情
    3. 提取视频/图集下载地址并下载
    """
    import httpx

    cookie = _ensure_cookie_str(_config.get("cookie", ""))
    proxy = _config.get("proxy") or None

    print(f"[DY] Starting download: link={link[:80]}")
    print(f"[DY] Cookie present: {bool(cookie)}, length: {len(cookie)}")

    # 对齐 internal.py DATA_HEADERS
    headers = {
        "Accept": "*/*",
        "Accept-Encoding": "*/*",
        "Referer": _REFERER,
        "User-Agent": _PC_UA,
    }
    if cookie:
        headers["Cookie"] = cookie

    with httpx.Client(
        headers=headers,
        follow_redirects=True,
        timeout=30.0,
        proxy=proxy,
    ) as client:
        # === Step 1: 解析链接获取 aweme_id ===
        aweme_id = _extract_aweme_id(client, link)
        print(f"[DY] Extracted aweme_id: {aweme_id}")
        if not aweme_id:
            return {"success": False, "title": link,
                    "message": "无法从链接中提取作品ID，请检查链接是否正确"}

        # === Step 2: 调用 API 获取作品详情 ===
        detail = _fetch_detail(client, aweme_id)
        if not detail or "_error" in detail:
            err = detail.get("_error", "") if detail else ""
            cookie_dict = _cookie_str_to_dict(_ensure_cookie_str(_config.get("cookie", "")))
            has_odin = "odin_tt" in cookie_dict
            print(f"[DY] Detail fetch FAILED: {err}")
            print(f"[DY] Cookie keys: {list(cookie_dict.keys())[:10]}")
            return {"success": False, "title": f"作品 {aweme_id}",
                    "message": f"获取作品详情失败\n{err}\nCookie状态: {len(cookie_dict)}个字段, odin_tt={'\u2713' if has_odin else '\u2717 缺失'}"}

        # === Step 3: 提取下载地址并下载===
        aweme_type = detail.get("aweme_type", 0)
        has_images = bool(detail.get("images"))
        has_video = bool(detail.get("video", {}).get("bit_rate") or detail.get("video", {}).get("play_addr"))
        print(f"[DY] Detail OK: aweme_type={aweme_type}, has_images={has_images}, has_video={has_video}, desc={detail.get('desc', '')[:50]}")
        return _download_content(client, detail, download_path, task_id=task_id)


def _extract_aweme_id(client, link: str) -> str:
    """从各种格式的抖音链接中提取 aweme_id"""
    print(f"[DY] Extracting aweme_id from: {link[:100]}")

    # 直接是19位数字ID
    m = re.search(r'\b(\d{19})\b', link)
    if m:
        print(f"[DY] Found 19-digit ID directly: {m.group(1)}")
        return m.group(1)

    # 是标准链接：/video/xxx 或 /note/xxx
    m = re.search(r'douyin\.com/(?:video|note|slides)/(\d{19})', link)
    if m:
        print(f"[DY] Found ID in standard URL: {m.group(1)}")
        return m.group(1)

    # 短链 v.douyin.com 需要跟踪重定向
    try:
        print(f"[DY] Following redirect for short link...")
        resp = client.get(link)
        final_url = str(resp.url)
        print(f"[DY] Redirect result: status={resp.status_code}, url={final_url[:120]}")
        # 跟踪后的 URL 可能是 /video/xxx 格式
        m = re.search(r'/(?:video|note|slides)/(\d{19})', final_url)
        if m:
            return m.group(1)
        # 也可能在页面内容中
        m = re.search(r'"aweme_id"\s*:\s*"(\d{19})"', resp.text)
        if m:
            return m.group(1)
        # modal_id 参数
        m = re.search(r'modal_id=(\d{19})', final_url)
        if m:
            return m.group(1)
        print(f"[DY] Could not extract ID from redirected URL or page content (page length={len(resp.text)})")
    except Exception as e:
        print(f"[DY] Redirect failed: {e}")
    return ""


def _fetch_detail(client, aweme_id: str) -> dict:
    """调用抖音 Web API 获取作品详情（对齐 detail.py）"""
    api_url = "https://www.douyin.com/aweme/v1/web/aweme/detail/"
    params = dict(_DOUYIN_PARAMS)
    params["aweme_id"] = aweme_id
    # detail.py 覆盖的版本号
    params["version_code"] = "190500"
    params["version_name"] = "19.5.0"

    # msToken
    params["msToken"] = _get_real_ms_token()

    try:
        signed = _sign_params(params, "GET")
        print(f"[DY] API request: aweme_id={aweme_id}")
        resp = client.get(f"{api_url}?{signed}")
        print(f"[DY] API response: status={resp.status_code}, length={len(resp.content)}")
        if resp.status_code != 200:
            resp_text = resp.text[:500]
            print(f"[DY] API error body: {resp_text}")
            return {"_error": f"API返回HTTP {resp.status_code}\n{resp_text}"}
        content = resp.text
        if not content or not content.strip():
            print(f"[DY] API returned empty body, status={resp.status_code}")
            return {"_error": f"API返回空响应 (HTTP {resp.status_code})，可能需要设置有效Cookie"}
        data = json.loads(content)
        detail = data.get("aweme_detail")
        if not detail:
            status = data.get("status_code", "unknown")
            msg = data.get("status_msg", "")
            # 打印原始响应 keys 辅助诊断
            print(f"[DY] API no aweme_detail: status_code={status}, msg={msg}, keys={list(data.keys())}")
            return {"_error": f"API未返回作品详情 (status_code={status}, msg={msg})"}
        print(f"[DY] API detail OK: aweme_type={detail.get('aweme_type')}, has_images={bool(detail.get('images'))}, has_video_bit_rate={bool(detail.get('video', {}).get('bit_rate'))}")
        return detail
    except Exception as e:
        print(f"[DY] API exception: {e}")
        return {"_error": f"API请求异常: {str(e)}\n{traceback.format_exc()}"}


def _download_content(client, detail: dict, download_path: str, task_id: str = "") -> dict:
    """根据作品详情下载视频或图集"""
    desc = detail.get("desc", "未知作品")
    # 提取作者昵称
    author = detail.get("author", {})
    nickname = author.get("nickname", "")
    # 文件名格式
    name_with_author = _config.get("name_with_author", True)
    if name_with_author and nickname:
        raw_name = f"{nickname}_{desc}"
    else:
        raw_name = desc
    safe_name = re.sub(r'[\\/:*?"<>|\n\r]', '_', raw_name).strip(' ._')
    # 按 UTF-8 字节数截断文件名，Android 文件系统限制 255 字节
    safe_name = _truncate_filename(safe_name, 80)
    if not safe_name:
        safe_name = detail.get("aweme_id", "download")

    # 按作者建文件夹（始终开启，UI已移除）
    if nickname:
        safe_author = re.sub(r'[\\/:*?"<>|\n\r]', '_', nickname).strip(' ._')
        if safe_author:
            download_path = os.path.join(download_path, safe_author)
            os.makedirs(download_path, exist_ok=True)
    else:
        # 不按作者分时，按类型分文件夹
        images = detail.get("images")
        if images and isinstance(images, list):
            download_path = os.path.join(download_path, "images")
        else:
            download_path = os.path.join(download_path, "videos")
        os.makedirs(download_path, exist_ok=True)

    # 获取发布时间（用于保留时间戳）
    create_time = detail.get("create_time", 0)

    # 图集类型 (aweme_type == 68 或有 images 字段)
    images = detail.get("images")
    if images and isinstance(images, list):
        result = _download_images(client, images, safe_name, download_path, task_id=task_id, create_time=create_time, desc=desc, author=nickname)
        if result.get("success"):
            result["author"] = nickname
            result["create_time"] = create_time
            # record_history handled by Kotlin DownloadHistoryManager
        return result

    # 视频类型（对齐 extractor.py __extract_video_download）
    video = detail.get("video", {})

    # 优先从 bit_rate 提取最高画质（与参考项目完全一致）
    bit_rate = video.get("bit_rate", [])
    video_url = ""
    print(f"[DY] Video extraction: bit_rate_count={len(bit_rate)}, play_addr_urls={len(video.get('play_addr', {}).get('url_list', []))}")
    if bit_rate:
        try:
            br_list = []
            for item in bit_rate:
                pa = item.get("play_addr", {})
                br_list.append((
                    item.get("FPS", 0),
                    item.get("bit_rate", 0),
                    pa.get("data_size", 0),
                    pa.get("height", 0),
                    pa.get("width", 0),
                    pa.get("url_list", []),
                ))
            br_list.sort(key=lambda x: (max(x[3], x[4]), x[0], x[1], x[2]))
            if br_list and br_list[-1][-1]:
                # VIDEO_INDEX = -1（取 url_list 最后一个）
                video_url = br_list[-1][-1][-1]
                best = br_list[-1]
                print(f"[DY] Best quality: FPS={best[0]}, bitrate={best[1]}, size={best[2]}, {best[3]}x{best[4]}, urls={len(best[5])}")
            else:
                print(f"[DY] bit_rate parsed but empty or no urls: {len(br_list)} entries")
        except Exception as e:
            print(f"[DY] bit_rate parse error: {e}")

    # 回退: play_addr
    if not video_url:
        play_addr = video.get("play_addr", {})
        url_list = play_addr.get("url_list", [])
        print(f"[DY] Fallback to play_addr: {len(url_list)} urls")
        if url_list:
            video_url = url_list[-1]

    if not video_url:
        return {"success": False, "title": desc,
                "message": "未找到视频下载地址"}

    return _download_file(client, video_url, safe_name, download_path, ".mp4", task_id=task_id, create_time=create_time, author=nickname, desc=desc)


def _download_images(client, images: list, name: str, download_path: str, task_id: str = "", create_time: int = 0, desc: str = "", author: str = "") -> dict:
    """下载图集/实况作品（对齐 extractor.py __extract_image_info + __classify_slides_item）"""
    count = 0
    total = len(images)
    saved_files = []
    print(f"[DY] Downloading images/slides: {total} items")
    for i, img in enumerate(images):
        if is_task_paused(task_id):
            return {"success": False, "paused": True, "title": desc or name,
                    "message": f"已暂停 ({count}/{total})"}

        saved = False
        # 动图/实况：image 项含有 video 字段，先尝试下载动图
        video_in_img = img.get("video")
        if video_in_img:
            print(f"[DY] Item {i+1}/{total}: animated/live type, trying video first")
            dl_url = _extract_best_video_url(video_in_img)
            if dl_url:
                saved = _try_download_to_file(client, dl_url, download_path, f"{name}_{i+1}.mp4")
                if saved:
                    saved_files.append(os.path.join(download_path, f"{name}_{i+1}.mp4"))
                    print(f"[DY] Item {i+1} animated saved as mp4")
                else:
                    print(f"[DY] Item {i+1} animated download empty/failed, fallback to static")

        # 静态图片（或动图下载失败后的回退）
        if not saved:
            url_list = img.get("url_list", [])
            if not url_list:
                print(f"[DY] Item {i+1}/{total}: no url_list, skipping")
                _report_progress(task_id, count, total, f"{name} ({count}/{total})")
                continue
            img_url = url_list[-1]  # 最高质量
            try:
                resp = client.get(img_url, headers=_DOWNLOAD_HEADERS)
                if resp.status_code in (200, 206) and len(resp.content) > 0:
                    ext = ".webp" if "webp" in img_url else ".jpeg"
                    file_path = os.path.join(download_path, f"{name}_{i+1}{ext}")
                    with open(file_path, "wb") as f:
                        f.write(resp.content)
                    saved = True
                    saved_files.append(file_path)
                    print(f"[DY] Item {i+1} static image saved: {len(resp.content)} bytes")
                else:
                    print(f"[DY] Item {i+1} static image HTTP {resp.status_code}, size={len(resp.content)}")
            except Exception as e:
                print(f"[DY] Item {i+1} static image download error: {e}")

        if saved:
            count += 1
        _report_progress(task_id, count, total, f"{name} ({count}/{total})")

    # 保留发布时间
    if _config.get("keep_mtime") and create_time and saved_files:
        for fp in saved_files:
            try:
                os.utime(fp, (create_time, create_time))
            except Exception:
                pass

    if count > 0:
        return {"success": True, "title": desc or name,
                "message": f"图集已保存: {count}/{total} 个文件"}
    return {"success": False, "title": desc or name, "message": f"图集下载失败: 0/{total} 个文件，请检查日志"}


def _extract_best_video_url(video_info: dict) -> str:
    """从 video 字段提取最高画质视频 URL"""
    bit_rate = video_info.get("bit_rate", [])
    if bit_rate:
        try:
            br_list = []
            for item in bit_rate:
                pa = item.get("play_addr", {})
                br_list.append((
                    item.get("FPS", 0),
                    item.get("bit_rate", 0),
                    pa.get("data_size", 0),
                    pa.get("height", 0),
                    pa.get("width", 0),
                    pa.get("url_list", []),
                ))
            br_list.sort(key=lambda x: (max(x[3], x[4]), x[0], x[1], x[2]))
            if br_list and br_list[-1][-1]:
                return br_list[-1][-1][-1]
        except Exception as e:
            print(f"[DY] bit_rate parse error: {e}")
    # 回退 play_addr
    play_addr = video_info.get("play_addr", {})
    url_list = play_addr.get("url_list", [])
    if url_list:
        return url_list[-1]
    return ""


def _try_download_to_file(client, url: str, download_path: str, filename: str) -> bool:
    """尝试下载文件，如果内容为空则删除并返回 False"""
    file_path = os.path.join(download_path, filename)
    try:
        resp = client.stream("GET", url, headers=_DOWNLOAD_HEADERS).__enter__()
        try:
            if resp.status_code not in (200, 206):
                return False
            downloaded = 0
            with open(file_path, "wb") as f:
                for chunk in resp.iter_bytes(chunk_size=65536):
                    f.write(chunk)
                    downloaded += len(chunk)
            if downloaded == 0:
                os.remove(file_path)
                return False
            return True
        finally:
            resp.close()
    except Exception as e:
        print(f"[DY] _try_download_to_file error: {e}")
        if os.path.exists(file_path):
            try:
                os.remove(file_path)
            except Exception:
                pass
        return False


def _download_file(client, url: str, name: str, download_path: str, ext: str, task_id: str = "", create_time: int = 0, author: str = "", desc: str = "") -> dict:
    """流式下载文件（对齐 download.py，使用 DOWNLOAD_HEADERS）"""
    try:
        # 报告开始下载的标题
        _report_progress(task_id, 0, 0, desc or name)
        with client.stream("GET", url, headers=_DOWNLOAD_HEADERS) as resp:
            if resp.status_code not in (200, 206):
                return {"success": False, "title": desc or name,
                        "message": f"下载失败: HTTP {resp.status_code}"}
            # 从 Content-Length 获取总大小
            total = int(resp.headers.get("content-length", 0))
            downloaded = 0
            last_reported = 0
            file_path = os.path.join(download_path, f"{name}{ext}")
            paused = False
            with open(file_path, "wb") as f:
                for chunk in resp.iter_bytes(chunk_size=65536):
                    if is_task_paused(task_id):
                        paused = True
                        break
                    f.write(chunk)
                    downloaded += len(chunk)
                    if downloaded - last_reported >= _progress_interval:
                        _report_progress(task_id, downloaded, total, desc or name)
                        last_reported = downloaded
            if paused:
                return {"success": False, "paused": True, "title": desc or name,
                        "message": "已暂停"}
            # 最后报告完成进度
            _report_progress(task_id, downloaded, total, desc or name)
            # 保留发布时间
            if _config.get("keep_mtime") and create_time:
                try:
                    os.utime(file_path, (create_time, create_time))
                except Exception:
                    pass
            # record_history handled by Kotlin DownloadHistoryManager
            size_mb = downloaded / (1024 * 1024)
            return {"success": True, "title": desc or name, "author": author, "create_time": create_time,
                    "message": f"已保存: {file_path} ({size_mb:.1f}MB)"}
    except Exception as e:
        return {"success": False, "title": desc or name,
                "message": f"下载失败: {str(e)}"}


# ── 收藏夹功能──

def list_collect_folders(download_path: str = "") -> str:
    """
    获取当前账号的收藏夹列表。
    返回 JSON 字符串: {"success": bool, "folders": [{"id": str, "name": str, "count": int}, ...], "message": str}
    对齐原工具 collects.py Collects 类
    """
    try:
        import httpx
        import string
        import random

        cookie = _ensure_cookie_str(_config.get("cookie", ""))
        if not cookie:
            return json.dumps({"success": False, "folders": [],
                               "message": "请先登录获取 Cookie"})

        proxy = _config.get("proxy") or None
        # 对齐 internal.py DATA_HEADERS（GET 请求不带 Content-Type）
        headers = {
            "Accept": "*/*",
            "Accept-Encoding": "*/*",
            "Referer": _REFERER,
            "User-Agent": _PC_UA,
            "Cookie": cookie,
        }

        with httpx.Client(
            headers=headers,
            follow_redirects=True,
            timeout=30.0,
            proxy=proxy,
        ) as client:
            # 对齐 collects.py Collects
            api_url = "https://www.douyin.com/aweme/v1/web/collects/list/"
            params = dict(_DOUYIN_PARAMS)
            # 对齐原工具: count=10, cursor=0（整数）
            params["count"] = 10
            params["cursor"] = 0
            params["version_code"] = "170400"
            params["version_name"] = "17.4.0"
            # msToken 需放最后（对齐 __generate_params 的 pop+re-add）
            params["msToken"] = _get_real_ms_token()

            signed = _sign_params(params, "GET")
            resp = client.get(
                f"{api_url}?{signed}",
                headers={
                    "Referer": "https://www.douyin.com/user/self?showTab=favorite_collection",
                },
            )
            if resp.status_code != 200:
                return json.dumps({"success": False, "folders": [],
                                   "message": f"请求失败: HTTP {resp.status_code}\n{resp.text[:500]}"})

            data = resp.json()
            collect_list = data.get("collects_list", [])

            if not collect_list:
                return json.dumps({"success": False, "folders": [],
                                   "message": "没有找到收藏夹，可能Cookie无效或没有收藏内容\n"
                                              "请确保已登录且进入过[我的]->[收藏夹]页面"})

            folders = []
            for item in collect_list:
                folders.append({
                    "id": str(item.get("collects_id", "")),
                    "name": item.get("collects_name", "未命名"),
                    "count": item.get("total_count", item.get("aweme_count", 0)),
                })

            return json.dumps({"success": True, "folders": folders, "message": ""})

    except Exception as e:
        return json.dumps({"success": False, "folders": [],
                           "message": f"获取收藏夹列表失败: {str(e)}\n{traceback.format_exc()}"})


def batch_download_collect(collect_id: str, collect_name: str, download_path: str, task_id: str = "") -> dict:
    """
    下载指定收藏夹的所有作品。
    Args:
        collect_id: 收藏夹 ID
        collect_name: 收藏夹名称（用于显示）
        download_path: 下载目录
    """
    try:
        import httpx
        import string
        import random

        folder_path = os.path.join(download_path, re.sub(r'[\\/:*?"<>|\n\r]', '_', collect_name))
        os.makedirs(folder_path, exist_ok=True)

        cookie = _ensure_cookie_str(_config.get("cookie", ""))
        if not cookie:
            return {"success": False, "title": collect_name,
                    "message": "请先登录获取 Cookie"}

        proxy = _config.get("proxy") or None
        # 对齐 internal.py DATA_HEADERS
        headers = {
            "Accept": "*/*",
            "Accept-Encoding": "*/*",
            "Referer": _REFERER,
            "User-Agent": _PC_UA,
            "Cookie": cookie,
        }

        with httpx.Client(
            headers=headers,
            follow_redirects=True,
            timeout=30.0,
            proxy=proxy,
        ) as client:
            cursor = 0
            total = 0
            success_count = 0
            fail_count = 0
            max_pages = 100

            for _ in range(max_pages):
                # 对齐 collects.py CollectsDetail
                api_url = "https://www.douyin.com/aweme/v1/web/collects/video/list/"
                params = dict(_DOUYIN_PARAMS)
                params["collects_id"] = collect_id
                params["count"] = 10
                params["cursor"] = cursor
                params["version_code"] = "170400"
                params["version_name"] = "17.4.0"
                params["msToken"] = _get_real_ms_token()

                try:
                    signed = _sign_params(params, "GET")
                    resp = client.get(
                        f"{api_url}?{signed}",
                        headers={
                            "Referer": "https://www.douyin.com/user/self?showTab=favorite_collection",
                        },
                    )
                    if resp.status_code != 200:
                        break
                    data = resp.json()
                except Exception:
                    break

                items = data.get("aweme_list", [])
                if not items:
                    break

                for item in items:
                    total += 1
                    try:
                        result = _download_content(client, item, folder_path, task_id=task_id)
                        if result.get("success"):
                            success_count += 1
                        else:
                            fail_count += 1
                        _report_progress(task_id, success_count + fail_count, 0,
                                         f"{collect_name} ({success_count + fail_count}/{total})")
                    except Exception:
                        fail_count += 1

                cursor = data.get("cursor", 0)
                has_more = data.get("has_more", 0) == 1
                if not has_more:
                    break

            if total == 0:
                return {"success": False, "title": collect_name,
                        "message": "该收藏夹为空或获取失败"}

            return {"success": True, "title": collect_name,
                    "message": f"共 {total} 个作品，成功 {success_count}，失败 {fail_count}"}

    except Exception as e:
        return {"success": False, "title": collect_name,
                "message": f"下载失败: {str(e)}"}


# ── 从作品链接检测账号/合集信息 ──

def detect_link_info(link: str) -> str:
    """
    从任意作品链接中解析出账号信息和合集信息。
    返回 JSON: {
        "success": bool,
        "author": {"uid": str, "sec_uid": str, "nickname": str, "unique_id": str} | null,
        "mix": {"mix_id": str, "mix_name": str, "count": int} | null,
        "title": str,
        "message": str
    }
    """
    try:
        import httpx
        cookie = _ensure_cookie_str(_config.get("cookie", ""))
        proxy = _config.get("proxy") or None
        headers = {
            "Accept": "*/*",
            "Accept-Encoding": "*/*",
            "Referer": _REFERER,
            "User-Agent": _PC_UA,
        }
        if cookie:
            headers["Cookie"] = cookie

        with httpx.Client(
            headers=headers,
            follow_redirects=True,
            timeout=30.0,
            proxy=proxy,
        ) as client:
            aweme_id = _extract_aweme_id(client, link)
            if not aweme_id:
                return json.dumps({"success": False, "author": None, "mix": None,
                                   "title": "", "message": "无法从链接中提取作品ID"})

            detail = _fetch_detail(client, aweme_id)
            if not detail:
                return json.dumps({"success": False, "author": None, "mix": None,
                                   "title": "", "message": "获取作品详情失败，请检查Cookie"})

            desc = detail.get("desc", "")
            result = {"success": True, "author": None, "mix": None, "title": desc, "message": ""}

            # 提取账号信息
            author = detail.get("author", {})
            if author:
                result["author"] = {
                    "uid": str(author.get("uid", "")),
                    "sec_uid": author.get("sec_uid", ""),
                    "nickname": author.get("nickname", "未知用户"),
                    "unique_id": author.get("unique_id", ""),
                }

            # 提取合集信息 (mix_info)
            mix_info = detail.get("mix_info", {})
            if mix_info and mix_info.get("mix_id"):
                statis = mix_info.get("statis", {})
                result["mix"] = {
                    "mix_id": str(mix_info.get("mix_id", "")),
                    "mix_name": mix_info.get("mix_name", "未知合集"),
                    "count": statis.get("current_episode", 0),
                }

            return json.dumps(result, ensure_ascii=False)

    except Exception as e:
        return json.dumps({"success": False, "author": None, "mix": None,
                           "title": "", "message": f"检测失败: {str(e)}"})


def batch_download_account(sec_uid: str, nickname: str, download_path: str, task_id: str = "") -> dict:
    """
    批量下载指定账号的所有作品。
    对齐 account.py AccountTikTok 的 post API
    """
    try:
        import httpx
        import string
        import random

        folder_path = os.path.join(download_path, re.sub(r'[\\/:*?"<>|\n\r]', '_', nickname))
        os.makedirs(folder_path, exist_ok=True)

        cookie = _ensure_cookie_str(_config.get("cookie", ""))
        if not cookie:
            return {"success": False, "title": nickname,
                    "message": "请先登录获取 Cookie"}
        proxy = _config.get("proxy") or None
        headers = {
            "Accept": "*/*",
            "Accept-Encoding": "*/*",
            "Referer": _REFERER,
            "User-Agent": _PC_UA,
            "Cookie": cookie,
        }

        with httpx.Client(
            headers=headers,
            follow_redirects=True,
            timeout=30.0,
            proxy=proxy,
        ) as client:
            cursor = 0
            total = 0
            success_count = 0
            fail_count = 0
            max_pages = 200

            for _ in range(max_pages):
                api_url = "https://www.douyin.com/aweme/v1/web/aweme/post/"
                params = dict(_DOUYIN_PARAMS)
                params["sec_user_id"] = sec_uid
                params["count"] = 18
                params["max_cursor"] = cursor
                params["version_code"] = "170400"
                params["version_name"] = "17.4.0"
                params["msToken"] = _get_real_ms_token()

                try:
                    signed = _sign_params(params, "GET")
                    resp = client.get(f"{api_url}?{signed}")
                    if resp.status_code != 200:
                        break
                    data = resp.json()
                except Exception:
                    break

                items = data.get("aweme_list", [])
                if not items:
                    break

                for item in items:
                    total += 1
                    try:
                        result = _download_content(client, item, folder_path, task_id=task_id)
                        if result.get("success"):
                            success_count += 1
                        else:
                            fail_count += 1
                        _report_progress(task_id, success_count + fail_count, 0,
                                         f"{nickname} ({success_count + fail_count}/{total})")
                    except Exception:
                        fail_count += 1

                cursor = data.get("max_cursor", 0)
                has_more = data.get("has_more", 0) == 1
                if not has_more:
                    break

            if total == 0:
                return {"success": False, "title": nickname,
                        "message": "该账号没有作品或获取失败"}

            return {"success": True, "title": nickname,
                    "message": f"共 {total} 个作品，成功 {success_count}，失败 {fail_count}"}

    except Exception as e:
        return {"success": False, "title": nickname,
                "message": f"下载失败: {str(e)}"}


def list_account_works(sec_uid: str) -> str:
    """列出账号所有作品（不下载），返回 JSON 列表"""
    try:
        import httpx
        cookie = _ensure_cookie_str(_config.get("cookie", ""))
        if not cookie:
            return json.dumps({"success": False, "message": "请先设置 Cookie", "works": []})
        proxy = _config.get("proxy") or None
        headers = {
            "Accept": "*/*", "Accept-Encoding": "*/*",
            "Referer": _REFERER, "User-Agent": _PC_UA, "Cookie": cookie,
        }
        works = []
        with httpx.Client(headers=headers, follow_redirects=True, timeout=30.0, proxy=proxy) as client:
            cursor = 0
            for _ in range(50):
                api_url = "https://www.douyin.com/aweme/v1/web/aweme/post/"
                params = dict(_DOUYIN_PARAMS)
                params["sec_user_id"] = sec_uid
                params["count"] = 18
                params["max_cursor"] = cursor
                params["version_code"] = "170400"
                params["version_name"] = "17.4.0"
                params["msToken"] = _get_real_ms_token()
                try:
                    signed = _sign_params(params, "GET")
                    resp = client.get(f"{api_url}?{signed}")
                    if resp.status_code != 200:
                        break
                    data = resp.json()
                except Exception:
                    break
                items = data.get("aweme_list", [])
                if not items:
                    break
                for item in items:
                    desc = item.get("desc", "无标题")
                    aweme_id = str(item.get("aweme_id", ""))
                    aweme_type = item.get("aweme_type", 0)
                    type_name = "图集" if aweme_type in [2, 68] else "视频"
                    stats = item.get("statistics", {})
                    likes = stats.get("digg_count", 0)
                    comments = stats.get("comment_count", 0)
                    works.append({
                        "id": aweme_id,
                        "title": desc[:60],
                        "type": type_name,
                        "likes": likes,
                        "comments": comments,
                        "link": f"https://www.douyin.com/video/{aweme_id}"
                    })
                cursor = data.get("max_cursor", 0)
                if data.get("has_more", 0) != 1:
                    break
        return json.dumps({"success": True, "works": works, "count": len(works)})
    except Exception as e:
        return json.dumps({"success": False, "message": str(e), "works": []})


def list_xhs_user_works(user_id: str) -> str:
    """列出小红书用户所有作品（不下载），返回 JSON 列表"""
    try:
        import httpx
        cookie = _ensure_cookie_str(_config.get("cookie", ""))
        if not cookie:
            return json.dumps({"success": False, "message": "请先设置 Cookie", "works": []})
        proxy = _config.get("proxy") or None
        headers = {
            "Accept": "*/*", "Accept-Encoding": "*/*",
            "Referer": _REFERER, "User-Agent": _PC_UA, "Cookie": cookie,
        }
        works = []
        with httpx.Client(headers=headers, follow_redirects=True, timeout=30.0, proxy=proxy) as client:
            resp = client.get(f"https://www.xiaohongshu.com/user/profile/{user_id}")
            html = resp.text
            import re as _re
            note_ids = list(set(_re.findall(r'"noteId":\s*"([a-f0-9]+)"', html)))
            for nid in note_ids:
                works.append({
                    "id": nid,
                    "link": f"https://www.xiaohongshu.com/explore/{nid}"
                })
        return json.dumps({"success": True, "works": works, "count": len(works)})
    except Exception as e:
        return json.dumps({"success": False, "message": str(e), "works": []})


def batch_download_mix(mix_id: str, mix_name: str, download_path: str, task_id: str = "") -> dict:
    """
    批量下载指定合集的所有作品。
    对齐 mix.py Mix
    """
    try:
        import httpx
        import string
        import random

        folder_path = os.path.join(download_path, re.sub(r'[\\/:*?"<>|\n\r]', '_', mix_name))
        os.makedirs(folder_path, exist_ok=True)

        cookie = _ensure_cookie_str(_config.get("cookie", ""))
        if not cookie:
            return {"success": False, "title": mix_name,
                    "message": "请先登录获取 Cookie"}
        proxy = _config.get("proxy") or None
        headers = {
            "Accept": "*/*",
            "Accept-Encoding": "*/*",
            "Referer": _REFERER,
            "User-Agent": _PC_UA,
            "Cookie": cookie,
        }

        with httpx.Client(
            headers=headers,
            follow_redirects=True,
            timeout=30.0,
            proxy=proxy,
        ) as client:
            cursor = 0
            total = 0
            success_count = 0
            fail_count = 0
            max_pages = 200

            for _ in range(max_pages):
                api_url = "https://www.douyin.com/aweme/v1/web/mix/aweme/"
                params = dict(_DOUYIN_PARAMS)
                params["mix_id"] = mix_id
                params["count"] = 20
                params["cursor"] = cursor
                params["version_code"] = "170400"
                params["version_name"] = "17.4.0"
                params["msToken"] = _get_real_ms_token()

                try:
                    signed = _sign_params(params, "GET")
                    resp = client.get(f"{api_url}?{signed}")
                    if resp.status_code != 200:
                        break
                    data = resp.json()
                except Exception:
                    break

                items = data.get("aweme_list", [])
                if not items:
                    break

                for item in items:
                    total += 1
                    try:
                        result = _download_content(client, item, folder_path, task_id=task_id)
                        if result.get("success"):
                            success_count += 1
                        else:
                            fail_count += 1
                        _report_progress(task_id, success_count + fail_count, 0,
                                         f"{mix_name} ({success_count + fail_count}/{total})")
                    except Exception:
                        fail_count += 1

                cursor = data.get("cursor", 0)
                has_more = data.get("has_more", 0) == 1
                if not has_more:
                    break

            if total == 0:
                return {"success": False, "title": mix_name,
                        "message": "该合集没有作品或获取失败"}

            return {"success": True, "title": mix_name,
                    "message": f"共 {total} 个作品，成功 {success_count}，失败 {fail_count}"}

    except Exception as e:
        return {"success": False, "title": mix_name,
                "message": f"下载失败: {str(e)}"}


# ── 直播录制 ──

def record_live(live_url: str, download_path: str, task_id: str = "") -> dict:
    """
    录制抖音直播流。
    传入直播间链接，获取推流地址并录制。
    """
    try:
        import httpx
        import string
        import random
        import time

        cookie = _ensure_cookie_str(_config.get("cookie", ""))
        proxy = _config.get("proxy") or None
        headers = {
            "Accept": "*/*",
            "Accept-Encoding": "*/*",
            "Referer": _REFERER,
            "User-Agent": _PC_UA,
        }
        if cookie:
            headers["Cookie"] = cookie

        with httpx.Client(
            headers=headers,
            follow_redirects=True,
            timeout=30.0,
            proxy=proxy,
        ) as client:
            # 解析直播间链接获取 room_id / web_rid
            web_rid = ""
            # 从文本中先提取 URL
            url_m = re.search(r'https?://[^\s<>"{}|\\^`\[\]]+', live_url, re.IGNORECASE)
            actual_url = url_m.group() if url_m else live_url

            # 标准直播链接格式: live.douyin.com/xxx
            m = re.search(r'live\.douyin\.com/(\d+)', actual_url)
            if m:
                web_rid = m.group(1)
            # 关注列表直播: douyin.com/follow/live/xxx
            if not web_rid:
                m = re.search(r'douyin\.com/follow/live/(\d+)', actual_url)
                if m:
                    web_rid = m.group(1)
            if not web_rid:
                # 短链跳转 (v.douyin.com 等)
                try:
                    resp = client.get(actual_url)
                    final_url = str(resp.url)
                    # 也检查页面内容中的 room_id
                    for pattern in [
                        r'live\.douyin\.com/(\d+)',
                        r'douyin\.com/follow/live/(\d+)',
                        r'webcast\.amemv\.com/.*?/(\d+)',
                        r'"web_rid"\s*:\s*"(\d+)"',
                        r'"roomId"\s*:\s*"(\d+)"',
                        r'"room_id"\s*:\s*"?(\d+)',
                    ]:
                        m = re.search(pattern, final_url)
                        if m:
                            web_rid = m.group(1)
                            break
                    if not web_rid:
                        # 在页面内容中搜索
                        for pattern in [
                            r'"web_rid"\s*:\s*"(\d+)"',
                            r'"roomId"\s*:\s*"(\d+)"',
                            r'"room_id"\s*:\s*"?(\d+)',
                        ]:
                            m = re.search(pattern, resp.text)
                            if m:
                                web_rid = m.group(1)
                                break
                except Exception as e:
                    print(f"[Live] Short link resolve failed: {e}")

            if not web_rid:
                return {"success": False, "title": live_url,
                        "message": f"无法识别直播间ID\n输入: {actual_url}\n请使用直播间分享链接"}

            # 获取直播间信息和推流地址
            # 使用直播专用参数（对齐 dy_src/interface/live.py Live.with_web_rid）
            api_url = "https://live.douyin.com/webcast/room/web/enter/"
            chars = string.ascii_letters + string.digits
            live_params = {
                "aid": "6383",
                "app_name": "douyin_web",
                "live_id": "1",
                "device_platform": "web",
                "language": "zh-CN",
                "enter_from": "web_share_link",
                "cookie_enabled": "true",
                "screen_width": "1536",
                "screen_height": "864",
                "browser_language": "zh-CN",
                "browser_platform": "Win32",
                "browser_name": "Edge",
                "browser_version": "139.0.0.0",
                "web_rid": web_rid,
                "enter_source": "",
                "is_need_double_stream": "false",
                "insert_task_id": "",
                "live_reason": "",
                "msToken": _get_real_ms_token(),
            }

            # 直播 API 需要 live.douyin.com referer
            live_headers = dict(headers)
            live_headers["Referer"] = "https://live.douyin.com/"

            room = None
            resp_json = {}

            # 策略1: 不签名直接请求（直播 API 通常不需要 ABogus）
            print(f"[Live] Trying web_rid API without ABogus for {web_rid}")
            try:
                resp = client.get(api_url, params=live_params, headers=live_headers)
                print(f"[Live] Response: HTTP {resp.status_code}")
                if resp.status_code == 200:
                    resp_json = resp.json()
                    room = _extract_live_room(resp_json)
            except Exception as e:
                print(f"[Live] Strategy 1 failed: {e}")

            # 策略2: 带 ABogus 签名
            if not room or room.get("status", 0) != 2:
                print(f"[Live] Trying web_rid API with ABogus")
                try:
                    signed = _sign_params(live_params, "GET")
                    resp = client.get(f"{api_url}?{signed}", headers=live_headers)
                    print(f"[Live] Signed response: HTTP {resp.status_code}")
                    if resp.status_code == 200:
                        resp_json2 = resp.json()
                        room2 = _extract_live_room(resp_json2)
                        if room2 and room2.get("status", 0) == 2:
                            room = room2
                            resp_json = resp_json2
                except Exception as e:
                    print(f"[Live] Strategy 2 failed: {e}")

            # 策略3: 备用分享页 API（webcast.amemv.com）
            if not room or room.get("status", 0) != 2:
                print(f"[Live] Trying share API (amemv)")
                try:
                    share_api = "https://webcast.amemv.com/webcast/room/reflow/info/"
                    share_params = {
                        "type_id": "0",
                        "live_id": "1",
                        "room_id": web_rid,
                        "sec_user_id": "",
                        "app_id": "1128",
                        "msToken": _get_real_ms_token(),
                    }
                    share_headers = {
                        "Accept": "*/*",
                        "User-Agent": _PC_UA,
                    }
                    if cookie:
                        share_headers["Cookie"] = cookie
                    resp = client.get(share_api, params=share_params, headers=share_headers)
                    print(f"[Live] Share API response: HTTP {resp.status_code}")
                    if resp.status_code == 200:
                        resp_json3 = resp.json()
                        data3 = resp_json3.get("data", {})
                        # 分享 API 返回格式: data 直接就是 room 信息
                        if data3.get("stream_url") or data3.get("room", {}).get("stream_url"):
                            room = data3 if data3.get("stream_url") else data3.get("room", {})
                            resp_json = resp_json3
                except Exception as e:
                    print(f"[Live] Strategy 3 failed: {e}")

            if not room or not isinstance(room, dict):
                return {"success": False, "title": f"直播间 {web_rid}",
                        "message": f"无法获取直播间信息\nAPI status_code: {resp_json.get('status_code')}\ndata keys: {list(resp_json.get('data', {}).keys())[:10]}"}

            status = room.get("status", 0)
            print(f"[Live] Final room status={status}, has stream_url={bool(room.get('stream_url'))}")
            print(f"[Live] room keys: {list(room.keys())[:15]}")

            if status != 2:
                return {"success": False, "title": f"直播间 {web_rid}",
                        "message": f"该直播间当前未开播 (status={status})\nAPI status_code: {resp_json.get('status_code')}\nroom keys: {list(room.keys())[:10]}"}


            owner = room.get("owner", {})
            nickname = owner.get("nickname", f"主播{web_rid}")
            safe_name = re.sub(r'[\\/:*?"<>|\n\r]', '_', nickname)

            # 获取推流地址
            stream_url = ""
            pull = room.get("stream_url", {})
            flv = pull.get("flv_pull_url", {})
            if flv:
                # 取最高画质
                for quality in ["FULL_HD1", "HD1", "SD1", "SD2"]:
                    if quality in flv:
                        stream_url = flv[quality]
                        break
                if not stream_url:
                    stream_url = list(flv.values())[0] if flv else ""

            if not stream_url:
                hls = pull.get("hls_pull_url_map", {})
                if hls:
                    for quality in ["FULL_HD1", "HD1", "SD1", "SD2"]:
                        if quality in hls:
                            stream_url = hls[quality]
                            break
                    if not stream_url:
                        stream_url = list(hls.values())[0] if hls else ""

            if not stream_url:
                return {"success": False, "title": nickname,
                        "message": "无法获取直播推流地址"}

            # 录制直播流
            timestamp = time.strftime("%Y%m%d_%H%M%S")
            live_path = os.path.join(download_path, "live")
            os.makedirs(live_path, exist_ok=True)
            file_path = os.path.join(live_path, f"{safe_name}_{timestamp}.flv")

            with client.stream("GET", stream_url, headers=_DOWNLOAD_HEADERS, timeout=None) as resp:
                if resp.status_code not in (200, 206):
                    return {"success": False, "title": nickname,
                            "message": f"录制失败: HTTP {resp.status_code}"}
                with open(file_path, "wb") as f:
                    recorded_bytes = 0
                    last_reported = 0
                    for chunk in resp.iter_bytes(chunk_size=65536):
                        if is_task_paused(task_id):
                            break
                        f.write(chunk)
                        recorded_bytes += len(chunk)
                        if recorded_bytes - last_reported >= _progress_interval:
                            _report_progress(task_id, recorded_bytes, 0, f"直播录制: {nickname}")
                            last_reported = recorded_bytes

            size_mb = os.path.getsize(file_path) / (1024 * 1024)
            return {"success": True, "title": nickname,
                    "message": f"直播录制完成: {size_mb:.1f}MB\n{file_path}"}

    except Exception as e:
        return {"success": False, "title": live_url,
                "message": f"直播录制失败: {str(e)}"}


# ══════════════════════════════════════════════════════════
# 新增功能: 配置更新
# ══════════════════════════════════════════════════════════

def update_config(config_json: str) -> dict:
    """从 Android 设置页面更新配置"""
    try:
        import json as json_mod
        new_config = json_mod.loads(config_json)
        for key in ("video_quality", "proxy", "folder_by_author", "name_with_author", "keep_mtime",
                     "remove_watermark", "dedup", "breakpoint", "filter_rules",
                     "file_size_limit_mb", "author_mapping", "image_format",
                     "xhs_video_quality"):
            if key in new_config:
                _config[key] = new_config[key]
        # 应用代理
        if _config.get("proxy"):
            os.environ["HTTP_PROXY"] = _config["proxy"]
            os.environ["HTTPS_PROXY"] = _config["proxy"]
        else:
            os.environ.pop("HTTP_PROXY", None)
            os.environ.pop("HTTPS_PROXY", None)
        return {"success": True}
    except Exception as e:
        return {"success": False, "message": str(e)}


# ══════════════════════════════════════════════════════════
# 新增功能: 评论采集
# ══════════════════════════════════════════════════════════

def scrape_comments(link: str, download_path: str, task_id: str = "") -> dict:
    """采集作品评论并保存为 CSV"""
    try:
        import httpx, csv, time, string, random

        if not _config.get("cookie"):
            return {"success": False, "title": link, "message": "请先设置 Cookie"}

        # 解析作品 ID
        aweme_id = _resolve_aweme_id(link)
        if not aweme_id:
            return {"success": False, "title": link, "message": "无法解析作品 ID"}

        # 获取作品详情，和下载时使用相同命名
        detail, err = _get_detail_standalone(link)
        if detail:
            desc = detail.get("desc", "")
            nickname = detail.get("author", {}).get("nickname", "")
            if nickname:
                raw_name = f"{nickname}_{desc}"
            else:
                raw_name = desc
            safe_name = re.sub(r'[\\/:*?"<>|\n\r]', '_', raw_name).strip(' ._')
            safe_name = _truncate_filename(safe_name, 80)
        else:
            safe_name = ""
        if not safe_name:
            safe_name = aweme_id

        headers = {**_API_HEADERS, "Cookie": _config["cookie"],
                   "Referer": f"https://www.douyin.com/video/{aweme_id}"}
        comments = []
        cursor = 0

        with httpx.Client(headers=headers, follow_redirects=True, timeout=30) as client:
            while True:
                url = "https://www.douyin.com/aweme/v1/web/comment/list/"
                params = dict(_DOUYIN_PARAMS)
                params.update({
                    "aweme_id": aweme_id,
                    "cursor": str(cursor),
                    "count": "20",
                    "item_type": "0",
                    "version_code": "170400",
                    "version_name": "17.4.0",
                    "msToken": _get_real_ms_token(),
                })
                signed = _sign_params(params, "GET")
                resp = client.get(f"{url}?{signed}")
                data = resp.json()

                items = data.get("comments", [])
                if not items:
                    break

                for c in items:
                    comments.append({
                        "user": c.get("user", {}).get("nickname", ""),
                        "text": c.get("text", ""),
                        "likes": c.get("digg_count", 0),
                        "time": c.get("create_time", 0),
                        "ip": c.get("ip_label", ""),
                    })

                cursor = data.get("cursor", 0)
                if not data.get("has_more", False):
                    break

                _report_progress(task_id, len(comments), 0, f"评论采集: {len(comments)} 条")
                time.sleep(0.5)

        # 保存 CSV
        if comments:
            data_path = os.path.join(download_path, "data")
            os.makedirs(data_path, exist_ok=True)
            csv_path = os.path.join(data_path, f"{safe_name}_comments.csv")
            with open(csv_path, "w", newline="", encoding="utf-8-sig") as f:
                writer = csv.DictWriter(f, fieldnames=["user", "text", "likes", "time", "ip"])
                writer.writeheader()
                writer.writerows(comments)
            return {"success": True, "title": safe_name, "message": f"采集完成: {len(comments)} 条评论\n{csv_path}"}
        else:
            return {"success": True, "title": safe_name, "message": "未找到评论"}

    except Exception as e:
        return {"success": False, "title": link, "message": f"评论采集失败: {str(e)}"}


def _resolve_aweme_id(link: str) -> str:
    """从链接中提取作品 ID (独立版本，无需 httpx client)"""
    import httpx
    # 先跟踪短链
    try:
        if "v.douyin.com" in link or "vm.tiktok" in link:
            with httpx.Client(follow_redirects=True, timeout=15) as client:
                resp = client.get(link)
                link = str(resp.url)
    except Exception:
        pass
    # 从 URL 中提取
    m = re.search(r"/video/(\d+)", link)
    if m:
        return m.group(1)
    m = re.search(r"/note/(\d+)", link)
    if m:
        return m.group(1)
    m = re.search(r"aweme_id=(\d+)", link)
    if m:
        return m.group(1)
    return ""


# ══════════════════════════════════════════════════════════
# 新增功能: 封面下载
# ══════════════════════════════════════════════════════════

def _get_detail_standalone(link: str) -> tuple:
    """独立获取作品详情 (用于封面/音频/动图/统计等附加功能)"""
    import httpx
    aweme_id = _resolve_aweme_id(link)
    if not aweme_id:
        return None, "无法解析作品 ID"
    cookie = _ensure_cookie_str(_config.get("cookie", ""))
    if not cookie:
        return None, "请先设置 Cookie"
    headers = {**_API_HEADERS, "Cookie": cookie}
    proxy = _config.get("proxy") or None
    with httpx.Client(headers=headers, follow_redirects=True, timeout=30, proxy=proxy) as client:
        detail = _fetch_detail(client, aweme_id)
    if not detail or "_error" in detail:
        err = detail.get("_error", "") if detail else "空响应"
        return None, f"获取详情失败: {err}"
    return detail, None


def download_cover(link: str, download_path: str, task_id: str = "") -> dict:
    """下载作品封面图片"""
    try:
        import httpx

        detail, err = _get_detail_standalone(link)
        if err:
            return {"success": False, "title": link, "message": err}

        desc = detail.get("desc", detail.get("aweme_id", ""))
        safe_name = _truncate_filename(re.sub(r'[\\/*?:"<>|]', '_', desc))

        # 静态封面
        cover_url = detail.get("video", {}).get("cover", {}).get("url_list", [None])[0]
        # 动态封面
        dynamic_cover = detail.get("video", {}).get("dynamic_cover", {}).get("url_list", [None])[0]

        downloaded = 0
        with httpx.Client(headers=_DOWNLOAD_HEADERS, follow_redirects=True, timeout=30) as client:
            if cover_url:
                cover_path = os.path.join(download_path, f"{safe_name}_cover.jpg")
                resp = client.get(cover_url)
                with open(cover_path, "wb") as f:
                    f.write(resp.content)
                downloaded += 1

            if dynamic_cover:
                dyn_path = os.path.join(download_path, f"{safe_name}_dynamic_cover.webp")
                resp = client.get(dynamic_cover)
                with open(dyn_path, "wb") as f:
                    f.write(resp.content)
                downloaded += 1

        return {"success": True, "title": desc, "message": f"封面下载完成: {downloaded} 个文件"}

    except Exception as e:
        return {"success": False, "title": link, "message": f"封面下载失败: {str(e)}"}


# ══════════════════════════════════════════════════════════
# 新增功能: 音频提取
# ══════════════════════════════════════════════════════════

def extract_audio(link: str, download_path: str, task_id: str = "") -> dict:
    """提取作品中的背景音乐/原声"""
    try:
        import httpx

        detail, err = _get_detail_standalone(link)
        if err:
            return {"success": False, "title": link, "message": err}

        music = detail.get("music", {})
        music_title = music.get("title", "未知音乐")
        author = music.get("author", "未知")
        play_url = music.get("play_url", {}).get("url_list", [None])[0]

        if not play_url:
            return {"success": False, "title": music_title, "message": "未找到音频链接"}

        safe_name = _truncate_filename(re.sub(r'[\\/*?:"<>|]', '_', f"{music_title}-{author}"))
        audio_path = os.path.join(download_path, f"{safe_name}.mp3")

        with httpx.Client(headers=_DOWNLOAD_HEADERS, follow_redirects=True, timeout=60) as client:
            resp = client.get(play_url)
            with open(audio_path, "wb") as f:
                f.write(resp.content)

        size_kb = os.path.getsize(audio_path) / 1024
        return {"success": True, "title": music_title,
                "message": f"音频提取完成: {music_title} - {author} ({size_kb:.0f}KB)"}

    except Exception as e:
        return {"success": False, "title": link, "message": f"音频提取失败: {str(e)}"}


# ══════════════════════════════════════════════════════════
# 新增功能: 动图/实况照片下载
# ══════════════════════════════════════════════════════════

def download_livephoto(link: str, download_path: str, task_id: str = "") -> dict:
    """下载作品的动态封面/实况照片"""
    try:
        import httpx

        detail, err = _get_detail_standalone(link)
        if err:
            return {"success": False, "title": link, "message": err}

        desc = detail.get("desc", detail.get("aweme_id", ""))
        safe_name = _truncate_filename(re.sub(r'[\\/*?:"<>|]', '_', desc))

        # 图集中的动图
        images = detail.get("images", [])
        downloaded = 0

        with httpx.Client(headers=_DOWNLOAD_HEADERS, follow_redirects=True, timeout=60) as client:
            for i, img in enumerate(images):
                # 尝试获取动图 URL
                urls = img.get("video", {}).get("play_addr", {}).get("url_list", [])
                if not urls:
                    urls = img.get("url_list", [])
                if urls:
                    ext = ".mp4" if "video" in img else ".webp"
                    file_path = os.path.join(download_path, f"{safe_name}_livephoto_{i+1}{ext}")
                    resp = client.get(urls[0])
                    with open(file_path, "wb") as f:
                        f.write(resp.content)
                    downloaded += 1
                _report_progress(task_id, i + 1, len(images), f"动图: {desc}")

        if downloaded == 0:
            # fallback: 下载动态封面
            dyn = detail.get("video", {}).get("dynamic_cover", {}).get("url_list", [])
            if dyn:
                file_path = os.path.join(download_path, f"{safe_name}_dynamic.webp")
                with httpx.Client(headers=_DOWNLOAD_HEADERS, follow_redirects=True) as client:
                    resp = client.get(dyn[0])
                    with open(file_path, "wb") as f:
                        f.write(resp.content)
                downloaded = 1

        return {"success": True, "title": desc,
                "message": f"动图下载完成: {downloaded} 个文件"}

    except Exception as e:
        return {"success": False, "title": link, "message": f"动图下载失败: {str(e)}"}


# ══════════════════════════════════════════════════════════
# 新增功能: 数据统计
# ══════════════════════════════════════════════════════════

def get_data_stats(link: str) -> str:
    """获取作品的数据统计信息 (返回 JSON 字符串)"""
    import json as _json
    try:
        detail, err = _get_detail_standalone(link)
        if err:
            return _json.dumps({"success": False, "message": err}, ensure_ascii=False)

        stats = detail.get("statistics", {})
        author = detail.get("author", {}).get("nickname", "未知")
        desc = detail.get("desc", "")

        return _json.dumps({
            "success": True,
            "title": desc,
            "author": author,
            "stats": {
                "likes": str(stats.get("digg_count", 0)),
                "comments": str(stats.get("comment_count", 0)),
                "shares": str(stats.get("share_count", 0)),
                "plays": str(stats.get("play_count", 0)),
                "collects": str(stats.get("collect_count", 0)),
            }
        }, ensure_ascii=False)

    except Exception as e:
        return _json.dumps({"success": False, "message": f"获取统计失败: {str(e)}"}, ensure_ascii=False)


def batch_download_music(download_path: str) -> str:
    """批量下载收藏音乐"""
    import json as _json2
    try:
        if not _config.get("cookie"):
            return _json2.dumps({"success": False, "message": "请先设置Cookie"}, ensure_ascii=False)

        headers = {**_API_HEADERS, "Cookie": _config["cookie"],
                   "Referer": "https://www.douyin.com/"}
        music_list = []
        cursor = 0
        downloaded = 0

        with httpx.Client(headers=headers, follow_redirects=True, timeout=30) as client:
            # 获取收藏音乐列表
            while True:
                params = dict(_DOUYIN_PARAMS)
                params.update({
                    "cursor": str(cursor),
                    "count": "20",
                    "msToken": _get_real_ms_token(),
                })
                url = "https://www.douyin.com/aweme/v1/web/music/listcollect/"
                resp = client.get(url, params=params)
                data = resp.json()
                items = data.get("music_list", [])
                if not items:
                    break
                music_list.extend(items)
                if not data.get("has_more", False):
                    break
                cursor = data.get("cursor", cursor + 20)

            if not music_list:
                return _json2.dumps({"success": False, "message": "没有找到收藏的音乐"}, ensure_ascii=False)

            # 下载音乐文件
            os.makedirs(download_path, exist_ok=True)
            music_dir = os.path.join(download_path, "收藏音乐")
            os.makedirs(music_dir, exist_ok=True)

            for music in music_list:
                try:
                    title = music.get("title", "unknown")
                    author = music.get("author", "unknown")
                    play_url = music.get("play_url", {}).get("uri", "")
                    if not play_url:
                        continue
                    safe_name = re.sub(r'[\\/:*?"<>|\n\r]', '_', f"{author}_{title}").strip(' ._')
                    safe_name = _truncate_filename(safe_name, 80)
                    filepath = os.path.join(music_dir, f"{safe_name}.mp3")
                    if os.path.exists(filepath):
                        downloaded += 1
                        continue
                    resp = client.get(play_url)
                    if resp.status_code == 200:
                        with open(filepath, "wb") as f:
                            f.write(resp.content)
                        downloaded += 1
                except Exception:
                    continue

        return _json2.dumps({
            "success": True,
            "message": f"下载完成: {downloaded}/{len(music_list)} 首音乐"
        }, ensure_ascii=False)

    except Exception as e:
        return _json2.dumps({"success": False, "message": f"下载失败: {str(e)}"}, ensure_ascii=False)


def search_scrape(keyword: str, download_path: str) -> str:
    """搜索关键词并采集结果数据"""
    import json as _json2
    import httpx
    try:
        headers = {**_API_HEADERS, "Cookie": _config.get("cookie", ""),
                   "Referer": "https://www.douyin.com/search/" + keyword}

        results = []
        offset = 0

        with httpx.Client(headers=headers, follow_redirects=True, timeout=30) as client:
            for _ in range(5):  # 最多采集5页
                params = dict(_DOUYIN_PARAMS)
                params.update({
                    "keyword": keyword,
                    "search_channel": "aweme_general",
                    "offset": str(offset),
                    "count": "20",
                    "search_source": "normal_search",
                    "query_correct_type": "1",
                    "is_filter_search": "0",
                    "msToken": _get_real_ms_token(),
                })
                url = "https://www.douyin.com/aweme/v1/web/general/search/single/"
                resp = client.get(url, params=params)
                data = resp.json()
                items = data.get("data", [])
                if not items:
                    break
                for item in items:
                    aweme = item.get("aweme_info", {})
                    if not aweme:
                        continue
                    results.append({
                        "desc": aweme.get("desc", ""),
                        "author": aweme.get("author", {}).get("nickname", ""),
                        "likes": aweme.get("statistics", {}).get("digg_count", 0),
                        "comments": aweme.get("statistics", {}).get("comment_count", 0),
                        "shares": aweme.get("statistics", {}).get("share_count", 0),
                    })
                if not data.get("has_more", False):
                    break
                offset += 20

        if not results:
            return _json2.dumps({"success": False, "message": "未搜索到结果"}, ensure_ascii=False)

        # 保存结果到CSV
        os.makedirs(download_path, exist_ok=True)
        safe_keyword = re.sub(r'[\\/:*?"<>|\n\r]', '_', keyword)
        csv_path = os.path.join(download_path, f"搜索_{safe_keyword}.csv")
        with open(csv_path, "w", encoding="utf-8-sig") as f:
            f.write("描述,作者,点赞,评论,分享\n")
            for r in results:
                desc = r["desc"].replace(",", " ").replace("\n", " ")[:50]
                f.write(f'{desc},{r["author"]},{r["likes"]},{r["comments"]},{r["shares"]}\n')

        return _json2.dumps({
            "success": True,
            "message": f"采集完成: {len(results)} 条结果，已保存到 {os.path.basename(csv_path)}"
        }, ensure_ascii=False)

    except Exception as e:
        return _json2.dumps({"success": False, "message": f"搜索采集失败: {str(e)}"}, ensure_ascii=False)


def get_hot_list() -> str:
    """获取抖音热榜数据"""
    import json as _json2
    import httpx
    try:
        headers = {**_API_HEADERS, "Cookie": _config.get("cookie", ""),
                   "Referer": "https://www.douyin.com/hot"}

        with httpx.Client(headers=headers, follow_redirects=True, timeout=30) as client:
            params = dict(_DOUYIN_PARAMS)
            params.update({
                "msToken": _get_real_ms_token(),
            })
            url = "https://www.douyin.com/aweme/v1/web/hot/search/list/"
            resp = client.get(url, params=params)
            data = resp.json()

            word_list = data.get("data", {}).get("word_list", [])
            if not word_list:
                return _json2.dumps({"success": False, "message": "获取热榜数据失败"}, ensure_ascii=False)

            items = []
            for word in word_list[:50]:
                items.append({
                    "title": word.get("word", ""),
                    "hot_value": str(word.get("hot_value", 0)),
                })

        return _json2.dumps({"success": True, "items": items}, ensure_ascii=False)

    except Exception as e:
        return _json2.dumps({"success": False, "message": f"获取热榜失败: {str(e)}"}, ensure_ascii=False)


# Initialize config on import
_load_config()
