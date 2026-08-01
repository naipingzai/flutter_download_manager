"""
XHS (小红书/Xiaohongshu) Bridge for DyDownload Android App
Isolated from Douyin bridge.py, shares only the Python environment and progress reporting.
Uses xhs_src (adapted from XHS-Downloader) for core data extraction.
"""
import os
import json
import re
import traceback
from typing import Union
from urllib.parse import urlparse

import httpx
from yaml import safe_load

# 复用 dy_bridge.py 的进度回调机制和暂停控制
from dy_bridge import _report_progress, is_task_paused, _truncate_filename


# ── HTML 解析器（内联自 xhs_src/expansion/converter.py）──
class _Converter:
    """从小红书页面 HTML 中提取笔记 JSON 数据"""
    _YAML_ILLEGAL = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]")
    _INITIAL_STATE = "//script/text()"
    _PC_KEYS = ("note", "noteDetailMap", "[-1]", "note")
    _PHONE_KEYS = ("noteData", "data", "noteData")

    def run(self, content: str) -> dict:
        extracted = self._extract(content)
        if not extracted:
            return {}
        parsed = self._parse(extracted)
        if not parsed:
            return {}
        result = self._filter(parsed)
        print(f"[XHS] Converter.run: extracted_len={len(extracted)}, parsed_keys={list(parsed.keys())[:5] if isinstance(parsed, dict) else type(parsed).__name__}, filtered_keys={list(result.keys())[:5] if result else 'empty'}")
        return result

    def _extract(self, html: str) -> str:
        if not html:
            return ""
        # 方法1：从 script 标签提取
        matches = re.findall(r'<script[^>]*>(.*?)</script>', html, re.DOTALL)
        matches.reverse()
        result = next((s.strip() for s in matches if s.strip().startswith("window.__INITIAL_STATE__")), "")
        if result:
            print(f"[XHS] _extract: method1 found, len={len(result)}")
            return result
        # 方法2：直接搜索 window.__INITIAL_STATE__
        m = re.search(r'window\.__INITIAL_STATE__\s*=\s*', html)
        if m:
            start = m.end()
            snippet = html[start:start + 200000]
            end = snippet.find('</script>')
            if end > 0:
                result = "window.__INITIAL_STATE__=" + snippet[:end].strip()
            else:
                result = "window.__INITIAL_STATE__=" + snippet.strip()
            print(f"[XHS] _extract: method2 found, len={len(result)}")
            return result
        # 方法3：搜索带引号的格式 window.__INITIAL_STATE__ = "..."
        m = re.search(r'window\.__INITIAL_STATE__\s*=\s*["\']', html)
        if m:
            print(f"[XHS] _extract: method3 found quoted format at pos {m.start()}")
        print(f"[XHS] _extract: all methods failed, html_len={len(html)}")
        # 打印包含 INITIAL_STATE 的上下文
        idx = html.find('__INITIAL_STATE__')
        if idx >= 0:
            print(f"[XHS] _extract: found __INITIAL_STATE__ at pos {idx}, context: {html[idx-20:idx+100]}")
        else:
            print(f"[XHS] _extract: __INITIAL_STATE__ not found in HTML at all")
        return ""

    def _parse(self, text: str) -> dict:
        cleaned = self._YAML_ILLEGAL.sub("", text.lstrip("window.__INITIAL_STATE__="))
        # 替换 JS 特殊值为 YAML 兼容格式
        cleaned = cleaned.replace(': undefined', ': null')
        cleaned = cleaned.replace(':undefined', ': null')
        try:
            return safe_load(cleaned)
        except Exception as e:
            print(f"[XHS] _parse: YAML failed: {e}")
            print(f"[XHS] _parse: cleaned[:200]={cleaned[:200]}")
            # 尝试用 JSON 解析（有些格式是 JSON）
            try:
                import json as _json
                return _json.loads(cleaned)
            except Exception:
                pass
            return {}

    def _filter(self, data: dict) -> dict:
        return self._deep_get(data, self._PHONE_KEYS) or self._deep_get(data, self._PC_KEYS) or {}

    @staticmethod
    def _deep_get(data, keys, default=None):
        if not data:
            return default
        try:
            for key in keys:
                if key.startswith("[") and key.endswith("]"):
                    idx = int(key[1:-1])
                    data = list(data.values())[idx] if isinstance(data, dict) else data[idx]
                else:
                    data = data[key]
            return data
        except (KeyError, IndexError, ValueError, TypeError):
            return default


_converter = _Converter()

# ── XHS 配置 ──
_xhs_config = {
    "cookie": "",
    "proxy": "",
    "download_path": "",
    "image_format": "png",
}

# ── XHS 常量（对齐 XHS-Downloader/source/module/static.py）──
_XHS_UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36 Edg/143.0.0.0"
)
_XHS_HEADERS = {
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7",
    "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
    "Referer": "https://www.xiaohongshu.com/explore",
    "User-Agent": _XHS_UA,
}
_XHS_DOWNLOAD_HEADERS = {
    "Accept": "*/*",
    "Referer": "https://www.xiaohongshu.com/",
    "User-Agent": _XHS_UA,
}

# ── URL 匹配模式（对齐 app.py）──
_LINK_RE = re.compile(r"(?:https?://)?www\.xiaohongshu\.com/explore/\S+")
_SHARE_RE = re.compile(r"(?:https?://)?www\.xiaohongshu\.com/discovery/item/\S+")
_SHORT_RE = re.compile(
    r"(?:https?://)?xhslink\.com/[^\s\"<>\\^`{|}\uFF0C\u3002\uFF1B\uFF01\uFF1F\u3001\u3010\u3011\u300A\u300B]+"
)
_ID_RE = re.compile(r"(?:explore|item)/([a-zA-Z0-9]+)")


# ── 配置持久化──
def _config_path():
    home = os.environ.get("HOME", "/data/data/com.advancedownloader")
    return os.path.join(home, "Volume", "xhs_settings.json")


def _save_config():
    try:
        path = _config_path()
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            json.dump(_xhs_config, f, ensure_ascii=False, indent=2)
    except Exception as e:
        print(f"[XHS] Warning: _save_config failed: {e}")


def pause_task(task_id: str) -> bool:
    """Signal a running task to pause."""
    from dy_bridge import pause_task as _dy_pause
    return _dy_pause(task_id)


def resume_task(task_id: str) -> bool:
    """Clear pause signal for a task."""
    from dy_bridge import resume_task as _dy_resume
    return _dy_resume(task_id)


def _load_config():
    try:
        path = _config_path()
        if os.path.exists(path):
            with open(path, "r", encoding="utf-8") as f:
                _xhs_config.update(json.load(f))
            print(f"[XHS] Config loaded, cookie length={len(_xhs_config.get('cookie', ''))}")
        else:
            print(f"[XHS] Config file not found: {path}")
    except Exception as e:
        print(f"[XHS] Warning: _load_config failed: {e}")


# ── 公开 API（供 Kotlin XhsPythonBridge 调用）──

def set_cookie(cookie: str):
    """设置小红书 Cookie"""
    clean = cookie.strip()
    _xhs_config["cookie"] = clean
    _save_config()
    print(f"[XHS] set_cookie: length={len(clean)}, has_a1={'a1=' in clean}, has_web_session={'web_session=' in clean}")
    return json.dumps({"success": True, "cookie_length": len(clean)})


def get_cookie_status() -> str:
    cookie = _xhs_config.get("cookie", "")
    if not cookie:
        return json.dumps({"has_cookie": False})
    return json.dumps({"has_cookie": True, "cookie_length": len(cookie)})


def set_proxy(proxy: str):
    _xhs_config["proxy"] = proxy.strip()
    _save_config()


def set_download_path(path: str):
    _xhs_config["download_path"] = path
    _save_config()


def diagnose_cookie() -> str:
    """诊断 Cookie 状态，返回详细 JSON 信息"""
    home = os.environ.get("HOME", "(unset)")
    path = _config_path()
    cookie = _xhs_config.get("cookie", "")
    result = {
        "home": home,
        "config_path": path,
        "config_exists": os.path.exists(path),
        "config_dir_exists": os.path.exists(os.path.dirname(path)),
        "cookie_in_memory": bool(cookie),
        "cookie_length": len(cookie),
        "has_a1": "a1=" in cookie,
        "has_web_session": "web_session=" in cookie,
        "has_webId": "webId=" in cookie,
    }
    # 尝试写入测试
    try:
        test_dir = os.path.dirname(path)
        os.makedirs(test_dir, exist_ok=True)
        result["dir_writable"] = True
    except Exception as e:
        result["dir_writable"] = False
        result["dir_error"] = str(e)
    return json.dumps(result, ensure_ascii=False)


def get_config():
    return json.dumps(_xhs_config)


def parse_link(link: str, download_path: str, task_id: str = "") -> dict:
    """
    解析小红书链接并下载内容。

    Args:
        link: 用户输入的小红书链接或分享文本
        download_path: 下载保存目录
        task_id: 任务 ID（用于进度回调）

    Returns:
        dict: {"success": bool, "title": str, "message": str}
    """
    try:
        _xhs_config["download_path"] = download_path
        os.makedirs(download_path, exist_ok=True)

        # 提取 URL
        url = _extract_xhs_url(link)
        if not url:
            return {"success": False, "title": link, "message": "未找到有效的小红书链接"}

        result = _download_xhs(url, download_path, task_id=task_id)
        if result.get("success"):
            _record_download_url(url, download_path)
        return result

    except Exception as e:
        return {
            "success": False,
            "title": link,
            "message": f"解析失败: {str(e)}\n{traceback.format_exc()}"
        }


def _record_download_url(url: str, download_path: str):
    """记录下载历史到 CSV 文件（写到 data/ 目录，兼容 Kotlin DownloadHistoryManager）"""
    try:
        import csv, time
        data_dir = os.path.join(download_path, "data")
        os.makedirs(data_dir, exist_ok=True)
        csv_path = os.path.join(data_dir, "download_history.csv")
        write_header = not os.path.exists(csv_path) or os.path.getsize(csv_path) == 0
        with open(csv_path, "a", newline="", encoding="utf-8-sig") as f:
            writer = csv.writer(f)
            if write_header:
                writer.writerow(["链接", "作者", "标题", "类型", "发布时间", "下载时间"])
            writer.writerow([url.strip(), "", "", "video", "", time.strftime("%Y-%m-%d %H:%M:%S")])
    except Exception as e:
        print(f"[XHS] Failed to record URL: {e}")


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
            # 兼容旧格式 txt
            history_file = os.path.join(download_path, "download_history.txt")
            if os.path.isfile(history_file):
                with open(history_file, "r", encoding="utf-8") as f:
                    urls = [line.strip() for line in f if line.strip()]
        if not urls:
            return {"success": False, "title": "重新下载", "message": "下载记录文件为空"}
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
            result = _download_xhs(url, download_path, task_id="")
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


# ── 内部实现 ──

def _extract_xhs_url(text: str) -> str:
    """从文本中提取小红书链接"""
    # 先尝试各种 URL 模式
    for pattern in (_SHORT_RE, _LINK_RE, _SHARE_RE):
        m = pattern.search(text)
        if m:
            url = m.group()
            if not url.startswith("http"):
                url = "https://" + url
            return url
    # 尝试通用 URL 提取
    m = re.search(r'https?://[^\s<>"{}|\\^`\[\]]+', text, re.IGNORECASE)
    if m and ("xiaohongshu" in m.group() or "xhslink" in m.group()):
        return m.group()
    return ""


def _resolve_short_link(client, url: str) -> str:
    """解析短链接（xhslink.com）到完整 URL"""
    try:
        resp = client.get(url, follow_redirects=True)
        final_url = str(resp.url)
        print(f"[XHS] Short link resolved: {url} -> {final_url}")
        if "xiaohongshu.com" in final_url:
            return final_url
        return url
    except Exception as e:
        print(f"[XHS] Short link resolve failed: {e}")
        return url


def _extract_note_id(url: str) -> str:
    """从 URL 中提取笔记 ID（对齐 XHS-Downloader __extract_link_id）"""
    # 优先用 urlparse 提取路径最后一段
    try:
        parsed = urlparse(url)
        path_parts = [p for p in parsed.path.split("/") if p]
        if path_parts:
            note_id = path_parts[-1]
            # 确保是有效的 ID（字母数字）
            if re.match(r'^[a-zA-Z0-9]+$', note_id):
                return note_id
    except Exception:
        pass
    # 回退：正则匹配
    m = _ID_RE.search(url)
    if m:
        return m.group(1)
    # 回退2：query 参数 note_id=
    m = re.search(r'note_id=([a-zA-Z0-9]+)', url)
    if m:
        return m.group(1)
    return ""


def _parse_initial_state(html: str) -> dict:
    """
    从 HTML 中提取 window.__INITIAL_STATE__ 数据。
    使用 xhs_src.expansion.converter.Converter（对齐 XHS-Downloader 原版逻辑）。
    """
    try:
        data = _converter.run(html)
        if data:
            print(f"[XHS] Converter extracted note data, type={data.get('type', '?')}, title={data.get('title', '?')[:30]}")
            return data
        else:
            print(f"[XHS] Converter returned empty data from HTML ({len(html)} chars)")
            # 打印 HTML 片段用于诊断
            snippet = html[:1500] if len(html) > 1500 else html
            print(f"[XHS] HTML snippet: {snippet}")
            return {}
    except Exception as e:
        print(f"[XHS] Converter error: {e}")
        print(f"[XHS] HTML length: {len(html)}")
        return {}


def _extract_content_info(note_data: dict) -> dict:
    """从笔记数据中提取标题、类型和下载地址"""
    title = note_data.get("title", "") or note_data.get("desc", "") or "未知作品"
    note_type = note_data.get("type", "")
    image_list = note_data.get("imageList", [])

    result = {
        "title": title,
        "note_type": note_type,
        "images": [],
        "video_url": "",
    }

    if note_type == "video":
        # 视频类型
        video_info = note_data.get("video", {})
        # 优先 consumer.originVideoKey
        origin_key = ""
        consumer = video_info.get("consumer", {})
        if consumer:
            origin_key = consumer.get("originVideoKey", "")
        if origin_key:
            result["video_url"] = f"https://sns-video-bd.xhscdn.com/{origin_key}"
        else:
            # 从 media.stream 中获取
            media = video_info.get("media", {})
            stream = media.get("stream", {})
            h264 = stream.get("h264", [])
            h265 = stream.get("h265", [])
            all_streams = h264 + h265
            if all_streams:
                # 按 height 排序取最高画质
                all_streams.sort(key=lambda x: x.get("height", 0))
                best = all_streams[-1]
                backup_urls = best.get("backupUrls", [])
                if backup_urls:
                    result["video_url"] = backup_urls[0]
                elif best.get("masterUrl"):
                    result["video_url"] = best["masterUrl"]

        # 视频类型如果 imageList 长度为1，仍是视频
        if len(image_list) == 1:
            result["note_type"] = "video"
    elif note_type == "normal" and image_list:
        result["note_type"] = "image"

    # 提取图片链接（每项为 dict: {"static": 静图URL, "animated": 动图URL或空}）
    for img in image_list:
        entry = {"static": "", "animated": ""}
        # 静态图：优先 urlDefault，其次 url
        img_url = img.get("urlDefault", "") or img.get("url", "")
        if img_url:
            token = _extract_image_token(img_url)
            if token:
                fmt = _xhs_config.get("image_format", "jpeg")
                entry["static"] = f"https://ci.xiaohongshu.com/{token}?imageView2/format/{fmt}"
            else:
                entry["static"] = img_url

        # 动图（live photo）
        stream_info = img.get("stream", {})
        h264_list = stream_info.get("h264", [])
        if h264_list:
            master = h264_list[0].get("masterUrl", "")
            if master:
                entry["animated"] = master

        if entry["static"] or entry["animated"]:
            result["images"].append(entry)

    return result


def _extract_image_token(url: str) -> str:
    """从图片 URL 中提取 token（对齐 Image.__extract_image_token）"""
    parts = url.split("/")
    if len(parts) > 5:
        token = "/".join(parts[5:])
        token = token.split("!")[0]
        return token
    return ""


def _download_xhs(url: str, download_path: str, task_id: str = "") -> dict:
    """小红书下载主流程"""

    cookie = _xhs_config.get("cookie", "")
    proxy = _xhs_config.get("proxy") or None

    print(f"[XHS] Starting download: url={url}")
    print(f"[XHS] Cookie present: {bool(cookie)}, length: {len(cookie)}")

    headers = dict(_XHS_HEADERS)
    if cookie:
        headers["Cookie"] = cookie

    with httpx.Client(
        headers=headers,
        follow_redirects=True,
        timeout=httpx.Timeout(connect=10.0, read=20.0, write=10.0, pool=10.0),
        verify=False,
        proxy=proxy,
    ) as client:
        # Step 1: 解析短链接
        if "xhslink.com" in url:
            url = _resolve_short_link(client, url)

        # Step 2: 提取笔记 ID
        note_id = _extract_note_id(url)
        if not note_id:
            return {"success": False, "title": url, "message": "无法提取笔记ID"}

        # 构建请求 URL
        # 优先使用原始 URL（保留 xsec_token 等安全参数）
        # 如果原始 URL 已经是 explore 或 discovery/item 格式，直接使用
        parsed = urlparse(url)
        if "xiaohongshu.com" in (parsed.netloc or ""):
            # 保留原始查询参数，只确保路径使用 explore 格式
            query = parsed.query
            if query:
                page_url = f"https://www.xiaohongshu.com/explore/{note_id}?{query}"
            else:
                page_url = f"https://www.xiaohongshu.com/explore/{note_id}"
        else:
            page_url = f"https://www.xiaohongshu.com/explore/{note_id}"
        print(f"[XHS] Request URL: {page_url}")

        # Step 3: 获取页面 HTML
        _report_progress(task_id, 0, 0, f"正在获取笔记: {note_id}")
        try:
            resp = client.get(page_url)
            final_url = str(resp.url)
            print(f"[XHS] Response status: {resp.status_code}, url: {final_url}")
            resp.raise_for_status()

            # 检测是否被重定向到 404 错误页
            if "/404" in final_url or "error_code=" in final_url:
                import urllib.parse as up
                parsed_url = up.urlparse(final_url)
                params = up.parse_qs(parsed_url.query)
                error_msg = params.get("error_msg", ["未知错误"])[0]
                error_msg = up.unquote(error_msg)
                print(f"[XHS] Redirected to 404: {error_msg}")

                # 如果带了 xsec_token 还是失败，尝试不带参数重试
                if "?" in page_url and "xsec_token" in page_url:
                    print("[XHS] Retrying without xsec_token params...")
                    clean_url = f"https://www.xiaohongshu.com/explore/{note_id}"
                    resp = client.get(clean_url)
                    final_url2 = str(resp.url)
                    if "/404" not in final_url2 and "error_code=" not in final_url2:
                        print(f"[XHS] Clean URL succeeded: {final_url2}")
                        html = resp.text
                    else:
                        return {"success": False, "title": note_id,
                                "message": f"小红书返回错误: {error_msg}\n该笔记可能已被删除或设为私密"}
                else:
                    return {"success": False, "title": note_id,
                            "message": f"小红书返回错误: {error_msg}\n该笔记可能已被删除或设为私密"}
            else:
                html = resp.text

            print(f"[XHS] HTML length: {len(html)}")
            has_state = 'window.__INITIAL_STATE__' in html
            print(f"[XHS] Has __INITIAL_STATE__: {has_state}")
        except Exception as e:
            print(f"[XHS] Request failed: {e}")
            return {"success": False, "title": note_id,
                    "message": f"获取页面失败: {str(e)}"}

        # Step 4: 解析 __INITIAL_STATE__
        note_data = _parse_initial_state(html)
        if not note_data:
            # 检查是否被重定向到登录页
            if '请先登录' in html or '登录已过期' in html:
                hint = "页面要求登录，Cookie可能已失效"
            elif 'window.__INITIAL_STATE__' not in html:
                hint = f"HTML中未找到__INITIAL_STATE__(长度{len(html)})"
            elif len(html) < 500:
                hint = f"页面内容过短({len(html)}字符)，可能被拦截"
            else:
                hint = f"Converter解析返回空数据（长度{len(html)})"
            return {"success": False, "title": note_id,
                    "message": f"解析页面数据失败: {hint}"}

        # Step 5: 提取内容信息
        info = _extract_content_info(note_data)
        title = info["title"]
        # 提取作者昵称
        user = note_data.get("user", {})
        nickname = user.get("nickname", "") or user.get("name", "")
        print(f"[XHS] Note: type={info['note_type']}, title={title}, author={nickname}, images={len(info['images'])}, video_url={bool(info['video_url'])}")
        # 文件名格式: 作者昵称_作品标题
        if nickname:
            raw_name = f"{nickname}_{title}"
        else:
            raw_name = title
        safe_name = re.sub(r'[\\/:*?"<>|\n\r]', '_', raw_name).strip(' ._')
        # 按 UTF-8 字节数截断文件名，Android 文件系统限制 255 字节
        safe_name = _truncate_filename(safe_name, 80)
        if not safe_name:
            safe_name = note_id

        # Step 6: 下载
        if info["note_type"] == "video" and info["video_url"]:
            result = _download_video(client, info["video_url"], safe_name,
                                   download_path, task_id)
            # 添加作者和发布时间信息
            if result.get("success"):
                result["author"] = nickname
                result["create_time"] = note_data.get("time", 0)
            return result
        elif info["images"]:
            result = _download_images(client, info["images"], safe_name,
                                    download_path, task_id)
            # 添加作者和发布时间信息
            if result.get("success"):
                result["author"] = nickname
                result["create_time"] = note_data.get("time", 0)
            return result
        else:
            return {"success": False, "title": safe_name,
                    "message": "未找到可下载的内容"}


def _download_video(client, url: str, name: str, download_path: str,
                    task_id: str = "") -> dict:
    """下载视频"""
    try:
        _report_progress(task_id, 0, 0, name)
        with client.stream("GET", url, headers=_XHS_DOWNLOAD_HEADERS) as resp:
            if resp.status_code not in (200, 206):
                return {"success": False, "title": name,
                        "message": f"下载失败: HTTP {resp.status_code}"}
            total = int(resp.headers.get("content-length", 0))
            downloaded = 0
            file_path = os.path.join(download_path, f"{name}.mp4")
            paused = False
            with open(file_path, "wb") as f:
                for chunk in resp.iter_bytes(chunk_size=65536):
                    if is_task_paused(task_id):
                        paused = True
                        break
                    f.write(chunk)
                    downloaded += len(chunk)
                    _report_progress(task_id, downloaded, total, name)
        if paused:
            return {"success": False, "paused": True, "title": name, "message": "已暂停"}
        return {"success": True, "title": name, "message": "视频下载成功"}
    except Exception as e:
        return {"success": False, "title": name,
                "message": f"视频下载异常: {str(e)}"}


def _download_images(client, items: list, name: str, download_path: str,
                     task_id: str = "") -> dict:
    """下载图集（每项可为 dict{static,animated} 或纯 URL 字符串）"""
    count = 0
    total = len(items)
    for i, item in enumerate(items):
        if is_task_paused(task_id):
            return {"success": False, "paused": True, "title": name,
                    "message": f"已暂停 ({count}/{total})"}

        # 兼容旧格式（纯字符串）和新格式（dict）
        if isinstance(item, dict):
            animated_url = item.get("animated", "")
            static_url = item.get("static", "")
        else:
            animated_url = ""
            static_url = item

        saved = False
        # 先尝试下载动图
        if animated_url:
            try:
                resp = client.get(animated_url, headers=_XHS_DOWNLOAD_HEADERS)
                if resp.status_code in (200, 206) and len(resp.content) > 0:
                    file_path = os.path.join(download_path, f"{name}_{i + 1}.mp4")
                    with open(file_path, "wb") as f:
                        f.write(resp.content)
                    saved = True
                    print(f"[XHS] Item {i+1} animated saved: {len(resp.content)} bytes")
                else:
                    print(f"[XHS] Item {i+1} animated empty/failed (HTTP {resp.status_code}, size={len(resp.content)}), fallback to static")
            except Exception as e:
                print(f"[XHS] Item {i+1} animated download error: {e}, fallback to static")

        # 动图下载失败或为空，回退到静图
        if not saved and static_url:
            try:
                resp = client.get(static_url, headers=_XHS_DOWNLOAD_HEADERS)
                if resp.status_code in (200, 206) and len(resp.content) > 0:
                    ct = resp.headers.get("content-type", "")
                    if "png" in ct:
                        ext = ".png"
                    elif "webp" in ct:
                        ext = ".webp"
                    else:
                        ext = ".jpeg"
                    file_path = os.path.join(download_path, f"{name}_{i + 1}{ext}")
                    with open(file_path, "wb") as f:
                        f.write(resp.content)
                    saved = True
                    print(f"[XHS] Item {i+1} static image saved: {len(resp.content)} bytes")
            except Exception as e:
                print(f"[XHS] Item {i+1} static download error: {e}")

        if saved:
            count += 1
        _report_progress(task_id, count, total, f"{name} ({count}/{total})")

    if count > 0:
        return {"success": True, "title": name,
                "message": f"图集已保存: {count}/{total} 张"}
    return {"success": False, "title": name, "message": "图集下载失败"}


# ══════════════════════════════════════════════════════════
# 新增功能: 配置更新
# ══════════════════════════════════════════════════════════

def update_config(config_json: str) -> dict:
    """从 Android 设置页面更新配置"""
    try:
        new_config = json.loads(config_json)
        for key in ("image_format", "xhs_video_quality", "proxy", "folder_by_author",
                     "keep_mtime", "remove_watermark", "dedup", "breakpoint",
                     "file_size_limit_mb", "author_mapping", "video_quality", "filter_rules"):
            if key in new_config:
                _xhs_config[key] = new_config[key]
        # 应用代理
        if _xhs_config.get("proxy"):
            os.environ["HTTP_PROXY"] = _xhs_config["proxy"]
            os.environ["HTTPS_PROXY"] = _xhs_config["proxy"]
        else:
            os.environ.pop("HTTP_PROXY", None)
            os.environ.pop("HTTPS_PROXY", None)
        return {"success": True}
    except Exception as e:
        return {"success": False, "message": str(e)}


# ══════════════════════════════════════════════════════════
# 新增功能: 检测用户信息
# ══════════════════════════════════════════════════════════

def detect_user_info(link: str) -> dict:
    """从链接中检测用户信息"""
    try:
        if not _xhs_config.get("cookie"):
            return {"success": False, "message": "请先设置 Cookie"}

        # 从分享文本中提取 URL，解析短链接
        url = _extract_xhs_url(link)
        if not url:
            url = link
        if "xhslink.com" in url:
            headers = {**_XHS_HEADERS, "Cookie": _xhs_config["cookie"]}
            with httpx.Client(headers=headers, follow_redirects=True, timeout=15) as client:
                url = _resolve_short_link(client, url)

        # 优先检查是否为用户主页链接
        user_id = _extract_user_id(url)
        if not user_id:
            # 可能是笔记链接，从笔记中获取用户
            note_id = _extract_note_id(url)
            if not note_id:
                return {"success": False, "message": "无法从链接中识别用户信息"}
            user_id = _get_user_from_note(note_id, url)
            if not user_id:
                return {"success": False, "message": "无法获取用户信息"}

        # 获取用户详情
        headers = {**_XHS_HEADERS, "Cookie": _xhs_config["cookie"]}
        user_url = f"https://www.xiaohongshu.com/user/profile/{user_id}"

        with httpx.Client(headers=headers, follow_redirects=True, timeout=30) as client:
            resp = client.get(user_url)
            html = resp.text

        # 解析用户信息
        nickname = "未知用户"
        note_count = 0
        m = re.search(r'"nickname":\s*"([^"]+)"', html)
        if m:
            nickname = m.group(1)
        m = re.search(r'"noteCount":\s*(\d+)', html)
        if m:
            note_count = int(m.group(1))

        return {
            "success": True,
            "user_id": user_id,
            "nickname": nickname,
            "note_count": note_count,
        }

    except Exception as e:
        return {"success": False, "message": f"检测失败: {str(e)}"}


def detect_note_info(link: str) -> str:
    """从链接中解析笔记基本信息（不下载），返回 JSON"""
    try:
        note_id = _extract_note_id(link)
        if not note_id:
            return json.dumps({"success": False, "message": "无法识别笔记链接"})

        if not _xhs_config.get("cookie"):
            return json.dumps({"success": False, "message": "请先设置 Cookie"})

        headers = {**_XHS_HEADERS, "Cookie": _xhs_config["cookie"]}
        with httpx.Client(headers=headers, follow_redirects=True, timeout=30) as client:
            resp = client.get(f"https://www.xiaohongshu.com/explore/{note_id}")
            html = resp.text

        nickname = ""
        title = ""
        note_type = ""
        m = re.search(r'"nickname":\s*"([^"]+)"', html)
        if m:
            nickname = m.group(1)
        m = re.search(r'"title":\s*"([^"]*)"', html)
        if m:
            title = m.group(1)
        m = re.search(r'"type":\s*"(video|normal)"', html)
        if m:
            note_type = "视频" if m.group(1) == "video" else "图文"

        return json.dumps({
            "success": True,
            "title": title or "未知笔记",
            "nickname": nickname,
            "type": note_type,
        }, ensure_ascii=False)
    except Exception as e:
        return json.dumps({"success": False, "message": f"解析失败: {str(e)}"})


def _extract_user_id(link: str) -> str:
    """从链接提取用户 ID"""
    m = re.search(r"/user/profile/([a-fA-F0-9]+)", link)
    if m:
        return m.group(1)
    return ""


def _get_user_from_note(note_id: str, original_url: str = "") -> str:
    """通过笔记 ID 获取作者的用户 ID"""
    try:
        headers = {**_XHS_HEADERS, "Cookie": _xhs_config["cookie"]}

        # 方法1：用 XHS feed API 获取笔记详情（不需要 xsec_token）
        api_url = "https://edith.xiaohongshu.com/api/sns/web/v1/feed"
        api_headers = {
            **headers,
            "Content-Type": "application/json",
            "Origin": "https://www.xiaohongshu.com",
        }
        payload = {"source_note_id": note_id, "image_formats": ["jpg", "webp", "avif"]}
        try:
            with httpx.Client(headers=api_headers, follow_redirects=True, timeout=15, verify=False) as client:
                resp = client.post(api_url, json=payload)
                data = resp.json()
                print(f"[XHS] _get_user_from_note: feed API status={resp.status_code}, code={data.get('code')}")
                if data.get("code") == 0 and data.get("data"):
                    items = data["data"].get("items", [])
                    if items:
                        note_card = items[0].get("note_card", {})
                        user = note_card.get("user", {})
                        uid = user.get("user_id", "") or user.get("userId", "")
                        print(f"[XHS] _get_user_from_note: API user_id={uid}, nickname={user.get('nickname')}")
                        if uid:
                            return uid
        except Exception as e:
            print(f"[XHS] _get_user_from_note: feed API failed: {e}")

        # 方法2：请求 explore 页面，保留 xsec_token
        if original_url:
            parsed_url = urlparse(original_url)
            query = parsed_url.query
            if query:
                page_url = f"https://www.xiaohongshu.com/explore/{note_id}?{query}"
            else:
                page_url = f"https://www.xiaohongshu.com/explore/{note_id}"
        else:
            page_url = f"https://www.xiaohongshu.com/explore/{note_id}"

        with httpx.Client(headers=headers, follow_redirects=True, timeout=30, verify=False) as client:
            resp = client.get(page_url)
            html = resp.text
        print(f"[XHS] _get_user_from_note: page status={resp.status_code}, html_len={len(html)}")

        note_data = _parse_initial_state(html)
        if note_data:
            user = note_data.get("user", {})
            if isinstance(user, dict):
                uid = user.get("userId", "") or user.get("user_id", "") or user.get("id", "")
                print(f"[XHS] _get_user_from_note: note_data.user uid={uid}")
                if uid:
                    return uid

        # 方法3：正则兜底
        m = re.search(r'"userId"\s*:\s*"([a-fA-F0-9]{20,})"', html)
        if m:
            print(f"[XHS] _get_user_from_note: regex userId={m.group(1)}")
            return m.group(1)
        m = re.search(r'/user/profile/([a-fA-F0-9]+)', html)
        if m:
            print(f"[XHS] _get_user_from_note: regex profile={m.group(1)}")
            return m.group(1)
        print(f"[XHS] _get_user_from_note: no user found")
    except Exception as e:
        print(f"[XHS] _get_user_from_note exception: {e}")
    return ""


# ══════════════════════════════════════════════════════════
# 新增功能: 批量下载用户作品
# ══════════════════════════════════════════════════════════

def batch_download_user(user_id: str, nickname: str, download_path: str, task_id: str = "") -> dict:
    """批量下载指定用户的全部笔记"""
    try:
        import time
        if not _xhs_config.get("cookie"):
            return {"success": False, "message": "请先设置 Cookie"}

        headers = {**_XHS_HEADERS, "Cookie": _xhs_config["cookie"]}
        user_url = f"https://www.xiaohongshu.com/user/profile/{user_id}"

        with httpx.Client(headers=headers, follow_redirects=True, timeout=30) as client:
            resp = client.get(user_url)
            html = resp.text

        # 从 __INITIAL_STATE__ 提取笔记列表
        note_ids = re.findall(r'"noteId"\s*:\s*"([a-fA-F0-9]+)"', html)
        note_ids = list(dict.fromkeys(note_ids))  # 去重保序

        if not note_ids:
            return {"success": False, "message": f"未找到用户 {nickname} 的笔记"}

        # 按作者建文件夹
        safe_nickname = _truncate_filename(re.sub(r'[\\/*?:"<>|]', '_', nickname))
        if _xhs_config.get("folder_by_author"):
            dl_path = os.path.join(download_path, safe_nickname)
            os.makedirs(dl_path, exist_ok=True)
        else:
            dl_path = download_path

        downloaded = 0
        total = len(note_ids)
        for i, nid in enumerate(note_ids):
            if is_task_paused(task_id):
                return {"success": False, "message": f"已暂停 ({downloaded}/{total})"}
            link = f"https://www.xiaohongshu.com/explore/{nid}"
            result = parse_link(link, dl_path, "")
            if result.get("success"):
                downloaded += 1
            _report_progress(task_id, i + 1, total, f"下载 {nickname}: {i+1}/{total}")
            time.sleep(1)  # 避免请求过快

        return {"success": True,
                "message": f"批量下载完成: {downloaded}/{total} 篇笔记"}

    except Exception as e:
        return {"success": False, "message": f"批量下载失败: {str(e)}"}


# ══════════════════════════════════════════════════════════
# 新增功能: 获取收藏列表
# ══════════════════════════════════════════════════════════

def list_collections() -> dict:
    """获取收藏夹列表"""
    try:
        if not _xhs_config.get("cookie"):
            return {"success": False, "message": "请先设置 Cookie"}

        headers = {**_XHS_HEADERS, "Cookie": _xhs_config["cookie"]}
        proxy = _xhs_config.get("proxy") or None

        with httpx.Client(headers=headers, follow_redirects=True, timeout=30, proxy=proxy) as client:
            # 先获取用户自己的 user_id
            resp = client.get("https://www.xiaohongshu.com/user/me")
            html = resp.text

            user_id = ""
            m = re.search(r'"userId"\s*:\s*"([a-fA-F0-9]+)"', html)
            if m:
                user_id = m.group(1)
            if not user_id:
                m = re.search(r'/user/profile/([a-fA-F0-9]+)', html)
                if m:
                    user_id = m.group(1)
            if not user_id:
                return {"success": False, "message": "无法获取用户ID，请重新登录"}

            # 使用 API 获取收藏夹列表
            api_url = "https://edith.xiaohongshu.com/api/sns/web/v1/user/collection/page"
            params = {"num": "20", "cursor": "", "user_id": user_id}
            api_headers = {
                **headers,
                "Accept": "application/json, text/plain, */*",
                "Origin": "https://www.xiaohongshu.com",
            }
            resp = client.get(api_url, params=params, headers=api_headers)

            collections = []
            if resp.status_code == 200:
                data = resp.json()
                items = data.get("data", {}).get("items", [])
                for item in items:
                    col = item.get("collection", {})
                    col_id = col.get("id", "")
                    col_name = col.get("name", "未命名")
                    note_count = col.get("note_count", 0)
                    if col_id:
                        collections.append({
                            "id": col_id,
                            "name": col_name,
                            "count": note_count,
                        })

            # 如果 API 没返回，用网页兜底
            if not collections:
                m = re.search(r'"collectCount":\s*(\d+)', html)
                collect_count = int(m.group(1)) if m else 0
                if collect_count > 0:
                    collections.append({
                        "id": "default",
                        "name": "默认收藏",
                        "count": collect_count,
                    })

        return {"success": True, "collections": collections}

    except Exception as e:
        return {"success": False, "message": f"获取收藏列表失败: {str(e)}"}


# ══════════════════════════════════════════════════════════
# 新增功能: 批量下载收藏
# ══════════════════════════════════════════════════════════

def batch_download_collection(col_id: str, col_name: str, download_path: str, task_id: str = "") -> dict:
    """批量下载收藏夹中的笔记"""
    try:
        import time
        if not _xhs_config.get("cookie"):
            return {"success": False, "message": "请先设置 Cookie"}

        headers = {**_XHS_HEADERS, "Cookie": _xhs_config["cookie"]}
        proxy = _xhs_config.get("proxy") or None

        note_ids = []

        with httpx.Client(headers=headers, follow_redirects=True, timeout=30, proxy=proxy) as client:
            if col_id == "default":
                # 默认收藏：从用户主页抓取
                resp = client.get("https://www.xiaohongshu.com/user/me")
                html = resp.text
                note_ids = re.findall(r'"noteId"\s*:\s*"([a-fA-F0-9]+)"', html)
                note_ids = list(dict.fromkeys(note_ids))
            else:
                # 指定收藏夹：使用 API 获取笔记列表
                api_url = "https://edith.xiaohongshu.com/api/sns/web/v2/note/collect/page"
                cursor = ""
                api_headers = {
                    **headers,
                    "Accept": "application/json, text/plain, */*",
                    "Origin": "https://www.xiaohongshu.com",
                }
                while True:
                    params = {"collection_id": col_id, "num": "20", "cursor": cursor}
                    resp = client.get(api_url, params=params, headers=api_headers)
                    if resp.status_code != 200:
                        break
                    data = resp.json()
                    items = data.get("data", {}).get("items", [])
                    for item in items:
                        nid = item.get("note_id", "")
                        if nid:
                            note_ids.append(nid)
                    has_more = data.get("data", {}).get("has_more", False)
                    cursor = data.get("data", {}).get("cursor", "")
                    if not has_more or not cursor:
                        break
                    time.sleep(0.5)

        if not note_ids:
            return {"success": False, "message": f"收藏「{col_name}」中没有找到笔记"}

        downloaded = 0
        total = len(note_ids)
        for i, nid in enumerate(note_ids):
            if is_task_paused(task_id):
                return {"success": False, "message": f"已暂停 ({downloaded}/{total})"}
            link = f"https://www.xiaohongshu.com/explore/{nid}"
            result = parse_link(link, download_path, "")
            if result.get("success"):
                downloaded += 1
            _report_progress(task_id, i + 1, total, f"收藏下载: {i+1}/{total}")
            time.sleep(1)

        return {"success": True,
                "message": f"收藏下载完成: {downloaded}/{total} 篇笔记"}

    except Exception as e:
        return {"success": False, "message": f"收藏下载失败: {str(e)}"}


# ══════════════════════════════════════════════════════════
# 新增功能: 列出笔记图片
# ══════════════════════════════════════════════════════════

def list_note_images(link: str) -> dict:
    """解析笔记并列出所有图片"""
    try:
        if not _xhs_config.get("cookie"):
            return {"success": False, "message": "请先设置 Cookie"}

        note_id = _extract_note_id(link)
        if not note_id:
            # 尝试短链解析
            try:
                with httpx.Client(headers=_XHS_HEADERS, follow_redirects=True, timeout=15) as client:
                    resp = client.get(link)
                    link = str(resp.url)
                note_id = _extract_note_id(link)
            except Exception:
                pass

        if not note_id:
            return {"success": False, "message": "无法解析链接"}

        headers = {**_XHS_HEADERS, "Cookie": _xhs_config["cookie"]}
        url = f"https://www.xiaohongshu.com/explore/{note_id}"

        with httpx.Client(headers=headers, follow_redirects=True, timeout=30) as client:
            resp = client.get(url)
            html = resp.text

        # 提取图片列表
        images = re.findall(r'"urlDefault":\s*"(https?://[^"]+)"', html)
        if not images:
            images = re.findall(r'"url":\s*"(https?://sns-webpic[^"]+)"', html)

        if not images:
            return {"success": False, "message": "该笔记没有图片或为视频笔记"}

        return {
            "success": True,
            "images": images,
            "count": len(images),
        }

    except Exception as e:
        return {"success": False, "message": f"解析失败: {str(e)}"}


# ══════════════════════════════════════════════════════════
# 新增功能: 选择性下载图片
# ══════════════════════════════════════════════════════════

def download_selected_images(link: str, indices_str: str, download_path: str, task_id: str = "") -> dict:
    """下载笔记中指定的图片"""
    try:
        indices = [int(x.strip()) for x in indices_str.split(",") if x.strip()]

        # 获取所有图片列表
        result = list_note_images(link)
        if not result.get("success"):
            return result

        images = result.get("images", [])
        if not images:
            return {"success": False, "message": "没有找到图片"}

        note_id = _extract_note_id(link) or "note"
        downloaded = 0

        with httpx.Client(headers=_XHS_DOWNLOAD_HEADERS, follow_redirects=True, timeout=30) as client:
            for idx in indices:
                if idx < 0 or idx >= len(images):
                    continue
                if is_task_paused(task_id):
                    return {"success": False, "message": f"已暂停 ({downloaded}/{len(indices)})"}

                img_url = images[idx]
                try:
                    resp = client.get(img_url)
                    ct = resp.headers.get("content-type", "")
                    if "png" in ct:
                        ext = ".png"
                    elif "webp" in ct:
                        ext = ".webp"
                    else:
                        ext = ".jpeg"
                    file_path = os.path.join(download_path, f"{note_id}_{idx+1}{ext}")
                    with open(file_path, "wb") as f:
                        f.write(resp.content)
                    downloaded += 1
                except Exception:
                    continue

                _report_progress(task_id, downloaded, len(indices), f"选择性下载: {downloaded}/{len(indices)}")

        return {"success": True,
                "message": f"下载完成: {downloaded}/{len(indices)} 张图片"}

    except Exception as e:
        return {"success": False, "message": f"选择性下载失败: {str(e)}"}


def check_status() -> str:
    """检查 Python 环境和 Cookie 状态"""
    try:
        cookie = _xhs_config.get("cookie", "")
        return json.dumps({
            "success": True,
            "python_ok": True,
            "has_cookie": bool(cookie),
            "cookie_length": len(cookie),
            "version": "1.0.0",
        })
    except Exception as e:
        return json.dumps({"success": False, "python_ok": False, "error": str(e)})


def get_data_stats(link: str) -> str:
    """采集笔记数据统计信息"""
    import json as _json2
    try:
        note_id = _extract_note_id(link)
        if not note_id:
            return _json2.dumps({"success": False, "message": "无法识别笔记链接"}, ensure_ascii=False)

        headers = {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Referer": "https://www.xiaohongshu.com/",
            "Cookie": _xhs_config.get("cookie", ""),
        }

        with httpx.Client(headers=headers, follow_redirects=True, timeout=30) as client:
            url = f"https://www.xiaohongshu.com/explore/{note_id}"
            resp = client.get(url)
            html = resp.text

            # 从页面中提取 __INITIAL_STATE__ JSON
            import re
            match = re.search(r'window\.__INITIAL_STATE__\s*=\s*({.+?})\s*</script>', html, re.DOTALL)
            if not match:
                return _json2.dumps({"success": False, "message": "无法获取笔记数据，可能需要Cookie"}, ensure_ascii=False)

            state_str = match.group(1).replace("undefined", "null")
            state = _json2.loads(state_str)

            note_data = state.get("note", {}).get("noteDetailMap", {}).get(note_id, {}).get("note", {})
            if not note_data:
                return _json2.dumps({"success": False, "message": "无法解析笔记详情"}, ensure_ascii=False)

            interact_info = note_data.get("interactInfo", {})
            user_info = note_data.get("user", {})
            tag_list = note_data.get("tagList", [])

            title = note_data.get("title", "")
            desc = note_data.get("desc", "")
            note_type = note_data.get("type", "")
            type_name = "视频" if note_type == "video" else "图文"

            tags_str = " ".join([f"#{t.get('name', '')}" for t in tag_list]) if tag_list else ""

            return _json2.dumps({
                "success": True,
                "title": title or desc[:30],
                "author": user_info.get("nickname", "未知"),
                "type": type_name,
                "tags": tags_str,
                "stats": {
                    "likes": str(interact_info.get("likedCount", "0")),
                    "collects": str(interact_info.get("collectedCount", "0")),
                    "comments": str(interact_info.get("commentCount", "0")),
                    "shares": str(interact_info.get("shareCount", "0")),
                }
            }, ensure_ascii=False)

    except Exception as e:
        return _json2.dumps({"success": False, "message": f"数据采集失败: {str(e)}"}, ensure_ascii=False)


def list_xhs_user_works(user_id: str) -> str:
    """列出小红书用户所有作品（不下载），返回 JSON 列表"""
    import json as _json3
    try:
        cookie = _xhs_config.get("cookie", "")
        if not cookie:
            return _json3.dumps({"success": False, "message": "请先设置 Cookie", "works": []}, ensure_ascii=False)

        headers = {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Cookie": cookie,
            "Referer": "https://www.xiaohongshu.com/",
        }
        proxy = _xhs_config.get("proxy") or None

        import httpx
        works = []
        with httpx.Client(headers=headers, follow_redirects=True, timeout=30.0, proxy=proxy) as client:
            resp = client.get(f"https://www.xiaohongshu.com/user/profile/{user_id}")
            html = resp.text
            import re as _re
            note_ids = list(set(_re.findall(r'"noteId"\s*:\s*"([a-fA-F0-9]+)"', html)))
            for nid in note_ids:
                works.append({
                    "id": nid,
                    "link": f"https://www.xiaohongshu.com/explore/{nid}"
                })
        return _json3.dumps({"success": True, "works": works, "count": len(works)}, ensure_ascii=False)
    except Exception as e:
        return _json3.dumps({"success": False, "message": str(e), "works": []}, ensure_ascii=False)


# 模块加载时读取配置
_load_config()
