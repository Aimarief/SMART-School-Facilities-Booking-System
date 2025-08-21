import * as admin from "firebase-admin";
import { onSchedule } from "firebase-functions/v2/scheduler";

admin.initializeApp();

// This function runs every 15 minutes and re-enables facilities
// whose inactiveTo has already passed, clearing inactive fields
export const autoReEnableFacilities = onSchedule(
  {
    schedule: "every 15 minutes",
    timeZone: "Asia/Kuala_Lumpur",
    // optional: adjust memory/timeout if needed
    // memory: "256MiB",
    // timeoutSeconds: 60,
  },
  async () => {
    const db = admin.firestore();
    const now = admin.firestore.Timestamp.now();

    const snap = await db
      .collection("Facilities")
      .where("deleted", "==", false) // only live docs
      .where("active", "==", false) // currently disabled
      .where("inactiveTo", "<=", now) // end has passed
      .limit(450) // safety limit for batch
      .get();

    if (snap.empty) {
      console.log("No facilities to re-enable");
      return;
    }

    const batch = db.batch();
    snap.docs.forEach((doc) => {
      batch.update(doc.ref, {
        active: true,
        inactiveReason: null,
        inactiveFrom: null,
        inactiveTo: null,
      });
    });

    await batch.commit();
    console.log(`Re-enabled ${snap.size} facilities`);
  }
);
