#-----------------------------
# Depends on assert.sh; git.sh
#-----------------------------

function azure-pipelines-yaml-protection
{
	assert-not-empty SYSTEM_PULLREQUEST_PULLREQUESTID
	local pullrequest_id=$SYSTEM_PULLREQUEST_PULLREQUESTID
	git-diff-prepare "$(get-base-branch)"
	if git diff --numstat "$(get-base-branch)" | \
		egrep '^[0-9]+\s+[0-9]+\s+azure-pipelines\.yml$' > /dev/null 2>&1
	then
		red "******************************************************************"
		red "* azure-pipelines.yml should not be modified in topic branches.  *"
		red "******************************************************************"
		exit 47 # Critical, pipeline must not procceed.
	fi
}
