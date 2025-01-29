param (
    [Parameter()][string]$TerraformVersion,
    [Parameter(ValueFromRemainingArguments=$true)][string[]]$Modules
)

$check = @()
$check += @'
workflow:
    rules:
        - if: $CI_PIPELINE_SOURCE == "parent_pipeline"
'@

$check += @"
stages: [$($Modules -join ',')]
"@

foreach ($module in $Modules) {
$check += @"

$module-lint:
    stage: $module
    needs: []
    image:
        name: ghcr.io/terraform-linters/tflint:v0.55.0
        entrypoint:
        - "/usr/bin/env"
        - "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    script:
        - tflint --init
        - tflint --chdir="./$module" --color --minimum-failure-severity=notice

$module-validate:
    stage: $module
    needs: []
    image: 
        name: hashicorp/terraform:$TerraformVersion
        entrypoint: [""]
    script:
        - terraform -chdir="./$module" init --backend=false
        - terraform -chdir="./$module" fmt -write=false -diff -check
        - terraform -chdir="./$module" validate

$module-checkov:
    stage: $module
    needs: []
    image:
        name: bridgecrew/checkov:3.2.357
        entrypoint:
            - "/usr/bin/env"
            - "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    script:
    - checkov -d ./$module


$module-tfsec:
    stage: $module
    needs: []
    image: aquasec/tfsec-ci:v1.28
    script:
        - tfsec ./$module

"@
}

$check | Out-File check.yml -Encoding utf8
