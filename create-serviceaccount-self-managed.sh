#!/bin/bash
set -eu

# This script sets up a Service Account on a GitLab.com top-level group, generates an
# access token for the account and registers it in Datadog.
# The service account should be added to the desired group / projects afterwards.

# Fail early if some vars aren't set
if [ -z "$GITLAB_ADMIN_TOKEN" ] ||
   [ -z "$GITLAB_HOSTNAME" ] ||
   [ -z "$DD_API_KEY" ] ||
   [ -z "$DD_APPLICATION_KEY" ] ||
   [ -z "$DD_SITE" ] ||
   [ -z "$ORG_NAME" ] ;
then exit 1; fi

# Create a service account on your GitLab instance
# https://docs.gitlab.com/ee/api/user_service_accounts.html#create-a-service-account-user
if ! SA_RESP=`curl -sS --fail-with-body -X POST "https://$GITLAB_HOSTNAME/api/v4/service_accounts" \
    -H "Content-Type: application/json" \
    -H "PRIVATE-TOKEN: $GITLAB_ADMIN_TOKEN" \
    -d "{
          \"name\": \"Datadog - $ORG_NAME\",
          \"username\": \"datadog-$(cat /dev/urandom | tr -dc 'a-z0-9A-Z' | fold -w 6 | head -n 1)\"
        }"` ; then
    echo "Failed to create service account: $SA_RESP"
    exit 1
fi

SA_ID=`echo "$SA_RESP" | jq -r '.id'`
SA_NAME=`echo "$SA_RESP" | jq -r '.name'`
echo "Successfully created service account $SA_NAME with ID $SA_ID."

# Generate an access token for the service account. This access token will be sent to Datadog in the next step.
if ! TOKEN_RESP=`curl -sS --fail-with-body -X POST "https://$GITLAB_HOSTNAME/api/v4/service_accounts/$SA_ID/personal_access_tokens" \
    -H "Content-Type: application/json" \
    -H "PRIVATE-TOKEN: $GITLAB_ADMIN_TOKEN" \
    -d "{
          \"name\": \"datadog-token-$(cat /dev/urandom | tr -dc 'a-z0-9A-Z' | fold -w 6 | head -n 1)\",
          \"scopes\": [\"api\",\"read_api\", \"read_user\", \"read_repository\", \"write_repository\"]
        }"` ; then
    echo "Failed to create access token for service account: $TOKEN_RESP"
    exit 1
fi
echo "Successfully generated token $(echo "$TOKEN_RESP" | jq -r '.name') with ID $(echo "$TOKEN_RESP" | jq -r '.id')"

# Register the access token in Datadog. This will allow Datadog to call your GitLab instance's API on behalf of
# the service account.
if ! DD_RESP=`curl -sS --fail-with-body -X POST https://$DD_SITE/api/v2/source-code/gitlab/tokens
    -H "Content-Type: application/json" \
    -H "DD-API-KEY: $DD_API_KEY" \
    -H "DD-APPLICATION-KEY: $DD_APPLICATION_KEY" \
    -d "{
        \"data\": {
            \"id\": \"$(uuidgen)\",
            \"type\": \"source_code_gitlab_token_creation\",
            \"attributes\": {
                \"secret_token\": \"$(echo "$TOKEN_RESP" | jq -r '.token')\",
                \"hostname\": \"$GITLAB_HOSTNAME\"
            }
        }
    }"` ; then
    echo "Failed to register service account token in Datadog: $DD_RESP"
    exit 1
fi

echo "Successfully registered token in Datadog."
exit 0
