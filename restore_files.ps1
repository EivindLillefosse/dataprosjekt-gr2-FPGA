$files = Get-Content .\fully_diff.txt
if ($files.Length -eq 0) { Write-Output 'No files to restore'; exit 0 }
for ($i=0; $i -lt $files.Length; $i++) {
    $f = $files[$i]
    Write-Output ("Checking out: {0}" -f $f)
    git checkout fullyconnected -- "$f"
    if ($LASTEXITCODE -ne 0) { Write-Output ("Failed to checkout {0}" -f $f); exit 1 }
}

git add -A
$st = git status --porcelain
if ([string]::IsNullOrEmpty($st)) { Write-Output 'No changes to commit'; exit 0 }

git commit -m 'Restore files from fullyconnected (diff)'
if ($LASTEXITCODE -ne 0) { Write-Output 'Commit failed'; exit 1 }

git push -u origin HEAD
