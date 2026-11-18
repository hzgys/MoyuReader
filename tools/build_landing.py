#!/usr/bin/env python3
"""
把落地页里的相对路径下载链接「内嵌」成自包含单文件。

为什么需要它
------------
oneshot 只接受**单个 HTML 文件**（不支持 zip、多文件、二进制附件），所以落地页里的

    <a href="MoyuReader.dmg" download>下载 DMG</a>

在上传之后必然 404 —— 那个 .dmg 根本没被传上去。

这个脚本把 dmg / zip 以 base64 内嵌进 HTML，并在页面加载时接管那几个链接：
点按钮时用 Blob 触发浏览器下载。产物是**自包含单文件**，传到哪都能用，
不依赖任何外部服务，也不额外消耗带宽。

为什么用 Blob 而不是直接 <a href="data:...">
Safari 从 10 开始禁止顶层导航到 data: URI，`download` 属性对 data: 也基本无效 ——
点下去没反应。改成运行时生成 Blob URL、再把这个 URL 写进 href，是跨浏览器都稳的做法
（见注入脚本里的注释：为什么是「换 href」而不是「拦截 click 再程序化点击」）。

源文件不动
----------
`MoyuReader.html` 保持人类可读的原样（相对路径链接），脚本只在 </body> 前
**注入**一段自举代码，不改动原标签。这样源文件始终可编辑、可 diff。

用法
----
    python3 tools/build_landing.py

产物：dist/MoyuReader.html —— 上传 oneshot 用**这一个**文件。
"""

import base64
import hashlib
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "MoyuReader.html")
OUT_DIR = os.path.join(ROOT, "dist")
OUT = os.path.join(OUT_DIR, "MoyuReader.html")

# 要内嵌的附件：文件名 -> MIME。
# MIME 统一用 application/octet-stream：download 属性本来就会强制下载并指定文件名，
# 而 octet-stream 保证浏览器**绝不会尝试内联渲染**这个内容 —— 万一某浏览器忽略了
# download 属性（Safari 在部分场景下会），octet-stream 是唯一不会打开成乱码的选择。
CANDIDATES = {
    "MoyuReader.dmg": "application/octet-stream",
    "MoyuReader-macOS.zip": "application/octet-stream",
}

MARKER = "<!-- oneshot-embed:start -->"


def find_node():
    """找一个可用的 node 做 JS 语法校验。找不到返回 None（跳过校验但会警告）。"""
    for c in (
        shutil.which("node"),
        "/usr/local/bin/node",
        os.path.expanduser("~/.workbuddy/binaries/node/versions/current/bin/node"),
    ):
        if c and os.path.exists(c):
            return c
    return None


def js_syntax_error(node, script):
    """
    用 `node --check` 校验一段 JS，返回错误描述；没问题返回 None。

    为什么必须做：注入的脚本一旦有语法错误，浏览器会**整个 script 块静默跳过** ——
    不报错、不提示，页面照常渲染、按钮照常可点，只是**点了没反应**。
    本项目就栽过这一次：对象 key 写成 `MoyuReader.dmg`（含点号）却忘了加引号，
    而结构正则恰好匹配上了那个写法 —— 于是「检查全绿、功能全废」。
    这类错误只能靠真语法校验拦住。
    """
    fd, path = tempfile.mkstemp(suffix=".js")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(script)
        p = subprocess.run([node, "--check", path], capture_output=True, text=True)
        if p.returncode == 0:
            return None
        lines = (p.stdout + p.stderr).splitlines()
        for line in lines:
            if line.startswith(("SyntaxError", "ReferenceError")):
                return line.strip()
        for line in lines:
            if line.strip() and not line.startswith(" "):
                return line.strip()
        return "（node --check 未给出具体信息）"
    finally:
        os.remove(path)


def b64_of(path):
    with open(path, "rb") as f:
        return base64.b64encode(f.read()).decode("ascii")


def main():
    if not os.path.exists(SRC):
        sys.exit(f"❌ 找不到源文件：{SRC}")

    with open(SRC, "r", encoding="utf-8") as f:
        html = f.read()

    if MARKER in html:
        sys.exit("❌ 源文件里已经存在注入标记，说明它本身是产物。请对原始的 MoyuReader.html 运行。")

    # 找出 HTML 里真正引用的附件（href="xxx"），只嵌这些
    hrefs = set(re.findall(r'href="([^"]+)"', html))
    embed = {}
    for name, mime in CANDIDATES.items():
        if name not in hrefs:
            print(f"⏭  {name} 未被 HTML 引用，跳过")
            continue
        path = os.path.join(ROOT, name)
        if not os.path.exists(path):
            print(f"❌ {name} 被引用但文件不存在：{path}")
            sys.exit(1)
        data = b64_of(path)
        raw = os.path.getsize(path)
        embed[name] = (data, mime, raw)
        print(f"✅ 内嵌 {name}  {raw/1024:.0f} KB → base64 {len(data)/1024:.0f} KB")

    if not embed:
        sys.exit("❌ HTML 里没有任何可内嵌的附件，什么都没做。")

    # 按钮上写的体积是手抄的，版本一变就过期 —— 提示一下，不自动改（改源文件更可控）
    for name, (_, _, raw) in embed.items():
        kb = round(raw / 1024)
        m = re.search(
            r'href="%s"[^>]*>(?:(?!</a>)[\s\S]){0,600}?[（(]\s*(\d+)\s*KB\s*[)）]' % re.escape(name),
            html,
        )
        if m and int(m.group(1)) != kb:
            print(f"⚠️  按钮文案写的是「{m.group(1)} KB」，实际是 {kb} KB"
                  f" —— 建议改 MoyuReader.html 里的文案")

    # 生成注入代码。base64 直接写进 JS 字面量。
    # ⚠️ key 必须带引号：文件名含点号（MoyuReader.dmg），不加引号是语法错误，
    #    会让**整个 script 块**一行都不执行 —— 页面看着正常、按钮点了没反应，极难定位。
    entries = ",\n".join(
        "    '%s': { b64: '%s', mime: '%s' }" % (name, data, mime)
        for name, (data, mime, _) in embed.items()
    )

    inject = """
%(marker)s
<script>
/*
 * 自包含下载支持（由 tools/build_landing.py 注入，请勿手改 —— 改完重新跑脚本）
 *
 * 原 HTML 里的 <a href="MoyuReader.dmg" download> 在单文件部署下会 404，
 * 这里在页面加载后把那些链接的 href 换成运行时生成的 blob: URL ——
 * 用户点的仍然是原生链接，走浏览器自己的下载流程。
 */
(function () {
  var FILES = {
%(entries)s
  };

  function toBlob(f) {
    var bin = atob(f.b64), n = bin.length, bytes = new Uint8Array(n);
    for (var i = 0; i < n; i++) bytes[i] = bin.charCodeAt(i);
    return new Blob([bytes], { type: f.mime });
  }

  /*
   * 把 href 直接换成 blob: URL，而不是「拦截 click + 程序化点一个临时 <a>」。
   *
   * 为什么：程序化 a.click() 属于「脚本触发下载」，各浏览器（尤其 Safari）对
   * 它在「是否处于用户手势上下文」上的判定并不一致 —— 是所有下载路径里被限制
   * 最多的一种。把 href 直接指向 blob: URL 之后，用户点的就是一个**货真价实的
   * 链接**，浏览器走完全原生的下载流程：兼容性最好，右键「链接存储为」也能用。
   *
   * ⚠️ blob URL 创建之后**不要 revoke**：一旦 revoke，链接立刻失效，下载会中断，
   * 表现出来正是 Safari 那句「无法从网站上提取文件」。页面卸载时浏览器会自行
   * 回收，这里不需要（也不应该）手动管它的生命周期。
   */
  var links = document.querySelectorAll('a[href]');
  for (var i = 0; i < links.length; i++) {
    (function (a) {
      var name = a.getAttribute('href');
      var f = FILES[name];
      if (!f) return;
      a.setAttribute('href', URL.createObjectURL(toBlob(f)));
      a.setAttribute('download', name);
    })(links[i]);
  }
})();
</script>
%(marker)s
""" % {"marker": MARKER, "entries": entries}

    idx = html.rfind("</body>")
    if idx < 0:
        sys.exit("❌ HTML 里找不到 </body>，无法注入。")
    out_html = html[:idx] + inject + html[idx:]

    # ── 校验 1：注入的 JS 必须语法正确（写盘前拦） ──
    # 语法一错，浏览器会**整个 script 块静默跳过**：不报错、页面照常渲染、按钮照常可点，
    # 只是点了没反应。页面上完全看不出来，所以必须在产物落盘前拦住。
    blocks = re.findall(r"<script>(.*?)</script>", out_html, re.S)
    node = find_node()
    if not node:
        print("⚠️  找不到 node，跳过 JS 语法校验 —— 强烈建议装一个再跑，这类错误肉眼看不出来")
    else:
        for i, b in enumerate(blocks, 1):
            err = js_syntax_error(node, b)
            if err:
                sys.exit(
                    f"❌ 第 {i} 个 <script> 块语法错误，浏览器会整个跳过它：\n"
                    f"   {err}\n"
                    f"   这种错误页面上完全看不出来（按钮能点、就是没反应），已中止写盘。"
                )
        print(f"🔍 注入脚本语法校验通过（{len(blocks)} 个 script 块）")

    os.makedirs(OUT_DIR, exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(out_html)

    # ── 校验 2：回读产物，重新解码、逐个比对 SHA256 ──
    # 内嵌是「把二进制搬进文本」的操作，一旦编码/转义出错，用户下到的是坏文件，
    # 而且从页面上完全看不出来（按钮能点、下载能完成、打开才报损坏）。
    with open(OUT, "r", encoding="utf-8") as f:
        written = f.read()

    bad = []
    for name in embed:
        # key 必须是带引号的（见上面 entries 的说明），所以正则也要求引号 ——
        # 顺带成了「有没有漏加引号」的第二道闸。
        m = re.search(r"'" + re.escape(name) + r"':\s*\{\s*b64:\s*'([A-Za-z0-9+/=]+)'", written)
        if not m:
            bad.append(f"{name}：产物里找不到它的 base64")
            continue
        decoded = base64.b64decode(m.group(1))
        with open(os.path.join(ROOT, name), "rb") as f:
            origin = f.read()
        if decoded != origin:
            bad.append(f"{name}：解码后与原文件不一致（{len(decoded)} vs {len(origin)} 字节）")
        else:
            h = hashlib.sha256(origin).hexdigest()[:12]
            print(f"🔍 {name} 校验通过  sha256:{h}  {len(origin)/1024:.0f} KB")

    if bad:
        print("")
        for b in bad:
            print(f"❌ {b}")
        sys.exit("❌ 校验失败，产物不可信，请勿上传。")

    src_kb = len(html.encode("utf-8")) / 1024
    out_kb = len(out_html.encode("utf-8")) / 1024
    print("")
    print("产物：%s" % os.path.relpath(OUT, ROOT))
    print("体积：%.0f KB → %.0f KB" % (src_kb, out_kb))
    print("上传 oneshot 请用这一个文件。")


if __name__ == "__main__":
    main()
