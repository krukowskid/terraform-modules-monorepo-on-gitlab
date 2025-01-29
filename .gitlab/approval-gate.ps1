param (
    [Parameter(Mandatory=$True)]
    [String]$AccessToken,
    [Parameter(Mandatory=$True)]
    [Int]$MinimumNumberOfApprovals
)

$headers = @{
    "PRIVATE-TOKEN" = "$AccessToken"
    "Content-Type" = "application/json"
}

$author = (Invoke-RestMethod -Uri "$env:CI_API_V4_URL/projects/$env:CI_PROJECT_ID/merge_requests/$env:CI_MERGE_REQUEST_IID" `
                                    -Method Get `
                                    -Headers $headers).author

$approvals = (Invoke-RestMethod -Uri "$env:CI_API_V4_URL/projects/$env:CI_PROJECT_ID/merge_requests/$env:CI_MERGE_REQUEST_IID/approvals" `
                                    -Method Get `
                                    -Headers $headers).approved_by

$approvalsCount = ($approvals 
                    | Where-Object {
                        $($_.user).id -ne $author.id
                    }).count

if ($approvalsCount -lt $MinimumNumberOfApprovals){
    throw "This pipeline requires at least $MinimumNumberOfApprovals approval(s). Ensure that merge request is approved and re-run pipeline from merge request UI."
}
