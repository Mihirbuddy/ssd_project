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

Generate MongoDB execution statistics:

```bash
mongosh "mongodb+srv://YOUR_CLUSTER.mongodb.net/careconnect?appName=Cluster0" \
  --apiVersion 1 \
  --username USERNAME \
  --quiet \
  --file performance/generate_execution_stats.js \
  > performance/mongo_execution_stats.json
```

## MongoDB Performance Analysis

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
