#!/bin/bash
# =============================================================================
# OpenAlex Pipeline Setup Script
# =============================================================================
#
# This script automates the entire setup:
# 1. Creates the IAM role for Glue
# 2. Uploads Glue scripts to S3
# 3. Creates Glue jobs for each entity
# 4. Runs all jobs
#
# BEFORE RUNNING:
# 1. Install AWS CLI: pip install awscli
# 2. Configure credentials: aws configure
# 3. Edit the two variables below ↓↓↓
# =============================================================================

# ======================== EDIT THESE TWO LINES ========================
BUCKET="codex-raw-data-us-east-1"              # Your S3 bucket name
SOURCE_PREFIX="data"     # Path within bucket where OpenAlex gz files live
# ======================================================================

OUTPUT_PREFIX="openalex-parquet"
SCRIPTS_PREFIX="glue-scripts"
ROLE_NAME="OpenAlexGlueRole"
REGION=$(aws configure get region 2>/dev/null)
if [ -z "$REGION" ]; then
    # Try EC2 instance metadata (IMDSv2)
    TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60" 2>/dev/null)
    REGION=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/region 2>/dev/null)
fi
if [ -z "$REGION" ]; then
    REGION="us-east-1"
    echo "WARNING: Could not detect AWS region. Defaulting to ${REGION}"
    echo "Set permanently with: aws configure set region ${REGION}"
fi
export AWS_DEFAULT_REGION="${REGION}"

echo "============================================"
echo "OpenAlex Pipeline Setup"
echo "============================================"
echo "Bucket:        s3://${BUCKET}"
echo "Source data:   s3://${BUCKET}/${SOURCE_PREFIX}/"
echo "Parquet output:s3://${BUCKET}/${OUTPUT_PREFIX}/"
echo "Region:        ${REGION}"
echo "============================================"
echo ""

# Verify the source data exists
echo "Checking source data..."
ENTITY_COUNT=$(aws s3 ls "s3://${BUCKET}/${SOURCE_PREFIX}/" | grep -c "PRE")
if [ "$ENTITY_COUNT" -eq 0 ]; then
    echo "ERROR: No data found at s3://${BUCKET}/${SOURCE_PREFIX}/"
    echo "Please check your BUCKET and SOURCE_PREFIX variables."
    exit 1
fi
echo "Found ${ENTITY_COUNT} entity folders. Listing:"
aws s3 ls "s3://${BUCKET}/${SOURCE_PREFIX}/"
echo ""

# ---- Step 1: Create IAM Role ----
echo "Step 1: Creating IAM role '${ROLE_NAME}'..."

cat > /tmp/glue-trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "glue.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

aws iam create-role \
    --role-name "${ROLE_NAME}" \
    --assume-role-policy-document file:///tmp/glue-trust-policy.json \
    2>/dev/null

aws iam attach-role-policy \
    --role-name "${ROLE_NAME}" \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole \
    2>/dev/null

aws iam attach-role-policy \
    --role-name "${ROLE_NAME}" \
    --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess \
    2>/dev/null

# Wait for role to propagate
echo "Waiting 10 seconds for IAM role to propagate..."
sleep 10
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"
echo "IAM role ready. ARN: ${ROLE_ARN}"
echo ""

# ---- Step 2: Upload Glue scripts ----
echo "Step 2: Uploading Glue scripts to S3..."
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)/glue_scripts"

if [ ! -d "${SCRIPT_DIR}" ]; then
    echo "ERROR: glue_scripts/ directory not found. Run this from the openalex-pipeline directory."
    exit 1
fi

aws s3 cp "${SCRIPT_DIR}/convert_works.py" "s3://${BUCKET}/${SCRIPTS_PREFIX}/convert_works.py"
aws s3 cp "${SCRIPT_DIR}/convert_small_entity.py" "s3://${BUCKET}/${SCRIPTS_PREFIX}/convert_small_entity.py"
echo "Scripts uploaded."
echo ""

# ---- Step 3: Create Glue jobs ----
echo "Step 3: Creating Glue jobs..."

ALL_ENTITIES="works authors institutions sources publishers topics funders domains fields subfields awards concepts continents countries institution-types keywords languages licenses sdgs source-types work-types"

# Delete any existing jobs first (makes re-runs safe)
echo "  Cleaning up old jobs (if any)..."
for ENTITY in ${ALL_ENTITIES}; do
    aws glue delete-job --job-name "openalex-convert-${ENTITY}" 2>/dev/null
done
echo "  Done."

# Works job (large, needs more resources)
echo "  Creating job: openalex-convert-works"
aws glue create-job \
    --name "openalex-convert-works" \
    --role "${ROLE_ARN}" \
    --command "{
        \"Name\": \"glueetl\",
        \"ScriptLocation\": \"s3://${BUCKET}/${SCRIPTS_PREFIX}/convert_works.py\",
        \"PythonVersion\": \"3\"
    }" \
    --default-arguments "{
        \"--job-language\": \"python\",
        \"--SOURCE_PATH\": \"s3://${BUCKET}/${SOURCE_PREFIX}/works\",
        \"--OUTPUT_PATH\": \"s3://${BUCKET}/${OUTPUT_PREFIX}/works\",
        \"--TempDir\": \"s3://${BUCKET}/glue-temp/\",
        \"--enable-metrics\": \"true\"
    }" \
    --glue-version "4.0" \
    --worker-type "G.2X" \
    --number-of-workers 25 \
    --timeout 240 \
    > /dev/null \
    && echo "    ✓ Created" || echo "    ✗ FAILED (see error above)"

# All other entities
SMALL_ENTITIES="authors institutions sources publishers topics funders domains fields subfields awards concepts continents countries institution-types keywords languages licenses sdgs source-types work-types"

for ENTITY in ${SMALL_ENTITIES}; do
    echo "  Creating job: openalex-convert-${ENTITY}"
    aws glue create-job \
        --name "openalex-convert-${ENTITY}" \
        --role "${ROLE_ARN}" \
        --command "{
            \"Name\": \"glueetl\",
            \"ScriptLocation\": \"s3://${BUCKET}/${SCRIPTS_PREFIX}/convert_small_entity.py\",
            \"PythonVersion\": \"3\"
        }" \
        --default-arguments "{
            \"--job-language\": \"python\",
            \"--ENTITY_NAME\": \"${ENTITY}\",
            \"--SOURCE_PATH\": \"s3://${BUCKET}/${SOURCE_PREFIX}/${ENTITY}\",
            \"--OUTPUT_PATH\": \"s3://${BUCKET}/${OUTPUT_PREFIX}/${ENTITY}\",
            \"--TempDir\": \"s3://${BUCKET}/glue-temp/\"
        }" \
        --glue-version "4.0" \
        --worker-type "G.1X" \
        --number-of-workers 10 \
        --timeout 120 \
        > /dev/null \
        && echo "    ✓ Created" || echo "    ✗ FAILED (see error above)"
done
echo ""

# ---- Step 4: Run all jobs ----
echo "Step 4: Starting all Glue jobs..."

for ENTITY in ${ALL_ENTITIES}; do
    echo "  Starting: openalex-convert-${ENTITY}"
    aws glue start-job-run --job-name "openalex-convert-${ENTITY}" > /dev/null \
        && echo "    ✓ Started" || echo "    ✗ FAILED (see error above)"
done

echo ""
echo "============================================"
echo "All jobs started! Monitor progress with:"
echo ""
echo "  bash monitor_jobs.sh"
echo ""
echo "Or check the AWS Console → Glue → Jobs"
echo ""
echo "Once all jobs complete, run the Athena setup:"
echo "  Copy queries from athena_setup.sql into the Athena console"
echo "============================================"
