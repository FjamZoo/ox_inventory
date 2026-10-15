[CmdletBinding()]
param(
    [string] $VcVarsPath,
    [string] $BuildDirectory
)

$ErrorActionPreference = 'Stop'
$luaRevision = '4b086dc082da96a8e21aaa38ef7c0f4a7697f2a4'
$glmRevision = 'c1b4c6b60135d5c286052b4affaf5b330a057c8c'

if (-not $VcVarsPath) {
    $vswherePath = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
    if (Test-Path -LiteralPath $vswherePath) {
        $installationPath = & $vswherePath -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
        if ($installationPath) {
            $VcVarsPath = Join-Path $installationPath 'VC/Auxiliary/Build/vcvars64.bat'
        }
    }
}

if (-not $VcVarsPath -or -not (Test-Path -LiteralPath $VcVarsPath -PathType Leaf)) {
    throw 'Install MSVC C++ build tools or pass -VcVarsPath with the full vcvars64.bat path.'
}

if (-not $BuildDirectory) {
    $BuildDirectory = Join-Path ([IO.Path]::GetTempPath()) ('ox-inventory-cfxlua-' + [Guid]::NewGuid().ToString('N'))
}

if (Test-Path -LiteralPath $BuildDirectory) {
    throw 'BuildDirectory must be a new directory. Existing directories are never modified or removed.'
}

$buildRoot = (New-Item -ItemType Directory -Path $BuildDirectory).FullName
$luaArchive = Join-Path $buildRoot 'lua.zip'
$glmArchive = Join-Path $buildRoot 'glm.zip'
Invoke-WebRequest -Uri "https://codeload.github.com/citizenfx/lua/zip/$luaRevision" -OutFile $luaArchive
Invoke-WebRequest -Uri "https://codeload.github.com/citizenfx/glm/zip/$glmRevision" -OutFile $glmArchive
Expand-Archive -LiteralPath $luaArchive -DestinationPath $buildRoot
Expand-Archive -LiteralPath $glmArchive -DestinationPath $buildRoot

$luaPath = Join-Path $buildRoot "lua-$luaRevision"
$glmPath = Join-Path $buildRoot "glm-$glmRevision"
$executable = Join-Path $luaPath 'cfxlua.exe'
$compileScript = Join-Path $buildRoot 'compile.cmd'
$compileLines = @(
    '@echo off'
    "call `"$VcVarsPath`""
    'if errorlevel 1 exit /b %errorlevel%'
    "cd /d `"$luaPath`""
    "cl /nologo /O2 /TP /EHsc /I`"$glmPath`" /DLUA_USE_LONGJMP /DGRIT_POWER_COMPOUND /DGRIT_POWER_SAFENAV /DGRIT_POWER_JOAAT /DGRIT_POWER_TABINIT /DGRIT_POWER_INTABLE /DGRIT_POWER_CCOMMENT /DLUA_COMPAT_5_3 onelua.c /Fe:cfxlua.exe"
    'exit /b %errorlevel%'
)
Set-Content -LiteralPath $compileScript -Value $compileLines -Encoding ascii
& $env:ComSpec /d /c $compileScript
if ($LASTEXITCODE -ne 0) { throw "CfxLua compilation failed with exit code $LASTEXITCODE. Sources remain at $buildRoot" }

& $executable -e 'local count = 1; count += 1; local value = {}; assert(value.missing?.field == nil); assert(count == 2); assert(type(vector3(0, 0, 0)) == "vector3"); print(_VERSION)'
if ($LASTEXITCODE -ne 0) { throw 'The built interpreter failed its CfxLua syntax smoke check.' }

Write-Output $executable
