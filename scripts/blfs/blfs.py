#!/usr/bin/env python3
"""Lê o livro BLFS (nochunks) e responde a perguntas sobre pacotes.

  blfs.py info  <id>...           -> título, downloads, dependências, comandos
  blfs.py deps  [--no-rec] <id>... -> ordem de build (fecho de required+recommended)
  blfs.py ids   <regex>            -> procurar ids de pacotes
"""
import html, json, re, sys
from pathlib import Path

BOOK = Path(__file__).resolve().parents[2] / "book/BLFS-BOOK-13.1-systemd-nochunks.html"
CACHE = BOOK.with_suffix(".json")


def text(h):
    h = re.sub(r"<[^>]+>", "", h)
    return html.unescape(h)


def parse():
    if CACHE.exists() and CACHE.stat().st_mtime > BOOK.stat().st_mtime:
        return json.loads(CACHE.read_text())
    s = BOOK.read_text(encoding="utf-8")
    # cada pacote começa num <h2 class="title"><a id="X" ...></a>Nome-versão</h2>
    heads = list(re.finditer(r'<h([23]) class="(?:title|sect2)">\s*<a id="([^"]+)"[^>]*></a>(.*?)</h\1>', s, re.S))
    pkgs = {}
    for n, m in enumerate(heads):
        pid, title = m.group(2), " ".join(text(m.group(3)).split())
        body = s[m.end(): heads[n + 1].start() if n + 1 < len(heads) else len(s)]
        urls = re.findall(r'Download \(HTTPS?\):\s*<a class="ulink" href=\s*"([^"]+)"', body)
        md5 = re.findall(r"Download MD5 sum:\s*([0-9a-f]{32})", body)
        extra = re.findall(r'(?:Required|Recommended|Optional)?\s*(?:patch|Patch)[^<]*:\s*<a class="ulink" href=\s*"([^"]+)"', body)
        pkgdiv = body.split('<div class="installation"')[0]
        def deps(cls, label=None):
            out = []
            # o bloco <h5>Label</h5><p class="cls">…</p>
            for h5, p in re.findall(r"<h5>((?:(?!</h5>).)*?)</h5>\s*<p class=\"" + cls + r"\">(.*?)</p>", pkgdiv, re.S):
                lab = " ".join(text(h5).split())
                if label and lab != label:
                    continue
                out += re.findall(r'class="xref"\s+href=\s*"#([^"]+)"', p)
            return out
        cmds = []
        for kind, pre in re.findall(r'<pre class="(userinput|root)">(.*?)</pre>', body, re.S):
            cmds.append(text(pre))
        if not (urls or cmds):
            continue
        pkgs[pid] = dict(title=title, urls=urls, md5=md5, patches=extra,
                         required=deps("required", "Required"),
                         runtime=deps("required", "Required Runtime"),
                         recommended=deps("recommended", "Recommended"),
                         cmds=cmds)
    CACHE.write_text(json.dumps(pkgs))
    return pkgs


def order(pkgs, roots, rec=True, skip=()):
    seen, out, stack = set(), [], set()
    def visit(p, path):
        if p in seen or p in skip or p not in pkgs:
            return
        if p in stack:  # ciclo (normalmente via recommended): ignora
            return
        stack.add(p)
        d = pkgs[p]
        for q in d["required"] + (d["recommended"] if rec else []):
            visit(q, path + [p])
        stack.discard(p)
        seen.add(p); out.append(p)
        for q in d["runtime"]:
            visit(q, path + [p])
    for r in roots:
        visit(r, [])
    return out


def urls_main(ids):
    pkgs = parse()
    for a in ids:
        d = pkgs[a]
        for n, u in enumerate(d["urls"]):
            print(u, d["md5"][n] if n < len(d["md5"]) else "-")
        for u in d["patches"]:
            print(u, "-")


if __name__ == "__main__":
    pkgs = parse()
    cmd, args = sys.argv[1], sys.argv[2:]
    if cmd == "urls": sys.exit(urls_main(args))
    if cmd == "info":
        for a in args:
            d = pkgs[a]
            print(f"### {a}: {d['title']}")
            for k in ("urls", "md5", "patches", "required", "runtime", "recommended"):
                print(f"  {k}: {' '.join(d[k])}")
            for c in d["cmds"]:
                print("  ---\n" + "\n".join("    " + l for l in c.splitlines()))
    elif cmd == "deps":
        rec = "--no-rec" not in args
        skip = set()
        if "--skip" in args:
            i = args.index("--skip"); skip = set(args[i + 1].split(",")); args = args[:i] + args[i + 2:]
        args = [a for a in args if not a.startswith("--")]
        for p in order(pkgs, args, rec, skip):
            print(p, "\t", pkgs[p]["title"])
    elif cmd == "text":
        raw = BOOK.read_text(encoding="utf-8")
        for a in args:
            i = raw.find(f'id="{a}"')
            j = min([x for x in (raw.find('<h2 class="title">', i + 10), raw.find('<h3 class="sect2">\n                  <a id=', i + 10)) if x > 0] or [len(raw)])
            t = raw[i:j]
            t = re.sub(r"<pre[^>]*>", "\n$$$\n", t); t = re.sub(r"</pre>", "\n===\n", t)
            t = html.unescape(re.sub(r"<[^>]+>", "", t))
            t = re.sub(r"[ \t]+\n", "\n", t); t = re.sub(r"\n\s*\n+", "\n", t)
            print(f"########## {a}\n{t}")
    elif cmd == "ids":
        for p, d in pkgs.items():
            if re.search(args[0], p + " " + d["title"], re.I):
                print(p, "\t", d["title"])

