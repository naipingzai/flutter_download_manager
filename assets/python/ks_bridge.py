"""
Python Bridge for Kuaishou (快手) Downloader
Handles parsing and downloading content from Kuaishou platform.
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
}

_PC_UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
          "(KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36")
_REFERER = "https://www.kuaishou.com/"


def _cookie_str_to_dict(cookie_str: str) -> dict:
    """Parse cookie string to dict"""
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


def _cookie_dict_to_str(cookie_dict: dict) -> str:
    """Convert cookie dict to string"""
    if not cookie_dict:
        return ""
    return "; ".join(f"{k}={v}" for k, v in cookie_dict.items())


def _ensure_cookie_str(cookie) -> str:
    """Ensure cookie is a string"""
    if isinstance(cookie, dict):
        return _cookie_dict_to_str(cookie)
    if isinstance(cookie, str):
        return cookie.strip()
    return ""


def set_cookie(cookie: str):
    """Set the cookie for Kuaishou API requests."""
    clean = cookie.strip()
    _config["cookie"] = clean
    _save_config()
    cookie_dict = _cookie_str_to_dict(clean)
    return json.dumps({
        "success": True,
        "key_count": len(cookie_dict),
        "cookie_length": len(clean),
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
    return json.dumps(_config)


def _save_config():
    """Save config to local storage."""
    try:
        config_dir = os.path.join(os.environ.get("HOME", "/data/data/com.advancedownloader"), "Volume")
        os.makedirs(config_dir, exist_ok=True)
        config_file = os.path.join(config_dir, "ks_settings.json")
        with open(config_file, "w", encoding="utf-8") as f:
            json.dump(_config, f, ensure_ascii=False, indent=2)
    except Exception as e:
        print(f"[KS] Warning: _save_config failed: {e}")


def _load_config():
    """Load config from local storage."""
    try:
        config_dir = os.path.join(os.environ.get("HOME", "/data/data/com.advancedownloader"), "Volume")
        config_file = os.path.join(config_dir, "ks_settings.json")
        if os.path.exists(config_file):
            with open(config_file, "r", encoding="utf-8") as f:
                data = json.load(f)
            if isinstance(data.get("cookie"), dict):
                data["cookie"] = _cookie_dict_to_str(data["cookie"])
            _config.update(data)
            print(f"[KS] Config loaded, cookie length={len(_config.get('cookie', ''))}")
    except Exception as e:
        print(f"[KS] Warning: _load_config failed: {e}")


# Load config on module import
_load_config()


def parse_link(link: str, download_path: str, task_id: str = "") -> dict:
    """
    Parse a Kuaishou link and download the content.

    Args:
        link: The URL to parse and download
        download_path: Directory to save downloaded files
        task_id: Task ID for progress reporting

    Returns:
        dict with keys: success (bool), title (str), message (str)
    """
    try:
        _config["download_path"] = download_path
        os.makedirs(download_path, exist_ok=True)

        # Extract URL
        url_pattern = re.compile(r'https?://[^\s<>"{}|\\^`\[\]]+', re.IGNORECASE)
        urls = url_pattern.findall(link)
        if not urls:
            return {"success": False, "title": link, "message": "未找到有效链接"}

        target_url = urls[0]
        return _download_kuaishou(target_url, download_path)

    except Exception as e:
        return {
            "success": False,
            "title": link,
            "message": f"解析失败: {str(e)}\n{traceback.format_exc()}"
        }


def _download_kuaishou(link: str, download_path: str) -> dict:
    """
    Kuaishou download flow:
    1. Resolve short links and extract photo_id
    2. Call web API to get content details
    3. Download video/images
    """
    import httpx

    cookie = _ensure_cookie_str(_config.get("cookie", ""))
    proxy = _config.get("proxy") or None

    print(f"[KS] Starting download: link={link[:80]}")
    print(f"[KS] Cookie present: {bool(cookie)}, length: {len(cookie)}")

    headers = {
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
        "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
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
        # Step 1: Extract photo_id
        photo_id = _extract_photo_id(client, link)
        if not photo_id:
            return {"success": False, "title": link,
                    "message": "无法从链接中提取作品ID，请检查链接是否正确"}

        print(f"[KS] Extracted photo_id: {photo_id}")

        # Step 2: Get photo detail
        detail = _fetch_photo_detail(client, photo_id)
        if not detail:
            return {"success": False, "title": f"作品 {photo_id}",
                    "message": "获取作品详情失败，可能需要设置Cookie"}

        # Step 3: Download content
        return _download_content(detail, download_path)


def _extract_photo_id(client, link: str) -> str:
    """Extract photo_id from various Kuaishou URL formats."""
    print(f"[KS] Extracting photo_id from: {link[:100]}")

    # Short link: v.kuaishou.com/xxx
    if 'v.kuaishou.com' in link or 'v.m.chenzhongtech.com' in link:
        try:
            resp = client.get(link, follow_redirects=True)
            final_url = str(resp.url)
            print(f"[KS] Redirected to: {final_url[:100]}")
            link = final_url
        except Exception as e:
            print(f"[KS] Failed to resolve short link: {e}")

    # Direct photo ID in URL
    patterns = [
        r'photo/(\w+)',
        r'short-video/(\w+)',
        r'fw/(\w+)',
        r'/(\w{12,})',
    ]
    for pattern in patterns:
        m = re.search(pattern, link)
        if m:
            photo_id = m.group(1)
            if len(photo_id) >= 6:
                return photo_id

    # Try to find ID from page content
    try:
        resp = client.get(link)
        html = resp.text
        # Look for photoId in page source
        m = re.search(r'"photoId"\s*:\s*"(\w+)"', html)
        if m:
            return m.group(1)
        m = re.search(r'"id"\s*:\s*"(\w{12,})"', html)
        if m:
            return m.group(1)
    except Exception as e:
        print(f"[KS] Failed to fetch page: {e}")

    return ""


def _fetch_photo_detail(client, photo_id: str) -> dict:
    """Fetch photo detail from Kuaishou API."""
    try:
        # Use GraphQL API
        api_url = "https://www.kuaishou.com/graphql"
        query = {
            "operationName": "visionVideoDetail",
            "variables": {"photoId": photo_id, "page": "detail"},
            "query": """
                query visionVideoDetail($photoId: String, $type: String, $page: String) {
                    visionVideoDetail(photoId: $photoId, type: $type, page: $page) {
                        photo {
                            id
                            duration
                            caption
                            likeCount
                            realLikeCount
                            timestamp
                            photoUrl
                            coverUrl
                            webpCoverUrl
                            manifest
                            mainMvUrl
                            photoH265Url
                            coverAnimatedWebpUrl
                            photoWebpUrl
                            viewCount
                            videoResource {
                                ...
                            }
                        }
                        author {
                            id
                            name
                            headerUrl
                        }
                    }
                }
            """,
        }

        headers = {
            "Content-Type": "application/json",
            "Referer": f"https://www.kuaishou.com/short-video/{photo_id}",
            "User-Agent": _PC_UA,
            "Origin": "https://www.kuaishou.com",
        }
        cookie = _ensure_cookie_str(_config.get("cookie", ""))
        if cookie:
            headers["Cookie"] = cookie

        resp = client.post(api_url, json=query, headers=headers)
        if resp.status_code != 200:
            print(f"[KS] API returned {resp.status_code}")
            return {}

        data = resp.json()
        vision = data.get("data", {}).get("visionVideoDetail", {})
        photo = vision.get("photo", {})
        author = vision.get("author", {})

        if not photo:
            print(f"[KS] No photo data found")
            return {}

        return {
            "photo_id": photo.get("id", photo_id),
            "caption": photo.get("caption", ""),
            "photo_url": photo.get("photoUrl", ""),
            "cover_url": photo.get("coverUrl", ""),
            "author_name": author.get("name", ""),
            "author_id": author.get("id", ""),
            "duration": photo.get("duration", 0),
            "view_count": photo.get("viewCount", 0),
            "manifest": photo.get("manifest", ""),
        }

    except Exception as e:
        print(f"[KS] Failed to fetch photo detail: {e}")
        traceback.print_exc()
        return {}


def _download_content(detail: dict, download_path: str) -> dict:
    """Download the video/image content."""
    import httpx

    photo_url = detail.get("photo_url", "")
    caption = detail.get("caption", f"快手作品_{detail.get('photo_id', '')}")
    author_name = detail.get("author_name", "")

    if not photo_url:
        return {"success": False, "title": caption, "message": "无法获取下载地址"}

    # Create author directory
    safe_author = re.sub(r'[\\/:*?"<>|]', '_', author_name).strip() if author_name else ""
    author_dir = os.path.join(download_path, safe_author) if safe_author else download_path
    os.makedirs(author_dir, exist_ok=True)

    # Sanitize filename
    safe_caption = re.sub(r'[\\/:*?"<>|\n\r]', '_', caption).strip()
    prefix = f"{safe_author}_{safe_caption}" if safe_author else safe_caption
    file_base = prefix[:60]

    # Download video
    filename = f"{file_base}.mp4"
    filepath = os.path.join(author_dir, filename)

    print(f"[KS] Downloading video: {photo_url[:80]}")
    try:
        with httpx.Client(
            follow_redirects=True,
            timeout=60.0,
            proxy=_config.get("proxy") or None,
        ) as dl_client:
            headers = {
                "User-Agent": _PC_UA,
                "Referer": _REFERER,
            }
            with dl_client.stream("GET", photo_url, headers=headers) as resp:
                if resp.status_code != 200:
                    return {"success": False, "title": caption,
                            "message": f"下载失败，HTTP {resp.status_code}"}

                total = int(resp.headers.get("content-length", 0))
                downloaded = 0

                with open(filepath, "wb") as f:
                    for chunk in resp.iter_bytes(chunk_size=65536):
                        f.write(chunk)
                        downloaded += len(chunk)

        file_size = os.path.getsize(filepath)
        print(f"[KS] Download complete: {filepath} ({file_size} bytes)")

        return {
            "success": True,
            "title": caption,
            "path": filepath,
            "size": file_size,
            "author": author_name,
        }

    except Exception as e:
        print(f"[KS] Download failed: {e}")
        return {"success": False, "title": caption,
                "message": f"下载失败: {str(e)}"}
