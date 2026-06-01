# ── Pure QR Code Generator (no external dependencies) ─────────────────────────
# Implements QR Code Model 2 encoding: byte mode, EC level M, versions 1-10.
# Returns a WPF WriteableBitmap suitable for display in an Image control.
#
# NOTE: All array-returning helper functions use script-scope temp variables
# instead of pipeline returns to avoid PowerShell 5.1 array unrolling issues.

# ── GF(256) Arithmetic ────────────────────────────────────────────────────────
$script:gfExp = [int[]]::new(512)
$script:gfLog = [int[]]::new(256)

$val = 1
for ($i = 0; $i -lt 255; $i++) {
    $script:gfExp[$i] = $val
    $script:gfLog[$val] = $i
    $val = $val -shl 1
    if ($val -ge 256) { $val = $val -bxor 0x11D }
}
for ($i = 255; $i -lt 512; $i++) {
    $script:gfExp[$i] = $script:gfExp[$i - 255]
}

function GF-Multiply([int]$a, [int]$b) {
    if ($a -eq 0 -or $b -eq 0) { return 0 }
    return $script:gfExp[$script:gfLog[$a] + $script:gfLog[$b]]
}

# ── Version geometry (level-independent) ─────────────────────────────────────
$script:qrVersions = @{}
$script:qrVersions[1]  = @{ Size=21; Total=26  }
$script:qrVersions[2]  = @{ Size=25; Total=44  }
$script:qrVersions[3]  = @{ Size=29; Total=70  }
$script:qrVersions[4]  = @{ Size=33; Total=100 }
$script:qrVersions[5]  = @{ Size=37; Total=134 }
$script:qrVersions[6]  = @{ Size=41; Total=172 }
$script:qrVersions[7]  = @{ Size=45; Total=196 }
$script:qrVersions[8]  = @{ Size=49; Total=242 }
$script:qrVersions[9]  = @{ Size=53; Total=292 }
$script:qrVersions[10] = @{ Size=57; Total=346 }

# ── Per-(version, EC level) codeword layout, byte mode (ISO/IEC 18004) ───────
# Tables cover error-correction levels L, M, Q, H for versions 1-10.
# These constants MUST be exact or the resulting codes will not scan; the
# helper below self-validates each entry against the version's Total at load.
$script:_qrTmpBlk = $null
function script:_QR-MakeBlocks([int[]]$pairs) {
    # $pairs is a flat list of (count, dataCodewordsPerBlock) groups.
    $list = [System.Collections.Generic.List[int[]]]::new()
    for ([int]$i = 0; $i -lt $pairs.Count; $i += 2) {
        $list.Add([int[]]@($pairs[$i], $pairs[$i + 1]))
    }
    $script:_qrTmpBlk = $list
}

$script:qrEC = @{}
for ([int]$v = 1; $v -le 10; $v++) { $script:qrEC[$v] = @{} }

function script:_QR-SetEC([int]$v, [string]$lvl, [int]$ecPer, [int]$dataCW, [int]$cap, [int[]]$blocks) {
    [int]$blkCount = 0
    [int]$sumData  = 0
    for ([int]$i = 0; $i -lt $blocks.Count; $i += 2) {
        $blkCount += $blocks[$i]
        $sumData  += $blocks[$i] * $blocks[$i + 1]
    }
    if ($sumData -ne $dataCW) {
        throw "QR table error v$v level $lvl: DataCW $dataCW != block sum $sumData"
    }
    if (($dataCW + $ecPer * $blkCount) -ne [int]$script:qrVersions[$v].Total) {
        throw "QR table error v$v level $lvl: $dataCW + $ecPer*$blkCount != Total $([int]$script:qrVersions[$v].Total)"
    }
    script:_QR-MakeBlocks $blocks
    $script:qrEC[$v][$lvl] = @{
        ECPer          = $ecPer
        DataCW         = $dataCW
        Capacity       = $cap
        Blocks         = $blkCount
        BlockStructure = $script:_qrTmpBlk
    }
}

# Level L
script:_QR-SetEC 1  'L' 7  19  17  @(1,19)
script:_QR-SetEC 2  'L' 10 34  32  @(1,34)
script:_QR-SetEC 3  'L' 15 55  53  @(1,55)
script:_QR-SetEC 4  'L' 20 80  78  @(1,80)
script:_QR-SetEC 5  'L' 26 108 106 @(1,108)
script:_QR-SetEC 6  'L' 18 136 134 @(2,68)
script:_QR-SetEC 7  'L' 20 156 154 @(2,78)
script:_QR-SetEC 8  'L' 24 194 192 @(2,97)
script:_QR-SetEC 9  'L' 30 232 230 @(2,116)
script:_QR-SetEC 10 'L' 18 274 271 @(2,68, 2,69)

# Level M
script:_QR-SetEC 1  'M' 10 16  14  @(1,16)
script:_QR-SetEC 2  'M' 16 28  26  @(1,28)
script:_QR-SetEC 3  'M' 26 44  42  @(1,44)
script:_QR-SetEC 4  'M' 18 64  62  @(2,32)
script:_QR-SetEC 5  'M' 24 86  84  @(2,43)
script:_QR-SetEC 6  'M' 16 108 106 @(4,27)
script:_QR-SetEC 7  'M' 18 124 122 @(4,31)
script:_QR-SetEC 8  'M' 22 154 152 @(2,38, 2,39)
script:_QR-SetEC 9  'M' 22 182 180 @(3,36, 2,37)
script:_QR-SetEC 10 'M' 26 216 213 @(4,43, 1,44)

# Level Q
script:_QR-SetEC 1  'Q' 13 13  11  @(1,13)
script:_QR-SetEC 2  'Q' 22 22  20  @(1,22)
script:_QR-SetEC 3  'Q' 18 34  32  @(2,17)
script:_QR-SetEC 4  'Q' 26 48  46  @(2,24)
script:_QR-SetEC 5  'Q' 18 62  60  @(2,15, 2,16)
script:_QR-SetEC 6  'Q' 24 76  74  @(4,19)
script:_QR-SetEC 7  'Q' 18 88  86  @(2,14, 4,15)
script:_QR-SetEC 8  'Q' 22 110 108 @(4,18, 2,19)
script:_QR-SetEC 9  'Q' 20 132 130 @(4,16, 4,17)
script:_QR-SetEC 10 'Q' 24 154 151 @(6,19, 2,20)

# Level H
script:_QR-SetEC 1  'H' 17 9   7   @(1,9)
script:_QR-SetEC 2  'H' 28 16  14  @(1,16)
script:_QR-SetEC 3  'H' 22 26  24  @(2,13)
script:_QR-SetEC 4  'H' 16 36  34  @(4,9)
script:_QR-SetEC 5  'H' 22 46  44  @(2,11, 2,12)
script:_QR-SetEC 6  'H' 28 60  58  @(4,15)
script:_QR-SetEC 7  'H' 26 66  64  @(4,13, 1,14)
script:_QR-SetEC 8  'H' 26 86  84  @(4,14, 2,15)
script:_QR-SetEC 9  'H' 24 100 98  @(4,12, 4,13)
script:_QR-SetEC 10 'H' 28 122 119 @(6,15, 2,16)

# Alignment pattern center positions per version
$script:qrAlignmentPositions = @{}
$script:qrAlignmentPositions[1]  = [int[]]@()
$script:qrAlignmentPositions[2]  = [int[]]@(6, 18)
$script:qrAlignmentPositions[3]  = [int[]]@(6, 22)
$script:qrAlignmentPositions[4]  = [int[]]@(6, 26)
$script:qrAlignmentPositions[5]  = [int[]]@(6, 30)
$script:qrAlignmentPositions[6]  = [int[]]@(6, 34)
$script:qrAlignmentPositions[7]  = [int[]]@(6, 22, 38)
$script:qrAlignmentPositions[8]  = [int[]]@(6, 24, 42)
$script:qrAlignmentPositions[9]  = [int[]]@(6, 26, 46)
$script:qrAlignmentPositions[10] = [int[]]@(6, 28, 50)

# Pre-computed 15-bit format info strings (BCH, already mask-XORed), per EC
# level and mask 0-7. EC indicator bits: L=01, M=00, Q=11, H=10.
$script:formatInfoBits = @{
    'L' = [int[]]@(0x77C4, 0x72F3, 0x7DAA, 0x789D, 0x662F, 0x6318, 0x6C41, 0x6976)
    'M' = [int[]]@(0x5412, 0x5125, 0x5E7C, 0x5B4B, 0x45F9, 0x40CE, 0x4F97, 0x4AA0)
    'Q' = [int[]]@(0x355F, 0x3068, 0x3F31, 0x3A06, 0x24B4, 0x2183, 0x2EDA, 0x2BED)
    'H' = [int[]]@(0x1689, 0x13BE, 0x1CE7, 0x19D0, 0x0762, 0x0255, 0x0D0C, 0x083B)
}

# Finder pattern as 2D array
$script:finderPattern = [int[,]]::new(7, 7)
$fpData = @(1,1,1,1,1,1,1, 1,0,0,0,0,0,1, 1,0,1,1,1,0,1, 1,0,1,1,1,0,1, 1,0,1,1,1,0,1, 1,0,0,0,0,0,1, 1,1,1,1,1,1,1)
for ($i = 0; $i -lt 49; $i++) { $script:finderPattern[([Math]::Floor($i / 7)), ($i % 7)] = $fpData[$i] }

# Alignment pattern as 2D array
$script:alignPattern = [int[,]]::new(5, 5)
$apData = @(1,1,1,1,1, 1,0,0,0,1, 1,0,1,0,1, 1,0,0,0,1, 1,1,1,1,1)
for ($i = 0; $i -lt 25; $i++) { $script:alignPattern[([Math]::Floor($i / 5)), ($i % 5)] = $apData[$i] }

# ── Temp variables for pipeline-safe array passing ────────────────────────────
$script:_qrTmpGen = $null
$script:_qrTmpEC = $null
$script:_qrTmpData = $null
$script:_qrTmpInterleaved = $null
$script:_qrTmpMatrix = $null
$script:_qrTmpMasked = $null
$script:_qrTmpFinal = $null

# ── Reed-Solomon ──────────────────────────────────────────────────────────────

function _QR-BuildGenerator([int]$count) {
    $gen = [int[]]@(1)
    for ([int]$i = 0; $i -lt $count; $i++) {
        $newGen = [int[]]::new($gen.Count + 1)
        for ([int]$j = 0; $j -lt $gen.Count; $j++) {
            [int]$gfm = GF-Multiply $gen[$j] $script:gfExp[$i]
            $newGen[$j] = $newGen[$j] -bxor $gfm
            $newGen[$j + 1] = $newGen[$j + 1] -bxor $gen[$j]
        }
        $gen = $newGen
    }
    [Array]::Reverse($gen)
    $script:_qrTmpGen = $gen
}

function _QR-BuildECCodewords([byte[]]$data, [int]$numEC) {
    _QR-BuildGenerator $numEC
    [int[]]$gen = $script:_qrTmpGen
    [int]$genLen = $gen.Count

    $msg = [int[]]::new($data.Count + $numEC)
    for ([int]$i = 0; $i -lt $data.Count; $i++) { $msg[$i] = [int]$data[$i] }

    for ([int]$i = 0; $i -lt $data.Count; $i++) {
        [int]$coef = $msg[$i]
        if ($coef -ne 0) {
            for ([int]$j = 0; $j -lt $genLen; $j++) {
                [int]$gfm = GF-Multiply $gen[$j] $coef
                $msg[$i + $j] = $msg[$i + $j] -bxor $gfm
            }
        }
    }

    $ec = [byte[]]::new($numEC)
    for ([int]$i = 0; $i -lt $numEC; $i++) {
        $ec[$i] = [byte]$msg[$data.Count + $i]
    }
    $script:_qrTmpEC = $ec
}

# ── Data Encoding (byte mode) ────────────────────────────────────────────────

function _QR-EncodeData([string]$text, [int]$version, [string]$Level) {
    [int]$totalDataCW = [int]$script:qrEC[$version][$Level].DataCW
    [byte[]]$bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
    [int]$byteLen = $bytes.Count

    $bits = [System.Collections.Generic.List[int]]::new(($totalDataCW * 8 + 16))

    # Mode indicator: 0100 (byte mode)
    $null = $bits.Add(0); $null = $bits.Add(1); $null = $bits.Add(0); $null = $bits.Add(0)

    # Character count: 8 bits for v1-9
    [int]$countBits = if ($version -le 9) { 8 } else { 16 }
    for ([int]$i = $countBits - 1; $i -ge 0; $i--) {
        $null = $bits.Add(($byteLen -shr $i) -band 1)
    }

    # Data bytes
    for ([int]$bi = 0; $bi -lt $byteLen; $bi++) {
        [int]$bv = [int]$bytes[$bi]
        for ([int]$i = 7; $i -ge 0; $i--) {
            $null = $bits.Add(($bv -shr $i) -band 1)
        }
    }

    # Terminator
    [int]$totalBits = $totalDataCW * 8
    [int]$termLen = [Math]::Min(4, $totalBits - $bits.Count)
    for ([int]$i = 0; $i -lt $termLen; $i++) { $null = $bits.Add(0) }

    # Pad to byte boundary
    while (($bits.Count % 8) -ne 0) { $null = $bits.Add(0) }

    # Pad bytes
    [int]$padIdx = 0
    while ($bits.Count -lt $totalBits) {
        [int]$pb = if (($padIdx % 2) -eq 0) { 0xEC } else { 0x11 }
        for ([int]$i = 7; $i -ge 0; $i--) {
            $null = $bits.Add(($pb -shr $i) -band 1)
        }
        $padIdx = $padIdx + 1
    }

    # Convert bits to bytes
    $codewords = [byte[]]::new($totalDataCW)
    for ([int]$i = 0; $i -lt $totalDataCW; $i++) {
        [int]$v = 0
        for ([int]$j = 0; $j -lt 8; $j++) {
            $v = ($v -shl 1) -bor [int]$bits[($i * 8 + $j)]
        }
        $codewords[$i] = [byte]$v
    }

    $script:_qrTmpData = $codewords
}

# ── Interleave blocks and add EC ──────────────────────────────────────────────

function _QR-Interleave([byte[]]$dataCodewords, [int]$version, [string]$Level) {
    $ecInfo = $script:qrEC[$version][$Level]
    $blockGroups = $ecInfo.BlockStructure
    [int]$ecPerBlock = [int]$ecInfo.ECPer

    $dataBlocks = [System.Collections.Generic.List[byte[]]]::new()
    $ecBlocks   = [System.Collections.Generic.List[byte[]]]::new()
    [int]$offset = 0

    foreach ($group in $blockGroups) {
        [int]$numBlocks = [int]$group[0]
        [int]$dataPerBlock = [int]$group[1]
        for ([int]$b = 0; $b -lt $numBlocks; $b++) {
            $block = [byte[]]::new($dataPerBlock)
            [Array]::Copy($dataCodewords, $offset, $block, 0, $dataPerBlock)
            $offset = $offset + $dataPerBlock
            $null = $dataBlocks.Add($block)
            _QR-BuildECCodewords $block $ecPerBlock
            $null = $ecBlocks.Add(([byte[]]$script:_qrTmpEC))
        }
    }

    $result = [System.Collections.Generic.List[byte]]::new()
    [int]$maxDataLen = 0
    for ([int]$i = 0; $i -lt $dataBlocks.Count; $i++) {
        if ($dataBlocks[$i].Count -gt $maxDataLen) { $maxDataLen = $dataBlocks[$i].Count }
    }
    for ([int]$i = 0; $i -lt $maxDataLen; $i++) {
        for ([int]$bi = 0; $bi -lt $dataBlocks.Count; $bi++) {
            if ($i -lt $dataBlocks[$bi].Count) { $null = $result.Add($dataBlocks[$bi][$i]) }
        }
    }
    for ([int]$i = 0; $i -lt $ecPerBlock; $i++) {
        for ([int]$bi = 0; $bi -lt $ecBlocks.Count; $bi++) {
            if ($i -lt $ecBlocks[$bi].Count) { $null = $result.Add($ecBlocks[$bi][$i]) }
        }
    }

    $script:_qrTmpInterleaved = [byte[]]$result.ToArray()
}

# ── Matrix Construction ───────────────────────────────────────────────────────

function _QR-BuildMatrix([string]$text, [string]$Level) {
    [byte[]]$textBytes = [System.Text.Encoding]::UTF8.GetBytes($text)
    [int]$byteCount = $textBytes.Count

    [int]$version = 0
    for ([int]$v = 1; $v -le 10; $v++) {
        if ($byteCount -le [int]$script:qrEC[$v][$Level].Capacity) {
            $version = $v; break
        }
    }
    if ($version -eq 0) {
        [int]$maxCap = [int]$script:qrEC[10][$Level].Capacity
        throw "Text too long for QR code at EC level $Level (max $maxCap bytes)"
    }

    [int]$size = [int]$script:qrVersions[$version].Size

    $matrix   = [object[,]]::new($size, $size)
    $reserved = [bool[,]]::new($size, $size)

    # Finder patterns at three corners
    [int[]]$fpRows = @(0, 0, ($size - 7))
    [int[]]$fpCols = @(0, ($size - 7), 0)

    for ([int]$fp = 0; $fp -lt 3; $fp++) {
        [int]$r0 = $fpRows[$fp]
        [int]$c0 = $fpCols[$fp]
        for ([int]$r = 0; $r -lt 7; $r++) {
            for ([int]$c = 0; $c -lt 7; $c++) {
                $matrix[($r0 + $r), ($c0 + $c)] = [bool]$script:finderPattern[$r, $c]
                $reserved[($r0 + $r), ($c0 + $c)] = $true
            }
        }
    }

    # Separators
    for ([int]$i = 0; $i -lt 8; $i++) {
        $matrix[7, $i] = $false; $reserved[7, $i] = $true
        $matrix[$i, 7] = $false; $reserved[$i, 7] = $true
    }
    for ([int]$i = 0; $i -lt 8; $i++) {
        $matrix[7, ($size - 8 + $i)] = $false; $reserved[7, ($size - 8 + $i)] = $true
        $matrix[$i, ($size - 8)] = $false; $reserved[$i, ($size - 8)] = $true
    }
    for ([int]$i = 0; $i -lt 8; $i++) {
        $matrix[($size - 8), $i] = $false; $reserved[($size - 8), $i] = $true
        $matrix[($size - 8 + $i), 7] = $false; $reserved[($size - 8 + $i), 7] = $true
    }

    # Alignment patterns
    [int[]]$alignPos = $script:qrAlignmentPositions[$version]
    if ($alignPos -ne $null -and $alignPos.Count -gt 0) {
        $centerList = [System.Collections.Generic.List[int[]]]::new()
        foreach ($ar in $alignPos) {
            foreach ($ac in $alignPos) {
                [bool]$skip = $false
                for ([int]$fp = 0; $fp -lt 3; $fp++) {
                    if ([Math]::Abs([int]$ar - [int]($fpRows[$fp] + 3)) -le 5 -and
                        [Math]::Abs([int]$ac - [int]($fpCols[$fp] + 3)) -le 5) {
                        $skip = $true; break
                    }
                }
                if (-not $skip) { $null = $centerList.Add([int[]]@([int]$ar, [int]$ac)) }
            }
        }

        for ([int]$ci = 0; $ci -lt $centerList.Count; $ci++) {
            [int]$cr = $centerList[$ci][0]
            [int]$cc = $centerList[$ci][1]
            for ([int]$r = -2; $r -le 2; $r++) {
                for ([int]$c = -2; $c -le 2; $c++) {
                    [int]$mr = $cr + $r
                    [int]$mc = $cc + $c
                    $matrix[$mr, $mc] = [bool]$script:alignPattern[($r + 2), ($c + 2)]
                    $reserved[$mr, $mc] = $true
                }
            }
        }
    }

    # Timing patterns
    for ([int]$i = 8; $i -lt ($size - 8); $i++) {
        [bool]$dark = ($i % 2) -eq 0
        if (-not $reserved[6, $i]) { $matrix[6, $i] = $dark; $reserved[6, $i] = $true }
        if (-not $reserved[$i, 6]) { $matrix[$i, 6] = $dark; $reserved[$i, 6] = $true }
    }

    # Dark module
    $matrix[($size - 8), 8] = $true
    $reserved[($size - 8), 8] = $true

    # Reserve format info areas
    for ([int]$i = 0; $i -lt 9; $i++) {
        if ($i -lt $size) { $reserved[8, $i] = $true; $reserved[$i, 8] = $true }
    }
    for ([int]$i = 0; $i -lt 8; $i++) {
        $reserved[8, ($size - 8 + $i)] = $true
        $reserved[($size - 8 + $i), 8] = $true
    }

    # Version info (versions 7+)
    if ($version -ge 7) {
        # Compute version info: 6-bit version + 12-bit BCH(18,6)
        [int]$vBits = $version -shl 12
        [int]$rem = $vBits
        for ([int]$i = 17; $i -ge 12; $i--) {
            if (($rem -shr $i) -band 1) { $rem = $rem -bxor (0x1F25 -shl ($i - 12)) }
        }
        [int]$vInfo18 = $vBits -bor $rem

        # Place in two 6x3 blocks (not masked)
        for ([int]$i = 0; $i -lt 18; $i++) {
            [bool]$bit = [bool](($vInfo18 -shr $i) -band 1)
            [int]$row = [int]([Math]::Floor($i / 3))
            [int]$col = $i % 3

            # Bottom-left block: rows (size-11)+(0..2), cols 0..5
            $matrix[($size - 11 + $col), $row] = $bit
            $reserved[($size - 11 + $col), $row] = $true
            # Top-right block: rows 0..5, cols (size-11)+(0..2)
            $matrix[$row, ($size - 11 + $col)] = $bit
            $reserved[$row, ($size - 11 + $col)] = $true
        }
    }

    # Encode data
    _QR-EncodeData $text $version $Level
    [byte[]]$dataCW = $script:_qrTmpData

    _QR-Interleave $dataCW $version $Level
    [byte[]]$allCW = $script:_qrTmpInterleaved

    # Convert to bit stream
    $dataBits = [System.Collections.Generic.List[int]]::new(($allCW.Count * 8 + 16))
    for ([int]$cwi = 0; $cwi -lt $allCW.Count; $cwi++) {
        [int]$cwv = [int]$allCW[$cwi]
        for ([int]$i = 7; $i -ge 0; $i--) {
            $null = $dataBits.Add(($cwv -shr $i) -band 1)
        }
    }

    # Place data bits in zigzag pattern
    [int]$bitIdx = 0
    [int]$bitCount = $dataBits.Count
    [int]$col = $size - 1
    [bool]$upward = $true

    while ($col -ge 0) {
        if ($col -eq 6) { $col = $col - 1; continue }

        if ($upward) {
            for ([int]$row = ($size - 1); $row -ge 0; $row--) {
                for ([int]$dc = 0; $dc -le 1; $dc++) {
                    [int]$cc = $col - $dc
                    if ($cc -ge 0 -and -not $reserved[$row, $cc]) {
                        if ($bitIdx -lt $bitCount) {
                            $matrix[$row, $cc] = [bool]$dataBits[$bitIdx]
                            $bitIdx = $bitIdx + 1
                        } else {
                            $matrix[$row, $cc] = $false
                        }
                    }
                }
            }
        } else {
            for ([int]$row = 0; $row -lt $size; $row++) {
                for ([int]$dc = 0; $dc -le 1; $dc++) {
                    [int]$cc = $col - $dc
                    if ($cc -ge 0 -and -not $reserved[$row, $cc]) {
                        if ($bitIdx -lt $bitCount) {
                            $matrix[$row, $cc] = [bool]$dataBits[$bitIdx]
                            $bitIdx = $bitIdx + 1
                        } else {
                            $matrix[$row, $cc] = $false
                        }
                    }
                }
            }
        }
        $upward = -not $upward
        $col = $col - 2
    }

    $script:_qrTmpMatrix = @{
        Matrix   = $matrix
        Reserved = $reserved
        Size     = [int]$size
        Version  = [int]$version
        Level    = $Level
    }
}

# ── Masking ───────────────────────────────────────────────────────────────────

function _QR-TestMask([int]$mask, [int]$row, [int]$col) {
    switch ($mask) {
        0 { return (($row + $col) % 2) -eq 0 }
        1 { return ($row % 2) -eq 0 }
        2 { return ($col % 3) -eq 0 }
        3 { return (($row + $col) % 3) -eq 0 }
        4 { return (([Math]::Floor($row / 2) + [Math]::Floor($col / 3)) % 2) -eq 0 }
        5 { return ((($row * $col) % 2) + (($row * $col) % 3)) -eq 0 }
        6 { return (((($row * $col) % 2) + (($row * $col) % 3)) % 2) -eq 0 }
        7 { return (((($row + $col) % 2) + (($row * $col) % 3)) % 2) -eq 0 }
    }
    return $false
}

function _QR-ApplyMask([object[,]]$mat, [bool[,]]$res, [int]$size, [int]$mask) {
    $masked = [bool[,]]::new($size, $size)
    for ([int]$r = 0; $r -lt $size; $r++) {
        for ([int]$c = 0; $c -lt $size; $c++) {
            [bool]$val = [bool]$mat[$r, $c]
            if (-not $res[$r, $c]) {
                [bool]$flip = _QR-TestMask $mask $r $c
                if ($flip) { $val = -not $val }
            }
            $masked[$r, $c] = $val
        }
    }
    $script:_qrTmpMasked = $masked
}

function _QR-WriteFormatInfo([bool[,]]$mat, [int]$size, [int]$mask, [string]$Level) {
    [int]$fmtBits = $script:formatInfoBits[$Level][$mask]

    # Positions around top-left finder (parallel row/col arrays)
    [int[]]$p1r = @(0, 1, 2, 3, 4, 5, 7, 8, 8, 8, 8, 8, 8, 8, 8)
    [int[]]$p1c = @(8, 8, 8, 8, 8, 8, 8, 8, 7, 5, 4, 3, 2, 1, 0)

    # Positions along right and bottom edges
    [int]$s1 = $size - 1; [int]$s2 = $size - 2; [int]$s3 = $size - 3
    [int]$s4 = $size - 4; [int]$s5 = $size - 5; [int]$s6 = $size - 6
    [int]$s7 = $size - 7; [int]$s8 = $size - 8

    [int[]]$p2r = @(8, 8, 8, 8, 8, 8, 8, 8, $s7, $s6, $s5, $s4, $s3, $s2, $s1)
    [int[]]$p2c = @($s1, $s2, $s3, $s4, $s5, $s6, $s7, $s8, 8, 8, 8, 8, 8, 8, 8)

    for ([int]$i = 0; $i -lt 15; $i++) {
        [bool]$bit = [bool](($fmtBits -shr $i) -band 1)
        $mat[$p1r[$i], $p1c[$i]] = $bit
        $mat[$p2r[$i], $p2c[$i]] = $bit
    }
}

function _QR-CalcPenalty([bool[,]]$mat, [int]$size) {
    [int]$penalty = 0

    # Rule 1: runs of 5+ same-color in row/column
    for ([int]$r = 0; $r -lt $size; $r++) {
        [int]$run = 1
        for ([int]$c = 1; $c -lt $size; $c++) {
            if ($mat[$r, $c] -eq $mat[$r, ($c - 1)]) { $run = $run + 1 }
            else { if ($run -ge 5) { $penalty = $penalty + $run - 2 }; $run = 1 }
        }
        if ($run -ge 5) { $penalty = $penalty + $run - 2 }
    }
    for ([int]$c = 0; $c -lt $size; $c++) {
        [int]$run = 1
        for ([int]$r = 1; $r -lt $size; $r++) {
            if ($mat[$r, $c] -eq $mat[($r - 1), $c]) { $run = $run + 1 }
            else { if ($run -ge 5) { $penalty = $penalty + $run - 2 }; $run = 1 }
        }
        if ($run -ge 5) { $penalty = $penalty + $run - 2 }
    }

    # Rule 2: 2x2 blocks
    for ([int]$r = 0; $r -lt ($size - 1); $r++) {
        for ([int]$c = 0; $c -lt ($size - 1); $c++) {
            [bool]$v = $mat[$r, $c]
            if ($mat[$r, ($c+1)] -eq $v -and $mat[($r+1), $c] -eq $v -and $mat[($r+1), ($c+1)] -eq $v) {
                $penalty = $penalty + 3
            }
        }
    }

    # Rule 3: finder-like patterns
    [bool[]]$pat1 = @($true,$false,$true,$true,$true,$false,$true,$false,$false,$false,$false)
    [bool[]]$pat2 = @($false,$false,$false,$false,$true,$false,$true,$true,$true,$false,$true)
    [int]$limit = $size - 11
    for ([int]$r = 0; $r -lt $size; $r++) {
        for ([int]$c = 0; $c -le $limit; $c++) {
            [bool]$m1 = $true; [bool]$m2 = $true
            for ([int]$k = 0; $k -lt 11; $k++) {
                if ($mat[$r, ($c+$k)] -ne $pat1[$k]) { $m1 = $false }
                if ($mat[$r, ($c+$k)] -ne $pat2[$k]) { $m2 = $false }
            }
            if ($m1) { $penalty = $penalty + 40 }
            if ($m2) { $penalty = $penalty + 40 }
        }
    }
    for ([int]$c = 0; $c -lt $size; $c++) {
        for ([int]$r = 0; $r -le $limit; $r++) {
            [bool]$m1 = $true; [bool]$m2 = $true
            for ([int]$k = 0; $k -lt 11; $k++) {
                if ($mat[($r+$k), $c] -ne $pat1[$k]) { $m1 = $false }
                if ($mat[($r+$k), $c] -ne $pat2[$k]) { $m2 = $false }
            }
            if ($m1) { $penalty = $penalty + 40 }
            if ($m2) { $penalty = $penalty + 40 }
        }
    }

    # Rule 4: dark proportion
    [int]$darkCount = 0
    for ([int]$r = 0; $r -lt $size; $r++) {
        for ([int]$c = 0; $c -lt $size; $c++) {
            if ($mat[$r, $c]) { $darkCount = $darkCount + 1 }
        }
    }
    [double]$pct = ($darkCount * 100.0) / ($size * $size)
    [int]$prev5 = [int]([Math]::Floor($pct / 5.0)) * 5
    [int]$next5 = $prev5 + 5
    $penalty = $penalty + [int]([Math]::Min([Math]::Abs($prev5 - 50) / 5, [Math]::Abs($next5 - 50) / 5)) * 10

    return $penalty
}

# ── Main entry points ─────────────────────────────────────────────────────────

# Build the final masked QR matrix (best of all 8 masks). Result is stored in
# $script:_qrTmpFinal as @{ Matrix = <bool[,]>; Size = <int> } to avoid PS 5.1
# pipeline unrolling of the 2D array.
function Get-QRCodeMatrix {
    param(
        [string]$Text,
        [ValidateSet('L','M','Q','H')][string]$Level = 'M'
    )

    _QR-BuildMatrix $Text $Level
    $qr = $script:_qrTmpMatrix
    $matrix   = $qr.Matrix
    $reserved = $qr.Reserved
    [int]$size = [int]$qr.Size
    [string]$lvl = $qr.Level

    # Try all 8 masks and pick the best
    [int]$bestPenalty = [int]::MaxValue
    $bestMatrix = $null

    for ([int]$m = 0; $m -lt 8; $m++) {
        _QR-ApplyMask $matrix $reserved $size $m
        [bool[,]]$masked = $script:_qrTmpMasked
        _QR-WriteFormatInfo $masked $size $m $lvl
        [int]$p = _QR-CalcPenalty $masked $size
        if ($p -lt $bestPenalty) {
            $bestPenalty = $p
            $bestMatrix = $masked
        }
    }

    $script:_qrTmpFinal = @{ Matrix = $bestMatrix; Size = $size }
}

function New-QRCodeImage {
    param(
        [string]$Text,
        [int]$ModuleSize = 8,
        [System.Windows.Media.Color]$Dark = [System.Windows.Media.Colors]::Black,
        [System.Windows.Media.Color]$Light = [System.Windows.Media.Colors]::White,
        [ValidateSet('L','M','Q','H')][string]$Level = 'M',
        [int]$QuietZone = 4
    )

    Get-QRCodeMatrix -Text $Text -Level $Level
    $final = $script:_qrTmpFinal
    [bool[,]]$bestMatrix = $final.Matrix
    [int]$size = [int]$final.Size

    # Render to WriteableBitmap
    [int]$quiet = $QuietZone
    [int]$totalMods = $size + ($quiet * 2)
    [int]$imgSize = $totalMods * $ModuleSize

    $wb = [System.Windows.Media.Imaging.WriteableBitmap]::new(
        $imgSize, $imgSize, 96, 96,
        [System.Windows.Media.PixelFormats]::Bgra32, $null
    )

    [int]$stride = $imgSize * 4
    [byte[]]$pixels = [byte[]]::new($stride * $imgSize)

    # Fill with light color
    [byte]$lb = $Light.B; [byte]$lg = $Light.G; [byte]$lr = $Light.R; [byte]$la = $Light.A
    [byte]$db = $Dark.B;  [byte]$dg = $Dark.G;  [byte]$dr = $Dark.R;  [byte]$da = $Dark.A

    for ([int]$i = 0; $i -lt $pixels.Count; $i += 4) {
        $pixels[$i]     = $lb
        $pixels[$i + 1] = $lg
        $pixels[$i + 2] = $lr
        $pixels[$i + 3] = $la
    }

    # Draw dark modules
    for ([int]$r = 0; $r -lt $size; $r++) {
        for ([int]$c = 0; $c -lt $size; $c++) {
            if ($bestMatrix[$r, $c]) {
                [int]$px = ($c + $quiet) * $ModuleSize
                [int]$py = ($r + $quiet) * $ModuleSize
                for ([int]$dy = 0; $dy -lt $ModuleSize; $dy++) {
                    [int]$rowOff = ($py + $dy) * $imgSize
                    for ([int]$dx = 0; $dx -lt $ModuleSize; $dx++) {
                        [int]$off = ($rowOff + $px + $dx) * 4
                        $pixels[$off]     = $db
                        $pixels[$off + 1] = $dg
                        $pixels[$off + 2] = $dr
                        $pixels[$off + 3] = $da
                    }
                }
            }
        }
    }

    $wb.WritePixels(
        [System.Windows.Int32Rect]::new(0, 0, $imgSize, $imgSize),
        $pixels, $stride, 0
    )

    return $wb
}

# Render the QR code as a scalable SVG document string.
function New-QRCodeSvg {
    param(
        [string]$Text,
        [ValidateSet('L','M','Q','H')][string]$Level = 'M',
        [System.Windows.Media.Color]$Dark = [System.Windows.Media.Colors]::Black,
        [System.Windows.Media.Color]$Light = [System.Windows.Media.Colors]::White,
        [int]$ModuleSize = 10,
        [int]$QuietZone = 4
    )

    Get-QRCodeMatrix -Text $Text -Level $Level
    $final = $script:_qrTmpFinal
    [bool[,]]$m = $final.Matrix
    [int]$size = [int]$final.Size

    [int]$dim = ($size + ($QuietZone * 2)) * $ModuleSize
    [string]$darkHex  = "#{0:X2}{1:X2}{2:X2}" -f $Dark.R,  $Dark.G,  $Dark.B
    [string]$lightHex = "#{0:X2}{1:X2}{2:X2}" -f $Light.R, $Light.G, $Light.B

    $sb = [System.Text.StringBuilder]::new()
    $null = $sb.AppendLine('<?xml version="1.0" encoding="UTF-8"?>')
    $null = $sb.AppendLine("<svg xmlns=`"http://www.w3.org/2000/svg`" width=`"$dim`" height=`"$dim`" viewBox=`"0 0 $dim $dim`" shape-rendering=`"crispEdges`">")
    $null = $sb.AppendLine("<rect width=`"$dim`" height=`"$dim`" fill=`"$lightHex`"/>")
    $null = $sb.Append("<path fill=`"$darkHex`" d=`"")

    for ([int]$r = 0; $r -lt $size; $r++) {
        for ([int]$c = 0; $c -lt $size; $c++) {
            if ($m[$r, $c]) {
                [int]$x = ($c + $QuietZone) * $ModuleSize
                [int]$y = ($r + $QuietZone) * $ModuleSize
                $null = $sb.Append("M$x $y h$ModuleSize v$ModuleSize h-$ModuleSize z ")
            }
        }
    }

    $null = $sb.AppendLine('"/>')
    $null = $sb.AppendLine('</svg>')
    return $sb.ToString()
}
