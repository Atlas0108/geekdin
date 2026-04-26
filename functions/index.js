const { onCall } = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");

exports.helloWorld = onCall(
  { region: "us-central1" },
  (request) => {
    const source = request.data?.source ?? "unknown";
    logger.info("helloWorld called", { source });
    return {
      message: `Hello from Firebase Functions (${source})`,
    };
  }
);
