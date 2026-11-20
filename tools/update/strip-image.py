#!/usr/bin/env python3
"""Tira os símbolos de depuração aos programas e bibliotecas da imagem (corre no chroot da cópia).

O lfs.img fica com eles (para depurar no ambiente de construção); a imagem publicada não precisa.
Só mexe em ELF executáveis e bibliotecas partilhadas que ainda tenham .symtab/.debug_*;
deixa os módulos do kernel, os .o/.a, o firmware e o Flatpak (o ostree confirma os ficheiros).
Mantém dono, permissões (setuid incluído), datas, xattrs (capabilities) e ligações físicas.
"""
import os
import stat
import struct
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

SKIP = ("/proc", "/sys", "/dev", "/run", "/tmp", "/sources", "/tools", "/boot",
        "/usr/lib/firmware", "/usr/lib/modules", "/usr/lib/debug", "/var/lib/flatpak",
        "/var/tmp", "/var/cache", "/var/log")
# o gdb e o valgrind precisam dos símbolos destas (como no LFS): só se tira a depuração
DEBUG_ONLY = ("ld-linux-x86-64.so", "libc.so", "libthread_db.so", "libpthread.so",
              "libstdc++.so", "libquadmath.so", "libitm.so", "libatomic.so")


def needs_strip(path):
    try:
        with open(path, "rb") as f:
            h = f.read(64)
            if len(h) < 64 or h[:4] != b"\x7fELF" or h[4] != 2 or h[5] != 1:
                return False
            e_type = struct.unpack_from("<H", h, 16)[0]
            if e_type not in (2, 3):          # só EXEC e DYN
                return False
            shoff = struct.unpack_from("<Q", h, 0x28)[0]
            shentsize, shnum, shstrndx = struct.unpack_from("<HHH", h, 0x3A)
            if not shoff or not shnum or shstrndx >= shnum or shentsize < 64:
                return False
            f.seek(shoff)
            sh = f.read(shentsize * shnum)
            if len(sh) < shentsize * shnum:
                return False
            str_off, str_size = struct.unpack_from("<QQ", sh, shstrndx * shentsize + 0x18)
            f.seek(str_off)
            names = f.read(min(str_size, 1 << 20))
    except OSError:
        return False
    return b"\0.symtab\0" in b"\0" + names or b".debug_" in names


def walk():
    seen = {}
    for root, dirs, files in os.walk("/"):
        if root.startswith(SKIP) and any(root == s or root.startswith(s + "/") for s in SKIP):
            dirs[:] = []
            continue
        dirs[:] = [d for d in dirs if os.path.join(root, d) not in SKIP]
        for n in files:
            p = os.path.join(root, n)
            try:
                st = os.lstat(p)
            except OSError:
                continue
            if not stat.S_ISREG(st.st_mode) or st.st_size < 1024:
                continue
            key = (st.st_dev, st.st_ino)
            if key in seen:
                seen[key][1].append(p)
            else:
                seen[key] = [p, []]
    return seen.values()


def do(item):
    path, links = item
    if not needs_strip(path):
        return 0
    st = os.lstat(path)
    xattrs = {}
    try:
        for k in os.listxattr(path, follow_symlinks=False):
            xattrs[k] = os.getxattr(path, k, follow_symlinks=False)
    except OSError:
        pass
    mode = ["--strip-debug"] if os.path.basename(path).startswith(DEBUG_ONLY) else ["--strip-unneeded"]
    tmp = path + ".nexora-strip"
    r = subprocess.run(["strip", *mode, "-o", tmp, path], capture_output=True)
    if r.returncode != 0 or not os.path.exists(tmp):
        try:
            os.unlink(tmp)
        except OSError:
            pass
        print(f"  (ficou como estava) {path}: {r.stderr.decode(errors='replace').strip()[:120]}")
        return 0
    os.chown(tmp, st.st_uid, st.st_gid)
    os.chmod(tmp, stat.S_IMODE(st.st_mode))
    for k, v in xattrs.items():
        os.setxattr(tmp, k, v)
    os.utime(tmp, ns=(st.st_atime_ns, st.st_mtime_ns))
    saved = st.st_size - os.path.getsize(tmp)
    os.rename(tmp, path)
    for l in links:                       # as outras ligações físicas apontam para o novo
        os.unlink(l)
        os.link(path, l)
    return saved


def main():
    items = list(walk())
    with ThreadPoolExecutor(max_workers=os.cpu_count() or 4) as ex:
        res = list(ex.map(do, items))
    n = sum(1 for s in res if s > 0)
    print(f"   strip: {n} ficheiros, menos {sum(res) / 1e6:.0f} MB")


if __name__ == "__main__":
    sys.exit(main())
