"""
OpenAlex Small Entity → Parquet conversion (AWS Glue job)

Reusable script for: authors, institutions, sources, publishers,
topics, funders, domains, fields, subfields.

Pass --ENTITY_NAME, --SOURCE_PATH, --OUTPUT_PATH as job arguments.

Glue job settings:
  - Worker type: G.1X
  - Number of workers: 10
  - Timeout: 120 min
  - Glue version: 4.0
"""

import sys
from awsglue.utils import getResolvedOptions
from pyspark.sql import SparkSession
from pyspark.sql.functions import col

# Parse job arguments
args = getResolvedOptions(sys.argv, ['JOB_NAME', 'ENTITY_NAME', 'SOURCE_PATH', 'OUTPUT_PATH'])

entity = args['ENTITY_NAME']

spark = SparkSession.builder \
    .appName(f"{args['JOB_NAME']}-{entity}") \
    .config("spark.sql.adaptive.enabled", "true") \
    .config("spark.sql.adaptive.coalescePartitions.enabled", "true") \
    .config("spark.sql.parquet.compression.codec", "snappy") \
    .getOrCreate()

print(f"Converting entity: {entity}")
print(f"Reading from: {args['SOURCE_PATH']}")

# Read all .gz JSONL files
df = spark.read \
    .option("multiline", "false") \
    .option("mode", "PERMISSIVE") \
    .option("columnNameOfCorruptRecord", "_corrupt_record") \
    .json(f"{args['SOURCE_PATH']}/**/*.gz")

record_count = df.count()
print(f"Total {entity} records: {record_count}")

# Drop corrupt record column if present
if "_corrupt_record" in df.columns:
    corrupt_count = df.filter(col("_corrupt_record").isNotNull()).count()
    if corrupt_count > 0:
        print(f"WARNING: {corrupt_count} corrupt records in {entity}")
    df = df.drop("_corrupt_record")

# Repartition based on size
# Small entities (domains, fields, subfields): few partitions
# Medium entities (institutions, sources, publishers, topics, funders): moderate
# Large entities (authors): more partitions
REPARTITION_MAP = {
    "authors": 100,
    "institutions": 20,
    "sources": 20,
    "publishers": 10,
    "topics": 10,
    "funders": 10,
    "domains": 1,
    "fields": 1,
    "subfields": 5,
    "awards": 1,
    "concepts": 10,
    "continents": 1,
    "countries": 1,
    "institution-types": 1,
    "keywords": 10,
    "languages": 1,
    "licenses": 1,
    "sdgs": 1,
    "source-types": 1,
    "work-types": 1,
}
num_partitions = REPARTITION_MAP.get(entity, 20)

print(f"Writing parquet ({num_partitions} partitions) to: {args['OUTPUT_PATH']}")

df.repartition(num_partitions) \
    .write \
    .mode("overwrite") \
    .option("compression", "snappy") \
    .parquet(args['OUTPUT_PATH'])

print(f"{entity} conversion complete!")
spark.stop()
