#---------------------------------
# Depends on assert.sh; console.sh
#---------------------------------

# Workaround EACCES error
# https://docs.npmjs.com/resolving-eacces-permissions-errors-when-installing-packages-globally

function eacces-workaround-init
{
	NPM_PREFIX_DIR=$(mktemp -d -t npm-prefix-XXXXXXXX)		 
	chmod a+rwx $NPM_PREFIX_DIR
	npm config set prefix $NPM_PREFIX_DIR		 
	export npm_proj_directory=$npm_proj_directory:$NPM_PREFIX_DIR/bin
}

function eacces-workaround-end
{
	npm config rm prefix
	rm -Rf $NPM_PREFIX_DIR
}

# Update package.json version by adding buildid
function update-version
{
	local current_version=$(jq -r '.version' package.json)
	local version_pattern='^([0-9]+)\.([0-9]+)\.([0-9]+)(-.+)?$'
	if ! echo -n "$current_version" | egrep "$version_pattern" > /dev/null 2>&1
	then
		echo "Could not edit version in package.json, please check if it matches '$version_pattern'." >&2
		exit 1
	fi
	local new_version=$(echo $current_version | sed -E 's/'$version_pattern'/\1.\2.\3-v'$BUILD_BUILDID'/')
	jq -M '. + { "version": "'$new_version'" }' package.json > package.json.new
	rm package.json
	mv package.json.new package.json
	echo -n 'Updated packages.json version to: '
	jq -r '.version' package.json
}

NPM_PROJECT_DIR_NOT_FOUND=43

# Param project_dir
function npm-build
{
	local npm_proj_directory="$1"
	directory-exists "$npm_proj_directory" || return $NPM_PROJECT_DIR_NOT_FOUND
	local current_dir=$(pwd)
	cd $npm_proj_directory
	assert-success update-version
	assert-success eacces-workaround-init
	assert-success npm install
	assert-success npm run build
	assert-success eacces-workaround-end
	cd $current_dir
}

# Param project_dir
function npm-build-stage
{
	local npm_proj_directory="$1"
	directory-exists "$npm_proj_directory" || return $NPM_PROJECT_DIR_NOT_FOUND
	local current_dir=$(pwd)
	cd $npm_proj_directory
	assert-success update-version
	assert-success eacces-workaround-init
	assert-success npm install
	assert-success npm run build:staging
	assert-success eacces-workaround-end
	cd $current_dir
}
