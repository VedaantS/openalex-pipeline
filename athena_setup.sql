-- =============================================================================
-- OpenAlex Athena Setup
-- =============================================================================
-- Run these queries in the Athena console ONE AT A TIME.
-- Replace 'your-bucket' with your actual bucket name.
--
-- FIRST: Go to Athena → Settings → set query result location to:
--   s3://your-bucket/athena-results/
-- =============================================================================


-- ---- 1. Create database ----
CREATE DATABASE IF NOT EXISTS openalex;


-- ---- 2. Create tables (run each separately) ----

-- Works (partitioned by publication_year)
CREATE EXTERNAL TABLE IF NOT EXISTS openalex.works
STORED AS PARQUET
LOCATION 's3://your-bucket/openalex-parquet/works/'
TBLPROPERTIES ('parquet.compress' = 'SNAPPY');

-- Load partitions for works
MSCK REPAIR TABLE openalex.works;

-- Authors
CREATE EXTERNAL TABLE IF NOT EXISTS openalex.authors
STORED AS PARQUET
LOCATION 's3://your-bucket/openalex-parquet/authors/'
TBLPROPERTIES ('parquet.compress' = 'SNAPPY');

-- Institutions
CREATE EXTERNAL TABLE IF NOT EXISTS openalex.institutions
STORED AS PARQUET
LOCATION 's3://your-bucket/openalex-parquet/institutions/'
TBLPROPERTIES ('parquet.compress' = 'SNAPPY');

-- Sources
CREATE EXTERNAL TABLE IF NOT EXISTS openalex.sources
STORED AS PARQUET
LOCATION 's3://your-bucket/openalex-parquet/sources/'
TBLPROPERTIES ('parquet.compress' = 'SNAPPY');

-- Publishers
CREATE EXTERNAL TABLE IF NOT EXISTS openalex.publishers
STORED AS PARQUET
LOCATION 's3://your-bucket/openalex-parquet/publishers/'
TBLPROPERTIES ('parquet.compress' = 'SNAPPY');

-- Topics
CREATE EXTERNAL TABLE IF NOT EXISTS openalex.topics
STORED AS PARQUET
LOCATION 's3://your-bucket/openalex-parquet/topics/'
TBLPROPERTIES ('parquet.compress' = 'SNAPPY');

-- Funders
CREATE EXTERNAL TABLE IF NOT EXISTS openalex.funders
STORED AS PARQUET
LOCATION 's3://your-bucket/openalex-parquet/funders/'
TBLPROPERTIES ('parquet.compress' = 'SNAPPY');

-- Domains
CREATE EXTERNAL TABLE IF NOT EXISTS openalex.domains
STORED AS PARQUET
LOCATION 's3://your-bucket/openalex-parquet/domains/'
TBLPROPERTIES ('parquet.compress' = 'SNAPPY');

-- Fields
CREATE EXTERNAL TABLE IF NOT EXISTS openalex.fields
STORED AS PARQUET
LOCATION 's3://your-bucket/openalex-parquet/fields/'
TBLPROPERTIES ('parquet.compress' = 'SNAPPY');

-- Subfields
CREATE EXTERNAL TABLE IF NOT EXISTS openalex.subfields
STORED AS PARQUET
LOCATION 's3://your-bucket/openalex-parquet/subfields/'
TBLPROPERTIES ('parquet.compress' = 'SNAPPY');


-- ---- 3. Verify everything works ----

-- Check row counts
SELECT 'works' as entity, COUNT(*) as rows FROM openalex.works
UNION ALL SELECT 'authors', COUNT(*) FROM openalex.authors
UNION ALL SELECT 'institutions', COUNT(*) FROM openalex.institutions
UNION ALL SELECT 'sources', COUNT(*) FROM openalex.sources
UNION ALL SELECT 'publishers', COUNT(*) FROM openalex.publishers
UNION ALL SELECT 'topics', COUNT(*) FROM openalex.topics;

-- Preview works
SELECT * FROM openalex.works LIMIT 5;

-- Works by year
SELECT publication_year, COUNT(*) as count
FROM openalex.works
GROUP BY publication_year
ORDER BY publication_year DESC
LIMIT 20;

-- Find a famous paper
SELECT id, title, publication_year, cited_by_count
FROM openalex.works
WHERE title LIKE '%attention is all you need%'
LIMIT 5;
