#!/bin/bash
# Monitor all OpenAlex Glue job statuses
# Run this to check progress: bash monitor_jobs.sh

ENTITIES="works authors institutions sources publishers topics funders domains fields subfields"

echo "============================================"
echo "OpenAlex Glue Job Status"
echo "$(date)"
echo "============================================"
printf "%-20s %-15s %-10s\n" "ENTITY" "STATUS" "RUNTIME"
echo "--------------------------------------------"

ALL_DONE=true

for ENTITY in ${ENTITIES}; do
    JOB_NAME="openalex-convert-${ENTITY}"

    RESULT=$(aws glue get-job-runs --job-name "${JOB_NAME}" --max-results 1 \
        --query 'JobRuns[0].[JobRunState,ExecutionTime]' --output text 2>/dev/null)

    if [ -z "$RESULT" ] || [ "$RESULT" = "None" ]; then
        STATUS="NOT STARTED"
        RUNTIME="-"
    else
        STATUS=$(echo "$RESULT" | awk '{print $1}')
        SECONDS=$(echo "$RESULT" | awk '{print $2}')
        if [ "$SECONDS" != "None" ] && [ -n "$SECONDS" ]; then
            MINUTES=$((SECONDS / 60))
            RUNTIME="${MINUTES}m"
        else
            RUNTIME="-"
        fi
    fi

    if [ "$STATUS" != "SUCCEEDED" ] && [ "$STATUS" != "FAILED" ]; then
        ALL_DONE=false
    fi

    printf "%-20s %-15s %-10s\n" "${ENTITY}" "${STATUS}" "${RUNTIME}"
done

echo "============================================"

if [ "$ALL_DONE" = true ]; then
    echo "All jobs complete! Next step: run athena_setup.sql in the Athena console."
else
    echo "Jobs still running. Re-run this script to check again."
    echo "Or run in a loop: watch -n 30 bash monitor_jobs.sh"
fi
