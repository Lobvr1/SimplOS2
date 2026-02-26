# SimplOS 2 (ASM-only, 2-stage)

Minimal bootable OS starter using only x86 assembly, split into:
- bootloader (`512` bytes)
- kernel (loaded from later floppy sectors)

## Files
- `src/boot.asm`: stage-1 bootloader, loads kernel to `0x1000:0000`
- `src/kernel.asm`: stage-2 kernel (graphics + menu + power actions)
- `build_iso.bat`: builds binaries and writes a bootable floppy image

## Requirements
- `D:\nasm\nasm.exe`

## Build
```bat
build_iso.bat
```

Output goes to `out\`:
- `boot.bin`
- `kernel.bin`
- `floppy.img` (or `floppy_alt.img` if locked)
