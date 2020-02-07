#------------------------------------------------
# Depends on filesystem.sh; assert.sh; console.sh
#------------------------------------------------

# dotnet-publish
# Perform dotnet publish
# Usage: dotnet-publish Configuration project_dir output_dir

DOTNET_PUBLISH_OUTPUT_DIR_NOT_FOUND=68
DOTNET_PUBLISH_PROJECT_DIR_NOT_FOUND=69

# Param configuration
# Param project_dir
# Param output_dir
function dotnet-publish
{
	local configuration=$1
	local project_dir=$2
	local output_dir=$3	
	assert-not-empty configuration
	directory-exists "$project_dir" || return $DOTNET_PUBLISH_PROJECT_DIR_NOT_FOUND
	directory-exists "$output_dir" || return $DOTNET_PUBLISH_OUTPUT_DIR_NOT_FOUND
	echo "Running 'dotnet publish' for '$project_dir'"
	echo "Configuration: '$configuration' "
	echo "Output directory: '$build_output_dir'"
	dotnet publish --configuration $configuration --no-build --output="$output_dir" "$project_dir"
}
