/**
 * Firebase Cloud Function for Multi-Device FCM Notification Management
 * 
 * This function handles sending notifications to all registered tokens of a user
 * and automatically cleans up invalid or expired tokens from Firestore.
 */

const functions = require('firebase-functions');
const admin = require('firebase-admin');

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();

/**
 * Sends a notification to all devices of a specific user.
 * 
 * @param {string} userId - The unique ID of the user.
 * @param {object} payload - The notification payload (notification and/or data).
 */
exports.sendNotificationToUser = functions.https.onCall(async (data, context) => {
  const { userId, payload } = data;

  if (!userId || !payload) {
    throw new functions.https.HttpsError(
      'invalid-argument', 
      'The function must be called with a userId and a payload.'
    );
  }

  try {
    // 1. Fetch all active FCM tokens for the user from Firestore
    const tokensSnapshot = await db
      .collection('users')
      .doc(userId)
      .collection('fcmTokens')
      .get();

    if (tokensSnapshot.empty) {
      console.log(`No active FCM tokens found for user: ${userId}`);
      return { success: true, sentCount: 0 };
    }

    const tokens = tokensSnapshot.docs.map(doc => doc.id);
    console.log(`Attempting to send notification to ${tokens.length} devices for user: ${userId}`);

    // 2. Prepare the multicast message
    // payload should follow FCM message structure: { notification: { title, body }, data: { ... } }
    const message = {
      ...payload,
      tokens: tokens,
    };

    // 3. Send multicast notification
    const response = await admin.messaging().sendEachForMulticast(message);
    console.log(`Multicast results: ${response.successCount} success, ${response.failureCount} failure.`);

    // 4. Handle invalid/expired tokens (Cleanup phase)
    if (response.failureCount > 0) {
      const tokensToRemove = [];
      
      response.responses.forEach((resp, idx) => {
        if (!resp.success) {
          const errorCode = resp.error.code;
          // Clean up tokens that are no longer valid
          if (
            errorCode === 'messaging/invalid-registration-token' ||
            errorCode === 'messaging/registration-token-not-registered'
          ) {
            tokensToRemove.push(tokens[idx]);
          }
        }
      });

      if (tokensToRemove.length > 0) {
        console.log(`Cleaning up ${tokensToRemove.length} stale/invalid tokens for user: ${userId}`);
        const batch = db.batch();
        tokensToRemove.forEach(token => {
          const tokenRef = db
            .collection('users')
            .doc(userId)
            .collection('fcmTokens')
            .doc(token);
          batch.delete(tokenRef);
        });
        await batch.commit();
      }
    }

    return {
      success: true,
      sentCount: response.successCount,
      failureCount: response.failureCount,
    };
  } catch (error) {
    console.error('Error in sendNotificationToUser:', error);
    throw new functions.https.HttpsError('internal', error.message);
  }
});
