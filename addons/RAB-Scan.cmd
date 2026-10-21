@echo off
title RAB Scan (read only)
echo ================================================================
echo   RAB Scan - READ ONLY. Lists every Minecraft data folder on
echo   this PC, the packs in each, and the newest world name.
echo   Nothing is changed or deleted.
echo ================================================================
echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command "$uuid='f293a3f3-67f8-44ba-ac2f-faa727532237'; $cands=@(); $bases=@(\"$env:LocalAppData\Packages\",\"$env:AppData\",\"$env:UserProfile\",\"C:\XboxGames\"); foreach($b in $bases){ if(-not (Test-Path $b)){ continue }; Get-ChildItem $b -Directory -Recurse -Depth 7 -Filter 'com.mojang' -ErrorAction SilentlyContinue | ForEach-Object { $cands += $_.FullName } }; $cands = @($cands | Select-Object -Unique); if(-not $cands.Count){ Write-Host '  No com.mojang folders found.'; exit 1 }; Write-Host ('  Found ' + $cands.Count + ' Minecraft data folder(s):'); Write-Host ''; foreach($c in $cands){ Write-Host ('  ' + $c); $script:lines=@(); foreach($k in @('behavior_packs','development_behavior_packs')){ $d=Join-Path $c $k; if(-not (Test-Path $d)){ continue }; Get-ChildItem $d -Directory -ErrorAction SilentlyContinue | ForEach-Object { $mf=Join-Path $_.FullName 'manifest.json'; if(Test-Path $mf){ try { $j=Get-Content $mf -Raw | ConvertFrom-Json; $mark=''; if($j.header.uuid -eq $uuid){ $mark='   [#RAB]' }; $script:lines += ('      ' + $k + ' : ' + $j.header.name + '  v' + ($j.header.version -join '.') + $mark) } catch {} } } }; if($script:lines.Count){ $script:lines | ForEach-Object { Write-Host $_ } } else { Write-Host '      (no packs)' }; $w=Join-Path $c 'minecraftWorlds'; if(Test-Path $w){ $ws=@(Get-ChildItem $w -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending); if($ws.Count){ $nm=(Get-Content (Join-Path $ws[0].FullName 'levelname.txt') -Raw -ErrorAction SilentlyContinue); if($nm){ $nm=$nm.Trim() } else { $nm='(unnamed)' }; Write-Host ('      worlds: ' + $ws.Count + '   newest: ' + $nm + '   ' + $ws[0].LastWriteTime) } else { Write-Host '      worlds: 0' } } else { Write-Host '      worlds: none' }; Write-Host '' }"
echo.
pause
