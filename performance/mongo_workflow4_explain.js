const dbCare = db.getSiblingDB("careconnect");

const result = dbCare.PatientReviews
    .explain("executionStats")
    .aggregate([
        {
            $facet: {

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