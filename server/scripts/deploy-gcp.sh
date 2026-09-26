#!/usr/bin/env bash
# Deploys the SpaceNotes Live room server to Cloud Run in spacenotes-notebook,
# in Mumbai (asia-south1), so rooms and their data stay in India.
#
# NOT YET RUN. It creates billed resources, so it waits for the owner's
# go-ahead. Before the first run:
#   1. LiveKit: create a LiveKit Cloud project pinned to the India region (or
#      self-host, see docs/research), then store its keys:
#        printf %s "$KEY"    | gcloud secrets create livekit-api-key    --data-file=- --project=spacenotes-notebook
#        printf %s "$SECRET" | gcloud secrets create livekit-api-secret --data-file=- --project=spacenotes-notebook
#      and set LIVEKIT_URL below.
#   2. Firebase: register a Web app in the spacenotes-notebook Firebase
#      project and put its apiKey in FIREBASE_WEB_API_KEY below. Give that key
#      an HTTP-referrer restriction to this service's URL. (The iOS key is
#      restricted to identitytoolkit/securetoken and to the iOS app.)
#
# Run from the repository root:  bash server/scripts/deploy-gcp.sh
# It never touches gemini-proxy or teachdraw-server.
set -euo pipefail

G="${GCLOUD:-$HOME/google-cloud-sdk/bin/gcloud}"
P=spacenotes-notebook
R=asia-south1
SERVICE=spacenotes-live
SA="spacenotes-live@$P.iam.gserviceaccount.com"
BUCKET="$P-live-rooms"
LIVEKIT_URL="${LIVEKIT_URL:?set LIVEKIT_URL to the LiveKit project URL (wss://…)}"
FIREBASE_WEB_API_KEY="${FIREBASE_WEB_API_KEY:?set FIREBASE_WEB_API_KEY to the Firebase Web app key}"

# 1. A service account that can reach the rooms bucket and two secrets, and nothing else.
if ! "$G" iam service-accounts describe "$SA" --project=$P >/dev/null 2>&1; then
  "$G" iam service-accounts create spacenotes-live --project=$P --display-name="SpaceNotes Live room server"
fi
if ! "$G" storage buckets describe "gs://$BUCKET" --project=$P >/dev/null 2>&1; then
  "$G" storage buckets create "gs://$BUCKET" --project=$P --location=$R --uniform-bucket-level-access --public-access-prevention
  # Rooms are study sessions, not archives: delete them after 30 days.
  printf '{"rule":[{"action":{"type":"Delete"},"condition":{"age":30}}]}' > /tmp/live-lifecycle.json
  "$G" storage buckets update "gs://$BUCKET" --lifecycle-file=/tmp/live-lifecycle.json
fi
"$G" storage buckets add-iam-policy-binding "gs://$BUCKET" --member="serviceAccount:$SA" --role=roles/storage.objectAdmin --format=none
for secret in livekit-api-key livekit-api-secret; do
  "$G" secrets add-iam-policy-binding $secret --project=$P --member="serviceAccount:$SA" --role=roles/secretmanager.secretAccessor --format=none
done

# 2. The service. One instance: a room lives in one process's memory, so
#    everyone in a room must reach the same instance. That holds about 1,000
#    connections (~160 six-person rooms); beyond it, rooms need Redis fan-out
#    (docs/research). WebSockets are cut at the 60-minute timeout; clients
#    reconnect and resume on their own.
"$G" run deploy $SERVICE --source=. --region=$R --project=$P \
  --service-account="$SA" --allow-unauthenticated \
  --set-env-vars="FIREBASE_PROJECT_ID=$P,FIREBASE_WEB_API_KEY=$FIREBASE_WEB_API_KEY,LIVE_BUCKET=$BUCKET,LIVEKIT_URL=$LIVEKIT_URL" \
  --set-secrets="LIVEKIT_API_KEY=livekit-api-key:latest,LIVEKIT_API_SECRET=livekit-api-secret:latest" \
  --min-instances=0 --max-instances=1 --concurrency=1000 --timeout=3600 \
  --session-affinity --memory=512Mi --cpu=1 --quiet

echo "Service: $("$G" run services describe $SERVICE --region=$R --project=$P --format='value(status.url)')"
