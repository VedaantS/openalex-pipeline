#!/bin/bash
# =============================================================================
# QUICKSTART — Run these commands in order
# =============================================================================
# This is the TL;DR. If you want to understand what's happening,
# read README.md. If you just want it done, run these.
# =============================================================================

# ======================== EDIT THIS ========================
BUCKET="codex-raw-data-us-east-1"
# ===========================================================

# 0. Verify your data is there
aws s3 ls "s3://${BUCKET}/openalex/data/"
# You should see: PRE authors/ PRE works/ PRE institutions/ etc.
# If the path is different, edit SOURCE_PREFIX in setup.sh

# 1. Edit setup.sh with your bucket name
#    Open setup.sh and change BUCKET="codex-raw-data-us-east-1" to your actual bucket name
#    Also check SOURCE_PREFIX matches where your OpenAlex data lives

# 2. Run the setup script
cd openalex-pipeline
chmod +x setup.sh monitor_jobs.sh
bash setup.sh

# 3. Monitor jobs (re-run every few minutes, or use watch)
bash monitor_jobs.sh
# Or: watch -n 60 bash monitor_jobs.sh

# 4. Once ALL jobs show SUCCEEDED:
#    a. Go to AWS Console → Athena
#    b. Click Settings → set result location to s3://codex-raw-data-us-east-1/athena-results/
#    c. Copy-paste and run queries from athena_setup.sql ONE AT A TIME
#    d. (Optional) Run queries from athena_flatten.sql for flattened tables

# 5. Done! Query your data:
#    SELECT * FROM openalex.works LIMIT 10;
