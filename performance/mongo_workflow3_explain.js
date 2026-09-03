const dbCare = db.getSiblingDB("careconnect");

const result = dbCare.NursePings.explain("executionStats").aggregate([
  {
    $geoNear: {
      near: {
        type: "Point",
        coordinates: [78.4867, 17.385],
      },

      key: "location",

      distanceField: "distanceInMeters",

      spherical: true,

      query: {
        isActive: true,
      },
    },
  },

  {
    $limit: 1,
  },
]);

printjson(result);
