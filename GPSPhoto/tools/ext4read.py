"""Minimal read-only ext4 reader for a raw Windows disk.
usage: python ext4read.py <device> <part_offset> ls <path>
       python ext4read.py <device> <part_offset> get <path> <dest_dir> [suffix]
"""
import os, struct, sys


class Dev:
    """Sector-aligned reads from a raw device (required by Windows)."""
    def __init__(self, path, base):
        self.f = open(path, 'rb', buffering=0)
        self.base = base

    def read(self, off, n):
        a = (self.base + off) // 4096 * 4096
        end = self.base + off + n
        b = -(-end // 4096) * 4096
        self.f.seek(a)
        data = self.f.read(b - a)
        s = self.base + off - a
        return data[s:s + n]


class Ext4:
    def __init__(self, dev):
        self.d = dev
        sb = dev.read(1024, 1024)
        assert struct.unpack_from('<H', sb, 0x38)[0] == 0xEF53, 'not ext4'
        self.bs = 1024 << struct.unpack_from('<I', sb, 0x18)[0]
        self.ipg = struct.unpack_from('<I', sb, 0x28)[0]
        self.isz = struct.unpack_from('<H', sb, 0x58)[0]
        incompat = struct.unpack_from('<I', sb, 0x60)[0]
        self.is64 = bool(incompat & 0x80)
        self.dsz = struct.unpack_from('<H', sb, 0xFE)[0] if self.is64 else 32
        first = struct.unpack_from('<I', sb, 0x14)[0]
        self.gdt = (first + 1) * self.bs

    def blk(self, n, count=1):
        return self.d.read(n * self.bs, count * self.bs)

    def inode(self, ino):
        g, i = divmod(ino - 1, self.ipg)
        gd = self.d.read(self.gdt + g * self.dsz, self.dsz)
        lo = struct.unpack_from('<I', gd, 8)[0]
        hi = struct.unpack_from('<I', gd, 0x28)[0] if self.dsz >= 64 else 0
        table = lo | (hi << 32)
        return self.d.read(table * self.bs + i * self.isz, self.isz)

    def extents(self, node):
        magic, entries, _, depth = struct.unpack_from('<HHHH', node, 0)
        assert magic == 0xF30A, 'no extent header'
        for k in range(entries):
            e = node[12 + 12 * k: 24 + 12 * k]
            if depth == 0:
                lblk, ln, hi, lo = struct.unpack('<IHHI', e)
                if ln > 32768:
                    ln -= 32768          # uninitialized extent: reads as zeros
                    yield lblk, None, ln
                else:
                    yield lblk, lo | (hi << 32), ln
            else:
                lblk, lo, hi = struct.unpack_from('<IIH', e)
                yield from self.extents(self.blk(lo | (hi << 32)))

    def data(self, ino):
        raw = self.inode(ino)
        size = struct.unpack_from('<I', raw, 4)[0] | (struct.unpack_from('<I', raw, 0x6C)[0] << 32)
        out = bytearray(size)
        for lblk, pblk, ln in self.extents(raw[0x28:0x28 + 60]):
            start = lblk * self.bs
            if start >= size:
                continue
            chunk = bytes(ln * self.bs) if pblk is None else self.blk(pblk, ln)
            out[start:start + len(chunk)] = chunk[:size - start]
        return bytes(out), raw

    def listdir(self, ino):
        buf, _ = self.data(ino)
        res, p = {}, 0
        while p < len(buf):
            dino, rec, nlen, ftype = struct.unpack_from('<IHBB', buf, p)
            if rec < 8:
                break
            if dino and nlen:
                res[buf[p + 8:p + 8 + nlen].decode('utf-8', 'replace')] = dino
            p += rec
        return res

    def lookup(self, path):
        ino = 2
        for part in [x for x in path.split('/') if x]:
            ino = self.listdir(ino)[part]
        return ino


def main():
    dev, off, cmd, path = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]
    fs = Ext4(Dev(dev, off))
    d = fs.lookup(path)
    for name, ino in sorted(fs.listdir(d).items()):
        if name in ('.', '..'):
            continue
        content, raw = fs.data(ino)
        mtime = struct.unpack_from('<I', raw, 0x10)[0]
        if cmd == 'ls':
            print(f'{len(content):10d}  {name}')
        elif cmd == 'get':
            dest, suffix = sys.argv[5], (sys.argv[6] if len(sys.argv) > 6 else '')
            base, ext = os.path.splitext(name)
            target = os.path.join(dest, base + suffix + ext)
            with open(target, 'wb') as f:
                f.write(content)
            os.utime(target, (mtime, mtime))
            print(f'{len(content):10d}  {target}')


if __name__ == '__main__':
    main()
