
# Required environment variables:
# - BUILD_REPOSITORY_URI
# - VCS_TOKEN
# - BUILD_SOURCEBRANCHNAME
# - BUILD_SOURCEVERSION
# - BUILD_REQUESTEDFOR
# - BUILD_REQUESTEDFOREMAIL
function prepare-local-repo-for-changes
{
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

TAG_AND_COMMIT_CHANGES_MISS_TAG=21
TAG_AND_COMMIT_CHANGES_PUSH_ERROR=22

# Param tag
# Required environmento variables:
# - BUILD_SOURCEBRANCHNAME
# - BUILD_SOURCEVERSION
function commit-changes-and-tag
{
	local tag=$1

	if [ -z "$tag" ]
	then
		echo "commit-changes-and-tag: missing tag" >&2
		return $TAG_AND_COMMIT_CHANGES_MISS_TAG
	fi

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
