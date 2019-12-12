#---------------------
# Depends on assert.sh
#---------------------

VSTS_REQUEST_FAIL=37

# Expected environment variables:
# - SYSTEM_COLLECTIONURI
# - VCS_TOKEN

# Param method
# Param path 
# Param payload (optional)
# Param content_type (optional, default: application/json)
function vsts-request
{
	local method="$1"
	local path="$2"
	local payload="$3"
	local content_type="$4"
	assert-not-empty SYSTEM_COLLECTIONURI
	assert-not-empty VCS_TOKEN
	assert-not-empty path
	local url="$(echo $SYSTEM_COLLECTIONURI | sed 's/\/$//')$path"
	local curl_output=$(mktemp -t "vsts-req-curl-XXXXXXXX")
	if [ -z "$content_type" ]
	then
		content_type="application/json"
	fi
	local return_code=0
	if ! curl --fail -s -u _:$VCS_TOKEN -d "$payload" -H "Content-Type: $content_type" \
		-X "$method" "$url" -o $curl_output
	then
		echo "vsts-request failed while trying to '$method' '$url'" >&2
		return_code=$VSTS_REQUEST_FAIL
	fi
	cat $curl_output
	rm -f $curl_output
	return $return_code
}

# Param pullrequest_id
function vsts-get-pullrequest
{
	local pullrequest_id="$1"
	assert-not-empty pullrequest_id
	vsts-request "GET" "/_apis/git/pullrequests/$pullrequest_id?api-version=5.1"
}

VSTS_GET_REPOID_BY_PRID_PR_NOT_FOUND=99

# Param pullrequest_id
function vsts-get-repoid-by-prid
{
	local pullrequest_id="$1"
	assert-not-empty pullrequest_id
	local repository_id=$(vsts-get-pullrequest "$pullrequest_id" | jq -r '.repository.id')
	if [ "$repository_id" = "null" ]
	then
		echo "Could not found 'repository_id' for 'pullrequest_id' = '$pullrequest_id'." >&2
		return $VSTS_GET_REPOID_BY_PRID_PR_NOT_FOUND
	fi
	echo $repository_id
}

# vsts-comment-pull-request 
# Usage: vsts-comment-pull-request comment_text

# Param pullrequest_id
# Param comment_text
# Output comment_id
function vsts-comment-pull-request
{
	local pullrequest_id=$1
	local comment_text="$2"
	assert-not-empty pullrequest_id
	assert-not-empty comment_text
	local repository_id=$(vsts-get-repoid-by-prid "$pullrequest_id")
  	vsts-request "POST" \
  		"/_apis/git/repositories/$repository_id/pullrequests/$pullrequest_id/threads?api-version=5.1" \
  		"{ \"comments\": [ { \"content\": \"$comment_text\" } ] }" | jq -M '.id'
}

# vsts-pull-request-comment-change-status
# Usage: vsts-pull-request-comment-change-status comment_id comment_status

# Param pullrequest_id
# Param comment_id
# Param comment_status (int)
function vsts-pull-request-comment-change-status
{
	local pullrequest_id=$1
	local comment_id=$2
	local comment_status=$3
	assert-not-empty pullrequest_id
	assert-not-empty comment_id
	assert-not-empty comment_status
	local repository_id=$(vsts-get-repoid-by-prid "$pullrequest_id")
	vsts-request "PATCH" \
		"/_apis/git/repositories/$repository_id/pullrequests/$pullrequest_id/threads/$comment_id?api-version=5.1" \
		"{ \"status\": $comment_status }" > /dev/null
}

# Param pullrequest_id
# Param context_genre
# Param context_name
# Param state
# Param target_url (optional)
# Param description (optional)
# Reference: https://docs.microsoft.com/en-us/rest/api/azure/devops/git/pull%20request%20statuses/create?view=azure-devops-rest-5.1
function vsts-pr-push-status
{
	local pullrequest_id="$1"
	local context_genre="$2"
	local context_name="$3"
	local state="$4"
	local target_url="$5"
	local description="$6"
	assert-not-empty pullrequest_id
	assert-not-empty context_genre
	assert-not-empty context_name
	assert-not-empty state
	local repository_id=$(vsts-get-repoid-by-prid "$pullrequest_id")
	local payload="\
		{ \
			\"context\": { \
				\"genre\": \"$context_genre\", \
				\"name\": \"$context_name\" \
			}, \
			\"state\": \"$state\", \
			\"targetUrl\": \"$target_url\", \
			\"description\": \"$description\" \
		}"
	vsts-request "POST" \
		"/_apis/git/repositories/$repository_id/pullRequests/$pullrequest_id/statuses?api-version=5.1-preview.1" \
		"$payload"
}

# Param pullrequest_id
# Param payload
function vsts-pr-update-properties
{
	local pullrequest_id="$1"
	local payload="$2"
	assert-not-empty pullrequest_id
	assert-not-empty payload
	local repository_id=$(vsts-get-repoid-by-prid "$pullrequest_id")
	vsts-request "PATCH" \
		"/_apis/git/repositories/$repository_id/pullRequests/$pullrequest_id/properties?api-version=5.1-preview.1" \
		"$payload" \
		"application/json-patch+json"
}