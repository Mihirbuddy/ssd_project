// CareConnect
// Workflow 3: Find nearest active mobile nurse

const dbCare = db.getSiblingDB("careconnect");


// Patient's current location
// Format: [longitude, latitude]

const patientLongitude = 78.4867;
const patientLatitude = 17.3850;


// Find nearest active nurse

dbCare.NursePings.aggregate([

    {
        $geoNear: {

            near: {
                type: "Point",
                coordinates: [
                    patientLongitude,
                    patientLatitude
                ]
            },

            key: "location",

            distanceField: "distanceInMeters",

            spherical: true,

            query: {
                isActive: true
            }
        }
    },

    {
        $limit: 1
    }

]);