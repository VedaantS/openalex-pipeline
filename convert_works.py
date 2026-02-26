"""
OpenAlex Works → Parquet conversion (AWS Glue job)

This is the largest entity. Reads gzipped JSONL from S3, writes
partitioned Parquet back to S3. Partitioned by publication_year
for efficient Athena queries.

Glue job settings:
  - Worker type: G.2X
  - Number of workers: 25
  - Timeout: 240 min
  - Glue version: 4.0
"""

import sys
from awsglue.utils import getResolvedOptions
from pyspark.sql import SparkSession
from pyspark.sql.functions import col

# Parse job arguments
args = getResolvedOptions(sys.argv, ['JOB_NAME', 'SOURCE_PATH', 'OUTPUT_PATH'])

spark = SparkSession.builder \
    .appName(args['JOB_NAME']) \
    .config("spark.sql.adaptive.enabled", "true") \
    .config("spark.sql.adaptive.coalescePartitions.enabled", "true") \
    .config("spark.sql.parquet.compression.codec", "snappy") \
    .getOrCreate()

print(f"Reading works from: {args['SOURCE_PATH']}")

# Read all .gz JSONL files
# multiline=false because each line is one JSON record (JSONL format)
df = spark.read \
    .option("multiline", "false") \
    .option("mode", "PERMISSIVE") \
    .option("columnNameOfCorruptRecord", "_corrupt_record") \
    .json(f"{args['SOURCE_PATH']}/**/*.gz")

record_count = df.count()
print(f"Total records read: {record_count}")

# Check for corrupt records
corrupt_count = df.filter(col("_corrupt_record").isNotNull()).count()
if corrupt_count > 0:
    print(f"WARNING: {corrupt_count} corrupt records found. These will have null fields.")

# Drop the corrupt record column before writing
if "_corrupt_record" in df.columns:
    df = df.drop("_corrupt_record")

# Write as partitioned Parquet
# repartition(400) targets ~128-256MB per output file
# partitionBy("publication_year") makes year-filtered queries very fast
print(f"Writing parquet to: {args['OUTPUT_PATH']}")

df.repartition(400) \
    .write \
    .mode("overwrite") \
    .option("compression", "snappy") \
    .partitionBy("publication_year") \
    .parquet(args['OUTPUT_PATH'])

print("Works conversion complete!")
spark.stop()
