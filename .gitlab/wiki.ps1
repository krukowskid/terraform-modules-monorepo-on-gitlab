param (
    [string]$Releases,
    [string]$MergeRequestId,
    [string]$MergeRequestTitle,
    [string]$ChangelogEntry,
    [string]$Label
)

$wikiRepository = "$($env:CI_PROJECT_NAME).wiki"

if ($Label -eq "no-release") {
    exit 0
}
elseif([string]::IsNullOrEmpty($Releases)) {
    throw "No releases specified"
}

($releases | ConvertFrom-Json).releases | Foreach-Object {
    $module = $_.module
    $version = $_.new

$intro = @"
[[_TOC_]]

# Module Location
To use this module in your Terraform, use the below source value.
``````hcl
module "$(($module -split '/')[1])" {
    source = "git::$($env:CI_SERVER_PROTOCOL)://$($env:CI_SERVER_HOST)/$($env:CI_PROJECT_PATH).git?ref=$($module)/$version"
    # also any inputs for the module (see below)
}
``````

# Module Attributes
"@ 

    if(!(Test-Path $wikiRepository/$module)){
        New-Item -Path $wikiRepository/$module `
                 -ItemType Directory `
                 -Force
    }

    $intro | Out-File "$($module).md"

    $currentDir = $(Get-Location).Path

    ./terraform-docs markdown table `
        --output-file "$currentDir/$($module).md" `
        --sort-by required "$module"

    $docs = Get-Content -raw "$($module).md" | Out-String 
    $content = Get-Content -raw "$wikiRepository/$($module).md" -ErrorAction "SilentlyContinue" | Out-String 

    $date = Get-Date -Format dd-MM-yyyy
    
    $changelog = @"

# Changelog
<!-- CHANGELOG -->
## $version ($date)
* PR [#$($mergeRequestId)]($("$env:CI_PROJECT_URL/-/merge_requests/$mergeRequestId")) - $($mergeRequestTitle)
``````
$($changelogEntry)
``````
"@

    if ($content -like "*<!-- CHANGELOG -->*") {
        $existingChangelog = ($content -split ("<!-- CHANGELOG -->"))[1]

        if ($existingChangelog -like "*## $version*") {
            throw "Changelog for version $version already exists."
        }

    $changelog = @"
$changelog
$existingChangelog
"@
    }
    
    $docs -replace "(?s)(?<=!-- END_TF_DOCS -->).+?","$changelog" `
        | Out-File -FilePath "$wikiRepository/$($module).md" -Encoding utf8
}

if(!(Test-Path $wikiRepository/home.md)){
    'Welcome to the Terraform Modules wiki!' | Out-File -FilePath "$wikiRepository/home.md" -Encoding utf8
}

cd $wikiRepository
git add . 
git commit -m"$($mergeRequestTitle)"
git push
