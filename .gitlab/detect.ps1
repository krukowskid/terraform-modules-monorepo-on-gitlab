param (
    [Parameter(Mandatory=$True)]
    [String]$AccessToken
)

$headers = @{
    "PRIVATE-TOKEN" = "$AccessToken"
    "Content-Type" = "application/json"
}

# Get PR details
if ($env:CI_MERGE_REQUEST_IID) {
    $mergeRequestId = $env:CI_MERGE_REQUEST_IID
} 
else {
    $mergeRequestId = ((Invoke-RestMethod -Uri "$env:CI_API_V4_URL/projects/$env:CI_PROJECT_ID/merge_requests" `
                                        -Method Get `
                                        -Headers $headers
                    ) | Where-Object {$_.squash_commit_sha -eq $env:CI_COMMIT_SHA}).iid  
}

$mrDetails = Invoke-RestMethod  -Uri "$env:CI_API_V4_URL/projects/$env:CI_PROJECT_ID/merge_requests/$mergeRequestId" `
                                -Method Get `
                                -Headers $headers

$mrUrl = "$env:CI_PROJECT_URL/-/merge_requests/$mergeRequestId"
$mrDescription = $mrDetails.description

# Fetch PR labels
@("major", "minor", "patch", "no-release") | ForEach-Object {
    try {
        $hexColor = "#{0:X6}" -f ($([math]::Abs($_.GetHashCode())) % 16777215)
        Invoke-RestMethod -Uri "$env:CI_API_V4_URL/projects/$env:CI_PROJECT_ID/labels" `
                            -Method POST `
                            -Headers $headers `
                            -Body $(@{"name" = "$($_)";"color" = "$hexColor"} | ConvertTo-Json) `
                            -ContentType "application/json" 
    }
    catch {}
}

$labels = $mrDetails.labels `
    | Where-Object { 
        @("major", "minor", "patch", "no-release") -contains $_ 
    }

if ($labels.Count -eq 1) {
    Write-Output "Release type: $labels"
    $label = $labels
} elseif ($labels.Count -eq 0) {
    throw "No release type labels found. (patch/minor/major/no-release)."
} else {
    throw "Too many release labels set on merge request: $labels"
}

# Detect changed modules
if ($label -ne "no-release") {
$changedModules = (git diff --name-only $($mrDetails.diff_refs).base_sha HEAD `
                        | Where-Object { 
                            $_ -notlike '.gitlab*' `
                            -and $_ -like '*/*/*' 
                        }
                    ) | ForEach-Object {
                            ($_ -split '/')[0..1] -join '/' 
                        } | Select-Object -Unique

$existingModules = Get-ChildItem -Directory -Recurse -Depth 1 `
    | Select-Object Name, Parent `
    | Where-Object { 
        ((Get-ChildItem -Directory).Name -contains $_.Parent) `
        -and ($_.Name -ne '.gitlab') `
        -and ($_.Parent -ne '.gitlab')    
    }

if ((git tag -l "$_/v*" -n1 | Where-Object {$_ -like "*MR #$($mergeRequestId) -*"}).count -ne 0) {
    throw "Changes from this PR were already published for module: $_"
}

# Version calculation
$releases = @()
    foreach ($module in $changedModules) {
        $tags = (git tag -l "$module/v*.*.*")

        if ($tags) {
            $versions = $tags.Trim("$module/v")
            $latest = [System.Version[]]$versions | Sort-Object -Descending | Select-Object -First 1
        } else {
            $latest = New-Object System.Version(0, 0, 0)
        }

        switch ($label) {
            "major" {
            $major = $latest.Major + 1
            $minor = 0
            $patch = 0
            }
            "minor" {
            $major = $latest.Major
            $minor = $latest.Minor + 1
            $patch = 0
            }
            "patch" {
            $major = $latest.Major
            $minor = $latest.Minor
            $patch = $latest.Build + 1
            }
        }

        $new = New-Object System.Version($major, $minor, $patch)
        $releases += [PSCustomObject]@{
            module = $module
            previous = $latest
            new = "v$new"
        }
    }

    # Output results
    $output = [PSCustomObject]@{
        sha = (git rev-parse HEAD)
        releases = $releases
    } | ConvertTo-Json -Compress

    $plan = $releases | ForEach-Object {
        "| $($_.module) | v$($_.previous) | **$($_.new)** |`n"
    }

    # Extract changelog entry
    $changelogEntry = (($mrDescription -split ("#+ ?") | Where-Object {
        $_ -like "Changelog*"
    }) -split ('```'))[1].Trim()

    # Validate changelog
    if (!$changelogEntry) {
        throw "Changelog section not found in MR description"
    }
    if ($changelogEntry -like "TODO:*") {
        throw "Please update change log section in MR description"
    }

    # Create release plan content
    $content = @"
# Release plan
| Directory | Previous version | New version |
|-----------|------------------|-------------|
$plan
<details><summary>Changelog preview: </summary>

* MR [#$mergeRequestId]($mrUrl) - $($mrDetails.title)

``````
$changelogEntry
``````
</details>
"@

    if ($env:CI_MERGE_REQUEST_IID) {
        $changedModules | ForEach-Object {
            try {
                $hexColor = "#{0:X6}" -f ($([math]::Abs($_.GetHashCode())) % 16777215)
                Invoke-RestMethod -Uri "$env:CI_API_V4_URL/projects/$env:CI_PROJECT_ID/labels" `
                                    -Method POST `
                                    -Headers $headers `
                                    -Body $(@{"name" = "$($_)";"color" = "$hexColor"} | ConvertTo-Json) `
                                    -ContentType "application/json" `
                                    -ErrorAction "SilentlyContinue"
                }
            catch {}
        }

            $mrLabels = @{"labels" = @($label, $changedModules) -join ','} | ConvertTo-Json
            Invoke-RestMethod -Uri "$env:CI_API_V4_URL/projects/$env:CI_PROJECT_ID/merge_requests/$mergeRequestId" `
                                -Method PUT `
                                -Headers $headers `
                                -Body $mrLabels `
                                -ContentType "application/json" `
                                -ErrorAction "SilentlyContinue"

        $body = @{
            body = $content
        } | ConvertTo-Json

        $notes = (Invoke-RestMethod -Uri "$env:CI_API_V4_URL/projects/$env:CI_PROJECT_ID/merge_requests/$mergeRequestId/notes" `
                                    -Method GET `
                                    -Headers $headers) | Where-Object {($_.body -like "*# Release plan*")}

        if ($notes.count -gt 0) {
            Invoke-RestMethod -Uri "$env:CI_API_V4_URL/projects/$env:CI_PROJECT_ID/merge_requests/$mergeRequestId/notes/$($notes[0].id)" `
                                -Method PUT `
                                -Headers $headers `
                                -Body $body `
                                -ContentType "application/json"
        }
        else {
            Invoke-RestMethod -Uri "$env:CI_API_V4_URL/projects/$env:CI_PROJECT_ID/merge_requests/$mergeRequestId/notes" `
                                -Method POST `
                                -Headers $headers `
                                -Body $body `
                                -ContentType "application/json"
        }
    }
}

Write-Output "changelogEntry=$changelogEntry" | Out-File -FilePath variables.env -Encoding utf8 -Append
Write-Output "mergeRequestTitle=$($mrDetails.title)" | Out-File -FilePath variables.env -Encoding utf8 -Append
Write-Output "mergeRequestId=$mergeRequestId" | Out-File -FilePath variables.env -Encoding utf8 -Append
Write-Output "releases=$output" | Out-File -FilePath variables.env -Encoding utf8 -Append
Write-Output "label=$label" | Out-File -FilePath variables.env -Encoding utf8 -Append
Write-Output "modules=$changedModules" | Out-File -FilePath variables.env -Encoding utf8 -Append
