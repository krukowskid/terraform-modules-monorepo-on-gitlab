param (
    [string]$Releases,
    [string]$MergeRequestId,
    [string]$MergeRequestTitle,
    [string]$ChangelogEntry,
    [string]$Label
)

if ($Label -eq "no-release") {
    exit 0
}
elseif([string]::IsNullOrEmpty($Releases)) {
    throw "No releases specified"
}

$payload = $releases | ConvertFrom-Json

$date = Get-Date -Format dd-MM-yyyy

$message = "($date) MR #$($mergeRequestId) - $($mergeRequestTitle)"
$description = "- $($changelogEntry)"

$payload.releases | ForEach-Object {
    $branchName = "tmp_$($_.module)_$($_.new)"
    $tag = "$($_.module)/$($_.new)"
    $module = $($_.module)
    $previousTag = "$($_.module)/v$($_.previous)"
    $major = $($_.new).Substring(1).Split('.')[0]
    $minor = $($_.new).Substring(1).Split('.')[1]
    $majorTag = "$($module)/v$($major)"
    $minorTag = "$($module)/v$($major).$($minor)"

    git checkout "$($payload.sha)"
    
    Write-Output "module: $module"

    Copy-Item -Path $module `
            -Destination "./_workingtmp/" `
            -Recurse `
            -Force

    if (git tag -l "$previousTag")
    {
        git checkout "$previousTag"
    }

    git checkout -b "$branchName"

    Get-ChildItem -Exclude "_workingtmp" `
        | Remove-Item -Recurse `
                        -Force

    Copy-Item -Path "_workingtmp/*" `
            -Destination ./ `
            -Recurse `
            -Force

    Remove-Item -LiteralPath "_workingtmp" `
                -Force `
                -Recurse

    git rm -r ".gitlab"
    git rm ".gitignore"
    git rm ".gitlab-ci.yml"
    git rm ".tflint.hcl"

    git add .
    git commit -a -m "$message" -m "$description"
    git tag "$tag" -m "$message" -m "$description"
    git tag -fa "$majorTag" -m "$message" -m "$description"
    git tag -fa "$minorTag" -m "$message" -m "$description"
    git push origin "$tag"
    git push origin "$minorTag" -f
    git push origin "$majorTag" -f
    git checkout $env:CI_COMMIT_SHA
}
