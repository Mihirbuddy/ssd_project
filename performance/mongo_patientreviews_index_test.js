const dbCare = db.getSiblingDB("careconnect");

const result = dbCare.PatientReviews
    .find({
        clinicId: "C1"
    })
    .explain("executionStats");

printjson(result);
