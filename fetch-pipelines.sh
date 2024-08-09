#!/bin/bash
set -euo pipefail

oc whoami -c

# TODO: Make this is configurable or fetch it from KUBECONFIG?
tekton_results_url='https://tekton-results-tekton-results.apps.stone-prd-rh01.pg1f.p1.openshiftapps.com'

# TODO: I can't get this to work. Also tried just `name` to no avail. It always returns an empty response.
# PR_FILTER="$(echo -n 'data_type == "tekton.dev/v1beta1.PipelineRun" && data.metadata.namespace.matches("tenant")' | jq -Rrj '@uri')"
PR_FILTER="$(echo -n 'data_type == "tekton.dev/v1beta1.PipelineRun"' | jq -Rrj '@uri')"

# How many records to fetch at a time
PAGE_SIZE=1000

# The minimum amount of valid records to fetch
MINIMUM=2000

OUTPUT='pipelineruns.json'
RECORDS_OUTPUT='records.json'
TMP_RECORDS="$(mktemp)"
echo "DEBUG: Temp records at ${TMP_RECORDS}"

rm -f "${RECORDS_OUTPUT}" "${OUTPUT}"

next_page_token=''
count=0
# TODO: I think this is causing the script to exit with non-zero status
while [ $count -lt $MINIMUM ]; do
    echo 'Making a request'
    query="filter=${PR_FILTER}&page_size=${PAGE_SIZE}&page_token=${next_page_token}&order_by=create_time%20asc"

    curl -s -H "authorization: Bearer $(oc whoami -t)" \
        "${tekton_results_url}/apis/results.tekton.dev/v1alpha2/parents/-/results/-/records?${query}" | \
        tee "${TMP_RECORDS}" | jq '.records[]' >> "${RECORDS_OUTPUT}"

    < "${RECORDS_OUTPUT}" jq '.data.value |
        @base64d |
        fromjson |
        select(.spec.pipelineSpec != null) |
        select(.status.conditions[0].type == "Succeeded" and .status.conditions[0].status == "True") |
        select(.metadata.annotations["pipelinesascode.tekton.dev/repo-url"] != null) |
        select(.metadata.namespace | endswith("-tenant"))' | jq '.' > "${OUTPUT}"

    count="$(< "${OUTPUT}" jq -rs '. | length')"
    echo "DEBUG: Count is ${count}"

    next_page_token="$(< "${TMP_RECORDS}" jq -r '.nextPageToken')"
    echo "Next page token: ${next_page_token}"

    [[ -z $next_page_token ]] && break
done

