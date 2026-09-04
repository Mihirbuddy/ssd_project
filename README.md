# GITHUB URL
```text
https://github.com/Mihirbuddy/ssd_project/
```
# LAST COMMIT HASH
```text
abc
```

# CareConnect – On-Demand Telemedicine

CareConnect is a database-focused telemedicine project built with PostgreSQL and MongoDB.

- **PostgreSQL** stores patients, clinics, appointments, wallet balances, and audit records.
- **MongoDB** stores medical catalogs, patient reviews, and temporary nurse-location pings.

## Project structure

```text
docs/
  relational_erd.png
  mongo_schema_map.json

sql/
  01_schema_ddl.sql
  02_indexes.sql
  03_triggers_and_audit.sql
  04_stored_procedures.sql
  05_materialized_views.sql
  06_window_analytics.sql

mongo/
  01_collections_and_indexes.js
  02_workflow3_geonear.js
  03_workflow4_facet.js

data_generation/
  postgres_seeder.py
  mongo_seeder.py
  requirements.txt

performance/
  generate_execution_stats.js
  mongo_execution_stats.json

README.md
```

## 1. Python setup

Run from the project root:

```bash
python3 -m venv ssd
source ssd/bin/activate
python -m pip install -r data_generation/requirements.txt
```

For later sessions, activate the existing environment with:

```bash
source ssd/bin/activate
```

Use `deactivate` when finished. Keep `ssd/`, `.env`, and `__pycache__/` in `.gitignore`.

## 2. Connection configuration

Create `.env` in the project root:

```env
MONGO_URI=mongodb+srv://USERNAME:PASSWORD@YOUR_CLUSTER.mongodb.net/?appName=Cluster0
MONGO_DB=careconnect
```

Do not commit this file. If the password contains reserved URI characters such as `@`, `/`, `:` or `#`, URL-encode it.

The PostgreSQL seeder receives its connection string through the `--dsn` argument shown below.

## 3. Create the PostgreSQL database

Create the database if it does not already exist:

```bash
createdb careconnect
```

Apply the SQL files in order:

```bash
psql -d careconnect -f sql/01_schema_ddl.sql
psql -d careconnect -f sql/02_indexes.sql
psql -d careconnect -f sql/03_triggers_and_audit.sql
psql -d careconnect -f sql/04_stored_procedures.sql
psql -d careconnect -f sql/05_materialized_views.sql
```

## 4. Create the MongoDB collections

For MongoDB Atlas:

```bash
mongosh "mongodb+srv://YOUR_CLUSTER.mongodb.net/careconnect?appName=Cluster0" \
  --apiVersion 1 \
  --username USERNAME \
  --file mongo/01_collections_and_indexes.js
```

This creates `MedicalCatalogs`, `PatientReviews`, and `NursePings`, together with their validators and indexes. Run it once on a fresh database; running it again may produce `NamespaceExists`.

## 5. Seed the databases

Seed PostgreSQL first:

```bash
python data_generation/postgres_seeder.py \
  --dsn "postgresql://USER:PASSWORD@localhost:5432/careconnect"
```

Then seed MongoDB using the connection from `.env`:

```bash
python data_generation/mongo_seeder.py
```

After seeding, refresh the materialized view and run the window-analysis query:

```bash
psql -d careconnect \
  -c "REFRESH MATERIALIZED VIEW CONCURRENTLY clinic_monthly_discharges;"

psql -d careconnect -f sql/06_window_analytics.sql
```

## 6. Run the MongoDB workflows

Nearest active nurse:

```bash
mongosh "mongodb+srv://YOUR_CLUSTER.mongodb.net/careconnect?appName=Cluster0" \
  --apiVersion 1 \
  --username USERNAME \
  --file mongo/02_workflow3_geonear.js
```

Review analytics:

```bash
mongosh "mongodb+srv://YOUR_CLUSTER.mongodb.net/careconnect?appName=Cluster0" \
  --apiVersion 1 \
  --username USERNAME \
  --file mongo/03_workflow4_facet.js
```

To save a workflow's output, append a redirect such as:

```bash
--file mongo/02_workflow3_geonear.js > mongo/output1.txt
```

### Running from inside `mongosh`

After connecting to Atlas, scripts can also be loaded interactively:

```javascript
load("mongo/01_collections_and_indexes.js")
load("mongo/02_workflow3_geonear.js")
load("mongo/03_workflow4_facet.js")
```

Useful checks:

```javascript
show collections
db.MedicalCatalogs.countDocuments()
db.PatientReviews.countDocuments()
db.NursePings.countDocuments()
db.PatientReviews.getIndexes()
db.NursePings.getIndexes()
```

Python files must be run from the machine terminal. MongoDB JavaScript files can be run with `mongosh --file` or with `load()` inside `mongosh`.

## 7. Performance evidence

## PostgreSQL Performance Analysis
Workflow 2 achieves an Index Only Scan by utilizing the covering index idx_appointments_discharged_analytics. By filtering the created_at timestamp directly at the index level and including the copay_amount payload, the query executes with zero heap fetches and avoids a costly sequential scan on the appointments table.


**Workflow 2: Postgres Performance Proof (7-Day Moving Average)**

The query successfully avoids sequential scans by utilizing a covering index (`idx_appointments_discharged_analytics`).

```text
Aggregate  (cost=7242.14..7242.15 rows=1 width=32) (actual time=30.302..30.304 rows=1.00 loops=1)
  Output: json_agg(sub.*)
  Buffers: shared hit=209
  ->  Subquery Scan on sub  (cost=5441.58..7186.80 rows=22134 width=76) (actual time=28.888..29.461 rows=775.00 loops=1)
        Output: sub.*
        Buffers: shared hit=209
        ->  Incremental Sort  (cost=5441.58..6965.46 rows=22134 width=124) (actual time=28.863..29.298 rows=775.00 loops=1)
              Output: moving_avg.clinic_id, moving_avg.day, moving_avg.revenue, (round(moving_avg.revenue_7day_avg, 2)), (dense_rank() OVER w1), moving_avg.revenue_7day_avg
              Sort Key: moving_avg.day, (dense_rank() OVER w1)
              Presorted Key: moving_avg.day
              Full-sort Groups: 16  Sort Method: quicksort  Average Memory: 28kB  Peak Memory: 28kB
              Buffers: shared hit=209
              ->  WindowAgg  (cost=5435.33..5933.32 rows=22134 width=124) (actual time=28.801..29.120 rows=775.00 loops=1)
                    Output: moving_avg.clinic_id, moving_avg.day, moving_avg.revenue, round(moving_avg.revenue_7day_avg, 2), dense_rank() OVER w1, moving_avg.revenue_7day_avg
                    Window: w1 AS (PARTITION BY moving_avg.day ORDER BY moving_avg.revenue_7day_avg ROWS UNBOUNDED PRECEDING)
                    Storage: Memory  Maximum Storage: 17kB
                    Buffers: shared hit=209
                    ->  Sort  (cost=5435.31..5490.64 rows=22134 width=84) (actual time=28.790..28.813 rows=775.00 loops=1)
                          Output: moving_avg.day, moving_avg.revenue_7day_avg, moving_avg.clinic_id, moving_avg.revenue
                          Sort Key: moving_avg.day, moving_avg.revenue_7day_avg DESC
                          Sort Method: quicksort  Memory: 67kB
                          Buffers: shared hit=209
                          ->  Subquery Scan on moving_avg  (cost=3395.24..3837.90 rows=22134 width=84) (actual time=28.009..28.480 rows=775.00 loops=1)
                                Output: moving_avg.day, moving_avg.revenue_7day_avg, moving_avg.clinic_id, moving_avg.revenue
                                Buffers: shared hit=209
                                ->  WindowAgg  (cost=3395.24..3837.90 rows=22134 width=84) (actual time=28.008..28.433 rows=775.00 loops=1)
                                      Output: appointments.clinic_id, ((appointments.created_at)::date), (sum(appointments.copay_amount)), avg((sum(appointments.copay_amount))) OVER w1
                                      Window: w1 AS (PARTITION BY appointments.clinic_id ORDER BY ((appointments.created_at)::date) ROWS BETWEEN '6'::bigint PRECEDING AND CURRENT ROW)
                                      Storage: Memory  Maximum Storage: 17kB
                                      Buffers: shared hit=209
                                      ->  Sort  (cost=3395.22..3450.56 rows=22134 width=52) (actual time=27.600..27.623 rows=775.00 loops=1)
                                            Output: appointments.clinic_id, ((appointments.created_at)::date), (sum(appointments.copay_amount))
                                            Sort Key: appointments.clinic_id, ((appointments.created_at)::date)
                                            Sort Method: quicksort  Memory: 61kB
                                            Buffers: shared hit=209
                                            ->  HashAggregate  (cost=1465.80..1797.81 rows=22134 width=52) (actual time=26.356..26.986 rows=775.00 loops=1)
                                                  Output: appointments.clinic_id, ((appointments.created_at)::date), sum(appointments.copay_amount)
                                                  Group Key: appointments.clinic_id, (appointments.created_at)::date
                                                  Batches: 1  Memory Usage: 849kB
                                                  Buffers: shared hit=209
                                                  ->  Index Only Scan using idx_appointments_discharged_analytics on public.appointments  (cost=0.29..1277.76 rows=25073 width=26) (actual time=0.450..15.787 rows=25397.00 loops=1)
                                                        Output: appointments.clinic_id, (appointments.created_at)::date, appointments.copay_amount
                                                        Index Cond: (appointments.created_at >= (CURRENT_DATE - '30 days'::interval))
                                                        Heap Fetches: 0
                                                        Index Searches: 1
                                                        Buffers: shared hit=209
Planning:
  Buffers: shared hit=151
Planning Time: 2.978 ms
Execution Time: 30.608 ms


Generate PostgreSQL execution statistics:
```bash
   psql -U YOUR_USERNAME -d careconnect -c "EXPLAIN (ANALYZE, BUFFERS, VERBOSE, FORMAT JSON) WITH daily_revenue AS (SELECT clinic_id, created_at::date AS day, SUM(copay_amount) AS revenue FROM appointments WHERE created_at >= (CURRENT_DATE - INTERVAL '30 days') GROUP BY clinic_id, created_at::date), moving_avg AS (SELECT clinic_id, day, revenue, AVG(revenue) OVER (PARTITION BY clinic_id ORDER BY day ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS revenue_7day_avg FROM daily_revenue) SELECT clinic_id, day, revenue, ROUND(revenue_7day_avg, 2) AS revenue_7day_avg, DENSE_RANK() OVER (PARTITION BY day ORDER BY revenue_7day_avg DESC) AS clinic_rank_that_day FROM moving_avg ORDER BY day, clinic_rank_that_day;" > performance/postgres_explain_analyzes_stats.txt
```

## MongoDB Performance Analysis
Generate MongoDB execution statistics:

```bash
mongosh "mongodb+srv://YOUR_CLUSTER.mongodb.net/careconnect?appName=Cluster0" \
  --apiVersion 1 \
  --username USERNAME \
  --quiet \
  --file performance/generate_execution_stats.js \
  > performance/mongo_execution_stats.json
```

The mongo_execution_stats.json file contains execution statistics for both MongoDB workflows. Workflow 3 uses the location_2dsphere index through the GEO_NEAR_2DSPHERE stage, allowing MongoDB to efficiently find the nearest nurse without scanning the entire collection. Workflow 4 uses a COLLSCAN because its $facet pipeline requires every patient review to calculate rating counts, frequent tags, and the overall average. Metrics such as executionTimeMillis, totalKeysExamined, and totalDocsExamined indicate the cost and efficiency of each query.
Validate the generated JSON:

```bash
python -m json.tool performance/mongo_execution_stats.json > /dev/null
```

See `performance/README.md` for the PostgreSQL `EXPLAIN` and MongoDB `explain("executionStats")` checks.

## Database relationship

`PatientReviews.patientId` and `PatientReviews.clinicId` are logical references to PostgreSQL patients and clinics. MongoDB cannot enforce foreign keys across databases, so the application or seeding process must ensure that these IDs exist in PostgreSQL. Patient and clinic master records are not duplicated in MongoDB.

## Local MongoDB

To use a local MongoDB server, change `.env` to:

```env
MONGO_URI=mongodb://localhost:27017
MONGO_DB=careconnect
```

Then use this connection for MongoDB shell commands:

```bash
mongosh "mongodb://localhost:27017/careconnect"
```

## Notes

- `book_appointment` performs balance deduction, appointment creation, and auditing in one transaction.
- `idx_active_consult` applies only to `WAITING` and `IN CONSULTATION` appointments.
- `REFRESH MATERIALIZED VIEW CONCURRENTLY` requires the unique index created for the view.
- GeoJSON coordinates use `[longitude, latitude]` order.
- `NursePings.createdAt` is stored as a BSON `Date`; its TTL index removes records after two hours.
