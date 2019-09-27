#-------------------------------------------------------------------
# Depends on filesystem.sh; dotnet.sh; docker.sh; helm.sh; assert.sh
#-------------------------------------------------------------------

DEPLOY_SOLUTION_DIR_NOT_FOUND=9

# Param solution_dir
# Param dotnet_configuration
# Param tag (tag for both docker image and git)
# Param namespace
# Param artifacts_suffix (optional) applied to:
#       - tag
#       - helm release name
#       - values Name key (chartname + artifacts_suffix)
# Param deployed_releases_output (optional)
function deploy
{
	local solution_dir=$(realpath $1)
	local dotnet_configuration=$2
	local tag=$3
	local namespace=$4
	local artifacts_suffix=$5
	local deployed_releases_output=$6

	assert-not-empty ORGANIZATION
	directory-exists "$solution_dir" || return $DEPLOY_SOLUTION_DIR_NOT_FOUND
	assert-not-empty dotnet_configuration
	assert-not-empty tag
	assert-not-empty namespace

	tag="${tag}${artifacts_suffix}"	

	local output_releases_to_file=false

	if ! [ -z "$deployed_releases_output" ]
	then
		>$deployed_releases_output
		output_releases_to_file=true
	fi

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
		
		assert-success docker-build "$build_output_dir" "$docker_image_full_name_and_tag"

		rm -Rf "$build_output_dir"
		
		assert-success docker-push "$docker_image_full_name_and_tag"
		assert-success edit-helm-tag "$helm_dir" "$tag"
		
		helm-dry-run "$helm_dir" || return $?

		# Deploy phase
		local values_name="${chart_name}${artifacts_suffix}"
		local release_name="r-${chart_name}-${namespace}${artifacts_suffix}"

		helm-install-or-upgrade "$helm_dir" "$namespace" \
			"$release_name" "Name=$values_name" || return $?
		
		# Validation
		helm-deploy-validation "$namespace" "$release_name" || return $?


		if $output_releases_to_file
		then
			echo $release_name >> $deployed_releases_output
		fi		
	done
}