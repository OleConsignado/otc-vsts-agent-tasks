#---------------------
# Depends on assert.sh
#---------------------

# Required environment variables:
# - BUILD_REPOSITORY_URI
# - VCS_TOKEN
# - BUILD_SOURCEBRANCHNAME
# - BUILD_SOURCEVERSION
# - BUILD_REQUESTEDFOR
# - BUILD_REQUESTEDFOREMAIL
function prepare-local-repo-for-changes
{
	assert-not-empty BUILD_REPOSITORY_URI
	assert-not-empty VCS_TOKEN
	assert-not-empty BUILD_SOURCEBRANCHNAME
	assert-not-empty BUILD_SOURCEVERSION
	assert-not-empty BUILD_REQUESTEDFOR
	assert-not-empty BUILD_REQUESTEDFOREMAIL
	local repo_uri_with_creedentials=$(echo $BUILD_REPOSITORY_URI | \
		sed -r "s/(^https?:\/\/)(.*)/\\1_:$VCS_TOKEN@\2/")
	if git remote | grep authrepo > /dev/null 2>&1 
	then
		git remote rm authrepo > /dev/null 2>&1
	fi
	git remote add authrepo $repo_uri_with_creedentials > /dev/null 2>&1 
	git checkout $BUILD_SOURCEBRANCHNAME
	git pull authrepo $BUILD_SOURCEBRANCHNAME
	local last_commit=$(git log --format="%H" -n 1)
	if [ "$last_commit" != "$BUILD_SOURCEVERSION" ]
	then
		echo "HEAD changed (expected $BUILD_SOURCEVERSION but $last_commit)"
		echo
		echo "******************************************************************************************"
		echo "* É comum acontecer esse erro quando o branch sofre mudanca durante o processo de build. *"
		echo "* Tente disparar um novo build. Caso o erro torne a acontecer, entre em contato com a    *"
		echo "* equipe de arquitetura (antes, certifique-se que nao  houveram novos commits no branch  *"
		echo "* durante a execucao do build).                                                          *"
		echo "******************************************************************************************"
		exit 10
	fi
	git config user.name "$BUILD_REQUESTEDFOR"
	git config user.email "$BUILD_REQUESTEDFOREMAIL"
}

TAG_AND_COMMIT_CHANGES_PUSH_ERROR=22

# Param tag
# Required environmento variables:
# - BUILD_SOURCEBRANCHNAME
# - BUILD_SOURCEVERSION
function commit-changes-and-tag
{
	local tag=$1
	assert-not-empty tag
	assert-not-empty BUILD_SOURCEBRANCHNAME
	assert-not-empty BUILD_SOURCEVERSION
	echo "Comminting changes to remote repository ..."
	git status
	git commit -m "Build $tag [skip ci]"
	git tag "$tag"
	if ! git push -u authrepo $BUILD_SOURCEBRANCHNAME --tags > gitpush.log 2>&1 # prevent expose creedential
	then
		echo "commit-changes-and-tag: git push error." >&2
		return $TAG_AND_COMMIT_CHANGES_PUSH_ERROR
	fi
	git remote rm authrepo > /dev/null 2>&1
	git checkout $BUILD_SOURCEVERSION > /dev/null 2>&1	
}

GIT_DIFF_CHECKOUT_ERROR=10


# Param base
# Param pullrequest_id
function git-diff-prepare
{
	local base_branch="$1"
	assert-not-empty base_branch
	local git_branch_result=$(mktemp -t git-diff-prepare-XXXXXX)
	git branch > $git_branch_result
	# detached state
	local current_branch=$(cat $git_branch_result | grep -Po '^\* \(HEAD detached at \K[A-Za-z0-9/]+(?=\))')
	if [ -z "$current_branch" ] # probably at a regular branch
	then
		current_branch=$(cat $git_branch_result | grep -Po '^\*\s*\K.*')
	fi
	rm -f $git_branch_result > /dev/null 2>&1
	if ! git checkout $base_branch > /dev/null 2>&1
	then
		echo "Error checking out $base_branch" >&2
		return $GIT_DIFF_CHECKOUT_ERROR
	fi
	
	if ! git checkout "$current_branch" > /dev/null 2>&1	
	then
		echo "Error checking out $current_branch" >&2
		return $GIT_DIFF_CHECKOUT_ERROR
	fi
}

# Param diff_shortstat_result_text
function diff-shortstat-result-text-to-json
{
	local diff_shortstat="$1"

	local insertions=$(echo $diff_shortstat | grep -Po '\K[0-9]+(?= insertions?)')
	local deletions=$(echo $diff_shortstat | grep -Po '\K[0-9]+(?= deletions?)')

	if [ -z "$insertions" ]
	then
		insertions=0
	fi
	if [ -z "$deletions" ]
	then
		deletions=0
	fi	

	echo '
	{ 
		"insertions": '$insertions',
		"deletions": '$deletions'
	}'	
}

function count-changed-lines-helper
{
	local base_branch="$1"
	local comments_and_blank_lines_pattern="$2"
	assert-not-empty base_branch
	assert-not-empty comments_and_blank_lines_pattern
	shift 2
	local diff_filter_args="$@"
	assert-success git-diff-prepare "$base_branch"
	local diff_shortstat=$(git diff --shortstat "$base_branch" -- $diff_filter_args)

	local diff_shortstat_json=$(diff-shortstat-result-text-to-json \
		"$diff_shortstat")

	local comments_and_blank_lines=$(git diff $base_branch -- $diff_filter_args \
		| egrep -c "$comments_and_blank_lines_pattern") 

	if [ -z "$comments_and_blank_lines" ]
	then
		comments_and_blank_lines=0
	fi
	echo $diff_shortstat_json | \
		jq -M ". + { comments_or_blank_lines: $comments_and_blank_lines }"
}

# Param base_branch
# Param comments_and_blank_lines_pattern
# Param diff_filter_args (--) ...
# Return lines changed report, example:
# {
#   "filtered": {
#     "insertions": 20,
#     "deletions": 16,
#     "comments_or_blank_lines": 4
#   },
#   "raw": {
#     "insertions": 28,
#     "deletions": 23,
#     "comments_or_blank_lines": 4
#   }
# }
function count-changed-lines
{
	local base_branch="$1"
	local comments_and_blank_lines_pattern="$2"
	assert-not-empty base_branch
	assert-not-empty comments_and_blank_lines_pattern
	shift 2
	local diff_filter_args="$@"	
	echo '
	{ 
		"filtered": '$(count-changed-lines-helper "$base_branch" \
			"$comments_and_blank_lines_pattern" $diff_filter_args)', 
		"raw": '$(count-changed-lines-helper "$base_branch" \
			"$comments_and_blank_lines_pattern")'
	}' | jq -M '.'
}

# Get the PR target branch name
function get-base-branch
{
	assert-not-empty SYSTEM_PULLREQUEST_TARGETBRANCH
	echo "$SYSTEM_PULLREQUEST_TARGETBRANCH" | sed 's/^refs\/heads\///'
}
