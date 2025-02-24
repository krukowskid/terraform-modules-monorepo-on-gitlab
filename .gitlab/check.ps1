param (
    [Parameter()][string]$TerraformVersion,
    [Parameter(ValueFromRemainingArguments=$true)][string[]]$Modules
)

$check = @()
$check += @'
workflow:
    rules:
        - if: $CI_PIPELINE_SOURCE == "parent_pipeline"

before_script:
    - git config --global url."https://gitlab-ci-token:${CI_JOB_TOKEN}@${CI_SERVER_HOST}".insteadOf "https://${CI_SERVER_HOST}"

'@

$check += @"
stages: [$($Modules -join ',')]
"@

foreach ($module in $Modules) {
$check += @"

$module-lint:
    stage: $module
    needs: []
    rules:
      - if: `$GITHUB_TOKEN
        variables:
            GITHUB_TOKEN: `${GITHUB_TOKEN}
      - if : `$GITHUB_TOKEN == null
    image:
        name: ghcr.io/terraform-linters/tflint:v0.55.0
        entrypoint:
        - "/usr/bin/env"
        - "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    before_script:
        - apk add git
        - !reference [before_script]
    script:
        - tflint --init
        - tflint --chdir="./$module" --color --minimum-failure-severity=notice

$module-validate:
    stage: $module
    needs: []
    image: 
        name: hashicorp/terraform:$TerraformVersion
        entrypoint: [""]
    before_script:
        - !reference [before_script]
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
    before_script:
        - !reference [before_script]
    script:
    - checkov -d ./$module  -o cli -o junitxml --output-file-path console,$module.xml
    artifacts:
        when: always
        paths:
            - $module.xml
        reports:
            junit: $module.xml


$module-tfsec:
    stage: $module
    needs: []
    image: aquasec/tfsec-ci:v1.28
    before_script:
        - !reference [before_script]
    script:
        - tfsec ./$module
        
"@
}

$check | Out-File check.yml -Encoding utf8
