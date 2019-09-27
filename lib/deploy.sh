#-------------------------------------------------------------------------------
# Depends on filesystem.sh; dotnet.sh; docker.sh; helm.sh; assert.sh; console.sh
#-------------------------------------------------------------------------------

DEPLOY_SOLUTION_DIR_NOT_FOUND=9

# Param solution_dir
# Param dotnet_configuration
# Param tag (tag for both docker image and git)
# Param namespace
# Param artifacts_suffix (optional) applied to:
#       - tag
#       - helm release name
#       - values Name key (chartname + artifacts_suffix)
# Output 1 - release_name's
function deploy
{
	local solution_dir=$(realpath $1)
	local dotnet_configuration=$2
	local tag=$3
	local namespace=$4
	local artifacts_suffix=$5

	assert-not-empty ORGANIZATION
	directory-exists "$solution_dir" || return $DEPLOY_SOLUTION_DIR_NOT_FOUND
	assert-not-empty dotnet_configuration
	assert-not-empty tag
	assert-not-empty namespace

	tag="${tag}${artifacts_suffix}"	

	for helm_dir in $(find "$solution_dir" -name 'Kubernetes.Helm')
	do
		helm_dir=$(realpath "$helm_dir")
		
		local chart_name=$(discover-chart-name "$helm_dir")
		local build_output_dir=$(mktemp -d --suffix=-$chart_name)
		local project_dir=$(dirname "$helm_dir")
		local docker_image_full_name_and_tag="$ORGANIZATION/$chart_name:$tag"

		assert-success dotnet-publish "$dotnet_configuration" "$project_dir" "$build_output_dir"	
		
		# Create/replace version file with tag as content 
		echo "$tag" > "${build_output_dir}/version"
		
		assert-success docker-build "$build_output_dir" "$docker_image_full_name_and_tag" >&2

		rm -Rf "$build_output_dir" > /dev/null 2>&1
		
		assert-success docker-push "$docker_image_full_name_and_tag" >&2
		assert-success edit-helm-tag "$helm_dir" "$tag" >&2
		
		helm-dry-run "$helm_dir" >&2 || return $?

		# Deploy phase
		local values_name="${chart_name}${artifacts_suffix}"
		local release_name="r-${chart_name}-${namespace}${artifacts_suffix}"

		helm-install-or-upgrade "$helm_dir" "$namespace" \
			"$release_name" "Name=$values_name" >&2 || return $?
		
		# Validation
		helm-deploy-validation "$namespace" "$release_name" >&2 || return $?

		echo $release_name
	done
}