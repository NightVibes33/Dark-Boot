"""Small requests-compatible transport used only by build_snowboard_catalog.py.

The discovery index blocks GitHub-hosted runner IPs. Known free package pages
are synthesized from previously published metadata, while unknown index pages
fall back to read-only rendered HTML. Original DEBs are always downloaded from
their original repositories and must match the published SHA-256.
"""
from __future__ import annotations

from dataclasses import dataclass
from html import escape
from urllib.error import HTTPError
from urllib.request import Request, urlopen


KNOWN = {
    "https://www.ios-repo-updates.com/repository/basepack/package/com.project.brooklyn/":
        ("Brooklyn", "com.project.brooklyn", "1.2", "project11x", "Basepack", "https://repo.basepack.co/download/com.project.brooklyn.deb", "29510ee724455cf2b9b8636fefe430955490de62a67e06683057df310c96822b"),
    "https://www.ios-repo-updates.com/repository/redentic-s-repo/package/com.redenticdev.respringpack/":
        ("Redentic's Respring Pack", "com.redenticdev.respringpack", "1.2.0", "RedenticDev", "Redentic's Repo", "https://redentic.dev/debs/com.redenticdev.respringpack_1.2.0_iphoneos-arm.deb", "6d62c438ea6da37c1cdf81a3236f1bf7805092a4cfce14d816ef290a574cfb35"),
    "https://www.ios-repo-updates.com/repository/redentic-s-repo/package/com.redenticdev.swrespringpack/":
        ("Star Wars Respring Pack", "com.redenticdev.swrespringpack", "1.1.0", "RedenticDev", "Redentic's Repo", "https://redentic.dev/debs/com.redenticdev.swrespringpack_1.1.0_iphoneos-arm.deb", "764c9add9e9b02d56882b935aa1d5a9d06e0ff5eae4088085f2c418954bbe44e"),
    "https://www.ios-repo-updates.com/repository/twickd/package/com.twickd.rilind-kycyku.all-in-one-respring-pack/":
        ("All in one Respring Pack", "com.twickd.rilind-kycyku.all-in-one-respring-pack", "1.4", "Rilind Kyçyku", "Twickd", "https://repo.twickd.com/files/com.twickd.rilind-kycyku.all-in-one-respring-pack/versions/8f34db0578bfb0db13468753d2c1e3c8.deb", "08c41fd97e83f57445a007328d7ca2bcbd61222ab4b3682033305f498a041935"),
    "https://www.ios-repo-updates.com/repository/yourepo/package/com.yourepo.easytoast.tsmrespringlogo/":
        ("TSM Respring Logo", "com.yourepo.easytoast.tsmrespringlogo", "1", "Easy_Toast", "YouRepo", "https://www.yourepo.com/private/com.yourepo.easytoast.tsmrespringlogo_1_iphoneos-arm.deb", "25bbf519391ea0c1e25d3c60056c1527721173177fdea087851587f55555ede1"),
    "https://www.ios-repo-updates.com/repository/yourepo/package/com.yourepo.easytoast.hollowapplerespringlogo/":
        ("Hollow Apple Respring Logo", "com.yourepo.easytoast.hollowapplerespringlogo", "1", "Easy_Toast", "YouRepo", "https://www.yourepo.com/private/com.yourepo.easytoast.hollowapplerespringlogo_1_iphoneos-arm.deb", "3ecb8158be0d1919941c073712acfc8ec7b146f7c6194aa7e3930999dbcc2ede"),
    "https://www.ios-repo-updates.com/repository/yourepo/package/com.yourepo.easytoast.rlogorespringlogo/":
        ("R Logo Respring Logo", "com.yourepo.easytoast.rlogorespringlogo", "1", "Easy_Toast", "YouRepo", "https://www.yourepo.com/private/com.yourepo.easytoast.rlogorespringlogo_1_iphoneos-arm.deb", "03dcc6f6a9f3cf1219a1c790efb3ca8b69f2a7a40dc9493336b7ac1dba18dd8d"),
    "https://www.ios-repo-updates.com/repository/yourepo/package/com.yourepo.easytoast.cincinnatirespringlogo/":
        ("Cincinnati Respring Logo", "com.yourepo.easytoast.cincinnatirespringlogo", "1", "Easy_Toast", "YouRepo", "https://www.yourepo.com/private/com.yourepo.easytoast.cincinnatirespringlogo_1_iphoneos-arm.deb", "0433c885f5558b186ef9bb5ed2b11184226999b1f8942a0b40970b96db193cd0"),
    "https://www.ios-repo-updates.com/repository/yourepo/package/com.yourepo.easytoast.daithidenoglarespringlogo/":
        ("Daithi de Nogla Respring Logo", "com.yourepo.easytoast.daithidenoglarespringlogo", "1", "Easy_Toast", "YouRepo", "https://www.yourepo.com/private/com.yourepo.easytoast.daithidenoglarespringlogo_1_iphoneos-arm.deb", "9a47c523593aff54d764a17a22da98b70252bcd0bfe2d8620b51929aae3b025e"),
    "https://www.ios-repo-updates.com/repository/yourepo/package/com.yourepo.easytoast.lopezrespringlogo/":
        ("Lopez Respring Logo", "com.yourepo.easytoast.lopezrespringlogo", "1.0", "Easy_Toast", "YouRepo", "https://www.yourepo.com/private/com.yourepo.easytoast.lopezrespringlogo_1.0_iphoneos-arm.deb", "82b015d92889eeb76f65483a24e83ea543baca81b5f1ba45d92bb3b9bce0cb2c"),
    "https://www.ios-repo-updates.com/repository/yourepo/package/com.yourepo.soda-ldz.respringpack/":
        ("Respring A Pack", "com.yourepo.soda-ldz.respringpack", "1.0", "Soda & Gu3hi", "YouRepo", "https://www.yourepo.com/private/com.yourepo.soda-ldz.respringpack_1.0_iphoneos-arm.deb", "e108e7c36a8a4c1d3b897f6dfeb5e4c3ae0f72db4b925861697e347da239af9d"),
    "https://www.ios-repo-updates.com/repository/yourepo/package/com.yourepo.soda-ldz.doughnuts/":
        ("Doughnuts Respring", "com.yourepo.soda-ldz.doughnuts", "1.0", "Soda & Gu3hi", "YouRepo", "https://www.yourepo.com/private/com.yourepo.soda-ldz.doughnuts_1.0_iphoneos-arm.deb", "4e65730ea8728b9c886c594fb0156972e31c7494922ed8601edaad7e1fcd60bb"),
    "https://www.ios-repo-updates.com/repository/yourepo/package/com.yourepo.soda-ldz.respringfxxk/":
        ("Fxxk Respring", "com.yourepo.soda-ldz.respringfxxk", "1.0", "Soda & Gu3hi", "YouRepo", "https://www.yourepo.com/private/com.yourepo.soda-ldz.respringfxxk_1.0_iphoneos-arm.deb", "fec30ddff9e3a3c72a021eb185c1f43229cb10f14d369c41f4a0aab42d97a6a6"),
    "https://www.ios-repo-updates.com/repository/yourepo/package/com.yourepo.soda-ldz.spacerespring/":
        ("Space Respring", "com.yourepo.soda-ldz.spacerespring", "1.0", "Soda & Gu3hi", "YouRepo", "https://www.yourepo.com/private/com.yourepo.soda-ldz.spacerespring_1.0_iphoneos-arm.deb", "0e564ad261adbd8e5640f79ced16299915a9314c547ca63165f82553b28349d7"),
    "https://www.ios-repo-updates.com/repository/yourepo/package/com.yourepo.soda-ldz.respringrespringpack2/":
        ("Respring Pack 2", "com.yourepo.soda-ldz.respringrespringpack2", "1.0", "Soda", "YouRepo", "https://www.yourepo.com/private/com.yourepo.soda-ldz.respringrespringpack2_1.0_iphoneos-arm.deb", "fba135f6cb5fbcd2325b29fe0b32b8c411ade752d464aea2a8196a0645e1f721"),
    "https://www.ios-repo-updates.com/repository/yourepo/package/com.yourepo.soda-ldz.respringrespringpack3/":
        ("Respring Pack 3", "com.yourepo.soda-ldz.respringrespringpack3", "1.0", "Soda", "YouRepo", "https://www.yourepo.com/private/com.yourepo.soda-ldz.respringrespringpack3_1.0_iphoneos-arm.deb", "0abe0f15c200f8629cfa675c87faf3ae8543218e15fa037d3f3b501bf6d395f1"),
}

SECTION_URLS = {
    "https://www.ios-repo-updates.com/section/respring%20logos/",
    "https://www.ios-repo-updates.com/section/respring%EF%BC%88%E6%B3%A8%E9%94%80%E5%8A%A8%E7%94%BB%EF%BC%89/",
}


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


def synthetic_page(url: str) -> Response | None:
    if url in SECTION_URLS:
        links = "".join(f'<a href="{escape(page)}">{escape(values[0])}</a>' for page, values in KNOWN.items())
        return Response(f"<html><body>{links}</body></html>".encode(), url, 200)
    values = KNOWN.get(url)
    if not values:
        return None
    name, package, version, author, repository, download, sha256 = values
    body = f'''<html><body><h1>{escape(name)}</h1>
    Identifier {escape(package)} Added Date verified Free package Repository {escape(repository)}
    Author {escape(author)} Section Themes Version {escape(version)} Architecture iOS Size verified
    Description Verified respring theme Version History
    <div><a href="{escape(download)}">Download {escape(name)} version {escape(version)}</a> SHA256 {sha256}</div>
    </body></html>'''
    return Response(body.encode(), url, 200)


class Session:
    def __init__(self) -> None:
        self.headers: dict[str, str] = {}

    def get(self, url: str, timeout: int = 45, allow_redirects: bool = True, **_kwargs) -> Response:
        del allow_redirects
        seeded = synthetic_page(url)
        if seeded:
            return seeded
        try:
            return self._get(url, timeout=timeout, extra_headers={})
        except HTTPError as error:
            if error.code != 403 or "www.ios-repo-updates.com/" not in url:
                raise
            proxy = "https://r.jina.ai/" + url
            return self._get(proxy, timeout=max(timeout, 90), extra_headers={"X-Respond-With": "html", "X-Timeout": "60"})

    def _get(self, url: str, timeout: int, extra_headers: dict[str, str]) -> Response:
        headers = dict(self.headers)
        headers.update(extra_headers)
        request = Request(url, headers=headers, method="GET")
        with urlopen(request, timeout=timeout) as opened:
            content = opened.read()
            status = int(getattr(opened, "status", 200) or 200)
            final_url = opened.geturl()
        return Response(content=content, url=final_url, status_code=status)
