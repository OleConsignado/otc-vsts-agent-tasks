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
# Param current
function git-diff
{
	local base_branch="$1"
	local pullrequest_id="$2"
	assert-not-empty base_branch
	assert-not-empty pullrequest_id
	
	if ! git checkout $base_branch > /dev/null 2>&1
	then
		echo "Error checking out $base_branch" >&2
		return $GIT_DIFF_CHECKOUT_ERROR
	fi
	
	if ! git checkout pull/$pullrequest_id/merge > /dev/null 2>&1	
	then
		echo "Error checking out pull/$pullrequest_id/merge" >&2
		return $GIT_DIFF_CHECKOUT_ERROR
	fi

	git diff --numstat $base_branch
}

# Param base_branch
# Param pullrequest_id
# Param include_pattern (optional)
# Param exclude_pattern (optional)
# Return lines count
function count-changed-lines
{
	local base_branch="$1"
	local pullrequest_id="$2"
	local include_pattern="$3"
	local exclude_pattern="$4"
	assert-not-empty base_branch
	assert-not-empty pullrequest_id
	
	if [ -z "$include_pattern" ]
	then
		include_pattern=".*"
	fi

	if [ -z "$exclude_pattern" ]
	then
		exclude_pattern="I hope there is no file named like this."
	fi

	# 'git diff --numstat' output is like '10   1   Path/To/File'
	# replace leading '^'' with '^[0-9] +[0-9]' in order to make
	# include/exclude pattern match only the 'Path/To/File' part.
	include_pattern=$(echo "$include_pattern" | sed 's/^\^/^[0-9][ \t]+[0-9][ \t]+/')
	exclude_pattern=$(echo "$exclude_pattern" | sed 's/^\^/^[0-9][ \t]+[0-9][ \t]+/')

	# git checkout $base_branch > /dev/null 2>&1
	# git checkout pull/$pullrequest_id/merge > /dev/null 2>&1
	
	local git_diff_result_file=$(mktemp -t "pr-diff-${pullrequest_id}-XXXXXXXX")
	git-diff $base_branch $pullrequest_id | \
		egrep "$include_pattern" | \
		egrep -v "$exclude_pattern" > "$git_diff_result_file"
	echo "Counting lines ..." >&2
	cat "$git_diff_result_file" >&2
	local total_lines=$(cat "$git_diff_result_file" | awk '{n += $1+$2}; END{print n}')
	rm -f "$git_diff_result_file"
	echo "Sum (added + removed): $total_lines" >&2
	echo $total_lines
}
