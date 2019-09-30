#------------------------------
# Depends on assert.sh; vsts.sh
#------------------------------

# For state params, see https://docs.microsoft.com/en-us/rest/api/azure/devops/git/pull%20request%20statuses/create?view=azure-devops-rest-5.1#gitstatusstate

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
		"Sonarqube analysis $state" > /dev/null	
}

# Param pullrequest_id
# Param state 
# Para description (optional)
function pullrequest-set-size-status
{
	local pullrequest_id="$1"
	local state="$2"
	local description="$3"
	assert-not-empty pullrequest_id
	assert-not-empty state
	if [ -z "$description" ]
	then
		description="Size validation $state"
	fi
	vsts-pr-push-status \
		"$pullrequest_id" \
		"preconditions" \
		"pr_size" \
		"$state" \
		"https://arquitetura.oleconsignado.com.br/checklist-pull-request/#Tamanho-do-PR" \
		"$description" > /dev/null	
}


# Param pullrequest_id
# Param state
function pullrequest-set-deploy-status
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
		"Deployment preview $state" > /dev/null	
}