// CareConnect
// Workflow 4: Multi-Faceted Review Analytics

const dbCare = db.getSiblingDB("careconnect");

const result=dbCare.PatientReviews.aggregate([

    {
        $facet: {

            // 1. Count reviews for each rating
            ratingBuckets: [
                {
                    $group: {
                        _id: "$rating",
                        count: { $sum: 1 }
                    }
                },
                {
                    $sort: {
                        _id: 1
                    }
                }
            ],

            // 2. Find most frequent bedside-manner tags
            frequentTags: [
                {
                    $unwind: "$bedsideMannerTags"
                },
                {
                    $group: {
                        _id: "$bedsideMannerTags",
                        count: { $sum: 1 }
                    }
                },
                {
                    $sort: {
                        count: -1
                    }
                }
            ],

            // 3. Calculate global average rating
            globalAverage: [
                {
                    $group: {
                        _id: null,
                        averageRating: {
                            $avg: "$rating"
                        }
                    }
                }
            ]
        }
    }

]);

printjson(result);