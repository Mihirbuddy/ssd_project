import os
from dotenv import load_dotenv
import random
import certifi
from datetime import datetime, timedelta, timezone

from pymongo import MongoClient


# --------------------------------------------------
# MongoDB connection
# --------------------------------------------------
load_dotenv()

MONGODB_URI = os.getenv("MONGODB_URI")

if not MONGODB_URI:
    raise ValueError("MONGODB_URI not found in .env")

client = MongoClient(
    MONGODB_URI,
    tlsCAFile=certifi.where()
)

db = client["careconnect"]


# --------------------------------------------------
# Clear existing test data
# --------------------------------------------------

db.MedicalCatalogs.delete_many({})
db.PatientReviews.delete_many({})
db.NursePings.delete_many({})


# --------------------------------------------------
# 1. MedicalCatalogs
# --------------------------------------------------

medical_catalogs = [

    {
        "catalogType": "SPECIALIST",
        "name": "Dr. Amit Sharma",
        "specialization": "Cardiology",
        "availability": [
            {
                "day": "Monday",
                "startTime": "09:00",
                "endTime": "13:00"
            }
        ],
        "createdAt": datetime.now(timezone.utc)
    },

    {
        "catalogType": "SPECIALIST",
        "name": "Dr. Neha Verma",
        "specialization": "Dermatology",
        "availability": [
            {
                "day": "Tuesday",
                "startTime": "10:00",
                "endTime": "15:00"
            }
        ],
        "createdAt": datetime.now(timezone.utc)
    },

    {
        "catalogType": "MEDICATION",
        "name": "Paracetamol",
        "medicationDetails": {
            "dosage": "500mg",
            "manufacturer": "ABC Pharma"
        },
        "createdAt": datetime.now(timezone.utc)
    },

    {
        "catalogType": "MEDICATION",
        "name": "Amoxicillin",
        "medicationDetails": {
            "dosage": "250mg",
            "manufacturer": "XYZ Pharma"
        },
        "createdAt": datetime.now(timezone.utc)
    }
]

db.MedicalCatalogs.insert_many(medical_catalogs)

print("MedicalCatalogs inserted:", len(medical_catalogs))


# --------------------------------------------------
# 2. PatientReviews
# --------------------------------------------------

tags = [
    "friendly",
    "empathetic",
    "clear",
    "professional",
    "patient",
    "helpful"
]

reviews = []

for i in range(100000):

    review = {

        "patientId": "P" + str(random.randint(1, 5000)),

        "clinicId": "C" + str(random.randint(1, 100)),

        "rating": random.randint(1, 5),

        "bedsideMannerTags": random.sample(
            tags,
            random.randint(1, 3)
        ),

        "comment": "Generated patient review",

        "createdAt": datetime.now(timezone.utc)
    }

    reviews.append(review)


db.PatientReviews.insert_many(reviews)

print("PatientReviews inserted:", len(reviews))


# --------------------------------------------------
# 3. NursePings
# --------------------------------------------------

TOTAL_PINGS = 200000
BATCH_SIZE = 5000

inserted = 0


while inserted < TOTAL_PINGS:

    batch = []

    current_batch_size = min(
        BATCH_SIZE,
        TOTAL_PINGS - inserted
    )

    for i in range(current_batch_size):

        # Coordinates around Hyderabad
        longitude = random.uniform(78.30, 78.65)
        latitude = random.uniform(17.25, 17.55)

        # Keep generated timestamps within the last 90 minutes.
        # This prevents the 2-hour TTL index from immediately
        # deleting the generated performance-test data.
        minutes_ago = random.randint(0, 90)

        created_at = (
            datetime.now(timezone.utc)
            - timedelta(minutes=minutes_ago)
        )

        ping = {

            "nurseId":
                "N" + str(random.randint(1, 2000)),

            "location": {
                "type": "Point",
                "coordinates": [
                    longitude,
                    latitude
                ]
            },

            "isActive":
                random.choice([True, False]),

            "createdAt":
                created_at
        }

        batch.append(ping)


    db.NursePings.insert_many(batch)

    inserted += len(batch)

    print(
        "NursePings inserted:",
        inserted,
        "/",
        TOTAL_PINGS
    )


print("\nMongoDB seeding completed.")