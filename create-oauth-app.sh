#!/bin/bash
set -eu

# This script creates an OAuth2 application on your GitLab instance, and sends its credentials to Datadog.
# This allows Datadog to let your users authorize access to GitLab resources on their behalf.

# Fail early if some vars aren't set
if [ -z "$GITLAB_ADMIN_TOKEN" ] ||
   [ -z "$GITLAB_HOSTNAME" ] ||
   [ -z "$DD_API_KEY" ] ||
   [ -z "$DD_APPLICATION_KEY" ] ||
   [ -z "$DD_DOMAIN" ] ||
   [ -z "$DD_SITE" ] ;
then exit 1; fi

if [ "$GITLAB_HOSTNAME" == "gitlab.com" ] ; then
  echo "Creating an OAuth application is not required for gitlab.com groups. You can ignore this step."
  exit 0
fi

# Make a request to GitLab's Applications API to create the new app
# https://docs.gitlab.com/ee/api/applications.html#create-an-application
if ! APP_RESP=`curl -sS --fail-with-body -X POST https://$GITLAB_HOSTNAME/api/v4/applications \
  -H "Content-Type: application/json" \
  -H "PRIVATE-TOKEN: $GITLAB_ADMIN_TOKEN" \
  -d "{
    \"name\": \"Datadog\",
    \"redirect_uri\": \"https://$DD_DOMAIN/api/ui/integration/gitlab/oauth/callback\",
    \"scopes\": \"api read_api read_repository write_repository\"
  }"` ; then
    echo "Failed to create OAuth application in GitLab: $APP_RESP"
    exit 1
fi

CLIENT_ID=`echo "$APP_RESP" | jq -r '.application_id'`
CLIENT_SECRET=`echo "$APP_RESP" | jq -r '.secret'`
APP_NAME=`echo "$APP_RESP" | jq -r '.application_name'`
echo "Successfully created OAuth app $APP_NAME with ID $CLIENT_ID"

# Register the app in Datadog's integration endpoint
if ! DD_RESP=`curl -sS --fail-with-body -X POST https://$DD_SITE/api/v2/source-code/gitlab/oauth-apps \
  -H "Content-Type: application/json" \
  -H "DD-API-KEY: $DD_API_KEY" \
  -H "DD-APPLICATION-KEY: $DD_APPLICATION_KEY" \
  -d "{
	\"data\": {
		\"id\": \"$(uuidgen)\",
		\"type\": \"source_code_gitlab_private_oauth_app_creation\",
		\"attributes\": {
			\"name\": \"$APP_NAME\",
			\"hostname\": \"$GITLAB_HOSTNAME\",
			\"client_id\": \"$CLIENT_ID\",
			\"client_secret\": \"$CLIENT_SECRET\",
			\"scopes\": [\"api\", \"read_api\", \"read_repository\", \"write_repository\"]
		}
	}
}"` ; then
    echo "Failed to register application in Datadog: $DD_RESP"
    exit 1
fi

echo "Successfully registered application in Datadog."
exit 0
