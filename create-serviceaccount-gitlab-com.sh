#!/bin/bash
set -eu

# Fail early if some vars aren't set
if [ -z "$GITLAB_ADMIN_TOKEN" ] ||
   [ -z "$GITLAB_GROUP_ID" ] ||
   [ -z "$DD_API_KEY" ] ||
   [ -z "$DD_APPLICATION_KEY" ] ||
   [ -z "$DD_SITE" ] ||
   [ -z "$ORG_NAME" ] ;
then exit 1; fi

# This script sets up a Service Account on a GitLab.com top-level group, grants it Reporter permission
# in this group, generates an access token for the account and registers it in Datadog.

# Create a service account owned by your GitLab.com top-level group
# https://docs.gitlab.com/ee/api/group_service_accounts.html#create-a-service-account-user
if ! SA_RESP=`curl -sS --fail-with-body -X POST "https://gitlab.com/api/v4/groups/$GITLAB_GROUP_ID/service_accounts" \
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

# Add the Service Account as a member of the GitLab.com group, with the Reporter role
# https://docs.gitlab.com/ee/api/members.html#add-a-member-to-a-group-or-project
if ! ADD_MEMBER_RESP=`curl -sS --fail-with-body -X POST "https://gitlab.com/api/v4/groups/$GITLAB_GROUP_ID/members" \
    -H "Content-Type: application/json" \
    -H "PRIVATE-TOKEN: $GITLAB_ADMIN_TOKEN" \
    -d "{
          \"user_id\": \"$SA_ID\",
          \"access_level\": 20
        }"` ; then
    echo "Failed to add the service account as member of the GitLab group $GITLAB_GROUP_ID: $ADD_MEMBER_RESP"
    exit 1
fi
echo "Successfully added $SA_NAME as Reported in GitLab group $GITLAB_GROUP_ID"

# Generate an access token for the service account. This access token will be sent to Datadog in the next step.
# https://docs.gitlab.com/ee/api/group_service_accounts.html#create-a-personal-access-token-for-a-service-account-user
if ! TOKEN_RESP=`curl -sS --fail-with-body -X POST "https://gitlab.com/api/v4/groups/$GITLAB_GROUP_ID/service_accounts/$SA_ID/personal_access_tokens" \
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

# Register the access token in Datadog. This will allow Datadog to call GitLab's API on behalf of the service account.
if ! DD_RESP=`curl -sS --fail-with-body -X POST https://$DD_SITE/api/v2/source-code/gitlab/tokens \
    -H "Content-Type: application/json" \
    -H "DD-API-KEY: $DD_API_KEY" \
    -H "DD-APPLICATION-KEY: $DD_APPLICATION_KEY" \
    -d "{
        \"data\": {
            \"id\": \"$(uuidgen)\",
            \"type\": \"source_code_gitlab_token_creation\",
            \"attributes\": {
                \"secret_token\": \"$(echo "$TOKEN_RESP" | jq -r '.token')\",
                \"hostname\": \"gitlab.com\",
                \"group_id\": $GITLAB_GROUP_ID
            }
        }
    }"` ; then
    echo "Failed to register service account token in Datadog: $DD_RESP"
    exit 1
fi

echo "Successfully registered token in Datadog."
exit 0
