#------------------------------
# Depends on assert.sh; vsts.sh
#------------------------------

# Required variable: SYSTEM_WORKFOLDER
assert-not-empty SYSTEM_WORKFOLDER

# For state params, see https://docs.microsoft.com/en-us/rest/api/azure/devops/git/pull%20request%20statuses/create?view=azure-devops-rest-5.1#gitstatusstate

# Param state
function friendly-state
{
	local state="$1"
	assert-not-empty state
	if [ "$state" = "notSet" ]
	then
		state="queued"
	elif [ "$state" = "pending" ]
	then
		state="in progress"
	fi
	echo "$state"
}

QUALITY_STATUS_STATE_FILE="$SYSTEM_WORKFOLDER/quality_status_state"

# Param pullrequest_id
# Param state 
# Param report_url (optional)
function pullrequest-set-quality-gate-status
{
	local pullrequest_id="$1"
	local state="$2"
	local report_url="$3"
	assert-not-empty pullrequest_id
	assert-not-empty state
	assert-success vsts-pr-push-status \
		"$pullrequest_id" \
		"analysis" \
		"sonarqube" \
		"$state" \
		"$report_url" \
		"Sonarqube analysis $(friendly-state "$state")" > /dev/null	

	echo "$state" > "$QUALITY_STATUS_STATE_FILE"
}

SIZE_STATUS_STATE_FILE="$SYSTEM_WORKFOLDER/size_status_state"

# Param pullrequest_id
# Param state 
# Param lines_changed (optional)
# Param lines_threshold (optional)
function pullrequest-set-size-status
{
	local pullrequest_id="$1"
	local state="$2"
	local lines_changed="$3"
	local lines_threshold="$4"
	assert-not-empty pullrequest_id
	assert-not-empty state
	local description="Size validation $(friendly-state "$state")"

	if ! [ -z "$lines_changed" ]
	then
		description="$description (actual size $lines_changed, threshold $lines_threshold)"
	fi
	
	vsts-pr-push-status \
		"$pullrequest_id" \
		"preconditions" \
		"pr_size" \
		"$state" \
		"https://arquitetura.oleconsignado.com.br/validacao-de-tamanho-de-um-pull-request/" \
		"$description" > /dev/null	

	echo "$state" > "$SIZE_STATUS_STATE_FILE"
}

DEPLOY_PREVIEW_STATUS_STATE_FILE="$SYSTEM_WORKFOLDER/deploy_preview_status_state"

# Param pullrequest_id
# Param state
function pullrequest-set-deploy-preview-status
{
	local pullrequest_id="$1"
	local state="$2"
	assert-not-empty pullrequest_id
	assert-not-empty state
	vsts-pr-push-status \
		"$pullrequest_id" \
		"ci" \
		"deploy_preview" \
		"$state" \
		"" \
		"Deployment preview $(friendly-state "$state")" > /dev/null	

	echo "$state" > "$DEPLOY_PREVIEW_STATUS_STATE_FILE"
}

# Param pullrequest_id
function reset-pr-statuses
{
	local pullrequest_id="$1"
	assert-not-empty pullrequest_id
	pullrequest-set-size-status "$pullrequest_id" "notSet"
	pullrequest-set-quality-gate-status "$pullrequest_id" "notSet"
	pullrequest-set-deploy-preview-status "$pullrequest_id" "notSet"
}

# Param filename
function should-set-status-as-failed
{
	local filename="$1"
	egrep -v "^succeeded|failed$" "$filename" > /dev/null 2>&1 \
		&& return 0
	return 1
}

# Param pullrequest_id
function finalize-pr-statuses
{
	local pullrequest_id="$1"
	assert-not-empty pullrequest_id
	should-set-status-as-failed "$DEPLOY_PREVIEW_STATUS_STATE_FILE" && \
		pullrequest-set-deploy-preview-status "$pullrequest_id" "error"
	should-set-status-as-failed "$SIZE_STATUS_STATE_FILE" && \
		pullrequest-set-size-status "$pullrequest_id" "error"
	should-set-status-as-failed "$QUALITY_STATUS_STATE_FILE" && \
		pullrequest-set-quality-gate-status "$pullrequest_id" "error"
}