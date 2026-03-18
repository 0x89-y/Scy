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

# ── Version/EC tables (EC level M, byte mode) ────────────────────────────────
$script:qrVersions = @{}
$script:qrVersions[1]  = @{ Size=21;  Total=26;   ECPer=10; Blocks=1; Capacity=14  }
$script:qrVersions[2]  = @{ Size=25;  Total=44;   ECPer=16; Blocks=1; Capacity=26  }
$script:qrVersions[3]  = @{ Size=29;  Total=70;   ECPer=26; Blocks=1; Capacity=42  }
$script:qrVersions[4]  = @{ Size=33;  Total=100;  ECPer=18; Blocks=2; Capacity=62  }
$script:qrVersions[5]  = @{ Size=37;  Total=134;  ECPer=24; Blocks=2; Capacity=84  }
$script:qrVersions[6]  = @{ Size=41;  Total=172;  ECPer=16; Blocks=4; Capacity=106 }
$script:qrVersions[7]  = @{ Size=45;  Total=196;  ECPer=18; Blocks=4; Capacity=122 }
$script:qrVersions[8]  = @{ Size=49;  Total=242;  ECPer=24; Blocks=4; Capacity=152 }
$script:qrVersions[9]  = @{ Size=53;  Total=292;  ECPer=22; Blocks=4; Capacity=180 }
$script:qrVersions[10] = @{ Size=57;  Total=346;  ECPer=28; Blocks=4; Capacity=213 }

# Block structure per version: list of (numBlocks, dataCodewordsPerBlock) pairs
$script:qrBlockStructure = @{}
$script:qrBlockStructure[1]  = [System.Collections.Generic.List[int[]]]::new(); $script:qrBlockStructure[1].Add([int[]]@(1, 16))
$script:qrBlockStructure[2]  = [System.Collections.Generic.List[int[]]]::new(); $script:qrBlockStructure[2].Add([int[]]@(1, 28))
$script:qrBlockStructure[3]  = [System.Collections.Generic.List[int[]]]::new(); $script:qrBlockStructure[3].Add([int[]]@(1, 44))
$script:qrBlockStructure[4]  = [System.Collections.Generic.List[int[]]]::new(); $script:qrBlockStructure[4].Add([int[]]@(2, 32))
$script:qrBlockStructure[5]  = [System.Collections.Generic.List[int[]]]::new(); $script:qrBlockStructure[5].Add([int[]]@(2, 43))
$script:qrBlockStructure[6]  = [System.Collections.Generic.List[int[]]]::new(); $script:qrBlockStructure[6].Add([int[]]@(4, 27))
$script:qrBlockStructure[7]  = [System.Collections.Generic.List[int[]]]::new(); $script:qrBlockStructure[7].Add([int[]]@(4, 31))
$script:qrBlockStructure[8]  = [System.Collections.Generic.List[int[]]]::new(); $script:qrBlockStructure[8].Add([int[]]@(2, 38)); $script:qrBlockStructure[8].Add([int[]]@(2, 39))
$script:qrBlockStructure[9]  = [System.Collections.Generic.List[int[]]]::new(); $script:qrBlockStructure[9].Add([int[]]@(3, 36)); $script:qrBlockStructure[9].Add([int[]]@(1, 37))
$script:qrBlockStructure[10] = [System.Collections.Generic.List[int[]]]::new(); $script:qrBlockStructure[10].Add([int[]]@(4, 43)); $script:qrBlockStructure[10].Add([int[]]@(1, 44))

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

# Pre-computed format info bits for EC level M, mask 0-7
$script:formatInfoBits = [int[]]@(0x5412, 0x5125, 0x5E7C, 0x5B4B, 0x45F9, 0x40CE, 0x4F97, 0x4AA0)

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

function _QR-EncodeData([string]$text, [int]$version) {
    $vInfo = $script:qrVersions[$version]
    [int]$totalDataCW = [int]$vInfo.Total - ([int]$vInfo.ECPer * [int]$vInfo.Blocks)
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

function _QR-Interleave([byte[]]$dataCodewords, [int]$version) {
    $vInfo = $script:qrVersions[$version]
    $blockGroups = $script:qrBlockStructure[$version]
    [int]$ecPerBlock = [int]$vInfo.ECPer

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

function _QR-BuildMatrix([string]$text) {
    [byte[]]$textBytes = [System.Text.Encoding]::UTF8.GetBytes($text)
    [int]$byteCount = $textBytes.Count

    [int]$version = 0
    for ([int]$v = 1; $v -le 10; $v++) {
        if ($byteCount -le [int]$script:qrVersions[$v].Capacity) {
            $version = $v; break
        }
    }
    if ($version -eq 0) { throw "Text too long for QR code (max ~213 bytes)" }

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

    # Encode data
    _QR-EncodeData $text $version
    [byte[]]$dataCW = $script:_qrTmpData

    _QR-Interleave $dataCW $version
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

function _QR-WriteFormatInfo([bool[,]]$mat, [int]$size, [int]$mask) {
    [int]$fmtBits = $script:formatInfoBits[$mask]

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
        [bool]$bit = [bool](($fmtBits -shr (14 - $i)) -band 1)
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

# ── Main entry point ──────────────────────────────────────────────────────────

function New-QRCodeImage {
    param(
        [string]$Text,
        [int]$ModuleSize = 8,
        [System.Windows.Media.Color]$Dark = [System.Windows.Media.Colors]::Black,
        [System.Windows.Media.Color]$Light = [System.Windows.Media.Colors]::White
    )

    _QR-BuildMatrix $Text
    $qr = $script:_qrTmpMatrix
    $matrix   = $qr.Matrix
    $reserved = $qr.Reserved
    [int]$size = [int]$qr.Size

    # Try all 8 masks and pick the best
    [int]$bestPenalty = [int]::MaxValue
    [int]$bestMask = 0
    $bestMatrix = $null

    for ([int]$m = 0; $m -lt 8; $m++) {
        _QR-ApplyMask $matrix $reserved $size $m
        [bool[,]]$masked = $script:_qrTmpMasked
        _QR-WriteFormatInfo $masked $size $m
        [int]$p = _QR-CalcPenalty $masked $size
        if ($p -lt $bestPenalty) {
            $bestPenalty = $p
            $bestMask = $m
            $bestMatrix = $masked
        }
    }

    # Render to WriteableBitmap
    [int]$quiet = 4
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
