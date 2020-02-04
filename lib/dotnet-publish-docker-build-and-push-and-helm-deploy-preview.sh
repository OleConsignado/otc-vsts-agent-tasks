#-------------------------------------------------------------------------------
# Depends on filesystem.sh; dotnet.sh; docker.sh; helm.sh; assert.sh; console.sh
#-------------------------------------------------------------------------------

DEPLOY_BASE_DIR_NOT_FOUND=9
DEPLOY_SOLUTION_NOTHING_TO_PUBLISH=10

# Param base_dir - the base directory where will find for Kubernetes.Helm
# Param dotnet_configuration
# Param tag (tag for both docker image and git)
# Param namespace
# Param artifacts_suffix (optional) applied to:
#       - tag
#       - helm release name
#       - values Name key (chartname + artifacts_suffix)
# Output 1 - release_name's
function dotnet-publish-docker-build-and-push-and-helm-deploy-preview
{
	local base_dir=$(realpath $1)
	local dotnet_configuration=$2
	local tag=$3
	local namespace=$4
	local artifacts_suffix=$5

	assert-not-empty ORGANIZATION
	directory-exists "$base_dir" || return $DEPLOY_BASE_DIR_NOT_FOUND
	assert-not-empty dotnet_configuration
	assert-not-empty tag
	assert-not-empty namespace

	tag="${tag}${artifacts_suffix}"	

	for helm_dir in $(find "$base_dir" -name 'Kubernetes.Helm')
	do
		helm_dir=$(realpath "$helm_dir")
		
		local chart_name=$(discover-chart-name "$helm_dir")
		local build_output_dir=$(mktemp -d --suffix=-$chart_name)
		local project_dir=$(dirname "$helm_dir")
		local docker_image_full_name_and_tag="$ORGANIZATION/$chart_name:$tag"

		echo -n "Looking for dotnet core .csproj in order to publish it ... " >&2

		# TODO: Look for decouple dotnet-publish from deploy

		if ls $project_dir/*.csproj > /dev/null 2>&1 
		then
			echo "found!" >&2
			echo "As .csproj has found, publishing it to '$build_output_dir'" >&2
			assert-success dotnet-publish "$dotnet_configuration" "$project_dir" "$build_output_dir" >&2
		else
			echo "NOT found!" >&2
			echo -n "As .csproj has NOT found, looking for Dockerfile on '$project_dir' ... " >&2
			
			if [ -f "$project_dir/Dockerfile" ]
			then
				echo "found!" >&2
				echo "Copying artifacts from '$project_dir' to '$build_output_dir'" >&2
				rsync -rp --exclude=.git "$project_dir/." "$build_output_dir" >&2
			else
				echo "NOT found!" >&2
				red "Nothing to publish." >&2

				return $DEPLOY_SOLUTION_NOTHING_TO_PUBLISH
			fi
		fi
		
		# Create/replace buildid file with tag as content 
		echo -n "$tag" > "${build_output_dir}/buildid"
		
		assert-success docker-build "$build_output_dir" "$docker_image_full_name_and_tag" >&2

		rm -Rf "$build_output_dir" > /dev/null 2>&1
		
		assert-success docker-push "$docker_image_full_name_and_tag" >&2
		assert-success edit-helm-tag "$helm_dir" "$tag" >&2
		
		local release_name_file=$(mktemp -t "release_name-XXXXXXXX")
		local helm_deploy_success=false

		helm-deploy "$helm_dir" "$namespace" \
			"${chart_name}${artifacts_suffix}" > $release_name_file && helm_deploy_success=$?

		local release_name=$(cat $release_name_file)
		rm $release_name_file

		if [ -z "$release_name" ]
		then
			red "CRITICAL ERROR" >&2
			echo "Could not get release name, not that this is not a regular error." >&2
			echo "If you reading this message, helm/kubernetes apiserver could became unvailable "  >&2
			echo "or there is a BUG in this script." > &2
			exit 109
		fi

		if ! $helm_deploy_success
		then
			helm delete $release_name --purge >&2
		fi
		
		echo $release_name

		return $helm_deploy_success
	done
}
