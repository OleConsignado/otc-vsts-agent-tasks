# Expected environment variables:
# - SYSTEM_COLLECTIONURI
# - VCS_TOKEN

VSTS_POST_JSON_MISS_PATH=5
VSTS_POST_JSON_MISS_REQUIRED_ENV=6

# Param method
# Param path 
# Param payload (optional)
function vsts-request
{
	local method="$1"
	local path="$2"
	local payload="$3"

	if [ -z "$SYSTEM_COLLECTIONURI" ] || \
		[ -z "$VCS_TOKEN" ]
	then
		echo "Required environment variables (SYSTEM_COLLECTIONURI and/or VCS_TOKEN) are missing, check vsts.sh." >&2

		return $VSTS_POST_JSON_MISS_REQUIRED_ENV
	fi

	if [ -z "$path" ]
	then
		echo "vsts-request: path is missing." >&2

		return $VSTS_POST_JSON_MISS_PATH
	fi

	local url="$(echo $SYSTEM_COLLECTIONURI | sed 's/\/$//')$path"

	curl -s -u _:$VCS_TOKEN -d "$payload" -H "Content-Type: application/json" -X "$method" "$url"
}

VSTS_GET_PR_MISS_PR_ID=87

# Param pullrequest_id
function vsts-get-pullrequest
{
	local pullrequest_id="$1"

	if [ -z "$pullrequest_id" ]
	then
		echo "vsts-get-pullrequest: missing pullrequest_id" >&2

		return $VSTS_GET_PR_MISS_PR_ID
	fi

	vsts-request "GET" "/_apis/git/pullrequests/$pullrequest_id?api-version=5.1"
}

VSTS_GET_REPOID_BY_PRID_MISS_PR_ID=98
VSTS_GET_REPOID_BY_PRID_PR_NOT_FOUND=99

# Param pullrequest_id
function vsts-get-repoid-by-prid
{
	local pullrequest_id="$1"
	
	if [ -z "$pullrequest_id" ]
	then
		echo "vsts-get-repoid-by-prid: missing pullrequest_id" >&2

		return $VSTS_GET_REPOID_BY_PRID_MISS_PR_ID
	fi

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

VSTS_COMMENT_PR_MISS_COMMENT_TEXT=35
VSTS_COMMENT_PR_MISS_REPOSITORY_ID=36
VSTS_COMMENT_PR_MISS_PR_ID=37

# Param pullrequest_id
# Param comment_text
# Output comment_id
function vsts-comment-pull-request
{
	local pullrequest_id=$1
	local comment_text="$2"

	if [ -z "$pullrequest_id" ]
	then
		echo "vsts-comment-pull-request: missing pullrequest_id" >&2

		return $VSTS_COMMENT_PR_MISS_PR_ID
	fi

	if [ -z "$comment_text" ]
	then
		echo "vsts-comment-pull-request: missing comment_text" >&2

		return $VSTS_COMMENT_PR_MISS_COMMENT_TEXT
	fi
 
	local repository_id=$(vsts-get-repoid-by-prid "$pullrequest_id")

  	vsts-request "POST" \
  		"/_apis/git/repositories/$repository_id/pullrequests/$pullrequest_id/threads?api-version=5.1" \
  		"{ \"comments\": [ { \"content\": \"$comment_text\" } ] }" | jq -M '.id'
}

# vsts-pull-request-comment-change-status
# Usage: vsts-pull-request-comment-change-status comment_id comment_status

VSTS_PR_COMMENT_CHANGE_STATUS_MISS_COMMENT_ID=36
VSTS_PR_COMMENT_CHANGE_STATUS_MISS_COMMENT_STATUS=37
VSTS_PR_COMMENT_CHANGE_STATUS_MISS_REPOSITORY_ID=38
VSTS_PR_COMMENT_CHANGE_STATUS_MISS_PR_ID=39

# Param pullrequest_id
# Param comment_id
# Param comment_status (int)
function vsts-pull-request-comment-change-status
{
	local pullrequest_id=$1
	local comment_id=$2
	local comment_status=$3

	if [ -z "$pullrequest_id" ]
	then
		echo "vsts-pull-request-comment-change-status: missing pullrequest_id" >&2

		return $VSTS_PR_COMMENT_CHANGE_STATUS_MISS_PR_ID
	fi

	if [ -z "$comment_id" ]
	then
		echo "vsts-pull-request-comment-change-status: missing comment_id" >&2

		return $VSTS_PR_COMMENT_CHANGE_STATUS_MISS_COMMENT_ID
	fi

	if [ -z "$comment_status" ]
	then
		echo "vsts-pull-request-comment-change-status: missing comment_status" >&2

		return $VSTS_PR_COMMENT_CHANGE_STATUS_MISS_COMMENT_STATUS
	fi	

	local repository_id=$(vsts-get-repoid-by-prid "$pullrequest_id")
 
	vsts-request "PATCH" \
		"/_apis/git/repositories/$repository_id/pullrequests/$pullrequest_id/threads/$comment_id?api-version=5.1" \
		"{ \"status\": $comment_status }" > /dev/null
}
