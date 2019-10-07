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

# Param base_branch
# Param ignore_lines_pattern
# Param diff_filter_args (--) ...
# Return lines count on output 1
# Information/Error message goes to output 2
function count-changed-lines
{
	local base_branch="$1"
	local ignore_lines_pattern="$2"
	assert-not-empty base_branch
	assert-not-empty ignore_lines_pattern
	shift 2
	local diff_filter_args="$@"
	assert-success git-diff-prepare "$base_branch"
	echo "count-changed-lines - filter: $diff_filter_args" >&2
	local diff_shortstat=$(git diff --shortstat "$base_branch" -- $diff_filter_args)
	echo "count-changed-lines - diff_shortstat: $diff_shortstat" >&2
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
	echo "count-changed-lines - insertions: $insertions" >&2
	echo "count-changed-lines - deletions: $deletions" >&2
	local total_lines=$(( $insertions + $deletions ))
	echo "count-changed-lines - total: $total_lines" >&2
	# ignored_lines is usefull for remove comment and empty lines. C# example: "^[+-]\s*(\/\/.*|)$" 
	local ignored_lines=$(git diff $base_branch -- $diff_filter_args | egrep -c "$ignore_lines_pattern") 
	if [ -z "$ignored_lines" ]
	then
		ignored_lines=0
	fi
	echo "count-changed-lines - ignored_lines: $ignored_lines" >&2
	echo $(( $total_lines - $ignored_lines ))
}

# Get the PR target branch name
function get-base-branch
{
	assert-not-empty SYSTEM_PULLREQUEST_TARGETBRANCH
	echo "$SYSTEM_PULLREQUEST_TARGETBRANCH" | sed 's/^refs\/heads\///'
}