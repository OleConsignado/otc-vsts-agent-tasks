# params
# $1 = COMMENT_TEXT
# Return coment id (via echo)
function comment-pull-request
{
	COMMENT_TEXT="$1"

	if [ -z "$COMMENT_TEXT" ]
	then
		echo "$0: missing COMMENT_TEXT"
		return 1
	fi

  	URL="${SYSTEM_TEAMFOUNDATIONCOLLECTIONURI}${SYSTEM_TEAMPROJECT}/_apis/git/repositories/$BUILD_REPOSITORY_ID/pullRequests/$SYSTEM_PULLREQUEST_PULLREQUESTID/threads?api-version=5.0"
  	PAYLOAD="{ \"comments\": [ { \"content\": \"$COMMENT_TEXT\" } ] }"
 
  	curl -s -u _:$VCS_TOKEN -d "$PAYLOAD" -H "Content-Type: application/json" -X POST $URL | jq -M '.id'
}

# params
# $1 = COMMENT_ID
# $2 = new status (int)
function pull-request-comment-change-status
{
	COMMENT_ID=$1
	COMMENT_STATUS=$2

	if [ -z "$COMMENT_ID" ]
	then
		echo "$0: missing COMMENT_ID"
		return 1
	fi

	if [ -z "$COMMENT_STATUS" ]
	then
		echo "$0: missing COMMENT_STATUS"
		return 1
	fi	

	URL="${SYSTEM_TEAMFOUNDATIONCOLLECTIONURI}${SYSTEM_TEAMPROJECT}/_apis/git/repositories/$BUILD_REPOSITORY_ID/pullRequests/$SYSTEM_PULLREQUEST_PULLREQUESTID/threads/$COMMENT_ID?api-version=5.0"
  	PAYLOAD="{ \"status\": $COMMENT_STATUS }"
 
  	curl -s -u _:$VCS_TOKEN -d "$PAYLOAD" -H "Content-Type: application/json" -X PATCH $URL > /dev/null
}