#---------------------------------------------------------
# Depends on filesystem.sh; dotnet.sh; docker.sh; helm.sh
#---------------------------------------------------------

DEPLOY_MISSING_DOTNET_CONFIGURATION=8
DEPLOY_SOLUTION_DIR_NOT_FOUND=9
DEPLOY_MISSING_TAG=10
DEPLOY_MISSING_ORGANIZATION=11
DEPLOY_MISSING_NAMESPACE=13

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

	if [ -z "$ORGANIZATION" ]
	then
		echo "Missing environment variable ORGANIZATION." >&2
		return $DEPLOY_MISSING_ORGANIZATION
	fi

	directory-exists "$solution_dir" || return $DEPLOY_SOLUTION_DIR_NOT_FOUND

	if [ -z "$dotnet_configuration" ]
	then
		echo "Missing dotnet_configuration." >&2
		return $DEPLOY_MISSING_DOTNET_CONFIGURATION
	fi

	if [ -z "$tag" ]
	then
		echo "Missing tag." >&2
		return $DEPLOY_MISSING_TAG
	fi

	tag="${tag}${artifacts_suffix}"	

	if [ -z "$namespace" ]
	then
		echo "Missing namespace." >&2
		return $DEPLOY_MISSING_NAMESPACE
	fi

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

		dotnet-publish "$dotnet_configuration" "$project_dir" "$build_output_dir"	
		docker-build "$build_output_dir" "$docker_image_full_name_and_tag"

		rm -Rf "$build_output_dir"
		
		docker-push "$docker_image_full_name_and_tag"
		edit-helm-tag "$helm_dir" "$tag"
		helm-dry-run "$helm_dir" 

		# Deploy phase
		local values_name="${chart_name}${artifacts_suffix}"
		local release_name="r-${chart_name}-${namespace}${artifacts_suffix}"

		helm-install-or-upgrade "$helm_dir" "$namespace" "$release_name" "Name=$values_name"
		
		# Validation
		helm-deploy-validation "$namespace" "$release_name"


		if $output_releases_to_file
		then
			echo $release_name >> $deployed_releases_output
		fi		
	done
}