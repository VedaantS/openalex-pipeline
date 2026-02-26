-- =============================================================================
-- OpenAlex: Flatten Nested Fields
-- =============================================================================
-- Run these in Athena AFTER the base tables are set up.
-- These create new Parquet tables from nested arrays in works.
-- Replace 'codex-raw-data-us-east-1' with your actual bucket name.
--
-- These are optional but highly recommended — they make joins and
-- filters on nested data much faster and easier.
-- =============================================================================


-- ---- Works ↔ Authors (who wrote what) ----
CREATE TABLE openalex.works_authorships
WITH (
    format = 'PARQUET',
    external_location = 's3://codex-raw-data-us-east-1/openalex-parquet/works_authorships/',
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


-- ---- Works ↔ Locations (where papers are published/hosted) ----
CREATE TABLE openalex.works_locations
WITH (
    format = 'PARQUET',
    external_location = 's3://codex-raw-data-us-east-1/openalex-parquet/works_locations/',
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


-- ---- Works ↔ Topics ----
CREATE TABLE openalex.works_topics
WITH (
    format = 'PARQUET',
    external_location = 's3://codex-raw-data-us-east-1/openalex-parquet/works_topics/',
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


-- ---- Works ↔ Concepts (legacy, but still useful) ----
CREATE TABLE openalex.works_concepts
WITH (
    format = 'PARQUET',
    external_location = 's3://codex-raw-data-us-east-1/openalex-parquet/works_concepts/',
    write_compression = 'SNAPPY'
) AS
SELECT
    id AS work_id,
    publication_year,
    concept.id AS concept_id,
    concept.display_name AS concept_name,
    concept.level AS concept_level,
    concept.score AS concept_score
FROM openalex.works
CROSS JOIN UNNEST(concepts) AS t(concept);


-- ---- Works ↔ Referenced Works (citation graph) ----
CREATE TABLE openalex.works_citations
WITH (
    format = 'PARQUET',
    external_location = 's3://codex-raw-data-us-east-1/openalex-parquet/works_citations/',
    write_compression = 'SNAPPY'
) AS
SELECT
    id AS citing_work_id,
    publication_year,
    ref AS cited_work_id
FROM openalex.works
CROSS JOIN UNNEST(referenced_works) AS t(ref);


-- ---- Works ↔ Grants/Funding ----
CREATE TABLE openalex.works_grants
WITH (
    format = 'PARQUET',
    external_location = 's3://codex-raw-data-us-east-1/openalex-parquet/works_grants/',
    write_compression = 'SNAPPY'
) AS
SELECT
    id AS work_id,
    publication_year,
    g.funder AS funder_id,
    g.funder_display_name AS funder_name,
    g.award_id
FROM openalex.works
CROSS JOIN UNNEST(grants) AS t(g);


-- ---- Verify flattened tables ----
SELECT 'works_authorships' as tbl, COUNT(*) as rows FROM openalex.works_authorships
UNION ALL SELECT 'works_locations', COUNT(*) FROM openalex.works_locations
UNION ALL SELECT 'works_topics', COUNT(*) FROM openalex.works_topics
UNION ALL SELECT 'works_concepts', COUNT(*) FROM openalex.works_concepts
UNION ALL SELECT 'works_citations', COUNT(*) FROM openalex.works_citations
UNION ALL SELECT 'works_grants', COUNT(*) FROM openalex.works_grants;
