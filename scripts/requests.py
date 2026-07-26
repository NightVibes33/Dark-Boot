"""Small requests-compatible transport used only by build_snowboard_catalog.py.

The package index blocks GitHub-hosted runner IPs. For index HTML only, retry
through Jina Reader with x-respond-with=html. Original DEB payloads are always
fetched directly from their source repositories and verified by SHA-256.
"""
from __future__ import annotations

from dataclasses import dataclass
from urllib.error import HTTPError
from urllib.request import Request, urlopen


@dataclass
class Response:
    content: bytes
    url: str
    status_code: int

    @property
    def text(self) -> str:
        return self.content.decode("utf-8", errors="replace")

    def raise_for_status(self) -> None:
        if self.status_code < 200 or self.status_code >= 400:
            raise RuntimeError(f"HTTP {self.status_code} for {self.url}")


class Session:
    def __init__(self) -> None:
        self.headers: dict[str, str] = {}

    def get(self, url: str, timeout: int = 45, allow_redirects: bool = True, **_kwargs) -> Response:
        del allow_redirects  # urllib follows normal HTTP redirects.
        try:
            return self._get(url, timeout=timeout, extra_headers={})
        except HTTPError as error:
            if error.code != 403 or "www.ios-repo-updates.com/" not in url:
                raise
            proxy = "https://r.jina.ai/" + url
            return self._get(
                proxy,
                timeout=max(timeout, 90),
                extra_headers={
                    "X-Respond-With": "html",
                    "X-Timeout": "60",
                    "X-No-Cache": "true",
                },
            )

    def _get(self, url: str, timeout: int, extra_headers: dict[str, str]) -> Response:
        headers = dict(self.headers)
        headers.update(extra_headers)
        request = Request(url, headers=headers, method="GET")
        with urlopen(request, timeout=timeout) as opened:
            content = opened.read()
            status = int(getattr(opened, "status", 200) or 200)
            final_url = opened.geturl()
        return Response(content=content, url=final_url, status_code=status)
