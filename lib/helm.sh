#--------------------------
# Depends on filesystem.sh
#--------------------------

# discover-chart-name 
# Get chart name for the given helm chart directory.

DISCOVER_DISCOVER_CHART_NAME_ERROR_HELM_DIR=4
DISCOVER_CHART_NAME_ERROR=5

# Param helm_dir
# Return chart_name
function discover-chart-name 
{
	local helm_dir=$1

	directory-exists "$helm_dir" || return $DISCOVER_DISCOVER_CHART_NAME_ERROR_HELM_DIR

	local chart_yaml_filename="$helm_dir/Chart.yaml"
	local chart_name=$(egrep '^name: ' "$chart_yaml_filename" | awk '{ print $2 }')	
	
	if [ -z "$chart_name" ]
	then
		echo "Could not find the chartname, check file '$chart_yaml_filename'." >&2
		return $DISCOVER_CHART_NAME_ERROR
	fi

	echo $chart_name
}

# edit-helm-tag
# Usage: edit-helm-tag helm_dir new_tag

EDIT_HELM_TAG_HELM_DIR_NOT_FOUND=88
EDIT_HELM_TAG_MISS_TAG=87
EDIT_HELM_TAG_VALUES_NOT_FOUND=89

# Param helm_dir
# Param tag
function edit-helm-tag
{
	helm_dir=$1
	tag=$2

	directory-exists "$helm_dir" || return $EDIT_HELM_TAG_HELM_DIR_NOT_FOUND

	if [ -z "$tag" ]
	then
		echo "Missing tag." >&2
		return $EDIT_HELM_TAG_MISS_TAG
	fi

	values_path="$helm_dir/values.yaml"

	if ! [ -f "$values_path" ]
	then
		echo "File '$values_path' not found." >&2
		return $EDIT_HELM_TAG_VALUES_NOT_FOUND
	fi

	sed -ri "s/^  tag: .*/  tag: $tag/" "$values_path"

	git add "$values_path"
}

# helm-dry-run
# Usage: helm-dry-run helm_dir

HELM_DRY_RUN_FAILED=45
HELM_DRY_RUN_HELM_DIR_NOT_FOUND=46

# Param helm_dir
function helm-dry-run
{
	helm_dir="$1"

	directory-exists "$helm_dir" || return $HELM_DRY_RUN_HELM_DIR_NOT_FOUND

	echo -n "Performing helm dry-run... "

	if ! helm install "$helm_dir" --dry-run > /dev/null 2>&1
	then
		echo "FAILED!"
		echo "helm dry-run failed, performing helm dry-run with --debug in order to expose errors." >&2
		! helm install "$helm_dir" --dry-run --debug
		return $HELM_DRY_RUN_FAILED
	fi

	echo "Passed!"
}

# helm-release-exists
# Usage: helm-release-exists namespace helm_release_name

HELM_RELEASE_EXISTS_MISS_REL_NAME=58
HELM_RELEASE_EXISTS_MISS_NAMESPACE=59
HELM_RELEASE_EXISTS_NOT_EXISTS=60

# Param namespace
# Param helm_release_name
function helm-release-exists
{
	local namespace=$1
	local helm_release_name=$2

	if [ -z "$namespace" ]
	then
		echo "Missing namespace." >&2
		return $HELM_RELEASE_EXISTS_MISS_NAMESPACE
	fi

	if [ -z "$helm_release_name" ]
	then
		echo "Missing helm_release_name." >&2
		return $HELM_RELEASE_EXISTS_MISS_REL_NAME
	fi

	if ! helm --namespace="$namespace" ls -q | egrep "^$helm_release_name\$" > /dev/null
	then
		return $HELM_RELEASE_EXISTS_NOT_EXISTS
	fi
}

# helm-install-or-upgrade
# Usage: helm-install-or-upgrade helm_dir namespace helm_release_name item1=va1 item2=val2 ....

HELM_INSTALL_OR_UPGRADE_INVALID_CUSTOM_VALUE=55
HELM_INSTALL_OR_UPGRADE_MISS_NAMESPACE=56
HELM_INSTALL_OR_UPGRADE_MISS_REL_NAME=57
HELM_INSTALL_OR_UPGRADE_INST_FAILED=58
HELM_INSTALL_OR_UPGRADE_HELM_DIR_NOT_FOUND=59
HELM_INSTALL_OR_UPGRADE_UPGR_FAILED=60

# Param helm_dir
# Param namespace
# Param helm_release_name
# Param helm_values - ex: item1=val1 item2=val2
function helm-install-or-upgrade
{
	local helm_dir=$1
	local namespace=$2
	local helm_release_name=$3
	shift 3
	local helm_custom_values=$@

	directory-exists "$helm_dir" || return $HELM_INSTALL_OR_UPGRADE_HELM_DIR_NOT_FOUND

	if [ -z "$namespace" ]
	then
		echo "Missing namespace." >&2
		return $HELM_INSTALL_OR_UPGRADE_MISS_NAMESPACE
	fi

	if [ -z "$helm_release_name" ]
	then
		echo "Missing helm_release_name." >&2
		return $HELM_INSTALL_OR_UPGRADE_MISS_REL_NAME
	fi	

	local helm_set_arg=''

	for item in $helm_custom_values
	do 
		if ! echo "$item" | egrep '^[a-zA-Z_0-9-]+=[a-zA-Z_0-9-]+$' > /dev/null
		then
			echo "Argument '$item' is invalid for helm_custom_values" >&2
			return $HELM_INSTALL_OR_UPGRADE_INVALID_CUSTOM_VALUE
		fi
		helm_set_arg="$helm_set_arg --set $item"
	done

	if helm-release-exists "$namespace" "$helm_release_name"
	then
	    # Release already exists, will upgrade
	    echo "Upgrading helm $helm_release_name ..."
	    if ! helm --namespace="$namespace" upgrade "$helm_release_name" $helm_set_arg "$helm_dir"
	    then
	    	echo "helm upgrade failed." >&2

	    	return $HELM_INSTALL_OR_UPGRADE_UPGR_FAILED
	    fi
	else
		# New release
		echo "Installing helm $helm_release_name ..."
		if ! helm --namespace="$namespace" install --name="$helm_release_name" $helm_set_arg "$helm_dir"
		then
			echo "helm install failed." >&2
			
			# Delete release only if is a new release
			helm delete "$helm_release_name" --purge
			return $HELM_INSTALL_OR_UPGRADE_INST_FAILED
		fi		
	fi
}

# helm-deploy-validation
# Usage: helm-deploy-validation namespace helm_release_name

HELM_DEPLOY_VALIDATION_MISS_NAMESPACE=77
HELM_DEPLOY_VALIDATION_MISS_REL_NAME=78
HELM_DEPLOY_VALIDATION_REVISION_NOT_FOUND=79
HELM_DEPLOY_VALIDATION_POD_CREATION_FAIL=80
HELM_DEPLOY_VALIDATION_POD_DIDNT_RUN=81

# Param namespace
# Param helm_release_name
function helm-deploy-validation
{
	local namespace=$1
	local helm_release_name=$2

	if [ -z "$namespace" ]
	then
		echo "Missing namespace." >&2
		return $HELM_DEPLOY_VALIDATION_MISS_NAMESPACE
	fi

	if [ -z "$helm_release_name" ]
	then
		echo "Missing helm_release_name." >&2
		return $HELM_DEPLOY_VALIDATION_MISS_REL_NAME
	fi

	local release_revision=$(helm get "$helm_release_name" | head -1 | grep ^REVISION: | awk '{ print $2 }')

	if ! echo $release_revision | egrep '^[1-9][0-9]*$' > /dev/null 2>&1
	then
		echo "Could not get helm release revision." >&2
		return $HELM_DEPLOY_VALIDATION_REVISION_NOT_FOUND
	fi	

	echo -n "Checking POD creation... "
	local pooling_attemps=0
	local kubectl_get_pod_cmd="kubectl -n $namespace get pod -l release=$helm_release_name,revision=$release_revision -ojson"

	while : 
		[ "$($kubectl_get_pod_cmd | jq -M '.items[0]')" = "null" ]
	do
		# POD creation should not exceeds 30 seconds.
		# If it exceeds, must be something wrong on Kubernetes scheduling
		if [ "$pooling_attemps" -gt 30 ]
		then
			echo "FAILED"
			echo "Could not validate POD creation." >&2
			return $HELM_DEPLOY_VALIDATION_POD_CREATION_FAIL
		fi

		echo -n '.'
		sleep 1
		pooling_attemps=$((pooling_attemps+1))
	done

	echo "OK"

	# check POD status

	echo "Checking POD status."

	pooling_attemps=0
	local max_pooling_attemps=180
	local deploy_validation_completed=false
	local deploy_sucess=false
	local pod_status_pending=false	

	while : 
		[ "$pooling_attemps" -lt "$max_pooling_attemps" ] && ! $deploy_validation_completed
	do
		local pooling_attemps_step=""
		local prev_pooling_attemps_step=""
		local pod_ready=""
		local reason=""
		local pod_status=$($kubectl_get_pod_cmd | jq -M '.items[0]?.status')
		local container_status=$(echo $pod_status | jq -M '.containerStatuses[0]?.state')

		if [ "$container_status" = "null" ] && [ "$(echo $pod_status | jq -Mr '.phase')" = "Pending" ]
		then
			pod_status_pending=true
			pooling_attemps_step="PENDING"
			echo "Pending..."
		else
			pod_status_pending=false

			if [ "$container_status" = "null" ]
			then
				pooling_attemps_step="INITIAL"
				echo "Waiting..."
			elif [ "$(echo $container_status | jq -M '.waiting')" != "null" ]
			then
				pooling_attemps_step="CONTAINER_CREATING"

				reason=$(echo $container_status | jq -Mr '.waiting.reason')
				
				echo "Waiting: $reason"

				if [ "$reason" = "CrashLoopBackOff" ]
				then
					deploy_validation_completed=true
					deploy_sucess=false
				fi

			elif [ "$(echo $container_status | jq -M '.running')" != "null" ] 
			then
				#echo $container_status | jq -M '.running'
				pooling_attemps_step="CHECK_READYNESS"
				pod_ready=$(echo $pod_status | jq -Mr '.conditions[] | select(.type == "Ready") | .status')

				if [ "$pod_ready" = "True" ]
				then
					deploy_validation_completed=true
					deploy_sucess=true
				else
					echo "Container running... Looking for ready status [$pod_ready]"
				fi

			elif [ "$(echo $container_status | jq -M '.terminated')" != "null" ] 
			then
				reason=$(echo $container_status | jq -Mr '.terminated.reason')
				echo "Terminated: $reason" # reason: Error

				deploy_validation_completed=true
				deploy_sucess=false
			else
				echo "## STATUS NOT MAPPED ##################################################"
				echo $container_status
			fi
		fi

		if [ "$prev_pooling_attemps_step" != "$pooling_attemps_step" ]
		then
			pooling_attemps=0
		fi

		prev_pooling_attemps_step=$pooling_attemps_step

		sleep 1
		pooling_attemps=$((pooling_attemps+1))
	done

	if ! $deploy_sucess
	then
		if $pod_status_pending
		then
			echo -e "\e[31mError while trying to start $helm_release_name."
			echo "POD pending: Kubernetes low on resources."
		elif ! $deploy_validation_completed
		then
			echo -e "\e[31mCould not validate deployment, the POD is taking a long time to get ready, should be something wrong on Kubernetes Cluster."
			echo "## POD details ##################################################"
			kubectl -n $namespace describe pod -l release=$helm_release_name,revision=$release_revision
		else
			# TODO: improve log
			echo -e "\e[31mError while trying to start $helm_release_name"
			if ! kubectl -n $namespace logs -l release=$helm_release_name,revision=$release_revision -p
			then
				echo "Could not get container logs."
			fi
		fi

		helm delete $helm_release_name --purge
		return $HELM_DEPLOY_VALIDATION_POD_DIDNT_RUN
	fi

	echo
	echo -e "\e[32m$helm_release_name successfuly deployed."
}
