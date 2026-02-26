# OpenAlex → Parquet → Athena: Complete Setup Guide

This guide takes you from a raw OpenAlex S3 mirror to a fully queryable analytics database using AWS Glue, S3 Parquet, and Athena.

**What you'll end up with:** All OpenAlex entities (works, authors, institutions, sources, topics, publishers, funders, domains, fields, subfields) stored as fast, columnar Parquet files in S3, queryable via SQL in Athena, and accessible from your app via the AWS SDK.

**Estimated time:** ~1 hour of setup, ~2-4 hours for Glue jobs to run.
**Estimated cost:** ~$20-40 one-time for Glue conversion. Athena queries are $5/TB scanned after that (very cheap with Parquet).

---

## Prerequisites

- An AWS account
- Your OpenAlex mirror in S3 (e.g., `s3://your-bucket/openalex/data/`)
- AWS CLI installed (`pip install awscli` or `brew install awscli`)
- Basic terminal access

**Replace `your-bucket` with your actual S3 bucket name throughout this guide.**

---

## Step 1: Create the output S3 location

You need a place to store the converted Parquet files. You can use the same bucket or a different one.

```bash
# Create a prefix for parquet output (no command needed — S3 creates prefixes automatically)
# Your parquet files will go to: s3://your-bucket/openalex-parquet/
```

---

## Step 2: Create an IAM Role for Glue

Glue needs permission to read your source data and write Parquet.

### Option A: AWS Console (easiest for beginners)

1. Go to **AWS Console → IAM → Roles → Create role**
2. Trusted entity type: **AWS service**
3. Use case: **Glue**
4. Click **Next**
5. Attach these policies:
   - `AWSGlueServiceRole` (search for it)
   - `AmazonS3FullAccess` (search for it) — in production you'd scope this down, but this is fine to start
6. Click **Next**
7. Role name: `OpenAlexGlueRole`
8. Click **Create role**

### Option B: AWS CLI

```bash
# Create the trust policy file
cat > trust-policy.json << 'EOF'
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

# Create the role
aws iam create-role \
  --role-name OpenAlexGlueRole \
  --assume-role-policy-document file://trust-policy.json

# Attach policies
aws iam attach-role-policy \
  --role-name OpenAlexGlueRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole

aws iam attach-role-policy \
  --role-name OpenAlexGlueRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess
```

---

## Step 3: Upload the Glue scripts to S3

Glue reads its job scripts from S3. Upload all the scripts from this package:

```bash
# From this directory, upload all glue scripts
aws s3 cp glue_scripts/ s3://your-bucket/glue-scripts/ --recursive
```

This uploads these scripts:
- `convert_works.py` — the big one (papers)
- `convert_small_entity.py` — reusable for all other entities

---

## Step 4: Create and run Glue jobs

### 4a: Create the Works job (largest entity, needs more resources)

```bash
aws glue create-job \
  --name openalex-convert-works \
  --role OpenAlexGlueRole \
  --command '{
    "Name": "glueetl",
    "ScriptLocation": "s3://your-bucket/glue-scripts/convert_works.py",
    "PythonVersion": "3"
  }' \
  --default-arguments '{
    "--job-language": "python",
    "--SOURCE_PATH": "s3://your-bucket/openalex/data/works",
    "--OUTPUT_PATH": "s3://your-bucket/openalex-parquet/works",
    "--TempDir": "s3://your-bucket/glue-temp/",
    "--enable-metrics": "true",
    "--enable-spark-ui": "true",
    "--spark-event-logs-path": "s3://your-bucket/glue-logs/"
  }' \
  --glue-version "4.0" \
  --worker-type "G.2X" \
  --number-of-workers 25 \
  --timeout 240
```

### 4b: Create jobs for every other entity

Run this for each entity. These are smaller so they need fewer resources:

```bash
# List of all other entities
for ENTITY in authors institutions sources publishers topics funders domains fields subfields; do
  aws glue create-job \
    --name "openalex-convert-${ENTITY}" \
    --role OpenAlexGlueRole \
    --command "{
      \"Name\": \"glueetl\",
      \"ScriptLocation\": \"s3://your-bucket/glue-scripts/convert_small_entity.py\",
      \"PythonVersion\": \"3\"
    }" \
    --default-arguments "{
      \"--job-language\": \"python\",
      \"--ENTITY_NAME\": \"${ENTITY}\",
      \"--SOURCE_PATH\": \"s3://your-bucket/openalex/data/${ENTITY}\",
      \"--OUTPUT_PATH\": \"s3://your-bucket/openalex-parquet/${ENTITY}\",
      \"--TempDir\": \"s3://your-bucket/glue-temp/\"
    }" \
    --glue-version "4.0" \
    --worker-type "G.1X" \
    --number-of-workers 10 \
    --timeout 120
done
```

### 4c: Run all jobs

```bash
# Start the works job
aws glue start-job-run --job-name openalex-convert-works
echo "Started works conversion"

# Start all other entity jobs
for ENTITY in authors institutions sources publishers topics funders domains fields subfields; do
  aws glue start-job-run --job-name "openalex-convert-${ENTITY}"
  echo "Started ${ENTITY} conversion"
done
```

### 4d: Monitor progress

```bash
# Check status of all jobs
for JOB in works authors institutions sources publishers topics funders domains fields subfields; do
  STATUS=$(aws glue get-job-runs --job-name "openalex-convert-${JOB}" --max-results 1 \
    --query 'JobRuns[0].JobRunState' --output text 2>/dev/null)
  echo "${JOB}: ${STATUS}"
done
```

You can also watch progress in the **AWS Console → Glue → Jobs** page.

**Expected runtimes:**
- works: 1-3 hours (this is ~130GB+ compressed, hundreds of millions of records)
- authors: 30-60 min
- institutions, sources, publishers, topics: 5-20 min each
- domains, fields, subfields: < 5 min each

---

## Step 5: Set up Athena

### 5a: Create an Athena results bucket

Athena needs somewhere to store query results.

```bash
# Create a location for Athena query results (can be same bucket)
# Just note the path — you'll need it in the console
# s3://your-bucket/athena-results/
```

### 5b: Configure Athena workgroup (first time only)

1. Go to **AWS Console → Athena**
2. If prompted, click **Settings** (top right) or **Edit settings**
3. Set query result location to: `s3://your-bucket/athena-results/`
4. Click **Save**

### 5c: Create the database and tables

Open the Athena query editor and run each of these queries one at a time. Copy-paste from `athena_setup.sql` or run them below:

```sql
-- Create database
CREATE DATABASE IF NOT EXISTS openalex;
```

Then for each entity, create a table. Run these one at a time:

```sql
-- Works (partitioned by publication_year)
CREATE EXTERNAL TABLE IF NOT EXISTS openalex.works
STORED AS PARQUET
LOCATION 's3://your-bucket/openalex-parquet/works/'
TBLPROPERTIES ('parquet.compress' = 'SNAPPY');

MSCK REPAIR TABLE openalex.works;
```

```sql
-- Authors
CREATE EXTERNAL TABLE IF NOT EXISTS openalex.authors
STORED AS PARQUET
LOCATION 's3://your-bucket/openalex-parquet/authors/'
TBLPROPERTIES ('parquet.compress' = 'SNAPPY');
```

```sql
-- Institutions
CREATE EXTERNAL TABLE IF NOT EXISTS openalex.institutions
STORED AS PARQUET
LOCATION 's3://your-bucket/openalex-parquet/institutions/'
TBLPROPERTIES ('parquet.compress' = 'SNAPPY');
```

```sql
-- Sources (journals, conferences, etc.)
CREATE EXTERNAL TABLE IF NOT EXISTS openalex.sources
STORED AS PARQUET
LOCATION 's3://your-bucket/openalex-parquet/sources/'
TBLPROPERTIES ('parquet.compress' = 'SNAPPY');
```

```sql
-- Publishers
CREATE EXTERNAL TABLE IF NOT EXISTS openalex.publishers
STORED AS PARQUET
LOCATION 's3://your-bucket/openalex-parquet/publishers/'
TBLPROPERTIES ('parquet.compress' = 'SNAPPY');
```

```sql
-- Topics
CREATE EXTERNAL TABLE IF NOT EXISTS openalex.topics
STORED AS PARQUET
LOCATION 's3://your-bucket/openalex-parquet/topics/'
TBLPROPERTIES ('parquet.compress' = 'SNAPPY');
```

```sql
-- Funders
CREATE EXTERNAL TABLE IF NOT EXISTS openalex.funders
STORED AS PARQUET
LOCATION 's3://your-bucket/openalex-parquet/funders/'
TBLPROPERTIES ('parquet.compress' = 'SNAPPY');
```

```sql
-- Domains
CREATE EXTERNAL TABLE IF NOT EXISTS openalex.domains
STORED AS PARQUET
LOCATION 's3://your-bucket/openalex-parquet/domains/'
TBLPROPERTIES ('parquet.compress' = 'SNAPPY');
```

```sql
-- Fields
CREATE EXTERNAL TABLE IF NOT EXISTS openalex.fields
STORED AS PARQUET
LOCATION 's3://your-bucket/openalex-parquet/fields/'
TBLPROPERTIES ('parquet.compress' = 'SNAPPY');
```

```sql
-- Subfields
CREATE EXTERNAL TABLE IF NOT EXISTS openalex.subfields
STORED AS PARQUET
LOCATION 's3://your-bucket/openalex-parquet/subfields/'
TBLPROPERTIES ('parquet.compress' = 'SNAPPY');
```

---

## Step 6: Verify it works

Run these test queries in Athena:

```sql
-- Count all works
SELECT COUNT(*) FROM openalex.works;

-- See what columns you have
SELECT * FROM openalex.works LIMIT 5;

-- Count works by year
SELECT publication_year, COUNT(*) as count
FROM openalex.works
GROUP BY publication_year
ORDER BY publication_year DESC
LIMIT 20;

-- Count authors
SELECT COUNT(*) FROM openalex.authors;

-- Find a specific paper
SELECT id, title, publication_year, cited_by_count
FROM openalex.works
WHERE title LIKE '%attention is all you need%'
LIMIT 5;
```

---

## Step 7: Create flattened tables for nested data (optional but recommended)

Works has nested arrays that are hard to query directly. Create flattened versions:

See `athena_flatten.sql` for ready-to-run queries, or run these:

```sql
-- Flatten authorships (who wrote what)
CREATE TABLE openalex.works_authorships
WITH (
  format = 'PARQUET',
  external_location = 's3://your-bucket/openalex-parquet/works_authorships/',
  write_compression = 'SNAPPY'
) AS
SELECT
    id AS work_id,
    publication_year,
    auth.author.id AS author_id,
    auth.author.display_name AS author_name,
    auth.author_position,
    auth.raw_affiliation_string
FROM openalex.works
CROSS JOIN UNNEST(authorships) AS t(auth);
```

```sql
-- Flatten locations (where papers are published/hosted)
CREATE TABLE openalex.works_locations
WITH (
  format = 'PARQUET',
  external_location = 's3://your-bucket/openalex-parquet/works_locations/',
  write_compression = 'SNAPPY'
) AS
SELECT
    id AS work_id,
    publication_year,
    loc.source.id AS source_id,
    loc.source.display_name AS source_name,
    loc.is_oa,
    loc.landing_page_url,
    loc.pdf_url
FROM openalex.works
CROSS JOIN UNNEST(locations) AS t(loc);
```

```sql
-- Flatten topics
CREATE TABLE openalex.works_topics
WITH (
  format = 'PARQUET',
  external_location = 's3://your-bucket/openalex-parquet/works_topics/',
  write_compression = 'SNAPPY'
) AS
SELECT
    id AS work_id,
    publication_year,
    topic.id AS topic_id,
    topic.display_name AS topic_name,
    topic.score AS topic_score
FROM openalex.works
CROSS JOIN UNNEST(topics) AS t(topic);
```

---

## Step 8: Query from your app

### Python (boto3)

```python
import boto3
import time

athena = boto3.client('athena', region_name='us-east-1')  # your region

def run_query(sql):
    response = athena.start_query_execution(
        QueryString=sql,
        QueryExecutionContext={'Database': 'openalex'},
        ResultConfiguration={'OutputLocation': 's3://your-bucket/athena-results/'}
    )
    query_id = response['QueryExecutionId']

    # Wait for completion
    while True:
        result = athena.get_query_execution(QueryExecutionId=query_id)
        state = result['QueryExecution']['Status']['State']
        if state in ('SUCCEEDED', 'FAILED', 'CANCELLED'):
            break
        time.sleep(1)

    if state == 'SUCCEEDED':
        results = athena.get_query_results(QueryExecutionId=query_id)
        return results
    else:
        raise Exception(f"Query failed: {result['QueryExecution']['Status']}")

# Example usage
results = run_query("""
    SELECT title, cited_by_count, publication_year
    FROM openalex.works
    WHERE cited_by_count > 1000
    ORDER BY cited_by_count DESC
    LIMIT 20
""")

for row in results['ResultSet']['Rows'][1:]:  # skip header
    print([col.get('VarCharValue', '') for col in row['Data']])
```

### Simpler: Use PyAthena (wrapper)

```bash
pip install pyathena
```

```python
from pyathena import connect
import pandas as pd

conn = connect(
    s3_staging_dir='s3://your-bucket/athena-results/',
    region_name='us-east-1'
)

df = pd.read_sql("""
    SELECT title, cited_by_count, publication_year
    FROM openalex.works
    WHERE cited_by_count > 1000
    ORDER BY cited_by_count DESC
    LIMIT 100
""", conn)

print(df)
```

---

## Monthly updates

When OpenAlex releases a new snapshot, re-run the Glue jobs:

```bash
# Re-run all conversion jobs
aws glue start-job-run --job-name openalex-convert-works
for ENTITY in authors institutions sources publishers topics funders domains fields subfields; do
  aws glue start-job-run --job-name "openalex-convert-${ENTITY}"
done

# After jobs complete, repair partitions for works
# (run in Athena)
# MSCK REPAIR TABLE openalex.works;
```

---

## Troubleshooting

**Glue job fails with OutOfMemory:** Increase `--number-of-workers` or use `G.2X` worker type.

**Athena says "table not found":** Make sure you selected the `openalex` database in the Athena dropdown (left sidebar).

**Athena shows no data:** Check that the Glue job completed successfully and Parquet files exist at the expected S3 path: `aws s3 ls s3://your-bucket/openalex-parquet/works/`

**Athena shows weird column names:** Parquet schema is inferred from the JSON. If some files have different schemas, you may get nulls. This is normal for OpenAlex — not all fields are present in all records.

**MSCK REPAIR TABLE hangs or fails:** This only applies to the `works` table (partitioned by year). If it fails, you can create partitions manually:
```sql
ALTER TABLE openalex.works ADD PARTITION (publication_year=2024) LOCATION 's3://your-bucket/openalex-parquet/works/publication_year=2024/';
```

---

## Cost summary

| Service | Cost | Notes |
|---------|------|-------|
| Glue (one-time conversion) | ~$20-40 | 25 workers × G.2X × 2hr for works + smaller jobs |
| S3 storage (Parquet) | ~$5-15/month | Parquet is smaller than gz JSON in many cases |
| Athena queries | $5/TB scanned | Parquet + partitions = very little data scanned per query |
| **Total ongoing** | **~$10-20/month** | Depends on query volume |
