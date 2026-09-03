// CareConnect MongoDB setup

const dbCare = db.getSiblingDB("careconnect");


// --------------------------------------------------
// 1. MedicalCatalogs
// ---------------------------------------------



dbCare.createCollection("MedicalCatalogs", {
    validator: {
        $jsonSchema: {
            bsonType: "object",

            required: ["catalogType", "name", "createdAt"],

            properties: {
                catalogType: {
                    bsonType: "string",
                    enum: ["SPECIALIST", "MEDICATION"]
                },

                name: {
                    bsonType: "string"
                },

                specialization: {
                    bsonType: "string"
                },

                availability: {
                    bsonType: "array"
                },

                medicationDetails: {
                    bsonType: "object"
                },

                createdAt: {
                    bsonType: "date"
                }
            }
        }
    }
});


// --------------------------------------------------
// 2. PatientReviews
// --------------------------------------------------

dbCare.createCollection("PatientReviews", {
    validator: {
        $jsonSchema: {
            bsonType: "object",

            required: [
                "patientId",
                "clinicId",
                "rating",
                "bedsideMannerTags",
                "createdAt"
            ],

            properties: {
                patientId: {
                    bsonType: "string"
                },

                clinicId: {
                    bsonType: "string"
                },

                rating: {
                    bsonType: "int",
                    minimum: 1,
                    maximum: 5
                },

                bedsideMannerTags: {
                    bsonType: "array",
                    items: {
                        bsonType: "string"
                    }
                },

                comment: {
                    bsonType: "string"
                },

                createdAt: {
                    bsonType: "date"
                }
            }
        }
    }
});


// --------------------------------------------------
// 3. NursePings
// --------------------------------------------------

dbCare.createCollection("NursePings", {
    validator: {
        $jsonSchema: {
            bsonType: "object",

            required: [
                "nurseId",
                "location",
                "isActive",
                "createdAt"
            ],

            properties: {
                nurseId: {
                    bsonType: "string"
                },

                location: {
                    bsonType: "object",

                    required: ["type", "coordinates"],

                    properties: {
                        type: {
                            enum: ["Point"]
                        },

                        coordinates: {
                            bsonType: "array"
                        }
                    }
                },

                isActive: {
                    bsonType: "bool"
                },

                createdAt: {
                    bsonType: "date"
                }
            }
        }
    }
});


// --------------------------------------------------
// Indexes
// --------------------------------------------------

// Required geospatial index
dbCare.NursePings.createIndex({
    location: "2dsphere"
});

// Required 2-hour TTL index
dbCare.NursePings.createIndex(
    { createdAt: 1 },
    { expireAfterSeconds: 7200 }
);

// Useful for review analytics
dbCare.PatientReviews.createIndex({
    clinicId: 1
});