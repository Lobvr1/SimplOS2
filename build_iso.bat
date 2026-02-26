@echo off
setlocal EnableExtensions

set "ROOT=%~dp0"
set "BOOT_SRC=%ROOT%src\boot.asm"
set "KERNEL_SRC=%ROOT%src\kernel.asm"
set "OUTDIR=%ROOT%out"
set "BOOTBIN=%OUTDIR%\boot.bin"
set "KERNELBIN=%OUTDIR%\kernel.bin"
set "FLOPPY=%OUTDIR%\floppy.img"
set "FLOPPY_ALT=%OUTDIR%\floppy_alt.img"
set "FLOPPY_META=%OUTDIR%\last_floppy_path.txt"
set "ISO=%OUTDIR%\SimplOS2.iso"
set "NASM_EXE=D:\nasm\nasm.exe"
set "KERNEL_SECTORS=32"

if not exist "%BOOT_SRC%" (
  echo ERROR: Missing %BOOT_SRC%
  exit /b 1
)
if not exist "%KERNEL_SRC%" (
  echo ERROR: Missing %KERNEL_SRC%
  exit /b 1
)

for %%I in ("%NASM_EXE%") do set "NASM_NAME=%%~nxI"
if /i "%NASM_NAME%"=="ndisasm.exe" (
  echo ERROR: NASM_EXE points to ndisasm.exe.
  echo Use nasm.exe for assembling.
  exit /b 1
)

if not exist "%NASM_EXE%" (
  echo ERROR: NASM executable not found at:
  echo   %NASM_EXE%
  exit /b 1
)

if not exist "%OUTDIR%" mkdir "%OUTDIR%"

echo [1/4] Assembling boot sector...
"%NASM_EXE%" -f bin "%BOOT_SRC%" -o "%BOOTBIN%"
if errorlevel 1 exit /b 1
for %%I in ("%BOOTBIN%") do set "BOOT_SIZE=%%~zI"
if not "%BOOT_SIZE%"=="512" (
  echo ERROR: boot.bin must be exactly 512 bytes. Got %BOOT_SIZE%.
  exit /b 1
)

echo [2/4] Assembling kernel...
"%NASM_EXE%" -f bin "%KERNEL_SRC%" -o "%KERNELBIN%"
if errorlevel 1 exit /b 1
for %%I in ("%KERNELBIN%") do set "KERNEL_SIZE=%%~zI"
set /a "KERNEL_MAX=%KERNEL_SECTORS%*512"
if %KERNEL_SIZE% GTR %KERNEL_MAX% (
  echo ERROR: kernel.bin is too large: %KERNEL_SIZE% bytes. Max is %KERNEL_MAX%.
  exit /b 1
)

echo [3/4] Creating bootable floppy image...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop';" ^
  "$primary = '%FLOPPY%'; $fallback = '%FLOPPY_ALT%'; $chosen = $primary;" ^
  "$kernelSectors = %KERNEL_SECTORS%;" ^
  "$img = New-Object byte[] 1474560;" ^
  "$boot = [IO.File]::ReadAllBytes('%BOOTBIN%'); if($boot.Length -ne 512){ throw 'boot.bin must be exactly 512 bytes'; }" ^
  "$kernel = [IO.File]::ReadAllBytes('%KERNELBIN%'); if($kernel.Length -gt ($kernelSectors*512)){ throw 'kernel.bin exceeds configured sector budget'; }" ^
  "$writeImage = {" ^
  "  param($path);" ^
  "  [IO.File]::WriteAllBytes($path, $img);" ^
  "  $fs = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None);" ^
  "  try {" ^
  "    $kernelLba = 33; $fat1Lba = 1; $fat2Lba = 10; $rootLba = 19;" ^
  "    $bytesPerSector = 512; $sectorsPerFat = 9; $rootEntries = 224; $rootSectors = 14;" ^
  "    $kernelClusters = [int][Math]::Ceiling($kernel.Length / 512.0);" ^
  "    if($kernelClusters -lt 1){ $kernelClusters = 1 }" ^
  "    $note = [Text.Encoding]::ASCII.GetBytes('SimplOS FAT12 volume OK.' + [Environment]::NewLine);" ^
  "    $noteCluster = 2 + $kernelClusters;" ^
  "    $fs.Write($boot,0,512);" ^
  "    $fs.Position = $kernelLba * $bytesPerSector; $fs.Write($kernel,0,$kernel.Length);" ^
  "    $fs.Position = $noteCluster * $bytesPerSector + ($kernelLba - 2) * $bytesPerSector; $fs.Write($note,0,$note.Length);" ^
  "    $fat = New-Object byte[] ($sectorsPerFat * $bytesPerSector);" ^
  "    $fat[0] = 0xF0; $fat[1] = 0xFF; $fat[2] = 0xFF;" ^
  "    function Set-Fat12([byte[]]$arr,[int]$cluster,[int]$value){ $offset=[int](($cluster*3)/2); if(($cluster -band 1)-eq 0){ $arr[$offset]=[byte]($value -band 0xFF); $arr[$offset+1]=[byte](($arr[$offset+1]-band 0xF0) -bor (($value -shr 8)-band 0x0F)); } else { $arr[$offset]=[byte](($arr[$offset]-band 0x0F) -bor (($value -shl 4)-band 0xF0)); $arr[$offset+1]=[byte](($value -shr 4)-band 0xFF); } }" ^
  "    $start = 2;" ^
  "    for($i=0;$i -lt $kernelClusters;$i++){ $c = $start + $i; if($i -eq ($kernelClusters-1)){ Set-Fat12 $fat $c 0xFFF } else { Set-Fat12 $fat $c ($c+1) } }" ^
  "    Set-Fat12 $fat $noteCluster 0xFFF;" ^
  "    $fs.Position = $fat1Lba * $bytesPerSector; $fs.Write($fat,0,$fat.Length);" ^
  "    $fs.Position = $fat2Lba * $bytesPerSector; $fs.Write($fat,0,$fat.Length);" ^
  "    $root = New-Object byte[] ($rootSectors * $bytesPerSector);" ^
  "    function Set-RootEntry([byte[]]$root,[int]$idx,[string]$name11,[int]$startCluster,[int]$size){ $off=$idx*32; $n=[Text.Encoding]::ASCII.GetBytes($name11); [Array]::Copy($n,0,$root,$off,11); $root[$off+11]=0x20; $root[$off+26]=[byte]($startCluster -band 0xFF); $root[$off+27]=[byte](($startCluster -shr 8)-band 0xFF); $root[$off+28]=[byte]($size -band 0xFF); $root[$off+29]=[byte](($size -shr 8)-band 0xFF); $root[$off+30]=[byte](($size -shr 16)-band 0xFF); $root[$off+31]=[byte](($size -shr 24)-band 0xFF); }" ^
  "    Set-RootEntry $root 0 'KERNEL  BIN' 2 $kernel.Length;" ^
  "    Set-RootEntry $root 1 'SIMPLOS TXT' $noteCluster $note.Length;" ^
  "    $fs.Position = $rootLba * $bytesPerSector; $fs.Write($root,0,$root.Length);" ^
  "  } finally { $fs.Dispose() }" ^
  "};" ^
  "try { & $writeImage $primary } catch [System.IO.IOException] { Write-Host 'WARN: floppy.img is locked; using floppy_alt.img'; $chosen = $fallback; & $writeImage $fallback };" ^
  "[IO.File]::WriteAllText('%FLOPPY_META%', $chosen);"
if errorlevel 1 exit /b 1
if not exist "%FLOPPY_META%" (
  echo ERROR: Failed to determine floppy output path.
  exit /b 1
)
set /p FLOPPY=<"%FLOPPY_META%"
for %%I in ("%FLOPPY%") do set "FLOPPY_NAME=%%~nxI"

echo [4/4] Creating ISO (optional)...
set "ISOTOOL="
where oscdimg >nul 2>nul && set "ISOTOOL=oscdimg"
if not defined ISOTOOL where mkisofs >nul 2>nul && set "ISOTOOL=mkisofs"
if not defined ISOTOOL where genisoimage >nul 2>nul && set "ISOTOOL=genisoimage"
if not defined ISOTOOL where xorriso >nul 2>nul && set "ISOTOOL=xorriso"

if not defined ISOTOOL (
  echo No ISO tool found. Skipping ISO creation.
  goto done
)

pushd "%OUTDIR%"
if /i "%ISOTOOL%"=="oscdimg" (
  oscdimg -n -m -b"%FLOPPY%" . "SimplOS2.iso"
) else if /i "%ISOTOOL%"=="xorriso" (
  xorriso -as mkisofs -V "SIMPLOS2" -o "SimplOS2.iso" -b "%FLOPPY_NAME%" -no-emul-boot -boot-load-size 4 -boot-info-table .
) else (
  %ISOTOOL% -V "SIMPLOS2" -o "SimplOS2.iso" -b "%FLOPPY_NAME%" -no-emul-boot -boot-load-size 4 -boot-info-table .
)
set "RC=%ERRORLEVEL%"
popd
if not "%RC%"=="0" (
  echo ISO tool failed. Keeping floppy image only.
)

:done
echo.
echo Build complete:
echo   %BOOTBIN%
echo   %KERNELBIN%
echo   %FLOPPY%
if exist "%ISO%" (
  echo   %ISO%
) else (
  echo   ISO not created
)
exit /b 0
